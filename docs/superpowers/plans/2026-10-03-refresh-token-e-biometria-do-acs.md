# Refresh token rotativo e desbloqueio biométrico do ACS — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Com MFA ligada, o ACS digita matrícula + senha + código TOTP **uma vez por turno**, e não a cada 15 minutos; o desbloqueio entre uma casa e outra é por impressão digital.

**Architecture:** O backend passa a emitir, junto com o JWT de 15 min, um refresh token **opaco, rotativo e com detecção de reuso** (família de tokens, só o hash no banco, amarrado ao aparelho). O app guarda esse token no Keystore (nunca a senha), renova o JWT sozinho por `auth.refreshSession` (uma chamada por vez) e deixa de reter a senha em memória. Um *portão de bloqueio* (`AppLockGate`), posto **acima** do `Navigator`, cobre o app após ficar em segundo plano e pede biometria (`local_auth`) — sem destruir a pilha de telas, o feed MQTT, a fila de visitas nem formulário em andamento.

**Tech Stack:** Serverpod 3.4.13 (Dart), Postgres, Flutter (`flutter_secure_storage` já presente, `local_auth` novo), `crypto` (SHA-256).

**Spec:** `spec/lgpd_design.md` LGPD-RT06 (linha 709: "JWT … 8h (ACS); refresh token rotativo; MFA com TOTP para ACS; autenticação biométrica nativa do dispositivo") e linha 669; `PROGRESS.md` seção "Pendências do ACS", D6 (refresh token adiado de propósito); `spec/PRD_system.md` (INV-01 território, RF07).

## Global Constraints

- Texto de UI, comentários e docs em **português**; nomes de código seguem o que o arquivo vizinho já usa.
- Território (INV-01): a `microAreaId` do novo JWT vem **sempre do banco, relida a cada refresh** — nunca copiada do token antigo. ACS desativado ou sem microárea não renova.
- Alerta vermelho nunca some em silêncio: **o bloqueio biométrico e a expiração de sessão não podem destruir o painel, o feed MQTT, a fila de alertas, a fila de visitas nem um formulário aberto.** Mesma regra de `session_reauth_test.dart`.
- Nunca persistir senha. O refresh token só no `flutter_secure_storage` (Keystore); nunca em log, nunca em mensagem de erro, nunca em `shared_preferences`.
- Backend guarda **somente o hash SHA-256** do refresh token (o token tem 256 bits aleatórios; sem pepper). Nunca o token em claro.
- Toda recusa de refresh tem **uma só** mensagem para o cliente (`Sessão expirada. Entre novamente.`); o motivo real vai só para `audit_logs`.
- Nunca editar `lib/src/generated/` nem `migrations/` à mão: `serverpod generate` + `serverpod create-migration`.
- Nunca dado real de paciente em teste, log ou config. Dados sintéticos, UUIDs próprios por suíte.
- Commits **sem** "Co-Authored-By" / "Generated with Claude Code" (regra do `CLAUDE.md` do repositório). Um commit por tarefa.
- `defaultTargetPlatform`/Android: `minSdk = 24` (já vigente); `local_auth` exige `FlutterFragmentActivity` e `USE_BIOMETRIC`.
- CI: não mexer em `.github/workflows/ci.yml` (vigiado por `scripts/qa/ci_invariants.sh`).

## Decisões de produto (P2, P4 e P5 confirmadas pelo usuário em 2026-10-03; P1 e P3 seguem propostas — todas reversíveis por constante)

| # | Decisão | Valor proposto | Por quê |
|---|---|---|---|
| P1 | Janela **ociosa** do refresh token | 2 h | Cada rotação estende até 2 h; aparelho esquecido no armário não renova. |
| P2 | Janela **absoluta** | **8 h** desde o login com senha+TOTP (confirmado: segue as 8 h que a spec LGPD-RT06 cita para o ACS) | Cobre o turno; o dia seguinte exige credencial completa. As 8 h da spec valem como duração da *sessão*; o JWT em si continua em 15 min e é renovado pelo refresh, para que um token vazado dure pouco. |
| P3 | Tolerância de reuso | 30 s | Resposta de refresh perdida em rede ruim: o app repete o token antigo. Sem tolerância, o campo derrubaria o ACS por falha de rede. Fora dos 30 s, reuso = suspeita de roubo → **a família inteira é revogada**. |
| P4 | Bloqueio por inatividade | 30 s em segundo plano | "A tela apagou entre uma casa e outra" volta sem digitar nada de novo; mais que isso pede digital. **Confirmado.** |
| P5 | Sem biometria cadastrada no aparelho | Cai para PIN/padrão/senha do aparelho (`biometricOnly: false`); sem **nenhum** bloqueio de tela no aparelho, o app **não retoma** sessão salva (exige login completo) | Sem trava física, o refresh token seria uma chave deixada na porta. **Confirmado.** |
| P6 | "Sair" | Revoga a família no servidor e apaga o token do Keystore | Resposta ao roubo/troca de turno; hoje não há botão. |

## Review Focus

1. **Resposta de refresh perdida** (rede cai depois de o servidor rotacionar): o app repete o token antigo dentro de 30 s → deve receber sessão nova, **não** ser deslogado. Teste na Task 2 (`reuso dentro da tolerância`) e na Task 5.
2. **Duas chamadas simultâneas renovando** (fila de visitas + `listMicroArea` + pull no mesmo instante com JWT vencido): o app deve fazer **um** refresh e compartilhar o resultado, senão ele mesmo dispara a detecção de reuso. Teste na Task 5 (`single-flight`).
3. **Token roubado reusado em outro aparelho** ou **após a tolerância**: família inteira revogada, os dois lados caem para login completo. Teste na Task 2.
4. **ACS desativado ou trocado de microárea durante o turno**: o próximo refresh recusa (desativado) ou emite JWT com a microárea nova (INV-01). Teste na Task 2.
5. **Biometria cancelada/falha/bloqueada pelo SO** com alerta chegando por MQTT por baixo: nada é descartado; "Entrar com senha" é sempre possível; sem laço de prompts. Testes na Task 7.

---

## Estrutura de arquivos

**Backend (`backend/sinalacs_server/`)**
- Criar `lib/src/models/acs_refresh_token.spy.yaml` — tabela `acs_refresh_tokens`.
- Criar `lib/src/models/exceptions/session_expired_exception.spy.yaml`.
- Modificar `lib/src/models/api/development_login_result.spy.yaml` — campo opcional `refreshToken`.
- Criar `lib/src/application/auth/refresh_token_service.dart` — regra de rotação, interface `RefreshTokenStore`.
- Criar `lib/src/infrastructure/database/orm_refresh_token_store.dart` — ORM + `UPDATE` atômico.
- Modificar `lib/src/runtime/alert_runtime.dart` — `refreshTokenServiceFor(session)`.
- Modificar `lib/src/endpoints/auth_endpoint.dart` — `loginInstitutional` emite refresh; novos `refreshSession` e `logout`.
- Modificar `test/unit/endpoint_auth_posture_test.dart` — allowlist dos dois métodos novos.
- Criar `test/unit/refresh_token_service_test.dart`, `test/integration/refresh_token_test.dart`.

**App (`apps/acs/`)**
- Criar `lib/core/security/refresh_token_store.dart` — Keystore (`RefreshTokenStore`, `SecureStorageRefreshTokenStore`, `MemoryRefreshTokenStore`) e `DeviceIdStore`.
- Modificar `lib/core/network/backend_client.dart` — `AcsBackend` ganha `resumeSession`/`logout`; `BackendClient` renova por refresh, single-flight, sem `_credentials`.
- Criar `lib/core/security/biometric_gate.dart` — porta sobre `local_auth` (`BiometricGate`, `LocalAuthBiometricGate`).
- Criar `lib/app/app_lock_gate.dart` — overlay de bloqueio acima do `Navigator`.
- Modificar `lib/app/app.dart` — monta o gate; retomada de sessão na `LoginScreen`; "Sair" em Ajustes.
- Modificar `android/app/src/main/AndroidManifest.xml`, `MainActivity.kt`, `pubspec.yaml`.
- Modificar `test/support/fake_rpc_server.dart`; testes novos `refresh_session_test.dart`, `app_lock_gate_test.dart`, `session_resume_test.dart`; ajustar `session_expiry_mfa_test.dart`, `session_reauth_test.dart`, `android_manifest_test.dart`.

**Docs:** `spec/lgpd_data_audit.md`, `spec/lgpd_design.md`, `backend/CLAUDE.md`, `apps/CLAUDE.md`, `CLAUDE.md` (parágrafo "Still missing"), `PROGRESS.md`.

---

## Parte A — Refresh token

### Task 1: Modelo, exceção, campo no resultado e migração

**Files:**
- Create: `backend/sinalacs_server/lib/src/models/acs_refresh_token.spy.yaml`
- Create: `backend/sinalacs_server/lib/src/models/exceptions/session_expired_exception.spy.yaml`
- Modify: `backend/sinalacs_server/lib/src/models/api/development_login_result.spy.yaml`
- Generated: `lib/src/generated/**`, `migrations/<timestamp>/**`, `backend/sinalacs_client/**`
- Modify: `spec/lgpd_data_audit.md`

**Interfaces:**
- Produces: classes geradas `AcsRefreshToken` (tabela `acs_refresh_tokens`), `SessionExpiredException(message)`, `DevelopmentLoginResult.refreshToken` (`String?`).

- [ ] **Step 1: Criar o modelo da tabela**

```yaml
### Refresh token do ACS (LGPD-RT06). Uma linha por token emitido; os tokens de
### um mesmo login formam uma *família* (`familyId`) e a rotação encadeia
### dentro dela.
###
### **Nunca** o token: só o SHA-256 dele em hex. O token é 256 bits aleatórios,
### então um hash simples basta (não há senha humana para adivinhar).
class: AcsRefreshToken
table: acs_refresh_tokens
fields:
  id: UuidValue?, defaultPersist=random
  userId: UuidValue, relation(parent=users)
  ### Todos os tokens nascidos do mesmo login por senha+TOTP.
  familyId: UuidValue
  tokenHash: String
  ### Aparelho que recebeu o token. Token apresentado por outro aparelho
  ### revoga a família.
  deviceId: String
  issuedAt: DateTime
  ### Janela ociosa: renovada a cada rotação, nunca além de `absoluteExpiresAt`.
  idleExpiresAt: DateTime
  ### Teto do turno, fixado no login por senha+TOTP e herdado pelos filhos.
  absoluteExpiresAt: DateTime
  ### `null` = ainda não usado. Preenchido na rotação.
  rotatedAt: DateTime?
  ### `null` = vigente. Preenchido na revogação da família ou no logout.
  revokedAt: DateTime?
indexes:
  acs_refresh_tokens_hash_key:
    fields: tokenHash
    unique: true
  acs_refresh_tokens_family_idx:
    fields: familyId
  acs_refresh_tokens_user_idx:
    fields: userId
```

- [ ] **Step 2: Criar a exceção** (mesmo formato de `mfa_required_exception.spy.yaml`)

```yaml
### O refresh token não vale mais (expirado, revogado, reusado, de outro
### aparelho ou de conta desativada). Mensagem única de propósito: o motivo
### real fica só em audit_logs.
exception: SessionExpiredException
fields:
  message: String
```

- [ ] **Step 3: Acrescentar o campo ao resultado de login**

Em `development_login_result.spy.yaml`, abaixo de `tokenType: String`:

```yaml
  ### Só no `loginInstitutional` e no `refreshSession`. `null` nos demais
  ### emissores (paciente, `developmentLogin`).
  refreshToken: String?
```

- [ ] **Step 4: Gerar e migrar**

Run (em `backend/sinalacs_server`): `serverpod generate && serverpod create-migration`
Expected: nova pasta em `migrations/` criando `acs_refresh_tokens` com FK para `users` e três índices; `sinalacs_client` regenerado.

- [ ] **Step 5: Classificar a tabela no audit de LGPD**

Em `spec/lgpd_data_audit.md`, acrescentar a seção de `acs_refresh_tokens` no formato das demais: `userId` (identificador pessoal do ACS, pseudonimizado por UUID), `tokenHash` (credencial — hash, não reversível), `deviceId`, datas; sem dado de saúde. Atualizar a contagem de tabelas (re-medir em `definition.sql` da migração mais recente, como pede o `CLAUDE.md`).

- [ ] **Step 6: Verificar e commitar**

Run: `cd backend && dart pub get && dart analyze && cd sinalacs_server && dart test test/unit`
Expected: sem erros; testes unitários verdes (nada usa o campo novo ainda).

```bash
git add backend spec/lgpd_data_audit.md
git commit -m "feat(auth): tabela acs_refresh_tokens, SessionExpiredException e refreshToken no resultado de login"
```

---

### Task 2: `RefreshTokenService` (regra de rotação) — TDD com store em memória

**Files:**
- Create: `backend/sinalacs_server/lib/src/application/auth/refresh_token_service.dart`
- Test: `backend/sinalacs_server/test/unit/refresh_token_service_test.dart`

**Interfaces:**
- Consumes: `AuthenticatedUser`, `AuditTrail.recordSafely(AuditEvent)` (`audit_trail.dart`), `UserRole`.
- Produces:
  - `class RefreshAccount { final bool active; final String? microAreaId; }`
  - `class RefreshTokenRecord` (campos da tabela, `String`/`DateTime`).
  - `abstract interface class RefreshTokenStore { insert(RefreshTokenRecord, String tokenHash); Future<RefreshTokenRecord?> findByHash(String); Future<bool> markRotated(String id, DateTime at); Future<void> revokeFamily(String familyId, DateTime at); Future<RefreshAccount?> findAccount(String userId); Future<void> deleteExpiredFor(String userId, DateTime before); }`
  - `class RefreshTokenService` com `issue(AuthenticatedUser, {DateTime? now}) → Future<String>`, `refresh({required String refreshToken, required String deviceId, DateTime? now}) → Future<RefreshedSession>`, `revoke(String refreshToken, {DateTime? now}) → Future<void>`; `class RefreshedSession { AuthenticatedUser user; String refreshToken; }`.
  - Constantes `idleWindow = 2h`, `absoluteWindow = 8h`, `reuseGrace = 30s`; recusa lança `SessionExpiredException(message: RefreshTokenService.deniedMessage)`.

- [ ] **Step 1: Escrever os testes que falham** — `refresh_token_service_test.dart` com um `_MemoryStore` (mapas em memória; `markRotated` devolve `false` se `rotatedAt != null` ou `revokedAt != null`, imitando o `UPDATE` condicional) e um `_AuditSpy` que acumula `AuditEvent`. Casos, cada um um `test`:

```dart
const _acsId = '00000000-0000-4000-8000-000000000091';
const _area = '00000000-0000-4000-8000-000000000092';
const _user = AuthenticatedUser(
    id: _acsId, role: UserRole.acs, microAreaId: _area, deviceId: 'aparelho-A');

test('issue grava só o hash e devolve token de 43+ caracteres', ...);          // store nunca contém o token
test('refresh rotaciona: devolve token novo, marca o antigo, mesma família', ...);
test('refresh relê a microárea do banco, não a do token', ...);               // account.microAreaId muda → user novo
test('conta desativada: recusa e revoga a família', ...);
test('conta sem microárea: recusa e revoga a família', ...);
test('aparelho diferente: recusa e revoga a família', ...);
test('janela ociosa vencida: recusa', ...);                                   // now + 2h01
test('teto absoluto vencido mesmo com rotação recente: recusa', ...);         // 8h01
test('filho nunca passa do teto absoluto do pai', ...);                       // idleExpiresAt == min(now+2h, absolute)
test('reuso dentro da tolerância (30 s): emite token novo e NÃO revoga', ...);
test('reuso fora da tolerância: revoga a família inteira e recusa', ...);     // o filho vigente também cai
test('token desconhecido: recusa, sem auditoria (sem sujeito)', ...);
test('revoke apaga a família; revoke de token desconhecido não lança', ...);
test('toda recusa lança a MESMA mensagem', ...);                              // compara .message de 4 recusas distintas
test('cada desfecho relevante gera auditoria: refresh_granted, denied_reuse, denied_device, denied_inactive', ...);
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `dart test test/unit/refresh_token_service_test.dart`
Expected: FAIL (`refresh_token_service.dart` não existe).

- [ ] **Step 3: Implementar**

```dart
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

class RefreshAccount {
  const RefreshAccount({required this.active, required this.microAreaId});
  final bool active;
  final String? microAreaId;
}

class RefreshTokenRecord {
  const RefreshTokenRecord({
    required this.id,
    required this.userId,
    required this.familyId,
    required this.deviceId,
    required this.issuedAt,
    required this.idleExpiresAt,
    required this.absoluteExpiresAt,
    this.rotatedAt,
    this.revokedAt,
  });

  final String id;
  final String userId;
  final String familyId;
  final String deviceId;
  final DateTime issuedAt;
  final DateTime idleExpiresAt;
  final DateTime absoluteExpiresAt;
  final DateTime? rotatedAt;
  final DateTime? revokedAt;
}

abstract interface class RefreshTokenStore {
  Future<void> insert(RefreshTokenRecord record, String tokenHash);
  Future<RefreshTokenRecord?> findByHash(String tokenHash);

  /// Marca `rotatedAt` **só se** a linha ainda não foi rotacionada nem
  /// revogada (um `UPDATE` condicional). `false` = outra requisição ganhou.
  Future<bool> markRotated(String id, DateTime at);

  Future<void> revokeFamily(String familyId, DateTime at);
  Future<RefreshAccount?> findAccount(String userId);

  /// Poda do próprio usuário: tokens cujo teto absoluto já passou.
  Future<void> deleteExpiredFor(String userId, DateTime before);
}

class RefreshedSession {
  const RefreshedSession({required this.user, required this.refreshToken});
  final AuthenticatedUser user;
  final String refreshToken;
}

class RefreshTokenService {
  RefreshTokenService({required this.store, required this.audit, Random? random})
      : _random = random ?? Random.secure();

  final RefreshTokenStore store;
  final AuditTrail audit;
  final Random _random;

  static const idleWindow = Duration(hours: 2);
  static const absoluteWindow = Duration(hours: 8);
  static const reuseGrace = Duration(seconds: 30);
  static const deniedMessage = 'Sessão expirada. Entre novamente.';

  /// Primeiro token de uma família nova (login por senha+TOTP).
  Future<String> issue(AuthenticatedUser user, {DateTime? now}) async {
    final at = (now ?? DateTime.now()).toUtc();
    await store.deleteExpiredFor(user.id, at);
    return _insert(
      userId: user.id,
      familyId: _uuid(),
      deviceId: user.deviceId,
      at: at,
      absoluteExpiresAt: at.add(absoluteWindow),
    );
  }

  Future<RefreshedSession> refresh({
    required String refreshToken,
    required String deviceId,
    DateTime? now,
  }) async {
    final at = (now ?? DateTime.now()).toUtc();
    final record = await store.findByHash(_hash(refreshToken));
    if (record == null) throw _denied(); // sem sujeito para auditar

    if (record.revokedAt != null) {
      await _audit(record.userId, 'denied_revoked');
      throw _denied();
    }
    if (record.deviceId != deviceId) {
      await store.revokeFamily(record.familyId, at);
      await _audit(record.userId, 'denied_device');
      throw _denied();
    }
    if (!at.isBefore(record.absoluteExpiresAt) || !at.isBefore(record.idleExpiresAt)) {
      await _audit(record.userId, 'denied_expired');
      throw _denied();
    }

    final rotatedAt = record.rotatedAt;
    if (rotatedAt != null && at.difference(rotatedAt) > reuseGrace) {
      await store.revokeFamily(record.familyId, at);
      await _audit(record.userId, 'denied_reuse');
      throw _denied();
    }

    final account = await store.findAccount(record.userId);
    final microAreaId = account?.microAreaId;
    if (account == null || !account.active || microAreaId == null) {
      await store.revokeFamily(record.familyId, at);
      await _audit(record.userId, 'denied_inactive');
      throw _denied();
    }

    // Quem perde a corrida do UPDATE é uma chamada concorrente com o mesmo
    // token, no mesmo instante: cai na mesma tolerância do reuso, não é roubo.
    if (rotatedAt == null) await store.markRotated(record.id, at);

    final child = await _insert(
      userId: record.userId,
      familyId: record.familyId,
      deviceId: deviceId,
      at: at,
      absoluteExpiresAt: record.absoluteExpiresAt,
    );
    await _audit(record.userId, 'refresh_granted');
    return RefreshedSession(
      user: AuthenticatedUser(
        id: record.userId,
        role: UserRole.acs,
        microAreaId: microAreaId, // relida agora (INV-01)
        deviceId: deviceId,
      ),
      refreshToken: child,
    );
  }

  Future<void> revoke(String refreshToken, {DateTime? now}) async {
    final at = (now ?? DateTime.now()).toUtc();
    final record = await store.findByHash(_hash(refreshToken));
    if (record == null) return;
    await store.revokeFamily(record.familyId, at);
    await _audit(record.userId, 'logout');
  }

  Future<String> _insert({
    required String userId,
    required String familyId,
    required String deviceId,
    required DateTime at,
    required DateTime absoluteExpiresAt,
  }) async {
    final token = base64Url
        .encode(List<int>.generate(32, (_) => _random.nextInt(256)))
        .replaceAll('=', '');
    final idle = at.add(idleWindow);
    await store.insert(
      RefreshTokenRecord(
        id: _uuid(),
        userId: userId,
        familyId: familyId,
        deviceId: deviceId,
        issuedAt: at,
        idleExpiresAt: idle.isAfter(absoluteExpiresAt) ? absoluteExpiresAt : idle,
        absoluteExpiresAt: absoluteExpiresAt,
      ),
      _hash(token),
    );
    return token;
  }

  String _hash(String token) => sha256.convert(utf8.encode(token)).toString();

  String _uuid() {
    final b = List<int>.generate(16, (_) => _random.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }

  SessionExpiredException _denied() => SessionExpiredException(message: deniedMessage);

  Future<void> _audit(String userId, String result) => audit.recordSafely(
        AuditEvent(
          userId: userId,
          actionType: 'login',
          resourceType: 'session_refresh',
          result: result,
        ),
      );
}
```

> Nota ao executor: se o repositório já tem um gerador de UUID v4 (grep `Uuid()` em `lib/src`), use-o em vez de `_uuid()` e remova o método.

- [ ] **Step 4: Rodar e ver passar**

Run: `dart test test/unit/refresh_token_service_test.dart`
Expected: todos os casos do Step 1 verdes. Rodar `dart analyze`.

- [ ] **Step 5: Commit**

```bash
git add backend/sinalacs_server/lib/src/application/auth/refresh_token_service.dart backend/sinalacs_server/test/unit/refresh_token_service_test.dart
git commit -m "feat(auth): serviço de refresh token rotativo com detecção de reuso e tolerância de rede"
```

---

### Task 3: `OrmRefreshTokenStore` com rotação atômica — contra Postgres

**Files:**
- Create: `backend/sinalacs_server/lib/src/infrastructure/database/orm_refresh_token_store.dart`
- Test: `backend/sinalacs_server/test/integration/refresh_token_test.dart`

**Interfaces:**
- Consumes: `RefreshTokenStore`, `RefreshTokenRecord`, `RefreshAccount` (Task 2); `AcsRefreshToken`, `Acs`, `User` (gerados).
- Produces: `OrmRefreshTokenStore({required Session Function() session})`.

- [ ] **Step 1: Teste de integração que falha** — seguir o arranjo de `test/integration/institutional_mfa_test.dart` (`withServerpod`, seed sintético de `Ubs`/`MicroArea`/`User`/`Acs`, ids próprios `...0a1`). Casos:
  - `insert` + `findByHash` devolvem os mesmos campos; a linha **não contém** o token em claro (consultar a coluna `tokenHash` e comparar com o SHA-256).
  - `markRotated` chamado duas vezes em paralelo (`Future.wait`) → exatamente uma devolve `true`.
  - `markRotated` em linha revogada → `false`.
  - `revokeFamily` revoga todos os tokens da família e só eles (outra família intacta).
  - `findAccount` devolve `active`/`microAreaId` reais (usar `acs.active` e `users.microAreaId`, como `OrmAcsCredentialStore.findByEnrollmentId`).
  - `deleteExpiredFor` só apaga linhas do próprio usuário com `absoluteExpiresAt < before`.

- [ ] **Step 2: Rodar e ver falhar**

Run: `docker compose --profile test up -d postgres-test && dart test test/integration/refresh_token_test.dart`
Expected: FAIL (arquivo do store não existe).

- [ ] **Step 3: Implementar** — `markRotated` precisa ser **uma instrução**, no mesmo estilo de `registerFailedAttempt` (o ORM não expressa o `WHERE` condicional com contagem de linhas de forma atômica):

```dart
@override
Future<bool> markRotated(String id, DateTime at) async {
  final linhas = await _session().db.unsafeExecute(
    'UPDATE "acs_refresh_tokens" SET "rotatedAt" = @at '
    'WHERE "id" = @id::uuid AND "rotatedAt" IS NULL AND "revokedAt" IS NULL;',
    parameters: QueryParameters.named({'at': at, 'id': id}),
  );
  return linhas == 1;
}

@override
Future<void> revokeFamily(String familyId, DateTime at) async {
  await _session().db.unsafeExecute(
    'UPDATE "acs_refresh_tokens" SET "revokedAt" = @at '
    'WHERE "familyId" = @familyId::uuid AND "revokedAt" IS NULL;',
    parameters: QueryParameters.named({'at': at, 'familyId': familyId}),
  );
}
```

`insert`, `findByHash`, `findAccount`, `deleteExpiredFor` usam o ORM (`AcsRefreshToken.db.insertRow` / `findFirstRow` / `deleteWhere`; `findAccount` = `Acs.db.findFirstRow(id == userId)` + `User.db.findFirstRow(id == userId)`).

- [ ] **Step 4: Rodar e ver passar**

Run: `dart test test/integration/refresh_token_test.dart`
Expected: PASS, incluindo a corrida (`exatamente um true`).

- [ ] **Step 5: Commit**

```bash
git add backend/sinalacs_server/lib/src/infrastructure/database/orm_refresh_token_store.dart backend/sinalacs_server/test/integration/refresh_token_test.dart
git commit -m "feat(auth): store do refresh token com rotação atômica em uma instrução"
```

---

### Task 4: Endpoints — `loginInstitutional` emite refresh; `refreshSession` e `logout`

**Files:**
- Modify: `backend/sinalacs_server/lib/src/runtime/alert_runtime.dart` (junto de `institutionalAuthServiceFor`)
- Modify: `backend/sinalacs_server/lib/src/endpoints/auth_endpoint.dart`
- Modify: `backend/sinalacs_server/test/unit/endpoint_auth_posture_test.dart` (`_publicMethodsByDesign`)
- Test: acrescentar a `backend/sinalacs_server/test/integration/refresh_token_test.dart`; ajustar `test/integration/institutional_login_test.dart` se afirmar a forma do resultado.

**Interfaces:**
- Consumes: `RefreshTokenService`, `OrmRefreshTokenStore` (Tasks 2–3), `runtime.auth.issueToken`.
- Produces (RPC): `auth.loginInstitutional(...)` → `DevelopmentLoginResult` com `refreshToken` preenchido; `auth.refreshSession({required String refreshToken, required String deviceId}) → DevelopmentLoginResult`; `auth.logout({required String refreshToken}) → void`.

- [ ] **Step 1: Testes de integração que falham** (via endpoint, no padrão de `institutional_login_test.dart`):
  - login institucional (com MFA ligada e código válido) devolve `refreshToken != null`; o `deviceId` enviado é o `device_id` do JWT.
  - `refreshSession` com o token devolvido → novo `accessToken` válido (`runtime.auth.verifyToken` ≠ null, mesma `sub`, `micro_area_id` do banco) e novo `refreshToken` diferente.
  - `refreshSession` **sem TOTP e sem senha** funciona — é o objetivo.
  - segundo uso do token antigo, > 30 s depois (passar `now` não é possível pelo endpoint: use o service direto com relógio injetado nesse caso, ou insira a linha com `rotatedAt` antigo), → `SessionExpiredException` e família revogada (o filho também recusa).
  - mudar `users.microAreaId` no banco entre dois refresh → o segundo JWT carrega a microárea nova.
  - `acs.active = false` → `SessionExpiredException`.
  - `logout` → o token passa a recusar; `logout` com token inexistente não lança.
  - login do **paciente** (`verifyOtp`) continua com `refreshToken == null`.

- [ ] **Step 2: Rodar e ver falhar**

Run: `dart test test/integration/refresh_token_test.dart`
Expected: FAIL (`refreshSession` não existe).

- [ ] **Step 3: Implementar**

`alert_runtime.dart`:

```dart
RefreshTokenService refreshTokenServiceFor(Session session) => RefreshTokenService(
      store: OrmRefreshTokenStore(session: () => session),
      audit: auditTrailFor(session),
    );
```

`auth_endpoint.dart` — em `loginInstitutional`, depois de obter `user`:

```dart
final refreshToken = await runtime.refreshTokenServiceFor(session).issue(user);
return DevelopmentLoginResult(
  accessToken: runtime.auth.issueToken(user),
  tokenType: 'Bearer',
  refreshToken: refreshToken,
);
```

e os dois métodos novos:

```dart
/// Renova a sessão do ACS sem pedir senha nem TOTP (LGPD-RT06). Público por
/// desenho: quem chama já perdeu o JWT de 15 min — o refresh token, opaco e de
/// uso único, é a credencial. Toda recusa é a mesma `SessionExpiredException`.
Future<DevelopmentLoginResult> refreshSession(
  Session session, {
  required String refreshToken,
  required String deviceId,
}) async {
  final runtime = AlertRuntime.instance;
  final renewed = await runtime
      .refreshTokenServiceFor(session)
      .refresh(refreshToken: refreshToken, deviceId: deviceId);
  return DevelopmentLoginResult(
    accessToken: runtime.auth.issueToken(renewed.user),
    tokenType: 'Bearer',
    refreshToken: renewed.refreshToken,
  );
}

/// Encerra o turno: revoga a família inteira. Idempotente.
Future<void> logout(Session session, {required String refreshToken}) =>
    AlertRuntime.instance.refreshTokenServiceFor(session).revoke(refreshToken);
```

`endpoint_auth_posture_test.dart` — acrescentar a `_publicMethodsByDesign`:

```dart
  'AuthEndpoint.refreshSession':
      'renovação por refresh token (LGPD-RT06): quem chama já perdeu o JWT; o '
      'token opaco, rotativo e amarrado ao aparelho É a credencial',
  'AuthEndpoint.logout':
      'revoga pela posse do refresh token; idempotente e sem efeito sobre '
      'token desconhecido',
```

Atualizar o comentário de `AuthEndpoint.patientSessionLifetime` ("a renovação dele é silenciosa, por credencial em memória") para refletir o refresh token.

- [ ] **Step 4: Rodar a suíte do backend inteira**

Run: `serverpod generate` (se a assinatura mudou) e `dart test`
Expected: tudo verde, incluindo `endpoint_auth_posture_test` e `app_config_test`.

- [ ] **Step 5: Commit**

```bash
git add backend
git commit -m "feat(auth): loginInstitutional emite refresh token; refreshSession e logout"
```

---

### Task 5: App — armazenamento, renovação silenciosa e fim da senha em memória

**Files:**
- Create: `apps/acs/lib/core/security/refresh_token_store.dart`
- Modify: `apps/acs/lib/core/network/backend_client.dart` (`AcsBackend`, `MisconfiguredBackend`, `BackendClient`)
- Modify: `apps/acs/test/support/fake_rpc_server.dart`
- Test: `apps/acs/test/refresh_session_test.dart` (novo); ajustar `test/session_expiry_mfa_test.dart` e `test/session_reauth_test.dart`.
- Regenerar o cliente: `sinalacs_client` já veio da Task 1; rodar `flutter pub get` em `apps/acs`.

**Interfaces:**
- Consumes: RPC `auth.refreshSession`, `auth.logout`, `DevelopmentLoginResult.refreshToken` (cliente gerado).
- Produces:
  - `abstract interface class RefreshTokenStore { Future<String?> read(); Future<void> write(String token); Future<void> clear(); }` + `SecureStorageRefreshTokenStore` (chave `acs_refresh_token`) + `MemoryRefreshTokenStore` (testes).
  - `abstract interface class DeviceIdStore { Future<String> readOrCreate(); }` + `SecureStorageDeviceIdStore` (UUID aleatório criado na 1ª vez, chave `acs_device_id`) + `MemoryDeviceIdStore`.
  - `AcsBackend`: `Future<AuthSession?> resumeSession()` (tenta refresh com o token salvo; `null` se não há token ou foi recusado) e `Future<void> logout()`.
  - `BackendClient({String? host, List<int>? trustedCaBytes, RefreshTokenStore? tokenStore, DeviceIdStore? deviceIds})`.

- [ ] **Step 1: Estender o `FakeRpcServer`** — `refreshSession` devolve `{accessToken, tokenType, refreshToken: 'refresh-N'}` e conta chamadas; flags `rejectRefresh` (responde `SessionExpiredException`), `refreshDelay` (`Duration`, para provocar concorrência) e `failRefreshOnce` (derruba a conexão uma vez, simulando resposta perdida); `loginInstitutional` passa a devolver `refreshToken: 'refresh-0'`; `logout` responde 200 sem corpo e é registrado; expor `int get refreshCount`.

- [ ] **Step 2: Testes que falham** — `refresh_session_test.dart`:

```dart
test('JWT vencido é renovado por refresh, sem reenviar senha nem código', ...);
// server.tokenLifetime = -1 min → listPatients(); expect loginCount 1, refreshCount 1.

test('chamadas simultâneas com JWT vencido compartilham UM refresh (single-flight)', ...);
// server.refreshDelay = 200ms; Future.wait([listPatients(), listPatients(), listPatients()]);
// expect refreshCount == 1.

test('o refresh token rotativo é regravado a cada renovação', ...);
// MemoryRefreshTokenStore: após login = 'refresh-0'; após renovar = 'refresh-1'.

test('recusa do refresh (SessionExpiredException) limpa o token e chama onSessionExpired', ...);
// BackendFailure(isRecoverable: false), avisos == 1, store.read() == null.

test('falha de REDE no refresh é recuperável e NÃO apaga o token', ...);
// failRefreshOnce: 1ª chamada lança BackendFailure(isRecoverable: true);
// store ainda tem o token; a 2ª tentativa renova.

test('resumeSession: sem token salvo devolve null; com token, devolve sessão', ...);

test('logout revoga no servidor e apaga o token local, mesmo se o servidor estiver fora', ...);

test('a senha não é guardada: BackendClient não mantém credencial após o login', ...);
// renova com loginCount == 1 e sem reenviar `password` (inspecionar server.requests).

test('o deviceId enviado ao login e ao refresh é o mesmo e persiste entre instâncias', ...);
```

Ajustar `session_expiry_mfa_test.dart` (o comentário "Sem refresh token…" deixa de valer): agora o caso é "refresh recusado ⇒ `BackendFailure` não recuperável com a mensagem `Sua sessão expirou. Entre novamente com o código do autenticador.` e `onSessionExpired` chamado uma vez". Ajustar `session_reauth_test.dart` apenas onde ele dependia de `_credentials`.

- [ ] **Step 3: Rodar e ver falhar**

Run (em `apps/acs`): `flutter test test/refresh_session_test.dart`
Expected: FAIL (símbolos novos não existem).

- [ ] **Step 4: Implementar**

`refresh_token_store.dart` — espelhar `SecureStorageDatabaseKeyStore` (mesmas opções `AndroidOptions(encryptedSharedPreferences: true)` e `IOSOptions` `first_unlock_this_device`); **nunca** logar o valor.

`BackendClient`:
- Remover `_credentials` e o laço de `renewSession` por senha.
- `login(...)`: ler `result.refreshToken`; se vier, `await _tokenStore.write(...)`. Enviar `deviceId: await _deviceIds.readOrCreate()` em `loginInstitutional` (o parâmetro já existe no RPC).
- Renovação **single-flight**:

```dart
Future<AuthSession>? _renewal;

Future<AuthSession> renewSession() => _renewal ??= _doRenew().whenComplete(() => _renewal = null);

Future<AuthSession> _doRenew() async {
  final token = await _tokenStore.read();
  if (token == null) {
    _expire();
    throw const BackendFailure('Sua sessão expirou. Entre novamente.', isRecoverable: false);
  }
  try {
    final result = await _client.auth.refreshSession(
      refreshToken: token,
      deviceId: await _deviceIds.readOrCreate(),
    );
    final session = AuthSession.tryParse(result.accessToken, result.tokenType);
    final next = result.refreshToken;
    if (session == null || next == null) {
      throw const BackendFailure('O servidor devolveu um token que o aplicativo não entendeu.', isRecoverable: false);
    }
    await _tokenStore.write(next); // grava ANTES de expor a sessão: perder o filho = perder o turno
    return _session = session;
  } on SessionExpiredException {
    await _tokenStore.clear();
    _expire();
    throw const BackendFailure('Sua sessão expirou. Entre novamente com o código do autenticador.', isRecoverable: false);
  }
  // Erros de rede/timeout passam pelo `_guard` já existente como recuperáveis,
  // e NÃO apagam o token: a repetição cai na tolerância de 30 s do servidor.
}

void _expire() { _session = null; onSessionExpired?.call(); }
```

(o `try` real envolve a chamada com `_guard`, mantendo a tradução de exceções existente; `SessionExpiredException` deve ser tratada **antes** de `_guard` convertê-la.)
- `resumeSession()`: se `_tokenStore.read()` é `null` → `null`; senão `try { return await renewSession(); } on BackendFailure { return null; }` — **sem** chamar `onSessionExpired` (na partida a UI ainda é a tela de login; um parâmetro interno `notify: false` evita empilhar login sobre login).
- `logout()`: ler o token, `try { await _client.auth.logout(refreshToken: t) } catch (_) {}` (best-effort, o aparelho pode estar sem rede), depois `clear()` e `_session = null`.
- `MisconfiguredBackend`: `resumeSession` → `null`, `logout` → no-op.

- [ ] **Step 5: Rodar e ver passar**

Run: `flutter test test/refresh_session_test.dart test/session_expiry_mfa_test.dart test/session_reauth_test.dart test/backend_client_test.dart test/login_flow_test.dart test/mfa_login_test.dart && flutter analyze`
Expected: PASS; `flutter analyze` limpo. Depois `flutter test` (suíte inteira do ACS).

- [ ] **Step 6: Commit**

```bash
git add apps/acs
git commit -m "feat(acs): renovação silenciosa por refresh token no Keystore; app deixa de reter a senha"
```

---

## Parte B — Desbloqueio biométrico

### Task 6: Porta biométrica, manifesto e `AppLockGate`

**Files:**
- Modify: `apps/acs/pubspec.yaml` (dependência `local_auth: ^2.3.0` — conferir a versão compatível com o Flutter do `.fvmrc`/CI rodando `flutter pub add local_auth`)
- Modify: `apps/acs/android/app/src/main/AndroidManifest.xml` (`<uses-permission android:name="android.permission.USE_BIOMETRIC"/>`)
- Modify: `apps/acs/android/app/src/main/kotlin/br/com/prismrr/sinalacs/acs/MainActivity.kt` (`FlutterActivity` → `FlutterFragmentActivity`; **manter** o `FLAG_SECURE`)
- Modify: `apps/acs/test/android_manifest_test.dart`
- Create: `apps/acs/lib/core/security/biometric_gate.dart`
- Create: `apps/acs/lib/app/app_lock_gate.dart`
- Test: `apps/acs/test/app_lock_gate_test.dart`

**Interfaces:**
- Produces:

```dart
enum UnlockResult { unlocked, cancelled, unavailable, lockedOut }

abstract interface class BiometricGate {
  /// `true` se o aparelho tem biometria cadastrada OU bloqueio de tela seguro.
  Future<bool> get isAvailable;
  Future<UnlockResult> authenticate({required String reason});
}
```

  - `class AppLockGate extends StatefulWidget { AppLockGate({required BiometricGate gate, required Widget child, Duration lockAfter = const Duration(seconds: 30), DateTime Function()? clock, VoidCallback? onUsePassword}) }` — **sempre** mantém `child` montado (Stack), cobrindo-o quando bloqueado.

- [ ] **Step 1: Manifesto e atividade**

`android_manifest_test.dart` — acrescentar:

```dart
test('declara USE_BIOMETRIC para o desbloqueio por digital', () {
  expect(declares('USE_BIOMETRIC'), isTrue);
});
```

(e um teste que lê `MainActivity.kt` e exige `FlutterFragmentActivity` **e** `FLAG_SECURE` — o `local_auth` falha em tempo de execução com `FlutterActivity`, e o `FLAG_SECURE` não pode regredir.)

- [ ] **Step 2: Testes do gate que falham** — `app_lock_gate_test.dart` com `FakeBiometricGate` (resultado programável, contador de chamadas) e relógio injetado:

```dart
testWidgets('fica desbloqueado se voltar do segundo plano antes do prazo', ...);        // 10 s < 30 s
testWidgets('bloqueia ao voltar depois do prazo e mostra "Desbloquear com digital"', ...);
testWidgets('o filho continua MONTADO e com o mesmo estado enquanto bloqueado', ...);   // TextField com texto digitado sobrevive; Navigator não é recriado
testWidgets('desbloqueio bem-sucedido remove a cobertura', ...);
testWidgets('cancelamento mantém bloqueado, sem laço de prompts', ...);                 // authenticate chamado 1x por toque
testWidgets('lockedOut e unavailable oferecem "Entrar com senha" e NÃO desbloqueiam', ...);
testWidgets('a cobertura não expõe o conteúdo ao leitor de tela nem a toques', ...);    // ExcludeSemantics / AbsorbPointer no filho
testWidgets('abre o prompt sozinho ao bloquear (um toque a menos na rua)', ...);
testWidgets('app que nunca saiu do primeiro plano não bloqueia', ...);
```

- [ ] **Step 3: Rodar e ver falhar**

Run: `flutter test test/app_lock_gate_test.dart test/android_manifest_test.dart`
Expected: FAIL.

- [ ] **Step 4: Implementar**

`LocalAuthBiometricGate` sobre `LocalAuthentication`:
- `isAvailable` = `await auth.isDeviceSupported()` (cobre biometria **ou** PIN/padrão do aparelho — P5).
- `authenticate` = `auth.authenticate(localizedReason: reason, options: const AuthenticationOptions(biometricOnly: false, stickyAuth: true))`; mapear `LocalAuthException`/`PlatformException` de lockout (`LockedOut`, `PermanentlyLockedOut`) → `lockedOut`; `notAvailable`/`NotEnrolled` → `unavailable`; falso → `cancelled`. Nunca logar a causa com dado do usuário.

`AppLockGate` — `WidgetsBindingObserver`; ao `paused`/`hidden` guarda `_leftAt = clock()`; ao `resumed`, se `clock() - _leftAt >= lockAfter` → `_locked = true` e chama `_prompt()`. Build:

```dart
Stack(children: [
  ExcludeSemantics(excluding: _locked, child: IgnorePointer(ignoring: _locked, child: widget.child)),
  if (_locked) _LockCover(...), // opaca, Material, cobre tudo (inclusive rotas empilhadas — por isso o gate vai no `MaterialApp.builder`)
]);
```

`_LockCover`: ícone de digital, texto "Aplicativo bloqueado", botão **"Desbloquear"** (re-chama `authenticate`) e botão **"Entrar com senha"** (chama `onUsePassword`). Texto: "Alertas continuam chegando; eles estarão no painel ao desbloquear." (sem nenhum dado de paciente na cobertura). Alvos de toque ≥ 48 dp; cores pelos tokens `*OnSurface` (ver `apps/CLAUDE.md` e `test/contrast_tokens_test.dart`).

- [ ] **Step 5: Rodar e ver passar**

Run: `flutter test test/app_lock_gate_test.dart test/android_manifest_test.dart test/no_fixed_white_text_test.dart test/contrast_tokens_test.dart test/text_scale_test.dart && flutter analyze`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add apps/acs
git commit -m "feat(acs): bloqueio por inatividade com biometria acima do Navigator, sem destruir o painel"
```

---

### Task 7: Integração — retomada de sessão na partida, "Entrar com senha" e "Sair"

**Files:**
- Modify: `apps/acs/lib/app/app.dart` (`SinalAcsApp`, `_LoginScreenState`, `ThemeSettingsScreen`/aba Ajustes)
- Modify: `apps/acs/lib/main.dart` (injeção das fábricas reais)
- Test: `apps/acs/test/session_resume_test.dart` (novo); ajustar `test/session_reauth_test.dart` se o `MaterialApp.builder` mudar a árvore.

**Interfaces:**
- Consumes: `AcsBackend.resumeSession()`/`logout()` (Task 5), `BiometricGate` e `AppLockGate` (Task 6).
- Produces: `SinalAcsApp({..., BiometricGate? biometricGate})` (padrão `LocalAuthBiometricGate`; testes injetam o fake).

- [ ] **Step 1: Testes que falham** — `session_resume_test.dart`:

```dart
testWidgets('partida com refresh token salvo: digital OK → entra no painel sem digitar nada', ...);
testWidgets('partida com token salvo e digital cancelada → fica na tela de login completa', ...);
testWidgets('partida sem token salvo → tela de login normal, sem prompt biométrico', ...);
testWidgets('aparelho sem nenhum bloqueio de tela (unavailable) NÃO retoma a sessão salva (P5)', ...);
testWidgets('refresh recusado na partida → tela de login com aviso, token apagado', ...);
testWidgets('"Entrar com senha" do bloqueio leva ao login completo e preserva o painel por baixo', ...);
testWidgets('após login completo, o token novo substitui o salvo', ...);
testWidgets('"Sair" em Ajustes pede confirmação, chama logout e volta ao login', ...);
testWidgets('alerta vermelho recebido com o app BLOQUEADO está na fila ao desbloquear', ...);
// usa FakeAlertFeed já existente em test/support/fakes.dart: emite o alerta durante o bloqueio;
// após desbloquear, o card está no painel. É o teste do invariante "nunca descartar alerta".
testWidgets('retomada da sessão respeita a microárea devolvida pelo servidor', ...);
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `flutter test test/session_resume_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implementar**

1. `SinalAcsApp` recebe `biometricGate` e envolve a árvore **no `MaterialApp.builder`** (`builder: (context, child) => AppLockGate(gate: gate, onUsePassword: _usePassword, child: child!)`) — é isso que cobre rotas empilhadas (formulário de visita, reauth).
2. `_LoginScreenState.initState` → `_tryResume()` (só quando `widget.reauthUserId == null`, isto é, partida a frio):
   - `final backend = BackendScope.of(context)` (em `didChangeDependencies`, como o resto do arquivo);
   - `if (!await gate.isAvailable) return;` (P5);
   - se não há token salvo (`resumeSession` devolverá `null` sem rede; checar antes com `backend.hasStoredSession` — acrescentar o getter assíncrono em `AcsBackend` se necessário) → return, sem prompt;
   - `gate.authenticate(reason: 'Entrar no SinalACS')` → só se `unlocked`: `final s = await backend.resumeSession();` e, se `s?.microAreaId != null`, `pushReplacement` para `AcsHomeShell` com `acsId: s.userId`, exatamente como `_enter()` faz (extrair `_openShell(session)` para não duplicar).
   - qualquer outro caminho: permanece no formulário; se o refresh foi recusado, `_aviso = 'Sua sessão expirou. Entre novamente.'`.
3. `_usePassword` (do gate): `Navigator.push` da `LoginScreen` com `reauthUserId` = usuário atual — **reaproveita** o caminho de reautenticação empilhada que já existe e é provado por `session_reauth_test.dart`; ao concluir, o gate se desbloqueia.
4. "Sair": na aba Ajustes (`AcsDestination.settings`), abaixo do tema, um `FilledButton` "Sair e encerrar o turno" → diálogo de confirmação ("As visitas ainda não sincronizadas continuam salvas neste aparelho.") → `backend.logout()` → `pushAndRemoveUntil` para `LoginScreen`. **Não** apagar a fila de visitas nem o banco (offline-first: visita não sincronizada não se perde por sair).
5. `main.dart`: instanciar `LocalAuthBiometricGate()`, `SecureStorageRefreshTokenStore()` e `SecureStorageDeviceIdStore()` e passá-los ao `BackendClient`/`SinalAcsApp`.

- [ ] **Step 4: Rodar e ver passar**

Run: `flutter test && flutter analyze`
Expected: suíte inteira do ACS verde (158+ testes anteriores mais os novos); `flutter analyze` limpo.

- [ ] **Step 5: Commit**

```bash
git add apps/acs
git commit -m "feat(acs): retomada de sessão por digital na partida, 'Entrar com senha' e 'Sair'"
```

---

### Task 8: Prova no emulador, documentação e fechamento

**Files:**
- Modify: `apps/acs/integration_test/full_journey_e2e.dart` (e o script que o dispara — ver a skill `validacao-e2e`)
- Modify: `backend/CLAUDE.md`, `apps/CLAUDE.md`, `CLAUDE.md`, `PROGRESS.md`, `spec/lgpd_design.md` (linhas 669 e 709; §RT06), `spec/validation_report.md` só se o conferidor de contagem exigir (`scripts/qa/contagem_validation_report.py`)

- [ ] **Step 1: E2E no emulador (`emulator-5554`)** — estender o último teste do `full_journey_e2e` (MFA ligada pelo RPC):
  1. login completo com TOTP; 2. forçar o vencimento do JWT (esperar o TTL ou reduzir o TTL do servidor de e2e via `docker-compose.e2e.yml`, se já houver variável — senão aguardar os 15 min **uma vez** e registrar o tempo); 3. disparar `listPatients` e verificar que **não** apareceu a tela de reautenticação e que o servidor registrou `refresh_granted` em `audit_logs`; 4. `adb shell input keyevent KEYCODE_SLEEP`/`WAKEUP` após > 30 s e verificar a cobertura de bloqueio (a biometria real fica fora do e2e: usar `adb -e emu finger touch 1` com a digital cadastrada no emulador, ou o `FakeBiometricGate` injetado por `--dart-define` de teste — escolher o que o harness já permitir e **dizer no PROGRESS qual foi**).
  Run: `./scripts/qa/e2e.sh --emulator` (ver a skill `validacao-e2e` para o comando exato do full journey).
  Expected: jornada verde; a prova da biometria real fica declarada como feita no emulador, **não** em aparelho físico.

- [ ] **Step 2: Atualizar a documentação** — o que muda de verdade:
  - `backend/CLAUDE.md`: endpoints `auth.refreshSession`/`auth.logout`; a tabela `acs_refresh_tokens`; as constantes P1–P3; a frase "a renovação dele é silenciosa, por credencial em memória" some; a contagem "17 tables" do parágrafo de camadas é re-medida.
  - `apps/CLAUDE.md`: o app **não** retém mais a senha; refresh no Keystore; `AppLockGate`; `local_auth`; `FlutterFragmentActivity`.
  - `CLAUDE.md` (raiz): tirar "refresh token" de "Still missing" e acrescentar o desbloqueio biométrico em "Already delivered"; deixar claro que "reset de MFA pela coordenação" segue aberto.
  - `spec/lgpd_design.md` (linhas 669 e 709): marcar refresh token e biometria como implementados, com a ressalva de que a biometria é **portão de interface** (não liga a chave do SQLCipher nem a do refresh token ao `BiometricPrompt`).
  - `PROGRESS.md`: seção "Pendências do ACS" — refresh token e a consequência dos 15 minutos viram "fechado"; **abertos:** (a) biometria ligada ao Keystore (`setUserAuthenticationRequired`) em vez de portão de UI; (b) revogação de todas as famílias pelo coordenador / MFA reset; (c) limpeza periódica de `acs_refresh_tokens` (hoje só poda o próprio usuário no login); (d) iOS não existe; (e) refresh token do **paciente** (OTP segue em 1 h).
  - Apagar o item D6 ("refresh token… ficam fora") ou marcá-lo como superado.

- [ ] **Step 3: Rodar tudo que a CI roda para estes pacotes**

Run: `cd backend && dart analyze && cd sinalacs_server && dart test` ; `cd apps/acs && flutter analyze && flutter test` ; `./scripts/qa/ci_invariants.sh` ; `python3 scripts/qa/contagem_validation_report.py` (se falhar, corrigir a contagem que ele aponta).
Expected: tudo verde.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "docs(acs): fecha refresh token e desbloqueio biométrico; registra o que segue aberto"
```

---

## Auto-revisão

- **Cobertura da demanda:** refresh token (Tasks 1–5) → ACS não refaz matrícula/senha/código a cada 15 min; biometria para desbloqueio rápido e como camada contra roubo (Tasks 6–7); "Sair" e revogação (Tasks 2, 4, 7) completam a história do roubo.
- **Placeholders:** nenhum "TBD"; as duas notas ao executor (gerador de UUID já existente; versão do `local_auth`; mecanismo de digital no e2e) apontam para uma verificação concreta de 1 comando, não para decisão em aberto.
- **Consistência de tipos:** `RefreshTokenStore` (backend, Task 2) e `RefreshTokenStore` (app, Task 5) são interfaces **diferentes** em pacotes diferentes — se o executor preferir evitar confusão, renomear a do app para `SessionTokenStore` na Task 5 e atualizar os usos (`BackendClient`, `main.dart`, `MemoryRefreshTokenStore`). `deniedMessage`, `SessionExpiredException`, `refreshSession(refreshToken, deviceId)` e `logout(refreshToken)` têm a mesma forma nas Tasks 2, 4 e 5.
- **Risco assumido e declarado:** a biometria é portão de interface, não chave criptográfica; um aparelho com root pode lê-la fora do app. O ganho real contra o roubo vem do portão **mais** de o token estar no Keystore, ter janela ociosa de 2 h/teto de 8 h e poder ser revogado por "Sair" e pela detecção de reuso.
