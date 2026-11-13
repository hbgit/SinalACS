# PR #160 (C-04): parecer e comentários a publicar

Textos da revisão da PR #160 (`feat/issue-127-pedido-de-contato-192`, autor `vinimartinsufrr`, base `develop`, commit `16b33b2`). Publicar só depois da aprovação do dono, com `gh pr review` (parecer) e `gh api repos/hbgit/SinalACS/pulls/160/comments` (inlines, um por chamada). Plano: `2026-11-13-prs-156-163-revisao.md`.

Veredito proposto: **Comentar (pedidos antes do merge)** (`gh pr review --comment`). Não há bloqueante: a INV-03 está preservada e a orientação "Ligar 192" não chama o backend. Os três pedidos são pequenos: o rótulo de risco que ainda aparece ao lado do "Pedido de contato" em "Meus dados", a ordem da orientação com fonte grande e a contagem de testes no `PROGRESS.md`. A #161 está empilhada nesta PR; um ajuste aqui pede rebase lá.

---

## Parecer

Revisei a PR contra a issue #127, o escopo (`spec/requisitos_piloto.md` §INV-03 no piloto) e as duas regras que não podem ceder: o pedido enviado nunca some (INV-03) e o participante não vê cor nem rótulo clínico. Os quatro critérios de aceite estão atendidos e provados por teste:

| Critério da #127 | Evidência |
|---|---|
| "Ligar 192" aparece antes de qualquer pedido de contato | `test/call_192_test.dart`, "\"Ligar 192\" aparece antes do pedido de contato": compara os retângulos (`call_192_button.bottom < panic_button.top`) e confere que o discador recebe `192`. |
| A saída "Ligar 192" exige escolha explícita para fechar e grava um evento local cifrado | "não fecha pelo voltar do sistema; só pela escolha explícita" (`handlePopRoute`, sem `BackButton`/`CloseButton`); "mostra a orientação, grava o evento local…" (tipo, UTC, `selfAssessmentEngineVersion`); `test/events/sqflite_local_event_log_test.dart` prova a tabela no banco da #136. |
| O status não usa "Atendido" como promessa | `patient_app_mvp_test.dart`, "pedido concluído pelo agente aparece como \"Encerrado\", nunca \"Atendido\"", e "nenhum rótulo de urgência nem promessa de atendimento na tela". |
| INV-03 segue verde; a saída 192 grava o evento e não chama `alerts.createRedAlert` | Os testes de INV-03 de `patient_app_mvp_test.dart` (idempotência em duas tentativas, localização de reserva para cada `LocationUnavailableReason`, `liveRegion`) só trocaram textos de busca; a lógica e as asserções sobre `idempotencyKeys`/`locationHashes` são as mesmas. A chave continua `_attemptKey ??= newIdempotencyKey()`, sem mudança no diff. Escrevi um teste extra (abaixo) com um backend que registra **qualquer** chamada: a orientação, o "Ligar 192" e o fechar não fazem nenhuma. |

**O que rodei em Linux** (Flutter estável, worktree limpo da branch, `16b33b2`):

- `flutter analyze` em `apps/patient`: só o aviso `asset_directory_does_not_exist` de `assets/certs/`, que é o diretório gitignorado criado por `scripts/dev/sync_dev_ca.sh`; não é desta PR.
- `flutter test` completo: 350 passam.
- `bash scripts/qa/check_documentation_links.sh`: nada novo (o único "ausente" é `graphify-out`, gitignorado, em `AGENTS.md`).
- `grep -rn "Atendido\|Risco:" apps/patient/lib`: sobram `app.dart:1715–1725` (`_TriageResult`, amarelo e verde, declarado como C-08), `app.dart:2150` ("Atendido" de um pedido LGPD do titular, não do pedido de contato, correto), `app.dart:2343` ("Meus dados", ver Inline 1) e dois comentários.
- Três testes que escrevi em `test/call_192_test.dart` (não commitados; diff no Geral): os três passam, e a suíte completa com eles fica em 353.
- CI: 9 de 9 verdes, inclusive `android-e2e` (`gh pr checks 160`, consultado em 2026-11-13).

**Pontos que conferi no código e aprovo:**

- INV-03: o envio continua pelo mesmo `alerts.createRedAlert`, com a mesma chave por confirmação e a mesma reserva de localização. Só mudou o que a pessoa vê.
- `triage.evaluate` no backend (`TriageSessionService.evaluateAndRecord`) não cria alerta; o único caminho para um pedido é a aba Contato. A orientação é empurrada só depois que a avaliação volta.
- Migração v1 → v2: só `CREATE TABLE local_events`, ligada a `onUpgrade` nos dois caminhos de abertura (cifrado e o de teste); o v1 escrito no teste é igual ao `_create` de `develop`. `onDowngrade` continua `onDatabaseDowngradeDelete`.
- `local_events` tem só `id`, `kind`, `occurred_at` (UTC) e `engine_version` (teste de `PRAGMA table_info`); nenhuma resposta da autoavaliação. `deleteEverything()` leva a trilha junto. Um tipo desconhecido é ignorado na leitura, e isso tem teste.
- A gravação do evento não segura a tela, e o erro é descartado sem log (a causa pode carregar material da custódia, como na #136). A orientação abre e fecha igual com o banco quebrado, e isso tem teste.
- `selfAssessmentEngineVersion = 'arvore-v1'` nasce aqui, com a regra de subir junto com a árvore. A #161 reaproveita a constante.
- Manifesto: `<queries><intent><action android:name="android.intent.action.DIAL"/><data android:scheme="tel"/>`, sem `CALL_PHONE`. `tel:` abre o discador e nunca liga sozinho; quando o discador não abre, a pessoa vê um aviso para ligar 192 pelo telefone.
- `url_launcher` ^6.3.0, a mesma versão do ACS, registrado em `spec/stack.md`. O `apps/patient/pubspec.lock` já era versionado em `develop`; a PR só acrescenta os pacotes `url_launcher*`.
- `PopScope(canPop: false)` com `automaticallyImplyLeading: false` e o botão "Fechar esta orientação" sempre presente: aceito. O fechamento explícito é o que a §INV-03 item 2a pede, e a saída existe.
- Botão "Pedir contato ao agente" sem `Semantics` em volta (um nó, nome = texto visível) e sem `PatientColors.danger`.
- Rótulos de status: mapa servidor → texto sem promessa. "Repassado à coordenação do piloto" usa exatamente a expressão da #158 (C-06).
- `docs/telas-paciente.md`: a captura `01-emergencia.png` foi marcada como anterior à C-04, sem captura inventada.

**Pedidos (pequenos, nesta PR):** "Meus dados" (Inline 1); ordem da orientação com fonte grande (Inline 2); contagem no `PROGRESS.md` (Inline 3).

**Sugestões (opcionais):** cor do estado do pedido (Inline 4); consentimento na prova da migração (Inline 5); levar os três testes da revisão (Geral).

**Registros (só documentam):** rótulo "Repassado…" sem escritor (Inline 6); disciplina da versão do motor (Inline 7); o que fica para C-08/C-10 e para o lado do agente (Geral).

---

## Inline 1 — apps/patient/lib/app/app.dart:2223 — pedido

A linha já mostrava "· Risco: Vermelho" antes desta PR ("Alerta de urgência · Risco: Vermelho"); com o novo rótulo, o histórico de "Meus dados" passa a dizer **"Pedido de contato · Risco: Vermelho"** (linha 2343, `'${_sourceLabel(event.source)} · Risco: ${_riskLabel(event.riskLevel)}'`). O teste `mostra os consentimentos e o histórico de risco…` (`patient_app_mvp_test.dart:1830–1831`) passou a fixar essa combinação.

O pedido de contato não é uma classificação: o servidor grava `riskLevel = red` em todo pedido porque o envio é o `createRedAlert`. Para o participante, a linha diz que pedir contato o classificou como vermelho. É o rótulo clínico que a C-04 tira do Status e da aba Contato, voltando por outra tela.

Proposta mínima: para `source == 'alert'`, mostrar só "Pedido de contato" e a data, sem o risco, e trocar o `expect(find.textContaining('Vermelho'), findsOneWidget)` por `findsNothing`. O risco da triagem (`source == 'triage'`) fica como está até a C-08. Se preferir deixar "Meus dados" inteiro para a C-08, peço só uma linha no `PROGRESS.md` (seção "Abertos e limites") dizendo que a combinação existe, e a issue de continuação 1 abaixo.

---

## Inline 2 — apps/patient/lib/app/call_192.dart:146 — pedido

Com fonte a 200 %, numa tela de 360×640, o botão "Ligar 192" fica abaixo do parágrafo explicativo e só aparece depois de rolar. Medi com um teste temporário: o `ListView` nem chega a construir o `call_192_button` sem rolar (o parágrafo termina em y = 1092 numa viewport de 584).

A fonte de teste do Flutter é mais larga que a Roboto, então no aparelho a distância é menor. Mesmo assim, a ação que a orientação existe para provocar não deveria depender de rolagem para quem usa fonte grande. Pela §INV-03 item 2a, a orientação com o botão de discagem é exibida "antes de qualquer outra ação".

Proposta: subir `const Call192Button()` para logo depois do título e deixar o parágrafo e o "Se não conseguir ligar…" abaixo dele. Os testes atuais continuam verdes, porque nenhum depende da ordem dentro da orientação. Um teste a 2.0× que afirme `getRect(call_192_button).bottom <= altura da tela` sem rolar prende a correção.

---

## Inline 3 — PROGRESS.md:1935 — pedido

O `CONTRIBUTING.md` (linha 250) pede para não gravar contagens de testes nos documentos, porque "elas envelhecem a cada PR". Sugiro trocar "`flutter analyze` sem avisos e 350 testes (eram 334)." por "`flutter analyze` sem avisos e suíte verde." e manter as contagens só no corpo da PR. Foi o mesmo pedido feito na #155.

---

## Inline 4 — apps/patient/lib/app/app.dart:1507 — sugestão

O estado do pedido ("Pedido enviado ao agente…", "Enviando pedido…") continua com `context.patientRisk.accentOnSurface`. Pelo `patient_theme.dart`, `accent` "só pode significar `RiskLevel`", e no `_TriageResult` esse tom é o do verde. O tema também usa esse tom como semente da marca, então a leitura não é inequívoca. Como a PR tira toda cor clínica da aba, `Theme.of(context).colorScheme.onSurface` em negrito fecha a questão sem perder contraste. Opcional.

---

## Inline 5 — apps/patient/test/events/sqflite_local_event_log_test.dart:111 — sugestão

O texto da PR e o `PROGRESS.md` dizem que a migração preserva lembretes **e consentimento**, mas o teste só insere e lê um lembrete. Duas linhas fecham a prova: `await v1.insert('consent_preferences', {'purpose': 'reminders', 'granted': 1});` antes do `close()`, e a leitura de volta depois do `open()`. O mesmo vale para uma linha de `local_meta`, que guarda o estado do banco da #136.

---

## Inline 6 — apps/patient/lib/app/app.dart:2653 — registro

Conferi o texto contra a #158 (C-06), revisada em paralelo: lá o texto é "Ligar para a coordenação do piloto", "a pedido da coordenação do piloto". A expressão é a mesma, então as duas PRs juntas não divergem. O estado `escalated` não tem escritor hoje: escalonar mantém `pending`, pela #44. O comentário diz isso, e está certo trocar o "Encaminhado para o SAMU" antigo, que prometia o que o projeto não faz. Nada a mudar.

---

## Inline 7 — apps/patient/lib/core/triage/self_assessment.dart:8 — registro

Só para deixar escrito: a constante nasce aqui, mas hoje a árvore que produz o vermelho é a do backend (`TriageEngine`); a #161 (C-11, empilhada nesta) traz o motor para o aparelho e reaproveita `selfAssessmentEngineVersion`. A regra do comentário ("quem mudar as regras… sobe esta versão no mesmo commit") depende de disciplina enquanto não houver teste que a prenda; o teste de paridade da #161 é o lugar natural para isso. Nada a mudar aqui.

---

## Geral — sugestão e registros

**Sugestão: levar os três testes da revisão.** Escrevi em `apps/patient/test/call_192_test.dart` (worktree local, não commitado) e todos passam:

1. `'a 200% de fonte, "Fechar esta orientação" continua visível e tocável'`: tela de 360×640 e `textScaleFactor` 2.0 aplicados depois do login, que fica fora do escopo. Rola até o botão de fechar e afirma que ele fica na tela, com 48dp ou mais de altura, que o toque fecha a orientação e que não há exceção de layout. **Verde.**
2. `'a orientação tem Semantics de cabeçalho e o botão de fechar tem rótulo'`: o título é `isHeader` e contém "Ligue 192"; o fechar tem rótulo "Fechar esta orientação", papel de botão e ação de toque. **Verde.**
3. `'a orientação e o fechar não fazem chamada nenhuma ao backend'`: um `_RecordingBackend extends FakePatientBackend` registra todos os 19 métodos de `PatientBackend`. Depois da orientação, do "Ligar 192" e do fechar, a lista de chamadas é a mesma de quando a avaliação voltou. **Verde.**

Posso enviar o diff (cerca de 230 linhas) se quiser incluí-los. O terceiro prova o critério "não chama o backend" de forma mais forte que o `idempotencyKeys` vazio atual.

**Registros:**

- **Fora da PR, como declarado:** amarelo e verde ainda mostram "Risco: …" e prometem uma solicitação que não é enviada (C-08, #130). O ramo vermelho de `_TriageResult` ficou inalcançável e sem a promessa antiga. A retenção de 30 dias e "Apagar meus dados" da trilha são da C-10 (#131).
- **Não verificado no aparelho**, como a própria PR diz: a cifra do arquivo com a tabela nova, o voltar preditivo do Android 14+ com `PopScope` e o discador real. O `integration_test/full_journey_test.dart` foi ajustado e não roda na CI (o smoke do `android-e2e` não depende desses textos); não o rodei por falta de emulador.
- **`docs/telas-paciente.md:23`** ainda termina com "A confirmação de recebimento pela equipe aparece na aba Status". Pelo resto da PR seria "pelo agente". Fica junto com o refazer da captura.
- **Lado do agente:** o ACS e o backoffice continuam chamando o pedido de "alerta vermelho" / "Risco: Vermelho". Como a PR diz, a #127 não pede isso; deixo como issue para o dono decidir (abaixo).

---

## Issues de continuação

### Issue 1 — "Meus dados" do paciente: pedido de contato sem rótulo de risco (C-04/C-08, continuação)

> Abrir só se o Inline 1 não for resolvido na própria PR #160.

**Objetivo**
O histórico de "Meus dados" sempre mostrou "· Risco: Vermelho" ao lado do alerta; desde a C-04 (#127, PR #160) a linha diz "Pedido de contato · Risco: Vermelho", o que contradiz a própria C-04. Isso acontece porque o servidor grava `riskLevel = red` em todo pedido feito por `alerts.createRedAlert`. Para o participante, a linha diz que pedir contato o classificou como vermelho, que é o rótulo clínico que a C-04 tirou do Status e da aba Contato.

**Critério de aceite**
- [ ] Em "Meus dados", uma entrada de origem `alert` mostra "Pedido de contato" e a data, sem "Risco:" e sem cor clínica.
- [ ] O teste de widget de "Meus dados" afirma a ausência de "Vermelho" para a origem `alert`.
- [ ] A origem `triage` segue a decisão da C-08 (#130).

**Referências**
IDs: C-04, C-08, RF05, P-09
Escopo: https://github.com/hbgit/SinalACS/blob/develop/spec/requisitos_piloto.md#inv-03-no-piloto
Origem: revisão da PR #160

### Issue 2 — Lado do agente e backoffice: "alerta vermelho" vira "pedido de contato" (decisão do dono)

**Objetivo**
A C-04 (#127) mudou só o app do paciente. O app do ACS e o backoffice continuam chamando o pedido de contato de "alerta vermelho" e mostrando "Risco: Vermelho". O participante não vê esses textos, mas o agente participante vê, e a fila prioriza o pedido como risco máximo. Cabe ao dono decidir se o piloto renomeia isso, e como, sem mexer na entrega com ACK, na reserva HTTP e no escalonamento (INV-03).

**Critério de aceite**
- [ ] Decisão registrada (manter ou renomear) em `docs/escopo/`.
- [ ] Se renomear: textos do ACS e do backoffice trocados, com testes de widget; nenhuma mudança em `alerts.*`, `AlertQueue` ou na semântica de ACK, reserva e escalonamento.

**Referências**
IDs: C-04, P-09, INV-03, RF19
Origem: revisão da PR #160 (seção "Fora deste PR" do corpo da PR)

### Issue 3 — Refazer a captura `docs/screenshots/patient/01-emergencia.png` depois da C-04

**Objetivo**
A captura da aba Contato em `docs/telas-paciente.md` ainda mostra o botão circular "EMERGÊNCIA", de antes da C-04 (#127). A PR marcou a imagem como antiga. Falta refazê-la no emulador com dados sintéticos e incluir uma captura da orientação "Ligue 192 (SAMU) agora".

**Critério de aceite**
- [ ] `01-emergencia.png` substituída pela aba Contato atual ("Ligar 192" acima de "Pedir contato ao agente").
- [ ] Captura nova da orientação "Ligar 192", referenciada na seção "Triagem rápida".
- [ ] A frase "confirmação de recebimento pela equipe" passa a "pelo agente".
- [ ] Só dados sintéticos.

**Referências**
IDs: C-04
Origem: revisão da PR #160
