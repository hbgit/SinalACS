import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/services/mqtt_secure_client.dart';

/// Recusa TLS na reconexão automática (#94, achado do e2e da Task 7).
///
/// O backend revoga o certificado do aparelho, o broker derruba a sessão e
/// passa a recusar o handshake (`certificate verify failed`). Com
/// `autoReconnect`, o `mqtt_client` 10.5.1 tenta de novo sozinho e a
/// `TlsException` escapava como erro assíncrono não tratado. Broker falso em
/// TLS real (`dart:io`), com mTLS: a primeira conexão passa, as seguintes são
/// recusadas porque o "broker" deixa de confiar na CA do cliente. Certificados
/// gerados pelo `openssl` numa pasta temporária, só para este teste.
void main() {
  final temOpenssl = () {
    try {
      return Process.runSync('openssl', ['version']).exitCode == 0;
    } on ProcessException {
      return false;
    }
  }();

  test(
    'recusa TLS na reconexão automática vira queda tlsRefused, sem erro não tratado, e o cliente não tenta de novo',
    () async {
      final broker = await _BrokerTls.start(aceitarAte: 1);
      final client = broker.client();
      addTearDown(client.disconnect);

      final quedas = <MqttDropReason>[];
      final caiu = Completer<void>();
      await client.connect(
        onAlert: (_) {},
        onDrop: (motivo) {
          quedas.add(motivo);
          if (motivo == MqttDropReason.tlsRefused && !caiu.isCompleted) caiu.complete();
        },
      );
      expect(client.isConnected, isTrue);

      broker.derrubarSessoes();
      await broker.segundaTentativa.future.timeout(const Duration(seconds: 10), onTimeout: () {
        fail('o cliente nunca tentou reconectar');
      });
      // A primeira tentativa pode trazer só o erro do socket antigo (que uma
      // queda comum também produz); a recusa se decide quando a SEGUNDA
      // tentativa com erro de E/S falha — 2 ciclos de 3×5 s do mqtt_client.
      await caiu.future.timeout(const Duration(seconds: 60), onTimeout: () {
        fail('a recusa TLS na reconexão nunca virou queda tlsRefused: $quedas');
      });

      // Sem insistir para sempre. A queda é decidida no `onAutoReconnect`,
      // que o mqtt_client 10.5.1 chama ANTES do ciclo de tentativas que ele já
      // ia fazer; esse ciclo (no máximo `maxConnectionAttempts` = 3, de 5 s
      // cada) não tem como ser cortado de fora e ainda sai, falhando calado.
      // Depois dele, nada: o barramento de eventos foi destruído e o laço
      // morre — antes, seguia para sempre.
      final naQueda = broker.tentativas;
      await Future<void>.delayed(const Duration(seconds: 17));
      final depois = broker.tentativas;
      expect(depois - naQueda, lessThanOrEqualTo(3), reason: 'no máximo o ciclo já em curso');
      await Future<void>.delayed(const Duration(seconds: 6));
      expect(broker.tentativas, depois, reason: 'o cliente não pode seguir tentando com o certificado recusado');
      expect(client.isConnected, isFalse);
      expect(quedas.where((q) => q == MqttDropReason.tlsRefused), hasLength(1));
    },
    skip: temOpenssl ? false : 'openssl ausente',
    timeout: const Timeout(Duration(seconds: 120)),
  );

  // A garantia da #80: uma queda comum com reconexão ACEITA nunca vira
  // `onDrop` (nem descarte do certificado nem consulta de wipe). Repetida
  // porque a corrida de escrita no socket derrubado depende de tempo.
  for (var rodada = 1; rodada <= 5; rodada++) {
    test(
      'queda TLS comum com reconexão aceita não dispara onDrop e o autoReconnect volta (rodada $rodada)',
      () async {
        final broker = await _BrokerTls.start(aceitarAte: 1000);
        final client = broker.client();
        addTearDown(client.disconnect);

        final quedas = <MqttDropReason>[];
        final estados = <bool>[];
        final caiu = Completer<void>();
        final voltou = Completer<void>();
        await client.connect(
          onAlert: (_) {},
          onDrop: quedas.add,
          onConnectionChanged: (conectado) {
            estados.add(conectado);
            if (!conectado && !caiu.isCompleted) caiu.complete();
            if (conectado && caiu.isCompleted && !voltou.isCompleted) voltou.complete();
          },
        );
        expect(client.isConnected, isTrue);

        broker.derrubarSessoes();
        await caiu.future.timeout(const Duration(seconds: 10), onTimeout: () {
          fail('a queda nunca virou onConnectionChanged(false): $estados');
        });
        await voltou.future.timeout(const Duration(seconds: 15), onTimeout: () {
          fail('o autoReconnect não reconectou: $estados, quedas $quedas');
        });
        // Folga para um erro tardio do socket derrubado aparecer.
        await Future<void>.delayed(const Duration(seconds: 1));

        expect(quedas, isEmpty, reason: 'queda comum não é recusa do certificado');
        expect(client.isConnected, isTrue);
        expect(estados.last, isTrue);
      },
      skip: temOpenssl ? false : 'openssl ausente',
      timeout: const Timeout(Duration(seconds: 60)),
    );
  }

  test(
    'recusa TLS no primeiro connect lança MqttTlsRefused, sem erro não tratado',
    () async {
      final broker = await _BrokerTls.start(aceitarAte: 0);
      final client = broker.client();
      addTearDown(client.disconnect);
      final quedas = <MqttDropReason>[];

      await expectLater(
        client.connect(onAlert: (_) {}, onDrop: quedas.add),
        throwsA(isA<MqttTlsRefused>()),
      );
      expect(client.isConnected, isFalse);

      final depois = broker.tentativas;
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(broker.tentativas, depois, reason: 'falhou o primeiro connect: ninguém tenta de novo sozinho');
      expect(quedas, isEmpty, reason: 'a recusa no primeiro connect é a exceção, não uma queda');
    },
    skip: temOpenssl ? false : 'openssl ausente',
    timeout: const Timeout(Duration(seconds: 60)),
  );
}

/// Broker MQTT falso em TLS real com mTLS: as primeiras [aceitarAte]
/// conexões confiam na CA que assinou o cliente; as seguintes, numa CA alheia
/// — o handshake do cliente é recusado, como o do certificado revogado.
class _BrokerTls {
  _BrokerTls._(this._pki, this._server);

  final _Pki _pki;
  final ServerSocket _server;
  final List<SecureSocket> _sessoes = <SecureSocket>[];
  final Completer<void> segundaTentativa = Completer<void>();
  int tentativas = 0;

  static Future<_BrokerTls> start({required int aceitarAte}) async {
    final pki = _Pki.create();
    addTearDown(pki.dispose);
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final broker = _BrokerTls._(pki, server);
    final aceita = broker._contexto('ca.crt');
    final recusa = broker._contexto('other_ca.crt');
    server.listen((raw) {
      broker.tentativas++;
      if (broker.tentativas >= 2 && !broker.segundaTentativa.isCompleted) broker.segundaTentativa.complete();
      final contexto = broker.tentativas <= aceitarAte ? aceita : recusa;
      SecureSocket.secureServer(raw, contexto, requireClientCertificate: true).then((socket) {
        broker._sessoes.add(socket);
        socket.listen((bytes) {
          // CONNECT (0x10) → CONNACK aceito; SUBSCRIBE (0x82) → SUBACK QoS 1.
          if (bytes.isNotEmpty && bytes.first == 0x10) {
            socket.add([0x20, 0x02, 0x00, 0x00]);
          } else if (bytes.isNotEmpty && bytes.first == 0x82 && bytes.length >= 4) {
            socket.add([0x90, 0x03, bytes[2], bytes[3], 0x01]);
          }
        }, onError: (_) {});
      }, onError: (_) {
        // O lado do "broker" recusou o certificado do cliente: esperado.
      });
    });
    return broker;
  }

  SecurityContext _contexto(String caDoCliente) => SecurityContext(withTrustedRoots: false)
    ..useCertificateChain(_pki.path('server.crt'))
    ..usePrivateKey(_pki.path('server.key'))
    ..setTrustedCertificates(_pki.path(caDoCliente));

  /// O broker derruba a sessão (certificado revogado) e passa a recusar.
  void derrubarSessoes() {
    for (final s in _sessoes) {
      s.destroy();
    }
  }

  MqttSecureClient client() => MqttSecureClient(
        config: SecureMqttConfig(
          brokerHost: '127.0.0.1',
          port: _server.port,
          clientId: 'acs-recusa-tls-teste',
          topic: 'sinalacs/v1/microareas/area-teste/alerts',
          caCertificate: File(_pki.path('ca.crt')).readAsBytesSync(),
          clientCertificate: File(_pki.path('client.crt')).readAsBytesSync(),
          clientPrivateKey: File(_pki.path('client.key')).readAsBytesSync(),
        ),
      );
}

/// CA, servidor (SAN 127.0.0.1) e cliente assinados pela CA; mais uma CA
/// alheia, a que o "broker" passa a exigir quando recusa.
class _Pki {
  _Pki._(this.dir);

  final Directory dir;

  String path(String nome) => '${dir.path}/$nome';

  static _Pki create() {
    final pki = _Pki._(Directory.systemTemp.createTempSync('mqtt_tls_recusa_'));
    void run(List<String> args) {
      final r = Process.runSync('openssl', args, workingDirectory: pki.dir.path);
      if (r.exitCode != 0) throw StateError('openssl ${args.first}: ${r.stderr}');
    }

    for (final ca in ['ca', 'other_ca']) {
      run(['req', '-x509', '-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:prime256v1', '-nodes', '-days', '1',
        '-subj', '/CN=$ca-teste', '-keyout', '$ca.key', '-out', '$ca.crt']);
    }
    File(pki.path('server.ext')).writeAsStringSync('subjectAltName=IP:127.0.0.1\n');
    for (final (nome, ext) in [('server', 'server.ext'), ('client', null)]) {
      run(['req', '-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:prime256v1', '-nodes',
        '-subj', '/CN=$nome-teste', '-keyout', '$nome.key', '-out', '$nome.csr']);
      run(['x509', '-req', '-in', '$nome.csr', '-CA', 'ca.crt', '-CAkey', 'ca.key', '-CAcreateserial',
        '-days', '1', '-out', '$nome.crt', if (ext != null) ...['-extfile', ext]]);
    }
    return pki;
  }

  void dispose() => dir.deleteSync(recursive: true);
}
