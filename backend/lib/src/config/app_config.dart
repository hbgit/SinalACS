class AppConfig {
  const AppConfig({
    required this.databaseUrl,
    required this.mqttBroker,
    required this.jwtSecret,
  });

  final String databaseUrl;
  final String mqttBroker;
  final String jwtSecret;

  factory AppConfig.fromEnvironment() {
    return AppConfig(
      databaseUrl: const String.fromEnvironment('DATABASE_URL', defaultValue: 'postgresql://sinalacs_user:strongpassword@localhost:5432/sinalacs_db'),
      mqttBroker: const String.fromEnvironment('MQTT_BROKER', defaultValue: 'localhost:1883'),
      jwtSecret: const String.fromEnvironment('JWT_SECRET', defaultValue: 'development-secret'),
    );
  }
}
