import 'dart:convert';
import 'dart:io';

import 'package:sinalacs_backend/src/application/alerts/red_alert_service.dart';
import 'package:sinalacs_backend/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_backend/src/config/app_config.dart';
import 'package:sinalacs_backend/src/domain/enums/user_role.dart';
import 'package:sinalacs_backend/src/infrastructure/database/postgres_alert_store.dart';
import 'package:sinalacs_backend/src/infrastructure/mqtt/mqtt_alert_dispatcher.dart';

Future<void> main() async {
  final config = AppConfig.fromEnvironment();
  final server = await HttpServer.bind(InternetAddress.anyIPv4, 8080);
  final mqtt = MqttAlertDispatcher(config: config);
  final store = PostgresAlertStore(databaseUrl: config.databaseUrl);
  final auth = DevelopmentAuthService(secret: config.jwtSecret);
  await store.open();
  final alerts = RedAlertService(publisher: mqtt, store: store);

  print('SinalACS backend starting...');
  print('Database URL: ${config.databaseUrl}');
  print('MQTT broker: ${config.mqttBroker}');
  await mqtt.connect(
    onAcknowledgement: (ack) async {
      final acknowledged = await alerts.acknowledge(
        user: AuthenticatedUser(id: ack.acsId, role: UserRole.acs, microAreaId: ack.microAreaId, deviceId: 'mqtt'),
        alertId: ack.alertId,
      );
      print('Alert ${ack.alertId} acknowledged: $acknowledged.');
    },
  );
  print('Listening on port ${server.port}');

  await for (final request in server) {
    if (request.method == 'GET' && request.uri.path == '/health') {
      await _writeJson(request.response, HttpStatus.ok, {'status': 'ok'});
    } else if (request.method == 'POST' && request.uri.path == '/v1/auth/development/login') {
      final body = await _readJson(request);
      final role = body['role'];
      final user = switch (role) {
        'patient' => const AuthenticatedUser(id: '00000000-0000-4000-8000-000000000001', role: UserRole.patient, microAreaId: '00000000-0000-4000-8000-000000000003', deviceId: 'patient-device-001'),
        'acs' => const AuthenticatedUser(id: '00000000-0000-4000-8000-000000000002', role: UserRole.acs, microAreaId: '00000000-0000-4000-8000-000000000003', deviceId: 'acs-device-001'),
        _ => null,
      };
      if (user == null) {
        await _writeJson(request.response, HttpStatus.badRequest, {'error': 'role deve ser patient ou acs'});
      } else {
        await _writeJson(request.response, HttpStatus.ok, {'access_token': auth.issueToken(user), 'token_type': 'Bearer'});
      }
    } else if (request.method == 'POST' && request.uri.path == '/v1/alerts/red') {
      final user = auth.verifyToken(request.headers.value(HttpHeaders.authorizationHeader)?.replaceFirst('Bearer ', '') ?? '');
      if (user == null) {
        await _writeJson(request.response, HttpStatus.unauthorized, {'error': 'token inválido ou expirado'});
      } else {
        final body = await _readJson(request);
        try {
          final alert = await alerts.create(
            user: user,
            idempotencyKey: request.headers.value('idempotency-key') ?? '',
            locationHash: body['location_hash'] as String? ?? '',
          );
          await _writeJson(request.response, HttpStatus.accepted, {'alert_id': alert.delivery.alertId, 'status': 'pending'});
        } on ArgumentError catch (error) {
          await _writeJson(request.response, HttpStatus.badRequest, {'error': error.message});
        } on StateError catch (error) {
          await _writeJson(request.response, HttpStatus.forbidden, {'error': error.message});
        }
      }
    } else if (request.method == 'POST' && RegExp(r'^/v1/alerts/[0-9a-f-]+/ack$').hasMatch(request.uri.path)) {
      final user = auth.verifyToken(request.headers.value(HttpHeaders.authorizationHeader)?.replaceFirst('Bearer ', '') ?? '');
      if (user == null) {
        await _writeJson(request.response, HttpStatus.unauthorized, {'error': 'token inválido ou expirado'});
      } else {
        final alertId = request.uri.pathSegments[2];
        try {
          final acknowledged = await alerts.acknowledge(user: user, alertId: alertId);
          await _writeJson(
            request.response,
            acknowledged ? HttpStatus.ok : HttpStatus.notFound,
            {'alert_id': alertId, 'status': acknowledged ? 'acknowledged' : 'not_found'},
          );
        } on StateError catch (error) {
          await _writeJson(request.response, HttpStatus.forbidden, {'error': error.message});
        }
      }
    } else {
      await _writeJson(request.response, HttpStatus.notFound, {'error': 'not found'});
    }
  }

  await mqtt.close();
  await store.close();
}

Future<Map<String, dynamic>> _readJson(HttpRequest request) async {
  final body = await utf8.decoder.bind(request).join();
  return jsonDecode(body) as Map<String, dynamic>;
}

Future<void> _writeJson(HttpResponse response, int statusCode, Map<String, dynamic> body) async {
  response
    ..statusCode = statusCode
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
  await response.close();
}
