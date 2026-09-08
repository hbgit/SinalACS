import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/triage/triage_engine.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// Motor de triagem determinístico, inspirado no Protocolo de Manchester.
///
/// Endpoint novo: o [TriageEngine] já existia e era testado, mas nunca esteve
/// exposto por HTTP — os apps replicavam a regra do lado do cliente. Publicá-lo
/// permite que a classificação passe a vir de uma única fonte.
///
/// A mesma entrada produz sempre a mesma saída, sem modelo probabilístico e sem
/// campo editável: a classificação de risco não é alterável por intervenção
/// manual no fluxo de triagem (INV-02).
class TriageEndpoint extends Endpoint {
  @override
  bool get requireLogin => false;

  static const _engine = TriageEngine();

  Future<TriageResult> evaluate(
    Session session, {
    required bool chestPain,
    required bool difficultyBreathing,
    required bool fever,
    required bool persistentVomiting,
    required bool bleeding,
    required bool severeWeakness,
  }) async {
    return TriageResult(
      risk: _engine.evaluate(
        chestPain: chestPain,
        difficultyBreathing: difficultyBreathing,
        fever: fever,
        persistentVomiting: persistentVomiting,
        bleeding: bleeding,
        severeWeakness: severeWeakness,
      ),
    );
  }
}
