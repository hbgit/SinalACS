import 'package:sinalacs_server/src/application/triage/triage_engine.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:test/test.dart';

typedef _Scenario = ({
  String name,
  bool chestPain,
  bool difficultyBreathing,
  bool fever,
  bool persistentVomiting,
  bool bleeding,
  bool severeWeakness,
  RiskLevel expected,
});

void main() {
  group('TriageEngine', () {
    test('classifica todas as 64 combinacoes dos seis sinais', () {
      const engine = TriageEngine();

      for (var mask = 0; mask < 64; mask++) {
        final result = engine.evaluate(
          chestPain: mask & 1 != 0,
          difficultyBreathing: mask & 2 != 0,
          fever: mask & 4 != 0,
          persistentVomiting: mask & 8 != 0,
          bleeding: mask & 16 != 0,
          severeWeakness: mask & 32 != 0,
        );
        final hasCriticalSignal = mask & (1 | 2 | 16 | 32) != 0;
        final hasModerateSignal = mask & (4 | 8) != 0;

        expect(
          result,
          hasCriticalSignal
              ? RiskLevel.red
              : hasModerateSignal
                  ? RiskLevel.yellow
                  : RiskLevel.green,
          reason: 'combinação $mask',
        );
      }
    });

    const scenarios = <_Scenario>[
      (
        name: 'verde sem sintomas',
        chestPain: false,
        difficultyBreathing: false,
        fever: false,
        persistentVomiting: false,
        bleeding: false,
        severeWeakness: false,
        expected: RiskLevel.green,
      ),
      (
        name: 'vermelho por dor no peito',
        chestPain: true,
        difficultyBreathing: false,
        fever: false,
        persistentVomiting: false,
        bleeding: false,
        severeWeakness: false,
        expected: RiskLevel.red,
      ),
      (
        name: 'vermelho por dificuldade respiratória',
        chestPain: false,
        difficultyBreathing: true,
        fever: false,
        persistentVomiting: false,
        bleeding: false,
        severeWeakness: false,
        expected: RiskLevel.red,
      ),
      (
        name: 'amarelo por febre',
        chestPain: false,
        difficultyBreathing: false,
        fever: true,
        persistentVomiting: false,
        bleeding: false,
        severeWeakness: false,
        expected: RiskLevel.yellow,
      ),
      (
        name: 'amarelo por vômito persistente',
        chestPain: false,
        difficultyBreathing: false,
        fever: false,
        persistentVomiting: true,
        bleeding: false,
        severeWeakness: false,
        expected: RiskLevel.yellow,
      ),
      (
        name: 'vermelho por sangramento',
        chestPain: false,
        difficultyBreathing: false,
        fever: false,
        persistentVomiting: false,
        bleeding: true,
        severeWeakness: false,
        expected: RiskLevel.red,
      ),
      (
        name: 'vermelho por fraqueza intensa',
        chestPain: false,
        difficultyBreathing: false,
        fever: false,
        persistentVomiting: false,
        bleeding: false,
        severeWeakness: true,
        expected: RiskLevel.red,
      ),
      (
        name: 'vermelho prevalece sobre amarelo quando há sinais mistos',
        chestPain: false,
        difficultyBreathing: false,
        fever: true,
        persistentVomiting: false,
        bleeding: false,
        severeWeakness: true,
        expected: RiskLevel.red,
      ),
    ];

    for (final scenario in scenarios) {
      test('classifica ${scenario.name}', () {
        final result = const TriageEngine().evaluate(
          chestPain: scenario.chestPain,
          difficultyBreathing: scenario.difficultyBreathing,
          fever: scenario.fever,
          persistentVomiting: scenario.persistentVomiting,
          bleeding: scenario.bleeding,
          severeWeakness: scenario.severeWeakness,
        );

        expect(result, scenario.expected);
      });
    }
  });
}
