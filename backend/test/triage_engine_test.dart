import 'package:sinalacs_backend/src/application/triage/triage_engine.dart';
import 'package:sinalacs_backend/src/domain/enums/risk_level.dart';
import 'package:test/test.dart';

void main() {
  group('TriageEngine', () {
    test('classifica como vermelho quando há sinais críticos', () {
      final result = const TriageEngine().evaluate(
        chestPain: true,
        difficultyBreathing: false,
        fever: false,
        persistentVomiting: false,
        bleeding: false,
        severeWeakness: false,
      );

      expect(result, RiskLevel.red);
    });

    test('classifica como amarelo quando há sintomas moderados', () {
      final result = const TriageEngine().evaluate(
        chestPain: false,
        difficultyBreathing: false,
        fever: true,
        persistentVomiting: false,
        bleeding: false,
        severeWeakness: false,
      );

      expect(result, RiskLevel.yellow);
    });

    test('classifica como verde quando não há sinais de urgência', () {
      final result = const TriageEngine().evaluate(
        chestPain: false,
        difficultyBreathing: false,
        fever: false,
        persistentVomiting: false,
        bleeding: false,
        severeWeakness: false,
      );

      expect(result, RiskLevel.green);
    });
  });
}
