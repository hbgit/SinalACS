import 'package:sinalacs_backend/src/config/app_config.dart';

Future<void> main() async {
  final config = AppConfig.fromEnvironment();

  print('SinalACS backend starting...');
  print('Database URL: ${config.databaseUrl}');
  print('MQTT broker: ${config.mqttBroker}');
}
