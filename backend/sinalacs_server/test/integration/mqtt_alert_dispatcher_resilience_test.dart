@Tags(['resiliencia'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
}) async {
  final broker = await FakeMqttBroker.start();
  final fatais = <Object>[];
  final logs = StringBuffer();
  final d = MqttAlertDispatcher(
    config: _config(broker.port),
    initialBackoff: backoff,
    onFatal: fatais.add,
    log: logs.writeln,
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

      a.d.publish(_delivery());
      await _until(() => a.broker.publishCount == 1);
    });

    test('durante a queda publish lança MqttUnavailableException', () async {
      final a = await _ambiente(backoff: const Duration(seconds: 5));
      await a.d.connect();
      await a.broker.close(); // nada mais aceita conexões
      await _until(() => !a.d.isConnected);
      expect(
        () => a.d.publish(_delivery()),
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
      a.d.publish(_delivery());
      await _until(() => a.broker.publishCount == 1);
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

      a.d.publish(_delivery());
      await _until(() => a.broker.publishCount == 1);
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
}
