# Gestão de ACS, vínculo de microárea e reset de MFA no backoffice (issue #43) — Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** dar ao backoffice (coordenador e administrador) o ciclo de vida da conta de ACS — cadastro com senha inicial, vínculo/desvínculo de microárea, ativação/desativação com revogação de sessões — e a redefinição de senha e de MFA (do ACS e do staff), tudo restrito por papel/escopo, auditado na cadeia de `audit_logs` e com confirmação explícita para ações destrutivas.

**Architecture:** backend Serverpod com a mesma postura dos endpoints de leitura da #40 — `AdminEndpoint extends AuthenticatedEndpoint`, regra de papel/escopo extraída para um `AdminScopeResolver` compartilhado, serviço de aplicação (`AdminAccountService`) sobre portas estreitas (`AdminAccountStore` novo + `AcsCredentialStore`/`TotpStore`/`RefreshTokenStore`/`UploadTokenStore`/`StaffActivationStore` estendidos), implementação ORM em transação por operação. No app, a tela Microáreas deixa de ser somente leitura: seções de ACS e de Equipe (staff) alimentadas por novos métodos do `AdminDataSource`, com diálogos de confirmação e testes de acessibilidade.

**Tech Stack:** Dart 3.12 / Serverpod 3.4.13 (server + client gerado), Flutter (app `sinalacs_admin`), PostgreSQL, scripts bash em `scripts/qa/`, emulador Android `emulator-5554`.

**Spec:** issue #43 (`gh issue view 43`) + `spec/PRD_system.md` §4.2.2 (matriz RBAC/ABAC) + `spec/lgpd_design.md` LGPD-RF11 (§5.2/§5.3) + `AGENTS.md` + `backend/CLAUDE.md` (seções RF07/Staff #39/#48, `AdminEndpoint` #40) + `apps/CLAUDE.md` (seção Admin app) + `PROGRESS.md` L633, L643, L665, L608, L807(b). Os planos `2026-10-07-issue-40-endpoints-admin.md`, `2026-10-07-issue-48-ativacao-totp-staff.md` e `2026-10-06-admin-autenticacao-real.md` registram o que foi adiado para esta issue — ler os três antes de começar.

## Global Constraints

- Idioma: código, comentários, textos de tela, commits e docs em **português** (padrão do repositório).
- Nenhum dado real de paciente/ACS em teste, seed, log, print ou config. Fixtures sintéticas, geradas por execução (`bin/seed_e2e_fixtures.dart`).
- Nunca commitar com `Co-Authored-By`, "Generated with Claude Code" ou qualquer atribuição de IA.
- `backend/sinalacs_server/lib/src/generated/**` e `migrations/**` **nunca** editados à mão: só `serverpod generate` / `serverpod create-migration`. Nesta issue **não há** migração (nenhuma tabela/coluna nova; só modelos de API e endpoints). Se o `serverpod generate` acusar drift de migração, pare e investigue antes de seguir.
- Senha em claro não existe em repouso, em log nem em auditoria: o servidor guarda Argon2id (`PasswordHasher`), a auditoria registra só o fato (`password_reset`), nunca o valor.
- A auditoria do backoffice é **fail-closed** (`AuditTrail.record`, nunca `recordSafely`), como em `AdminReadService`: se a linha não grava, a operação não pode seguir em silêncio. Leitura: audita e só então lê. Escrita: recusa audita antes de lançar; sucesso audita depois do commit — se a auditoria falhar, a exceção sobe (nunca um write de staff sem trilha).
- Papéis: só `coordinator` e `admin` (`Authorization.staffRoles`); o coordenador enxerga e opera **apenas** a própria UBS (`staff_accounts.ubsId`), fail-closed sem UBS; o administrador, o sistema inteiro. Toda operação fora do escopo devolve a mesma recusa genérica (`acesso restrito ao backoffice` / ` não encontrado`), sem distinguir "não existe" de "não é seu".
- Invariantes de produto intactos: territorialização (INV-01) e classificação de risco determinística não são tocadas; nenhum caminho novo escreve em `triage_sessions`/`alerts`.
- Acessibilidade: alvos de toque ≥ 48dp (WCAG 2.5.5), texto colorido só via tokens `*OnSurface` de `apps/admin/lib/app/admin_theme.dart` (WCAG 1.4.3), layout sem estouro a 130%/200% de fonte e em 360×800 / 800×360 (WCAG 1.4.4/1.4.10).
- Emulador: `emulator-5554` (`DEVICE` sobreponível); SDK em `~/Android/Sdk` (`platform-tools/`, `emulator/`); nada de `10.0.2.2` — o padrão dos scripts é `adb reverse`.
- A criação/recriação de contêiner pelo script de e2e deve ser rodada **pelo usuário** (efeito colateral da máquina), com `!` quando aplicável.

## Review Focus

(os cinco casos que mais provavelmente mordem quem usar isto — cada um tem teste na tarefa que o implementa)

1. **Escopo do coordenador na escrita (TOCTOU):** um coordenador da UBS A tentando desativar/redefinir um ACS da UBS B — inclusive passando o `acsId` direto no RPC, não pelo fluxo da tela — deve receber a mesma resposta de "não encontrado", a tentativa deve virar linha `denied` na trilha, e a pré-checagem de escopo **não** pode ser separada do `UPDATE` (o `WHERE` da mutação carrega o predicado de escopo). Testes: Tarefa 4/5/6 (unit + integração).
2. **Matrícula duplicada em corrida:** dois cadastros simultâneos com a mesma matrícula — um vence, o outro recebe erro de validação limpo (`AdminInvalidRequestException`), nunca 500 de índice único. Teste: Tarefa 3.
3. **Criação parcial:** falha no meio do cadastro (após `users`, antes de `acs`/`user_credentials`) não pode deixar usuário órfão sem credencial. Teste com o hook `debugFailAfterUsersInsert`: Tarefa 3.
4. **Desativação não revoga:** ACS desativado cujo refresh token continua renovando sessão, ou cujo token de envio diferido continua podendo subir visitas em nome dele. Teste: Tarefa 5 (SQL + `refreshSession`/`syncDeferred` recusados).
5. **Confirmação decorativa:** o botão "Desativar" chamando a API antes (ou sem) o diálogo de confirmação, e a senha inicial/código de ativação reaparecendo em outro ponto da tela depois de fechado o diálogo "mostrado uma única vez". Testes de widget: Tarefa 10.

---

## 1. Resumo da ISSUE #43

**Título:** `admin: gestão de ACS e microáreas (cadastro, vínculo, desativação) e reset de MFA`.

**Contexto (da issue):** a tela Microáreas é somente leitura. Hoje o reset de MFA do ACS é manual e não existe cadastro/desativação de ACS pelo produto.

**O que falta (da issue):**
- Criar/desativar ACS, vincular ACS a microárea, redefinir senha inicial.
- Reset de MFA pelo coordenador com trilha de auditoria.
- Desativar conta deve revogar a família de refresh tokens (já suportado pelo backend).

**Critérios de aceite (da issue):**
- [ ] Ações restritas ao papel coordenador/admin e auditadas.
- [ ] Confirmação explícita para ações destrutivas, com teste de acessibilidade (alvos de toque, contraste).

**Resultado esperado:** um coordenador (na própria UBS) ou um administrador (sistema) consegue, pelo app `sinalacs_admin` rodando no emulador contra o backend real: cadastrar um ACS com senha inicial gerada e mostrada uma única vez; mover esse ACS entre microáreas; desativar (com confirmação) e reativar; redefinir a senha (nova senha gerada, mostrada uma única vez); redefinir a MFA do ACS e a MFA de uma conta de equipe (código de ativação emitido pela tela, mostrado uma única vez); e a desativação derruba sessão (refresh token) e envio diferido daquele ACS. Toda operação gera linha na cadeia de `audit_logs` com o ator, o alvo e o desfecho.

**Escopo incluído por deferimento explícito (documentado em outros planos/PROGRESS):**
- Reset de MFA do **staff** e emissão do código de ativação por quem já tem sessão — adiado para a #43 por `2026-10-07-issue-48-ativacao-totp-staff.md` L627/L656 e `PROGRESS.md` L665. (Hoje só a CLI `bin/issue_staff_activation_code.dart` emite, e a emissão não entra em `audit_logs`.)
- Auditoria por UBS para o coordenador — adiada para a #43 por `2026-10-07-issue-40-endpoints-admin.md` L347/L538 e `PROGRESS.md` L643(2). Na Tarefa 8; se o humano preferir reduzir a PR, é a única tarefa removível sem tocar as outras.

**Fora do escopo desta entrega (nomeado, para virar issue própria):**
- Criar contas de coordenador/administrador e atribuir `staff_accounts.ubsId` pela UI (`PROGRESS.md` L643 chama a #43 de "lugar natural", mas não está no corpo da issue; criar um coordenador de desenvolvimento exige decidir mais uma senha em `.env`/`bootstrap_env.sh` — decisão da #40, L543). Fica registrado no `PROGRESS.md` (Tarefa 13).
- Troca de senha pelo próprio ACS (não existe fluxo no app do ACS; a senha inicial gerada permanece até uma redefinição pela coordenação) e expiração de senha inicial.
- Desbloqueio de conta trancada por tentativas como ação separada: a redefinição de senha (Tarefa 6) zera o bloqueio como efeito colateral; não haverá botão "desbloquear".
- iOS, web do backoffice, refresh token do staff.

---

## 2. Diagnóstico preliminar

### Fatos verificados no código (2026-10-08, branch `develop`, `db6a756`)

**Backend — o que existe:**
- `AdminEndpoint` (`backend/sinalacs_server/lib/src/endpoints/admin_endpoint.dart`, 57 linhas) expõe **só leitura**: `indicators`, `microAreas`, `alerts`, `auditLogs`. O doc da classe diz "Somente leitura, só para `coordinator` e `admin`".
- `AdminReadService` (`application/admin/admin_read_service.dart`) implementa papel (`Authorization.staffRoles`), escopo (`AdminScope.system()` para admin; `AdminScope.ubs(staff_accounts.ubsId)` para coordenador; coordenador sem UBS recusado) e "auditoria antes do dado" com `AuditTrail.record` (fail-closed). `auditLogs` é **admin-only** hoje (L109: `if (user.role != UserRole.admin)`), com comentário L56 apontando o deferimento à #43.
- `OrmAdminReadStore` (`infrastructure/database/orm_admin_read_store.dart`) faz SQL direto com `QueryParameters.named`; `microAreas` agrega ACS por microárea (L67-93); `auditLogs` já faz o join `users`/`acs`/`staff_accounts` para o rótulo (L149-154); `ubsOf` lê `staff_accounts.ubsId` (L189-198).
- Login institucional (`InstitutionalAuthService`, `application/auth/institutional_auth_service.dart`): `_authenticatePassword` recusa conta inativa (`'Este acesso está inativo.'`, L490-493) e ACS sem território (L507-515); `beginTotpEnrollment` responde `'A verificação em duas etapas já está ativa. Peça a redefinição à coordenação.'` (L314-316, L322-324) — a mensagem já aponta para um caminho que **não existe**.
- `AcsCredentialStore.saveCredential` (`orm_acs_credential_store.dart`) já existe e "substitui a credencial" (comentário na interface: "usado pelo seed e por uma **futura troca de senha**") — zera `failedAttempts`/`lockedUntil`, mas **não** zera `lockStreak` (bug de borda que a Tarefa 6 corrige).
- `TotpStore` (mesma linha da interface, em `institutional_auth_service.dart` L25-40) tem `saveSecret`/`enable`/`registerStep`; **não tem** operação de limpar as colunas `totp*`.
- `RefreshTokenStore` (`application/auth/refresh_token_service.dart` L38-53) tem `revokeFamily(familyId)` — **não tem** "revogar todas as famílias de um usuário". `UploadTokenStore` (`upload_token_service.dart` L28-44) tem `revoke(id)` e `replace(...)`, e **não tem** revogação em massa por usuário.
- `StaffActivationStore` (#48) tem `issue/find/clear` gravando `activationCodeHash/ExpiresAt/IssuedBy/IssuedAt` em `staff_accounts`; `StaffActivationCode.generate()` gera 130 bits (26 chars base32 com grupos), `defaultValidity` = 24 h.
- Seed de desenvolvimento: a linha de ACS é `'00000000-…-0002'` com `cpfHash = 'development-acs'`, `birthDate = '1980-01-01'`, `acs."ubsId" = …0004`, `enrollmentId = 'ACS-001'` (`seeds/development.sql` L23-26, L67). O seed de e2e (`bin/seed_e2e_fixtures.dart` + `infrastructure/testing/e2e_fixtures.dart`) cria 1 UBS, 2 microáreas (mesma UBS), 2 ACS, pacientes e 1 admin (bloco `staff`, matrícula `E2E-ADM-*`, com `activationCode`); **não** cria coordenador e **não** define `staff_accounts.ubsId` (armadilha: o coordenador do e2e precisa disso para escopo).
- O único emissor de código de ativação hoje é a CLI de operador `bin/issue_staff_activation_code.dart`; a emissão **não** grava `audit_logs` (decisão do #48, L481, apontada como pendência em `PROGRESS.md` L665(2)).

**App `sinalacs_admin` — o que existe:**
- `AdminDataSource` (`lib/core/data/admin_data_source.dart`) só tem leitura (4 métodos) + `recordAccess`; `BackendAdminDataSource` mapeia o `EndpointAdmin` gerado e traduz falhas para `AdminDataFailure` (texto fixo) / `AdminSessionExpired`; hoje `AdminInvalidRequestException` vira `'Parâmetro de paginação inválido.'` (L133-134) — inadequado para escrita.
- A tela `MicroAreasScreen` (`lib/app/app.dart` L400-458) mostra um subtítulo explícito: "Listagem somente leitura — edição de vínculo fica para uma próxima issue." (L438), e o teste `test/micro_areas_screen_test.dart` L20-21 **afirma** `find.byIcon(Icons.edit_outlined) → findsNothing` (essa asserção precisa ser invertida pela Tarefa 10, de propósito).
- A casca tem 4 destinos (`AdminDestination` L39-55) e o comentário de `responsive_layout_test.dart` L23-26 avisa que o rail em paisagem (800×360) "cabe por poucos pixels" com 4 destinos — por isso a gestão entra **dentro** de Microáreas, sem quinto destino.
- `MockAdminDataSource` (`lib/core/data/mock_admin_data_source.dart`) tem 3 microáreas, 6 alertas e um log em memória; é o duplo dos testes de widget e do smoke hermético.
- `AdminSession` (`lib/core/auth/admin_auth_backend.dart`) carrega `role` (`'admin'`/`'coordinator'`) — disponível na casca para decidir seções visíveis.
- Infra de teste de acessibilidade já existe: `test/support/layout_harness.dart` (com `percorrerBackofficeInteiro`, `esperarSemEstouroDeLayout`), `test/support/contrast.dart` (razão WCAG calculada), `test/touch_targets_test.dart` (régua de 48dp), `test/contrast_tokens_test.dart`, `test/text_scale_test.dart`, `test/responsive_layout_test.dart`. Botões declaram `minimumSize` individuais (`login_screen.dart` L184, `mfa_enrollment_screen.dart` L149/L198) — o tema **não** define mínimo global.

**Tooling de validação (verificado na máquina em 2026-10-08):**
- Emulador `emulator-5554` (AVD `Medium_Phone`) **já rodando**; SDK em `~/Android/Sdk` (`platform-tools/adb`, `emulator/emulator`); `flutter` em `/home/rock/flutter/bin`.
- Stack de desenvolvimento **já de pé** (`sinalacs-serverpod` healthy, `mosquitto`, `traefik`, `postgres`, `postgres-test`, `gorush`).
- E2E real do backoffice: `./scripts/qa/admin_login_e2e.sh` (troca a stack de dev pela de e2e, semeia fixtures sintéticas, entrega a credencial do admin pelo relé `otp_relay.py /admin`, roda `apps/admin/integration_test/admin_login_e2e.dart` com `--dart-define=SINALACS_HOST=https://localhost:8443/`, e ao final faz asserts SQL). O script é manual (a CI não o roda).
- `otp_relay.py` serve `/now`, `/code`, `/count`, `/acs`, `/acs-b`, `/admin`, cada credencial **uma única vez**; tem teste (`otp_relay_test.py`).

### Componentes envolvidos (mapa)

| Camada | Arquivos |
|---|---|
| Endpoint | `backend/sinalacs_server/lib/src/endpoints/admin_endpoint.dart` |
| Serviço | `application/admin/admin_read_service.dart`, **novos** `application/admin/admin_scope.dart`, `application/admin/admin_account_service.dart`, `application/admin/initial_password.dart` |
| Portas | **nova** `AdminAccountStore`; estendidas `TotpStore` (`clearTotp`), `RefreshTokenStore`/`UploadTokenStore` (`revokeAllForUser`), `saveCredential` (fix `lockStreak`) |
| Infra | **novo** `infrastructure/database/orm_admin_account_store.dart`; `orm_acs_credential_store.dart`, `orm_refresh_token_store.dart`, `orm_upload_token_store.dart`, `orm_admin_read_store.dart` |
| Modelos API | **novos** `models/api/admin_acs.spy.yaml`, `admin_staff.spy.yaml`, `admin_acs_creation_result.spy.yaml`, `admin_password_reset_result.spy.yaml`, `admin_staff_mfa_reset_result.spy.yaml` |
| Runtime | `runtime/alert_runtime.dart` (`adminAccountServiceFor`) |
| App dados | `apps/admin/lib/core/data/{admin_data_source,backend_admin_data_source,mock_admin_data_source}.dart` |
| App UI | `apps/admin/lib/app/app.dart` (MicroAreasScreen), **novo** `apps/admin/lib/app/admin_accounts.dart` |
| Seeds/scripts | `backend/sinalacs_server/{bin/seed_e2e_fixtures.dart,lib/src/infrastructure/testing/e2e_fixtures.dart}`, `scripts/qa/otp_relay.py`, **novos** `scripts/qa/admin_acs_gestao_e2e.sh` + `admin_acs_gestao_e2e_test.sh`, `apps/admin/integration_test/admin_acs_gestao_e2e.dart` |
| Docs | `PROGRESS.md`, `apps/admin/README.md`, `backend/CLAUDE.md`, `apps/CLAUDE.md`, `CLAUDE.md` (raiz), `docs/telas-admin.md` |

### Hipóteses (a confirmar na execução — não tratadas como fato)

- H1: criar `users` (papel `acs`) com `cpfHash` de preenchimento aleatório único e `birthDate` sentinela não afeta nenhum caminho existente (a busca por CPF usa HMAC e só devolve linha de paciente; nada fora do login passwordless lê `birthDate`). O precedente existe: `'development-acs'` no seed e `'admin-ep-$id'` em `test/integration/admin_endpoint_test.dart` L36-46. **Verificar com um teste de integração** que o login passwordless com o CPF/`birthDate` de um ACS criado continua impossível (nenhum HMAC bate).
- H2: a transação interna de `OrmAuditTrail.record` (`session.db.transaction` próprio) convive com uma transação externa do store (aninhamento degenerado no Postgres). Se a auditoria de escrita for chamada **de dentro** de uma transação do store, o comportamento precisa ser verificado na Tarefa 3 — por isso o desenho padrão é: mutação (com transação própria do store) **e depois** `audit.record`.
- H3: o `AlertDialog` do Material 3 tem botões abaixo de 48dp por padrão — a Tarefa 10 deve declarar `minimumSize: Size(48, 52)` nos botões dos diálogos, como `login_screen.dart` faz, e provar com `touch_targets_test.dart`.

---

## 3. Estratégia de reprodução no emulador (linha de base)

A issue é um **enhancement**, não um bug: "reproduzir" aqui é *comprovar o comportamento atual* (a ausência) com evidência verificável antes de mexer em código, e reexecutar exatamente o mesmo caminho no fim para provar a diferença.

### 3.1 Pré-requisitos (já presentes na máquina em 2026-10-08; reconferir)

```bash
export PATH="$HOME/Android/Sdk/platform-tools:$HOME/Android/Sdk/emulator:$HOME/flutter/bin:$PATH"
adb devices                     # espera: emulator-5554	device
docker ps --format '{{.Names}} {{.Status}}'   # espera: sinalacs-serverpod (healthy), postgres, traefik
```

Se o emulador não estiver no ar: `emulator -avd Medium_Phone -no-snapshot -no-boot-anim &`, `adb wait-for-device` (a AVD canônica do repositório é API 36 x86_64, ver `docs/android-avd.md`).

### 3.2 Linha de base (executar ANTES de qualquer alteração — vira a evidência da Tarefa 0)

1. Prova estática (instantânea):
   ```bash
   grep -c "Future<" backend/sinalacs_server/lib/src/endpoints/admin_endpoint.dart   # 4 métodos, todos leitura
   grep -n "Icons.edit_outlined" apps/admin/test/micro_areas_screen_test.dart        # asserção de que NÃO há edição
   ```
2. Prova de widget (hermética, segundos): `cd apps/admin && flutter test test/micro_areas_screen_test.dart` → verde, com a asserção `find.byIcon(Icons.edit_outlined) → findsNothing`.
3. Prova no emulador (real, troca a stack de dev pela de e2e — rodar pelo usuário):
   ```bash
   ./scripts/qa/admin_login_e2e.sh
   ```
   Esperado hoje: `OK — login real do backoffice contra o banco de teste`. Em seguida, com o app aberto (o script instala o APK e roda o teste instrumentado; para ver a tela: `cd apps/admin && flutter run -d emulator-5554 --dart-define=SINALACS_HOST=https://localhost:8443/`), abrir **Microáreas** e registrar: só a listagem, sem "Novo ACS", sem ações por ACS, e o subtítulo "Listagem somente leitura — edição de vínculo fica para uma próxima issue.". Capturar print (`adb exec-out screencap -p > /tmp/issue43-baseline-microareas.png`) para o registro da issue.
4. Ao final, restaurar a stack de desenvolvimento: `docker compose up -d` (o `e2e_stack.sh down` não a reergue sozinho).

### 3.3 Resultado esperado depois da correção (mesmo caminho)

`./scripts/qa/admin_login_e2e.sh` continua verde (regressão) **e** o novo `./scripts/qa/admin_acs_gestao_e2e.sh` fica verde, com os asserts SQL descritos na Tarefa 12. O print da tela Microáreas passa a mostrar as seções "Agentes de saúde (ACS)" e "Equipe do backoffice" com seus botões.

### 3.4 Se a reprodução no emulador não for possível

Registrar em `PROGRESS.md` (Tarefa 13) o que foi tentado (comando, saída) e a limitação; a validação substituída é a bateria de integração do backend contra `postgres-test` + os widget tests — nunca "só análise estática".

---

## 4. Estrutura de arquivos

**Criar (backend):**
- `backend/sinalacs_server/lib/src/application/admin/admin_scope.dart` — `AdminScopeStore` + `AdminScopeResolver` (papel, escopo, recusa auditada). Ponto único da regra de escopo do backoffice.
- `backend/sinalacs_server/lib/src/application/admin/admin_account_service.dart` — `AdminAccountStore` (porta) + `AdminAccountService` (regras de gestão de contas).
- `backend/sinalacs_server/lib/src/application/admin/initial_password.dart` — `AcsInitialPassword.generate([Random?])` (senha inicial legível, ~80 bits).
- `backend/sinalacs_server/lib/src/infrastructure/database/orm_admin_account_store.dart` — SQL/ORM da `AdminAccountStore`.
- `backend/sinalacs_server/lib/src/models/api/admin_acs.spy.yaml`, `admin_staff.spy.yaml`, `admin_acs_creation_result.spy.yaml`, `admin_password_reset_result.spy.yaml`, `admin_staff_mfa_reset_result.spy.yaml`.
- Testes: `test/unit/admin_scope_test.dart`, `test/unit/admin_account_service_test.dart`, `test/integration/admin_account_store_test.dart`, `test/integration/admin_endpoint_accounts_test.dart`.

**Criar (app):**
- `apps/admin/lib/app/admin_accounts.dart` — seções (`AcsManagementSection`, `StaffManagementSection`) e diálogos (novo ACS, vínculo, confirmação destrutiva, senha/código mostrados uma vez).
- Testes: `apps/admin/test/acs_management_screen_test.dart`, `apps/admin/test/admin_accounts_data_source_test.dart`.

**Criar (qa):**
- `scripts/qa/admin_acs_gestao_e2e.sh` + `scripts/qa/admin_acs_gestao_e2e_test.sh` (guarda de invariantes do script, no padrão de `admin_login_e2e_test.sh`).
- `apps/admin/integration_test/admin_acs_gestao_e2e.dart` (sufixo `_e2e` — fora do discovery da CI, de propósito).

**Modificar (backend):**
- `lib/src/endpoints/admin_endpoint.dart` (8 métodos novos + doc da classe).
- `lib/src/application/admin/admin_read_service.dart` (usa o resolver; `auditLogs` escopado na Tarefa 8).
- `lib/src/application/auth/institutional_auth_service.dart` (interface `TotpStore` ganha `clearTotp`).
- `lib/src/application/auth/refresh_token_service.dart` (`RefreshTokenStore.revokeAllForUser`).
- `lib/src/application/auth/upload_token_service.dart` (`UploadTokenStore.revokeAllForUser`).
- `lib/src/infrastructure/database/{orm_acs_credential_store,orm_refresh_token_store,orm_upload_token_store,orm_admin_read_store}.dart`.
- `lib/src/runtime/alert_runtime.dart` (`adminAccountServiceFor`).
- `bin/seed_e2e_fixtures.dart` + `lib/src/infrastructure/testing/e2e_fixtures.dart` (fixture de coordenador).

**Modificar (app):**
- `lib/core/data/{admin_data_source,backend_admin_data_source,mock_admin_data_source}.dart`.
- `lib/app/app.dart` (MicroAreasScreen compõe as seções; passa `role`).
- Testes existentes que **devem** mudar de propósito: `test/micro_areas_screen_test.dart` (inverte a asserção de somente-leitura), `test/mock_admin_data_source_test.dart` (métodos novos), `test/touch_targets_test.dart`, `test/contrast_tokens_test.dart` (só se novo token), `test/admin_home_shell_test.dart` (só se o título mudar — manter "Microáreas e vínculo ACS").

**Modificar (docs/scripts):** `scripts/qa/otp_relay.py` (+ rota `/coordenador`) e `scripts/qa/otp_relay_test.py`; `PROGRESS.md`; `apps/admin/README.md`; `backend/CLAUDE.md`; `apps/CLAUDE.md`; `CLAUDE.md` (raiz); `docs/telas-admin.md`.

---

## 5. Plano de implementação

### Task 0: Linha de base e pré-requisitos (somente leitura, sem commits)

**Files:** nenhum (evidência em texto; o print vai para `/tmp`, nunca versionado).
**Interfaces:** Consumes: nada. Produces: o parágrafo "Reprodução" da issue/seção de prova do `PROGRESS.md` (Tarefa 13).

- [ ] **Step 1: Ferramentas e stack**

```bash
export PATH="$HOME/Android/Sdk/platform-tools:$HOME/Android/Sdk/emulator:$HOME/flutter/bin:$PATH"
adb devices; docker ps --format '{{.Names}} {{.Status}}'
```
Esperado: `emulator-5554 device`; `sinalacs-serverpod` healthy.

- [ ] **Step 2: Prova estática da ausência**

```bash
grep -n "Future<" backend/sinalacs_server/lib/src/endpoints/admin_endpoint.dart
grep -rn "Novo ACS\|createAcs\|resetStaffMfa\|setAcsActive" apps/admin/lib backend/sinalacs_server/lib || echo "ausente (esperado)"
```
Esperado: 4 métodos, todos de leitura; `ausente (esperado)`.

- [ ] **Step 3: Prova de widget atual**

```bash
cd apps/admin && flutter test test/micro_areas_screen_test.dart
```
Esperado: verde — o teste atual **prova** que não há edição.

- [ ] **Step 4: Linha de base no emulador (rodar pelo usuário: `! ./scripts/qa/admin_login_e2e.sh`)**

Esperado: termina com `OK — login real do backoffice contra o banco de teste`. Registrar o print da tela Microáreas (seção 3.2). Restaurar depois: `docker compose up -d`.

- [ ] **Step 5: Registrar a evidência**

Anotar (para colar na Tarefa 13): saída dos comandos acima + link do print. **Nada é commitado nesta tarefa.**

---

### Task 1: `AdminScopeResolver` — a regra única de papel/escopo do backoffice

**Files:**
- Create: `backend/sinalacs_server/lib/src/application/admin/admin_scope.dart`
- Create: `backend/sinalacs_server/test/unit/admin_scope_test.dart`
- Modify: `backend/sinalacs_server/lib/src/application/admin/admin_read_service.dart`

**Interfaces:**
- Consumes: `AdminScope`, `AdminAudit...` — nada de novo; `AuditTrail`, `AuthenticatedUser`, `AlertPermissionException` (gerados/`application`).
- Produces (usado pelas Tarefas 2–8):
  ```dart
  abstract interface class AdminScopeStore { Future<String?> ubsOf(String staffId); }
  class AdminScopeResolver {
    AdminScopeResolver({required AdminScopeStore store, required AuditTrail audit});
    static const negado = 'acesso restrito ao backoffice';
    Future<AdminScope> resolve(AuthenticatedUser user, {required String recurso});
    Future<void> requireAdmin(AuthenticatedUser user, {required String recurso});
  }
  ```
  `resolve`: papel fora de `Authorization.staffRoles` → audita `denied` + `AlertPermissionException`; admin → `AdminScope.system()`; coordenador sem UBS → audita `denied` + exceção; coordenador → `AdminScope.ubs(ubs)`.
  `requireAdmin`: papel != admin → audita `denied` + exceção.

- [ ] **Step 1: Escrever o teste que falha** (`test/unit/admin_scope_test.dart`, espelhando `admin_read_service_test.dart`: `_Store implements AdminScopeStore`, `_Audit extends AuditTrail`)

```dart
test('coordenador sem UBS é recusado, fail-closed, com denied na trilha', () async {
  final audit = _Audit();
  final r = AdminScopeResolver(store: _Store(ubs: {'coord': null}), audit: audit);
  await expectLater(r.resolve(_u('coord', UserRole.coordinator), recurso: 'admin_acs'),
      throwsA(isA<AlertPermissionException>()));
  expect(audit.events.single.result, 'denied');
  expect(audit.events.single.resourceType, 'admin_acs');
});

test('acs e patient são recusados mesmo com token válido', () async { /* role acs/patient → throwsA */ });

test('requireAdmin recusa coordenador e audita; admin passa', () async { /* ... */ });
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd backend/sinalacs_server && dart test test/unit/admin_scope_test.dart`
Expected: FAIL — `admin_scope.dart` não existe.

- [ ] **Step 3: Implementar `admin_scope.dart`** (mover, palavra por palavra, o corpo de `AdminReadService._escopo` L118-130 e o bloco admin de `auditLogs` L108-116 para o resolver — comportamento idêntico: mesmos `resourceType`, mesmos `result`, mesma mensagem).

- [ ] **Step 4: `AdminReadService` passa a usar o resolver** — o construtor público **não muda** (`{required this.store, required this.audit, DateTime Function()? clock}`); internamente cria `_resolver = AdminScopeResolver(store: store, audit: audit)` (campo `late final`). Trocar as 4 chamadas `_escopo(...)`/bloco admin. Remover o código duplicado.

- [ ] **Step 5: Provar que nada mudou de comportamento**

Run: `cd backend/sinalacs_server && dart test test/unit/admin_read_service_test.dart`
Expected: PASS **sem editar o arquivo de teste** (critério objetivo da refatoração: os 9 testes existentes passam intactos). Depois: `dart test test/unit/admin_scope_test.dart` → PASS.

- [ ] **Step 6: Commit**

```bash
git add backend/sinalacs_server/lib/src/application/admin/admin_scope.dart \
        backend/sinalacs_server/lib/src/application/admin/admin_read_service.dart \
        backend/sinalacs_server/test/unit/admin_scope_test.dart
git commit -m "refactor(admin): extrai o escopo do backoffice para AdminScopeResolver (#43)"
```

---

### Task 2: Listagem de ACS e da equipe (leitura)

**Files:**
- Create: `backend/sinalacs_server/lib/src/models/api/admin_acs.spy.yaml`, `admin_staff.spy.yaml`
- Create: `backend/sinalacs_server/lib/src/application/admin/admin_account_service.dart` (nesta tarefa: porta + listagens)
- Create: `backend/sinalacs_server/lib/src/infrastructure/database/orm_admin_account_store.dart`
- Create: `backend/sinalacs_server/test/unit/admin_account_service_test.dart`
- Create: `backend/sinalacs_server/test/integration/admin_account_store_test.dart`
- Modify: `backend/sinalacs_server/lib/src/endpoints/admin_endpoint.dart`, `lib/src/runtime/alert_runtime.dart`
- Test: `backend/sinalacs_server/test/integration/admin_endpoint_accounts_test.dart`

**Interfaces:**
- Consumes: `AdminScopeResolver` (T1), `AdminScope`.
- Produces (usado pelas Tarefas 3–8 e pelo app via client gerado):
  ```dart
  class AdminAcs {            // protocolo gerado
    String id; String name; String enrollmentId;
    String ubsId; String ubsName;
    String? microAreaId; String? microAreaName;
    bool active; bool mfaActive;
  }
  class AdminStaff {          // protocolo gerado
    String id; String name; String enrollmentId; UserRole role;
    String? ubsName; bool active; bool mfaActive;
  }
  abstract interface class AdminAccountStore implements AdminScopeStore {
    Future<List<AdminAcs>> acsList(AdminScope scope);
    Future<List<AdminStaff>> staffList();
    Future<AdminAcs?> acsById(AdminScope scope, String acsId);
    Future<AdminStaff?> staffById(String staffId);
  }
  // AdminAccountService
  Future<List<AdminAcs>> acsList(AuthenticatedUser user);
  Future<List<AdminStaff>> staffList(AuthenticatedUser user);   // requireAdmin
  ```

- [ ] **Step 1: Modelos `spy.yaml`** — `admin_acs.spy.yaml` com o doc "ACS no backoffice (#43): identificação profissional, território e estado de acesso. Nunca inclui CPF, senha ou contato." e os campos acima (`mfaActive` = `totpEnabledAt IS NOT NULL`); `admin_staff.spy.yaml` análogo. Sem migração (nenhuma tabela nova).

- [ ] **Step 2: Regenerar cliente e tipos**

Run: `cd backend/sinalacs_server && serverpod generate`
Expected: `lib/src/generated/**` e `backend/sinalacs_client/**` ganham `AdminAcs`/`AdminStaff`; nenhuma migração nova é sugerida. Depois `cd backend && dart analyze` → sem erros.

- [ ] **Step 3: Teste unitário do serviço que falha** (`admin_account_service_test.dart`; fakes de `AdminAccountStore`, `AcsCredentialStore`, `TotpStore`, `RefreshTokenStore`, `UploadTokenStore`, `StaffActivationStore`, `PasswordHasher`, `AuditTrail`):

```dart
test('coordenador lista só a própria UBS; a leitura é auditada com o recurso admin_acs', () async {
  await servico.acsList(coordA);
  expect(store.ultimoEscopo!.ubsId, 'ubs-a');
  expect(audit.events.single, isA<AuditEvent>()
      .having((e) => e.actionType, 'actionType', 'read')
      .having((e) => e.resourceType, 'resourceType', 'admin_acs'));
});

test('staffList é só do administrador: coordenador recebe recusa auditada', () async {
  await expectLater(servico.staffList(coordA), throwsA(isA<AlertPermissionException>()));
  expect(audit.events.single.result, 'denied');
});
```

- [ ] **Step 4: Rodar e ver falhar** — `dart test test/unit/admin_account_service_test.dart` → FAIL (arquivo não existe).

- [ ] **Step 5: Implementar o serviço** (`AdminAccountService` com o construtor completo já definido: `store`, `credentials`, `totpStore`, `activationStore`, `refreshStore`, `uploadStore`, `hasher`, `audit`, `Random? random`, `DateTime Function()? clock`; nesta tarefa só construtor + `acsList`/`staffList` + os dois helpers privados usados pelas tarefas seguintes). Regra de auditoria documentada no topo da classe (Global Constraints). Helpers (interface interna, usados nas Tarefas 3–7):

  ```dart
  /// Recusa com linha `denied` na trilha ANTES de lançar (fail-closed), a mesma
  /// mensagem para "não existe" e "não é seu". [message] só é sobre a própria
  /// entrada do operador (validação) — nunca revela existência de outro território.
  Future<Never> _negar(AuthenticatedUser user, String recurso,
      {String message = 'Não foi possível concluir a operação com os dados informados.'}) async {
    await audit.record(AuditEvent(userId: user.id, actionType: 'write',
        resourceType: recurso, result: 'denied'));
    throw AdminInvalidRequestException(message: message);
  }

  /// Sucesso: audita DEPOIS do commit, com `record` (não `recordSafely`).
  Future<void> _auditar(AuthenticatedUser user, String recurso,
      {required String result, required String resourceId}) =>
      audit.record(AuditEvent(userId: user.id, actionType: 'write',
          resourceType: recurso, resourceId: resourceId, result: result));
  ```

- [ ] **Step 6: Implementar `OrmAdminAccountStore`** com o SQL:

```sql
SELECT u.id, u.name, acs."enrollmentId", acs."ubsId", ub.name,
       m.id, m.name, acs.active, (uc."totpEnabledAt" IS NOT NULL)
FROM acs
JOIN users u ON u.id = acs.id
JOIN ubs ub ON ub.id = acs."ubsId"
LEFT JOIN micro_areas m ON m.id = u."microAreaId"
LEFT JOIN user_credentials uc ON uc."userId" = acs.id
WHERE (@ubs::uuid IS NULL OR acs."ubsId" = @ubs::uuid)
ORDER BY u.name, u.id
```
(A lista de ACS inclui quem não tem microárea — `LEFT JOIN`; o escopo do coordenador é por `acs."ubsId"`, o mesmo campo que o login usa.) `staffList`:
```sql
SELECT u.id, u.name, s."enrollmentId", u.role, ub.name, s.active, (uc."totpEnabledAt" IS NOT NULL)
FROM staff_accounts s
JOIN users u ON u.id = s.id
LEFT JOIN ubs ub ON ub.id = s."ubsId"
LEFT JOIN user_credentials uc ON uc."userId" = s.id
ORDER BY u.name, u.id
```

- [ ] **Step 7: Endpoint + runtime** — `admin.acs`, `admin.staff` em `AdminEndpoint` (mesmo arranjo das leituras existentes: `AlertRuntime.instance.adminAccountServiceFor(session).xxx(authenticate(accessToken))`), e `adminAccountServiceFor` no `AlertRuntime` montando `OrmAdminAccountStore(session: () => session)` + os stores ORM existentes. Atualizar o doc da classe `AdminEndpoint` ("Somente leitura" → descrever leitura e escrita).

- [ ] **Step 8: Integração com Postgres real e tokens reais** — `admin_account_store_test.dart` (aproveitar o `_seed` de `test/integration/admin_endpoint_test.dart` L68-167 como modelo: UBS A/B, microáreas, ACS, admin, coordenador com e sem UBS) provando: coordenador não vê ACS de outra UBS; ACS sem microárea aparece com `microAreaId == null`; `mfaActive` reflete `totpEnabledAt`. `admin_endpoint_accounts_test.dart`: papel recusado (`acs`/`patient`) com token válido → `AlertPermissionException` + linha `denied`; sucesso grava `read/success`. Rodar: `docker compose --profile test up -d postgres-test && dart test test/integration/admin_account_store_test.dart test/integration/admin_endpoint_accounts_test.dart` → PASS.

- [ ] **Step 9: Suíte completa e commit**

Run: `cd backend/sinalacs_server && dart test test/unit && dart analyze`
Expected: PASS/limpo. Depois:
```bash
git add backend/sinalacs_server/lib/src/models/api/admin_acs.spy.yaml \
        backend/sinalacs_server/lib/src/models/api/admin_staff.spy.yaml \
        backend/sinalacs_server/lib/src/application/admin/admin_account_service.dart \
        backend/sinalacs_server/lib/src/infrastructure/database/orm_admin_account_store.dart \
        backend/sinalacs_server/lib/src/endpoints/admin_endpoint.dart \
        backend/sinalacs_server/lib/src/runtime/alert_runtime.dart \
        backend/sinalacs_server/lib/src/generated backend/sinalacs_client \
        backend/sinalacs_server/test/unit/admin_account_service_test.dart \
        backend/sinalacs_server/test/integration/admin_account_store_test.dart \
        backend/sinalacs_server/test/integration/admin_endpoint_accounts_test.dart
git commit -m "feat(admin): lista ACS e equipe do backoffice por escopo de UBS (#43)"
```

---

### Task 3: Cadastro de ACS com senha inicial gerada

**Files:**
- Create: `backend/sinalacs_server/lib/src/application/admin/initial_password.dart` + teste unitário em `test/unit/admin_account_service_test.dart` (mesmo arquivo, novo grupo) 
- Create: `backend/sinalacs_server/lib/src/models/api/admin_acs_creation_result.spy.yaml`
- Modify: `admin_account_service.dart` (`AdminAccountStore.insertAcs`, `enrollmentIdTaken`, `microAreaUbs`), `orm_admin_account_store.dart`, `admin_endpoint.dart`
- Test: unit (`admin_account_service_test.dart`), integração (`admin_account_store_test.dart`)

**Interfaces:**
- Consumes: T1/T2.
- Produces:
  ```dart
  class AcsInitialPassword { static String generate([Random? random]); } // ex.: 'K7QM-3XPD-9FTB-VRZ8' (~80 bits, alfabeto sem 0/O/1/I/L)
  class AdminAcsCreationResult { AdminAcs acs; String initialPassword; } // protocolo gerado
  // AdminAccountStore
  Future<({String? ubsId, String? name})?> microAreaFor(String microAreaId);
  Future<bool> enrollmentIdTaken(String enrollmentId);
  Future<AdminAcs?> insertAcs({required String name, required String enrollmentId,
      required String microAreaId, required String ubsId,
      required PasswordDigest digest, required DateTime at});
  // AdminAccountService
  Future<AdminAcsCreationResult> createAcs(AuthenticatedUser user, {required String name,
      required String enrollmentId, required String microAreaId});
  ```

- [ ] **Step 1: Testes que falham — serviço e gerador**

```dart
test('createAcs: nome/matrícula/microárea inválidos → AdminInvalidRequestException, nada escrito, recusa auditada', () async { /* trim + vazio; microárea inexistente e microárea de OUTRA UBS devolvem a MESMA mensagem 'Microárea não encontrada.' */ });
test('createAcs: coordenador cadastra na própria UBS e a auditoria registra created com o id do novo ACS', () async { /* audit: actionType write, resourceType admin_acs, result created, resourceId = id novo */ });
test('createAcs: matrícula duplicada → mesma mensagem de validação (nune 500) e auditoria denied', () async {});
test('AcsInitialPassword.generate: 16 caracteres do alfabeto, dois sorteios diferem, formato XXXX-XXXX-XXXX-XXXX', () {});
```

- [ ] **Step 2: Rodar e ver falhar** — `dart test test/unit/admin_account_service_test.dart` → FAIL.

- [ ] **Step 3: Implementar o gerador** (`initial_password.dart`, espelhando `StaffActivationCode` L10-27: `Random` injetável, alfabeto `'ABCDEFGHJKMNPQRSTUVWXYZ23456789'`, 16 chars em 4 grupos de 4; doc explicando por que **não** vem do operador: senha fraca digitada vira credencial fraca no RF07, e o padrão do repositório para credencial entregue fora de banda é gerar e mostrar uma vez — #48).

- [ ] **Step 4: Implementar `createAcs` no serviço**

```dart
Future<AdminAcsCreationResult> createAcs(AuthenticatedUser user,
    {required String name, required String enrollmentId, required String microAreaId}) async {
  const recurso = 'admin_acs';
  final escopo = await _resolver.resolve(user, recurso: recurso);
  final nome = name.trim();
  final matricula = enrollmentId.trim();
  final ma = await store.microAreaFor(microAreaId);
  // mesma resposta para "não existe" e "não é sua" (não vaza território alheio)
  if (nome.isEmpty || nome.length > 120 || matricula.isEmpty || matricula.length > 32) {
    await _negar(user, recurso, message: 'Informe nome e matrícula do ACS.');
  }
  if (ma == null || (escopo.ubsId != null && ma.ubsId != escopo.ubsId)) {
    await _negar(user, recurso, message: 'Microárea não encontrada.');
  }
  if (await store.enrollmentIdTaken(matricula)) {
    await _negar(user, recurso, message: 'Já existe um ACS com esta matrícula.');
  }
  final senha = AcsInitialPassword.generate(_random);
  final digest = await hasher.derive(senha);
  final acs = await store.insertAcs(name: nome, enrollmentId: matricula, microAreaId: microAreaId,
      ubsId: ma!.ubsId, digest: digest, at: _clock().toUtc());
  if (acs == null) { await _negar(user, recurso, message: 'Já existe um ACS com esta matrícula.'); }
  await audit.record(AuditEvent(userId: user.id, actionType: 'write', resourceType: recurso,
      resourceId: acs!.id, result: 'created'));
  return AdminAcsCreationResult(acs: acs, initialPassword: senha);
}
```

- [ ] **Step 5: Implementar `insertAcs` no store — uma transação, três tabelas**

```dart
// users (papel acs) + acs + user_credentials numa transação; devolve null quando
// o índice único de acs."enrollmentId" dispara (corrida com outro cadastro).
// cpfHash: placeholder aleatório único ('acs-sem-cpf-<uuid>') — NUNCA o HMAC de
// um CPF real: verifyOtp emite papel de PACIENTE, e um CPF na linha do ACS
// faria o login passwordless abrir sessão de paciente com o id/microárea dele
// (spec/lgpd_data_audit.md, nota de seed). birthDate: sentinela 1900-01-01 UTC,
// documentado — nada fora do login passwordless lê esse campo.
return session.db.transaction((transaction) async {
  try {
    await User.db.insertRow(session, User(id: id, cpfHash: 'acs-sem-cpf-$id', name: nome,
        birthDate: DateTime.utc(1900, 1, 1), role: UserRole.acs,
        microAreaId: UuidValue.fromString(microAreaId), createdAt: at, updatedAt: at),
        transaction: transaction);
    if (_debugFailAfterUsersInsert) throw StateError('falha injetada (só em teste)');
    await Acs.db.insertRow(session, Acs(id: id, enrollmentId: matricula,
        ubsId: UuidValue.fromString(ubsId), active: true), transaction: transaction);
    await UserCredential.db.insertRow(session, UserCredential(userId: id, /* digest */),
        transaction: transaction);
  } on DatabaseException catch (e) {   // 23505 = unique_violation
    if (e.code == '23505') return null;
    rethrow;
  }
  return _acsById(transaction|session, id);
});
```
(`_debugFailAfterUsersInsert` como campo `@visibleForTesting`, precedente `orm_data_subject_rights_store.dart` `_debugFailAfterTokenDelete`.)

- [ ] **Step 6: Endpoint** `admin.createAcs(Session, {required String accessToken, required String name, required String enrollmentId, required String microAreaId})` → delega. `serverpod generate`.

- [ ] **Step 7: Integração — os três casos críticos** (`admin_account_store_test.dart` + endpoint):

```dart
test('cadastro grava users+acs+user_credentials e o ACS consegue logar com a senha gerada', () async {
  final r = await servico.createAcs(admin, name: 'Nova ACS', enrollmentId: 'ACS-43-1', microAreaId: _maA);
  final login = await InstitutionalAuthService(store: OrmAcsCredentialStore(...), hasher: Argon2PasswordHasher(), audit: fake)
      .login(matricula: 'ACS-43-1', password: r.initialPassword);
  expect(login.microAreaId, _maA);
});
test('falha injetada depois de users não deixa órfão: nem users, nem acs, nem credencial', () async {...});
test('matrícula repetida devolve null (corrida) e o serviço responde validação, não 500', () async {...});
test('o CPF/birthDate sentinela do ACS não abre login passwordless de paciente', () async {
  // PasswordlessAuthService.findByCpfHash com o CPF correspondente ao placeholder → null
});
```

- [ ] **Step 8: Rodar tudo e commitar**

Run: `cd backend/sinalacs_server && dart test test/unit/admin_account_service_test.dart && dart test test/integration/admin_account_store_test.dart`
Expected: PASS.
```bash
git add backend/sinalacs_server/lib/src/application/admin/initial_password.dart \
        backend/sinalacs_server/lib/src/models/api/admin_acs_creation_result.spy.yaml \
        backend/sinalacs_server/lib/src/application/admin/admin_account_service.dart \
        backend/sinalacs_server/lib/src/infrastructure/database/orm_admin_account_store.dart \
        backend/sinalacs_server/lib/src/endpoints/admin_endpoint.dart \
        backend/sinalacs_server/lib/src/generated backend/sinalacs_client \
        backend/sinalacs_server/test/unit/admin_account_service_test.dart \
        backend/sinalacs_server/test/integration/admin_account_store_test.dart
git commit -m "feat(admin): cadastro de ACS com senha inicial gerada e mostrada uma vez (#43)"
```

---

### Task 4: Vínculo ACS ↔ microárea (cadastro já nasce vinculado; vincular move)

**Files:** Modify: `admin_account_service.dart`, `orm_admin_account_store.dart`, `admin_endpoint.dart`; Test: unit + integração (mesmos arquivos das tarefas anteriores).

**Interfaces:**
- Produces:
  ```dart
  // AdminAccountStore
  Future<AdminAcs?> setAcsMicroArea({required String acsId, required String microAreaId,
      required String ubsId, required AdminScope scope, required DateTime at});
  // AdminAccountService
  Future<AdminAcs> setAcsMicroArea(AuthenticatedUser user,
      {required String acsId, required String microAreaId});
  ```

- [ ] **Step 1: Teste que falha** — regras: microárea inexistente e microárea de outra UBS → `'Microárea não encontrada.'` (mesma); ACS inexistente **ou de outra UBS** → `'ACS não encontrado.'` (mesma recusa, auditada `denied`); coordenador movendo ACS da própria UBS para microárea da própria UBS → sucesso, audit `result: 'micro_area_changed'`, `resourceId: acsId`.

- [ ] **Step 2: Rodar e ver falhar** → FAIL.

- [ ] **Step 3: Implementar no store com o escopo **dentro** do `WHERE`** (fecha o TOCTOU):

```sql
WITH alvo AS (
  SELECT a.id FROM acs a
   WHERE a.id = @acs::uuid AND (@ubs::uuid IS NULL OR a."ubsId" = @ubs::uuid)
)
UPDATE acs SET "ubsId" = @ubs::uuid WHERE id IN (SELECT id FROM alvo) RETURNING id;
```
e, na MESMA transação, `UPDATE users SET "microAreaId" = @ma, "updatedAt" = @at WHERE id = @acs::uuid;`. (`acs."ubsId"` é derivado da microárea, nunca do chamador.) A microárea-alvo é validada contra o escopo **antes** (uniformidade da mensagem) e o `WHERE` do `UPDATE` repete o predicado (defesa em profundidade).

- [ ] **Step 4: Implementar no serviço** (validações iguais às da criação; resultado audita depois do commit; devolve `acsById(escopo, acsId)!`).

- [ ] **Step 5: Endpoint** `admin.setAcsMicroArea` + `serverpod generate`.

- [ ] **Step 6: Integração** — prova de que a mudança pega no próximo refresh: login do ACS com a microárea antiga grava o JWT; `setAcsMicroArea`; `auth.refreshSession` → o novo JWT carrega a microárea nova (`RefreshTokenService.refresh` já relê a linha do banco a cada rotação — este teste **prova** a relitura, e é o que sustenta INV-01 depois de um vínculo novo). Rodar → PASS.

- [ ] **Step 7: Commit**

```bash
git add backend/sinalacs_server/lib backend/sinalacs_client backend/sinalacs_server/test
git commit -m "feat(admin): vincula e move ACS entre microáreas com escopo de UBS (#43)"
```

---

### Task 5: Ativar/desativar ACS com revogação de sessões e do envio diferido

**Files:** Modify: `refresh_token_service.dart` (`RefreshTokenStore.revokeAllForUser`), `upload_token_service.dart` (`UploadTokenStore.revokeAllForUser`), `orm_refresh_token_store.dart`, `orm_upload_token_store.dart`, `admin_account_service.dart`, `orm_admin_account_store.dart`, `admin_endpoint.dart`; Test: unit + integração.

**Interfaces:**
- Produces:
  ```dart
  // RefreshTokenStore / UploadTokenStore
  Future<void> revokeAllForUser(String userId, DateTime at);
  // AdminAccountStore
  Future<bool> setAcsActive({required String acsId, required AdminScope scope, required bool active, required DateTime at});
  // AdminAccountService
  Future<AdminAcs> setAcsActive(AuthenticatedUser user, {required String acsId, required bool active});
  ```

- [ ] **Step 1: Teste que falha** — desativar audita `deactivated`; reativar audita `activated`; desativar já inativo é idempotente (mesmo resultado, nova linha de auditoria); ACS de outra UBS/inexistente → `'ACS não encontrado.'` + `denied`.

- [ ] **Step 2: Implementar `revokeAllForUser` nos dois stores ORM**

```sql
UPDATE "acs_refresh_tokens" SET "revokedAt" = @at WHERE "userId" = @userId::uuid AND "revokedAt" IS NULL;
UPDATE "acs_upload_tokens"  SET "revokedAt" = @at WHERE "userId" = @userId::uuid AND "revokedAt" IS NULL;
```
(Dois `UPDATE` simples, não um por família: a família é agrupamento do refresh, mas a revogação por conta é o que a desativação exige. Doc de interface: "Todas as famílias do usuário, para a desativação; o `logout` continua revogando só a própria família".)

- [ ] **Step 3: Implementar `setAcsActive` no store** — uma transação: `UPDATE acs SET active=@a WHERE id=@id AND (@ubs IS NULL OR "ubsId"=@ubs)` (Retorno booleano) + quando `!active`, `revokeAllForUser` das duas tabelas na mesma transação. Usuário inativo não loga (`_authenticatePassword` já recusa) e `visits.syncDeferred`/`refreshSession` já recusam pelo `findAccount`.

- [ ] **Step 4: Serviço + endpoint** (`admin.setAcsActive`) + `serverpod generate`.

- [ ] **Step 5: Integração — a prova da revogação** (Review Focus nº 4):

```dart
test('desativar revoga refresh e envio diferido: refreshSession e syncDeferred são recusados depois', () async {
  final login = await endpoints.auth.loginInstitutional(sessionBuilder, matricula: 'ACS-43-1', password: senha, deviceId: 'dev-1');
  await endpoints.admin.setAcsActive(sessionBuilder, accessToken: tokenAdmin, acsId: id, active: false);
  // SQL: acs_refresh_tokens e acs_upload_tokens do usuário, revokedAt IS NOT NULL
  await expectLater(endpoints.auth.refreshSession(sessionBuilder, refreshToken: login.refreshToken!, deviceId: 'dev-1'),
      throwsA(isA<SessionExpiredException>()));
  await expectLater(endpoints.visits.syncDeferred(sessionBuilder, uploadToken: login.uploadToken!, ...),
      throwsA(isA<SessionExpiredException>()));
  // e o login por senha: 'Este acesso está inativo.'
});
```

- [ ] **Step 6: Rodar tudo e commitar**

```bash
git add backend/sinalacs_server/lib backend/sinalacs_client backend/sinalacs_server/test
git commit -m "feat(admin): ativa/desativa ACS revogando refresh token e envio diferido (#43)"
```

---

### Task 6: Redefinir senha e redefinir MFA do ACS

**Files:** Modify: `institutional_auth_service.dart` (`TotpStore.clearTotp`), `orm_acs_credential_store.dart` (`clearTotp` + fix `lockStreak` em `saveCredential`), `admin_account_service.dart`, `admin_endpoint.dart`, modelo `admin_password_reset_result.spy.yaml`; Test: unit + integração.

**Interfaces:**
- Produces:
  ```dart
  abstract interface class TotpStore { /* … */
    Future<void> clearTotp(String acsId, DateTime at); }
  class AdminPasswordResetResult { String newPassword; }   // protocolo gerado
  Future<AdminPasswordResetResult> resetAcsPassword(AuthenticatedUser user, {required String acsId});
  Future<void> resetAcsMfa(AuthenticatedUser user, {required String acsId});
  ```

- [ ] **Step 1: Testes que falham**

```dart
test('redefinir senha devolve senha nova, grava Argon2id novo e zera bloqueio (failedAttempts, lockedUntil e lockStreak)', () async {
  // conta bloqueada com lockStreak=2; após reset, login com a senha nova funciona e a linha está zerada
});
test('redefinir MFA zera as quatro colunas totp* e a próxima entrada pede ativação de novo', () async {
  // MFA ativa → reset → login sem código recebe MfaEnrollmentRequiredException (com requireMfa true)
  // e beginTotpEnrollment volta a funcionar (a mensagem 'Peça a redefinição à coordenação' agora tem caminho)
});
test('resetAcsMfa de ACS sem MFA é idempotente e ainda audita mfa_reset', () async {});
```

- [ ] **Step 2: Rodar e ver falhar** → FAIL.

- [ ] **Step 3: `TotpStore.clearTotp`** na interface + implementação ORM:

```dart
Future<void> clearTotp(String acsId, DateTime at) async {
  await UserCredential.db.updateWhere(_session(),
    columnValues: (t) => [t.totpSecretEncrypted(null), t.totpKeyVersion(null),
        t.totpEnabledAt(null), t.totpLastStep(null), t.updatedAt(at)],
    where: (t) => t.userId.equals(UuidValue.fromString(acsId)));
}
```

- [ ] **Step 4: Fix de `saveCredential`** — acrescentar `..lockStreak = 0` ao ramo de substituição (hoje preserva a contagem de rodadas de bloqueio de uma credencial que deixou de existir) + doc de uma linha. Teste unitário do store ORM não é possível sem banco → a prova é o teste de integração do Step 1.

- [ ] **Step 5: Serviço** — `resetAcsPassword` reusa `credentials.saveCredential(acsId, await hasher.derive(nova), at)` (já existe e é exatamente "substituir credencial"); `resetAcsMfa` chama `totpStore.clearTotp`. Ambos: escopo resolvido, alvo validado (`acsById` dentro do escopo → senão `'ACS não encontrado.'` + `denied`), auditoria `password_reset` / `mfa_reset` com `resourceId`.

- [ ] **Step 6: Endpoint + `serverpod generate`** — `admin.resetAcsPassword`, `admin.resetAcsMfa`.

- [ ] **Step 7: Integração e suíte** — os três testes do Step 1 contra Postgres real, mais regressão de `institutional_auth_service`/`staff_login_test`. Depois:

```bash
git add backend/sinalacs_server/lib backend/sinalacs_client backend/sinalacs_server/test
git commit -m "feat(admin): redefine senha e MFA do ACS com trilha e desbloqueio (#43)"
```

---

### Task 7: Redefinir MFA do staff e emitir o código de ativação pela tela (deferimento da #48)

**Files:** Modify: `admin_account_service.dart`, `orm_admin_account_store.dart` (`resetStaffMfa` transacional), `admin_endpoint.dart`, modelo `admin_staff_mfa_reset_result.spy.yaml`; Test: unit + integração.

**Interfaces:**
- Produces:
  ```dart
  class AdminStaffMfaResetResult { String activationCode; DateTime activationCodeExpiresAt; } // protocolo gerado
  // AdminAccountStore
  Future<bool> resetStaffMfa({required String staffId, required String codeHash,
      required DateTime expiresAt, required String issuedBy, required String at});
  // AdminAccountService
  Future<AdminStaffMfaResetResult> resetStaffMfa(AuthenticatedUser user, {required String staffId});
  ```

- [ ] **Step 1: Testes que falham**
  - só admin: coordenador recebe `AlertPermissionException` auditada (`denied`), inclusive para a própria conta;
  - a própria conta do chamador é recusada (`AdminInvalidRequestException('Uma conta não redefine a própria MFA: peça a outro administrador.')`) — decisão registrada (seção 9);
  - alvo inativo/inexistente → `'Conta de equipe não encontrada.'`;
  - sucesso: `totp*` zeradas **e** `activationCodeHash/ExpiresAt/IssuedBy/IssuedAt` gravados na mesma transação; o código devolvido casa com o hash (`StaffActivationCode.matches`), vale 24 h; auditoria `admin_staff`/`mfa_reset` com `resourceId` do alvo (fecha a pendência L665(2): a emissão pela tela **entra** na trilha).

- [ ] **Step 2: Implementar** — serviço gera com `StaffActivationCode.generate(_random)`, `issuedBy: user.id` (UUID do ator; o rótulo humano vem da trilha), store faz `clearTotp` + `activationStore.issue(...)` numa transação, endpoint `admin.resetStaffMfa` + `serverpod generate`.

- [ ] **Step 3: Integração — o ciclo completo**: reset → `auth.beginStaffTotpEnrollment` com o código devolvido funciona (com `activationCode`), `confirmStaffTotpEnrollment` ativa a MFA nova, e o código antigo (se havia) não vale mais. Rodar suíte e commitar:

```bash
git add backend/sinalacs_server/lib backend/sinalacs_client backend/sinalacs_server/test
git commit -m "feat(admin): redefinição de MFA do staff com código de ativação emitido pela tela (#43)"
```

---

### Task 8: Auditoria por UBS para o coordenador (deferimento da #40; removível se a PR precisar encolher)

**Files:** Modify: `orm_admin_read_store.dart` (`auditLogs`), `admin_read_service.dart` (`auditLogs` deixa de ser admin-only); Test: unit (`admin_read_service_test.dart` — acrescentar casos, sem tocar os 9 existentes) + integração (`admin_read_store_test.dart`).

- [ ] **Step 1: Testes que falham** — coordenador com UBS lê só linhas cujo `userId` pertence a usuário com `users."microAreaId"` numa microárea da UBS dele; linhas de staff (sem microárea) ficam invisíveis para o coordenador; admin continua vendo tudo; coordenador sem UBS continua recusado (`denied`).

- [ ] **Step 2: Implementar na consulta** de `auditLogs` (o parâmetro `@ubs` já é o padrão do arquivo):

```sql
WHERE (@before::bigint IS NULL OR l.sequence < @before::bigint)
  AND (@ubs::uuid IS NULL OR l."userId" IN (
        SELECT u.id FROM users u
        JOIN micro_areas m ON m.id = u."microAreaId"
        WHERE m."ubsId" = @ubs::uuid))
```

- [ ] **Step 3: `AdminReadService.auditLogs`** passa a usar `_resolver.resolve(user, recurso: 'admin_audit_logs')` e repassa o escopo ao store (a assinatura do store ganha `AdminScope scope`). Rodar unit + integração → PASS; atualizar o comentário L56 do serviço (o deferimento foi cumprido).

- [ ] **Step 4: Commit**

```bash
git add backend/sinalacs_server/lib backend/sinalacs_server/test
git commit -m "feat(admin): auditoria escopada à UBS para o coordenador (#43)"
```

---

### Task 9: App — camada de dados (interface, backend e mock)

**Files:** Modify: `apps/admin/lib/core/data/admin_data_source.dart`, `backend_admin_data_source.dart`, `mock_admin_data_source.dart`; Test: `apps/admin/test/admin_accounts_data_source_test.dart` (novo), `apps/admin/test/mock_admin_data_source_test.dart` (acrescentar).

**Interfaces:**
- Produces (usado pela Tarefa 10):
  ```dart
  class AcsSummary { String id; String name; String enrollmentId; String ubsName;
      String? microAreaId; String? microAreaName; bool active; bool mfaActive; }
  class StaffSummary { String id; String name; String enrollmentId; String role;
      String? ubsName; bool active; bool mfaActive; }
  class NewAcsCredential { AcsSummary acs; String initialPassword; }
  class NewStaffActivation { String code; DateTime expiresAt; }
  /// Falha de validação cuja mensagem VEM do servidor e pode ir à tela: é o
  /// texto sobre a própria entrada do operador ('Já existe um ACS…'), nunca
  /// dado de outro território nem o motivo de uma recusa de permissão.
  class AdminValidationFailure implements Exception { final String message; }
  // AdminDataSource (acrescentar):
  Future<List<AcsSummary>> fetchAcs();
  Future<List<StaffSummary>> fetchStaff();
  Future<NewAcsCredential> createAcs({required String name, required String enrollmentId, required String microAreaId});
  Future<AcsSummary> setAcsMicroArea({required String acsId, required String microAreaId});
  Future<AcsSummary> setAcsActive({required String acsId, required bool active});
  Future<String> resetAcsPassword({required String acsId});
  Future<void> resetAcsMfa({required String acsId});
  Future<NewStaffActivation> resetStaffMfa({required String staffId});
  ```

- [ ] **Step 1: Testes que falham** (`FakeEndpointCaller` de `test/support/fake_admin_auth.dart`):

```dart
test('createAcs manda token e payload, e devolve a senha inicial uma vez', () async {
  final r = await fonte.createAcs(name: 'Nova', enrollmentId: 'ACS-9', microAreaId: 'ma-1');
  expect(caller.lastArgs, {'accessToken': 'token-de-teste', 'name': 'Nova', 'enrollmentId': 'ACS-9', 'microAreaId': 'ma-1'});
  expect(r.initialPassword, 'SENHA-INICIAL-DE-TESTE');
});
test('AdminInvalidRequestException vira AdminValidationFailure com a mensagem do servidor', () async {
  caller.error = api.AdminInvalidRequestException(message: 'Já existe um ACS com esta matrícula.');
  await expectLater(fonte.createAcs(...), throwsA(isA<AdminValidationFailure>()
      .having((e) => e.message, 'message', 'Já existe um ACS com esta matrícula.')));
});
test('AlertPermissionException continua AdminDataFailure (texto fixo) nas escritas', () async {});
test('mfaActive/role são traduzidos por nome, nunca por índice', () async {});
```

- [ ] **Step 2: Rodar e ver falhar** — `cd apps/admin && flutter test test/admin_accounts_data_source_test.dart` → FAIL.

- [ ] **Step 3: Implementar** — `BackendAdminDataSource`: um `_guardEscrita` próprio que mapeia `AdminInvalidRequestException` → `AdminValidationFailure(e.message)` (o `_guard` atual fica intocado para as leituras, que continuam com `'Parâmetro de paginação inválido.'`); enums do cliente com prefixo `api.` e tradução por nome (padrão do arquivo). `MockAdminDataSource`: estado mutável (`_acs`, `_staff`), listas públicas de chamadas para os testes de widget (`desativados`, `vinculados`, `senhasRedefinidas`, `mfasRedefinidas`), senha `'SENHA-INICIAL-DE-TESTE'` e código `'ABCD-EFGH-JKLM-NPQR-STUV'`. Sementes que os testes da Tarefa 10 usam por chave: ACS `acs-1` (Carla Nogueira, `ACS-001`, microárea `ma-12`, ativa, sem MFA) e conta de equipe `staff-1` (`COO-001`, papel `coordinator`, UBS sintética).

- [ ] **Step 4: Rodar tudo e commitar** — `flutter analyze && flutter test test/admin_accounts_data_source_test.dart test/mock_admin_data_source_test.dart` → PASS; commit `feat(admin-app): camada de dados da gestão de contas do backoffice (#43)`.

---

### Task 10: App — UI de gestão na tela Microáreas, com confirmação explícita

**Files:** Create: `apps/admin/lib/app/admin_accounts.dart`; Modify: `apps/admin/lib/app/app.dart` (`MicroAreasScreen` compõe as seções; `AdminHomeShell._telaAtual` passa `widget.session.role`); Test: `apps/admin/test/acs_management_screen_test.dart` (novo), `apps/admin/test/micro_areas_screen_test.dart` (inverter a asserção de somente-leitura), `apps/admin/test/error_handling_test.dart` (se a mensagem genérica de falha da tela mudar).

**Interfaces:**
- Consumes: T9 (`AcsSummary`, `StaffSummary`, `AdminValidationFailure`, métodos).
- Produces: keys usadas pelos testes e pelo e2e (Tarefa 12): `novo_acs`, `acs_<id>`, `vincular_acs_<id>`, `ativar_acs_<id>`/`desativar_acs_<id>`, `redefinir_senha_<id>`, `redefinir_mfa_<id>`, `staff_<id>`, `redefinir_mfa_staff_<id>`, `confirmar_acao`, `cancelar_acao`, `senha_inicial`, `codigo_ativacao`, `fechar_credencial`, campos `acs_nome_field`, `acs_matricula_field`, `acs_microarea_field`.

- [ ] **Step 1: Testes de widget que falham** (`acs_management_screen_test.dart`, via `abrirBackoffice`/`SinalAdminApp(dataSource: MockAdminDataSource(), auth: FakeAdminAuth())`):

```dart
testWidgets('a tela Microáreas lista os ACS com estado e oferece o cadastro', (tester) async {
  await abrirBackoffice(tester, tamanho: const Size(1024, 768));
  await irPara(tester, 'Microáreas');
  expect(find.text('Agentes de saúde (ACS)'), findsOneWidget);
  expect(find.byKey(const Key('novo_acs')), findsOneWidget);
  expect(find.byKey(const Key('acs_acs-1')), findsOneWidget);
});
testWidgets('desativar só acontece DEPOIS da confirmação', (tester) async {
  final mock = MockAdminDataSource();
  await abrirBackoffice(tester, tamanho: const Size(1024, 768), dataSource: mock);
  await irPara(tester, 'Microáreas');
  await tester.tap(find.byKey(const Key('desativar_acs_acs-1')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('confirmar_acao')), findsOneWidget);
  await tester.tap(find.byKey(const Key('cancelar_acao')));
  await tester.pumpAndSettle();
  expect(mock.desativados, isEmpty);           // cancelar não chama nada
  await tester.tap(find.byKey(const Key('desativar_acs_acs-1')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('confirmar_acao')));
  await tester.pumpAndSettle();
  expect(mock.desativados, ['acs-1']);
});
testWidgets('a senha inicial aparece uma única vez, com botão de copiar, e não volta', (tester) async {
  // Novo ACS → preencher → confirmar → Key('senha_inicial') visível (SelectableText)
  // → Key('fechar_credencial') → reabrir a lista: a senha não aparece em lugar nenhum
});
testWidgets('a seção Equipe só aparece para o papel admin', (tester) async {
  // FakeAdminAuth()..role = 'coordinator' → find.text('Equipe do backoffice') findsNothing
});
testWidgets('erro de validação do servidor aparece com a mensagem do servidor', (tester) async {
  // mock com falha de validação → SnackBar/diálogo com 'Já existe um ACS com esta matrícula.'
});
```

- [ ] **Step 2: Rodar e ver falhar** → FAIL (widgets não existem).

- [ ] **Step 3: Implementar `admin_accounts.dart`** — `AcsManagementSection` (título, botão "Novo ACS" ≥48dp, lista de `Card` por ACS com `Chip` de estado e MFA, botões de ação) e `StaffManagementSection` (admin-only, título "Equipe do backoffice", botão "Redefinir MFA" por conta). Diálogos: formulário de cadastro (name/matrícula/dropdown de microárea vindo de `fetchMicroAreas()`), vínculo (dropdown), confirmação destrutiva genérica (`_ConfirmacaoDestrutiva`: título, consequência em texto claro, `confirmar_acao` com `AdminColors.redOnSurface` no rótulo e `minimumSize: Size(48, 52)`, `cancelar_acao`), e `_CredencialMostradaUmaVez` (SelectableText + `IconButton` de copiar com `Semantics(label: 'Copiar')`, aviso "não será mostrada de novo").
  Regra de fluxo: **toda** ação destrutiva (desativar, redefinir senha, redefinir MFA do ACS, redefinir MFA do staff) passa por `_ConfirmacaoDestrutiva`; reativar e vincular não são destrutivas (um passo, sem confirmação).

- [ ] **Step 4: Compor na `MicroAreasScreen`** — `_load()` passa a buscar microáreas + ACS (+ staff se `role == 'admin'`) numa única tarefa, mantendo `recordAccess` **antes** dos dados (o padrão de hoje continua valendo); a seção de ACS fica abaixo dos cartões de microárea; título da tela mantido ("Microáreas e vínculo ACS") para não quebrar `admin_home_shell_test.dart`; subtítulo trocado para descrever a gestão.

- [ ] **Step 5: Inverter o teste de somente-leitura** — em `micro_areas_screen_test.dart`, substituir `expect(find.byIcon(Icons.edit_outlined), findsNothing)` por asserções do novo comportamento (botão `novo_acs` presente; a lista continua sem qualquer controle de reclassificação de risco).

- [ ] **Step 6: Rodar e commitar** — `flutter analyze && flutter test test/acs_management_screen_test.dart test/micro_areas_screen_test.dart test/admin_home_shell_test.dart` → PASS; commit `feat(admin-app): gestão de ACS e equipe na tela Microáreas, com confirmação (#43)`.

---

### Task 11: Acessibilidade e layout da UI nova (WCAG)

**Files:** Modify: `apps/admin/test/touch_targets_test.dart`, `apps/admin/test/contrast_tokens_test.dart` (se houver token novo — provavelmente não), `apps/admin/test/responsive_layout_test.dart` e/ou `apps/admin/test/text_scale_test.dart` (só se a tela mais longa exigir mais rolagem no harness); possivelmente `apps/admin/lib/app/admin_accounts.dart` (ajustes).

- [ ] **Step 1: Teste de alvos de toque** — acrescentar casos: botão `novo_acs` ≥48dp; `confirmar_acao`/`cancelar_acao` **dentro do diálogo** ≥48dp (medir após abrir o diálogo; H3 do diagnóstico: se o `AlertDialog` não herdar o mínimo, declarar `minimumSize` nos botões, como `login_screen.dart` L184 faz).

```dart
testWidgets('os botões do diálogo de confirmação têm pelo menos 48dp', (tester) async {
  await abrirBackoffice(tester, tamanho: const Size(360, 800));
  await irPara(tester, 'Microáreas');
  await tester.tap(find.byKey(const Key('desativar_acs_acs-1')));
  await tester.pumpAndSettle();
  expect(tester.getSize(find.byKey(const Key('confirmar_acao'))).height, greaterThanOrEqualTo(48));
  expect(tester.getSize(find.byKey(const Key('cancelar_acao'))).height, greaterThanOrEqualTo(48));
});
```

- [ ] **Step 2: Contraste** — asserção de que o rótulo destrutivo usa `AdminColors.redOnSurface` (token), e — se algum texto novo não for coberto — acrescentar a linha correspondente à matriz de `contrast_tokens_test.dart` (o arquivo calcula a razão com `test/support/contrast.dart` contra `surfaceRaised`/`surface`; régua 4.5:1).

- [ ] **Step 3: Layout** — rodar `flutter test test/responsive_layout_test.dart test/text_scale_test.dart`; a tela Microáreas ficou substancialmente mais longa — se `percorrerTelaInteira` (8 arrastos de 320dp) não cobrir o fim, aumentar o número de passos **no harness** (um lugar só) e registrar o motivo em comentário.

- [ ] **Step 4: Rodar a suíte inteira do app e commitar** — `flutter test` → PASS; commit `test(admin-app): alvos de toque e contraste da gestão de contas (#43)`.

---

### Task 12: E2E no emulador contra o backend real

**Files:** Modify: `backend/sinalacs_server/lib/src/infrastructure/testing/e2e_fixtures.dart` + `bin/seed_e2e_fixtures.dart` (bloco `coordinator`), `scripts/qa/otp_relay.py` + `scripts/qa/otp_relay_test.py` (rota `/coordenador`); Create: `apps/admin/integration_test/admin_acs_gestao_e2e.dart`, `scripts/qa/admin_acs_gestao_e2e.sh`, `scripts/qa/admin_acs_gestao_e2e_test.sh`.

**Interfaces:**
- Consumes: tudo o anterior; `support/e2e_admin.dart` (relé) e `support/totp.dart` (código RFC 6238) já existentes.
- Produces: manifest `.e2e/fixtures.json` com bloco novo `"coordinator": {"id","matricula","password","activationCode"}`; rota GET `/coordenador` (uma única vez, como `/admin`).

- [ ] **Step 1: Fixture de coordenador no seed** — a classe `E2eStaff` já existe em `lib/src/infrastructure/testing/e2e_fixtures.dart`; acrescentar um `coordinator` (mesma forma, papel `UserRole.coordinator` e `staff_accounts.ubsId = fixtures.ubsId` — o escopo do coordenador no e2e é a UBS que já contém as duas microáreas) e o campo no `toJson`. Em `bin/seed_e2e_fixtures.dart`: `INSERT INTO users (role 'coordinator')` + `staff_accounts (id, enrollmentId, active, "ubsId")` + código de ativação + `user_credentials` — espelhar exatamente o bloco `staff` (L109-173), a única diferença é o `"ubsId"` preenchido e o papel.

- [ ] **Step 2: Rota `/coordenador` no relé** — copiar o arranjo de `/admin` (`otp_relay.py` L72-81: flag `coordenador_entregue`, payload `{matricula, senha, activationCode}`), atualizar `otp_relay_test.py` com o caso positivo + o 404 de segunda chamada. Rodar: `python3 -m pytest scripts/qa/otp_relay_test.py -q` (ou o runner que o arquivo usa) → PASS.

- [ ] **Step 3: Teste de integração do app** (`admin_acs_gestao_e2e.dart`, `@Timeout(Duration(minutes: 6))`, testes ordenados como em `admin_login_e2e.dart`; usa `buildAdminWiring(caBytes:…)` e o `Client` do `sinalacs_client` diretamente para as provas por RPC):
  1. login admin pelo relé (`/admin`) → Microáreas → "Novo ACS" (nome sintético, matrícula `E2E-ACS-<timestamp>`, microárea "Microárea E2E") → confirmar → **ler a senha do diálogo** (`Key('senha_inicial')`) e fechar.
  2. prova por RPC: `client.auth.loginInstitutional(matricula, password: senhaLida, deviceId: 'e2e-dev-1')` → sucesso; guardar `refreshToken`.
  3. vínculo: vincular o ACS novo à "Outra Microárea E2E" (`vincular_acs_<id>` → confirmar) → reabrir a lista → cartão mostra a microárea nova.
  4. desativar (confirmação) → RPC: novo login recusa com `'Este acesso está inativo.'`; `refreshSession(refreshToken)` recusa com `SessionExpiredException`.
  5. redefinir MFA do ACS criado: antes, ativar MFA por RPC (`beginTotpEnrollment` + `confirmTotpEnrollment` com `totpCode` do `support/totp.dart`) → na tela, `redefinir_mfa_<id>` → confirmar → RPC: `beginTotpEnrollment` volta a responder com segredo novo.
  6. login como **coordenador** pelo relé (`/coordenador`): a seção "Equipe do backoffice" não aparece; a lista de ACS mostra o ACS criado (mesma UBS); o coordenador cadastra um segundo ACS — prova o escopo positivo do papel.
  7. (admin novamente, se a sessão vencer, novo login pelo relé já consumido → usar a credencial memorizada como o `e2e_admin.dart` faz) `staff_<coordId>` → "Redefinir MFA" → confirmar → **ler o código** (`Key('codigo_ativacao')`) → RPC: `beginStaffTotpEnrollment(matricula do coordenador, activationCode: códigoLido)` devolve segredo novo.

- [ ] **Step 4: Script `admin_acs_gestao_e2e.sh`** — clonar a anatomia de `admin_login_e2e.sh` (cabeçalho, `DEVICE` com default `emulator-5554`, `e2e_stack.sh up`/`seed`/`down` no trap, `adb reverse tcp:8443 tcp:443` + `tcp:8765 tcp:8765`, relé com `E2E_FIXTURES_FILE`, `flutter test integration_test/admin_acs_gestao_e2e.dart -d "$dev" --dart-define=SINALACS_HOST=https://localhost:8443/`). Para os asserts SQL, o `flutter test` é capturado em uma variável (padrão `status=$?` já usado no script de login) e o nome/matrícula criados são descobertos por linha marcadora impressa pelo teste:

  ```dart
  // no fim do teste 1, com print-once (print() do Dart aparece na saída do flutter test):
  print('E2E_ACS_CRIADO matricula=$matricula nome=$nomeSintetico');
  ```
  ```bash
  matricula=$(sed -n 's/^E2E_ACS_CRIADO matricula=\([^ ]*\).*/\1/p' <<< "$saida" | tail -1)
  ```

  Asserts finais via `e2e_stack.sh psql`:
  - `SELECT active FROM acs WHERE "enrollmentId" = '<matrícula criada>'` → `false` ao fim;
  - `SELECT count(*) FROM acs_refresh_tokens t JOIN users u ON u.id = t."userId" WHERE u.name = '<nome criado>' AND t."revokedAt" IS NULL` → `0`;
  - `SELECT count(*) FROM user_credentials uc JOIN users u ON u.id = uc."userId" WHERE u.name = '<nome criado>' AND uc."totpEnabledAt" IS NULL AND uc."totpSecretEncrypted" IS NULL` → `1` (MFA redefinida);
  - `SELECT ("activationCodeHash" IS NOT NULL AND "ubsId" IS NOT NULL) FROM staff_accounts WHERE "enrollmentId" = '<matrícula do coordenador>'` → `true` (código emitido e escopo com UBS);
  - `SELECT count(*) FROM audit_logs WHERE "resourceType" IN ('admin_acs','admin_staff') AND "actionType" = 'write' AND result IN ('created','deactivated','micro_area_changed','mfa_reset')` → `>= 5`.
- [ ] **Step 5: Guarda do script** — `admin_acs_gestao_e2e_test.sh` no padrão de `admin_login_e2e_test.sh` (asserção de que `DEVICE` default é `emulator-5554`, que o `adb reverse` de 8443 existe, que o teste roda com `-d "$dev"`, e que `e2e.sh --full` **não** o descobre). Rodar `bash scripts/qa/admin_acs_gestao_e2e_test.sh` → PASS.
- [ ] **Step 6: Executar no emulador (pelo usuário, com `!`)** — `! ./scripts/qa/admin_acs_gestao_e2e.sh` → `OK`; depois a regressão `! ./scripts/qa/admin_login_e2e.sh` → `OK`; restaurar a stack de dev (`docker compose up -d`). Guardar as duas saídas para a Tarefa 13.
- [ ] **Step 7: Commit** — `test(qa): e2e da gestão de ACS no emulador contra o backend real (#43)`

---

### Task 13: Documentação e fechamento

**Files:** Modify: `PROGRESS.md`, `apps/admin/README.md`, `backend/CLAUDE.md`, `apps/CLAUDE.md`, `CLAUDE.md` (raiz), `docs/telas-admin.md`.

- [ ] **Step 1: `PROGRESS.md`** — nova seção `## Gestão de ACS e reset de MFA (issue #43, 2026-10-08)` no formato do repositório (**Entregue** / **Provado nesta execução** com as saídas reais da Tarefa 12 / **Decisões que valem até alguém trocá-las** / **Continua aberto**: criar coordenadores e atribuir `ubsId` pela UI; troca de senha pelo próprio ACS; desbloqueio como ação separada; auditoria por UBS *de outros recursos*; refresh token do staff). Fechar as pendências nomeadas em L633, L643(1)(2), L665(1)(2), L608 e L807(b) com "tratado na #43" e o que sobrou.
- [ ] **Step 2: `apps/admin/README.md`** — corrigir as linhas obsoletas L13-15 ("dados do painel seguem no mock (issue #41)", "ainda não executado") e citar os dois scripts de e2e (login e gestão).
- [ ] **Step 3: `backend/CLAUDE.md`** — seção do `AdminEndpoint` ganha os novos métodos; a seção de MFA (RF07) deixa de dizer "não há redefinição pela coordenação ainda — zere as quatro colunas à mão" e passa a apontar `admin.resetAcsMfa` / `admin.resetStaffMfa`; a seção Staff (#48) troca "a emissão por um coordenador/administrador pela interface depende da #43" pelo estado novo. `apps/CLAUDE.md` (seção Admin app): descrever a tela, os novos métodos do `AdminDataSource` e os tokens/limites. `CLAUDE.md` raiz: atualizar a lista de pendências (remover "MFA reset by the coordinator (manual today)").
- [ ] **Step 4: `docs/telas-admin.md`** — capturar as telas novas no emulador (sessão real, dados sintéticos do e2e; `adb exec-out screencap -p`), adicionar seção com a descrição dos fluxos e do "mostrado uma única vez". Regra do repositório: o doc só afirma o que foi executado.
- [ ] **Step 5: `graphify update .` + suíte final completa**

```bash
graphify update .
cd backend/sinalacs_server && dart analyze && dart test
cd ../../apps/admin && flutter analyze && flutter test
```
Expected: tudo verde. Conferir também `git status` (nada de `.e2e/`, prints ou `pg_data/` no diff).

- [ ] **Step 6: Commit final** — `docs: fecha a #43 no PROGRESS e nos CLAUDE.md`

---

## 6. Plano de testes

| Nível | O quê | Onde | Prioridade |
|---|---|---|---|
| Unit (Dart, sem banco) | Regra de escopo/papel nova (T1); regras de validação e auditoria do serviço (T2-T8): mensagens uniformes, recusa auditada, idempotência, gerador de senha | `backend/sinalacs_server/test/unit/admin_{scope,account_service}_test.dart` | Alta |
| Integração (Serverpod `withServerpod`, Postgres real) | Transação de cadastro sem órfãos; unicidade de matrícula em corrida; revogação de refresh+upload na desativação; `refreshSession`/`syncDeferred` recusados; reset de senha destrava conta bloqueada; reset de MFA permite re-ativar; ciclo do código de staff; escopo de auditoria por UBS | `test/integration/admin_account_store_test.dart`, `admin_endpoint_accounts_test.dart`, `admin_read_store_test.dart` | Alta |
| Registro da linha de base | Linha de base no emulador | `apps/admin/test/micro_areas_screen_test.dart` (estado atual), saída do `admin_login_e2e.sh`, print do baseline | Alta |
| Testes específicos da issue | Confirmação explícita antes de cada ação destrutiva; senha/código mostrados uma única vez; seção Equipe só para admin; mensagem de validação do servidor na tela | `apps/admin/test/acs_management_screen_test.dart` | Alta |
| Regressão (backend) | `dart test` completo (unit + integração) — nenhum teste existente editado além dos nomeados | `cd backend/sinalacs_server && dart test` | Alta |
| Regressão (app) | `flutter test` completo, com os testes existentes de layout/fonte/contraste verdes (o `micro_areas_screen_test.dart` muda **de propósito**) | `cd apps/admin && flutter analyze && flutter test` | Alta |
| Acessibilidade | Alvos ≥48dp (inclusive dentro de diálogos); contraste por token; 360×800 / 800×360 / 130% / 200% | `touch_targets_test.dart`, `contrast_tokens_test.dart`, `responsive_layout_test.dart`, `text_scale_test.dart` | Alta (critério de aceite) |
| E2E no emulador (real) | Jornada completa: cadastro→login real com a senha lida da tela→vínculo→desativação (login e refresh recusados)→reset de MFA→coordenador (escopo)→reset de MFA do staff; asserts SQL | `scripts/qa/admin_acs_gestao_e2e.sh` | Alta (critério de aceite) |
| Regressão E2E | `./scripts/qa/admin_login_e2e.sh` continua verde depois de tudo | idem | Alta |
| Guarda de CI | `scripts/qa/ci_invariants.sh` e `ci_invariants_test.sh` continuam verdes (nada de `ci.yml` muda nesta issue; conferir rodando) | `bash scripts/qa/ci_invariants.sh` | Média |

Comandos de referência:
```bash
docker compose --profile test up -d postgres-test          # banco dos testes de integração
cd backend/sinalacs_server && dart test test/unit
cd backend/sinalacs_server && dart test                    # suíte completa (precisa do postgres-test)
cd apps/admin && flutter test
cd apps/admin && flutter test integration_test/admin_mobile_smoke_test.dart -d emulator-5554   # hermético
```

## 7. Critérios de aceitação

Da issue, literalmente:
- [ ] **Ações restritas ao papel coordenador/admin e auditadas.** Cada operação nova passa por `AdminScopeResolver`; `acs`/`patient` com token válido recebem `AlertPermissionException` e a recusa vira linha `denied`; o coordenador opera só na própria UBS (provado por integração com UBS A/B e por e2e com o coordenador criado pelo seed); **toda** operação bem-sucedida grava `audit_logs` (`actionType: write`, `resourceType: admin_acs|admin_staff`, `result` específico, `resourceId` do alvo), e a emissão do código de ativação deixa de ser a única sem trilha.
- [ ] **Confirmação explícita para ações destrutivas, com teste de acessibilidade (alvos de toque, contraste).** Desativar, redefinir senha e redefinir MFA (ACS e staff) exigem diálogo de confirmação; teste de widget prova que cancelar não chama a API; alvos ≥48dp (inclusive no diálogo) e cores por token, com os testes de contraste/layout verdes.

Adicionais (derivados da issue, verificáveis):
- [ ] Desativar revoga refresh e envio diferido: `refreshSession` e `syncDeferred` recusados e linhas com `revokedAt` (Tarefa 5/12).
- [ ] Senha inicial e código de ativação aparecem **uma única vez**; nunca em log, auditoria ou resposta posterior (Tarefas 3/7/10/12).
- [ ] Cadastro cria o ACS **utilizável**: login institucional com a senha lida da tela funciona; ACS sem território não trava o cadastro (microárea é obrigatória) e o login sem território continua recusado por INV-01.
- [ ] Nenhuma migração nova; `dart analyze`/`flutter analyze` limpos; suítes completas verdes; `admin_login_e2e.sh` de regressão verde no emulador.

## 8. Riscos e contingências

| Risco | Probabilidade | Contingência |
|---|---|---|
| `session.db.transaction` aninhada com a transação própria do `OrmAuditTrail` se comportar de forma inesperada | Média | O desenho já evita: auditoria **fora** da transação do store. Se o teste de órfãos (T3) falhar por causa disso, isolar a auditoria com `record` pós-commit (estado atual do desenho) e documentar no código. |
| Índice único de matrícula disparar 500 em corrida | Média | `insertAcs` captura `23505` e devolve `null`; teste de integração com duas inserções iguais; se a exceção do Serverpod não expuser o código do Postgres, capturar pela mensagem textual **no store** (um lugar só) e registrar. |
| O `AlertDialog` não herdar 48dp nos botões (H3) | Alta | Declarar `minimumSize: Size(48, 52)` nos botões dos diálogos (padrão de `login_screen.dart`/`mfa_enrollment_screen.dart`) e guardar com `touch_targets_test.dart`. |
| A tela Microáreas mais longa mascarar estouro de layout (harness só rola 8×320dp) | Média | Ajustar `percorrerTelaInteira` no harness (um lugar) e registrar o porquê em comentário; `layout_harness_sanity_test.dart` segue provando que o detector detecta. |
| Coordenador do e2e sem `ubsId` por engano ⇒ tudo recusado e o e2e falha de forma confusa | Média | Asserts SQL do script checam `staff_accounts.ubsId IS NOT NULL` para a matrícula do coordenador **antes** do teste de UI rodar. |
| Reexecução do `admin_login_e2e.sh`/novo script exige stack limpa (o e2e derruba a dev) | Alta | O script recria a stack e o `sinalacs_e2e` do zero (já é o comportamento); lembrar `docker compose up -d` depois; documentar no cabeçalho de ambos. |
| Reprodução no emulador impossível (sem AVD/dispositivo na máquina de quem executar) | Baixa | Registrar a tentativa e a limitação no `PROGRESS.md`; a substituição mínima aceitável é `dart test` completo (integração real com Postgres) — nunca só análise estática. |
| Escopo crescer (coordenador do seed de dev, criar contas de staff, `ubsId` na UI) | Média | Estão explicitamente fora (seção 1) e listados como "continua aberto" no `PROGRESS.md`; se o humano quiser, viram tarefas novas **antes** de começar. |
| `otp_relay.py` com rota nova quebrando os e2e existentes | Baixa | `otp_relay_test.py` cobre cada rota; rodar antes e depois; as rotas antigas não são tocadas. |

## 9. Decisões que o plano toma (confirmar antes de executar)

1. **Coordenador pode cadastrar/desativar ACS na própria UBS** — a issue manda restringir "ao papel coordenador/admin"; o PRD §4.2.2 dá só ao administrador "Configurações de sistema" e ao coordenador "Logs de auditoria (UBS)". Aqui a issue (mais nova) vence, com escopo de UBS. Se o produto quiser admin-only, é trocar `resolve` por `requireAdmin` nas tarefas 3–7 (mudança localizada).
2. **Senha inicial gerada pelo servidor e mostrada uma única vez** (16 chars, ~80 bits, alfabeto sem ambíguos), em vez de digitada pelo operador — evita senha fraca no RF07 e segue o precedente do código de ativação (#48). `resetAcsPassword` usa o mesmo gerador.
3. **Redefinir senha zera bloqueio** (`failedAttempts`, `lockedUntil`, `lockStreak`) porque a credencial antiga deixa de existir; a redefinição de MFA **não** destrava a conta (quem perdeu a MFA por tentativas continua bloqueado até a redefinição de senha ou o vencimento).
4. **Redefinir MFA do staff é só do administrador**, nunca da própria conta (uma conta não redefine a própria MFA pela tela; pede a outro administrador). O coordenador não vê a seção "Equipe".
5. **`cpfHash` de ACS criado é placeholder aleatório** (`acs-sem-cpf-<uuid>`) e `birthDate` um sentinela (1900-01-01 UTC) — nunca um CPF/HMAC real, pela armadilha documentada em `spec/lgpd_data_audit.md` L254 (o login passwordless emite papel de *paciente*).
6. **Sem migração**: só modelos de API + endpoints. Se alguém decidir guardar "senha inicial emitida em" ou "quem desativou", aí sim entra migração aditiva — não é necessária para os critérios.
7. **A Tarefa 8 (auditoria por UBS do coordenador) é a única removível** se a PR precisar encolher; as demais são a issue.
8. **`invalidado em cascata`**: `resetAcsPassword` e `setAcsActive(false)` **não** revogam na redefinição de senha (só a desativação revoga sessões), porque a senha nova pode ser entregue ao ACS que está logado; se o produto preferir revogar a cada redefinição, é uma linha a mais na Tarefa 6.

## 10. Auto-revisão (self-review)

**Cobertura da spec:** cada item "O que falta" da issue → Tarefas 3 (criar), 5 (desativar + revogação), 4 (vincular), 6 (senha inicial + MFA do ACS), 7 (MFA do staff, deferimento #48), 8 (auditoria do coordenador, deferimento #40). Cada critério de aceite → seções 6/7 (testes de confirmação, alvos, contraste, trilha). Fora de escopo nomeado na seção 1 com justificativa.

**Placeholders:** nenhum "TBD"; os passos trazem comando, caminho e saída esperada; o código aparece nos pontos de risco (SQL, validações, transação, diálogos) e o boilerplate aponta o arquivo-modelo exato.

**Consistência de tipos:** `AdminAcs`/`AdminStaff`/`AdminAcsCreationResult`/`AdminPasswordResetResult`/`AdminStaffMfaResetResult` (protocolo) ↔ `AcsSummary`/`StaffSummary`/`NewAcsCredential`/`NewStaffActivation` (app) ↔ `AdminAccountStore`/`AdminAccountService` — nomes e assinaturas usados de forma idêntica nas tarefas 2–12; `AdminScope`/`AdminScopeResolver` definidos uma vez (T1) e consumidos sem redefinição.

**Review Focus:** os cinco casos têm teste na tarefa que os implementa (indicado entre parênteses na seção Review Focus).

**Lacunas assumidas (documentadas, não inventadas):** H1/H2/H3 da seção 2 são verificadas por testes nas Tarefas 3/10 respectivamente; a linha de base (Tarefa 0) é obrigatória antes de qualquer alteração.
