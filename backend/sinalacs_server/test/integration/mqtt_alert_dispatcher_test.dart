import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/domain/entities/alert_delivery.dart';
import 'package:sinalacs_server/src/infrastructure/mqtt/mqtt_alert_dispatcher.dart';
import 'package:test/test.dart';

AppConfig _config() => AppConfig(
      mqttBroker: 'localhost:1883',
      jwtSecret: 'test-secret',
      auditChainSecret: 'test-audit-chain-secret',
      // Hex de 64 caracteres: HealthDataCipher decodifica byte a byte
      // para montar a chave AES-256 (ver AppConfig).
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

void main() {
  group('MqttAlertDispatcher', () {
    test('falha ao publicar quando o broker não está conectado', () {
      final dispatcher = MqttAlertDispatcher(config: _config());

      expect(
        () => dispatcher.publish(_delivery()),
        throwsA(isA<MqttUnavailableException>()),
      );
    });

    test('a primeira falha de conexão não derruba o processo', () async {
      final dispatcher = MqttAlertDispatcher(
        config: AppConfig(
          mqttBroker: 'localhost:1',
          jwtSecret: 'test-secret',
          auditChainSecret: 'test-audit-chain-secret',
          // Hex de 64 caracteres: HealthDataCipher decodifica byte a byte
          // para montar a chave AES-256 (ver AppConfig).
          healthDataEncryptionKey: AppConfig.developmentHealthDataEncryptionKey,
          cpfHashPepper: AppConfig.developmentCpfHashPepper,
          smsGateway: 'log',
          mqttUsername: null,
          mqttPassword: null,
          mqttUseTls: false,
          mqttCaCertificatePath: null,
          appEnv: 'development',
          enableDevLogin: true,
        ),
      );

      await dispatcher.connect();

      expect(dispatcher.isConnected, isFalse);
      await dispatcher.close();
    });
  });
}