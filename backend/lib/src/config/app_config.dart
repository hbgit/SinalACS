import 'dart:io';

class AppConfig {
  const AppConfig({
    required this.databaseUrl,
    required this.mqttBroker,
    required this.jwtSecret,
    required this.mqttUsername,
    required this.mqttPassword,
    required this.mqttUseTls,
    required this.mqttCaCertificatePath,
  });

  final String databaseUrl;
  final String mqttBroker;
  final String jwtSecret;
  final String? mqttUsername;
  final String? mqttPassword;
  final bool mqttUseTls;
  final String? mqttCaCertificatePath;

  factory AppConfig.fromEnvironment() {
    return AppConfig(
      databaseUrl: Platform.environment['DATABASE_URL'] ?? 'postgresql://sinalacs_user:strongpassword@localhost:5432/sinalacs_db',
      mqttBroker: Platform.environment['MQTT_BROKER'] ?? 'localhost:1883',
      jwtSecret: Platform.environment['JWT_SECRET'] ?? 'development-secret',
      mqttUsername: Platform.environment['MQTT_USERNAME'],
      mqttPassword: Platform.environment['MQTT_PASSWORD'],
      mqttUseTls: Platform.environment['MQTT_USE_TLS'] == 'true',
      mqttCaCertificatePath: Platform.environment['MQTT_CA_CERT_PATH'],
    );
  }
}
