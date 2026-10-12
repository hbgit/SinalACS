@Tags(['resiliencia'])
library;

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
  });
}
