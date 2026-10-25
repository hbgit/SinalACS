import 'dart:async';
import 'dart:io';

import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/infrastructure/mqtt/mqtt_alert_dispatcher.dart';

/// Sonda de processo: conecta um dispatcher ao broker de `MQTT_BROKER`,
/// imprime PRONTO no stdout e fica viva. Não loga nada além do dispatcher.
Future<void> main() async {
  final dispatcher = MqttAlertDispatcher(
    config: AppConfig(
      mqttBroker: Platform.environment['MQTT_BROKER'] ?? 'localhost:1883',
      jwtSecret: 'test-secret',
      auditChainSecret: 'test-audit-chain-secret',
      healthDataEncryptionKey: AppConfig.developmentHealthDataEncryptionKey,
      cpfHashPepper: AppConfig.developmentCpfHashPepper,
      telemetryPseudonymKey: AppConfig.developmentTelemetryPseudonymKey,
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
  stdout.writeln('PRONTO');
  await Completer<void>().future;
}
