# Issue #48 — Ativação do TOTP do staff com código de uso único — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fechar o trust-on-first-use da primeira ativação do TOTP do staff: `beginStaffTotpEnrollment`/`confirmStaffTotpEnrollment` passam a exigir, além de matrícula e senha, um **código de ativação de uso único**, emitido fora de banda por quem opera o banco.

**Architecture:** Três colunas aditivas em `staff_accounts` guardam o hash SHA-256 do código, a expiração e quem o emitiu. `InstitutionalAuthService` (audiência `staff`) valida o código em `begin` e `confirm`, conta erro como tentativa falha e o apaga quando a MFA é ativada. Uma CLI Dart (`bin/issue_staff_activation_code.dart`) emite o código e o mostra uma única vez. O fluxo do ACS não muda. O app admin ganha um campo de código antes do QR.

**Tech Stack:** Dart/Serverpod (backend, migrações, `dart test` com `postgres-test`), Flutter (`apps/admin`, widget tests, `integration_test`), bash/adb, Docker Compose.

**Spec:** Issue #48 (`gh issue view 48`); `PROGRESS.md` seções "Login real do backoffice (issue #39)" e "Minors adiados da #39"; `backend/CLAUDE.md` (bloco "Staff (backoffice, issue #39)"); `spec/security_assessment.md`; `spec/lgpd_design.md`.

## Global Constraints

- Idioma: mensagens de UI/erro, comentários e docs em português.
- Só dados sintéticos. Código de ativação, senha e segredo TOTP **nunca** vão para log, auditoria, mensagem de exceção nem para o git.
- Mensagem de recusa de código errado, expirado, ausente ou já usado: uma só, `Código de ativação inválido ou expirado.` (não distingue os casos).
- Política de bloqueio: erro de código conta como tentativa falha da conta, pelo mesmo `_registrarFalha` do login (limite `maxFailedAttempts = 5`, `lockDurationFor`).
- O código tem 128 bits aleatórios (`Random.secure()`), é guardado só como SHA-256 e comparado em tempo constante; validade padrão 24 h.
- A ativação do **ACS** (`beginTotpEnrollment`/`confirmTotpEnrollment` da audiência `acs`) não muda de assinatura nem de comportamento.
- Migração só **aditiva** (3 colunas anuláveis); nada de `DROP`.
- Commits sem `Co-Authored-By` e sem "Generated with Claude Code" (regra do `CLAUDE.md` do projeto). Execução do plano em uma branch nova a partir de `main` (ex.: `fix/staff-totp-activation-48`), não em `fix/app_admin`.
- `scripts/qa/e2e_stack.sh up` recria os containers de dev e o ambiente recusa que o agente o rode: o usuário roda com `!`. Ao fim, `docker compose up -d` devolve a stack de dev.
- Testes em aparelho: celular `0087014315` (Motorola edge 40 neo, Android 15) **e** emulador `emulator-5554` (AVD `Medium_Phone`). O `admin_login_e2e.sh` aceita `DEVICE=<serial>`.
- `backend/CLAUDE.md` e `PROGRESS.md` só afirmam o que foi executado.

## Review Focus

- Código expirado (1 s depois do prazo) → recusado com a mensagem única e conta como falha.
- Mesmo código usado duas vezes: depois do `confirm` bem-sucedido a coluna fica nula, então o segundo uso é recusado.
- Reemissão: um código novo invalida o anterior (o antigo deixa de funcionar).
- Código digitado com minúsculas, espaços ou hífens (`abcd-efgh ...`) deve valer como o original.
- Conta já com MFA ativa pede redefinição à coordenação **antes** de olhar o código (nenhum vazamento de que o código existe).
- Matrícula inexistente/inativa na CLI: recusa sem emitir nem imprimir nada.
- `begin` repetido com o mesmo código (usuário volta e fecha a tela) continua funcionando até a confirmação.
- ACS: `begin`/`confirm` sem código continuam funcionando como hoje.

---

## File Structure

- Modify: `backend/sinalacs_server/lib/src/models/staff_account.spy.yaml` — 3 colunas novas.
- Create: `backend/sinalacs_server/migrations/<timestamp>/` — gerada por `serverpod create-migration`.
- Create: `backend/sinalacs_server/lib/src/application/auth/staff_activation_code.dart` — gerar, normalizar, hashear e comparar o código (função pura, sem ORM).
- Modify: `backend/sinalacs_server/lib/src/application/auth/institutional_auth_service.dart` — interface `StaffActivationStore`, parâmetro `activationCode`, validação, consumo.
- Modify: `backend/sinalacs_server/lib/src/infrastructure/database/orm_acs_credential_store.dart` — `implements StaffActivationStore`.
- Modify: `backend/sinalacs_server/lib/src/runtime/alert_runtime.dart` (`staffAuthServiceFor`) e `lib/src/endpoints/auth_endpoint.dart` — fiação e parâmetro.
- Create: `backend/sinalacs_server/bin/issue_staff_activation_code.dart` — CLI do operador.
- Modify: `backend/sinalacs_server/bin/seed_e2e_fixtures.dart`, fixtures `E2eStaff` — o e2e semeia um código.
- Modify: `apps/admin/lib/core/auth/admin_auth_backend.dart`, `lib/app/mfa_enrollment_screen.dart`, `lib/app/login_screen.dart`, fakes dos testes; `apps/admin/integration_test/admin_login_e2e.dart`.
- Modify: `backend/CLAUDE.md`, `PROGRESS.md`, `docs/telas-admin.md`, `docs/screenshots/admin/` (captura da tela do código).
- Tests: `backend/sinalacs_server/test/unit/staff_activation_code_test.dart`, `test/unit/institutional_auth_staff_test.dart`, `test/integration/staff_login_test.dart`, `apps/admin/test/*`.

---

### Task 0: Verificar a issue contra o código atual (somente leitura)

**Files:** nenhum modificado.

- [ ] **Step 1: Provar o TOFU hoje**

Run:
```bash
cd backend/sinalacs_server && dart test test/integration/staff_login_test.dart -n "begin devolve segredo|confirm com código certo"
```
Expected: 2 testes passam usando só `matricula`+`password` (a falha da issue existe).

- [ ] **Step 2: Provar o "segredo pendente é sobrescrito"**

Run: `grep -n "saveSecret" -B2 -A12 lib/src/infrastructure/database/orm_acs_credential_store.dart | sed -n 1,30p`
Expected: o `WHERE` só barra quando `totpEnabledAt` não é nulo; um segundo `begin` sobrescreve o pendente.

- [ ] **Step 3: Provar que a #40 ainda não existe**

Run: `grep -rn "staffRoles" backend/sinalacs_server/lib/src/endpoints | head`
Expected: nenhum endpoint de dados aceita staff (confirma que o risco é "futuro, bloqueia a #40").

- [ ] **Step 4: Decidir branch**

Run: `git switch main && git pull --ff-only && git switch -c fix/staff-totp-activation-48`
Expected: branch nova. Sem commit.

---

### Task 1: Gerar, normalizar e conferir o código (função pura)

**Files:**
- Create: `backend/sinalacs_server/lib/src/application/auth/staff_activation_code.dart`
- Test: `backend/sinalacs_server/test/unit/staff_activation_code_test.dart`

**Interfaces:**
- Produces:
  - `class StaffActivationCode { static String generate([Random? random]); static String normalize(String input); static String hash(String code); static bool matches(String input, String storedHash); static const Duration defaultValidity = Duration(hours: 24); }`
  - `generate` devolve 26 caracteres base32 (alfabeto `A-Z2-7`, 130 bits ⇒ usa 26 símbolos) em grupos de 4 separados por hífen, ex.: `ABCD-EFGH-…`.
  - `normalize` tira espaços e hífens e põe em maiúsculas.
  - `hash` = SHA-256 hex de `normalize(code)`.
  - `matches` compara `hash(input)` com `storedHash` em tempo constante.

- [ ] **Step 1: Escrever o teste que falha**

```dart
import 'dart:math';
import 'package:sinalacs_server/src/application/auth/staff_activation_code.dart';
import 'package:test/test.dart';

void main() {
  test('generate devolve grupos de 4 base32 e sempre muda', () {
    final a = StaffActivationCode.generate(Random(1));
    final b = StaffActivationCode.generate(Random(2));
    expect(a, matches(RegExp(r'^([A-Z2-7]{4}-){6}[A-Z2-7]{2}$')));
    expect(a, isNot(b));
  });

  test('normalize ignora caixa, espaços e hífens', () {
    expect(StaffActivationCode.normalize(' ab cd-ef '), 'ABCDEF');
  });

  test('matches aceita o mesmo código em outra formatação e recusa o errado', () {
    final c = StaffActivationCode.generate(Random(3));
    final h = StaffActivationCode.hash(c);
    expect(StaffActivationCode.matches(c.toLowerCase().replaceAll('-', ' '), h), isTrue);
    expect(StaffActivationCode.matches('${c}X', h), isFalse);
    expect(StaffActivationCode.matches('', h), isFalse);
  });

  test('o hash não contém o código', () {
    final c = StaffActivationCode.generate(Random(4));
    expect(StaffActivationCode.hash(c), isNot(contains(StaffActivationCode.normalize(c))));
    expect(StaffActivationCode.hash(c), hasLength(64));
  });
}
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd backend/sinalacs_server && dart test test/unit/staff_activation_code_test.dart`
Expected: FAIL (arquivo/classe inexistente).

- [ ] **Step 3: Implementar**

```dart
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Código de ativação de uso único da MFA do staff (issue #48).
///
/// 130 bits de entropia: SHA-256 puro basta como hash (não há senha fraca a
/// proteger com KDF lento), e o código só existe em claro na saída da CLI.
class StaffActivationCode {
  const StaffActivationCode._();

  static const defaultValidity = Duration(hours: 24);
  static const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  static const _length = 26;

  static String generate([Random? random]) {
    final r = random ?? Random.secure();
    final raw = List.generate(_length, (_) => _alphabet[r.nextInt(_alphabet.length)]);
    final grupos = <String>[];
    for (var i = 0; i < raw.length; i += 4) {
      grupos.add(raw.sublist(i, i + 4 > raw.length ? raw.length : i + 4).join());
    }
    return grupos.join('-');
  }

  static String normalize(String input) =>
      input.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();

  static String hash(String code) =>
      sha256.convert(utf8.encode(normalize(code))).toString();

  /// Comparação em tempo constante do hash de [input] com [storedHash].
  static bool matches(String input, String storedHash) {
    if (normalize(input).isEmpty) return false;
    final a = utf8.encode(hash(input));
    final b = utf8.encode(storedHash);
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
```

- [ ] **Step 4: Rodar e ver passar**

Run: `dart test test/unit/staff_activation_code_test.dart`
Expected: 4 testes passam. Se `crypto` não estiver em `pubspec.yaml` do backend, o erro de import diz; adicionar com `dart pub add crypto` (já é dependência transitiva usada por `totp.dart`).

- [ ] **Step 5: Commit**

```bash
git add backend/sinalacs_server/lib/src/application/auth/staff_activation_code.dart backend/sinalacs_server/test/unit/staff_activation_code_test.dart
git commit -m "feat(auth): código de ativação de uso único do staff (#48)"
```

---

### Task 2: Colunas, migração e store

**Files:**
- Modify: `backend/sinalacs_server/lib/src/models/staff_account.spy.yaml`
- Create: migração gerada
- Modify: `backend/sinalacs_server/lib/src/application/auth/institutional_auth_service.dart` (só a interface)
- Modify: `backend/sinalacs_server/lib/src/infrastructure/database/orm_acs_credential_store.dart`
- Test: `backend/sinalacs_server/test/integration/staff_activation_store_test.dart`

**Interfaces:**
- Consumes: `StaffActivationCode.hash` (Task 1).
- Produces (em `institutional_auth_service.dart`):

```dart
class StaffActivationRecord {
  const StaffActivationRecord({required this.codeHash, required this.expiresAt});
  final String codeHash;
  final DateTime expiresAt;
}

abstract interface class StaffActivationStore {
  /// Grava o hash do código e a expiração, substituindo qualquer anterior.
  Future<void> issue(String staffId, {required String codeHash, required DateTime expiresAt, required String issuedBy, required DateTime at});
  /// Código vigente da conta, ou `null` (nunca emitido ou já consumido).
  Future<StaffActivationRecord?> find(String staffId);
  /// Apaga o código (hash e expiração); `issuedBy`/`issuedAt` ficam como último registro.
  Future<void> clear(String staffId);
}
```

- [ ] **Step 1: Adicionar as colunas**

Em `staff_account.spy.yaml`, depois de `active: bool`:
```yaml
  activationCodeHash: String?
  activationCodeExpiresAt: DateTime?
  activationCodeIssuedBy: String?
  activationCodeIssuedAt: DateTime?
```
(4 colunas, todas anuláveis; ajustar "3 colunas" do resumo para 4 ao documentar.)

- [ ] **Step 2: Gerar código e migração**

Run (comandos exatos em `backend/CLAUDE.md`, seção Serverpod):
```bash
cd backend/sinalacs_server && serverpod generate && serverpod create-migration
git status --short | head
```
Expected: nova pasta em `migrations/`, `definition.sql` com as 4 colunas, `ALTER TABLE ... ADD COLUMN` sem `DROP`. Conferir: `grep -n "DROP" migrations/<nova>/migration.sql` não devolve nada.

- [ ] **Step 3: Escrever o teste de integração que falha**

Em `test/integration/staff_activation_store_test.dart`, seguindo `staff_login_test.dart` (mesmo `withServerpod`, mesma semeadura de `staff_accounts`/`users` com UUID próprio `…0000b1`):

```dart
test('issue grava; find devolve; issue de novo substitui; clear apaga', () async {
  final store = OrmAcsCredentialStore(session: () => session, staff: true);
  final t0 = DateTime.utc(2026, 10, 7, 12);
  await store.issue(_staffId, codeHash: 'h1', expiresAt: t0.add(const Duration(hours: 1)), issuedBy: 'operador', at: t0);
  expect((await store.find(_staffId))?.codeHash, 'h1');
  await store.issue(_staffId, codeHash: 'h2', expiresAt: t0.add(const Duration(hours: 2)), issuedBy: 'operador', at: t0);
  expect((await store.find(_staffId))?.codeHash, 'h2');
  await store.clear(_staffId);
  expect(await store.find(_staffId), isNull);
});
```

- [ ] **Step 4: Rodar e ver falhar**

Run: `dart test test/integration/staff_activation_store_test.dart`
Expected: FAIL (`issue` não existe).

- [ ] **Step 5: Implementar**

Adicionar a interface acima ao `institutional_auth_service.dart` e, em `OrmAcsCredentialStore`, `implements AcsCredentialStore, TotpStore, StaffActivationStore`:

```dart
@override
Future<void> issue(String staffId, {required String codeHash, required DateTime expiresAt, required String issuedBy, required DateTime at}) async {
  await StaffAccount.db.updateWhere(
    _session(),
    columnValues: (t) => [
      t.activationCodeHash(codeHash),
      t.activationCodeExpiresAt(expiresAt),
      t.activationCodeIssuedBy(issuedBy),
      t.activationCodeIssuedAt(at),
    ],
    where: (t) => t.id.equals(UuidValue.fromString(staffId)),
  );
}

@override
Future<StaffActivationRecord?> find(String staffId) async {
  final c = await StaffAccount.db.findById(_session(), UuidValue.fromString(staffId));
  if (c?.activationCodeHash == null || c?.activationCodeExpiresAt == null) return null;
  return StaffActivationRecord(codeHash: c!.activationCodeHash!, expiresAt: c.activationCodeExpiresAt!);
}

@override
Future<void> clear(String staffId) async {
  await StaffAccount.db.updateWhere(
    _session(),
    columnValues: (t) => [t.activationCodeHash(null), t.activationCodeExpiresAt(null)],
    where: (t) => t.id.equals(UuidValue.fromString(staffId)),
  );
}
```

- [ ] **Step 6: Rodar e ver passar**

Run: `dart test test/integration/staff_activation_store_test.dart && dart analyze lib test | tail -3`
Expected: teste passa, sem avisos.

- [ ] **Step 7: Commit**

```bash
git add backend/sinalacs_server
git commit -m "feat(db): colunas e store do código de ativação do staff (#48)"
```

---

### Task 3: Serviço exige o código (`begin` e `confirm`)

**Files:**
- Modify: `backend/sinalacs_server/lib/src/application/auth/institutional_auth_service.dart` (`InstitutionalAuthService`, `beginTotpEnrollment`, `confirmTotpEnrollment`)
- Test: `backend/sinalacs_server/test/unit/institutional_auth_staff_test.dart`

**Interfaces:**
- Consumes: `StaffActivationStore`, `StaffActivationRecord` (Task 2); `StaffActivationCode.matches` (Task 1).
- Produces: `InstitutionalAuthService({..., this.activationStore})`; `beginTotpEnrollment({required matricula, required password, String? activationCode, DateTime? now})` e `confirmTotpEnrollment({..., String? activationCode, ...})`. Para `audience == staff`, `activationCode` é obrigatório (nulo/ausente = recusa). Para `acs`, é ignorado.

- [ ] **Step 1: Escrever os testes que falham**

Ler as primeiras ~60 linhas de `institutional_auth_staff_test.dart` e reaproveitar a construção do serviço de staff e os fakes ali usados. Acrescentar um `FakeStaffActivationStore` em memória:

```dart
class FakeStaffActivationStore implements StaffActivationStore {
  final _m = <String, StaffActivationRecord>{};
  @override
  Future<void> issue(String id, {required String codeHash, required DateTime expiresAt, required String issuedBy, required DateTime at}) async =>
      _m[id] = StaffActivationRecord(codeHash: codeHash, expiresAt: expiresAt);
  @override
  Future<StaffActivationRecord?> find(String id) async => _m[id];
  @override
  Future<void> clear(String id) async => _m.remove(id);
}
```

Casos (cada um com o serviço de staff + `activationStore` passado ao construtor):

```dart
const generica = 'Código de ativação inválido ou expirado.';
final agora = DateTime.utc(2026, 10, 7, 12);

test('begin sem código é recusado com a mensagem única e conta falha', ...);   // activationCode: null → AuthenticationFailedException(message: generica); failedAttempts == 1
test('begin com código errado é recusado', ...);
test('begin com código expirado é recusado (1 s depois)', ...);                 // now: expiresAt + 1s
test('begin com o código certo devolve segredo; repetido com o mesmo código também', ...);
test('confirm com código certo e TOTP certo ativa a MFA e apaga o código', ...); // store.find == null depois
test('o mesmo código não serve depois da ativação', ...);                        // novo begin → 'já está ativa' (conta com MFA)
test('conta com MFA já ativa recebe "já está ativa" mesmo com código errado', ...);
test('reemitir invalida o código anterior', ...);
test('código com minúsculas e hífens funciona', ...);
test('ACS: begin sem código continua funcionando', ...);                        // serviço com audience acs
test('5 códigos errados bloqueiam a conta', ...);                               // lockedUntil != null
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `dart test test/unit/institutional_auth_staff_test.dart`
Expected: FAIL (parâmetro `activationCode`/`activationStore` inexistentes).

- [ ] **Step 3: Implementar**

No construtor: `this.activationStore,` e `final StaffActivationStore? activationStore;`. Adicionar o helper e chamá-lo logo depois do bloco "MFA já ativa" de `begin`, e logo depois de `totp == null || totp.enabled` de `confirm` (no `confirm`, **antes** de `Totp.verify`):

```dart
static const _invalidActivation = 'Código de ativação inválido ou expirado.';

/// Só a audiência staff exige o código. Erro conta como falha de login e vira
/// auditoria; o texto é um só para não dizer se o código existiu ou expirou.
Future<void> _exigirCodigoDeAtivacao(AcsCredentialRecord record, String? code, DateTime at) async {
  if (audience != CredentialAudience.staff) return;
  final store = activationStore ?? (throw StateError('staff sem store de código de ativação'));
  final vigente = await store.find(record.acsId);
  final ok = vigente != null &&
      code != null &&
      at.isBefore(vigente.expiresAt) &&
      StaffActivationCode.matches(code, vigente.codeHash);
  if (ok) return;
  await _registrarFalha(record, at);
  await _recordAudit(record.acsId, 'denied_staff_activation_code');
  throw AuthenticationFailedException(message: _invalidActivation);
}
```

Em `beginTotpEnrollment`: adicionar `String? activationCode,` à assinatura e `await _exigirCodigoDeAtivacao(record, activationCode, at);` depois do `if (record.totp?.enabled ...)`. Em `confirmTotpEnrollment`: idem depois do `if (totp == null || totp.enabled)`, e, **depois** de `_totpStore().enable(...)` bem-sucedido: `await activationStore?.clear(record.acsId);` antes do `_recordAudit(... 'mfa_enabled')`. Importar `staff_activation_code.dart`.

- [ ] **Step 4: Rodar e ver passar**

Run: `dart test test/unit/institutional_auth_staff_test.dart test/unit/institutional_auth_service_test.dart test/unit/institutional_auth_mfa_test.dart`
Expected: todos passam (os do ACS provam que nada regrediu).

- [ ] **Step 5: Commit**

```bash
git add backend/sinalacs_server/lib backend/sinalacs_server/test
git commit -m "feat(auth): ativação da MFA do staff exige código de uso único (#48)"
```

---

### Task 4: Fiação do endpoint e teste contra Postgres

**Files:**
- Modify: `backend/sinalacs_server/lib/src/runtime/alert_runtime.dart` (`staffAuthServiceFor`: `activationStore: store`)
- Modify: `backend/sinalacs_server/lib/src/endpoints/auth_endpoint.dart` (`beginStaffTotpEnrollment`, `confirmStaffTotpEnrollment`: parâmetro `required String activationCode`)
- Modify: `backend/sinalacs_server/test/integration/staff_login_test.dart`, `test/unit/endpoint_auth_posture_test.dart` se citar a assinatura
- Regenerar: `serverpod generate`

**Interfaces:**
- Consumes: Task 3.
- Produces: RPC `auth.beginStaffTotpEnrollment({matricula, password, activationCode})` e `auth.confirmStaffTotpEnrollment({matricula, password, activationCode, code})` — o cliente Dart gerado (`sinalacs_client`) ganha o parâmetro; `apps/admin` consome na Task 6.

- [ ] **Step 1: Atualizar os testes de endpoint (falham até a fiação)**

Em `staff_login_test.dart` ("ativação de MFA do staff pelo endpoint"), semear um código antes de cada caso com `OrmAcsCredentialStore(staff:true).issue(...)` e passar `activationCode:`. Adicionar:

```dart
test('begin sem o código certo é recusado e não grava segredo', () async { ... });
test('confirm com código certo ativa; o código some do banco', () async { ... });
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `dart test test/integration/staff_login_test.dart`
Expected: FAIL (assinatura antiga).

- [ ] **Step 3: Implementar**

`staffAuthServiceFor` ganha `activationStore: store,`. Os dois métodos do endpoint passam `activationCode: activationCode`. Rodar `serverpod generate`.

- [ ] **Step 4: Rodar a suíte do backend**

Run: `cd backend/sinalacs_server && dart test 2>&1 | tail -5`
Expected: tudo verde (a suíte inteira, ~650 testes; os de integração exigem `postgres-test` de pé: `docker compose --profile test up -d postgres-test`).

- [ ] **Step 5: Commit**

```bash
git add backend
git commit -m "feat(auth): endpoints do staff recebem o código de ativação (#48)"
```

---

### Task 5: CLI do operador que emite o código

**Files:**
- Create: `backend/sinalacs_server/bin/issue_staff_activation_code.dart`
- Test: `backend/sinalacs_server/test/unit/issue_staff_activation_code_test.dart`

**Interfaces:**
- Consumes: `StaffActivationCode` (Task 1); colunas da Task 2.
- Produces: `dart run bin/issue_staff_activation_code.dart <matricula> --issued-by <quem> [--ttl-hours 24]`; saída: uma linha `Código de ativação (mostrado uma única vez): XXXX-…` e a validade. Código de saída `2` para matrícula inexistente/inativa ou argumento ausente. Lê o banco como `seed_acs_credentials.dart` (variáveis `SERVERPOD_DATABASE_*`, `package:postgres`). Lógica testável em `Future<IssueResult> issueStaffActivationCode(Connection db, {required String matricula, required String issuedBy, required Duration validity, DateTime? now})` exportada do próprio arquivo.

- [ ] **Step 1: Escrever o teste que falha**

Teste com conexão ao `postgres-test` (como outros testes de `bin/`; usar o padrão de `seed_staff_agreement_test.dart`): matrícula inexistente → `IssueResult.notFound`; conta inativa → `notFound`; conta ativa → retorna código, e no banco `activationCodeHash == StaffActivationCode.hash(codigo)`, `activationCodeIssuedBy == 'operador'`, e o hash **não** é igual ao código.

- [ ] **Step 2: Rodar e ver falhar**

Run: `dart test test/unit/issue_staff_activation_code_test.dart`
Expected: FAIL (arquivo inexistente).

- [ ] **Step 3: Implementar**

`issueStaffActivationCode` faz `SELECT id, active FROM staff_accounts WHERE "enrollmentId"=@m`; se não achar ou `active=false` devolve `notFound`; senão gera o código, e roda `UPDATE staff_accounts SET "activationCodeHash"=@h, "activationCodeExpiresAt"=@e, "activationCodeIssuedBy"=@by, "activationCodeIssuedAt"=@at WHERE id=@id`. `main` lê os argumentos (`--issued-by` obrigatório e não vazio), imprime só o código e a validade, **nunca** a matrícula+hash. Documentar no topo do arquivo: "ferramenta de operação; roda com acesso ao banco; a emissão fica registrada em `activationCodeIssuedBy/At` — a trilha `audit_logs` exige a cadeia de auditoria do servidor, que a CLI não carrega; o registro da emissão é essa coluna".

- [ ] **Step 4: Rodar e ver passar**

Run: `dart test test/unit/issue_staff_activation_code_test.dart && dart analyze bin | tail -2`
Expected: passa, sem avisos.

- [ ] **Step 5: Commit**

```bash
git add backend/sinalacs_server/bin/issue_staff_activation_code.dart backend/sinalacs_server/test/unit/issue_staff_activation_code_test.dart
git commit -m "feat(ops): CLI que emite o código de ativação do staff (#48)"
```

---

### Task 6: App admin pede o código antes do QR

**Files:**
- Modify: `apps/admin/lib/core/auth/admin_auth_backend.dart` (`beginMfaEnrollment`/`confirmMfaEnrollment` ganham `required String activationCode`; `BackendAdminAuth` repassa a `beginStaffTotpEnrollment`/`confirmStaffTotpEnrollment`)
- Modify: `apps/admin/lib/app/mfa_enrollment_screen.dart` (etapa 1: campo `activation_code_field` + botão `activation_continue`; etapa 2: o QR atual)
- Modify: `apps/admin/lib/app/login_screen.dart` (nada além da fiação, se `MfaEnrollmentScreen` mudar de assinatura)
- Modify: fakes e testes: `apps/admin/test/admin_auth_backend_test.dart`, `login_flow_test.dart`, `login_real_test.dart`
- Atualizar o cliente: `apps/admin` depende de `sinalacs_client` (regenerado na Task 4).

**Interfaces:**
- Consumes: RPC da Task 4.
- Produces: `AdminAuthBackend.beginMfaEnrollment({required String matricula, required String senha, required String activationCode})` e `confirmMfaEnrollment({..., required String activationCode, required String code})`. Chaves de widget: `activation_code_field`, `activation_continue`, `activation_error`.

- [ ] **Step 1: Escrever os testes de widget que falham**

Em `login_flow_test.dart`/`login_real_test.dart` (com o `AdminAuthBackend` falso que já existe): a tela de ativação **não** chama `beginMfaEnrollment` ao abrir; mostra o campo de código; com o código vazio, o botão fica sem ação e mostra `Informe o código de ativação.`; com um código, chama `beginMfaEnrollment(..., activationCode: <digitado>)` e só então mostra o QR; falha `AdminAuthFailure('Código de ativação inválido ou expirado.')` aparece em `activation_error` e o QR **não** aparece; `confirmMfaEnrollment` recebe o mesmo código.

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd apps/admin && flutter test test/login_flow_test.dart test/login_real_test.dart test/admin_auth_backend_test.dart`
Expected: FAIL (assinaturas antigas).

- [ ] **Step 3: Implementar**

`MfaEnrollmentScreen`: estado `_inicio == null && !_pediuCodigo` mostra o campo (rótulo `Código de ativação`, texto de ajuda `Peça o código à coordenação. Ele vale uma única vez.`, `autofillHints` vazio, `enableSuggestions: false`, `autocorrect: false`, `textCapitalization: characters`), e `_iniciar()` só roda no botão. Guardar `_codigoAtivacao` e repassá-lo a `confirmMfaEnrollment`. Cor de erro e alvos de toque seguem os tokens existentes (`*OnSurface`; alvo ≥ 48 dp): copiar o estilo do campo `Código de 6 dígitos` já na tela.

- [ ] **Step 4: Rodar o app admin inteiro**

Run: `cd apps/admin && flutter test && flutter analyze`
Expected: tudo verde (era 95 testes), sem avisos. `contrast_tokens_test`, `touch_targets_test` e `text_scale_test` passam com a nova etapa.

- [ ] **Step 5: Commit**

```bash
git add apps/admin
git commit -m "feat(admin): tela de ativação pede o código de uso único (#48)"
```

---

### Task 7: E2E e prova no emulador e no celular

**Files:**
- Modify: `backend/sinalacs_server/bin/seed_e2e_fixtures.dart` e a classe de fixtures (`E2eStaff`): gera e semeia um código; o bloco `staff` do manifesto ganha `activationCode`
- Modify: `apps/admin/integration_test/support/e2e_admin.dart`, `apps/admin/integration_test/admin_login_e2e.dart`
- Modify: `scripts/qa/admin_login_e2e.sh` (conferir no banco que o código foi apagado e que `activationCodeIssuedBy` ficou preenchido)
- Test: `backend/sinalacs_server/test/unit/` do seed de e2e (o teste unitário das fixtures já existente)

**Interfaces:**
- Consumes: Tasks 1–6.
- Produces: o relé `/admin` devolve `{matricula, senha, activationCode}`.

- [ ] **Step 1: Teste unitário das fixtures (falha)**

Estender o teste existente de fixtures para exigir `staff.activationCode` no formato `^([A-Z2-7]{4}-){6}[A-Z2-7]{2}$` e que o manifesto JSON o contenha.

- [ ] **Step 2: Rodar e ver falhar; implementar; rodar e ver passar**

Run: `cd backend/sinalacs_server && dart test test/unit -n "fixtures"` (ajustar ao nome real do arquivo do teste de fixtures; `grep -rln E2eStaff test`).
Expected: FAIL e depois PASS com o gerador (`StaffActivationCode.generate()`) e o `UPDATE` do seed.

- [ ] **Step 3: Estender o roteiro de integração**

Em `admin_login_e2e.dart`, no teste "primeiro acesso": digitar o código de ativação (`activation_code_field`), tocar `activation_continue`, só então ler o QR; novo teste **antes** dele: "código de ativação errado: recusado e o QR não aparece" (usa `<código>` alterado em 1 caractere). Ordem dos testes continua obrigatória (comentário do arquivo).

- [ ] **Step 4: Conferência no banco (script)**

Em `admin_login_e2e.sh`, após o login, acrescentar:
```bash
igual 'código de ativação apagado após a ativação' 'true' \
  "select (\"activationCodeHash\" is null)::text from staff_accounts where id='$staff_id'"
```

- [ ] **Step 5: Rodar no celular (o usuário executa; recria os containers de dev)**

Preflight: `adb -s 0087014315 get-state`, tela acordada, porta 8765 livre (`ss -ltn | grep :8765 || echo livre`).
```
! DEVICE=0087014315 ./scripts/qa/admin_login_e2e.sh 2>&1 | tee .superpowers/admin48_celular.log
```
Expected: todos os testes passam (incl. o do código errado), `TOTP ativado e passo registrado: true|true`, `código de ativação apagado após a ativação: true`.

- [ ] **Step 6: Rodar no emulador (o usuário sobe o AVD; o agente confere)**

```bash
export PATH="$PATH:$HOME/Android/Sdk/emulator:$HOME/Android/Sdk/platform-tools"
nohup emulator -avd Medium_Phone -no-snapshot -no-boot-anim >/dev/null 2>&1 &
adb wait-for-device && adb devices
```
Expected: `emulator-5554 device`. Depois:
```
! DEVICE=emulator-5554 ./scripts/qa/admin_login_e2e.sh 2>&1 | tee .superpowers/admin48_emulador.log
```
Expected: mesmo resultado. Se algum dos dois falhar, `superpowers:systematic-debugging` antes de editar; a primeira rodada do #39 falhou uma vez sem causa conhecida: **guardar o log sempre** (`tee`).

- [ ] **Step 7: Prova manual da CLI contra a stack de e2e (sem app)**

Com a stack de e2e no ar (`./scripts/qa/e2e_stack.sh up && ./scripts/qa/e2e_stack.sh seed`, o usuário roda), emitir um código e provar a recusa/uso por RPC é redundante com o teste de integração; aqui só conferir a CLI contra o banco real:
```bash
cd backend/sinalacs_server
SERVERPOD_DATABASE_HOST=localhost SERVERPOD_DATABASE_PORT=9090 SERVERPOD_DATABASE_NAME=sinalacs_e2e SERVERPOD_DATABASE_USER=postgres SERVERPOD_DATABASE_PASSWORD="$TEST_DATABASE_PASSWORD" \
  dart run bin/issue_staff_activation_code.dart ADM-INEXISTENTE --issued-by teste; echo "exit=$?"
```
Expected: `exit=2` e nenhuma linha com código.

- [ ] **Step 8: Commit**

```bash
git add backend apps/admin scripts/qa
git commit -m "test(e2e): login do staff com código de ativação, celular e emulador (#48)"
```

---

### Task 8: Telas, documentação e fechamento da issue

**Files:**
- Modify: `docs/telas-admin.md`; Create: `docs/screenshots/admin/01b-codigo-ativacao.png`
- Modify: `backend/CLAUDE.md` (bloco "Staff (backoffice, issue #39)"), `PROGRESS.md`, `apps/CLAUDE.md` se citar a ativação do staff

- [ ] **Step 1: Capturar a tela do código no celular**

Com a stack de e2e no ar e o app rodando (`cd apps/admin && flutter run -d 0087014315 --dart-define=SINALACS_HOST=https://localhost:8443/`), esconder as notificações (`adb shell settings put global sysui_demo_allowed 1` + `am broadcast -a com.android.systemui.demo -e command notifications -e visible false`), entrar com matrícula e senha do relé `/admin` (digitar a senha em blocos de 5 caracteres e conferir o tamanho: o `adb input text` perde caracteres) e capturar a tela do código com `adb exec-out screencap -p`. Abrir a imagem com `Read` e rejeitar qualquer dado real. Depois `am broadcast ... -e command exit` e `settings put global sysui_demo_allowed 0`.
Expected: PNG da etapa "Código de ativação".

- [ ] **Step 2: Atualizar `docs/telas-admin.md`**

Na lista dos três desfechos do login, acrescentar a etapa do código de ativação com a imagem nova, e dizer que o código é emitido por `bin/issue_staff_activation_code.dart`.

- [ ] **Step 3: Atualizar `backend/CLAUDE.md` e `PROGRESS.md`**

`backend/CLAUDE.md`: remover o risco residual de TOFU do staff; documentar o novo parâmetro, as 4 colunas, a mensagem única, a CLI (`dart run bin/issue_staff_activation_code.dart <matricula> --issued-by <quem>`) e a regra "emissão registrada em `activationCodeIssuedBy/At`, não em `audit_logs`". Dev: `ADM-001` precisa de um código emitido pela CLI (`docker compose exec`/`dart run` conforme o resto do arquivo) antes da primeira ativação. `PROGRESS.md`: mover o item "primeira ativação do TOTP do staff" de "Continua aberto" para fechado, citando commits, a data, os dois aparelhos (celular e emulador) e as contagens de testes rodados **nesta** execução. Item que sobrar (a emissão pela UI de coordenador depende da #43) permanece aberto, com esse nome.

- [ ] **Step 4: Conferências finais**

Run:
```bash
./scripts/qa/check_documentation_links.sh && ./scripts/qa/ci_invariants.sh && cd backend/sinalacs_server && dart test 2>&1 | tail -2 && cd ../../apps/admin && flutter test 2>&1 | tail -2
```
Expected: tudo verde.

- [ ] **Step 5: Commit, push e PR**

```bash
git add docs backend/CLAUDE.md PROGRESS.md apps
git commit -m "docs: ativação do TOTP do staff com código de uso único; fecha o risco da #48"
```
Push e abertura do PR só com confirmação do usuário (ação externa). Corpo do PR com `Closes #48` e as evidências (logs `.superpowers/admin48_*.log` resumidos, sem segredos).

- [ ] **Step 6: Devolver a stack de dev (o usuário executa)**

```
! ./scripts/qa/e2e_stack.sh down && docker compose up -d
```
Expected: serviços `healthy`; `adb -s 0087014315 shell wm size` sem `Override`.

---

## Self-Review

- **Cobertura da issue:** TOFU fechado (Tasks 1–4); fluxo do app (6); prova em aparelho real e emulador (7); "registra quem emitiu o código" (coluna `activationCodeIssuedBy/At`, Task 2/5, com a ressalva de não ir para `audit_logs`); `backend/CLAUDE.md` e `PROGRESS.md` (8). A emissão por tela de coordenador/administrador (a parte "emitido por coordenador/administrador com MFA (#43)" da opção 2) **não** entra: depende da #43; fica aberto e nomeado.
- **Decisão que o plano toma pelo usuário (confirmar):** opção 2 com emissão por CLI de operador, em vez da opção 1 (segredo pré-registrado) ou da emissão por UI (#43). Custo se errado: Tasks 3–6 trocam o formato do segredo/código; Tasks 1 e 2 em boa parte se reaproveitam.
- **Placeholders:** o nome do arquivo de teste das fixtures (Task 7 Step 2) vem de um `grep` indicado, pois não foi lido; os fakes do `institutional_auth_staff_test.dart` (Task 3) são reaproveitados lendo o arquivo, e só o `FakeStaffActivationStore` é novo e está completo.
- **Tipos:** `StaffActivationStore.issue/find/clear` e `StaffActivationRecord{codeHash,expiresAt}` iguais nas Tasks 2, 3, 4 e 5; `activationCode` é `String?` no serviço e `required String` no endpoint e no app.
- **Riscos conhecidos:** `serverpod generate` altera muitos arquivos gerados (revisar o diff só pelo que é do #48); `ADM-001` do desenvolvimento deixa de ativar sem código (documentado na Task 8).
