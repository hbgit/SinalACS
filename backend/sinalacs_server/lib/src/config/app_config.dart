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
    required this.appEnv,
    required this.enableDevLogin,
  });

  final String databaseUrl;
  final String mqttBroker;
  final String jwtSecret;
  final String? mqttUsername;
  final String? mqttPassword;
  final bool mqttUseTls;
  final String? mqttCaCertificatePath;
  final String appEnv;
  final bool enableDevLogin;

  bool get isProduction => appEnv == 'production';

  factory AppConfig.fromEnvironment() {
    final appEnv = Platform.environment['APP_ENV'] ?? 'development';
    final jwtSecret = Platform.environment['JWT_SECRET'];
    if (jwtSecret == null && appEnv == 'production') {
      throw StateError('JWT_SECRET é obrigatório quando APP_ENV=production.');
    }

    return AppConfig(
      databaseUrl: Platform.environment['DATABASE_URL'] ?? 'postgresql://sinalacs_user:strongpassword@localhost:5432/sinalacs_db',
      mqttBroker: Platform.environment['MQTT_BROKER'] ?? 'localhost:1883',
      jwtSecret: jwtSecret ?? 'development-secret',
      mqttUsername: Platform.environment['MQTT_USERNAME'],
      mqttPassword: Platform.environment['MQTT_PASSWORD'],
      mqttUseTls: Platform.environment['MQTT_USE_TLS'] == 'true',
      mqttCaCertificatePath: Platform.environment['MQTT_CA_CERT_PATH'],
      appEnv: appEnv,
      enableDevLogin: Platform.environment['ENABLE_DEV_LOGIN'] == 'true',
    );
  }
}
