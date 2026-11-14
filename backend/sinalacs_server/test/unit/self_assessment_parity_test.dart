// Paridade entre os dois motores da autoavaliação (C-11, #132; INV-02).
//
// O app do paciente roda a árvore no aparelho no pilar A (sem login, sem rede);
// o backend roda o `TriageEngine` no pilar B (`triage.evaluate`). As duas
// implementações têm de dar o mesmo resultado para as 64 combinações dos seis
// sinais. Este teste importa o motor do app por caminho relativo — por isso o
// arquivo do app é Dart puro, sem nenhum import — e roda em todo PR no job
// `serverpod-backend` do CI, seja qual for o motor que mudou.
//
// Se o arquivo do app mudar de lugar, este import quebra a compilação do teste
// (e o job fica vermelho): a paridade nunca deixa de ser verificada em silêncio.
import 'package:sinalacs_server/src/application/triage/triage_engine.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:test/test.dart';

// O `lib/` é o do app do paciente, outro pacote: não há `package:` que o
// alcance daqui sem trazer o Flutter para o backend. O caminho relativo é o
// ponto do teste.
// ignore: avoid_relative_lib_imports
import '../../../../apps/patient/lib/core/triage/self_assessment.dart' as app;

void main() {
  test('o motor do aparelho e o do backend dão o mesmo resultado nas 64 combinações', () {
    const server = TriageEngine();
    const device = app.SelfAssessmentEngine();
    final seen = <String>{};

    for (var mask = 0; mask < 64; mask++) {
      final chestPain = mask & 1 != 0;
      final difficultyBreathing = mask & 2 != 0;
      final fever = mask & 4 != 0;
      final persistentVomiting = mask & 8 != 0;
      final bleeding = mask & 16 != 0;
      final severeWeakness = mask & 32 != 0;

      final RiskLevel expected = server.evaluate(
        chestPain: chestPain,
        difficultyBreathing: difficultyBreathing,
        fever: fever,
        persistentVomiting: persistentVomiting,
        bleeding: bleeding,
        severeWeakness: severeWeakness,
      );
      final actual = device.evaluate(
        chestPain: chestPain,
        difficultyBreathing: difficultyBreathing,
        fever: fever,
        persistentVomiting: persistentVomiting,
        bleeding: bleeding,
        severeWeakness: severeWeakness,
      );

      // Por nome, como o app traduz: um índice reordenado passaria despercebido.
      expect(actual.name, expected.name, reason: 'combinação $mask');
      seen.add(expected.name);
    }

    // As três saídas aparecem: uma árvore que devolvesse sempre o mesmo nível
    // nos dois lados também seria "igual".
    expect(seen, {'red', 'yellow', 'green'});
  });

  test('os níveis do aparelho têm os mesmos nomes do RiskLevel do backend', () {
    expect(
      {for (final level in app.SelfAssessmentLevel.values) level.name},
      {for (final level in RiskLevel.values) level.name},
    );
  });
}
