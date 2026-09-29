/// Verificação rápida da camada de rede do app contra a stack local.
///
/// Roda na VM, sem emulador, e usa o MESMO `BackendClient` que a UI usa — é o
/// que separa "o backend está de pé" (video/rpc_demo) de "o app fala com ele".
///
/// Pré-requisito: `docker compose up` com o database-seed concluído e
/// `./scripts/dev/sync_dev_ca.sh` (a CA do RPC é regerada, não versionada).
///
///   cd apps/patient
///   dart run tool/live_check.dart
///   dart run tool/live_check.dart --host https://10.0.2.2/
///
/// O default é `https://localhost/` — a 8080 em texto claro não é mais
/// publicada e quem termina TLS é o Traefik (RNF04/L-08). O `--host` explícito
/// passa pela mesma regra: um endereço sem https para aqui com exit 2, antes de
/// qualquer chamada. Diferente do app, esta ferramenta roda na máquina (não num
/// APK), então lê a CA de desenvolvimento do RPC direto do runtime local, e não
/// de um asset Flutter.
///
/// Este arquivo importa a lib do app, mas **só** o que a VM do Dart consegue
/// compilar: `core/privacy/location_hash.dart` puxa `geolocator` → `flutter` →
/// `dart:ui`, e o `dart run` morria na compilação antes de qualquer chamada de
/// rede (ver o comentário do hash, abaixo). Manter esta leg compilável é o que
/// permite `scripts/qa/e2e.sh` chegar até a leg do ACS: o script é `set -e`.
library;

import 'dart:io';

import 'package:sinalacs_patient/core/network/backend_client.dart';

/// Caminho da CA de desenvolvimento do RPC (a que assina o certificado do
/// Traefik em 443), dentro do repositório.
///
/// Sai da posição DESTE arquivo, e não do diretório de onde o comando foi
/// executado (`Directory.fromUri(Platform.script)`, o mesmo idioma de
/// `scripts/qa/measure_latency.dart`): a CA é encontrada tanto rodando de
/// `apps/patient` quanto da raiz do repositório (medido). Um caminho relativo ao
/// CWD erraria por um `../` conforme quem chamasse, e o handshake falharia — que
/// é o desfecho que esta leitura existe para não produzir.
File _devRpcCaFile() {
  // apps/patient/tool/live_check.dart → raiz do repositório.
  final repoRoot = Directory.fromUri(Platform.script).parent.parent.parent.parent;
  return File('${repoRoot.path}/infra/docker/traefik/runtime/certs/ca.crt');
}

/// Lê a CA de desenvolvimento do RPC do runtime local.
///
/// `null` quando o arquivo não existe; quem chama diz o que fazer a respeito.
Future<List<int>?> _devRpcCaBytes() async {
  final file = _devRpcCaFile();
  return await file.exists() ? file.readAsBytes() : null;
}

Future<void> main(List<String> args) async {
  // O `--host` explícito é validado AQUI. O `BackendClient` isenta host
  // explícito de propósito — é o caminho dos testes herméticos, que apontam
  // para servidores fake em `http://127.0.0.1:<porta efêmera>/`. Esta
  // ferramenta não tem servidor fake: quem digita `--host http://…` quer falar
  // com a stack, e falava em texto claro. Medido antes desta guarda:
  // `--host http://localhost/` → exit 1 com "Não foi possível falar com o
  // servidor (404)" — falhava, e não dizia https.
  final hostIndex = args.indexOf('--host');
  final hostArg = hostIndex >= 0 && hostIndex + 1 < args.length
      ? args[hostIndex + 1]
      : 'https://localhost/';
  final String host;
  try {
    host = requireSecureHost(hostArg);
  } on BackendFailure catch (failure) {
    stderr.writeln('erro: ${failure.message}');
    exitCode = 2;
    return;
  }

  // A CA do RPC é lida ANTES de construir o cliente, e a ausência dela PARA a
  // execução com o motivo real. Se ela faltasse e o cliente fosse construído
  // assim mesmo, ele cairia no armazenamento do sistema, o handshake falharia,
  // e a saída diria "o backend não respondeu" — exatamente a confusão que este
  // plano existe para não produzir.
  final rpcCa = await _devRpcCaBytes();
  if (rpcCa == null) {
    stderr.writeln('erro: a CA do RPC não existe em ${_devRpcCaFile().path}.');
    stderr.writeln('Suba a stack (docker compose up) e rode ./scripts/dev/sync_dev_ca.sh.');
    exitCode = 2;
    return;
  }

  // O cliente é construído sob a MESMA guarda da CA acima: uma CA **presente
  // mas corrompida** lança `TlsException` em `setTrustedCertificatesBytes`, e
  // sem guarda nenhuma isso subia como exceção não tratada (exit 255) — nunca
  // chegava ao handshake, e nada na saída dizia qual arquivo estava errado.
  // Guarda própria, e não o `try` do ciclo, porque o `catch` de lá imprime
  // `falhou: $error`, que também não nomeia o caminho.
  final BackendClient backend;
  try {
    backend = BackendClient(host: host, trustedCaBytes: rpcCa);
  } catch (error) {
    stderr.writeln('erro: a CA do RPC em ${_devRpcCaFile().path} não pôde ser usada: $error');
    stderr.writeln('Rode ./scripts/dev/sync_dev_ca.sh para copiá-la de novo.');
    exitCode = 2;
    return;
  }
  stdout.writeln('paciente → $host');

  try {
    final health = await backend.health();
    stdout.writeln('  health ............. ${health.status} '
        '(db=${health.dbConnected} mqtt=${health.mqttConnected})');

    final session = await backend.developmentLogin(role: 'patient');
    // O token nunca é impresso inteiro.
    stdout.writeln('  login .............. papel=${session.role} '
        'microárea=${session.microAreaId} expira=${session.expiresAt.toIso8601String()}');

    final red = await backend.evaluateTriage(
      chestPain: true,
      difficultyBreathing: false,
      fever: false,
      persistentVomiting: false,
      bleeding: false,
      severeWeakness: false,
    );
    final green = await backend.evaluateTriage(
      chestPain: false,
      difficultyBreathing: false,
      fever: false,
      persistentVomiting: false,
      bleeding: false,
      severeWeakness: false,
    );
    stdout.writeln('  triagem ............ dor no peito=${red.name}  '
        'sem sintomas=${green.name}');
    if (red.name != 'red' || green.name != 'green') {
      stderr.writeln('  ERRO: motor de triagem do servidor respondeu fora do esperado.');
      exitCode = 1;
    }

    final key = 'live-check-${DateTime.now().millisecondsSinceEpoch}';
    // Cópia do `unknownLocationHash` do app (12 caracteres), e não o símbolo:
    // importar `core/privacy/location_hash.dart` arrasta `geolocator` →
    // `flutter` → `dart:ui`, que não existe na VM do Dart — era por aí que esta
    // leg morria, na COMPILAÇÃO e não no TLS. Para o backend o valor é opaco
    // (`red_alert_service.dart` só exige que não seja vazio), então a cópia não
    // precisa acompanhar a constante; "sem local" é o que esta ferramenta pode
    // afirmar, já que roda numa máquina sem GPS — e é o mesmo valor que a leg
    // do ACS envia.
    const hash = 'sem-local-00';
    final first = await backend.createRedAlert(
      idempotencyKey: key,
      locationHash: hash,
    );
    final again = await backend.createRedAlert(
      idempotencyKey: key,
      locationHash: hash,
    );
    stdout.writeln('  alerta vermelho .... ${first.alertId} '
        '(publicado=${first.published})');
    if (first.alertId == again.alertId) {
      stdout.writeln('  idempotência ....... mesmo alertId no reenvio');
    } else {
      stderr.writeln('  ERRO: reenvio com a mesma chave criou outro alerta.');
      exitCode = 1;
    }

    stdout.writeln(exitCode == 0 ? '\nOK — o app fala com o backend.' : '\nFALHOU.');
  } on BackendFailure catch (failure) {
    stderr.writeln('  falhou: ${failure.message}');
    exitCode = 1;
  } finally {
    backend.close();
  }
}
