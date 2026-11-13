# PR #161 (C-11, autoavaliação local): parecer e comentários a publicar

Textos da revisão da PR #161 (`feat/issue-132-autoavaliacao-local`, autor `vinimartinsufrr`, base `feat/issue-127-pedido-de-contato-192` — empilhada sobre a #160 —, commit `15fd57b`). Diff revisado: `gh pr diff 161` (só a C-11). Publicar só depois da aprovação do dono, com `gh pr review` (parecer) e `gh api repos/hbgit/SinalACS/pulls/161/comments` (inlines, um por chamada). Log: `pr161-verificacao.log` no scratchpad da sessão.

Veredito proposto: **Comentar (pedidos antes do merge)** (`gh pr review --comment`). Não há bloqueante: o motor do aparelho é idêntico ao do backend nas 64 combinações e a paridade reprova com mutação dos dois lados. O pedido principal é um teste da **ligação** entre as respostas da tela e o motor, que hoje nenhum teste prende (mutação conferida abaixo). O segundo é tirar contagens de testes do `PROGRESS.md`.

---

## Parecer

Revisei a PR contra a issue #132, a INV-02 (determinismo da triagem, mesma entrada → mesmo resultado, nunca alterável) e a regra do escopo (pilar A sem conta e sem rede, RNF07/RNF09). Os três critérios de aceite estão atendidos:

| Critério da #132 | Evidência |
|---|---|
| Sem login, o resultado é o mesmo do motor do backend nas 64 combinações | `backend/sinalacs_server/test/unit/self_assessment_parity_test.dart`: laço `mask` 0..63, comparação por `name` (não por índice) e `expect(seen, {'red','yellow','green'})` — dois motores constantes não passam. O segundo teste prende que os nomes de `SelfAssessmentLevel` e `RiskLevel` são os mesmos, o que protege o `RiskLevel.values.byName` da tela. A tela usa esse motor (`_evaluateOnDevice`, `apps/patient/lib/app/app.dart:1632`). |
| Nenhuma chamada de rede no pilar A | `apps/patient/test/local_self_assessment_test.dart`: `_NetworkSentinel` registra **qualquer** método de `PatientBackend` por `noSuchMethod` e lança; testes 1 e 3 afirmam a lista inalterada. `PatientBackend` é o único caminho de rede do app (`grep` por `HttpClient`/`http`/`WebSocket`/`mqtt` em `apps/patient/lib`: nada). |
| A paridade roda no CI a cada mudança de qualquer motor | `.github/workflows/ci.yml:121`: `dart test` sem filtro em `backend/sinalacs_server`, job `serverpod-backend` (check obrigatório), sem filtro de caminho (garantido por `ci_invariants.sh`). |

**O que rodei em Linux** (worktree limpo da branch, `15fd57b`):

- **Mutação 1, motor do app:** tirar `bleeding` do vermelho em `self_assessment.dart` → `dart test test/unit/self_assessment_parity_test.dart` reprova (exit 1) na **combinação 16**, `Expected: 'red' / Actual: 'green'`. Revertido com `git checkout --`.
- **Mutação 2, motor do backend:** tirar `persistentVomiting` do amarelo em `triage_engine.dart` → reprova na **combinação 8**. Revertido. A paridade pega mudança dos dois lados.
- **Mutação 3, ligação da tela:** em `_evaluateOnDevice`, passar a resposta de falta de ar no lugar da de dor no peito → `flutter test test/local_self_assessment_test.dart` **passa** (5/5). Revertido. Ver Inline 1.
- `dart test test/unit/self_assessment_parity_test.dart test/unit/triage_engine_test.dart`: `+11: All tests passed!`.
- `dart analyze` no backend: 98 issues, nenhuma nos arquivos da PR (o `ignore: avoid_relative_lib_imports` funciona).
- Paciente: `flutter analyze` só com o aviso `asset_directory_does_not_exist` de `assets/certs/` (diretório gitignorado, não é da PR); `flutter test` completo: `+355: All tests passed!`.
- `bash scripts/qa/check_documentation_links.sh`: só o `graphify-out` ausente em `AGENTS.md`, gitignorado, já assim antes.

**Pontos que conferi e aprovo:**

- `self_assessment.dart` é Dart puro, sem nenhum `import` (só `library;`), com a árvore idêntica à do `TriageEngine` linha a linha; o comentário explica por que não pode importar nada.
- No modo local, o único `BackendScope.of` do `_TriageScreenState` fica no ramo `false` do ternário; `Call192OrientationScreen` também não lê o `BackendScope` (só `Call192Scope`). Nada no modo local depende de servidor.
- Resultado local: o texto diz que nada foi enviado e o botão é "Concluir" (teste 2 afirma também a ausência de "solicitação" e "entrará em contato"); o vermelho abre a orientação "Ligar 192" da C-04, grava `call192OrientationShown` com `selfAssessmentEngineVersion` e recomeça do passo 1 sem guardar as respostas (teste 3).
- INV-02 na tela: nenhum caminho altera o resultado — `_risk` só é escrito com a saída do motor, não há campo editável, e o vermelho nunca vira cartão.
- O `ignore: avoid_relative_lib_imports` está justificado em comentário, e mover o arquivo do app quebra a compilação do teste (o job fica vermelho, não verde em silêncio).
- `AGENTS.md` e `apps/CLAUDE.md` registram a exceção à regra "sem regra de risco no cliente" e a obrigação de mudar os dois motores no mesmo PR com `selfAssessmentEngineVersion` novo. `spec/lgpd_design.md` corrige a frase que dizia que a autoavaliação era enviada ao servidor.
- Pilar B inalterado: o teste 5 prova que, com sessão, a triagem continua indo a `triage.evaluate`.

**Pedidos (nesta PR):** teste da ligação respostas → motor (Inline 1); contagens fora do `PROGRESS.md` (Inline 2).

**Sugestões (opcionais):** prender `selfAssessmentEngineVersion` à tabela das 64 saídas (Inline 4); frase "Classificação feita pelo protocolo da equipe de saúde" no modo local (Inline 5); dois comentários de `app.dart` que ficaram desatualizados (Geral).

**Registros:** import relativo aprovado (Inline 3); o botão novo e os testes 2 e 5 precisam de ajuste quando a #156 e a #157 entrarem (Geral).

---

## Inline 1 — apps/patient/lib/app/app.dart:1634 — pedido

A paridade prova que o **motor** do aparelho é igual ao do backend, mas nada prova que a **tela** entrega a resposta certa a cada parâmetro. Conferi por mutação: trocando esta linha por `chestPain: _answers[TriageSymptom.difficultyBreathing] ?? false,`, a pessoa que responde só "dor no peito" recebe **verde** no modo local, e `test/local_self_assessment_test.dart` continua 5/5 verde. A amostra do teste 4 cobre só febre, vômitos e nenhum sinal; dor no peito, falta de ar e fraqueza nunca são respondidos sozinhos.

Como a INV-02 agora depende também desta ligação, peço um teste que responda cada sinal sozinho (mais "nenhum"; hoje faltam dor no peito, falta de ar e fraqueza, que nenhum teste responde isolados) e compare a saída da tela com `SelfAssessmentEngine` — o vermelho aparece como `call_192_title`, amarelo e verde como o rótulo do cartão. São sete execuções curtas e pegam qualquer resposta perdida ou trocada de classe. Se quiser ir além, as 64 combinações com o motor como oráculo também cabem num `testWidgets`.

---

## Inline 2 — PROGRESS.md:1950 — pedido

O `CONTRIBUTING.md` pede para não gravar contagens de testes nos documentos ("elas envelhecem a cada PR"). Sugiro tirar "355 testes", "(5)" e "4 dos 5" desta linha e deixar as contagens só no corpo da PR, por exemplo:

> - **Provas.** Paciente: `flutter analyze` sem avisos novos e suíte verde. `test/local_self_assessment_test.dart` usa um backend que registra **qualquer** método chamado: nenhum na autoavaliação local; forçar o modo remoto na tela reprova o teste. Backend: `dart analyze` sem issue nova; o teste de paridade e o `triage_engine_test.dart` verdes.

---

## Inline 3 — backend/sinalacs_server/test/unit/self_assessment_parity_test.dart:20 — registro

Aprovo o import relativo: é o que permite ao job `serverpod-backend` compilar o motor do app sem trazer Flutter para o backend, e o comentário acima justifica o `ignore`. Conferi as duas pontas por mutação: tirar `bleeding` do vermelho no app reprova na combinação 16, e tirar `persistentVomiting` do amarelo no backend reprova na combinação 8. Fica registrado que mover ou renomear `apps/patient/lib/core/triage/self_assessment.dart` quebra a compilação deste teste — é o comportamento desejado, e quem mover o arquivo atualiza este caminho no mesmo PR.

---

## Inline 4 — backend/sinalacs_server/test/unit/self_assessment_parity_test.dart:60 — sugestão

A paridade não pode pegar uma mudança feita **igual** nos dois motores (é para isso que ela existe), e é justamente nesse caso que `selfAssessmentEngineVersion` tem de subir — senão o evento local "Ligar 192" passa a dizer `arvore-v1` para uma regra que não é a v1. Uma forma barata de prender a versão, sem versão no backend: guardar a tabela das 64 saídas por versão e exigir que a versão corrente bata.

```dart
// Cada versão publicada da árvore e as 64 saídas dela (máscara 0..63; r/y/g).
const _arvores = {
  'arvore-v1': 'grrryrrryrrryrrr' 'rrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr',
};

test('a versão do motor corresponde à árvore em vigor', () {
  final saidas = [
    for (var mask = 0; mask < 64; mask++)
      const TriageEngine().evaluate(/* mesmos seis bits do laço acima */).name[0],
  ].join();
  expect(_arvores[app.selfAssessmentEngineVersion], saidas,
      reason: 'a árvore mudou: suba selfAssessmentEngineVersion e acrescente a linha nova');
});
```

Mudou a árvore sem subir a versão, o teste reprova; a troca da tabela fica visível no diff para quem revisa.

---

## Inline 5 — apps/patient/lib/app/app.dart:1801 — sugestão

No modo local esta frase continua aparecendo: "Classificação feita pelo protocolo da equipe de saúde." No pilar A não há equipe nem sessão, o projeto não tem vínculo com unidade de saúde, e o RF04 do piloto pede "nunca 'classificação de risco'". Como esta PR já troca a frase de orientação quando `local` é `true`, sugiro esconder esta também no modo local (ou trocar por algo como "Orientação educativa, calculada neste aparelho."). O texto final das saídas é da C-08 (#130); se preferir deixar para lá, basta citar esta frase na #130.

---

## Geral — comentários desatualizados e convivência com a #156 e a #157

**Comentários em `app.dart` fora do diff (sugestão).** Dois comentários perto da tela ficaram desatualizados com a C-11 e podem enganar quem mexer na tela depois:

- `app.dart:1554-1556`, no `enum TriageSymptom`: diz que calcular risco no cliente era "duas regras de risco no mesmo produto, o que viola o determinismo exigido pelo PRD (INV-02)". Agora existem dois motores por desenho, com paridade provada; vale citar a exceção e o teste de paridade.
- `app.dart:1579-1581`, em `_risk`: "Risco devolvido pelo servidor" e "Não existe cálculo de risco neste arquivo". No modo local o risco vem do aparelho. A segunda frase continua verdadeira (o cálculo está em `self_assessment.dart`), mas vale dizer de onde vem `_risk` em cada modo.

**Convivência com a #156 e a #157 (registro, para quem fizer o rebase).** O botão "Autoavaliação (sem cadastro)" entra no mesmo bloco da tela de entrada em que a #156 acrescenta "Biblioteca de saúde (sem cadastro)" (`login_library_button`), e a #157 reescreve essa tela (convite QR + PIN): o bloco `if (_step == _LoginStep.credenciais) ...[...]` deixa de existir e vira `_camposDoConvite()` (sem credencial no aparelho) ou `_camposDoPin()` (com credencial). Para o botão sobreviver às duas:

- Manter a chave `login_self_assessment_button` e colocar o botão **fora** das duas ramificações da #157, ao lado do botão da biblioteca, para aparecer com ou sem credencial: o pilar A não pode depender de conta, nem de lembrar o PIN (RNF07/RNF09).
- `test/local_self_assessment_test.dart` depende do login antigo: o teste 2 espera `cpf_field` depois de "Concluir" (linha 79), e o teste 5 entra por CPF + OTP (linhas 135–141). Com a #157 os dois precisam mudar — o 2 para uma chave que exista nas duas versões da entrada (por exemplo, a própria `login_self_assessment_button`), o 5 para o login por PIN.

---

## Issues de continuação

nenhuma
