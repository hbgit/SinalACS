/// Versão da árvore de decisão da autoavaliação (RF16, INV-02).
///
/// Vai no evento local da saída "Ligar 192" (C-04, `spec/requisitos_piloto.md`
/// §INV-03 no piloto: "evento com data, hora e versão do motor"). Quem mudar
/// as regras da árvore — no backend (`TriageEngine`) ou no aparelho — sobe
/// esta versão no mesmo commit, para que um evento antigo continue dizendo
/// qual regra o produziu.
const selfAssessmentEngineVersion = 'arvore-v1';
