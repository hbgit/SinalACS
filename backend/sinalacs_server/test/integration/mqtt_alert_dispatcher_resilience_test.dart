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

/// `stderr` falso para conferir o que o dispatcher registra (VAZ-01).
class _StderrCapturado implements Stdout {
  final linhas = StringBuffer();

  @override
  void writeln([Object? object = '']) => linhas.writeln(object);

  @override
  void write(Object? object) => linhas.write(object);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('MqttAlertDispatcher resiliência', () {
    test('conecta ao broker falso', () async {
      final broker = await FakeMqttBroker.start();
      final dispatcher = MqttAlertDispatcher(config: _config(broker.port));
      addTearDown(() async {
        await dispatcher.close();
        await broker.close();
      });

      await dispatcher.connect();

      expect(dispatcher.isConnected, isTrue);
      expect(broker.connectCount, 1);
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
      final broker = await FakeMqttBroker.start();
      final d = MqttAlertDispatcher(
        config: _config(broker.port),
        initialBackoff: const Duration(milliseconds: 100),
      );
      addTearDown(() async {
        await d.close();
        await broker.close();
      });
      await d.connect();
      expect(d.isConnected, isTrue);

      broker.dropClients();
      await _until(() => broker.connectCount >= 2 && d.isConnected);

      d.publish(_delivery());
      await _until(() => broker.publishCount == 1);
    });

    test('durante a queda publish lança MqttUnavailableException', () async {
      final broker = await FakeMqttBroker.start();
      final d = MqttAlertDispatcher(
        config: _config(broker.port),
        initialBackoff: const Duration(seconds: 5),
      );
      addTearDown(d.close);
      await d.connect();
      await broker.close(); // nada mais aceita conexões
      await _until(() => !d.isConnected);
      expect(
        () => d.publish(_delivery()),
        throwsA(isA<MqttUnavailableException>()),
      );
    });

    test(
        'socket real: RST do broker completa o Socket.done com erro, que não '
        'escapa da zona do dispatcher, e ele reconecta', () async {
      final broker = await FakeMqttBroker.start();
      final escapou = <Object>[];
      late MqttAlertDispatcher d;
      await runZonedGuarded(() async {
        d = MqttAlertDispatcher(
          config: _config(broker.port),
          initialBackoff: const Duration(milliseconds: 100),
        );
        await d.connect();
        expect(d.isConnected, isTrue);

        broker.resetClients();
        await _until(() => broker.connectCount >= 2 && d.isConnected);
        // Margem para um erro tardio do socket antigo aparecer.
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }, (e, _) => escapou.add(e));
      addTearDown(() async {
        await d.close();
        await broker.close();
      });
      expect(escapou.map((e) => e.runtimeType), isEmpty);
      d.publish(_delivery());
      await _until(() => broker.publishCount == 1);
    }, skip: Platform.isLinux ? false : 'SO_LINGER usa o número do Linux');

    test(
        'política do handler (seam, não socket real): erro transitório '
        'assíncrono não escapa e aciona reconexão', () async {
      final broker = await FakeMqttBroker.start();
      final escapou = <Object>[];
      late MqttAlertDispatcher d;
      await runZonedGuarded(() async {
        d = MqttAlertDispatcher(
          config: _config(broker.port),
          initialBackoff: const Duration(milliseconds: 100),
        );
        await d.connect();
        await d.simulateAsyncErrorForTest(
          const SocketException(
            'Broken pipe',
            osError: OSError('Broken pipe', 32),
          ),
        );
        await _until(() => broker.connectCount >= 2 && d.isConnected);
      }, (e, _) => escapou.add(e));
      addTearDown(() async {
        await d.close();
        await broker.close();
      });
      expect(escapou, isEmpty);
    });

    test('cliente obsoleto: onDisconnected antigo não derruba a conexão nova',
        () async {
      final broker = await FakeMqttBroker.start();
      final d = MqttAlertDispatcher(
        config: _config(broker.port),
        initialBackoff: const Duration(milliseconds: 100),
      );
      addTearDown(() async {
        await d.close();
        await broker.close();
      });
      await d.connect();
      final antigo = d.clientForTest!;

      broker.dropClients();
      await _until(() => broker.connectCount >= 2 && d.isConnected);
      final novo = d.clientForTest!;
      expect(identical(antigo, novo), isFalse);

      // O callback do cliente anterior dispara de novo, já com o novo ativo.
      antigo.onDisconnected!();
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(broker.connectCount, 2);
      expect(d.isConnected, isTrue);
      expect(identical(d.clientForTest, novo), isTrue);
    });

    test('erro desconhecido não é engolido: é registrado e chama onFatal',
        () async {
      final broker = await FakeMqttBroker.start();
      final fatais = <Object>[];
      final escapou = <Object>[];
      final saida = _StderrCapturado();
      late MqttAlertDispatcher d;
      await IOOverrides.runZoned(
        () => runZonedGuarded(() async {
          d = MqttAlertDispatcher(
            config: _config(broker.port),
            initialBackoff: const Duration(milliseconds: 100),
            onFatal: fatais.add,
          );
          await d.connect();
          await d.simulateAsyncErrorForTest(StateError('detalhe-interno'));
        }, (e, _) => escapou.add(e)),
        stderr: () => saida,
      );
      addTearDown(() async {
        await d.close();
        await broker.close();
      });
      expect(escapou, isEmpty);
      expect(fatais, [isA<StateError>()]);
      expect(saida.linhas.toString(), contains('StateError'));
      expect(saida.linhas.toString(), isNot(contains('detalhe-interno')));
      // Erro fatal não é tratado como queda: nada de reconexão.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(broker.connectCount, 1);
    });

    test('o registro do erro transitório traz só tipo e errno (VAZ-01)',
        () async {
      final broker = await FakeMqttBroker.start();
      final saida = _StderrCapturado();
      late MqttAlertDispatcher d;
      await IOOverrides.runZoned(
        () async {
          d = MqttAlertDispatcher(
            config: _config(broker.port),
            initialBackoff: const Duration(milliseconds: 100),
          );
          await d.connect();
          await d.simulateAsyncErrorForTest(
            SocketException(
              'texto-que-nao-pode-vazar',
              osError: const OSError('Connection reset by peer', 104),
              address: InternetAddress('10.9.8.7'),
              port: 8883,
            ),
          );
          await _until(() => broker.connectCount >= 2 && d.isConnected);
        },
        stderr: () => saida,
      );
      addTearDown(() async {
        await d.close();
        await broker.close();
      });
      final texto = saida.linhas.toString();
      expect(texto, contains('SocketException'));
      expect(texto, contains('errno=104'));
      expect(texto, isNot(contains('texto-que-nao-pode-vazar')));
      expect(texto, isNot(contains('10.9.8.7')));
      expect(texto, isNot(contains('reset by peer')));
    });
  });
}
