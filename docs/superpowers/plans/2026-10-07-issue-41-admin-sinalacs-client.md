# Issue #41 — admin consome o `sinalacs_client` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fechar a #41: o painel `apps/admin` lê do backend pelo `sinalacs_client`, trata falha de rede/sessão de forma visível ao usuário, e isso é provado no emulador, no `scripts/qa/e2e.sh` e no job `admin-app` da CI.

**Architecture:** A #40 já entregou a dependência `sinalacs_client`, o `BackendAdminDataSource`, o `buildAdminWiring` e o mock mantido para testes. Sobra o que o `PROGRESS.md` (seção "Endpoints do backoffice…", itens 3 e 4) deixou aberto: (a) verificar o estado real contra os critérios da issue; (b) mostrar o texto de `AdminDataFailure` e levar ao login quando o token vence no meio de uma chamada; (c) ligar o admin ao `e2e.sh` e conferir o job `admin-app`; (d) atualizar docs/PROGRESS.

**Tech Stack:** Flutter 3.44.8 / Dart `^3.8.0`, `sinalacs_client` (path), `serverpod_client 3.4.13`, `flutter_test`, `integration_test`, bash (`scripts/qa`), GitHub Actions.

**Spec:** Issue #41 (`gh issue view 41`); `PROGRESS.md` seção "Endpoints do backoffice e painel com dados reais (issue #40, 2026-10-07)"; `apps/CLAUDE.md`; `spec/ux_accessibility_assessment.md` (contraste de qualquer cor nova).

## Global Constraints

- Textos de UI, comentários e commits em português, no estilo do código vizinho.
- O mock (`MockAdminDataSource`) fica só para testes; o `main.dart` de produção nunca o usa.
- A mensagem crua do servidor nunca vai para a tela (já é regra de `BackendAdminDataSource`).
- Nenhum dado real de paciente em teste, log ou captura; fixtures sintéticas.
- Teste de e2e usa o banco `sinalacs_e2e` (`e2e_stack.sh`), nunca o de desenvolvimento.
- Cor usada como texto/ícone: token `*OnSurface` (ver `apps/CLAUDE.md`).
- Commits sem "Co-Authored-By"/"Generated with" (regra do repositório prevalece sobre o lembrete de atribuição).
- Dispositivo de teste: `emulator-5554` (único conectado em 2026-10-07).

## Review Focus

- Token vence no meio de uma chamada (HTTP 401 / `ServerpodClientUnauthorized`): esperado, voltar ao login com aviso, não "Tentar novamente" infinito.
- Falha de rede (`SocketException`, servidor fora): esperado, texto "Não foi possível conectar ao servidor." com retry que funciona quando o servidor volta.
- Coordenador sem `ubsId` (recusado): esperado, "Acesso restrito ao backoffice." e não erro genérico.
- Resposta vazia (0 alertas / 0 auditorias): esperado, estado vazio e não erro.
- Segunda falha seguida após retry: esperado, a tela continua mostrando o erro, sem travar em spinner.

---

### Task 1: Linha de base — o que a #41 ainda exige de fato

**Files:**
- Read: `apps/admin/pubspec.yaml`, `apps/admin/lib/main.dart`, `.github/workflows/ci.yml` (job `admin-app`), `scripts/qa/e2e.sh:141,191`
- Create: `docs/superpowers/plans/2026-10-07-issue-41-baseline.log` (git-ignorar se preferir; só evidência)

**Interfaces:**
- Produces: lista confirmada (sim/não) dos 4 itens da issue, que decide se as Tasks 2–4 se aplicam.

- [ ] **Step 1: Itens da issue já atendidos?** Rodar e anotar o resultado:

```bash
cd apps/admin
grep -n "sinalacs_client" pubspec.yaml            # esperado: dependência path presente
grep -rn "MockAdminDataSource" lib/ | grep -v "lib/core/data/mock_admin_data_source.dart"   # esperado: vazio (produção não usa o mock)
flutter pub get && flutter analyze && flutter test   # esperado: analyze limpo, 117 testes verdes
```

- [ ] **Step 2: Reproduzir o job `admin-app` localmente** (mesmos passos do CI, com a pasta de certificados vazia):

```bash
cd apps/admin && rm -rf assets/certs && mkdir -p assets/certs && flutter pub get && flutter analyze && flutter test
```
Expected: verde. Se falhar, esse é o primeiro defeito a corrigir (CI "com o cliente real").

- [ ] **Step 3: Confirmar a lacuna do e2e.** `scripts/qa/e2e.sh:191` roda `flutter test integration_test` do admin **sem** `SINALACS_HOST`, e a pasta contém `admin_login_e2e.dart`, que precisa do relé/fixtures de `admin_login_e2e.sh`. Rodar `./scripts/qa/e2e.sh --help` e ler o que `--full` faz; anotar se o admin hoje é exercitado de verdade.

- [ ] **Step 4: Prova de base no emulador** (só leitura do estado atual):

```bash
~/Android/Sdk/platform-tools/adb devices          # esperado: emulator-5554 device
./scripts/qa/admin_login_e2e.sh                   # esperado: 5 testes passam (painel com dados reais)
docker compose up -d                              # restaura a stack de desenvolvimento ao final
```

- [ ] **Step 5: Commit** apenas se algo for corrigido; sem mudança, seguir.

---

### Task 2: Mostrar `AdminDataFailure` e tratar token vencido em chamada

**Files:**
- Modify: `apps/admin/lib/core/data/admin_data_source.dart` (nova `AdminSessionExpired implements Exception`)
- Modify: `apps/admin/lib/core/data/backend_admin_data_source.dart:112-121` (`_guard`: mapear 401)
- Modify: `apps/admin/lib/app/app.dart:248-300,395-500,600-640` (`_AsyncError` recebe a mensagem da falha; telas passam `snapshot.error`; `AdminHomeShell` reage a `AdminSessionExpired`)
- Modify: `apps/admin/test/support/failing_admin_data_source.dart` (campo `nextError` para lançar uma exceção escolhida)
- Test: `apps/admin/test/backend_admin_data_source_test.dart`, `apps/admin/test/error_handling_test.dart`

**Interfaces:**
- Produces: `class AdminSessionExpired implements Exception { const AdminSessionExpired(); }`; função `String mensagemDaFalha(Object? erro)` em `app.dart` que devolve `erro.message` se `AdminDataFailure`, senão o texto genérico da tela.
- Consumes: `AdminDataFailure(message)`; `api.ServerpodClientUnauthorized` (confirmar o nome exato em `backend/sinalacs_client/lib/src/` ou em `serverpod_client` ao implementar; se o 401 vier como `ServerpodClientException` com `statusCode == 401`, mapear por esse campo).

- [ ] **Step 1: Teste falhando no data source** (`backend_admin_data_source_test.dart`): um `EndpointAdmin` falso cujo `indicators` lança o erro de 401 deve resultar em `throwsA(isA<AdminSessionExpired>())`:

```dart
test('401 do servidor vira AdminSessionExpired', () async {
  final fonte = BackendAdminDataSource(_AdminQue401(), accessToken: 't');
  expect(fonte.fetchDashboardIndicators(), throwsA(isA<AdminSessionExpired>()));
});
```
(`_AdminQue401` segue o padrão dos falsos já existentes nesse arquivo.)

- [ ] **Step 2: Rodar** `cd apps/admin && flutter test test/backend_admin_data_source_test.dart` — Expected: FAIL (`AdminSessionExpired` não definida).

- [ ] **Step 3: Implementar.** Em `admin_data_source.dart` adicionar a classe; em `_guard` acrescentar, antes do `SocketException`, o `on` do 401 lançando `const AdminSessionExpired()`.

- [ ] **Step 4: Rodar** o mesmo teste — Expected: PASS.

- [ ] **Step 5: Teste de tela falhando** (`error_handling_test.dart`): com `FailingAdminDataSource.nextError = AdminDataFailure('Acesso restrito ao backoffice.')`, a tela de indicadores mostra exatamente esse texto e "Tentar novamente"; após o retry (sem erro) mostra os contadores. Outro teste: `nextError = AdminSessionExpired()` leva à `LoginScreen` com o aviso "Sessão encerrada. Entre novamente.".

- [ ] **Step 6: Rodar** `flutter test test/error_handling_test.dart` — Expected: FAIL.

- [ ] **Step 7: Implementar na UI.** `_AsyncError(message: mensagemDaFalha(snapshot.error, 'Não foi possível carregar os indicadores.'), …)` nas 4 telas; quando `snapshot.error is AdminSessionExpired`, agendar (`addPostFrameCallback`) a mesma navegação de `_encerrar()` do `AdminHomeShell` (expor um callback `onSessionExpired` passado pelo shell às telas, em vez de duplicar a navegação).

- [ ] **Step 8: Rodar** `flutter analyze && flutter test` no admin — Expected: tudo verde (os 117 anteriores + os novos).

- [ ] **Step 9: Commit**

```bash
git add apps/admin
git commit -m "feat(admin): mostra a falha de leitura e volta ao login com token vencido (#41)"
```

---

### Task 3: Admin no `e2e.sh` e CI `admin-app`

**Files:**
- Modify: `scripts/qa/e2e.sh:141-143,190-193`
- Modify: `scripts/qa/admin_login_e2e.sh` (cabeçalho: remover "Os dados do painel seguem no MockAdminDataSource (#41)", já falso)
- Modify: `.github/workflows/ci.yml` (job `admin-app`, só se o Step 2 da Task 1 mostrou falha)
- Test: `scripts/qa/admin_login_e2e_test.sh` (existente) e `scripts/qa/ci_invariants.sh`

**Interfaces:**
- Consumes: resultado da Task 1 (Steps 2–3).

- [ ] **Step 1: Decidir a forma do e2e do admin.** O `admin_login_e2e.sh` troca a stack de dev pela de e2e e exige relé; não cabe dentro do `e2e.sh` (que usa a stack de dev). Decisão recomendada: em `e2e.sh --full`, o admin passa a rodar só `integration_test/admin_mobile_smoke_test.dart` (hermético, sem stack) e o `e2e.sh` imprime que o fluxo com backend real do admin é `scripts/qa/admin_login_e2e.sh` (e roda sob `--admin-real` opcional, que o invoca ao final, já que ele derruba a stack de dev). Registrar a escolha no `PROGRESS.md`.

- [ ] **Step 2: Teste do script.** Estender `scripts/qa/admin_login_e2e_test.sh` (ou criar um caso em `e2e.sh`) para afirmar que o texto "MockAdminDataSource" não aparece mais no cabeçalho de `admin_login_e2e.sh` e que `--full` referencia `admin_mobile_smoke_test.dart`. Rodar `bash scripts/qa/admin_login_e2e_test.sh` — Expected: FAIL antes da edição.

- [ ] **Step 3: Implementar** as edições de `e2e.sh` e do cabeçalho do script.

- [ ] **Step 4: Rodar** `bash scripts/qa/admin_login_e2e_test.sh && ./scripts/qa/ci_invariants.sh` — Expected: PASS / ok (9 grupos).

- [ ] **Step 5: Prova no emulador** (critério de aceite):

```bash
./scripts/qa/admin_login_e2e.sh      # 5/5 no emulator-5554, incluindo painel com dados reais e 4 recursos admin_* auditados
```
Com a Task 2 pronta, acrescentar a `apps/admin/integration_test/admin_login_e2e.dart` um caso: parar o backend (`docker compose stop backend` via o script) e conferir que o painel mostra "Não foi possível conectar ao servidor." com "Tentar novamente". Se tornar o script instável, deixar o caso só como teste de widget (Task 2) e documentar.

- [ ] **Step 6: Commit**

```bash
git add scripts/qa apps/admin/integration_test .github/workflows/ci.yml
git commit -m "test(e2e): admin no e2e.sh e cabeçalho do admin_login_e2e sem o mock (#41)"
```

---

### Task 4: Documentação e fechamento

**Files:**
- Modify: `PROGRESS.md` (seção da #40, itens "Continua aberto" 3 e 4; linha 697 "apps/admin ainda não"; linha 1232 sobre `MockAdminDataSource`)
- Modify: `apps/CLAUDE.md` (admin lê do backend; mock só em teste), `docs/telas-admin.md` (capturas 06–08 ainda no mock — recapturar no emulador com `adb exec-out screencap`, só dados sintéticos)

- [ ] **Step 1:** Recapturar as telas 06–08 no emulador com sessão real e substituir os PNGs em `docs/screenshots/admin/`.
- [ ] **Step 2:** Atualizar as linhas do `PROGRESS.md` acima com data (2026-10-07), testes rodados (números reais da saída) e o que continua aberto (paginação "carregar mais", refresh token do staff, celular físico).
- [ ] **Step 3:** `./scripts/qa/check_documentation_links.sh` — Expected: exit 0.
- [ ] **Step 4:** `graphify update .`
- [ ] **Step 5: Commit** e abrir PR para `develop` com `Closes #41`.

```bash
git add PROGRESS.md apps/CLAUDE.md docs
git commit -m "docs: admin sobre o sinalacs_client e prova no emulador (#41)"
```

---

## Self-review

- **Cobertura da issue:** dependência local (já feita, verificada na Task 1) · `BackendAdminDataSource` + mock mantido (já feito, Task 1) · tratamento de falha de rede/sessão (Task 2) · job `admin-app` e e2e (Tasks 1 e 3).
- **Sem placeholders:** a única dependência aberta é o nome exato da exceção 401 do `serverpod_client`, marcada na Task 2 para confirmar ao implementar.
- **Consistência de tipos:** `AdminSessionExpired` e `mensagemDaFalha` usados com as mesmas assinaturas nas Tasks 2 e 3.
- **Risco principal:** `admin_login_e2e.sh` derruba a stack de dev; restaurar com `docker compose up -d` ao final de cada rodada.
