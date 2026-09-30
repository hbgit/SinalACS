import 'dart:convert';
import 'dart:io';

import 'package:sinalacs_patient/core/network/auth_session.dart';
import 'package:sinalacs_patient/core/network/backend_client.dart';

import 'e2e_config.dart';

/// Entra como o paciente [role] da fixture, pelo OTP real: pede o código, lê no
/// relé (`scripts/qa/otp_relay.py`) o que o gateway `log` escreveu e verifica.
/// Sem manifesto ([config] nulo) cai no login de desenvolvimento, como antes —
/// é o que mantém o `android-e2e` da CI funcionando.
///
/// O servidor impõe 60 s entre dois pedidos de código do MESMO paciente: quem
/// precisa de várias sessões no mesmo paciente compartilha a sessão.
Future<AuthSession> loginPatientWith(
  PatientBackend backend,
  E2eConfig? config, {
  required String relayUrl,
  String role = 'main',
  Duration retryDelay = const Duration(milliseconds: 500),
  int attempts = 20,
}) async {
  if (config == null) return backend.developmentLogin(role: 'patient');
  final fixture = config.patient(role);
  final pedidoEm = DateTime.now().toUtc().millisecondsSinceEpoch;
  await backend.requestOtp(cpf: fixture.cpf, birthDate: fixture.birthDate);
  final code = await codeFromRelay(relayUrl, pedidoEm, retryDelay: retryDelay, attempts: attempts);
  return backend.verifyOtp(cpf: fixture.cpf, code: code);
}

/// O código mais recente escrito DEPOIS de [sinceMs] (epoch, ms).
Future<String> codeFromRelay(
  String relayUrl,
  int sinceMs, {
  Duration retryDelay = const Duration(milliseconds: 500),
  int attempts = 20,
}) async {
  final client = HttpClient();
  try {
    for (var i = 0; i < attempts; i++) {
      try {
        final request = await client.getUrl(Uri.parse('$relayUrl?since=$sinceMs'));
        final response = await request.close();
        final body = await utf8.decodeStream(response);
        if (response.statusCode == 200) return body.trim();
      } on SocketException {
        // relé ainda não subiu: tenta de novo
      }
      await Future<void>.delayed(retryDelay);
    }
    throw StateError('o relé não devolveu o código do OTP: rode scripts/qa/otp_relay.py '
        'e, no emulador, adb reverse tcp:8765 tcp:8765');
  } finally {
    client.close(force: true);
  }
}
