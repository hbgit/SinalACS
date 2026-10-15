@Tags(['resiliencia'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mqtt_client/mqtt_client.dart' show MqttConnectionHandlerBase;
import 'package:sinalacs_server/src/application/alerts/alert_outbox_dispatcher.dart';
import 'package:sinalacs_server/src/application/alerts/red_alert_service.dart';
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/domain/entities/alert_delivery.dart';
import 'package:sinalacs_server/src/infrastructure/mqtt/mqtt_alert_dispatcher.dart';
import 'package:test/test.dart';

import '../support/fake_mqtt_broker.dart';

AppConfig _config(int port) => AppConfig(
      mqttBroker: '127.0.0.1:$port',
      jwtSecret: 'test-secret',
      auditChainSecret: 'test-audit-chain-secret',
      healthDataEncryptionKey: AppConfig.developmentHealthDataEncryptionKey,
      cpfHashPepper: AppConfig.developmentCpfHashPepper,
      smsGateway: 'log',
      mqttUsername: null,
      mqttPassword: null,
      mqttUseTls: false,
      mqttCaCertificatePath: null,
      appEnv: 'development',
      enableDevLogin: true,
    );

AlertDelivery _delivery() => AlertDelivery(
      alertId: '00000000-0000-4000-8000-0000000000aa',
      patientId: '00000000-0000-4000-8000-000000000001',
      microAreaId: '00000000-0000-4000-8000-000000000003',
      riskLevel: 'red',
      locationHash: 'sem-local-00',
      triggeredAt: DateTime.utc(2026, 9, 16, 10),
    );

/// Outbox em memória para medir uma rodada de `drainOnce` contra o dispatcher
/// real: [n] entradas pendentes, publicadas e falhas registradas.
class _OutboxEmMemoria implements AlertOutbox {
  _OutboxEmMemoria(int n)
      : _pendentes = [
          for (var i = 0; i < n; i++)
            PendingDelivery(entryId: 'e$i', delivery: _delivery(), attempts: 1),
        ];

  final List<PendingDelivery> _pendentes;
  final publicadas = <String>[];
  final falhas = <String>[];

  @override
  Future<void> enqueue(AlertDelivery alert) async {}

  @override
  Future<List<PendingDelivery>> claimDue({int limit = 32}) async =>
      _pendentes.take(limit).toList();

  @override
  Future<void> markPublished(String entryId) async => publicadas.add(entryId);

  @override
  Future<void> markFailed(String entryId, String error, DateTime next) async =>
      falhas.add(entryId);
}

/// Polling a cada 25 ms até [cond] valer; falha com `timeout` depois de [timeout].
Future<void> _until(
  bool Function() cond, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final limite = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(limite)) fail('timeout');
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

/// Broker falso + dispatcher com `onFatal` e `log` gravados, já com o
/// encerramento registrado antes de qualquer `await` do teste.
class _Ambiente {
  _Ambiente(this.broker, this.d, this.fatais, this.logs);

  final FakeMqttBroker broker;
  final MqttAlertDispatcher d;
  final List<Object> fatais;
  final StringBuffer logs;
}

Future<_Ambiente> _ambiente({
  Duration backoff = const Duration(milliseconds: 100),
  bool esperaFatal = false,
  Duration publishAckTimeout = const Duration(seconds: 10),
  int keepAliveSeconds = 30,
  int pingResponseTimeoutSeconds = 10,
}) async {
  final broker = await FakeMqttBroker.start();
  final fatais = <Object>[];
  final logs = StringBuffer();
  final d = MqttAlertDispatcher(
    config: _config(broker.port),
    initialBackoff: backoff,
    onFatal: fatais.add,
    log: logs.writeln,
    publishAckTimeout: publishAckTimeout,
    keepAliveSeconds: keepAliveSeconds,
    pingResponseTimeoutSeconds: pingResponseTimeoutSeconds,
  );
  addTearDown(() async {
    await d.close();
    await broker.close();
    if (!esperaFatal) {
      expect(fatais, isEmpty, reason: 'onFatal não devia ser chamado');
    }
  });
  return _Ambiente(broker, d, fatais, logs);
}

/// Roda [body] numa zona guardada. Erro que escape para essa zona falha o
/// teste na hora (em vez de pendurar o `await` de um `runZonedGuarded`).
Future<void> _guardado(Future<void> Function() body) {
  final fim = Completer<void>();
  runZonedGuarded(() async {
    await body();
    if (!fim.isCompleted) fim.complete();
  }, (e, s) {
    if (!fim.isCompleted) fim.completeError(e, s);
  });
  return fim.future;
}

const _brokenPipe =
    SocketException('Broken pipe', osError: OSError('Broken pipe', 32));

/// Sentinelas de VAZ-01: nada disto pode aparecer num log do dispatcher.
const _proibidos = [
  'sentinela-vaz01-local',
  '0000000000aa',
  'localhost',
  '127.0.0.1',
  'sinalacs-backend-',
  'Broken pipe',
  'StackTrace',
  '#0 ',
];

void _semVazamento(String capturado) {
  for (final proibido in _proibidos) {
    expect(capturado, isNot(contains(proibido)), reason: 'vazou "$proibido"');
  }
}

/// Erro que carrega, de propósito, tudo o que um log bruto vazaria: mensagem
/// com sentinelas, endereço, porta e o texto do errno.
SocketException _erroCarregado() => SocketException(
      'Broken pipe sentinela-vaz01-local 0000000000aa localhost',
      osError: const OSError('Broken pipe', 32),
      address: InternetAddress('127.0.0.1'),
      port: 8883,
    );

/// Handler de conexão cujo uso sempre lança [_erroCarregado].
class _HandlerQueLanca implements MqttConnectionHandlerBase {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw _erroCarregado();
}

/// `stderr` do processo de teste capturado (a parte que o dispatcher escreve
/// quando não recebe `log`).
class _StderrCapturado implements Stdout {
  final buffer = StringBuffer();

  @override
  void writeln([Object? object = '']) => buffer.writeln(object);

  @override
  void write(Object? object) => buffer.write(object);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Sobe a sonda de processo contra [brokerAddr] e devolve o stderr acumulado.
Future<({Process probe, StringBuffer stderrText})> _sonda(
  String brokerAddr,
) async {
  final probe = await Process.start(
    'dart',
    ['run', 'test/support/mqtt_dispatcher_probe.dart'],
    environment: {'MQTT_BROKER': brokerAddr},
  );
  final stderrText = StringBuffer();
  probe.stderr.transform(utf8.decoder).listen(stderrText.write);
  await probe.stdout
      .transform(utf8.decoder)
      .firstWhere((s) => s.contains('PRONTO'));
  return (probe: probe, stderrText: stderrText);
}

void main() {
  group('MqttAlertDispatcher resiliência', () {
    test('conecta ao broker falso', () async {
      final a = await _ambiente();

      await a.d.connect();

      expect(a.d.isConnected, isTrue);
      expect(a.broker.connectCount, 1);
    });

    test(
      'processo congelado e conexão derrubada: sobrevive e reconecta',
      () async {
        final broker = await FakeMqttBroker.start();
        final probe = await Process.start(
          'dart',
          ['run', 'test/support/mqtt_dispatcher_probe.dart'],
          environment: {'MQTT_BROKER': 'localhost:${broker.port}'},
        );
        final stderrText = StringBuffer();
        probe.stderr.transform(utf8.decoder).listen(stderrText.write);
        await probe.stdout
            .transform(utf8.decoder)
            .firstWhere((s) => s.contains('PRONTO'));
        expect(broker.connectCount, 1);

        var saiu = false;
        unawaited(probe.exitCode.then((_) => saiu = true));

        probe.kill(ProcessSignal.sigstop);
        broker.dropClients(); // o broker "expira" a conexão ociosa
        // Mais que o keepAlivePeriod (30 s).
        await Future<void>.delayed(const Duration(seconds: 35));
        probe.kill(ProcessSignal.sigcont);

        await Future<void>.delayed(const Duration(seconds: 10));
        final caiu = saiu;
        final reconectou = broker.connectCount;
        probe.kill();
        await broker.close();
        expect(caiu, isFalse, reason: 'o processo caiu: $stderrText');
        expect(reconectou, greaterThan(1), reason: 'não reconectou');
      },
      timeout: const Timeout(Duration(seconds: 90)),
      skip: Platform.isWindows ? 'SIGSTOP não existe no Windows' : false,
    );

    test('reconecta depois que o broker derruba a conexão e volta a publicar',
        () async {
      final a = await _ambiente();
      await a.d.connect();
      expect(a.d.isConnected, isTrue);

      a.broker.dropClients();
      await _until(() => a.broker.connectCount >= 2 && a.d.isConnected);

      await a.d.publish(_delivery());
      expect(a.broker.publishCount, 1);
    });

    test('durante a queda publish lança MqttUnavailableException', () async {
      final a = await _ambiente(backoff: const Duration(seconds: 5));
      await a.d.connect();
      await a.broker.close(); // nada mais aceita conexões
      await _until(() => !a.d.isConnected);
      await expectLater(
        a.d.publish(_delivery()),
        throwsA(isA<MqttUnavailableException>()),
      );
    });

    test(
        'socket real: RST do broker completa o Socket.done com erro, que é '
        'tratado na zona do dispatcher, e ele reconecta', () async {
      final a = await _ambiente();
      await _guardado(() async {
        await a.d.connect();
        expect(a.d.isConnected, isTrue);

        a.broker.resetClients();
        await _until(() => a.broker.connectCount >= 2 && a.d.isConnected);
        // Margem para um erro tardio do socket antigo aparecer.
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      // O erro do socket real chegou ao handler (e não ao processo).
      expect(a.logs.toString(), contains('errno=104'));
      await a.d.publish(_delivery());
      expect(a.broker.publishCount, 1);
    }, skip: Platform.isLinux ? false : 'SO_LINGER usa o número do Linux');

    test(
        'política do handler (seam, não socket real): erro transitório '
        'assíncrono não escapa e aciona reconexão', () async {
      final a = await _ambiente();
      await _guardado(() async {
        await a.d.connect();
        await a.d.simulateAsyncErrorForTest(_brokenPipe);
        await _until(() => a.broker.connectCount >= 2 && a.d.isConnected);
      });
    });

    test('cliente obsoleto: onDisconnected antigo não derruba a conexão nova',
        () async {
      final a = await _ambiente();
      await a.d.connect();
      final antigo = a.d.clientForTest!;

      a.broker.dropClients();
      await _until(() => a.broker.connectCount >= 2 && a.d.isConnected);
      final novo = a.d.clientForTest!;
      expect(identical(antigo, novo), isFalse);

      // O callback do cliente anterior dispara de novo, já com o novo ativo.
      antigo.onDisconnected!();
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(a.broker.connectCount, 2);
      expect(a.d.isConnected, isTrue);
      expect(identical(a.d.clientForTest, novo), isTrue);
    });

    test(
        'cliente obsoleto: erro assíncrono tardio na zona do cliente antigo '
        'não derruba a conexão nova', () async {
      final a = await _ambiente();
      await a.d.connect();
      final antigo = a.d.clientForTest!;

      a.broker.dropClients();
      await _until(() => a.broker.connectCount >= 2 && a.d.isConnected);
      final novo = a.d.clientForTest!;

      await a.d.simulateAsyncErrorForTest(_brokenPipe, from: antigo);
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(a.broker.connectCount, 2);
      expect(a.d.isConnected, isTrue);
      expect(identical(a.d.clientForTest, novo), isTrue);
    });

    test(
        'queda na troca de cliente durante a reconexão não deixa o '
        'dispatcher com um cliente morto', () async {
      final a = await _ambiente();
      await a.d.connect();
      var injetado = false;
      // A queda chega exatamente na janela entre `_client = novo` e o fim da
      // troca, com `_reconnecting` ainda verdadeiro.
      a.d.afterClientSwapForTest = () async {
        if (injetado) return;
        injetado = true;
        await a.d.simulateAsyncErrorForTest(
          const SocketException(
            'reset',
            osError: OSError('Connection reset by peer', 104),
          ),
        );
      };

      a.broker.dropClients();
      await _until(() => a.broker.connectCount >= 3 && a.d.isConnected);
      expect(injetado, isTrue);

      await a.d.publish(_delivery());
      expect(a.broker.publishCount, 1);
    });

    test('erro desconhecido não é engolido: é registrado e chama onFatal',
        () async {
      final a = await _ambiente(esperaFatal: true);
      await _guardado(() async {
        await a.d.connect();
        await a.d.simulateAsyncErrorForTest(StateError('detalhe-interno'));
      });
      expect(a.fatais, [isA<StateError>()]);
      expect(a.logs.toString(), contains('StateError'));
      expect(a.logs.toString(), isNot(contains('detalhe-interno')));
      // Erro fatal não é tratado como queda: nada de reconexão.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(a.broker.connectCount, 1);
    });

    test('erro depois de close() não chama onFatal', () async {
      final a = await _ambiente();
      await a.d.connect();
      final antigo = a.d.clientForTest!;
      await a.d.close();

      await a.d.simulateAsyncErrorForTest(
        StateError('detalhe-interno'),
        from: antigo,
      );
      await a.d.simulateAsyncErrorForTest(_brokenPipe, from: antigo);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(a.fatais, isEmpty);
      expect(a.logs.toString(), contains('StateError'));
      expect(a.logs.toString(), isNot(contains('detalhe-interno')));
      expect(a.broker.connectCount, 1);
    });

    test('o registro do erro transitório traz só tipo e errno (VAZ-01)',
        () async {
      final a = await _ambiente();
      await a.d.connect();
      await a.d.simulateAsyncErrorForTest(
        SocketException(
          'texto-que-nao-pode-vazar',
          osError: const OSError('Connection reset by peer', 104),
          address: InternetAddress('10.9.8.7'),
          port: 8883,
        ),
      );
      await _until(() => a.broker.connectCount >= 2 && a.d.isConnected);
      final texto = a.logs.toString();
      expect(texto, contains('SocketException'));
      expect(texto, contains('errno=104'));
      expect(texto, isNot(contains('texto-que-nao-pode-vazar')));
      expect(texto, isNot(contains('10.9.8.7')));
      expect(texto, isNot(contains('reset by peer')));
    });
  });

  group('VAZ-01: o log não carrega identidade, local nem payload (#56)', () {
    test('queda transitória: só tipo e errno', () async {
      final a = await _ambiente();
      await a.d.connect();
      await a.d.simulateAsyncErrorForTest(_erroCarregado());
      await _until(() => a.broker.connectCount >= 2 && a.d.isConnected);
      final texto = a.logs.toString();
      expect(texto, contains('SocketException'));
      expect(texto, contains('errno=32'));
      _semVazamento(texto);
    });

    test('falha de reconexão: só o tipo', () async {
      final a = await _ambiente();
      await a.d.connect();
      await a.broker.close();
      a.broker.dropClients();
      await _until(
        () => a.logs.toString().contains('Falha ao reconectar'),
      );
      final texto = a.logs.toString();
      expect(texto, contains('SocketException'));
      _semVazamento(texto);
    });

    test('falha na conexão inicial: só o tipo, também no stderr real',
        () async {
      final broker = await FakeMqttBroker.start();
      final porta = broker.port;
      await broker.close();
      final capturado = _StderrCapturado();
      final d = MqttAlertDispatcher(
        config: _config(porta),
        initialBackoff: const Duration(seconds: 30),
        onFatal: (_) {},
      );
      await IOOverrides.runZoned(
        () => d.connect(),
        stderr: () => capturado,
      );
      await d.close();
      final texto = capturado.buffer.toString();
      expect(texto, contains('Falha ao conectar ao broker MQTT'));
      expect(texto, contains('SocketException'));
      _semVazamento(texto);
    });

    test('erro fatal via onFatal: tipo no log, mensagem nunca', () async {
      final a = await _ambiente(esperaFatal: true);
      await _guardado(() async {
        await a.d.connect();
        await a.d.simulateAsyncErrorForTest(
          StateError('Broken pipe sentinela-vaz01-local 0000000000aa localhost'),
        );
      });
      final texto = a.logs.toString();
      expect(a.fatais, [isA<StateError>()]);
      expect(texto, contains('StateError'));
      _semVazamento(texto);
    });

    test('erro tardio depois de close(): só o tipo e o errno', () async {
      final a = await _ambiente();
      await a.d.connect();
      final antigo = a.d.clientForTest!;
      await a.d.close();
      await a.d.simulateAsyncErrorForTest(_erroCarregado(), from: antigo);
      final texto = a.logs.toString();
      expect(texto, contains('SocketException'));
      expect(texto, contains('encerrado'));
      _semVazamento(texto);
    });

    test('erro de teardown: só o tipo', () async {
      final a = await _ambiente();
      await a.d.connect();
      // Qualquer acesso do cliente ao seu handler lança o erro carregado:
      // o `disconnect()` do teardown falha e cai no `catch` do dispatcher.
      // ignore: invalid_use_of_protected_member
      a.d.clientForTest!.connectionHandler = _HandlerQueLanca();
      await a.d.close();
      final texto = a.logs.toString();
      expect(texto, contains('Falha ao encerrar cliente MQTT antigo ('));
      expect(texto, contains('SocketException'));
      _semVazamento(texto);
    });

    test('processo real: stderr da sonda traz só tipo e errno', () async {
      final broker = await FakeMqttBroker.start();
      final s = await _sonda('localhost:${broker.port}');
      broker.resetClients();
      await _until(() => broker.connectCount >= 2);
      await broker.close();
      await Future<void>.delayed(const Duration(seconds: 3));
      s.probe.kill();
      final texto = s.stderrText.toString();
      expect(texto, contains('SocketException'));
      _semVazamento(texto);
    }, skip: Platform.isLinux ? false : 'SO_LINGER usa o número do Linux');

    test('processo real: conexão inicial recusada loga só o tipo', () async {
      final broker = await FakeMqttBroker.start();
      final porta = broker.port;
      await broker.close();
      final s = await _sonda('localhost:$porta');
      await Future<void>.delayed(const Duration(seconds: 3));
      s.probe.kill();
      final texto = s.stderrText.toString();
      expect(texto, contains('Falha ao conectar ao broker MQTT'));
      expect(texto, contains('SocketException'));
      _semVazamento(texto);
    });
  });

  group('publicação confirmada por PUBACK (H5, #56)', () {
    test('completa só depois do PUBACK do broker', () async {
      final a = await _ambiente();
      await a.d.connect();

      await a.d.publish(_delivery());

      expect(a.broker.publishCount, 1);
      expect(a.broker.pubackCount, 1);
    });

    test(
        'sem PUBACK: falha no prazo, dá a conexão como perdida, reconecta e a '
        'publicação seguinte é confirmada', () async {
      final a = await _ambiente(
        publishAckTimeout: const Duration(milliseconds: 300),
      );
      await a.d.connect();
      final antigo = a.d.clientForTest;
      a.broker.withholdPuback = true;

      final inicio = DateTime.now();
      await expectLater(
        a.d.publish(_delivery()),
        throwsA(isA<MqttUnavailableException>()),
      );
      expect(DateTime.now().difference(inicio),
          greaterThanOrEqualTo(const Duration(milliseconds: 250)));
      expect(a.broker.publishCount, 1, reason: 'o PUBLISH saiu');
      // O tempo limite derrubou o cliente na hora: nada de "connected" morto.
      expect(identical(a.d.clientForTest, antigo), isFalse);

      a.broker.withholdPuback = false;
      await _until(() => a.broker.connectCount >= 2 && a.d.isConnected);
      await a.d.publish(_delivery());
      expect(a.broker.pubackCount, 1);
      expect(a.logs.toString(), contains('PUBACK não recebido'));
    });

    test(
        'depois de um tempo limite as publicações seguintes falham na hora, '
        'sem esperar outro prazo inteiro', () async {
      final a = await _ambiente(
        backoff: const Duration(seconds: 30),
        publishAckTimeout: const Duration(milliseconds: 500),
      );
      await a.d.connect();
      a.broker.withholdPuback = true;

      await expectLater(
        a.d.publish(_delivery()),
        throwsA(isA<MqttUnavailableException>()),
      );
      final inicio = DateTime.now();
      for (var i = 0; i < 5; i++) {
        await expectLater(
          a.d.publish(_delivery()),
          throwsA(isA<MqttUnavailableException>()),
        );
      }
      expect(DateTime.now().difference(inicio),
          lessThan(const Duration(milliseconds: 200)));
      expect(a.broker.publishCount, 1, reason: 'só a primeira chegou a sair');
    });

    test(
        'publicações em voo falham com MqttUnavailableException quando a '
        'conexão cai antes do PUBACK', () async {
      final a = await _ambiente();
      await a.d.connect();
      a.broker.withholdPuback = true;

      final emVoo = [
        a.d.publish(_delivery()),
        a.d.publish(_delivery()),
        a.d.publish(_delivery()),
      ];
      await _until(() => a.broker.publishCount == 3);
      final inicio = DateTime.now();
      a.broker.dropClients();

      for (final f in emVoo) {
        await expectLater(f, throwsA(isA<MqttUnavailableException>()));
      }
      // Pela queda, não pelo prazo de 10 s.
      expect(DateTime.now().difference(inicio),
          lessThan(const Duration(seconds: 5)));

      a.broker.withholdPuback = false;
      await _until(() => a.broker.connectCount >= 2 && a.d.isConnected);
      await a.d.publish(_delivery());
    });

    test('close() falha as publicações em voo', () async {
      final a = await _ambiente();
      await a.d.connect();
      a.broker.withholdPuback = true;
      final emVoo = a.d.publish(_delivery());
      await _until(() => a.broker.publishCount == 1);

      await a.d.close();

      await expectLater(emVoo, throwsA(isA<MqttUnavailableException>()));
    });

    test(
        'partição sem FIN/RST: sem PINGRESP no prazo a biblioteca derruba a '
        'conexão e o dispatcher reconecta', () async {
      final a = await _ambiente(keepAliveSeconds: 1, pingResponseTimeoutSeconds: 1);
      await _guardado(() async {
        await a.d.connect();
        final antigo = a.d.clientForTest;
        a.broker.ignorePings = true;
        // PINGREQ em ~1 s, sem resposta por 1 s: queda detectada em ~2 s.
        await _until(
          () => !identical(a.d.clientForTest, antigo),
          timeout: const Duration(seconds: 6),
        );
        a.broker.ignorePings = false;
        await _until(() => a.broker.connectCount >= 2 && a.d.isConnected);
      });
      await a.d.publish(_delivery());
      expect(a.broker.pubackCount, 1);
    });

    test(
        'outbox: lote de 32 com o broker mudo leva um prazo de PUBACK, não 32, '
        'e nenhuma entrada é marcada publicada', () async {
      final a = await _ambiente(
        backoff: const Duration(seconds: 30),
        publishAckTimeout: const Duration(milliseconds: 400),
      );
      await a.d.connect();
      a.broker.withholdPuback = true;
      final outbox = _OutboxEmMemoria(32);
      final drenador = AlertOutboxDispatcher(outbox: outbox, publisher: a.d);

      final inicio = DateTime.now();
      final publicadas = await drenador.drainOnce();
      final duracao = DateTime.now().difference(inicio);

      expect(publicadas, 0);
      expect(outbox.publicadas, isEmpty);
      expect(outbox.falhas, hasLength(32));
      expect(duracao, lessThan(const Duration(seconds: 2)),
          reason: '32 x 400 ms seriam 12,8 s');
      expect(a.broker.publishCount, 1, reason: 'as outras falham na hora');
    });

    test('VAZ-01: a falha de confirmação registra só o tipo, sem identidade',
        () async {
      final a = await _ambiente(
        publishAckTimeout: const Duration(milliseconds: 200),
      );
      await a.d.connect();
      a.broker.withholdPuback = true;
      await expectLater(
        a.d.publish(_delivery()),
        throwsA(isA<MqttUnavailableException>()),
      );
      a.broker.withholdPuback = false;
      await _until(() => a.broker.connectCount >= 2 && a.d.isConnected);
      final texto = a.logs.toString();
      expect(texto, contains('PUBACK não recebido'));
      _semVazamento(texto);
      expect(texto, isNot(contains('sem-local-00')), reason: 'locationHash');
      expect(texto, isNot(contains('000000000003')), reason: 'microárea');
      expect(texto, isNot(contains('000000000001')), reason: 'paciente');
    });
  });
}
