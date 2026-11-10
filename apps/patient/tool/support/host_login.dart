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
/// que pode nem estar de pé, e a ferramenta tentaria um convite que ninguém
/// emitiu. Sem a variável, usa o login de desenvolvimento, como antes.
///
/// O login com manifesto consome um convite de uso único gravado pelo seed
/// (C-05, RF24) e cria a credencial de dispositivo no processo — nada fica no
/// aparelho nem no disco.
Future<AuthSession> loginPatientOnHost(PatientBackend backend, {String role = 'main'}) {
  final path = Platform.environment['E2E_FIXTURES_FILE'];
  final config = path == null || path.isEmpty
      ? null
      : E2eConfig.fromMap((jsonDecode(File(path).readAsStringSync()) as Map).cast<String, Object?>());
  return loginPatientWith(backend, config, role: role);
}
