import '../../domain/enums/risk_level.dart';

class TriageEngine {
  const TriageEngine();

  RiskLevel evaluate({
    required bool chestPain,
    required bool difficultyBreathing,
    required bool fever,
    required bool persistentVomiting,
    required bool bleeding,
    required bool severeWeakness,
  }) {
    if (chestPain || difficultyBreathing || severeWeakness || bleeding) {
      return RiskLevel.red;
    }

    if (fever || persistentVomiting) {
      return RiskLevel.yellow;
    }

    return RiskLevel.green;
  }
}
