import 'dart:convert';
import 'dart:io';

import 'package:sinalacs_patient/core/network/auth_session.dart';
import 'package:sinalacs_patient/core/network/backend_client.dart';

import '../../test/support/e2e_config.dart';
import '../../test/support/e2e_login_core.dart';

/// Login do paciente para as ferramentas de linha de comando (rodam no host).
///
/// O manifesto de fixtures só vale quando pedido: `E2E_FIXTURES_FILE=<arquivo>`
/// (o `scripts/qa/patient_full_e2e.sh` define). Um arquivo esquecido em
/// `.e2e/` não muda o caminho sozinho — ele descreveria pacientes de uma stack
/// que pode nem estar de pé, e a ferramenta tentaria um OTP que ninguém vai
/// ouvir. Sem a variável, usa o login de desenvolvimento, como antes.
Future<AuthSession> loginPatientOnHost(PatientBackend backend, {String role = 'main'}) {
  final path = Platform.environment['E2E_FIXTURES_FILE'];
  final config = path == null || path.isEmpty
      ? null
      : E2eConfig.fromMap((jsonDecode(File(path).readAsStringSync()) as Map).cast<String, Object?>());
  return loginPatientWith(
    backend,
    config,
    relayUrl: Platform.environment['OTP_RELAY'] ?? 'http://127.0.0.1:8765/code',
    role: role,
  );
}
