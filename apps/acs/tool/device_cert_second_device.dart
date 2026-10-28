/// O SEGUNDO aparelho do ACS no e2e do certificado por aparelho (#94).
///
/// Roda na VM (como `live_check.dart`), com o código de rede do app: entra
/// como o MESMO ACS da fixture, mas com um id de instalação próprio
/// (`MemoryDeviceIdStore`, aleatório) — para o servidor, é outro aparelho —,
/// gera o par EC e o CSR, pede o certificado (`devices.issueCertificate`),
/// conecta ao broker com o client id do aparelho e fica assinando o tópico da
/// microárea. A chave privada fica SÓ em memória: nada é gravado em disco nem
/// impresso.
///
/// Só roda por `scripts/qa/acs_device_cert_e2e.sh`, que lê estas linhas
/// marcadoras na saída, em tempo real:
///   E2E_DEV2_CONECTADO device=<id> serial=<hex>  → emitido e conectado
///   E2E_DEV2_ALERTA_RECEBIDO <alertId>           → um alerta pelo broker
///   E2E_DEV2_DERRUBADO at_ms=<epoch ms>          → a sessão caiu (a limpeza
///                                                   remota a derrubou)
///   E2E_DEV2_RECONECTOU                          → FALHA: voltou sozinho
///   E2E_DEV2_RECONEXAO_RECUSADA erro=<tipo>      → uma conexão nova com o
///                                                   mesmo certificado é recusada
///   E2E_DEV2_RECONEXAO_ACEITA                    → FALHA: o broker aceitou
///
/// Depois da derrubada, o cliente segue como o do app (`autoReconnect`) por
/// [_janelaReconexao]: se ele voltar sozinho, o certificado revogado ainda
/// passa e a ferramenta falha. Só então abre uma conexão nova, que tem de ser
/// recusada pela CRL recarregada.
///
///   E2E_FIXTURES_FILE=.e2e/fixtures.json dart run tool/device_cert_second_device.dart \
///     --rpc-ca <ca do Traefik> --broker-ca <ca do broker>
///
/// A credencial vem do manifesto (`E2E_FIXTURES_FILE`, nunca do argv). O host
/// é `https://localhost/` e o broker `localhost:8883`, os da stack de e2e.
///
/// PRIVACIDADE: só fixtures sintéticas. Senha, token e chave nunca saem.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/security/session_token_store.dart';
import 'package:sinalacs_acs/core/services/device_csr.dart';
import 'package:sinalacs_acs/core/services/mqtt_secure_client.dart';

const _janelaReconexao = Duration(seconds: 12);
const _teto = Duration(minutes: 8);

String _arg(List<String> args, String name) {
  final i = args.indexOf('--$name');
  if (i < 0 || i + 1 >= args.length) {
    stderr.writeln('erro: falta --$name');
    exit(2);
  }
  return args[i + 1];
}

void _marca(String linha) => stdout.writeln(linha);

Future<void> main(List<String> args) async {
  final rpcCa = File(_arg(args, 'rpc-ca')).readAsBytesSync();
  final brokerCa = File(_arg(args, 'broker-ca')).readAsBytesSync();
  final manifesto = Platform.environment['E2E_FIXTURES_FILE'];
  if (manifesto == null || manifesto.isEmpty) {
    stderr.writeln('erro: defina E2E_FIXTURES_FILE (o manifesto das fixtures)');
    exit(2);
  }
  final acs = (jsonDecode(File(manifesto).readAsStringSync()) as Map)['acs'] as Map;

  // Falha alta, nunca espera para sempre: o script derruba a ferramenta no
  // cleanup, mas um laço esquecido aqui não pode prender a execução.
  Timer(_teto, () {
    stderr.writeln('erro: a ferramenta passou de ${_teto.inMinutes} min sem terminar');
    exit(3);
  });

  // Id próprio, aleatório: é o que faz deste o SEGUNDO aparelho do ACS.
  final ids = MemoryDeviceIdStore();
  final backend = BackendClient(host: 'https://localhost/', trustedCaBytes: rpcCa, deviceIds: ids);
  MqttSecureClient? mqtt;
  try {
    final sessao = await backend.login(matricula: acs['matricula'] as String, senha: acs['password'] as String);
    final deviceId = await ids.readOrCreate();
    final microAreaId = sessao.microAreaId!;

    // Par gerado aqui, só em memória; o servidor assina o CSR (CN = microárea).
    final par = generateDeviceKeyPair();
    final emitido = await backend.issueDeviceCertificate(buildDeviceCsrPem(keyPair: par, microAreaId: microAreaId));

    SecureMqttConfig config() => SecureMqttConfig(
      brokerHost: 'localhost',
      port: 8883,
      clientId: deviceClientId(acsId: sessao.userId, deviceId: deviceId),
      topic: alertTopicFor(microAreaId),
      caCertificate: brokerCa,
      clientCertificate: utf8.encode(emitido.certificatePem),
      clientPrivateKey: utf8.encode(par.privateKeyPem),
    );

    final vistos = <String>{};
    var conectado = false;
    final derrubado = Completer<void>();
    var reconectou = false;

    final cliente = mqtt = MqttSecureClient(config: config());
    await runZonedGuarded(
      () => cliente.connect(
        onAlert: (alerta) {
          if (vistos.add(alerta.alertId)) _marca('E2E_DEV2_ALERTA_RECEBIDO ${alerta.alertId}');
        },
        onConnectionChanged: (ok) {
          if (!conectado) return;
          if (!ok && !derrubado.isCompleted) {
            _marca('E2E_DEV2_DERRUBADO at_ms=${DateTime.now().millisecondsSinceEpoch}');
            derrubado.complete();
          } else if (ok && derrubado.isCompleted && !reconectou) {
            reconectou = true;
            _marca('E2E_DEV2_RECONECTOU');
          }
        },
      ),
      // As tentativas da reconexão automática contra um certificado revogado
      // falham fora do `await`: só o tipo vai para o log.
      (erro, _) => stderr.writeln('  [dev2] reconexão automática falhou (${erro.runtimeType})'),
    );
    conectado = true;
    _marca('E2E_DEV2_CONECTADO device=$deviceId serial=${emitido.serial}');

    await derrubado.future;
    await Future<void>.delayed(_janelaReconexao);
    cliente.disconnect();
    mqtt = null;
    if (reconectou) {
      stderr.writeln('erro: o aparelho revogado voltou ao broker sozinho');
      exitCode = 1;
      return;
    }

    // Conexão nova, mesmo certificado: a CRL recarregada tem de recusá-la no
    // handshake. A recusa do TLS chega ASSÍNCRONA (o `connect` do mqtt_client
    // nem sempre completa com erro): o primeiro erro, de onde vier, decide.
    final novo = MqttSecureClient(config: config());
    final desfecho = Completer<Object?>();
    runZonedGuarded(
      () => novo
          .connect(onAlert: (_) {})
          .then(
            (_) => desfecho.isCompleted ? null : desfecho.complete(null),
            onError: (Object erro) => desfecho.isCompleted ? null : desfecho.complete(erro),
          ),
      (erro, _) => desfecho.isCompleted ? null : desfecho.complete(erro),
    );
    final erro = await desfecho.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () => TimeoutException('sem resposta'),
    );
    novo.disconnect();
    if (erro == null) {
      _marca('E2E_DEV2_RECONEXAO_ACEITA');
      exitCode = 1;
    } else if (erro is MqttTlsRefused || erro is TlsException) {
      // O broker recusou o certificado no handshake: o `MqttSecureClient` o
      // entrega como `MqttTlsRefused` (o `TlsException` cru fica por defesa).
      _marca('E2E_DEV2_RECONEXAO_RECUSADA erro=${erro.runtimeType}');
    } else {
      stderr.writeln('erro: a reconexão falhou sem recusa do TLS (${erro.runtimeType})');
      exitCode = 1;
    }
  } on BackendFailure catch (falha) {
    stderr.writeln('erro: ${falha.message}');
    exitCode = 1;
  } catch (erro) {
    stderr.writeln('erro: ${erro.runtimeType}');
    exitCode = 1;
  } finally {
    mqtt?.disconnect();
    backend.close();
  }
  exit(exitCode);
}
