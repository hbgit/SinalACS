import 'dart:io';

import 'package:sinalacs_backend/src/config/app_config.dart';

Future<void> main() async {
  final config = AppConfig.fromEnvironment();
  final server = await HttpServer.bind(InternetAddress.anyIPv4, 8080);

  print('SinalACS backend starting...');
  print('Database URL: ${config.databaseUrl}');
  print('MQTT broker: ${config.mqttBroker}');
  print('Listening on port ${server.port}');

  await for (final request in server) {
    if (request.method == 'GET' && request.uri.path == '/health') {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write('{"status":"ok"}');
    } else {
      request.response.statusCode = HttpStatus.notFound;
    }

    await request.response.close();
  }
}
