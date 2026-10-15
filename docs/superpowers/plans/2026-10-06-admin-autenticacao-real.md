# Autenticação real do backoffice (issue #39) — Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Trocar o login local do `apps/admin` por login institucional real (matrícula + senha Argon2id + TOTP obrigatório) para os papéis `coordinator` e `admin`, emitindo JWT com esse papel.

**Architecture:** Reaproveitar `InstitutionalAuthService` (senha, bloqueio progressivo, TOTP, auditoria) parametrizado por uma audiência (`acs` | `staff`), em vez de duplicá-lo. Contas de staff ficam em uma tabela nova `staff_accounts` (matrícula única + `active`), 1:1 com `users` (papel `coordinator`/`admin`, sem microárea) e `user_credentials`. Endpoints novos `auth.loginStaff` e `auth.beginStaffTotpEnrollment`/`confirmStaffTotpEnrollment`; as tabelas distintas fazem matrícula de ACS não entrar como staff e vice-versa, com a mesma mensagem genérica. No app, `AdminAuthBackend` (interface + implementação sobre `sinalacs_client`) substitui o bypass local.

**Tech Stack:** Dart/Serverpod 3.4 (backend), Flutter (apps/admin), Postgres, `sinalacs_client` gerado.

**Spec:** `spec/PRD_system.md` (RNF06, §4.2.2), `spec/lgpd_design.md`, issue #39, plano de referência `docs/superpowers/plans/2026-09-18-rf07-login-institucional-acs.md`.

## Global Constraints

- Texto de UI, comentários e mensagens de erro em português.
- Nunca `serverpod`-gerado editado à mão: `lib/src/generated/` só via `serverpod generate`; migração só via `serverpod create-migration` (ver `backend/CLAUDE.md`).
- Mensagem **única** para matrícula inexistente e senha errada; bloqueio só revelado depois de a senha conferir (regra de `InstitutionalAuthService`).
- Sem dado real, senha ou segredo versionado: a senha do admin de dev vem de `DEV_ADMIN_PASSWORD` gerada por `scripts/dev/bootstrap_env.sh`.
- Endpoints públicos novos entram em `_publicMethodsByDesign` de `test/unit/endpoint_auth_posture_test.dart` com o motivo.
- Tokens de contraste/WCAG do admin: alvos de toque ≥ 48×52 dp, `Semantics(liveRegion: true)` em erro de login.
- Sem atribuições de IA em commits (regra do repositório), mesmo que o harness sugira.
- Cada tarefa termina com `dart test test/unit` (backend) ou `flutter analyze && flutter test` (admin) verdes.

## Decisões a confirmar antes de executar

1. **MFA do staff é sempre obrigatória**, independente de `REQUIRE_ACS_MFA` (critério de aceite da issue). O admin de dev precisa ativá-la pela tela de ativação na primeira entrada.
2. **Sem refresh token no admin nesta issue.** O JWT dura 15 min; ao vencer, o app volta ao login. O código TOTP é de uso único, então o re-login exige esperar o próximo passo de 30 s (mesma limitação do ACS, documentada em `PROGRESS.md`). O backoffice é somente leitura, então não há estado a preservar. Refresh para staff fica como follow-up.
3. **Recuperação de MFA de staff** é manual (SQL), como a do ACS; a tela de gestão é a issue #43.

## Review Focus

1. Matrícula de ACS em `loginStaff` e de staff em `loginInstitutional`: recusa com a mesma mensagem genérica, sem revelar que a conta existe na outra audiência (Tarefa 2).
2. Staff com `active = false` ou sem `users.role` coerente (`patient`/`acs` apontando para uma linha de `staff_accounts`): recusa, nunca token (Tarefa 2).
3. Senha certa, MFA não ativada, em qualquer ambiente (inclusive `development`): `MfaEnrollmentRequiredException`, nunca token (Tarefa 2).
4. Token `admin`/`coordinator` (sem `micro_area_id`) apresentado a endpoints de paciente/ACS: recusado, não vira acesso a território (Tarefa 3).
5. Build release do admin: sem bypass; `devLoginEnabled` não existe mais como caminho de entrada (Tarefa 6).

## Estrutura de arquivos

| Arquivo | Responsabilidade |
|---|---|
| `backend/sinalacs_server/lib/src/models/staff_account.spy.yaml` (novo) | Tabela `staff_accounts` |
| `backend/.../application/auth/institutional_auth_service.dart` (mod.) | Audiência `CredentialAudience`, papel por audiência, MFA obrigatória no staff |
| `backend/.../infrastructure/database/orm_acs_credential_store.dart` (mod.) | Flag `staff` que troca a tabela de busca da matrícula |
| `backend/.../application/auth/authorization.dart` (mod.) | `Authorization.staffRoles` |
| `backend/.../runtime/alert_runtime.dart` (mod.) | `staffAuthServiceFor(session)` |
| `backend/.../endpoints/auth_endpoint.dart` (mod.) | `loginStaff`, `beginStaffTotpEnrollment`, `confirmStaffTotpEnrollment` |
| `backend/.../bin/seed_acs_credentials.dart` (mod.) + `seeds/development.sql` + `docker-compose.yml` + `scripts/dev/bootstrap_env.sh` + `.env.example` | Admin de desenvolvimento |
| `apps/admin/lib/core/auth/admin_auth_backend.dart` (novo) | Interface + `BackendAdminAuth` sobre `sinalacs_client` |
| `apps/admin/lib/app/login_screen.dart` (novo, extraído de `app.dart`) | Login real + campo TOTP |
| `apps/admin/lib/app/mfa_enrollment_screen.dart` (novo) | Ativação da MFA |
| `apps/admin/lib/app/app.dart` (mod.) | Injeta `AdminAuthBackend`, remove `devLoginEnabled` |
| docs | `spec/PRD_system.md` RNF06, `backend/CLAUDE.md`, `apps/CLAUDE.md`, `spec/lgpd_data_audit.md`, `PROGRESS.md` |

---

### Task 1: Modelo `staff_accounts` e migração

**Files:**
- Create: `backend/sinalacs_server/lib/src/models/staff_account.spy.yaml`
- Create (gerados): `lib/src/generated/*`, `migrations/<timestamp>/*`, `backend/sinalacs_client/lib/src/protocol/*`
- Modify: `spec/lgpd_data_audit.md`, `backend/CLAUDE.md` (contagem de tabelas)
- Test: `backend/sinalacs_server/test/integration/staff_account_schema_test.dart`

**Interfaces:**
- Produces: classe gerada `StaffAccount { UuidValue? id, String enrollmentId, bool active }`, com `StaffAccount.db`.

- [ ] **Step 1: Escrever o teste de integração que falha**

Siga o arranjo de `test/integration/institutional_login_test.dart` (mesmo `withServerpod`/helpers de lá — leia as 40 primeiras linhas e copie o setup).

```dart
test('matrícula de staff é única', () async {
  final userId = await _insertStaffUser(session, role: UserRole.admin); // helper local: INSERT em users
  await StaffAccount.db.insertRow(
    session,
    StaffAccount(id: userId, enrollmentId: 'ADM-T1', active: true),
  );
  expect(
    () => StaffAccount.db.insertRow(
      session,
      StaffAccount(id: await _insertStaffUser(session, role: UserRole.admin), enrollmentId: 'ADM-T1', active: true),
    ),
    throwsA(anything),
  );
});
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd backend/sinalacs_server && dart test test/integration/staff_account_schema_test.dart`
Expected: FAIL (`StaffAccount` não definido).

- [ ] **Step 3: Criar o modelo**

```yaml
### Conta de staff do backoffice (coordenador ou administrador).
###
### Tabela própria, e não uma coluna em `acs`: staff não é ACS, não tem UBS nem
### sincronização, e misturar os dois faria `acs.enrollmentId` virar um
### namespace compartilhado. O id é o UUID do usuário (mesma decisão de `Acs`).
### O papel mora em `users.role` (`coordinator` | `admin`); a credencial, em
### `user_credentials`.
class: StaffAccount
table: staff_accounts
fields:
  id: UuidValue?, defaultPersist=random
  enrollmentId: String
  active: bool
indexes:
  staff_accounts_enrollment_id_key:
    fields: enrollmentId
    unique: true
```

- [ ] **Step 4: Gerar código e migração**

Run: `cd backend/sinalacs_server && serverpod generate && serverpod create-migration`
Expected: migração nova em `migrations/`, `StaffAccount` em `generated/` e no `sinalacs_client`. Inspecione o SQL: só `CREATE TABLE "staff_accounts"` e o índice único; nenhum `DROP`.

- [ ] **Step 5: Rodar o teste e a suíte unitária**

Run: `dart test test/integration/staff_account_schema_test.dart && dart test test/unit`
Expected: PASS. (Integração precisa do Postgres de teste; ver `backend/CLAUDE.md`.)

- [ ] **Step 6: Documentar e commitar**

Adicione `staff_accounts` a `spec/lgpd_data_audit.md` (`enrollmentId`: identificador funcional, baixa sensibilidade; `active`: operacional) e atualize a contagem de tabelas citada em `backend/CLAUDE.md` (re-meça no `definition.sql` da migração nova, não copie número).

```bash
git add backend spec/lgpd_data_audit.md
git commit -m "feat(backend): tabela staff_accounts para coordenador e administrador (#39)"
```

---

### Task 2: `InstitutionalAuthService` por audiência

**Files:**
- Modify: `backend/sinalacs_server/lib/src/application/auth/institutional_auth_service.dart` (`AcsCredentialRecord`, construtor, `login`, `_authenticatePassword`, `beginTotpEnrollment`, `confirmTotpEnrollment`)
- Modify: `backend/sinalacs_server/lib/src/infrastructure/database/orm_acs_credential_store.dart` (`findByEnrollmentId`)
- Test: `backend/sinalacs_server/test/unit/institutional_auth_staff_test.dart`
- Test: `backend/sinalacs_server/test/integration/staff_login_test.dart`

**Interfaces:**
- Produces: `enum CredentialAudience { acs, staff }`; construtor `InstitutionalAuthService(..., this.audience = CredentialAudience.acs)`; `AcsCredentialRecord` ganha `final UserRole role` com default `UserRole.acs` (os fakes dos testes existentes ficam intactos); `OrmAcsCredentialStore({required Session Function() session, bool staff = false})`.
- Comportamento: com `audience == staff`: (a) `login` devolve `AuthenticatedUser(role: record.role, microAreaId: null)`; (b) `_authenticatePassword` **não** exige microárea; (c) `requireMfa` é tratado como `true`; (d) recusa com a mensagem genérica se `record.role` não for `coordinator`/`admin`.

- [ ] **Step 1: Escrever os testes unitários que falham**

Copie o `_Store`/`_Cofre` de `test/unit/institutional_auth_mfa_test.dart` (mesmos imports) e acrescente:

```dart
AcsCredentialRecord _staff({UserRole role = UserRole.admin, bool active = true, TotpEnrollment? totp}) =>
    AcsCredentialRecord(
      acsId: '00000000-0000-4000-8000-000000000090',
      microAreaId: null,
      active: active,
      role: role,
      digest: _digest, // o mesmo helper do teste de MFA
      failedAttempts: 0,
      lockedUntil: null,
      totp: totp,
    );

test('staff sem MFA ativa recebe MfaEnrollmentRequired mesmo com requireMfa=false', () async {
  final service = _service(_Store(_staff()), audience: CredentialAudience.staff, requireMfa: false);
  expect(
    () => service.login(matricula: 'ADM-001', password: _senha),
    throwsA(isA<MfaEnrollmentRequiredException>()),
  );
});

test('staff com MFA ativa e código válido recebe token sem microárea e com o papel da conta', () async {
  final user = await _service(_Store(_staff(totp: _totpAtivo())), audience: CredentialAudience.staff)
      .login(matricula: 'ADM-001', password: _senha, totpCode: _codigoAtual());
  expect(user.role, UserRole.admin);
  expect(user.microAreaId, isNull);
});

test('conta cujo papel não é de staff é recusada com a mensagem genérica', () async {
  final service = _service(_Store(_staff(role: UserRole.acs)), audience: CredentialAudience.staff);
  expect(
    () => service.login(matricula: 'ADM-001', password: _senha, totpCode: '000000'),
    throwsA(isA<AuthenticationFailedException>().having((e) => e.message, 'message', 'Matrícula ou senha inválidos.')),
  );
});

test('conta de staff inativa é recusada', () async {
  final service = _service(_Store(_staff(active: false, totp: _totpAtivo())), audience: CredentialAudience.staff);
  expect(
    () => service.login(matricula: 'ADM-001', password: _senha, totpCode: _codigoAtual()),
    throwsA(isA<AuthenticationFailedException>()),
  );
});

test('audiência acs continua exigindo microárea (regressão)', () async {
  // reaproveite o caso existente de 'denied_no_territory' com audience: acs
});
```

`_service`, `_digest`, `_senha`, `_totpAtivo`, `_codigoAtual` são os helpers que o arquivo de MFA já define: extraia-os para `test/support/institutional_auth_fixtures.dart` se não estiverem acessíveis e faça os dois testes importarem de lá (não duplicar).

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd backend/sinalacs_server && dart test test/unit/institutional_auth_staff_test.dart`
Expected: FAIL (`CredentialAudience`/`role` não existem).

- [ ] **Step 3: Implementar no serviço**

Em `institutional_auth_service.dart`:

```dart
/// Quem está entrando: o ACS (com território) ou o staff do backoffice.
enum CredentialAudience { acs, staff }
```

`AcsCredentialRecord`: acrescentar `this.role = UserRole.acs` e `final UserRole role;`.

Construtor: `this.audience = CredentialAudience.acs`; campo `final CredentialAudience audience;` e getter

```dart
bool get _mfaObrigatoria => audience == CredentialAudience.staff || requireMfa;
```

Em `login`, trocar `else if (requireMfa)` por `else if (_mfaObrigatoria)`; no `return`:

```dart
return AuthenticatedUser(
  id: record.acsId,
  role: audience == CredentialAudience.staff ? record.role : UserRole.acs,
  microAreaId: audience == CredentialAudience.staff ? null : record.microAreaId!,
  deviceId: deviceId ?? deviceIdAbsent,
);
```

Em `_authenticatePassword`, depois do `record == null` e **antes** de qualquer outro uso do papel, logo após `hasher.matches` conferir não — a checagem de papel deve valer só quando a senha conferiu (não revelar nada antes). Coloque-a após o bloco `if (!record.active)`:

```dart
if (audience == CredentialAudience.staff &&
    record.role != UserRole.coordinator &&
    record.role != UserRole.admin) {
  await _recordAudit(record.acsId, 'denied_role');
  throw AuthenticationFailedException(message: _invalidCredentials);
}
```

e envolva o bloco de `microAreaId == null` em `if (audience == CredentialAudience.acs) { ... }`.

- [ ] **Step 4: Implementar no store**

Em `OrmAcsCredentialStore`: `OrmAcsCredentialStore({required Session Function() session, this.staff = false})`. Em `findByEnrollmentId`, buscar o id e o `active` conforme a flag:

```dart
final UuidValue id;
final bool active;
if (staff) {
  final conta = await StaffAccount.db.findFirstRow(
    session,
    where: (t) => t.enrollmentId.equals(enrollmentId),
  );
  if (conta == null) return null;
  id = conta.id!;
  active = conta.active;
} else {
  final acs = await Acs.db.findFirstRow(
    session,
    where: (t) => t.enrollmentId.equals(enrollmentId),
  );
  if (acs == null) return null;
  id = acs.id!;
  active = acs.active;
}
```

O restante (credencial, `User`) usa `id`. Preencha `role: user.role` no `AcsCredentialRecord`. No ramo ACS, o papel gravado em `users` deve ser `acs`: se não for, devolva `null` (um usuário `admin` com linha em `acs` não pode entrar como ACS).

- [ ] **Step 5: Rodar os unitários**

Run: `dart test test/unit`
Expected: PASS, incluindo os testes antigos de `institutional_auth_*`.

- [ ] **Step 6: Teste de integração (banco real)**

`test/integration/staff_login_test.dart`, mesmo setup de `institutional_login_test.dart`: insere `users` (`role: admin`, `microAreaId: null`), `staff_accounts`, `user_credentials` (hash via `Argon2PasswordHasher`) com MFA já ativada (como `institutional_mfa_test.dart` faz). Casos: login com código válido emite JWT cujo payload tem `"role":"admin"` e `micro_area_id` nulo; matrícula de ACS (`ACS-001` do seed de teste) no store `staff: true` → `AuthenticationFailedException` genérica; matrícula de staff no store `staff: false` → idem.

Run: `dart test test/integration/staff_login_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add backend
git commit -m "feat(backend): InstitutionalAuthService por audiência (acs|staff) com MFA obrigatória no staff (#39)"
```

---

### Task 3: Endpoints `loginStaff`/ativação de MFA e guarda de papel

**Files:**
- Modify: `backend/sinalacs_server/lib/src/application/auth/authorization.dart`
- Modify: `backend/sinalacs_server/lib/src/runtime/alert_runtime.dart` (junto de `institutionalAuthServiceFor`, ~linha 325)
- Modify: `backend/sinalacs_server/lib/src/endpoints/auth_endpoint.dart`
- Modify: `backend/sinalacs_server/test/unit/endpoint_auth_posture_test.dart` (`_publicMethodsByDesign`)
- Test: `backend/sinalacs_server/test/unit/authorization_test.dart`, `test/integration/staff_login_test.dart`
- Generated: `serverpod generate` (client)

**Interfaces:**
- Consumes: `CredentialAudience`, `OrmAcsCredentialStore(staff: true)` (Tarefa 2).
- Produces: `Authorization.staffRoles` (`const {UserRole.coordinator, UserRole.admin}`); `AlertRuntime.staffAuthServiceFor(Session)`; RPC `auth.loginStaff(matricula, password, totpCode?) → DevelopmentLoginResult` (só `accessToken`, `tokenType`; sem refresh/upload token), `auth.beginStaffTotpEnrollment(matricula, password) → TotpEnrollmentStart`, `auth.confirmStaffTotpEnrollment(matricula, password, code) → void`.

- [ ] **Step 1: Testes que falham**

Em `authorization_test.dart`:

```dart
test('staffRoles contém coordinator e admin, e só eles', () {
  expect(Authorization.staffRoles, {UserRole.coordinator, UserRole.admin});
});

test('token de admin (sem microárea) é recusado onde só o ACS pode', () {
  expect(
    () => Authorization.require(
      _user(UserRole.admin, microAreaId: null),
      roles: {UserRole.acs},
      onDenied: () => StateError('Somente ACS podem fazer isto.'),
    ),
    throwsA(isA<StateError>()),
  );
});

test('requireMicroArea:false com staffRoles aceita admin sem território', () {
  expect(
    () => Authorization.require(
      _user(UserRole.admin, microAreaId: null),
      roles: Authorization.staffRoles,
      requireMicroArea: false,
      onDenied: () => StateError('x'),
    ),
    returnsNormally,
  );
});
```

Em `integration/staff_login_test.dart`: `auth.loginStaff` com credenciais certas e código devolve token e `refreshToken == null`; senha errada ×5 bloqueia (reuso do bloqueio); `AuthEndpoint.loginStaff`, `beginStaffTotpEnrollment`, `confirmStaffTotpEnrollment` aparecem na allowlist.

- [ ] **Step 2: Rodar e ver falhar** — `dart test test/unit/authorization_test.dart` → FAIL.

- [ ] **Step 3: Implementar**

`authorization.dart`, dentro de `Authorization`:

```dart
/// Papéis do backoffice. Os endpoints de staff (issue #40) usam este conjunto
/// com `requireMicroArea: false`: staff não é territorializado.
static const Set<UserRole> staffRoles = {UserRole.coordinator, UserRole.admin};
```

`alert_runtime.dart`:

```dart
/// Login do backoffice: mesma regra do ACS, outra tabela de matrículas, MFA
/// sempre obrigatória e token sem microárea.
InstitutionalAuthService staffAuthServiceFor(Session session) {
  final store = OrmAcsCredentialStore(session: () => session, staff: true);
  return InstitutionalAuthService(
    store: store,
    hasher: passwordHasher,
    audit: auditTrailFor(session),
    totpStore: store,
    vault: HealthCipherTotpVault(healthDataCipher),
    audience: CredentialAudience.staff,
  );
}
```

`auth_endpoint.dart` (documente cada método com o mesmo cuidado dos vizinhos):

```dart
/// Login do backoffice (coordenador/administrador): matrícula + senha + TOTP.
/// A MFA é obrigatória em todo ambiente. Sem refresh token: a sessão dura os
/// 15 min do JWT.
Future<DevelopmentLoginResult> loginStaff(
  Session session, {
  required String matricula,
  required String password,
  String? totpCode,
}) async {
  final runtime = AlertRuntime.instance;
  final user = await runtime.staffAuthServiceFor(session).login(
        matricula: matricula,
        password: password,
        totpCode: totpCode,
      );
  return DevelopmentLoginResult(
    accessToken: runtime.auth.issueToken(user),
    tokenType: 'Bearer',
  );
}

Future<TotpEnrollmentStart> beginStaffTotpEnrollment(
  Session session, {required String matricula, required String password}) =>
    AlertRuntime.instance.staffAuthServiceFor(session)
        .beginTotpEnrollment(matricula: matricula, password: password);

Future<void> confirmStaffTotpEnrollment(
  Session session, {required String matricula, required String password, required String code}) =>
    AlertRuntime.instance.staffAuthServiceFor(session)
        .confirmTotpEnrollment(matricula: matricula, password: password, code: code);
```

`endpoint_auth_posture_test.dart`: três entradas em `_publicMethodsByDesign` ("emissor de token do backoffice: matrícula e senha SÃO credencial", e "ativação da MFA do staff: sem token antes da MFA, como a do ACS").

- [ ] **Step 4: Gerar o cliente** — `cd backend/sinalacs_server && serverpod generate`.

- [ ] **Step 5: Rodar tudo** — `dart test test/unit && dart test test/integration/staff_login_test.dart` → PASS.

- [ ] **Step 6: Commit**

```bash
git add backend
git commit -m "feat(backend): auth.loginStaff e ativação de MFA do staff, com Authorization.staffRoles (#39)"
```

---

### Task 4: Admin de desenvolvimento no seed

**Files:**
- Modify: `backend/sinalacs_server/lib/src/infrastructure/database/seeds/development.sql`
- Modify: `backend/sinalacs_server/bin/seed_acs_credentials.dart`
- Modify: `docker-compose.yml` (serviço `acs-credential-seed`), `scripts/dev/bootstrap_env.sh`, `.env.example`
- Test: `backend/sinalacs_server/test/unit/seed_birth_date_agreement_test.dart` (estilo de teste de acordo do seed; leia-o antes) ou novo `test/unit/seed_staff_agreement_test.dart`

**Interfaces:**
- Produces: usuário `00000000-0000-4000-8000-000000000090`, papel `admin`, matrícula `ADM-001`, `microAreaId` nulo; senha de `DEV_ADMIN_PASSWORD`.

- [ ] **Step 1: Teste de acordo que falha** — o UUID `…0090` e a matrícula `ADM-001` aparecem tanto em `development.sql` quanto em `seed_acs_credentials.dart`, e `DEV_ADMIN_PASSWORD` em `docker-compose.yml`, `bootstrap_env.sh` e `.env.example` (mesma técnica de `compose_secret_agreement_test.dart`). Run: `dart test test/unit/seed_staff_agreement_test.dart` → FAIL.

- [ ] **Step 2: SQL** — em `development.sql`, siga o INSERT do ACS já presente (copie as colunas obrigatórias de `users`, incluindo um `cpfHash` literal único tipo `'development-admin'`, que o `cpf-hash-seed` não toca por só atualizar linhas de paciente) com `role = 'admin'`, `microAreaId = NULL`, e:

```sql
INSERT INTO staff_accounts (id, "enrollmentId", active)
VALUES ('00000000-0000-4000-8000-000000000090', 'ADM-001', true)
ON CONFLICT DO NOTHING;
```

- [ ] **Step 3: Credencial** — em `seed_acs_credentials.dart`, depois de gravar a do ACS, ler `DEV_ADMIN_PASSWORD` (mesma recusa se vazia, mesma trava `APP_ENV=development`) e gravar a de `…0090` pelo mesmo caminho de upsert. Sem literal de senha.

- [ ] **Step 4: Ambiente** — `DEV_ADMIN_PASSWORD="$(secret)"` em `bootstrap_env.sh` (ao lado de `DEV_ACS_PASSWORD`, linha ~71 e mensagem ~89), `DEV_ADMIN_PASSWORD=` em `.env.example`, e a variável `${DEV_ADMIN_PASSWORD:?defina em .env — rode ./scripts/dev/bootstrap_env.sh}` no serviço `acs-credential-seed`.

- [ ] **Step 5: Verificar** — `dart test test/unit` → PASS; `./scripts/dev/bootstrap_env.sh --force` num clone limpo, `docker compose up --build`, depois confirmar no Postgres que existe a credencial: `docker compose exec postgres psql -U sinalacs_user -d sinalacs_db -c "select \"userId\" from user_credentials"` lista os dois ids.

- [ ] **Step 6: Commit** — `git commit -m "feat(dev): admin ADM-001 no seed de desenvolvimento (#39)"`.

---

### Task 5: `AdminAuthBackend` no app

**Files:**
- Modify: `apps/admin/pubspec.yaml` (SDK `^3.8.0` e `sinalacs_client` por path, como `apps/acs/pubspec.yaml`), regenerar `pubspec.lock`
- Create: `apps/admin/lib/core/auth/admin_auth_backend.dart`
- Create: `apps/admin/lib/core/auth/backend_config.dart` (host por `--dart-define=SINALACS_HOST`, default `https://10.0.2.2/`; copie a regra HTTPS-only de `apps/acs/lib/core/network/backend_config.dart`, incluindo a recusa de `http://`)
- Test: `apps/admin/test/support/fake_admin_auth.dart`, `apps/admin/test/admin_auth_backend_test.dart`

**Interfaces:**
- Produces:

```dart
class AdminSession {
  const AdminSession({required this.accessToken, required this.userId, required this.role, required this.expiresAt});
  final String accessToken, userId, role; // role: 'coordinator' | 'admin'
  final DateTime expiresAt;
}

class AdminAuthFailure implements Exception {
  const AdminAuthFailure(this.message);
  final String message;
}
class AdminMfaCodeRequired extends AdminAuthFailure { const AdminMfaCodeRequired() : super('Informe o código do aplicativo autenticador.'); }
class AdminMfaEnrollmentRequired extends AdminAuthFailure { const AdminMfaEnrollmentRequired() : super('Ative a verificação em duas etapas antes de entrar.'); }

abstract interface class AdminAuthBackend {
  Future<AdminSession> login({required String matricula, required String senha, String? totpCode});
  Future<({String secret, String otpauthUri})> beginMfaEnrollment({required String matricula, required String senha});
  Future<void> confirmMfaEnrollment({required String matricula, required String senha, required String code});
}
```

- [ ] **Step 1: Teste que falha** — `admin_auth_backend_test.dart` testa a leitura do JWT (sem verificar assinatura, como `AuthSession.fromToken` do ACS): um token montado no teste com `role: admin` vira `AdminSession`; token com `role: patient` ou `acs` → `AdminAuthFailure` (o app **recusa** papel que não é de staff mesmo se o servidor emitisse); token malformado → `AdminAuthFailure`; `expiresAt` vem de `exp`.

```dart
String _jwt(Map<String, Object?> payload) {
  String b64(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${b64({'alg': 'HS256'})}.${b64(payload)}.sig';
}

test('papel de ACS no token é recusado pelo app', () {
  final token = _jwt({'sub': 'u', 'role': 'acs', 'exp': 4102444800});
  expect(() => AdminSession.fromToken(token), throwsA(isA<AdminAuthFailure>()));
});
```

- [ ] **Step 2: Ver falhar** — `cd apps/admin && flutter pub get && flutter test test/admin_auth_backend_test.dart` → FAIL.

- [ ] **Step 3: Implementar** — `AdminSession.fromToken` (decodifica o payload, exige `role ∈ {coordinator, admin}`), e `BackendAdminAuth(Client client)` que chama `client.auth.loginStaff(...)` e traduz: `MfaRequiredException` → `AdminMfaCodeRequired`, `MfaEnrollmentRequiredException` → `AdminMfaEnrollmentRequired`, `AuthenticationFailedException` → `AdminAuthFailure(e.message)`, erro de rede/`SocketException` → `AdminAuthFailure('Não foi possível conectar ao servidor.')`. Nunca logar o token.

- [ ] **Step 4: Rodar** — `flutter analyze && flutter test` → PASS (os testes de dados continuam no mock).

- [ ] **Step 5: Commit** — `git commit -m "feat(admin): AdminAuthBackend sobre sinalacs_client (#39)"`.

---

### Task 6: Login real, TOTP e ativação de MFA nas telas

**Files:**
- Create: `apps/admin/lib/app/login_screen.dart` (move `LoginScreen` de `app.dart`)
- Create: `apps/admin/lib/app/mfa_enrollment_screen.dart` (base: `apps/acs/lib/app/mfa_enrollment_screen.dart`; QR com `qr_flutter`, fundo branco/módulos escuros; adicionar `qr_flutter` ao `pubspec.yaml` com a mesma versão do ACS)
- Modify: `apps/admin/lib/app/app.dart` (`SinalAdminApp({AdminDataSource? dataSource, required AdminAuthBackend auth})`, remover `devLoginEnabled`), `apps/admin/lib/main.dart` (injeta `BackendAdminAuth`)
- Modify: testes existentes `login_flow_test.dart`, `login_dev_gate_test.dart`, `admin_home_shell_test.dart`, `text_scale_test.dart`, `touch_targets_test.dart`, `responsive_layout_test.dart` etc. (qualquer um que faça `SinalAdminApp()` passa `auth: FakeAdminAuth()`)
- Test: `apps/admin/test/login_real_test.dart` (substitui `login_dev_gate_test.dart`, que deixa de fazer sentido: apague-o)

**Interfaces:**
- Consumes: `AdminAuthBackend`, `AdminSession`, `AdminAuthFailure`, `AdminMfaCodeRequired`, `AdminMfaEnrollmentRequired` (Tarefa 5).
- Produces: `FakeAdminAuth` em `test/support` com campos públicos `Object? failWith`, `bool requiresTotp`, `String? lastTotpCode`, e `login` que devolve uma `AdminSession` de papel `admin`.
- Chaves de widget: `matricula_field`, `senha_field`, `totp_field`, `login_button`, `login_error`, `mfa_secret`, `mfa_code_field`, `mfa_confirm_button`.

- [ ] **Step 1: Testes que falham** (`login_real_test.dart`)

```dart
testWidgets('credencial recusada mostra o erro em região viva e não abre o painel', (tester) async {
  final auth = FakeAdminAuth()..failWith = const AdminAuthFailure('Matrícula ou senha inválidos.');
  await tester.pumpWidget(SinalAdminApp(auth: auth));
  await tester.enterText(find.byKey(const Key('matricula_field')), 'ADM-001');
  await tester.enterText(find.byKey(const Key('senha_field')), 'x');
  await tester.tap(find.byKey(const Key('login_button')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('login_error')), findsOneWidget);
  expect(find.text('Painel de Indicadores'), findsNothing);
});

testWidgets('MfaCodeRequired mostra totp_field e reenvia com o código', (tester) async {
  final auth = FakeAdminAuth()..requiresTotp = true;
  await tester.pumpWidget(SinalAdminApp(auth: auth));
  // preenche matrícula/senha, toca em entrar → aparece totp_field
  // preenche '123456', toca em entrar → painel abre e auth.lastTotpCode == '123456'
});

testWidgets('mudar matrícula ou senha descarta o campo do código', (tester) async { /* ... */ });

testWidgets('MfaEnrollmentRequired abre a tela de ativação, sem token', (tester) async { /* ... */ });

testWidgets('não existe caminho de entrada sem chamar o backend (sem bypass)', (tester) async {
  await tester.pumpWidget(SinalAdminApp(auth: FakeAdminAuth()));
  await tester.tap(find.byKey(const Key('login_button')));
  await tester.pumpAndSettle();
  expect(find.text('Painel de Indicadores'), findsNothing); // campos vazios não autenticam
});

testWidgets('sessão vencida volta ao login', (tester) async { /* FakeAdminAuth com expiresAt no passado → ao abrir o painel, o shell detecta e volta */ });
```

Complete cada corpo comentado seguindo exatamente o padrão do primeiro (sem placeholders ao executar).

- [ ] **Step 2: Ver falhar** — `flutter test test/login_real_test.dart` → FAIL.

- [ ] **Step 3: Implementar**

`LoginScreen` recebe `AdminAuthBackend auth` e `AdminDataSource dataSource`. `_login` é assíncrono: valida não-vazio, chama `auth.login`; captura `AdminMfaCodeRequired` → `setState(_pedeCodigo = true)`; `AdminMfaEnrollmentRequired` → `Navigator.push(MfaEnrollmentScreen(...))`; `AdminAuthFailure` → mensagem em `Semantics(liveRegion: true)` com `Key('login_error')`; sucesso → `pushReplacement(AdminHomeShell(dataSource: dataSource, session: session))`. Desabilitar o botão durante a chamada (evita duplo envio). Remover o banner "ambiente de desenvolvimento" e o aviso `dev_login_disabled_notice`. `AdminHomeShell` recebe `AdminSession session` e, ao construir cada aba, verifica `session.expiresAt`; vencida → `Navigator.pushAndRemoveUntil` para o login com a mensagem "Sessão encerrada. Entre novamente.". O campo TOTP: `keyboardType: number`, `maxLength: 6`, `FilteringTextInputFormatter.digitsOnly`.

`MfaEnrollmentScreen`: chama `beginMfaEnrollment`, mostra `mfa_secret` + QR do `otpauthUri`, `mfa_code_field`, `mfa_confirm_button` → `confirmMfaEnrollment` → volta ao login com a mensagem "Verificação ativada. Entre com o código do aplicativo."; o segredo não é gravado no aparelho.

- [ ] **Step 4: Rodar** — `flutter analyze && flutter test` → PASS (toda a suíte, incluindo `contrast_tokens_test`, `touch_targets_test`, `text_scale_test`: o login ganhou um campo, confira a 130%/200% de fonte e 320 dp de largura).

- [ ] **Step 5: Commit** — `git commit -m "feat(admin): login institucional com TOTP e ativação de MFA; remove o bypass local (#39)"`.

---

### Task 7: Prova ponta a ponta, documentação e fechamento

**Files:**
- Create: `apps/admin/integration_test/admin_login_e2e.dart` (sufixo `_e2e` de propósito, para `flutter test integration_test` não o descobrir; ver `apps/CLAUDE.md`)
- Modify: `spec/PRD_system.md` (RNF06 e §4.2.2), `backend/CLAUDE.md` (endpoints `auth`, `DEV_ADMIN_PASSWORD`), `apps/CLAUDE.md` (seção Admin: o login deixou de ser local), `docs/telas-admin.md`, `PROGRESS.md`, `apps/admin/README.md`

- [ ] **Step 1: E2E contra o backend local** — com a stack no ar (`docker compose up --build`): ativar a MFA do `ADM-001` pela tela, depois entrar com o código; recusar senha errada. Siga o padrão de `apps/acs/integration_test/full_journey_e2e.dart` (gerar TOTP com `test/support/totp.dart` copiado para `integration_test/support/`, esperar o passo avançar entre a ativação e o login: o código da ativação já foi usado e o replay é barrado).

Run: `cd apps/admin && flutter test integration_test/admin_login_e2e.dart -d emulator-5554 --dart-define=SINALACS_HOST=https://10.0.2.2/ --dart-define=...` (confira em `scripts/qa/e2e.sh` como o ACS passa o host e o CA de desenvolvimento; o admin precisa confiar no mesmo certificado, ver `apps/acs/lib/core/network/backend_config.dart`).
Expected: PASS. Se o emulador ou a stack não estiverem disponíveis, registre em `PROGRESS.md` que a prova ficou pendente — não declare feito.

- [ ] **Step 2: Build release** — `cd apps/admin && flutter build apk --release` (ou `flutter build web`): confirme que o app sobe no login e que nenhuma rota abre o painel sem `AdminSession` (teste de widget da Tarefa 6 já cobre; aqui só a verificação manual de que o `devLoginEnabled` não existe mais: `grep -rn devLoginEnabled apps/admin` retorna vazio).

- [ ] **Step 3: Documentação** — RNF06 em `spec/PRD_system.md`: `coordinator`/`admin` agora têm caminho de emissão (`auth.loginStaff`), RBAC dos endpoints de staff segue na issue #40. Corrija o parágrafo da seção Admin de `apps/CLAUDE.md` ("Login is intentionally local-only…"). Atualize `PROGRESS.md` (o que foi provado e onde, o que ficou aberto: refresh token do staff, reset de MFA por tela, endpoints de dados).

- [ ] **Step 4: Suítes completas e CI** — `cd backend/sinalacs_server && dart test`; `cd apps/admin && flutter analyze && flutter test`; `./scripts/qa/ci_invariants.sh`.

- [ ] **Step 5: `graphify update .`** (regra do `CLAUDE.md`) e commit:

```bash
git add -A
git commit -m "docs(admin): login real do backoffice documentado e provado (#39)"
```

---

## Auto-revisão

- **Cobertura da issue:** emissão de JWT `admin`/`coordinator` com Argon2id e TOTP (T2–T3); app troca o login local, trata `MfaRequiredException` e expiração (T5–T6); `Authorization` cobre os novos papéis (T3); "sem credencial, nenhuma tela em release" (T6, T7); "MFA obrigatória" (T2, caso `requireMfa=false`); "testes de backend e widget cobrindo papel errado" (T2, T3, T5, T6); PRD RNF06 atualizado (T7).
- **Tipos consistentes:** `CredentialAudience`, `AcsCredentialRecord.role`, `OrmAcsCredentialStore(staff:)`, `Authorization.staffRoles`, `staffAuthServiceFor`, `AdminSession`/`AdminAuthBackend` usados com os mesmos nomes em todas as tarefas.
- **Pontos que o executor deve confirmar no código antes de seguir** (não verificados na análise): colunas obrigatórias de `users` no INSERT do seed; helpers (`_service`, `_digest`, `_totpAtivo`) de `institutional_auth_mfa_test.dart` e se já são reutilizáveis; como `e2e.sh` injeta host e CA; assinatura exata de `Client` do `sinalacs_client` para o admin; se o workspace `backend/` aceita o admin como membro (o ACS resolve por path, mesmo arranjo).
- **Fora do escopo (issues próprias):** endpoints de dados do staff (#40), troca do mock (#41), reset de MFA e gestão de contas (#43), refresh token do staff.
