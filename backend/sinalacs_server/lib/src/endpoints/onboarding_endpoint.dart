import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/devices/device_id_format.dart';
import 'package:sinalacs_server/src/endpoints/auth_endpoint.dart';
import 'package:sinalacs_server/src/endpoints/authenticated_endpoint.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';

/// Onboarding do paciente por convite do ACS (RF02) e captura de
/// consentimento por finalidade (LGPD-RF02). Ver decisão §2 de
/// docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md.
///
/// Postura de autenticação **mista**, e é por isso que este endpoint não
/// estende `AuthenticatedEndpoint`: `generateEnrollmentToken` exige token de
/// ACS, mas `completeEnrollment` é público por desenho — quem o chama ainda
/// não tem sessão, e o convite de uso único é a credencial. Ver a allowlist
/// em `test/unit/endpoint_auth_posture_test.dart`.
class OnboardingEndpoint extends Endpoint {
  @override
  bool get requireLogin => false;

  /// Chamado pelo app do ACS. Exige sessão de ACS.
  Future<EnrollmentTokenResult> generateEnrollmentToken(
    Session session, {
    required String accessToken,
    required String patientId,
  }) async {
    final user = authenticateToken(accessToken);
    try {
      return await AlertRuntime.instance
          .onboardingServiceFor(session)
          .generateToken(user, patientId: patientId);
    } on StateError catch (error) {
      throw AlertPermissionException(message: error.message);
    }
  }

  /// Chamado pelo app do paciente. Não exige sessão prévia — é a própria
  /// conclusão do onboarding que emite a primeira sessão.
  ///
  /// [deviceId]/[deviceSecret] são a credencial de dispositivo (C-05, RF24):
  /// o app sorteia os dois, protege o segredo com o PIN local e reapresenta
  /// o par em `auth.loginDevice` nos acessos seguintes. O `deviceId` precisa
  /// ser um UUID minúsculo de instalação (mesma regra do ACS, #94 C1); fora
  /// disso a chamada é recusada antes de consumir o convite.
  Future<EnrollmentResult> completeEnrollment(
    Session session, {
    required String token,
    required bool healthDataConsent,
    required bool remindersConsent,
    required bool pushConsent,
    required bool termsAccepted,
    required String deviceId,
    required String deviceSecret,
  }) async {
    if (!isDeviceIdFormat(deviceId)) {
      throw EnrollmentException(
        message: 'Identificador do aparelho fora do formato UUID.',
      );
    }

    // Consumir o convite, gravar os 4 `consent_logs` e criar a credencial de
    // dispositivo formam uma unidade só — mesmo arranjo de
    // `AlertsEndpoint.createRedAlert`. A emissão do token de sessão NÃO
    // participa: acontece depois do commit, sobre o usuário já resolvido, e
    // não depende de nenhuma escrita adicional.
    final user = await session.db.transaction((transaction) async {
      return AlertRuntime.instance
          .onboardingServiceFor(session, transaction: transaction)
          .completeEnrollment(
            token: token,
            consents: {
              ConsentPurpose.healthDataProcessing: healthDataConsent,
              ConsentPurpose.localReminders: remindersConsent,
              ConsentPurpose.segmentedPush: pushConsent,
              ConsentPurpose.termsOfUse: termsAccepted,
            },
            deviceId: deviceId,
            deviceSecret: deviceSecret,
          );
    });

    // Mesmo motivo do RF01 (`AuthEndpoint.verifyOtp`): a credencial de
    // dispositivo é reapresentável em `auth.loginDevice`, mas o JWT de 1 h
    // (`patientSessionLifetime`) é o que a LGPD-RT06 exige para o paciente.
    // O TTL de 15 minutos era um defeito do RF02, corrigido — ver
    // PROGRESS.md "Um defeito do RF02 que esta entrega mediu".
    return EnrollmentResult(
      accessToken: AlertRuntime.instance.auth.issueToken(
        user,
        lifetime: AuthEndpoint.patientSessionLifetime,
      ),
      tokenType: 'Bearer',
    );
  }
}
