# RF07 — Login Institucional do ACS (matrícula + senha) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Substituir o login de desenvolvimento do ACS por autenticação institucional real — matrícula (`acs.enrollmentId`) + senha verificada com Argon2id —, com bloqueio por tentativas, auditoria de cada tentativa e o app do ACS enviando de fato o que a pessoa digita.

**Architecture:** A senha nunca é armazenada: guarda-se um hash Argon2id com os parâmetros que o produziram, numa tabela `user_credentials` 1:1 com `users`, para que um aumento futuro de custo não invalide as credenciais antigas. A interface `PasswordHasher` vive em `application/` e a implementação Argon2id em `infrastructure/crypto/`, o mesmo arranjo de `AlertStore`/`OrmAlertStore` — `application/` decide *quando* verificar, `infrastructure/` sabe *como*. O novo endpoint `auth.loginInstitutional` passa por `Authorization` (plano anterior) e grava uma linha em `audit_logs` por tentativa, com a cadeia de hash já existente. O app ACS troca `login()` sem argumentos por `login(matricula, senha)` e passa a manter a credencial **apenas em memória** para a reautenticação silenciosa que ele já faz hoje quando o token de 15 minutos expira.

**Tech Stack:** Dart/Serverpod (`backend/sinalacs_server`), `package:cryptography` ^2.7.0 (**já é dependência** — Argon2id já vem nela, nenhum pacote novo), `package:postgres` para o seed Dart. Flutter (`apps/acs`).

**Spec:** `spec/PRD_system.md` linhas 140 (RF07 na matriz: "Auth própria no backend (hoje só existe login de desenvolvimento)") e 1009 (critério de MVP: "ACS loga com matrícula e senha"); `spec/lgpd_data_audit.md` linhas 185-197 (`users.cpfHash`/`birthDate` como credencial — contexto do RF01 vizinho) e linha 89 (`acs.enrollmentId` = "Identificável (Funcional)"); `spec/lgpd_design.md` linha 309 ("registro de tentativas de acesso") e §5.2 linha 495 (matriz de permissões); `spec/security_assessment.md` **F6** linhas 212-219 ("`AuthEndpoint.developmentLogin` não tem limite de tentativas nem throttling … tratar como pré-requisito de design da autenticação institucional") e **F1** linhas 111-129. Diagnóstico: `spec/validation_report.md` linha 75 (RF07 "ausente").

## Global Constraints

- **Nenhuma senha, em claro ou hasheada, entra em log, teste, seed versionado ou mensagem de erro.** O seed de desenvolvimento grava um hash calculado em tempo de execução a partir de `DEV_ACS_PASSWORD` (gerado por máquina) — nunca um hash literal no `.sql`, pelo mesmo motivo pelo qual `health-data-seed` existe: a lógica de KDF deve viver num lugar só e quebrar em silêncio é o pior modo de falha.
- **A resposta de erro é idêntica para matrícula inexistente e senha errada**, e o caminho da matrícula inexistente executa uma derivação descartada: sem isso, o tempo de resposta revela quais matrículas existem mesmo com a mensagem igual.
- **MFA/TOTP está fora deste plano, por decisão de escopo registrada em 2026-09-18.** `spec/lgpd_design.md` (LGPD-RF11 linha 177, LGPD-RT06 linha 661) e `spec/security_assessment.md` F5 linhas 200-210 exigem MFA para o ACS; o critério de MVP do PRD (linha 1009) pede "matrícula e senha". O conflito foi resolvido a favor do MVP, e a lacuna fica registrada na Task 7 — não silenciada.
- **TTL do token permanece 15 minutos, sem refresh token.** LGPD-RT06 pede 1h/8h com refresh rotativo; a divergência fica registrada na Task 7, também por decisão de escopo.
- **`ENABLE_DEV_LOGIN` continua existindo e não é tocado.** `auth.developmentLogin` segue como está: é o que as ferramentas (`tool/live_check.dart`) e os testes de integração dos apps usam. Este plano adiciona um caminho, não remove o outro.
- Mensagens, comentários e nomes de domínio em português, seguindo o repositório.
- Depois de qualquer `.spy.yaml` novo ou alterado: `cd backend/sinalacs_server && serverpod generate` e `serverpod create-migration` — **nunca** editar `lib/src/generated/` nem `migrations/` à mão.
- Antes de `dart test` de integração: `docker compose --profile test up -d postgres-test`.

---

## File Structure

- **Create** `backend/sinalacs_server/lib/src/application/auth/password_hasher.dart` — `PasswordDigest` + a interface `PasswordHasher`.
- **Create** `backend/sinalacs_server/lib/src/infrastructure/crypto/argon2_password_hasher.dart` — implementação Argon2id.
- **Create** `backend/sinalacs_server/lib/src/models/user_credential.spy.yaml` — tabela `user_credentials`.
- **Create** `backend/sinalacs_server/lib/src/models/exceptions/authentication_failed_exception.spy.yaml` — exceção única de recusa.
- **Create** `backend/sinalacs_server/lib/src/application/auth/institutional_auth_service.dart` — `AcsCredentialRecord`, `AcsCredentialStore`, `InstitutionalAuthService`.
- **Create** `backend/sinalacs_server/lib/src/infrastructure/database/orm_acs_credential_store.dart` — o ORM.
- **Create** `backend/sinalacs_server/bin/seed_acs_credentials.dart` — segunda metade do seed (o hash só existe em Dart).
- **Create** testes: `test/unit/argon2_password_hasher_test.dart`, `test/unit/institutional_auth_service_test.dart`, `test/integration/institutional_login_test.dart`.
- **Modify** `backend/sinalacs_server/lib/src/models/acs.spy.yaml` — índice único em `enrollmentId`.
- **Modify** `backend/sinalacs_server/lib/src/endpoints/auth_endpoint.dart` — método `loginInstitutional`.
- **Modify** `backend/sinalacs_server/lib/src/runtime/alert_runtime.dart` — `institutionalAuthServiceFor(session)` + a instância de `PasswordHasher`.
- **Modify** `backend/sinalacs_server/lib/src/config/app_config.dart` — nada de novo aqui **de propósito** (nenhum segredo novo: Argon2id não usa pepper).
- **Modify** `docker-compose.yml`, `scripts/dev/bootstrap_env.sh`, `.env.example` — o serviço de seed e `DEV_ACS_PASSWORD`.
- **Modify** `apps/acs/lib/core/network/backend_client.dart`, `apps/acs/lib/app/app.dart`, `apps/acs/test/support/fakes.dart`, `apps/acs/test/login_flow_test.dart`, `apps/acs/tool/live_check.dart`, `apps/acs/integration_test/red_alert_cycle_test.dart`.
- **Modify** `spec/validation_report.md`, `spec/security_assessment.md`, `apps/CLAUDE.md`, `backend/CLAUDE.md`.

**Depende de:** **nada** de `docs/superpowers/plans/2026-09-18-rbac-camada-autorizacao.md`. `auth.loginInstitutional` é público por definição (quem chama ainda não tem token), então não usa `Authorization` nem `AuthenticatedEndpoint`; e `AuthEndpoint` já está na allowlist de postura daquele plano, que não muda por acrescentar métodos a ele. Se aquele plano já tiver rodado, nada aqui conflita — o único arquivo em comum seria `auth_endpoint.dart`, e o plano de RBAC não o toca. `docs/superpowers/plans/2026-09-18-rf01-login-passwordless-otp.md` consome o **padrão** que este plano estabelece (KDF em `application/` + implementação em `infrastructure/`, seed Dart depois do `database-seed`, tradução de recusa de credencial no `_guard` do app) e é natural executá-lo em seguida, mas não há símbolo compartilhado entre os dois.

---

## Task 1: `PasswordHasher` (Argon2id)

**Files:**
- Create: `backend/sinalacs_server/lib/src/application/auth/password_hasher.dart`
- Create: `backend/sinalacs_server/lib/src/infrastructure/crypto/argon2_password_hasher.dart`
- Test: `backend/sinalacs_server/test/unit/argon2_password_hasher_test.dart`

**Interfaces:**
- Consumes: `package:cryptography` (já em `pubspec.yaml`, versão resolvida 2.9.0 — `Argon2id` existe nas duas).
- Produces:
  - `class PasswordDigest { final String hashBase64; final String saltBase64; final int memoryKb; final int iterations; final int parallelism; }`
  - `abstract interface class PasswordHasher { Future<PasswordDigest> derive(String password); Future<bool> matches(String password, PasswordDigest digest); }`
  - `class Argon2PasswordHasher implements PasswordHasher`

- [ ] **Step 1: Escrever o teste que falha**

Cria `backend/sinalacs_server/test/unit/argon2_password_hasher_test.dart`:

```dart
import 'package:sinalacs_server/src/application/auth/password_hasher.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/argon2_password_hasher.dart';
import 'package:test/test.dart';

void main() {
  // Parâmetros reduzidos para o teste não gastar ~19 MB e ~80 ms por
  // derivação: o que se prova aqui é o CONTRATO (salt por credencial,
  // verificação correta, parâmetros gravados junto do hash), não o custo, que
  // é uma constante declarada em Argon2PasswordHasher.recommended.
  final hasher = Argon2PasswordHasher(
    memoryKb: 512,
    iterations: 1,
    parallelism: 1,
  );

  test('aceita a senha correta', () async {
    final digest = await hasher.derive('senha-sintetica-de-teste');
    expect(await hasher.matches('senha-sintetica-de-teste', digest), isTrue);
  });

  test('recusa senha errada sem lançar', () async {
    final digest = await hasher.derive('senha-sintetica-de-teste');
    expect(await hasher.matches('outra-senha', digest), isFalse);
  });

  test('dois hashes da MESMA senha diferem (salt por credencial)', () async {
    final primeiro = await hasher.derive('senha-sintetica-de-teste');
    final segundo = await hasher.derive('senha-sintetica-de-teste');

    expect(primeiro.saltBase64, isNot(segundo.saltBase64));
    expect(primeiro.hashBase64, isNot(segundo.hashBase64));
  });

  test('grava os parâmetros que produziram o hash', () async {
    final digest = await hasher.derive('senha-sintetica-de-teste');

    // São eles que permitem subir o custo no futuro sem invalidar as
    // credenciais antigas: a verificação usa o que está gravado na linha, não
    // o que a configuração do processo diz hoje.
    expect(digest.memoryKb, 512);
    expect(digest.iterations, 1);
    expect(digest.parallelism, 1);
  });

  test('verifica com os parâmetros DA LINHA, não com os do processo', () async {
    final antigo = Argon2PasswordHasher(memoryKb: 512, iterations: 1, parallelism: 1);
    final digest = await antigo.derive('senha-sintetica-de-teste');

    // Um processo configurado com custo maior precisa continuar aceitando a
    // credencial gravada com o custo antigo — senão toda troca de parâmetro
    // tranca todos os ACS fora.
    final novo = Argon2PasswordHasher(memoryKb: 4096, iterations: 2, parallelism: 1);
    expect(await novo.matches('senha-sintetica-de-teste', digest), isTrue);
  });

  test('salt curto demais é recusado em vez de silenciosamente aceito', () async {
    const invalido = PasswordDigest(
      hashBase64: 'AAAA',
      saltBase64: '',
      memoryKb: 512,
      iterations: 1,
      parallelism: 1,
    );
    await expectLater(
      hasher.matches('qualquer', invalido),
      throwsA(isA<ArgumentError>()),
    );
  });
}
```

- [ ] **Step 2: Rodar o teste e confirmar que falha**

Run: `cd backend/sinalacs_server && dart test test/unit/argon2_password_hasher_test.dart`
Expected: FAIL — "Target of URI doesn't exist" para os dois arquivos de `lib/`.

- [ ] **Step 3: Escrever a interface**

Cria `backend/sinalacs_server/lib/src/application/auth/password_hasher.dart`:

```dart
/// Um hash de senha e os parâmetros que o produziram.
///
/// Os parâmetros viajam com o hash de propósito. Argon2id é caro por desenho, e
/// o custo recomendado sobe a cada ano; se a verificação usasse os parâmetros
/// da configuração do processo em vez dos gravados na linha, subir o custo
/// invalidaria toda credencial existente de uma vez — todos os ACS trancados
/// fora num deploy.
class PasswordDigest {
  const PasswordDigest({
    required this.hashBase64,
    required this.saltBase64,
    required this.memoryKb,
    required this.iterations,
    required this.parallelism,
  });

  final String hashBase64;
  final String saltBase64;

  /// Custo de memória em blocos de 1 kB (o `memory` do Argon2id).
  final int memoryKb;
  final int iterations;
  final int parallelism;
}

/// Derivação e verificação de senha.
///
/// Interface em `application/`, implementação em `infrastructure/` — mesmo
/// arranjo de `AlertStore`/`OrmAlertStore` (ver `backend/CLAUDE.md`). O serviço
/// de login decide *quando* verificar; a derivação em si é detalhe de
/// infraestrutura.
abstract interface class PasswordHasher {
  Future<PasswordDigest> derive(String password);

  /// `false` para senha errada. **Não lança** para credencial inválida: quem
  /// chama precisa distinguir "não confere" (conta com tentativa contada) de
  /// "a linha está corrompida" (erro de servidor), e uma exceção para o
  /// primeiro caso apagaria essa diferença.
  Future<bool> matches(String password, PasswordDigest digest);
}
```

- [ ] **Step 4: Escrever a implementação Argon2id**

Cria `backend/sinalacs_server/lib/src/infrastructure/crypto/argon2_password_hasher.dart`:

```dart
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:sinalacs_server/src/application/auth/password_hasher.dart';

/// Argon2id sobre `package:cryptography` — a mesma dependência que
/// `HealthDataCipher` já usa para AES-256-GCM, então verificação de senha não
/// acrescenta pacote nenhum ao backend.
///
/// Argon2id (e não PBKDF2) porque é resistente a ataque com GPU/ASIC: o custo
/// de memória é o que encarece a força bruta, e é justamente o que falta no
/// PBKDF2. `scrypt` também serviria; o pacote já instalado só oferece Argon2id
/// e PBKDF2, e entre os dois a escolha é Argon2id.
class Argon2PasswordHasher implements PasswordHasher {
  const Argon2PasswordHasher({
    this.memoryKb = recommendedMemoryKb,
    this.iterations = recommendedIterations,
    this.parallelism = recommendedParallelism,
  });

  /// 19 MiB × 2 iterações × 1 via — o piso recomendado pela OWASP para
  /// Argon2id. Não é um número medido nesta máquina: é o ponto de partida
  /// documentado, e subir é uma mudança de constante (as credenciais antigas
  /// continuam verificando, porque os parâmetros vivem na linha).
  static const recommendedMemoryKb = 19456;
  static const recommendedIterations = 2;
  static const recommendedParallelism = 1;

  static const _hashLength = 32;
  static const _saltLength = 16;

  /// Salt curto demais não protege contra rainbow table nem contra
  /// pré-computação entre credenciais. Recusar em vez de aceitar é o mesmo
  /// raciocínio de `HealthDataCipher._hexToBytes`.
  static const _minSaltLength = 8;

  final int memoryKb;
  final int iterations;
  final int parallelism;

  @override
  Future<PasswordDigest> derive(String password) async {
    final salt = _randomBytes(_saltLength);
    final hash = await _derive(password, salt, memoryKb: memoryKb, iterations: iterations, parallelism: parallelism);

    return PasswordDigest(
      hashBase64: base64.encode(hash),
      saltBase64: base64.encode(salt),
      memoryKb: memoryKb,
      iterations: iterations,
      parallelism: parallelism,
    );
  }

  @override
  Future<bool> matches(String password, PasswordDigest digest) async {
    final salt = base64.decode(digest.saltBase64);
    if (salt.length < _minSaltLength) {
      throw ArgumentError.value(
        salt.length,
        'digest.saltBase64',
        'salt precisa ter ao menos $_minSaltLength bytes',
      );
    }

    // Os parâmetros vêm DO DIGEST, nunca dos campos desta instância: é o que
    // permite aumentar o custo sem invalidar credencial antiga.
    final expected = base64.decode(digest.hashBase64);
    final actual = await _derive(
      password,
      salt,
      memoryKb: digest.memoryKb,
      iterations: digest.iterations,
      parallelism: digest.parallelism,
    );

    return _constantTimeEquals(expected, actual);
  }

  Future<Uint8List> _derive(
    String password,
    List<int> salt, {
    required int memoryKb,
    required int iterations,
    required int parallelism,
  }) async {
    final algorithm = Argon2id(
      parallelism: parallelism,
      memory: memoryKb,
      iterations: iterations,
      hashLength: _hashLength,
    );
    final key = await algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    return Uint8List.fromList(await key.extractBytes());
  }

  /// Comparação sem early-return: o tempo não pode depender de quantos bytes
  /// iniciais batem. Mesmo formato de `DevelopmentAuthService._matchesSignature`.
  bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var index = 0; index < a.length; index++) {
      difference |= a[index] ^ b[index];
    }
    return difference == 0;
  }

  Uint8List _randomBytes(int length) {
    final random = Random.secure();
    final bytes = Uint8List(length);
    for (var index = 0; index < length; index++) {
      bytes[index] = random.nextInt(256);
    }
    return bytes;
  }
}
```

- [ ] **Step 5: Rodar o teste e confirmar que passa**

Run: `cd backend/sinalacs_server && dart test test/unit/argon2_password_hasher_test.dart`
Expected: PASS — 6 testes.

- [ ] **Step 6: Commit**

```bash
git add backend/sinalacs_server/lib/src/application/auth/password_hasher.dart \
        backend/sinalacs_server/lib/src/infrastructure/crypto/argon2_password_hasher.dart \
        backend/sinalacs_server/test/unit/argon2_password_hasher_test.dart
git commit -m "feat(backend): Argon2id para senha institucional, com parâmetros gravados por credencial (RF07)

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

## Task 2: Modelo — `user_credentials` e matrícula única

**Files:**
- Create: `backend/sinalacs_server/lib/src/models/user_credential.spy.yaml`
- Create: `backend/sinalacs_server/lib/src/models/exceptions/authentication_failed_exception.spy.yaml`
- Modify: `backend/sinalacs_server/lib/src/models/acs.spy.yaml`

**Interfaces:**
- Produces: as classes geradas `UserCredential`, `AuthenticationFailedException` e o índice único `acs_enrollment_id_key`.

- [ ] **Step 1: Criar o modelo da credencial**

Cria `backend/sinalacs_server/lib/src/models/user_credential.spy.yaml`:

```yaml
### Credencial de login institucional (RF07). Uma linha por usuário, 1:1 com
### `users` — o `userId` tem índice único.
###
### Tabela própria em vez de colunas em `acs` por três motivos: a senha não é
### dado de domínio do ACS (um coordenador ou administrador passa a ter
### credencial sem que a tabela `acs` ganhe uma linha que não é dele), os
### parâmetros do Argon2id precisam viajar com o hash, e o contador de
### tentativas é estado de autenticação, não de territorialização.
class: UserCredential
table: user_credentials
fields:
  id: UuidValue?, defaultPersist=random
  userId: UuidValue, relation(parent=users)
  ### Argon2id em base64. **Nunca** a senha.
  passwordHash: String
  ### Salt por credencial, em base64. Guardado junto do hash porque a
  ### verificação precisa dele — e ao lado dos parâmetros, para que subir o
  ### custo não invalide as credenciais já emitidas.
  passwordSalt: String
  memoryKb: int
  iterations: int
  parallelism: int
  ### Estado do bloqueio por tentativas (achado F6). Zera no login bem-sucedido.
  failedAttempts: int
  ### `null` = não bloqueado.
  lockedUntil: DateTime?
  createdAt: DateTime
  updatedAt: DateTime
indexes:
  user_credentials_user_id_key:
    fields: userId
    unique: true
```

- [ ] **Step 2: Criar a exceção de recusa**

Cria `backend/sinalacs_server/lib/src/models/exceptions/authentication_failed_exception.spy.yaml`:

```yaml
### Credencial institucional recusada (RF07). Uma exceção única para matrícula
### inexistente, senha errada, conta bloqueada e acesso inativo — de propósito:
### distinguir "esta matrícula não existe" de "a senha está errada" entrega a
### quem sonda a lista de matrículas da unidade. O bloqueio e o inativo são
### distinguidos na MENSAGEM porque só chegam a quem já acertou a senha (o
### teste de inatividade acontece depois da verificação) ou já estourou o
### limite com a matrícula certa.
exception: AuthenticationFailedException
fields:
  message: String
```

- [ ] **Step 3: Tornar a matrícula única**

Em `backend/sinalacs_server/lib/src/models/acs.spy.yaml`, acrescente o índice:

```yaml
indexes:
  acs_ubs_idx:
    fields: ubsId
  ### O login institucional procura o ACS por `enrollmentId`. Sem unicidade, a
  ### matrícula deixaria de identificar uma pessoa: duas linhas com 'ACS-001' e
  ### o login passaria a escolher a primeira que o Postgres devolvesse.
  acs_enrollment_id_key:
    fields: enrollmentId
    unique: true
```

- [ ] **Step 4: Gerar e migrar**

```bash
cd backend/sinalacs_server
serverpod generate
serverpod create-migration
```

Expected: o gerador cria `lib/src/generated/user_credential.dart`, `authentication_failed_exception.dart`, atualiza `protocol.dart`/`client.dart` e cria um diretório novo em `migrations/`.

**Atenção:** se já existir mais de uma linha em `acs` com o mesmo `enrollmentId` em algum banco, a migração falha ao criar o índice único — é o comportamento desejado (melhor falhar no deploy do que ter login ambíguo), mas confira antes num banco com dados:

```bash
psql -h localhost -U sinalacs_user -d sinalacs_db -c \
  'SELECT "enrollmentId", count(*) FROM "acs" GROUP BY 1 HAVING count(*) > 1;'
```

Expected: zero linhas.

- [ ] **Step 5: Confirmar que o projeto ainda compila**

Run: `cd backend && dart analyze`
Expected: nenhum problema (nada usa as classes novas ainda).

- [ ] **Step 6: Commit**

```bash
git add backend/sinalacs_server/lib/src/models/ \
        backend/sinalacs_server/lib/src/generated/ \
        backend/sinalacs_server/migrations/ \
        backend/sinalacs_client/
git commit -m "feat(backend): modelo user_credentials, excecao de login e matricula unica (RF07)

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

## Task 3: `InstitutionalAuthService` — a política de login

**Files:**
- Create: `backend/sinalacs_server/lib/src/application/auth/institutional_auth_service.dart`
- Test: `backend/sinalacs_server/test/unit/institutional_auth_service_test.dart`

**Interfaces:**
- Consumes: `PasswordHasher`/`PasswordDigest` (Task 1); `AuthenticationFailedException` (Task 2); `AuditTrail`/`AuditEvent` (`application/audit/audit_trail.dart`); `AuthenticatedUser` (`application/auth/development_auth_service.dart`).
- Produces:
  - `class AcsCredentialRecord { final String acsId; final String? microAreaId; final bool active; final PasswordDigest digest; final int failedAttempts; final DateTime? lockedUntil; }`
  - `abstract interface class AcsCredentialStore { Future<AcsCredentialRecord?> findByEnrollmentId(String enrollmentId); Future<void> registerFailedAttempt(String acsId, {required int failedAttempts, required DateTime? lockedUntil}); Future<void> registerSuccessfulLogin(String acsId, DateTime at); Future<void> saveCredential(String acsId, PasswordDigest digest, DateTime at); }`
  - `class InstitutionalAuthService { InstitutionalAuthService({required AcsCredentialStore store, required PasswordHasher hasher, required AuditTrail audit}); Future<AuthenticatedUser> login({required String matricula, required String password, String? deviceId, DateTime? now}); }`

`saveCredential` entra já aqui porque a Task 5 (seed) e um futuro "trocar senha" precisam dele, e ele é a única operação de escrita da tabela.

- [ ] **Step 1: Escrever o teste que falha**

Cria `backend/sinalacs_server/test/unit/institutional_auth_service_test.dart`:

```dart
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/institutional_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/password_hasher.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/argon2_password_hasher.dart';
import 'package:test/test.dart';

const _acsId = '00000000-0000-4000-8000-000000000002';
const _microAreaId = '00000000-0000-4000-8000-000000000003';
const _senha = 'senha-sintetica-de-teste';

/// Store em memória: o serviço é o que está sob teste, não o Postgres.
class _FakeStore implements AcsCredentialStore {
  _FakeStore({this.record});

  AcsCredentialRecord? record;
  final fieldsWritten = <String, Object?>{};

  @override
  Future<AcsCredentialRecord?> findByEnrollmentId(String enrollmentId) async =>
      enrollmentId == 'ACS-001' ? record : null;

  @override
  Future<void> registerFailedAttempt(
    String acsId, {
    required int failedAttempts,
    required DateTime? lockedUntil,
  }) async {
    fieldsWritten['failedAttempts'] = failedAttempts;
    fieldsWritten['lockedUntil'] = lockedUntil;
    final current = record;
    if (current != null) {
      record = AcsCredentialRecord(
        acsId: current.acsId,
        microAreaId: current.microAreaId,
        active: current.active,
        digest: current.digest,
        failedAttempts: failedAttempts,
        lockedUntil: lockedUntil,
      );
    }
  }

  @override
  Future<void> registerSuccessfulLogin(String acsId, DateTime at) async {
    fieldsWritten['resetAt'] = at;
  }

  @override
  Future<void> saveCredential(String acsId, PasswordDigest digest, DateTime at) async {
    fieldsWritten['saved'] = true;
  }
}

// `extends`, não `implements`: `AuditTrail` é uma `abstract class` com o
// `recordSafely` concreto (herdado de propósito por todo implementador — ver o
// comentário dela). Todos os fakes do repositório usam `extends`
// (`visit_sync_service_test.dart:65`, `patient_directory_service_test.dart:34`,
// `triage_session_service_test.dart:49`, `audit_chain_test.dart:6`).
class _RecordingAudit extends AuditTrail {
  final events = <AuditEvent>[];

  @override
  Future<void> record(AuditEvent event) async => events.add(event);
}

void main() {
  final hasher = Argon2PasswordHasher(memoryKb: 512, iterations: 1, parallelism: 1);

  Future<InstitutionalAuthService> build({
    bool active = true,
    String? microAreaId = _microAreaId,
    int failedAttempts = 0,
    DateTime? lockedUntil,
  }) async {
    final digest = await hasher.derive(_senha);
    return InstitutionalAuthService(
      store: _FakeStore(
        record: AcsCredentialRecord(
          acsId: _acsId,
          microAreaId: microAreaId,
          active: active,
          digest: digest,
          failedAttempts: failedAttempts,
          lockedUntil: lockedUntil,
        ),
      ),
      hasher: hasher,
      audit: _RecordingAudit(),
    );
  }

  group('login institucional', () {
    test('aceita matrícula e senha corretas e devolve ACS territorializado', () async {
      final service = await build();

      final user = await service.login(matricula: 'ACS-001', password: _senha);

      expect(user.id, _acsId);
      expect(user.role, UserRole.acs);
      expect(user.microAreaId, _microAreaId);
    });

    test('ignora espaços em volta da matrícula', () async {
      final service = await build();
      final user = await service.login(matricula: '  ACS-001  ', password: _senha);
      expect(user.id, _acsId);
    });

    test('recusa matrícula inexistente com a MESMA exceção da senha errada', () async {
      final service = await build();

      // `try/catch` em vez de `Future.then(onError:)`: com o `then<Null>` que
      // `(_) => null` infere, um `onError` que devolve `Object` estoura em
      // runtime com "Invalid argument(s) (onError)" — o teste morre antes de
      // chegar às asserções.
      Object? capturar(Future<AuthenticatedUser> future) {
        return future.then<Object?>(
          (_) => null,
          onError: (Object error) => error,
        );
      }

      final inexistente = await capturar(
        service.login(matricula: 'ACS-999', password: _senha),
      );
      final senhaErrada = await capturar(
        service.login(matricula: 'ACS-001', password: 'outra'),
      );

      expect(inexistente, isA<AuthenticationFailedException>());
      expect(senhaErrada, isA<AuthenticationFailedException>());
      // A mensagem idêntica é o ponto: mensagens diferentes diriam quais
      // matrículas existem.
      expect(
        (inexistente! as AuthenticationFailedException).message,
        (senhaErrada! as AuthenticationFailedException).message,
      );
    });

    test('conta a tentativa errada sem bloquear antes do limite', () async {
      final service = await build(failedAttempts: 0);
      final store = service.store as _FakeStore;

      await expectLater(
        service.login(matricula: 'ACS-001', password: 'outra'),
        throwsA(isA<AuthenticationFailedException>()),
      );

      expect(store.fieldsWritten['failedAttempts'], 1);
      expect(store.fieldsWritten['lockedUntil'], isNull);
    });

    test('bloqueia ao atingir o limite de tentativas', () async {
      final service = await build(failedAttempts: 4);
      final store = service.store as _FakeStore;
      final agora = DateTime.utc(2026, 9, 18, 12);

      await expectLater(
        service.login(matricula: 'ACS-001', password: 'outra', now: agora),
        throwsA(isA<AuthenticationFailedException>()),
      );

      expect(store.fieldsWritten['failedAttempts'], 5);
      expect(
        store.fieldsWritten['lockedUntil'],
        agora.add(InstitutionalAuthService.lockDuration),
      );
    });

    test('recusa enquanto o bloqueio está ativo, sem recontar tentativa', () async {
      final agora = DateTime.utc(2026, 9, 18, 12);
      final service = await build(
        lockedUntil: agora.add(const Duration(minutes: 5)),
      );
      final store = service.store as _FakeStore;

      await expectLater(
        service.login(matricula: 'ACS-001', password: _senha, now: agora),
        throwsA(isA<AuthenticationFailedException>()),
      );

      // Nem senha certa passa durante o bloqueio, e a tentativa recusada por
      // bloqueio não estende o castigo.
      expect(store.fieldsWritten['failedAttempts'], isNull);
      expect(store.fieldsWritten['lockedUntil'], isNull);
    });

    test('aceita de novo depois de o bloqueio vencer', () async {
      final agora = DateTime.utc(2026, 9, 18, 12);
      final service = await build(
        lockedUntil: agora.subtract(const Duration(minutes: 1)),
      );

      final user = await service.login(
        matricula: 'ACS-001',
        password: _senha,
        now: agora,
      );

      expect(user.id, _acsId);
    });

    test('zera o contador no login bem-sucedido', () async {
      final service = await build(failedAttempts: 3);
      final store = service.store as _FakeStore;
      final agora = DateTime.utc(2026, 9, 18, 12);

      await service.login(matricula: 'ACS-001', password: _senha, now: agora);

      expect(store.fieldsWritten['resetAt'], agora);
    });

    test('recusa ACS inativo — e só depois de a senha conferir', () async {
      final service = await build(active: false);

      await expectLater(
        service.login(matricula: 'ACS-001', password: _senha),
        throwsA(
          isA<AuthenticationFailedException>().having(
            (error) => error.message,
            'message',
            contains('inativo'),
          ),
        ),
      );
    });

    test('recusa ACS sem microárea', () async {
      final service = await build(microAreaId: null);

      await expectLater(
        service.login(matricula: 'ACS-001', password: _senha),
        throwsA(isA<AuthenticationFailedException>()),
      );
    });

    test('recusa matrícula ou senha em branco sem tocar no banco', () async {
      final service = await build();
      final store = service.store as _FakeStore;

      await expectLater(
        service.login(matricula: '   ', password: _senha),
        throwsA(isA<AuthenticationFailedException>()),
      );

      expect(store.fieldsWritten, isEmpty);
    });

    test('marca o deviceId ausente em vez de inventar um', () async {
      final service = await build();
      final user = await service.login(matricula: 'ACS-001', password: _senha);

      // Mesma convenção de `orm_onboarding_store.dart`, que grava
      // 'nao-aplicavel-onboarding' em ipHash/userAgent: ausência explícita, e
      // não um valor fabricado que pareça medição.
      expect(user.deviceId, 'nao-aplicavel-login-institucional');
    });

    test('audita cada desfecho', () async {
      final service = await build();
      final audit = service.audit as _RecordingAudit;

      await service.login(matricula: 'ACS-001', password: _senha);
      await expectLater(
        service.login(matricula: 'ACS-001', password: 'outra'),
        throwsA(isA<AuthenticationFailedException>()),
      );

      expect(
        audit.events.map((event) => event.result).toList(),
        ['granted', 'denied_credentials'],
      );
      expect(audit.events.every((event) => event.resourceType == 'session'), isTrue);
    });
  });
}
```

O teste acessa `service.store` e `service.audit`: exponha os dois como campos `final` públicos no serviço (não privados), o que também documenta as dependências.

- [ ] **Step 2: Rodar o teste e confirmar que falha**

Run: `cd backend/sinalacs_server && dart test test/unit/institutional_auth_service_test.dart`
Expected: FAIL — URI de `institutional_auth_service.dart` não existe.

- [ ] **Step 3: Escrever o serviço**

Cria `backend/sinalacs_server/lib/src/application/auth/institutional_auth_service.dart`:

```dart
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/password_hasher.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// O que o login precisa saber sobre uma credencial, sem `application/`
/// conhecer o ORM.
class AcsCredentialRecord {
  const AcsCredentialRecord({
    required this.acsId,
    required this.microAreaId,
    required this.active,
    required this.digest,
    required this.failedAttempts,
    required this.lockedUntil,
  });

  final String acsId;

  /// `users.microAreaId` do ACS. `null` = não territorializado, e sem
  /// território não há fila (INV-01).
  final String? microAreaId;

  final bool active;
  final PasswordDigest digest;
  final int failedAttempts;
  final DateTime? lockedUntil;
}

/// Acesso à credencial do ACS e ao estado de bloqueio.
abstract interface class AcsCredentialStore {
  /// Credencial do ACS dono desta matrícula, ou `null` se não existir.
  Future<AcsCredentialRecord?> findByEnrollmentId(String enrollmentId);

  /// Grava a tentativa falha e o bloqueio resultante. A política (quantas
  /// tentativas, quanto tempo) é do serviço; o store só persiste.
  Future<void> registerFailedAttempt(
    String acsId, {
    required int failedAttempts,
    required DateTime? lockedUntil,
  });

  /// Zera o contador e o bloqueio depois de um login válido.
  Future<void> registerSuccessfulLogin(String acsId, DateTime at);

  /// Cria ou substitui a credencial (usado pelo seed e por uma futura troca de
  /// senha).
  Future<void> saveCredential(String acsId, PasswordDigest digest, DateTime at);
}

/// Login institucional do ACS (RF07): matrícula + senha.
///
/// Substitui `auth.developmentLogin` no caminho real. O que este serviço
/// garante, e que os testes verificam um a um:
///
/// 1. Matrícula inexistente e senha errada produzem a **mesma** exceção e a
///    **mesma** mensagem; o caminho da inexistente ainda deriva um hash
///    descartado, para o tempo de resposta não dizer o que a mensagem cala.
/// 2. A conta bloqueia depois de [maxFailedAttempts] falhas, por
///    [lockDuration] — a exigência de "registro de tentativas de acesso" de
///    `spec/lgpd_design.md` e o achado F6 de `spec/security_assessment.md`.
/// 3. Inatividade e ausência de território só são reveladas **depois** de a
///    senha conferir.
/// 4. Cada desfecho vira uma linha em `audit_logs` (RF17), pela mesma trilha
///    encadeada que os outros serviços usam.
class InstitutionalAuthService {
  InstitutionalAuthService({
    required this.store,
    required this.hasher,
    required this.audit,
  });

  final AcsCredentialStore store;
  final PasswordHasher hasher;
  final AuditTrail audit;

  static const maxFailedAttempts = 5;
  static const lockDuration = Duration(minutes: 15);

  /// Marcador de ausência de identificador de aparelho — mesma convenção de
  /// `orm_onboarding_store.dart` ('nao-aplicavel-onboarding').
  static const deviceIdAbsent = 'nao-aplicavel-login-institucional';

  static const _invalidCredentials = 'Matrícula ou senha inválidos.';

  Future<AuthenticatedUser> login({
    required String matricula,
    required String password,
    String? deviceId,
    DateTime? now,
  }) async {
    final enrollmentId = matricula.trim();
    if (enrollmentId.isEmpty || password.isEmpty) {
      throw AuthenticationFailedException(
        message: 'Informe matrícula e senha.',
      );
    }

    final at = (now ?? DateTime.now()).toUtc();
    final record = await store.findByEnrollmentId(enrollmentId);

    if (record == null) {
      // Derivação descartada de propósito: sem ela a resposta para uma
      // matrícula inexistente volta em microssegundos enquanto a de uma
      // matrícula real demora o tempo do Argon2id — o relógio entregaria a
      // lista de matrículas que a mensagem única existe para esconder.
      await hasher.derive(password);
      throw AuthenticationFailedException(message: _invalidCredentials);
    }

    final lockedUntil = record.lockedUntil;
    if (lockedUntil != null && lockedUntil.isAfter(at)) {
      await _recordAudit(record.acsId, 'denied_locked');
      throw AuthenticationFailedException(
        message: 'Acesso temporariamente bloqueado por tentativas inválidas. '
            'Tente novamente em alguns minutos.',
      );
    }

    if (!await hasher.matches(password, record.digest)) {
      // Bloqueio vencido zera o contador. Sem isto, uma única tentativa errada
      // depois de cada expiração tranca de novo por mais `lockDuration`: uma
      // conta pode ficar presa indefinidamente com **uma** tentativa por
      // janela — negação de serviço contra o acesso do ACS, e o ACS que só
      // errou a senha uma vez por dia nunca mais entra. O bloqueio é para
      // frear rajada, não para acumular para sempre.
      final lockExpirou = lockedUntil != null && !lockedUntil.isAfter(at);
      final attempts = lockExpirou ? 1 : record.failedAttempts + 1;
      await store.registerFailedAttempt(
        record.acsId,
        failedAttempts: attempts,
        lockedUntil:
            attempts >= maxFailedAttempts ? at.add(lockDuration) : null,
      );
      await _recordAudit(record.acsId, 'denied_credentials');
      throw AuthenticationFailedException(message: _invalidCredentials);
    }

    // Daqui para baixo a senha já conferiu: distinguir os motivos deixa de
    // entregar informação a quem sonda.
    if (!record.active) {
      await _recordAudit(record.acsId, 'denied_inactive');
      throw AuthenticationFailedException(message: 'Este acesso está inativo.');
    }

    final microAreaId = record.microAreaId;
    if (microAreaId == null) {
      await _recordAudit(record.acsId, 'denied_no_territory');
      throw AuthenticationFailedException(
        message: 'Este acesso não está vinculado a uma microárea.',
      );
    }

    await store.registerSuccessfulLogin(record.acsId, at);
    await _recordAudit(record.acsId, 'granted');

    return AuthenticatedUser(
      id: record.acsId,
      role: UserRole.acs,
      microAreaId: microAreaId,
      deviceId: deviceId ?? deviceIdAbsent,
    );
  }

  /// Best-effort, como toda auditoria deste repositório: uma trilha fora do ar
  /// não pode impedir um ACS de entrar.
  Future<void> _recordAudit(String userId, String result) => audit.recordSafely(
        AuditEvent(
          userId: userId,
          actionType: 'login',
          resourceType: 'session',
          result: result,
        ),
      );
}
```

- [ ] **Step 4: Rodar o teste e confirmar que passa**

Run: `cd backend/sinalacs_server && dart test test/unit/institutional_auth_service_test.dart`
Expected: PASS — 13 testes.

- [ ] **Step 5: Rodar a suíte inteira**

Run: `cd backend/sinalacs_server && dart test`
Expected: PASS — contagem anterior + 6 (Task 1) + 13.

- [ ] **Step 6: Commit**

```bash
git add backend/sinalacs_server/lib/src/application/auth/institutional_auth_service.dart \
        backend/sinalacs_server/test/unit/institutional_auth_service_test.dart
git commit -m "feat(backend): InstitutionalAuthService com bloqueio por tentativas e auditoria (RF07)

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

## Task 4: Store ORM, runtime e o endpoint `auth.loginInstitutional`

**Files:**
- Create: `backend/sinalacs_server/lib/src/infrastructure/database/orm_acs_credential_store.dart`
- Modify: `backend/sinalacs_server/lib/src/runtime/alert_runtime.dart`
- Modify: `backend/sinalacs_server/lib/src/endpoints/auth_endpoint.dart`
- Test: `backend/sinalacs_server/test/integration/institutional_login_test.dart`

**Interfaces:**
- Consumes: `AcsCredentialStore`, `InstitutionalAuthService` (Task 3); `Authorization`/`AuthenticatedEndpoint` (plano anterior — `AuthEndpoint` **não** estende a base, porque `developmentLogin` é público; ele usa `AuthenticationFailedException` direto).
- Produces: `AlertRuntime.instance.institutionalAuthServiceFor(session)` e `auth.loginInstitutional(matricula, password, deviceId?) → DevelopmentLoginResult`.

Reusa `DevelopmentLoginResult` (`accessToken`, `tokenType`) em vez de criar um DTO novo: o formato da resposta é idêntico e o app já sabe consumi-lo.

- [ ] **Step 1: Escrever o teste de integração que falha**

Cria `backend/sinalacs_server/test/integration/institutional_login_test.dart`:

```dart
import 'package:sinalacs_server/src/application/auth/institutional_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:serverpod/serverpod.dart';
import 'package:test/test.dart';

import 'test_tools/runtime_harness.dart';
import 'test_tools/serverpod_test_tools.dart';

/// Login institucional contra Postgres real: prova o JOIN
/// `acs.enrollmentId → acs.id → users.microAreaId → user_credentials` que o
/// teste unitário (com store falso) não alcança.
void main() {
  withServerpod('Dado o login institucional do ACS (RF07)', (
    sessionBuilder,
    endpoints,
  ) {
    const acsId = '00000000-0000-4000-8000-000000000002';
    const senha = 'senha-sintetica-de-teste';

    setUp(() async {
      final session = sessionBuilder.build();

      // O harness `withServerpod` aplica as MIGRAÇÕES, nunca o
      // `development.sql`: sem estas linhas, `ACS-001` não existe no banco de
      // teste e o JOIN não tem o que encontrar. Insere o mínimo que o caminho
      // exige — UBS, microárea, usuário ACS e a linha em `acs` —, com UUIDs
      // sintéticos próprios para não colidir com os de outros arquivos de
      // integração que rodam sob o mesmo banco.
      await AlertRuntimeHarness.seedAcs(session, acsId: acsId);

      // Mesma KDF de produção, com custo reduzido: o que se prova é o
      // caminho, não o custo.
      final digest = await AlertRuntimeHarness.hasher.derive(senha);
      await AlertRuntimeHarness.store(session).saveCredential(
            acsId,
            digest,
            DateTime.now().toUtc(),
          );
    });

    test('matrícula e senha corretas devolvem token de ACS', () async {
      // Endpoint recebe o próprio `sessionBuilder`; `sessionBuilder.build()` é
      // para acesso direto ao banco (ver `onboarding_endpoint_test.dart:236`).
      final result = await endpoints.auth.loginInstitutional(
        sessionBuilder,
        matricula: 'ACS-001',
        password: senha,
      );

      expect(result.accessToken, isNotEmpty);
      expect(result.tokenType, 'Bearer');

      final user = AlertRuntimeHarness.verify(result.accessToken);
      expect(user?.id, acsId);
      expect(user?.role, UserRole.acs);
    });

    test('senha errada é recusada pelo endpoint com a exceção tipada', () async {
      await expectLater(
        endpoints.auth.loginInstitutional(
          sessionBuilder,
          matricula: 'ACS-001',
          password: 'outra',
        ),
        throwsA(isA<AuthenticationFailedException>()),
      );
    });

    test('grava uma linha real em audit_logs', () async {
      final session = sessionBuilder.build();

      await expectLater(
        endpoints.auth.loginInstitutional(
          sessionBuilder,
          matricula: 'ACS-001',
          password: 'outra',
        ),
        throwsA(isA<AuthenticationFailedException>()),
      );

      final rows = await AuditLog.db.find(
        session,
        where: (table) =>
            table.resourceType.equals('session') & table.result.equals('denied_credentials'),
      );
      expect(rows, isNotEmpty);
    });
  });
}
```

**Nota sobre `AlertRuntimeHarness`:** o teste precisa (a) da mesma `PasswordHasher` de produção e (b) de `verifyToken`, que são singletons de processo. Em vez de criar um harness novo, adicione em `test/integration/test_tools/` um arquivo `runtime_harness.dart` com estes três atalhos, para que o teste acima compile:

```dart
import 'package:sinalacs_server/src/application/auth/password_hasher.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/argon2_password_hasher.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_acs_credential_store.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';
import 'package:serverpod/serverpod.dart';

/// Atalhos para os testes de integração alcançarem as peças de processo do
/// `AlertRuntime` sem duplicar a construção delas.
abstract final class AlertRuntimeHarness {
  /// Custo reduzido: a integração prova o caminho, não o custo do Argon2id.
  static final PasswordHasher hasher =
      const Argon2PasswordHasher(memoryKb: 512, iterations: 1, parallelism: 1);

  static AcsCredentialStore store(Session session) =>
      OrmAcsCredentialStore(session: () => session);

  static AuthenticatedUser? verify(String token) =>
      AlertRuntime.instance.auth.verifyToken(token);
}
```

- [ ] **Step 2: Rodar e confirmar que falha**

Run: `docker compose --profile test up -d postgres-test && cd backend/sinalacs_server && dart test test/integration/institutional_login_test.dart`
Expected: FAIL — `orm_acs_credential_store.dart` não existe.

- [ ] **Step 3: Escrever o store ORM**

Cria `backend/sinalacs_server/lib/src/infrastructure/database/orm_acs_credential_store.dart`:

```dart
import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/auth/institutional_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/password_hasher.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// Implementação sobre o ORM do Serverpod.
///
/// O `Session` é recebido por chamada (não guardado no construtor), o mesmo
/// arranjo de `OrmAlertStore`: o Serverpod amarra a conexão de banco à sessão
/// da requisição.
class OrmAcsCredentialStore implements AcsCredentialStore {
  OrmAcsCredentialStore({required Session Function() session}) : _session = session;

  final Session Function() _session;

  @override
  Future<AcsCredentialRecord?> findByEnrollmentId(String enrollmentId) async {
    final session = _session();

    // Duas consultas em vez de um JOIN escrito à mão: o ORM do Serverpod não
    // expressa junção, e a alternativa — SQL cru — passaria por fora dos
    // tipos gerados. A matrícula é única (índice `acs_enrollment_id_key`),
    // então a primeira consulta devolve no máximo uma linha.
    final acs = await Acs.db.findFirstRow(
      session,
      where: (table) => table.enrollmentId.equals(enrollmentId),
    );
    if (acs == null) return null;

    final credential = await UserCredential.db.findFirstRow(
      session,
      where: (table) => table.userId.equals(acs.id!),
    );
    if (credential == null) return null;

    final user = await User.db.findFirstRow(
      session,
      where: (table) => table.id.equals(acs.id!),
    );
    if (user == null) return null;

    return AcsCredentialRecord(
      acsId: acs.id!,
      microAreaId: user.microAreaId,
      active: acs.active,
      digest: PasswordDigest(
        hashBase64: credential.passwordHash,
        saltBase64: credential.passwordSalt,
        memoryKb: credential.memoryKb,
        iterations: credential.iterations,
        parallelism: credential.parallelism,
      ),
      failedAttempts: credential.failedAttempts,
      lockedUntil: credential.lockedUntil,
    );
  }

  @override
  Future<void> registerFailedAttempt(
    String acsId, {
    required int failedAttempts,
    required DateTime? lockedUntil,
  }) async {
    final session = _session();
    final credential = await UserCredential.db.findFirstRow(
      session,
      where: (table) => table.userId.equals(UuidValue.fromString(acsId)),
    );
    if (credential == null) return;

    credential.failedAttempts = failedAttempts;
    credential.lockedUntil = lockedUntil;
    credential.updatedAt = DateTime.now().toUtc();
    await UserCredential.db.updateRow(session, credential);
  }

  @override
  Future<void> registerSuccessfulLogin(String acsId, DateTime at) async {
    final session = _session();
    final credential = await UserCredential.db.findFirstRow(
      session,
      where: (table) => table.userId.equals(UuidValue.fromString(acsId)),
    );
    if (credential == null) return;

    credential.failedAttempts = 0;
    credential.lockedUntil = null;
    credential.updatedAt = at;
    await UserCredential.db.updateRow(session, credential);
  }

  @override
  Future<void> saveCredential(String acsId, PasswordDigest digest, DateTime at) async {
    final session = _session();
    final userId = UuidValue.fromString(acsId);

    final existing = await UserCredential.db.findFirstRow(
      session,
      where: (table) => table.userId.equals(userId),
    );

    if (existing == null) {
      await UserCredential.db.insertRow(
        session,
        UserCredential(
          userId: userId,
          passwordHash: digest.hashBase64,
          passwordSalt: digest.saltBase64,
          memoryKb: digest.memoryKb,
          iterations: digest.iterations,
          parallelism: digest.parallelism,
          failedAttempts: 0,
          lockedUntil: null,
          createdAt: at,
          updatedAt: at,
        ),
      );
      return;
    }

    existing
      ..passwordHash = digest.hashBase64
      ..passwordSalt = digest.saltBase64
      ..memoryKb = digest.memoryKb
      ..iterations = digest.iterations
      ..parallelism = digest.parallelism
      ..failedAttempts = 0
      ..lockedUntil = null
      ..updatedAt = at;
    await UserCredential.db.updateRow(session, existing);
  }
}
```

Confira os nomes exatos dos campos gerados em `lib/src/generated/user_credential.dart` antes de compilar (o Serverpod mantém os nomes do `.spy.yaml` em camelCase).

- [ ] **Step 4: Ligar no runtime**

Em `backend/sinalacs_server/lib/src/runtime/alert_runtime.dart`, adicione o import e o getter:

```dart
import 'package:sinalacs_server/src/application/auth/institutional_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/password_hasher.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/argon2_password_hasher.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_acs_credential_store.dart';
```

```dart
  /// Derivação de senha do login institucional (RF07). `const`, sem estado:
  /// os parâmetros de custo vivem em cada linha de `user_credentials`, não
  /// aqui — ver `PasswordDigest`.
  PasswordHasher get passwordHasher => const Argon2PasswordHasher();

  /// Serviço de login institucional para uma requisição.
  InstitutionalAuthService institutionalAuthServiceFor(Session session) =>
      InstitutionalAuthService(
        store: OrmAcsCredentialStore(session: () => session),
        hasher: passwordHasher,
        audit: auditTrailFor(session),
      );
```

- [ ] **Step 5: Adicionar o endpoint e registrar a postura pública do método novo**

Em `backend/sinalacs_server/lib/src/endpoints/auth_endpoint.dart`, acrescente o método na classe `AuthEndpoint`:

```dart
  /// Login institucional do ACS (RF07): matrícula + senha.
  ///
  /// Não é gated por `ENABLE_DEV_LOGIN` — é o caminho real, e o gate existe
  /// para o *outro* método. As recusas chegam ao app como
  /// `AuthenticationFailedException`, com a mensagem que o serviço escolheu:
  /// mensagem idêntica para matrícula inexistente e senha errada (ver
  /// `InstitutionalAuthService`).
  Future<DevelopmentLoginResult> loginInstitutional(
    Session session, {
    required String matricula,
    required String password,
    String? deviceId,
  }) async {
    final runtime = AlertRuntime.instance;

    final user = await runtime.institutionalAuthServiceFor(session).login(
          matricula: matricula,
          password: password,
          deviceId: deviceId,
        );

    return DevelopmentLoginResult(
      accessToken: runtime.auth.issueToken(user),
      tokenType: 'Bearer',
    );
  }
```

**E acrescente o método à allowlist do guard de postura.** O plano de RBAC (Task 4) entregou
`test/unit/endpoint_auth_posture_test.dart`, que agora exige que **todo método público que
recebe `Session session`** chame `authenticate(...)`/`authenticateToken(...)` ou conste de
`_publicMethodsByDesign` com o motivo. `loginInstitutional` é público por desenho — quem
chama ainda não tem token —, então sem esta entrada a suíte fica vermelha no primeiro
`dart test` depois do método novo:

```dart
  'AuthEndpoint.loginInstitutional':
      'login por desenho: quem chama ainda não tem sessão — matrícula e senha '
      'são a credencial',
```

Isso é o guard funcionando como projetado: acrescentar um método público a um endpoint
existente obriga a declarar a postura dele por escrito, em vez de deixá-la implícita. Rode
`cd backend/sinalacs_server && dart test test/unit/endpoint_auth_posture_test.dart` e
confirme que volta a passar.

Não esqueça de atualizar o comentário de classe de `AuthEndpoint`, que hoje diz "Acesso de desenvolvimento. **Não** é autenticação institucional." — passa a descrever as duas coisas:

```dart
/// Autenticação. `developmentLogin` é acesso de desenvolvimento e **não** é
/// autenticação institucional; `loginInstitutional` é o caminho real (RF07).
```

- [ ] **Step 6: Regenerar o cliente**

Adicionar um método a um endpoint **não** basta para o app enxergá-lo: o cliente
tipado carrega um stub por método (`backend/sinalacs_client/lib/src/protocol/client.dart:100`
é a classe `EndpointAuth`, com `developmentLogin` em `:106`), e ele só passa a existir
depois do gerador rodar. Sem este passo a Task 6 falha ao compilar em
`_client.auth.loginInstitutional(...)`, com um erro que aponta para o app e não para a
causa.

```bash
cd backend/sinalacs_server
serverpod generate
```

Expected: `sinalacs_client/lib/src/protocol/client.dart` ganha `loginInstitutional` na
classe `EndpointAuth`. Confirme com:

```bash
grep -n "loginInstitutional" ../sinalacs_client/lib/src/protocol/client.dart
```

Expected: uma ocorrência, dentro de `EndpointAuth`.

- [ ] **Step 7: Rodar os testes de integração e confirmar que passam**

Run: `cd backend/sinalacs_server && dart test test/integration/institutional_login_test.dart`
Expected: PASS — 3 testes.

- [ ] **Step 8: Rodar a suíte inteira**

Run: `cd backend/sinalacs_server && dart test`
Expected: PASS — contagem da Task 3 + 3.

- [ ] **Step 9: Commit**

```bash
git add backend/sinalacs_server/lib/src/infrastructure/database/orm_acs_credential_store.dart \
        backend/sinalacs_server/lib/src/runtime/alert_runtime.dart \
        backend/sinalacs_server/lib/src/endpoints/auth_endpoint.dart \
        backend/sinalacs_server/lib/src/generated/ \
        backend/sinalacs_client/ \
        backend/sinalacs_server/test/integration/
git commit -m "feat(backend): endpoint auth.loginInstitutional com store ORM (RF07)

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

## Task 5: Seed de desenvolvimento da credencial

**Files:**
- Create: `backend/sinalacs_server/bin/seed_acs_credentials.dart`
- Modify: `docker-compose.yml`
- Modify: `scripts/dev/bootstrap_env.sh`
- Modify: `.env.example`
- Modify: `backend/sinalacs_server/Dockerfile` (só se ele não copiar `bin/` — confira)

**Interfaces:**
- Consumes: `Argon2PasswordHasher` (Task 1), `OrmAcsCredentialStore` (Task 4).
- Produces: um serviço de compose `acs-credential-seed` que deixa o ACS do seed (`ACS-001`) capaz de logar com `DEV_ACS_PASSWORD` do `.env`.

Sem isto, a stack de desenvolvimento sobe com um ACS que **não consegue** entrar por `loginInstitutional` — e o login institucional seria impossível de exercitar à mão.

- [ ] **Step 1: Escrever o script**

Cria `backend/sinalacs_server/bin/seed_acs_credentials.dart`:

```dart
import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/argon2_password_hasher.dart';

/// Terceira metade do seed de desenvolvimento: a credencial institucional.
///
/// `seeds/development.sql` roda por `psql`, FORA do processo Dart, e por isso
/// não consegue derivar Argon2id — mesmo motivo de `bin/seed_health_data.dart`.
/// Colar um hash literal no `.sql` seria a alternativa, e foi rejeitada pelo
/// mesmo raciocínio: a lógica de KDF passaria a existir em dois lugares e
/// quebraria em silêncio a cada troca de parâmetro.
///
/// A senha vem de `DEV_ACS_PASSWORD`, gerada por máquina em
/// `scripts/dev/bootstrap_env.sh`. **Nunca** um literal versionado: uma senha
/// de desenvolvimento fixa no git é uma credencial pública.
Future<void> main(List<String> args) async {
  final env = Platform.environment;

  final appEnv = env['APP_ENV'] ?? 'development';
  if (appEnv != 'development') {
    stderr.writeln(
      'Recusando rodar: este script cria uma credencial de DESENVOLVIMENTO e '
      'APP_ENV=$appEnv. Ele nunca deve tocar um banco que não seja local.',
    );
    exit(2);
  }

  final password = env['DEV_ACS_PASSWORD'];
  if (password == null || password.isEmpty) {
    stderr.writeln(
      'DEV_ACS_PASSWORD não definida. Rode ./scripts/dev/bootstrap_env.sh para '
      'gerá-la no .env.',
    );
    exit(2);
  }

  const acsId = '00000000-0000-4000-8000-000000000002';
  final digest = await const Argon2PasswordHasher().derive(password);

  final connection = await Connection.open(
    Endpoint(
      host: env['SERVERPOD_DATABASE_HOST'] ?? 'localhost',
      port: int.parse(env['SERVERPOD_DATABASE_PORT'] ?? '5432'),
      database: env['SERVERPOD_DATABASE_NAME'] ?? 'sinalacs_db',
      username: env['SERVERPOD_DATABASE_USER'] ?? 'sinalacs_user',
      password: env['SERVERPOD_DATABASE_PASSWORD'],
    ),
    settings: ConnectionSettings(
      sslMode: env['SERVERPOD_DATABASE_REQUIRE_SSL'] == 'true'
          ? SslMode.require
          : SslMode.disable,
    ),
  );

  try {
    await connection.execute(
      Sql.named(
        'INSERT INTO "user_credentials" '
        '  ("userId", "passwordHash", "passwordSalt", "memoryKb", '
        '   "iterations", "parallelism", "failedAttempts", "createdAt", "updatedAt") '
        'VALUES (@userId, @hash, @salt, @memoryKb, @iterations, @parallelism, 0, NOW(), NOW()) '
        'ON CONFLICT ("userId") DO UPDATE SET '
        '  "passwordHash" = @hash, "passwordSalt" = @salt, '
        '  "memoryKb" = @memoryKb, "iterations" = @iterations, '
        '  "parallelism" = @parallelism, "failedAttempts" = 0, '
        '  "lockedUntil" = NULL, "updatedAt" = NOW()',
      ),
      parameters: {
        'userId': acsId,
        'hash': digest.hashBase64,
        'salt': digest.saltBase64,
        'memoryKb': digest.memoryKb,
        'iterations': digest.iterations,
        'parallelism': digest.parallelism,
      },
    );
    stdout.writeln(
      'Credencial de desenvolvimento do ACS ${acsId.substring(0, 8)}… gravada.',
    );
  } finally {
    await connection.close();
  }
}
```

Confirme que o `Dockerfile` compila também este entrypoint (o de `seed_health_data` virou o executável `./seed_health_data`). Se o Dockerfile compila alvos um a um, acrescente:

```dockerfile
RUN dart compile exe bin/seed_acs_credentials.dart -o seed_acs_credentials
```

Se ele já copia `bin/` inteiro, nada a fazer.

- [ ] **Step 2: Acrescentar o serviço ao compose**

Em `docker-compose.yml`, depois do `health-data-seed`, acrescente:

```yaml
  # Terceira metade do seed: a credencial institucional (RF07), que também só
  # existe em Dart (Argon2id não é expressão de Postgres). Roda depois do
  # database-seed, que é quem cria o usuário ACS referenciado.
  acs-credential-seed:
    image: sinalacs/server:local
    depends_on:
      database-seed:
        condition: service_completed_successfully
    environment:
      SERVERPOD_DATABASE_HOST: postgres
      SERVERPOD_DATABASE_PORT: "5432"
      SERVERPOD_DATABASE_NAME: ${POSTGRES_DB:-sinalacs_db}
      SERVERPOD_DATABASE_USER: ${POSTGRES_USER:-sinalacs_user}
      SERVERPOD_DATABASE_PASSWORD: ${POSTGRES_PASSWORD:?defina em .env — rode ./scripts/dev/bootstrap_env.sh}
      SERVERPOD_DATABASE_REQUIRE_SSL: "false"
      # Senha do ACS de desenvolvimento. Gerada por máquina — o script recusa
      # rodar fora de APP_ENV=development.
      DEV_ACS_PASSWORD: ${DEV_ACS_PASSWORD:?defina em .env — rode ./scripts/dev/bootstrap_env.sh}
      APP_ENV: ${APP_ENV:-development}
    entrypoint: ["./seed_acs_credentials"]
```

- [ ] **Step 3: Gerar a senha no bootstrap**

Em `scripts/dev/bootstrap_env.sh`, acrescente `DEV_ACS_PASSWORD="$(secret)" \` à lista que já contém `POSTGRES_PASSWORD`, `TEST_DATABASE_PASSWORD`, `MQTT_BACKEND_PASSWORD`, `MQTT_ACS_PASSWORD`, `JWT_SECRET`, `AUDIT_CHAIN_SECRET` e `HEALTH_DATA_ENCRYPTION_KEY` (linhas 63-69), e acrescente `DEV_ACS_PASSWORD` ao `echo` de confirmação (linha 84-86).

- [ ] **Step 4: Documentar no `.env.example`**

Acrescente o bloco, seguindo o estilo dos vizinhos:

```dotenv
# Senha do ACS de desenvolvimento (matrícula ACS-001), usada apenas pelo seed
# `acs-credential-seed` para gravar a credencial Argon2id no banco local. É uma
# credencial SINTÉTICA de desenvolvimento: gere com `openssl rand -hex 24`.
# O script de seed recusa rodar fora de APP_ENV=development.
DEV_ACS_PASSWORD=
```

- [ ] **Step 5: Verificar de ponta a ponta na stack**

```bash
./scripts/dev/bootstrap_env.sh
docker compose up --build -d
docker compose logs acs-credential-seed
```

Expected: `Credencial de desenvolvimento do ACS 00000000… gravada.` e exit 0.

Confirme que o login funciona de verdade, contra o servidor:

```bash
cd backend/sinalacs_server
curl -s -X POST http://localhost:8080/auth/loginInstitutional \
  -H 'Content-Type: application/json' \
  -d '{"matricula":"ACS-001","password":"'"$(grep '^DEV_ACS_PASSWORD=' ../../.env | cut -d= -f2-)"'"}'
```

Expected: JSON com `accessToken` não vazio. (Se a rota do método variar, use o caminho que o Serverpod gerou em `lib/src/generated/endpoints.dart` como referência — o Serverpod expõe os métodos por caminho derivado do nome do endpoint.)

- [ ] **Step 6: Commit**

```bash
git add backend/sinalacs_server/bin/seed_acs_credentials.dart \
        backend/sinalacs_server/Dockerfile \
        docker-compose.yml scripts/dev/bootstrap_env.sh .env.example
git commit -m "feat(dev): seed da credencial institucional do ACS (RF07)

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

## Task 6: App do ACS — enviar matrícula e senha de verdade

**Files:**
- Modify: `apps/acs/lib/core/network/backend_client.dart:30`, `:86-101`, `:75-82`
- Modify: `apps/acs/lib/app/app.dart:143-175`
- Modify: `apps/acs/test/support/fakes.dart:53`
- Modify: `apps/acs/test/login_flow_test.dart`
- Modify: `apps/acs/tool/live_check.dart:82`
- Modify: `apps/acs/integration_test/red_alert_cycle_test.dart` (7 chamadas a `backend.login()`)

**Interfaces:**
- Consumes: `auth.loginInstitutional` (Task 4) via `sinalacs_client`.
- Produces: `AcsBackend.login({required String matricula, required String senha}) → Future<AuthSession>`.

Hoje `_LoginScreenState` tem controllers de matrícula e senha (`app.dart:136-137`) e **descarta os dois** — o comentário no próprio arquivo admite que o formulário antes vinha preenchido com `'ACS-001'`/`'123456'` e o botão navegava sem olhar. Esta task liga o formulário ao backend.

- [ ] **Step 1: Trocar a assinatura na interface e na implementação**

Em `apps/acs/lib/core/network/backend_client.dart`, na interface `AcsBackend`:

```dart
  /// Autentica o ACS com matrícula e senha (RF07).
  ///
  /// A credencial fica **apenas em memória** — ver [_credentials] em
  /// [BackendClient] — para a reautenticação silenciosa que o app já fazia
  /// quando o token de 15 minutos expirava. Nada é gravado em disco.
  Future<AuthSession> login({required String matricula, required String senha});
```

Na implementação:

```dart
  /// Credencial em memória, para reautenticar quando o token de 15 min expira.
  ///
  /// **Só em memória, nunca em disco.** É o que preserva o comportamento que o
  /// app já tinha (reauth silencioso, que antes chamava `developmentLogin`) sem
  /// persistir senha nenhuma. A correção durável é o refresh token rotativo que
  /// `spec/lgpd_design.md` LGPD-RT06 exige e que este plano deliberadamente não
  /// implementa — ver a lacuna registrada no plano.
  ({String matricula, String senha})? _credentials;

  @override
  Future<AuthSession> login({
    required String matricula,
    required String senha,
  }) async {
    final result = await _guard(
      () => _client.auth.loginInstitutional(
        matricula: matricula,
        password: senha,
      ),
      permissionMessage: null,
      authenticationMessage: true,
    );

    final session = AuthSession.tryParse(result.accessToken, result.tokenType);
    if (session == null) {
      throw const BackendFailure(
        'O servidor devolveu um token que o aplicativo não entendeu.',
        isRecoverable: false,
      );
    }

    _credentials = (matricula: matricula, senha: senha);
    _session = session;
    return session;
  }

  /// Reautentica usando a credencial em memória.
  ///
  /// Sem credencial guardada não há como renovar: quem chama recebe uma falha
  /// não recuperável e a tela precisa mandar a pessoa entrar de novo.
  Future<AuthSession> renewSession() async {
    final credentials = _credentials;
    if (credentials == null) {
      throw const BackendFailure(
        'Sua sessão expirou. Entre novamente.',
        isRecoverable: false,
      );
    }
    return login(
      matricula: credentials.matricula,
      senha: credentials.senha,
    );
  }
```

E em `_requireToken` (linha 76), troque `await login();` por `await renewSession();`.

- [ ] **Step 2: Tratar a recusa de credencial no tradutor de falhas**

Em `_guard`, acrescente o parâmetro e o tratamento:

```dart
  Future<T> _guard<T>(
    Future<T> Function() call, {
    String? permissionMessage,
    bool authenticationMessage = false,
  }) async {
```

e, antes do `on AlertPermissionException`:

```dart
    } on AuthenticationFailedException catch (error) {
      // A mensagem vem do servidor de propósito: é ela que diferencia "senha
      // inválida" de "acesso bloqueado por tentativas" — e é igual para
      // matrícula inexistente e senha errada, para não revelar quais
      // matrículas existem.
      throw BackendFailure(error.message, isRecoverable: false);
    }
```

Remova o parâmetro `authenticationMessage` se ele não for usado — ele existe aqui só para deixar claro que a tradução de credencial é independente de `permissionMessage`; **não** deixe parâmetro morto no código final.

- [ ] **Step 3: Ligar o formulário**

Em `apps/acs/lib/app/app.dart`, no `_enter` (linha 143):

```dart
  /// Autentica contra `auth.loginInstitutional` (RF07) e só então abre o
  /// painel.
  Future<void> _enter() async {
    final matricula = _matricula.text.trim();
    final senha = _senha.text;
    if (matricula.isEmpty || senha.isEmpty) {
      setState(() {
        _busy = false;
        _error = 'Informe matrícula e senha.';
      });
      return;
    }

    setState(() { _busy = true; _error = null; });

    try {
      final session = await BackendScope.of(context).login(
        matricula: matricula,
        senha: senha,
      );
```

(o resto do bloco, do `microAreaId == null` em diante, fica igual — inclusive o `on BackendFailure catch (failure)` que já existe.)

Marque os campos com `autofillHints` para o gerenciador de senhas do Android funcionar, e `obscureText` na senha se ainda não estiver.

- [ ] **Step 4: Atualizar os chamadores**

`apps/acs/test/support/fakes.dart:53` — a implementação fake passa a registrar o que recebeu:

```dart
  ({String matricula, String senha})? lastCredentials;

  @override
  Future<AuthSession> login({
    required String matricula,
    required String senha,
  }) async {
    lastCredentials = (matricula: matricula, senha: senha);
    ...
  }
```

`apps/acs/tool/live_check.dart:82` e `apps/acs/integration_test/red_alert_cycle_test.dart` (7 sítios) — estas ferramentas rodam contra a stack de desenvolvimento com `ENABLE_DEV_LOGIN=true`. Em vez de embutir a senha do `.env` no código de teste, use `developmentLogin`, que continua existindo exatamente para isto:

```dart
// Em live_check.dart e nos integration_test, troque:
final session = await backend.login();
// por:
final session = await backend.developmentLogin(role: 'acs');
```

Para isso, acrescente à interface `AcsBackend` e ao `BackendClient` um método explícito de ferramenta, com o doc apontando o gate:

```dart
  /// Login de DESENVOLVIMENTO, para `tool/` e `integration_test/` contra a
  /// stack local. Só funciona com `ENABLE_DEV_LOGIN=true`; **não** é o caminho
  /// do produto (RF07 é [login]).
  Future<AuthSession> developmentLogin({required String role});
```

A implementação é a `login()` antiga, corpo inalterado.

- [ ] **Step 5: Ajustar o teste de widget**

Em `apps/acs/test/login_flow_test.dart`, o teste passa a digitar a credencial e a asseverar que ela chega ao backend:

```dart
  testWidgets('envia a matrícula e a senha digitadas', (tester) async {
    final backend = FakeAcsBackend(); // o fake de test/support/fakes.dart
    await tester.pumpWidget(/* mesma montagem já usada no arquivo */);

    await tester.enterText(find.byType(TextField).first, 'ACS-001');
    await tester.enterText(find.byType(TextField).last, 'senha-sintetica');
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();

    expect(backend.lastCredentials?.matricula, 'ACS-001');
    expect(backend.lastCredentials?.senha, 'senha-sintetica');
  });

  testWidgets('não chama o backend com campo em branco', (tester) async {
    // ... monta, deixa a senha vazia, toca em Entrar
    expect(backend.lastCredentials, isNull);
    expect(find.text('Informe matrícula e senha.'), findsOneWidget);
  });
```

Adapte os nomes (`FakeAcsBackend`) ao que o arquivo já usa — o fake existente está em `test/support/fakes.dart:53`.

- [ ] **Step 6: Rodar a suíte do app**

```bash
cd apps/acs && flutter analyze && flutter test
```

Expected: `flutter analyze` limpo; `flutter test` verde. Falhas pré-existentes em `encrypted_database_test.dart` por `libsqlite3.so` ausente neste ambiente Linux são conhecidas e não relacionadas (registrado em `spec/validation_report.md`).

- [ ] **Step 7: Commit**

```bash
git add apps/acs/
git commit -m "feat(acs): login institucional envia matricula e senha ao backend (RF07)

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

## Task 7: Sincronizar a documentação e registrar as lacunas

**Files:**
- Modify: `spec/validation_report.md` (linha 75 — RF07; linha 69 — RF01, para não deixar a impressão de que este plano o cobriu)
- Modify: `spec/security_assessment.md` (F6, linhas 212-219)
- Modify: `spec/lgpd_data_audit.md` — **tabela nova não classificada** (ver Step 5)
- Modify: `apps/CLAUDE.md` (a seção do app ACS, que hoje diz que `_enter` descarta os campos)
- Modify: `backend/CLAUDE.md` (a lista de endpoints)

- [ ] **Step 1: RF07 no relatório de validação**

Substitua a linha da tabela:

```markdown
| RF07 | Login institucional (matrícula/senha) | **backend + app** | `auth.loginInstitutional` verifica a senha com Argon2id contra `user_credentials`, bloqueia após 5 tentativas por 15 min (F6) e audita cada desfecho; o app ACS envia o que a pessoa digita. MFA/TOTP e refresh token seguem ausentes por decisão de escopo — ver `docs/superpowers/plans/2026-09-18-rf07-login-institucional-acs.md`. |
```

- [ ] **Step 2: F6 no security assessment**

Acrescente ao final do achado F6, preservando o diagnóstico original:

```markdown
**Estado atual (2026-09-18):** o rate limiting nasceu junto com a autenticação
institucional, como recomendado. `InstitutionalAuthService` conta tentativas
falhas por credencial e bloqueia por 15 minutos após 5
(`maxFailedAttempts`/`lockDuration`), grava cada desfecho em `audit_logs` e
responde com mensagem idêntica para matrícula inexistente e senha errada,
executando uma derivação descartada no caminho da inexistente para o tempo de
resposta não vazar o que a mensagem esconde. **Continua aberto:** o bloqueio é
por conta, não por origem — não há limite por IP, então um atacante com muitas
matrículas válidas distribui as tentativas. Limitar por IP exige o IP do
cliente, que o backend não coleta hoje. E uma varredura de matrículas
**inexistentes não deixa rastro em `audit_logs`**: `AuditEvent.userId` é
obrigatório e tem FK para `users`, então não há como auditar um sujeito que não
existe — o que `spec/lgpd_design.md` pede como "registro de tentativas de
acesso" fica atendido só para tentativas sobre contas reais. Fechar isso exige
ou um sujeito por origem (IP) ou uma trilha separada sem FK.
```

- [ ] **Step 3: Atualizar `apps/CLAUDE.md` e `backend/CLAUDE.md`**

Em `apps/CLAUDE.md`, a seção do ACS: onde hoje se lê que o app não tem autenticação institucional, registre que `_enter` envia matrícula e senha para `auth.loginInstitutional` e que a credencial vive apenas em memória para a renovação silenciosa — com o ponteiro para a lacuna de refresh token.

Em `backend/CLAUDE.md`, no parágrafo que lista os endpoints (linha 68), acrescente `auth.loginInstitutional` (matrícula + senha, Argon2id, bloqueio por tentativas, auditado) e a tabela `user_credentials`.

- [ ] **Step 5: Classificar `user_credentials` no inventário de LGPD**

`spec/lgpd_data_audit.md` §1 se declara um inventário campo a campo de **toda** tabela
persistida, e `user_credentials` guarda credencial — mas nenhuma task deste plano a
classificava. Achado do review da Task 2 (a tabela é a 12ª do domínio). Acrescente as
linhas à tabela do §1, no mesmo formato das vizinhas (`| tabela | campo | tipo |
classificação | descrição | observação |`):

```markdown
| **user_credentials** | `id` | `uuid` | Pseudonimizado | UUID da linha | — |
| | `userId` | `uuid` | Pseudonimizado | Chave estrangeira (`users.id`), única | Uma credencial por usuário. |
| | `passwordHash` | `text` | **Crítico** — credencial | Argon2id, base64, 32 bytes | Nunca a senha. Verificado por `Argon2PasswordHasher`; o parâmetro `salt` viaja ao lado. |
| | `passwordSalt` | `text` | Crítico — credencial | Salt por credencial, base64, 16 bytes | Impede pré-computação entre credenciais. |
| | `memoryKb` / `iterations` / `parallelism` | `bigint` | Metadado Técnico | Parâmetros do Argon2id vigentes na gravação | Gravados junto do hash para que subir o custo não invalide credencial antiga. |
| | `failedAttempts` | `bigint` | Metadado de Segurança | Tentativas falhas desde o último sucesso | Base do bloqueio (achado F6). |
| | `lockedUntil` | `timestamp without time zone` | Metadado de Segurança | Fim do bloqueio; `NULL` = não bloqueado | — |
| | `createdAt` / `updatedAt` | `timestamp without time zone` | Metadado Técnico | Timestamps | — |
```

E acrescente uma nota ao §2.5 ("Dados Cadastrais e Credenciais de Autenticação"), que hoje
cobre `users` e `patients`: registre que `user_credentials` é onde vive a credencial
institucional, que a senha nunca é armazenada — só o Argon2id com seus parâmetros — e que
o parecer de entropia do §2.1 **não** se aplica a ela, porque Argon2id é função de
derivação lenta e com custo de memória, ao contrário do SHA-256 sem salt que o §2.1
critica em `users.cpfHash`.

- [ ] **Step 6: Registrar as lacunas em PROGRESS.md**

Acrescente uma seção curta, com data, listando o que este plano **não** fez e por quê: MFA/TOTP (exigido por LGPD-RF11/LGPD-RT06, F5), refresh token rotativo e TTL de 1h/8h (LGPD-RT06), limite de tentativas por IP (F6), e troca de senha pelo próprio ACS.

- [ ] **Step 5: Rodar `graphify update` e commitar**

```bash
graphify update .
git add spec/ apps/CLAUDE.md backend/CLAUDE.md PROGRESS.md
git commit -m "docs: registrar RF07 implementado e as lacunas de MFA/refresh token

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

## Verificação final

- [ ] **Backend verde:** `cd backend/sinalacs_server && dart test` → `All tests passed!`.
- [ ] **Analisador limpo (backend e app):** `cd backend && dart analyze` e `cd apps/acs && flutter analyze`.
- [ ] **App verde:** `cd apps/acs && flutter test` (descontadas as falhas pré-existentes de SQLite neste ambiente).
- [ ] **Login real funciona na stack:** com `docker compose up --build`, o `acs-credential-seed` gravou a credencial e o `curl` da Task 5 devolveu `accessToken`.
- [ ] **Bloqueio observável:** cinco `loginInstitutional` com senha errada fazem o sexto responder "Acesso temporariamente bloqueado…", e o log do servidor mostra `denied_credentials` cinco vezes seguidas.
- [ ] **Nada de senha em disco:** `grep -rn "DEV_ACS_PASSWORD" apps/` → sem saída; `git log -p --all -S 'DEV_ACS_PASSWORD=' -- .env.example` → a variável aparece **vazia**, nunca com valor.

## Fora de escopo (registrado, não implementado)

- **MFA/TOTP para ACS** — exigido por `spec/lgpd_design.md` LGPD-RF11/LGPD-RT06 e pelo achado F5. Adiado em 2026-09-18: o critério de MVP do PRD pede "matrícula e senha", e não existe fluxo de enrollment de TOTP em nenhum app.
- **Refresh token rotativo e TTL de 1h/8h** — exigidos por LGPD-RT06, adiados na mesma decisão. Consequência prática: a sessão dura 15 minutos e a renovação depende da credencial mantida em memória.
- **Rate limiting por origem (IP)** — o bloqueio é por conta.
- **Troca de senha / recuperação** — não há fluxo; `saveCredential` existe para que o seed e um futuro fluxo possam usá-lo.
- **Refresh/expiração no app do paciente** — o app do paciente continua em `developmentLogin` até o plano de RF01.
