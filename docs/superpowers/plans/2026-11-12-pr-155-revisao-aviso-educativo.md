# PR #155 (C-02, aviso educativo) — Plano de Revisão e Comentário

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Revisar a PR #155 (`feat/c-02-aviso-educativo`, autor `Rosialdo`, base `develop`) contra a issue #125 e o escopo, e publicar no GitHub um parecer com comentários inline, depois de o dono aprovar o texto.

**Architecture:** Três fases: (1) verificação mecânica em Linux (testes, analyze, links, critérios de aceite); (2) leitura guiada do diff com uma lista fechada de pontos a conferir, cada um com arquivo, linha e resultado esperado; (3) redação dos comentários num arquivo de rascunho, checkpoint do dono e publicação com `gh`. Nada é empurrado para a branch do autor: achados viram comentários, não commits.

**Tech Stack:** `gh` CLI (pr view/diff/review, `gh api` para comentários inline), Flutter 3.x (`flutter test`, `flutter analyze`), `bash scripts/qa/check_documentation_links.sh`, git worktree.

**Spec:** issue #125 (critérios de aceite), corpo da PR #155, `spec/escopo_projeto.md#aviso-educativo` (texto canônico e regra), `spec/requisitos_piloto.md` linha RF21, `docs/escopo/mudancas-de-codigo-recomendadas.md` linha C-02, comentário do dono na #125 de 2026-11-04 (reaproveitar `LocalProtectionNotice`).

## Levantamento já feito (não refazer)

| Fato | Valor |
|---|---|
| Branch | `feat/c-02-aviso-educativo`, 1 commit (`eb78c64`), base = `develop` (`7511255`), 0 atrás |
| CI | 9/9 jobs verdes em 2026-11-08, inclusive `android-e2e`; GitGuardian verde |
| Arquivos | 15 (+1116/−6): 2× `lib/core/legal/educational_notice.dart`, 2× `lib/app/educational_notice_screens.dart`, 2× `app.dart`, 2× `test/educational_notice_test.dart`, 4× `flutter_test_config.dart` (novos), `geofence_gps_e2e.dart`, `android_backup_manifest_test.dart`, `PROGRESS.md` |
| Diff salvo | `/tmp/claude-1000/-home-rock-Documents-Dev-APPs-SinalACS/db87bd4e-f587-42f6-b307-c1e7658bb3fa/scratchpad/pr155.diff` (refazer com `gh pr diff 155` se sumir) |
| Corpo do commit | truncado: "A confir..." seguido de `Closes #125` |
| `PROGRESS.md` | grava contagens de testes (347/347; 824 e 2) — `CONTRIBUTING.md` pede para evitar |
| Coluna "Não" de RF21 em `requisitos_piloto.md` | é "Depende de instituição ou serviço pago?", **não** "entregue" — não pedir mudança nessa linha |
| ACS `_more` | já é `SingleChildScrollView` (`apps/acs/lib/app/app.dart:2683`); o paciente passou a ser nesta PR |
| `AppLockGate` | no `builder`, acima do Navigator (`app.dart:1013-1021`); tranca após 30 s fora mesmo sem sessão (já era assim no login) |
| Backup Android (paciente) | `sharedpref` excluído de cloud-backup e device-transfer; a confirmação some num aparelho novo (coerente) |
| `flutter drive` | só `scripts/qa/acs_gps_e2e.sh` (geofence) ignora `flutter_test_config.dart`; os outros `*_e2e.dart` rodam por `flutter test` |
| Push tap no paciente | não há navegação por toque em notificação (nenhum `navigatorKey`/`onDidReceiveNotificationResponse` em `lib/`) |

## Global Constraints

- Idioma dos comentários e do parecer: português, como a PR e a issue.
- Nenhum comentário, commit ou parecer leva atribuição de IA ("Generated with", "Co-Authored-By") — regra do `CLAUDE.md` da raiz.
- Nada é publicado no GitHub antes do checkpoint do dono (Task 6); prática do repositório desde a #136 (`docs/superpowers/plans/2026-11-03-issue-136-comentarios.md`).
- Não fazer push na branch do autor; não fechar a #125 (o `Closes #125` da PR fecha no merge).
- Dado sintético apenas: o CPF `123.456.789-09` dos testes é o mesmo de `patient_app_mvp_test.dart`.
- Texto canônico: qualquer diferença entre `educationalNoticeLong`/`Short` e `spec/escopo_projeto.md` é bloqueante (regra "copiada literalmente, sem paráfrase").

## Review Focus

Condições que o diff implica e que nenhum teste da PR exerce; cada uma vira um item da Task 4 e, se procedente, um comentário na Task 5:

1. **Texto muda e a versão não.** `educationalNoticeVersion = '2026-11-01'` é mantida à mão; o teste do escopo pega o texto divergente, mas não um bump esquecido. Esperado: ou uma versão derivada do texto, ou um teste que prenda a versão ao conteúdo. (Sugestão, não bloqueio.)
2. **Primeira abertura em emergência.** O portão é a primeira tela antes da aba de urgência; a aceitação dos termos foi feita como *prompt* e não *gate* para "o alerta de emergência nunca esperar". Esperado: decisão consciente — o critério da #125 pede portão; o texto curto traz "ligue 192"; um toque. Registrar a razão no `PROGRESS.md`, não mudar o comportamento.
3. **Regra do escopo "toda tela inicial"**. A PR cobre primeira abertura e "Sobre" e deixa a tela de login sem o aviso curto a cada abertura. Esperado: issue de continuação (rodapé com a versão curta nos dois logins), não bloqueio desta PR.
4. **ACS: `AppLockGate` tranca a tela do aviso** após 30 s fora. Esperado: mesmo regime do login hoje (sem sessão, "Entrar com senha" recria o portão). Conferir que a recriação por `_gateGeneration` não remonta `EducationalNoticeGate` com `_acknowledged` perdido — o portão está no `home`, abaixo do `builder`, então o `State` sobrevive.
5. **Dois cabeçalhos de "primeira abertura" em sequência no paciente** (#153: diálogo de permissão de notificação em `main.dart` antes do `runApp`; depois o aviso). Esperado: nada quebra; registrar como nota de UX para a #137/#153, sem pedido nesta PR.

---

### Task 1: Worktree da branch e verificação mecânica

**Files:**
- Worktree: `.worktrees/pr-155` (ou o que `superpowers:using-git-worktrees` criar) na branch `feat/c-02-aviso-educativo`
- Saída: `/tmp/claude-1000/-home-rock-Documents-Dev-APPs-SinalACS/db87bd4e-f587-42f6-b307-c1e7658bb3fa/scratchpad/pr155-verificacao.log`

**Interfaces:**
- Produces: o log de verificação que a Task 5 cita por nome; o worktree que as Tasks 2–4 leem.

- [ ] **Step 1: Criar o worktree na branch da PR**

```bash
git fetch origin feat/c-02-aviso-educativo
git worktree add .worktrees/pr-155 origin/feat/c-02-aviso-educativo
```
Esperado: `HEAD` em `eb78c64`; `git -C .worktrees/pr-155 merge-base --is-ancestor origin/develop HEAD && echo ok` imprime `ok`.

- [ ] **Step 2: Rodar os testes novos nos dois apps**

```bash
cd .worktrees/pr-155/apps/patient && flutter pub get >/dev/null && flutter test test/educational_notice_test.dart test/android_backup_manifest_test.dart
cd ../acs && flutter pub get >/dev/null && flutter test test/educational_notice_test.dart
```
Esperado: `All tests passed!` nos dois. Falha no grupo `texto canônico` = bloqueante.

- [ ] **Step 3: Rodar `flutter analyze` e as suítes completas (Linux)**

```bash
cd .worktrees/pr-155/apps/patient && flutter analyze && flutter test 2>&1 | tail -3
cd ../acs && flutter analyze && flutter test 2>&1 | tail -3
```
Esperado: `No issues found!` e `All tests passed!` nos dois — em particular `test/mqtt_tls_refused_test.dart` passa aqui, o que confirma que a falha relatada é só do Windows. Se falhar em Linux, é achado para a Task 5 (a PR não toca MQTT; seria regressão de ambiente a investigar, não bloqueio da PR).

- [ ] **Step 4: Conferir links da documentação e grep de atribuição**

```bash
cd .worktrees/pr-155 && bash scripts/qa/check_documentation_links.sh | tail -2
git log -1 --format=%B | grep -iE 'co-authored|generated with|claude' ; echo "grep exit=$?"
```
Esperado: nenhum `link local ausente`; `grep exit=1` (nada encontrado).

- [ ] **Step 5: Guardar o log**

Redirecionar a saída dos Steps 2–4 para `pr155-verificacao.log` no scratchpad (caminho completo acima). Não commitar nada.

---

### Task 2: Critérios de aceite da #125, um a um

**Files:**
- Read: `apps/patient/test/educational_notice_test.dart`, `apps/acs/test/educational_notice_test.dart`, `apps/{patient,acs}/lib/core/legal/educational_notice.dart`, `spec/escopo_projeto.md:50-62`

**Interfaces:**
- Produces: tabela "critério → evidência (arquivo:teste)" que entra no parecer da Task 5.

- [ ] **Step 1: Critério "primeira abertura exibe o aviso curto e só segue após confirmação"**

Evidência esperada: teste `mostra o aviso curto e só segue para o login depois de "Entendi"` nos dois apps, com `expect(find.byType(PatientLoginScreen), findsNothing)` antes do toque (paciente) e o equivalente no ACS. Conferir que o ACS também afirma que o login **não** está montado antes do "Entendi" (não só que o aviso está). Se faltar, pedir a asserção.

- [ ] **Step 2: Critério "Sobre exibe o aviso longo, copiado literalmente"**

```bash
cd .worktrees/pr-155 && grep -n '^> ' spec/escopo_projeto.md | sed -n 1,2p
grep -n "educationalNoticeLong =\|educationalNoticeShort =" -A 7 apps/patient/lib/core/legal/educational_notice.dart
```
Esperado: as duas citações do escopo e as duas constantes dizem o mesmo (conferência visual; a prova mecânica são os testes `as duas versões são cópia literal de spec/escopo_projeto.md` nos dois apps e `o texto é o mesmo do app do paciente` no ACS, verdes na Task 1 Step 2). Divergência = bloqueante.

- [ ] **Step 3: Critério "teste de widget para as duas telas nos dois apps"**

Contar `testWidgets(` por arquivo: esperado ≥ 8 no paciente e ≥ 7 no ACS, cobrindo primeira abertura, "Sobre" via menu, ida e volta, 200 % de fonte. Anotar qualquer caminho de entrada sem teste: no ACS, o `more_about` do painel é testado (`abre pelo menu "Mais" do painel`); no paciente, `login_about_link` e `more_about` são testados.

- [ ] **Step 4: Pedido do dono na #125 (reaproveitar `LocalProtectionNotice`)**

Esperado: `apps/patient/lib/app/educational_notice_screens.dart` monta `const LocalProtectionNotice()` em `AboutScreen` e o teste `mostra o aviso longo literal e reaproveita o aviso da cifra local` procura `Key('local_protection_notice')`. No ACS, ausente de propósito (não há cifra do paciente lá). Marcar como atendido.

---

### Task 3: Testes que a PR mexeu ou contornou

**Files:**
- Read: `apps/{patient,acs}/test/flutter_test_config.dart`, `apps/{patient,acs}/integration_test/flutter_test_config.dart`, `apps/acs/integration_test/geofence_gps_e2e.dart:59-66`, `apps/patient/test/android_backup_manifest_test.dart:45-60`

- [ ] **Step 1: Confirmar que o seam global é o único caminho e está guardado**

```bash
cd .worktrees/pr-155 && grep -rn "educationalNoticeStoreFactory\s*=[^=]" apps/patient/lib apps/acs/lib apps/*/test apps/*/integration_test
```
Esperado: exatamente 1 atribuição por `lib/` (a declaração) e 1 por cada `flutter_test_config.dart` (4 no total em test/integration_test). O teste `em produção, a loja padrão é a de shared_preferences e nada em lib/ a troca` já prende o lado de `lib/`.

- [ ] **Step 2: Listar os `integration_test` que sobem `SinalAcsApp` e como rodam**

```bash
cd .worktrees/pr-155 && grep -ln "SinalAcsApp(" apps/patient/integration_test/*.dart apps/acs/integration_test/*.dart
grep -rn "flutter drive" scripts/qa/*.sh
```
Esperado: só `geofence_gps_e2e.dart` roda por `flutter drive` e é o único que injeta `educationalNotice:` à mão; os outros 8 passam pelo `flutter_test_config.dart`. Se aparecer outro `flutter drive`, é achado (o e2e pararia no aviso).

- [ ] **Step 3: Backup Android**

Esperado: o teste `shared_preferences só é importado pelo tema e pelo aviso educativo` lista os dois arquivos ordenados; a regra `data_extraction_rules.xml` continua excluindo `sharedpref`. Nada a pedir; registrar no parecer que a confirmação não vai para backup (coerente com #136) e que no ACS não há teste equivalente (o manifesto do ACS tem `allowBackup="false"`, `android_manifest_test.dart`) — sem pedido.

---

### Task 4: Leitura guiada do código (lista fechada)

**Files:**
- Read: `apps/patient/lib/app/educational_notice_screens.dart`, `apps/acs/lib/app/educational_notice_screens.dart`, `apps/{patient,acs}/lib/core/legal/educational_notice.dart`, `apps/patient/lib/app/app.dart:214-222,660-669,3264`, `apps/acs/lib/app/app.dart:566-570,1035-1041,2702`, `PROGRESS.md` (bloco novo)

Cada item: conferir, anotar "ok" ou o achado com `arquivo:linha` para a Task 5.

- [ ] **Step 1: Portão e semântica de falha** — `_EducationalNoticeGateState`: `knownAcknowledged` evita o spinner quando a loja já sabe; `isAcknowledged()` com `onError` → `false`; `_confirm()` muda o estado **antes** do `await acknowledge()` e engole a exceção. Esperado: ok (falha de leitura mostra o aviso; falha de gravação não prende). Conferir que `_FailingStore` nos testes exercita os dois lados.

- [ ] **Step 2: Posição no ACS** — `home: ValueListenableBuilder(... ready ? EducationalNoticeGate(store:, child: _loginScreen()) : _WipeHold())`. Esperado: `_WipeHold` segue antes (limpeza remota #81 não espera o aviso), e `AppLockGate` está no `builder`, acima. Review Focus 4: a recriação do `AppLockGate` por `ValueKey(_gateGeneration)` não toca no `home`, logo o `State` do portão sobrevive. Ok se confirmado.

- [ ] **Step 3: Versão do texto** (Review Focus 1) — `educationalNoticeVersion` é literal; nenhum teste a prende ao texto. Achado de sugestão: no teste de cada app, `expect(educationalNoticeVersion, '<hash curto de long+short>')` ou derivar a versão do texto. Redigir como sugestão opcional.

- [ ] **Step 4: Acessibilidade e tema** — `FilledButton` 48×52 e `TextButton` 48×48 (WCAG 2.5.5 como no resto dos apps); `Semantics(header: true)` nos títulos; ícone sem rótulo (decorativo, ok); cores só `onSurface`/`onSurfaceVariant` (nenhum fill clínico como texto — regra do `CLAUDE.md`); `fontSize` literal segue o padrão do `app.dart` (13 e 16 ocorrências) — não pedir `textTheme`. Esperado: ok, sem comentário.

- [ ] **Step 5: Entradas no app** — paciente: `login_about_link` dentro da mesma coluna do link "Política de Privacidade e Termo de Uso" (sem sessão, pilar A) e `more_about` ao fim da folha "Mais", que virou `SingleChildScrollView`; ACS: `more_about` ao fim da folha já rolável. Esperado: ok. Nota: o ACS não tem link "Sobre" no login — aceitável (a C-02 pede "Sobre", não "no login"); mencionar como opcional.

- [ ] **Step 6: Privacidade da chave** — `aviso_educativo_confirmado` guarda só a string da versão; nome em português como `theme_mode`? (`theme_mode` é inglês.) Esperado: inconsistência cosmética, não pedir. O ACS justifica que o wipe (#81) não precisa apagá-la — concordar no parecer.

- [ ] **Step 7: `PROGRESS.md` e commit** — (a) o bloco grava contagens de testes e um resultado de Windows: pedir que as contagens saiam (ficam na PR) e que o parágrafo do Windows vire uma linha "rodado também em Linux pela revisão" depois da Task 1; (b) corpo do commit truncado ("A confir..."): pedir amend com a mensagem completa, ou avisar que o merge será *squash* com o corpo da PR. (c) Review Focus 2 e 3: pedir uma frase no bloco registrando a decisão "portão de um toque, com 192 no texto" e a issue de continuação para "toda tela inicial".

- [ ] **Step 8: Duplicação entre apps** — duas cópias idênticas de `educational_notice.dart` (sem pacote comum, como `totp.dart`), travadas por teste no ACS. Esperado: aceitar; registrar no parecer que um pacote `sinalacs_shared` fica fora desta PR.

---

### Task 5: Redigir o parecer e os comentários

**Files:**
- Create: `docs/superpowers/plans/2026-11-12-pr-155-comentarios.md`

**Interfaces:**
- Produces: um arquivo com (a) o corpo do parecer (`## Parecer`), (b) uma seção por comentário inline (`## Inline N — <path>:<linha> — <tipo>`) com o texto exato, (c) a seção `## Issues de continuação` com título e corpo propostos. Tipos: **bloqueante**, **pedido** (muda nesta PR), **sugestão** (opcional), **registro** (só documenta).

- [ ] **Step 1: Escrever o parecer** — estrutura fixa: resumo (o que a PR entrega contra os 3 critérios da #125, cada um com o teste que o prova); verificação feita pela revisão (Task 1: comandos e resultado, citando o log do scratchpad e que `mqtt_tls_refused_test` passa em Linux); achados por tipo; veredito proposto. Veredito padrão se não houver bloqueante: **Aprovar com observações** (os pedidos do Step 7 da Task 4 são pequenos e não exigem nova rodada de revisão).

- [ ] **Step 2: Escrever os comentários inline** — um por achado procedente das Tasks 2–4, mínimo esperado:
  - `PROGRESS.md` (bloco novo, linha das contagens) — **pedido**: tirar contagens e o detalhe do Windows (`CONTRIBUTING.md`: "Evite gravar contagens de testes nos documentos").
  - `apps/patient/lib/core/legal/educational_notice.dart` (linha de `educationalNoticeVersion`) — **sugestão**: prender a versão ao texto, com o trecho de teste proposto.
  - `apps/patient/lib/app/educational_notice_screens.dart` (doc de `EducationalNoticeGate`) — **registro**: portão antes da urgência é decisão consciente; pedir uma frase no `PROGRESS.md`.
  - `apps/acs/lib/app/app.dart:1035-1041` — **registro**: ordem `_WipeHold` → aviso → login confirmada; `AppLockGate` acima, `State` sobrevive à recriação do gate.
  - Comentário geral (não inline) — **pedido**: commit truncado; **sugestão**: link "Sobre" no login do ACS (opcional); **registro** (Review Focus 5): no paciente, a primeira abertura encadeia o diálogo de permissão de notificação (#153) e o aviso — nada quebra; nota de UX para a #137, sem pedido nesta PR.

- [ ] **Step 3: Escrever as issues de continuação** — dentro de `## Issues de continuação`, uma subseção `### Issue N — <título>` por issue, com o corpo pronto para `gh issue create`. (1) "Aviso curto em toda tela inicial (RF21, regra do escopo)": rodapé com `educationalNoticeShort` nos dois logins, teste de widget, pilar A; (2) só se a Task 4 Step 3 virar pedido do dono: "Versão do aviso derivada do texto". Não criar ainda: a criação é o Step 3 da Task 6.

- [ ] **Step 4: Reler contra as Global Constraints** — português, sem atribuição de IA, sem dado real, nenhum pedido que dependa de unidade de saúde ou serviço pago. Corrigir inline.

---

### Task 6: Checkpoint do dono e publicação

**Files:**
- Read: `docs/superpowers/plans/2026-11-12-pr-155-comentarios.md`

- [ ] **Step 1: Checkpoint** — apresentar ao dono o arquivo da Task 5 e o veredito proposto. Esperar aprovação explícita do texto e do veredito (`--approve`, `--comment` ou `--request-changes`). **Parar aqui se o dono não responder.**

- [ ] **Step 2: Publicar os comentários inline e o parecer**

```bash
SHA=$(gh pr view 155 --json headRefOid -q .headRefOid)
# um por comentário inline; path e line vêm do arquivo da Task 5
gh api repos/hbgit/SinalACS/pulls/155/comments -f commit_id="$SHA" -f path="PROGRESS.md" -F line=<n> -f side=RIGHT -f body="$(sed -n '/^## Inline 1/,/^## Inline 2/p' docs/superpowers/plans/2026-11-12-pr-155-comentarios.md | sed '1d;$d')"
# parecer
gh pr review 155 --<approve|comment|request-changes> --body-file <(sed -n '/^## Parecer/,/^## Inline 1/p' docs/superpowers/plans/2026-11-12-pr-155-comentarios.md | sed '1d;$d')
```
Esperado: `gh pr view 155 --json reviews,comments -q '.reviews|length'` ≥ 1 e `gh api repos/hbgit/SinalACS/pulls/155/comments -q 'length'` = número de inlines do arquivo. Se um inline falhar por linha fora do diff, trocar por comentário geral com `arquivo:linha` no texto.

- [ ] **Step 3: Abrir as issues de continuação aprovadas**

```bash
gh issue create --title "<título da Task 5 Step 3>" --body-file <(sed -n '/^### Issue 1/,/^### Issue 2/p' docs/superpowers/plans/2026-11-12-pr-155-comentarios.md | sed '1d;$d') --milestone Pilot --label enhancement
```
Esperado: número da issue devolvido; colar o número num comentário geral da PR ("continuação: #<n>").

- [ ] **Step 4: Commit do rascunho e limpeza**

```bash
git add docs/superpowers/plans/2026-11-12-pr-155-revisao-aviso-educativo.md docs/superpowers/plans/2026-11-12-pr-155-comentarios.md
git commit -m "docs(plano): revisão e comentários da PR #155 (C-02)"
git worktree remove .worktrees/pr-155
```
Esperado: commit na branch de trabalho do dono (hoje `docs/distribuicao-pilot`), sem atribuição de IA; worktree removido.
