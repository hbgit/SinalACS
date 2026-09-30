import 'dart:convert';

import 'package:sinalacs_patient/core/network/auth_session.dart';
import 'package:sinalacs_patient/core/network/backend_client.dart';

import '../../test/support/e2e_config.dart';
import '../../test/support/e2e_login_core.dart';

/// Microárea do seed de DESENVOLVIMENTO. Só vale no fallback (sem manifesto),
/// que é o que o `android-e2e` da CI usa; com o manifesto a microárea da
/// fixture é a referência.
const developmentMicroAreaId = '00000000-0000-4000-8000-000000000003';

const _fixtures = String.fromEnvironment('E2E_FIXTURES');
const _otpRelay = String.fromEnvironment(
  'OTP_RELAY',
  defaultValue: 'http://localhost:8765/code',
);

/// O manifesto de fixtures, ou `null` quando o teste roda contra a stack de
/// desenvolvimento (sem `--dart-define=E2E_FIXTURES=...`).
E2eConfig? e2eConfig() => _fixtures.isEmpty
    ? null
    : E2eConfig.fromMap((jsonDecode(_fixtures) as Map).cast<String, Object?>());

/// Microárea que a sessão do paciente [role] deve trazer.
String expectedMicroArea({String role = 'main'}) {
  final config = e2eConfig();
  return config == null
      ? developmentMicroAreaId
      : config.patient(role).microAreaId;
}

/// Entra como o paciente [role] da fixture (OTP real) ou, sem manifesto, pelo
/// login de desenvolvimento. Ver [loginPatientWith].
Future<AuthSession> loginPatient(
  BackendClient backend, {
  String role = 'main',
}) => loginPatientWith(backend, e2eConfig(), relayUrl: _otpRelay, role: role);
