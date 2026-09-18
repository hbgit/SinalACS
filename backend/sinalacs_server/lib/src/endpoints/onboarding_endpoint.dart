import 'package:serverpod/serverpod.dart';
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
  Future<EnrollmentResult> completeEnrollment(
    Session session, {
    required String token,
    required bool healthDataConsent,
    required bool remindersConsent,
    required bool pushConsent,
  }) async {
    // Consumir o convite e gravar os 3 `consent_logs` formam uma unidade só —
    // mesmo arranjo de `AlertsEndpoint.createRedAlert`. A emissão do token de
    // sessão NÃO participa: acontece depois do commit, sobre o usuário já
    // resolvido, e não depende de nenhuma escrita adicional.
    final user = await session.db.transaction((transaction) async {
      return AlertRuntime.instance
          .onboardingServiceFor(session, transaction: transaction)
          .completeEnrollment(
            token: token,
            consents: {
              ConsentPurpose.healthDataProcessing: healthDataConsent,
              ConsentPurpose.localReminders: remindersConsent,
              ConsentPurpose.segmentedPush: pushConsent,
            },
          );
    });

    return EnrollmentResult(
      accessToken: AlertRuntime.instance.auth.issueToken(user),
      tokenType: 'Bearer',
    );
  }
}
