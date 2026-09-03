import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

const _host = 'localhost';
const _port = 8080;

Future<Map<String, dynamic>> _request(
  String path, {
  String method = 'GET',
  Map<String, dynamic>? body,
  Map<String, String>? headers,
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(
      method,
      Uri.parse('http://$_host:$_port$path'),
    );

    if (headers != null) {
      headers.forEach(request.headers.set);
    }

    if (body != null) {
      final payload = jsonEncode(body);
      request.headers.contentType = ContentType.json;
      request.write(payload);
    }

    final response = await request.close();
    final raw = await response.transform(utf8.decoder).join();
    if (raw.isEmpty) {
      return <String, dynamic>{};
    }
    return jsonDecode(raw) as Map<String, dynamic>;
  } finally {
    client.close(force: true);
  }
}

Future<Process?> _startBackendIfNeeded() async {
  try {
    final health = await _request('/health');
    if (health['status'] == 'ok') {
      return null;
    }
  } on SocketException {
    // backend not running locally; continue with a process startup attempt.
  } on HttpException {
    // backend not accepting requests yet; continue with startup attempt.
  }

  final workingDirectory = Directory.current.path;
  final environment = Map<String, String>.from(Platform.environment)
    ..['DATABASE_URL'] = 'postgresql://sinalacs_user:strongpassword@localhost:5432/sinalacs_db?sslmode=disable'
    ..['MQTT_BROKER'] = 'localhost:1883'
    ..['JWT_SECRET'] = 'development-secret'
    ..['MQTT_USERNAME'] = 'backend'
    ..['MQTT_PASSWORD'] = 'development-backend-password'
    ..['MQTT_USE_TLS'] = 'false'
    ..['ENABLE_DEV_LOGIN'] = 'true';

  final process = await Process.start(
    Platform.resolvedExecutable,
    ['run', 'bin/server.dart'],
    workingDirectory: workingDirectory,
    environment: environment,
  );

  for (var attempt = 0; attempt < 30; attempt++) {
    try {
      final health = await _request('/health');
      if (health['status'] == 'ok') {
        return process;
      }
    } on SocketException {
      // continue waiting for the server to bind the port.
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  final stderr = await process.stderr.transform(utf8.decoder).join();
  process.kill();
  throw StateError('O backend não iniciou corretamente.\n$stderr');
}

void main() {
  late Process? backendProcess;

  setUpAll(() async {
    backendProcess = await _startBackendIfNeeded();
  });

  tearDownAll(() async {
    final process = backendProcess;
    if (process != null) {
      process.kill();
      await process.exitCode;
    }
  });

  test('health responde e o login de patient/acs funciona', () async {
    final health = await _request('/health');
    expect(health['status'], 'ok');

    final patient = await _request(
      '/v1/auth/development/login',
      method: 'POST',
      body: {'role': 'patient'},
    );
    expect(patient.containsKey('access_token'), isTrue);

    final acs = await _request(
      '/v1/auth/development/login',
      method: 'POST',
      body: {'role': 'acs'},
    );
    expect(acs.containsKey('access_token'), isTrue);
  });

  test('alerta vermelho e ACK completam o ciclo crítico via HTTP', () async {
    final patientLogin = await _request(
      '/v1/auth/development/login',
      method: 'POST',
      body: {'role': 'patient'},
    );
    final acsLogin = await _request(
      '/v1/auth/development/login',
      method: 'POST',
      body: {'role': 'acs'},
    );

    final patientToken = patientLogin['access_token'] as String;
    final acsToken = acsLogin['access_token'] as String;

    final alert = await _request(
      '/v1/alerts/red',
      method: 'POST',
      body: {'location_hash': '6gyf4bf'},
      headers: {'Authorization': 'Bearer $patientToken', 'Idempotency-Key': 'req-http-001'},
    );

    expect(alert['status'], 'pending');
    expect(alert.containsKey('alert_id'), isTrue);

    final alertId = alert['alert_id'] as String;
    final ack = await _request(
      '/v1/alerts/$alertId/ack',
      method: 'POST',
      headers: {'Authorization': 'Bearer $acsToken'},
    );

    expect(ack['status'], 'acknowledged');
    expect(ack['alert_id'], alertId);
  });
}
