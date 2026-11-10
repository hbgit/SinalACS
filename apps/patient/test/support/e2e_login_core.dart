import 'package:sinalacs_patient/core/network/auth_session.dart';
import 'package:sinalacs_patient/core/network/backend_client.dart';
import 'package:sinalacs_patient/core/security/device_identity.dart';

import 'e2e_config.dart';

/// Entra como o paciente [role] da fixture, pelo convite QR + credencial de
/// dispositivo (RF24, C-05): consome UM convite do manifesto (o seed grava
/// seis convites de uso único por paciente) com um deviceId/segredo sorteados
/// na hora — o mesmo caminho da tela de PIN, sem o envelope porque a
/// ferramenta não tem Keystore. Sem manifesto ([config] nulo) cai no login de
/// desenvolvimento, como antes — é o que mantém o `android-e2e` da CI
/// funcionando.
///
/// PRIVACIDADE: o segredo sorteado existe só no processo do teste; nada dele é
/// impresso ou gravado.
Future<AuthSession> loginPatientWith(
  PatientBackend backend,
  E2eConfig? config, {
  String role = 'main',
}) async {
  if (config == null) return backend.developmentLogin(role: 'patient');
  final fixture = config.patient(role);
  final token = fixture.takeInviteToken();
  return backend.completeEnrollment(
    token: token,
    healthDataConsent: true,
    remindersConsent: true,
    pushConsent: false,
    termsAccepted: true,
    deviceId: generateUuidV4(),
    deviceSecret: generateDeviceSecret(),
  );
}
