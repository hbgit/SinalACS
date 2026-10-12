@Tags(['resiliencia'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/infrastructure/mqtt/mqtt_alert_dispatcher.dart';
import 'package:test/test.dart';

import '../support/fake_mqtt_broker.dart';

AppConfig _config(int port) => AppConfig(
      mqttBroker: 'localhost:$port',
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
  });
}
