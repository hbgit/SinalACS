import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';

/// Onboarding do paciente por convite do ACS (RF02) e captura de
/// consentimento por finalidade (LGPD-RF02). Ver decisão §2 de
/// docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md.
class OnboardingEndpoint extends Endpoint {
  @override
  bool get requireLogin => false;

  /// Chamado pelo app do ACS. Exige sessão de ACS.
  Future<EnrollmentTokenResult> generateEnrollmentToken(
    Session session, {
    required String accessToken,
    required String patientId,
  }) async {
    final user = AlertRuntime.instance.auth.verifyToken(accessToken);
    if (user == null) {
      throw AlertPermissionException(message: 'token inválido ou expirado');
    }
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
  Future<EnrollmentResult> completeEnrollment(
    Session session, {
    required String token,
    required bool healthDataConsent,
    required bool remindersConsent,
    required bool pushConsent,
  }) async {
    final user = await AlertRuntime.instance.onboardingServiceFor(session).completeEnrollment(
          token: token,
          consents: {
            ConsentPurpose.healthDataProcessing: healthDataConsent,
            ConsentPurpose.localReminders: remindersConsent,
            ConsentPurpose.segmentedPush: pushConsent,
          },
        );

    return EnrollmentResult(
      accessToken: AlertRuntime.instance.auth.issueToken(user),
      tokenType: 'Bearer',
    );
  }
}
