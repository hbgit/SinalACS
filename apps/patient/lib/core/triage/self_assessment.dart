/// Motor de autoavaliação no aparelho (C-11, #132; RF04, RF16, INV-02).
///
/// No pilar A (sem login) a autoavaliação roda **aqui**, sem rede, sem
/// `accessToken` e sem gravar em `triage_sessions`. No pilar B (com sessão) o
/// app continua chamando `triage.evaluate`, que roda o `TriageEngine` do
/// backend e grava a sessão.
///
/// São, portanto, **duas implementações da mesma árvore de decisão fechada**, e
/// a INV-02 passa a depender de elas serem iguais. Quem prova isso é
/// `backend/sinalacs_server/test/unit/self_assessment_parity_test.dart`, que
/// importa ESTE arquivo e compara as duas nas 64 combinações dos seis sinais.
/// Ele roda no job `serverpod-backend` do CI em todo PR, seja qual for o motor
/// alterado.
///
/// **Este arquivo não pode importar nada** — nem Flutter, nem
/// `sinalacs_client`: o teste de paridade o carrega na VM do backend, que não
/// tem esses pacotes.
library;

/// Versão da árvore de decisão da autoavaliação (RF16, INV-02).
///
/// Vai no evento local da saída "Ligar 192" (C-04, `spec/requisitos_piloto.md`
/// §INV-03 no piloto: "evento com data, hora e versão do motor"). Quem mudar
/// as regras da árvore — no backend (`TriageEngine`) ou aqui — sobe esta
/// versão no mesmo commit, para que um evento antigo continue dizendo qual
/// regra o produziu.
const selfAssessmentEngineVersion = 'arvore-v1';

/// Saída do motor. Os nomes são os mesmos do `RiskLevel` do backend e do
/// cliente gerado; a tela traduz por **nome**, nunca por índice.
enum SelfAssessmentLevel { red, yellow, green }

/// Mesma árvore do `TriageEngine` do backend
/// (`backend/sinalacs_server/lib/src/application/triage/triage_engine.dart`).
///
/// Determinística: mesma entrada, mesma saída, sem estado, relógio, sorteio ou
/// campo editável (INV-02).
class SelfAssessmentEngine {
  const SelfAssessmentEngine();

  SelfAssessmentLevel evaluate({
    required bool chestPain,
    required bool difficultyBreathing,
    required bool fever,
    required bool persistentVomiting,
    required bool bleeding,
    required bool severeWeakness,
  }) {
    if (chestPain || difficultyBreathing || severeWeakness || bleeding) {
      return SelfAssessmentLevel.red;
    }

    if (fever || persistentVomiting) {
      return SelfAssessmentLevel.yellow;
    }

    return SelfAssessmentLevel.green;
  }
}
