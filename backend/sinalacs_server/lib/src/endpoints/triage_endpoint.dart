import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/triage/triage_session_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';

/// Motor de triagem determinístico, inspirado no Protocolo de Manchester.
///
/// A mesma entrada produz sempre a mesma saída, sem modelo probabilístico e sem
/// campo editável: a classificação de risco não é alterável por intervenção
/// manual no fluxo de triagem (INV-02).
///
/// Passou a exigir `accessToken` e a gravar em `triage_sessions`: antes disso o
/// endpoint era uma função pura, respondia sem autenticação alguma, e o
/// resultado clínico era descartado — não havia prontuário, nem vínculo com o
/// paciente, nem auditoria da triagem (RF17).
class TriageEndpoint extends Endpoint {
  @override
  bool get requireLogin => false;

  Future<TriageResult> evaluate(
    Session session, {
    required String accessToken,
    required bool chestPain,
    required bool difficultyBreathing,
    required bool fever,
    required bool persistentVomiting,
    required bool bleeding,
    required bool severeWeakness,
  }) async {
    final user = AlertRuntime.instance.auth.verifyToken(accessToken);
    if (user == null) {
      throw AlertPermissionException(message: 'token inválido ou expirado');
    }

    try {
      final risk = await AlertRuntime.instance
          .triageSessionServiceFor(session)
          .evaluateAndRecord(
            user: user,
            chestPain: chestPain,
            difficultyBreathing: difficultyBreathing,
            fever: fever,
            persistentVomiting: persistentVomiting,
            bleeding: bleeding,
            severeWeakness: severeWeakness,
          );
      return TriageResult(risk: risk);
    } on TriageAuthorizationException catch (error) {
      throw AlertPermissionException(message: error.message);
    }
  }
}
