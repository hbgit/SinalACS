# Issue #75 — Colunas de risco em texto plano (INV-04) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fechar a lacuna P0 da issue #75 — cifrar em repouso as classificações de risco de `triage_sessions` e `visits`, eliminar o rótulo derivado `resultDisplay` e registrar (com teste que a sustenta) a decisão de manter `alerts.riskLevel` legível.

**Architecture:** A cifragem segue o padrão já existente da Track E: AES-256-GCM na borda do repositório ORM (`HealthDataCipher` + par `*Encrypted`/`*KeyVersion`), com `application/` trafegando sempre o valor em claro. Um codec único (`EncryptedRiskLevel`) serializa o risco com **largura fixa**, para que o tamanho do ciphertext não revele a classe. `alerts.riskLevel` fica em claro porque só existe um valor gravável (`red`) e a coluna é usada pelos predicados SQL que garantem a INV-03.

**Tech Stack:** Dart, Serverpod 2 (models `.spy.yaml`, `serverpod generate`, `serverpod create-migration`), PostgreSQL, pacote `cryptography` (AES-GCM, já usado), `package:test` com o harness `withServerpod`.

**Spec:** Issue #75 (`gh issue view 75`), origem `docs/auditoria-prd/2026-10-15-lacunas-prd.md` (item #1, linhas INV-04/RNF03/LGPD-RF09); `spec/PRD_system.md` §1.2 (INV-03, INV-04); `spec/lgpd_data_audit.md` §1 (`:50-51`, `:64-65`, `:82`) e §2.3; decisão §6 de `docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md` (cifra na aplicação, não `pgcrypto`).

## Verificação feita ao escrever o plano (2026-10-16, `develop` em `9c7bca6`)

A lacuna procede. Leitores e escritores das cinco colunas, medidos por `grep` em `backend/sinalacs_server/lib`:

| Coluna | Escrita | Leitura | Usada em SQL cru? | Decisão |
|---|---|---|---|---|
| `triage_sessions.resultRisk` | `OrmTriageSessionStore.insert` | `OrmPatientDataOverviewStore.loadFor` (histórico do "Meus Dados") | Não | **Cifrar** |
| `triage_sessions.resultDisplay` | `OrmTriageSessionStore.insert` (valor de `_displayFor(risk)`) | Ninguém | Não | **Remover** (dado derivado, minimização) |
| `visits.riskLevelBefore` / `riskLevelAfter` | `OrmVisitStore._toRow` | `OrmVisitStore._toRecord` (sync e `pull` do ACS) | Não | **Cifrar** |
| `alerts.riskLevel` | Só `OrmAlertStore.save`, que grava **sempre** `RiskLevel.red` (`orm_alert_store.dart:47`) | ORM e SQL cru | **Sim**: `alert_overdue_sql.dart:22`, `orm_alert_escalation_store.dart:93`, `orm_retention_store.dart:25,76,154`, `orm_admin_read_store.dart:54-60,160` | **Manter em claro e registrar a decisão** |

Por que `alerts.riskLevel` fica legível: (1) como todo alerta gravado é vermelho, a coluna não revela nada além do que a própria existência da linha em `alerts` já revela; (2) ela está nos predicados SQL que impedem o descarte de alerta vermelho pendente (INV-03: varredura de escalonamento e guarda do expurgo) — cifrá-la obrigaria a trazer esses filtros para a memória do processo, trocando uma invariante crítica por uma proteção nula. A decisão **cai** no dia em que algum caminho gravar alerta amarelo/verde; a Task 4 transforma essa condição num teste.

## Global Constraints

- Cifra só na borda do repositório ORM; `application/` nunca sabe de ciphertext (`backend/CLAUDE.md`, parágrafo "The three clinical columns are encrypted at the ORM boundary only").
- Serialização de valor cifrado passa por `EncryptedJson` (`lib/src/infrastructure/crypto/encrypted_json.dart`) — ponto único de mudança da rotação de chave.
- Nunca editar à mão `lib/src/generated/` nem `migrations/`: usar `serverpod generate` e `serverpod create-migration`.
- Ciphertext vazio (`''`) significa "linha nunca escrita pelo caminho Dart"; o JSON `null` cifrado significa "ausência real".
- Nunca dado real de paciente em teste, log ou fixture (LGPD); mensagens de erro e log só com identificadores sintéticos, nunca o risco nem o conteúdo clínico (VAZ-01).
- Classificação de risco é determinística (INV-02): nenhum caminho de leitura pode **inventar** um risco para preencher um valor ausente.
- Commits em português, no estilo `tipo(escopo): descrição` do repositório, **sem** `Co-Authored-By` nem menção a IA (`CLAUDE.md`).
- Trabalhar num branch a partir de `develop`: `git switch -c fix/issue-75-colunas-de-risco`.
- Testes de integração precisam do Postgres de teste em `localhost:9090` (`docker compose up -d postgres-test`; ver `backend/CLAUDE.md`, início) e rodam com `-j 1`. Os valores de `POSTGRES_USER`/`POSTGRES_DB` da pilha local valem `sinalacs_user`/`sinalacs_db` salvo override no `.env`.

## Review Focus

1. **Tamanho do ciphertext revelando a classe** — AES-GCM preserva o tamanho do texto claro; `"red"` cifrado sairia mais curto que `"yellow"`, e quem lê o Postgres separaria os vermelhos pelo comprimento do base64. Esperado: os três níveis e a ausência produzem ciphertexts do mesmo tamanho. Teste na Task 1.
2. **Visita gravada antes da migração (ciphertext de risco vazio)** — um `pg_data/` antigo fica com `riskLevelBeforeEncrypted = ''`. Esperado: o `pull` falha alto (`StateError` com só o id da visita), nunca devolve um risco inventado. Teste na Task 3.
3. **Triagem antiga sem risco cifrado no "Meus Dados"** — esperado: o painel abre e essa triagem fica fora do histórico, sem risco inventado e sem derrubar o painel inteiro. Teste na Task 2.
4. **`riskLevelAfter` nulo e depois preenchido na conclusão da visita** — esperado: o nulo faz ida e volta como nulo, e a atualização (versão 2) regrava o risco cifrado novo, que volta legível no `pull`. Teste na Task 3.
5. **Um novo escritor de `alerts` gravando amarelo/verde** — derrubaria a justificativa de `alerts.riskLevel` em claro sem ninguém perceber. Esperado: a suíte falha apontando a decisão. Teste na Task 4.

---

### Task 1: Codec de risco cifrado com largura fixa

**Files:**
- Create: `backend/sinalacs_server/lib/src/infrastructure/crypto/encrypted_risk_level.dart`
- Create: `backend/sinalacs_server/test/unit/encrypted_risk_level_test.dart`

**Interfaces:**
- Consumes: `HealthDataCipher` (`encrypt`, `decrypt`, `keyVersion`), extensão `EncryptedJson` (`encryptJson(Object?)`, `decryptJson(String, int) → Future<Object?>`), enum gerado `RiskLevel { red, yellow, green }`.
- Produces: extensão `EncryptedRiskLevel on HealthDataCipher` com
  - `Future<EncryptedValue> encryptRiskLevel(RiskLevel? risk)`
  - `Future<RiskLevel?> decryptRiskLevel(String ciphertextBase64, int keyVersion)` — `null` para ciphertext vazio **e** para ausência cifrada; nome desconhecido lança `ArgumentError`.

- [ ] **Step 1: Criar o branch**

```bash
cd /home/rock/Documents/Dev/APPs/SinalACS
git switch develop && git pull --ff-only
git switch -c fix/issue-75-colunas-de-risco
```

- [ ] **Step 2: Escrever o teste que falha**

`backend/sinalacs_server/test/unit/encrypted_risk_level_test.dart`:

```dart
import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/encrypted_json.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/encrypted_risk_level.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/health_data_cipher.dart';
import 'package:test/test.dart';

/// Codec do risco cifrado (issue #75, INV-04). Hermético: só a cifra, sem banco.
void main() {
  final cipher = HealthDataCipher(
    keyHex: AppConfig.developmentHealthDataEncryptionKey,
    keyVersion: 1,
  );

  test('cada nível e a ausência fazem ida e volta', () async {
    for (final risk in <RiskLevel?>[...RiskLevel.values, null]) {
      final encrypted = await cipher.encryptRiskLevel(risk);
      expect(
        await cipher.decryptRiskLevel(encrypted.ciphertextBase64, encrypted.keyVersion),
        risk,
        reason: 'ida e volta de $risk',
      );
    }
  });

  test('o tamanho do ciphertext não revela a classe: todos têm o mesmo '
      'comprimento, inclusive a ausência', () async {
    final lengths = {
      for (final risk in <RiskLevel?>[...RiskLevel.values, null])
        risk: (await cipher.encryptRiskLevel(risk)).ciphertextBase64.length,
    };
    expect(lengths.values.toSet(), hasLength(1), reason: 'comprimentos: $lengths');
  });

  test('o mesmo risco cifrado duas vezes dá ciphertexts diferentes (nonce '
      'aleatório: igualdade de coluna não agrupa pacientes por risco)', () async {
    final a = await cipher.encryptRiskLevel(RiskLevel.red);
    final b = await cipher.encryptRiskLevel(RiskLevel.red);
    expect(a.ciphertextBase64, isNot(b.ciphertextBase64));
  });

  test('ciphertext vazio (linha nunca escrita pelo caminho Dart) vira null', () async {
    expect(await cipher.decryptRiskLevel('', 1), isNull);
  });

  test('nome desconhecido lança em vez de inventar um risco (INV-02)', () async {
    final forjado = await cipher.encryptJson('purple');
    expect(
      () => cipher.decryptRiskLevel(forjado.ciphertextBase64, forjado.keyVersion),
      throwsArgumentError,
    );
  });
}
```

- [ ] **Step 3: Rodar e ver falhar**

Run: `cd backend/sinalacs_server && dart test test/unit/encrypted_risk_level_test.dart`
Expected: FAIL na compilação — `encrypted_risk_level.dart` não existe / `encryptRiskLevel` não definido.

- [ ] **Step 4: Implementar o codec**

`backend/sinalacs_server/lib/src/infrastructure/crypto/encrypted_risk_level.dart`:

```dart
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/encrypted_json.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/health_data_cipher.dart';

/// Cifra de uma classificação de risco em repouso (INV-04, issue #75).
///
/// O AES-GCM não esconde o TAMANHO do texto claro: `"red"` cifrado sairia
/// mais curto que `"yellow"`, e quem lê a coluna bruta separaria os vermelhos
/// pelo comprimento do base64. Por isso o nome vai preenchido com espaços até
/// a largura do maior nome de [RiskLevel], e a ausência (`null`, o
/// `riskLevelAfter` de uma visita ainda não concluída) vai como só espaços,
/// do mesmo tamanho.
///
/// Usada pelos stores ORM de triagem e de visita; vive em `infrastructure/`
/// pelo mesmo motivo de [EncryptedJson].
extension EncryptedRiskLevel on HealthDataCipher {
  static final int _width =
      RiskLevel.values.map((r) => r.name.length).reduce((a, b) => a > b ? a : b);

  Future<EncryptedValue> encryptRiskLevel(RiskLevel? risk) =>
      encryptJson((risk?.name ?? '').padRight(_width));

  /// `null` para ciphertext vazio (linha nunca escrita pelo caminho Dart) e
  /// para a ausência cifrada; quem chama decide se `null` é aceitável. Um
  /// nome desconhecido lança `ArgumentError` — nunca vira um risco inventado.
  Future<RiskLevel?> decryptRiskLevel(String ciphertextBase64, int keyVersion) async {
    final decoded = await decryptJson(ciphertextBase64, keyVersion);
    if (decoded == null) return null;
    final name = (decoded as String).trim();
    if (name.isEmpty) return null;
    return RiskLevel.values.byName(name);
  }
}
```

- [ ] **Step 5: Rodar e ver passar**

Run: `cd backend/sinalacs_server && dart test test/unit/encrypted_risk_level_test.dart && dart analyze lib/src/infrastructure/crypto test/unit/encrypted_risk_level_test.dart`
Expected: 5 testes PASS; `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add backend/sinalacs_server/lib/src/infrastructure/crypto/encrypted_risk_level.dart \
        backend/sinalacs_server/test/unit/encrypted_risk_level_test.dart
git commit -m "feat(backend): codec de risco cifrado com largura fixa (#75)"
```

---

### Task 2: `triage_sessions` — cifrar `resultRisk` e remover `resultDisplay`

**Files:**
- Modify: `backend/sinalacs_server/lib/src/models/triage_session.spy.yaml`
- Modify: `backend/sinalacs_server/lib/src/application/triage/triage_session_service.dart` (`TriageSessionRecord` linhas ~32-55, chamada linhas ~150-160, `_displayFor` linhas ~183-187)
- Modify: `backend/sinalacs_server/lib/src/infrastructure/database/orm_triage_session_store.dart:62-74`
- Modify: `backend/sinalacs_server/lib/src/infrastructure/database/orm_patient_data_overview_store.dart:79-84`
- Modify: `backend/sinalacs_server/test/support/health_data_fixtures.dart`
- Modify (testes que constroem `TriageSession`/`TriageSessionRecord`): `test/integration/health_data_encryption_test.dart`, `test/integration/patient_data_overview_endpoint_test.dart:108-117`, `test/integration/retention_expurge_test.dart:180-198`, `test/integration/data_subject_case_store_test.dart:255-265,493`, `test/integration/triage_session_persistence_test.dart:127-128,233`, `test/unit/triage_session_service_test.dart:118-119`
- Generated (por comando): `lib/src/generated/**`, `backend/sinalacs_client/lib/src/protocol/**`, `migrations/<novo>/`

**Interfaces:**
- Consumes: `encryptRiskLevel`/`decryptRiskLevel` (Task 1).
- Produces:
  - Modelo `TriageSession` com `resultRiskEncrypted: String` (default `''`) e `resultRiskKeyVersion: int` (default `1`); **sem** `resultRisk` nem `resultDisplay`.
  - `TriageSessionRecord` **sem** `resultDisplay` (continua com `resultRisk: RiskLevel`).
  - Fixtures de teste: `Future<EncryptedValue> encryptedRiskLevel(RiskLevel? risk)` e `Future<RiskLevel?> decryptedTriageRisk(TriageSession session)` em `test/support/health_data_fixtures.dart`.

- [ ] **Step 1: Escrever o teste que verifica a lacuna (e falha hoje)**

Em `test/integration/health_data_encryption_test.dart`, acrescentar depois de `_colunaBruta` (linha ~140):

```dart
/// A linha inteira como mapa coluna → valor, lida por SQL cru (#75). Mostra
/// TODAS as colunas, inclusive as que alguém acrescentar depois.
Future<Map<String, dynamic>> _linhaBruta(Session session, {required String table}) async {
  final rows = await session.db.unsafeQuery('SELECT row_to_json(t)::text FROM "$table" t;');
  expect(rows, hasLength(1), reason: 'o seed deve ter gravado exatamente 1 linha');
  return jsonDecode(rows.single.first as String) as Map<String, dynamic>;
}

/// Nenhuma coluna pode guardar a classificação legível — nem o nome do enum
/// nem o rótulo de tela. Igualdade, não substring: um base64 pode conter
/// "red" por acaso.
void _expectSemRiscoLegivel(Map<String, dynamic> linha) {
  const legiveis = {'red', 'yellow', 'green', 'Vermelho', 'Amarelo', 'Verde'};
  for (final entry in linha.entries) {
    expect(
      legiveis.contains('${entry.value}'.trim()),
      isFalse,
      reason: 'a coluna ${entry.key} guarda o risco em claro (INV-04, #75)',
    );
  }
}
```

E, dentro do mesmo `group`, depois do teste de `triage_sessions.answersEncrypted`:

```dart
    test('#75: nenhuma coluna de triage_sessions guarda a classificação de '
        'risco em claro', () async {
      final session = sessionBuilder.build();
      await _seed(session);

      final service = TriageSessionService(
        store: OrmTriageSessionStore(
          session: () => session,
          cipher: testHealthDataCipher(),
        ),
        audit: _SilentAuditTrail(),
      );
      final risco = await service.evaluateAndRecord(
        user: _paciente,
        chestPain: true,
        difficultyBreathing: false,
        fever: false,
        persistentVomiting: false,
        bleeding: false,
        severeWeakness: false,
      );
      expect(risco, RiskLevel.red);

      final linha = await _linhaBruta(session, table: 'triage_sessions');
      _expectSemRiscoLegivel(linha);
    });
```

- [ ] **Step 2: Rodar e confirmar que a lacuna existe**

Run: `cd backend/sinalacs_server && dart test test/integration/health_data_encryption_test.dart -j 1 -N '#75'`
Expected: FAIL com `a coluna resultRisk guarda o risco em claro (INV-04, #75)` — é a evidência da issue no código atual.

- [ ] **Step 3: Mudar o modelo**

`lib/src/models/triage_session.spy.yaml` — substituir as linhas `resultRisk: RiskLevel` e `resultDisplay: String` por:

```yaml
  ### Classificação do TriageEngine, cifrada (INV-04, #75): nome do RiskLevel
  ### com largura fixa, ver `encrypted_risk_level.dart`. O rótulo de tela
  ### (`resultDisplay`) deixou de ser persistido: era derivado do risco.
  resultRiskEncrypted: String, default=''
  resultRiskKeyVersion: int, default=1
```

E trocar o comentário do topo (linha 1) por:

```yaml
### Sessão de triagem estruturada. O risco é produzido pelo TriageEngine
```

Run: `cd backend/sinalacs_server && serverpod generate`
Expected: termina sem erro; `dart analyze` agora acusa os usos antigos de `resultRisk`/`resultDisplay` — são os passos seguintes.

- [ ] **Step 4: Tirar `resultDisplay` do serviço**

Em `lib/src/application/triage/triage_session_service.dart`:
- remover `required this.resultDisplay,` do construtor e `final String resultDisplay;` de `TriageSessionRecord`;
- remover a linha `resultDisplay: _displayFor(risk),` da construção do record (linha ~157);
- remover o método `static String _displayFor(RiskLevel risk) => switch (risk) { … };` (linhas ~183-187), que fica sem uso.

- [ ] **Step 5: Cifrar no store de gravação**

Em `lib/src/infrastructure/database/orm_triage_session_store.dart`, importar o codec:

```dart
import 'package:sinalacs_server/src/infrastructure/crypto/encrypted_risk_level.dart';
```

Em `insert`, cifrar o risco junto das respostas e passar ao `_insert`:

```dart
  @override
  Future<UuidValue?> insert(TriageSessionRecord session) async {
    final encrypted = await _cipher.encryptJson(
      [for (final answer in session.answers) answer.toJson()],
    );
    final risk = await _cipher.encryptRiskLevel(session.resultRisk);
    final db = _session();
    final external = _transaction;
    if (external != null) return _insert(db, external, session, encrypted, risk);
    return db.db.transaction((transaction) => _insert(db, transaction, session, encrypted, risk));
  }

  Future<UuidValue?> _insert(
    Session db,
    Transaction transaction,
    TriageSessionRecord session,
    EncryptedValue encrypted,
    EncryptedValue risk,
  ) async {
```

e, no `TriageSession(...)` do `_insert`, trocar `resultRisk:`/`resultDisplay:` por:

```dart
        resultRiskEncrypted: risk.ciphertextBase64,
        resultRiskKeyVersion: risk.keyVersion,
```

Atualizar o comentário da classe (linhas 15-19): "É aqui que as respostas e a classificação de risco da triagem viram ciphertext (RNF03, INV-04, #75) …".

- [ ] **Step 6: Decifrar no histórico do "Meus Dados"**

Em `lib/src/infrastructure/database/orm_patient_data_overview_store.dart`, importar `encrypted_risk_level.dart` e trocar o bloco `final riskHistory = <RiskEventSnapshot>[ … ]..sort(…);` por:

```dart
    final riskHistory = <RiskEventSnapshot>[];
    for (final row in triageRows) {
      // Ciphertext vazio = triagem gravada antes da migração da #75: sem risco
      // legível, a linha fica fora do histórico — nunca um risco inventado
      // (INV-02), e o painel do titular continua abrindo.
      final risk = await _cipher.decryptRiskLevel(
        row.resultRiskEncrypted,
        row.resultRiskKeyVersion,
      );
      if (risk == null) continue;
      riskHistory.add(
        RiskEventSnapshot(source: 'triage', riskLevel: risk, recordedAt: row.createdAt),
      );
    }
    for (final row in alertRows) {
      riskHistory.add(
        RiskEventSnapshot(source: 'alert', riskLevel: row.riskLevel, recordedAt: row.triggeredAt),
      );
    }
    riskHistory.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
```

- [ ] **Step 7: Fixtures de teste**

Em `test/support/health_data_fixtures.dart`, importar `package:sinalacs_server/src/infrastructure/crypto/encrypted_risk_level.dart` e acrescentar no fim:

```dart
/// Cifra uma classificação de risco do jeito que os stores gravam (#75).
Future<EncryptedValue> encryptedRiskLevel(RiskLevel? risk) =>
    testHealthDataCipher().encryptRiskLevel(risk);

/// Decifra o risco de uma sessão de triagem lida pelo ORM (#75).
Future<RiskLevel?> decryptedTriageRisk(TriageSession session) =>
    testHealthDataCipher().decryptRiskLevel(
      session.resultRiskEncrypted,
      session.resultRiskKeyVersion,
    );
```

- [ ] **Step 8: Ajustar os testes que montavam a linha em claro**

Cada `TriageSession(...)` de teste troca `resultRisk: X, resultDisplay: '…',` por um par cifrado. Padrão (exemplo de `patient_data_overview_endpoint_test.dart:108`):

```dart
  final riscoTriagem = await encryptedRiskLevel(RiskLevel.yellow);
  await TriageSession.db.insertRow(
    session,
    TriageSession(
      patientId: UuidValue.fromString(_patientId),
      resultRiskEncrypted: riscoTriagem.ciphertextBase64,
      resultRiskKeyVersion: riscoTriagem.keyVersion,
      createdAt: DateTime.utc(2026, 2, 1),
      deviceId: 'device-de-teste',
    ),
  );
```

Aplicar em:
- `test/integration/patient_data_overview_endpoint_test.dart` (seed, `RiskLevel.yellow`; importar `../support/health_data_fixtures.dart` se ainda não importa);
- `test/integration/data_subject_case_store_test.dart:255-265` (`RiskLevel.yellow`); na asserção da linha ~493 trocar `expect(triagens.single.resultRisk, RiskLevel.yellow);` por `expect(await decryptedTriageRisk(triagens.single), RiskLevel.yellow);` — prova que a anonimização (#42) mantém o risco para a estatística;
- `test/integration/retention_expurge_test.dart:180-198` — o expurgo não lê o risco: basta **remover** as linhas `resultRisk:`/`resultDisplay:` (o default `''` vale);
- `test/integration/triage_session_persistence_test.dart:127-128,233` — trocar `expect(gravadas.single.resultRisk, RiskLevel.red);` por `expect(await decryptedTriageRisk(gravadas.single), RiskLevel.red);` (idem `green` na 233) e apagar a asserção de `resultDisplay`;
- `test/unit/triage_session_service_test.dart:119` — apagar `expect(store.saved.single.resultDisplay, 'Vermelho');` (o `resultRisk` do record em claro continua).

Run: `cd backend/sinalacs_server && dart analyze`
Expected: `No issues found!` (se sobrar algum uso de `resultRisk`/`resultDisplay` em `test/`, ajustar pelo mesmo padrão).

- [ ] **Step 9: Ida e volta e triagem antiga no painel**

No teste `#75` do Step 1, acrescentar ao fim:

```dart
      expect(
        linha.containsKey('resultDisplay'),
        isFalse,
        reason: 'o rótulo derivado do risco não é mais persistido',
      );
      final gravada = await TriageSession.db.findFirstRow(session);
      expect(await decryptedTriageRisk(gravada!), RiskLevel.red);
```

Em `test/integration/patient_data_overview_endpoint_test.dart`, dentro do `withServerpod`, acrescentar:

```dart
    test('#75: triagem gravada antes da cifra do risco fica fora do histórico '
        'e o painel abre mesmo assim', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      // Linha "antiga": o default '' da coluna, como a migração deixa as
      // linhas que já existiam.
      await TriageSession.db.insertRow(
        session,
        TriageSession(
          patientId: UuidValue.fromString(_patientId),
          createdAt: DateTime.utc(2026, 4, 1),
          deviceId: 'device-de-teste',
        ),
      );
      final login = await endpoints.auth.developmentLogin(sessionBuilder, role: 'patient');

      final result = await endpoints.patients.myData(
        sessionBuilder,
        accessToken: login.accessToken,
      );

      expect(result.riskHistory, hasLength(2), reason: 'só as duas linhas do seed');
      expect(
        result.riskHistory.every((e) => e.recordedAt != DateTime.utc(2026, 4, 1)),
        isTrue,
      );
    });
```

- [ ] **Step 10: Gerar a migração**

Run: `cd backend/sinalacs_server && serverpod create-migration`
Expected: novo diretório em `migrations/` com `DROP COLUMN "resultRisk"`, `DROP COLUMN "resultDisplay"` e `ADD COLUMN "resultRiskEncrypted" text NOT NULL DEFAULT ''`/`"resultRiskKeyVersion" bigint NOT NULL DEFAULT 1` em `migration.sql`. Se o comando recusar por mudança destrutiva, rodar `serverpod create-migration --force` — o descarte é a mudança pretendida e fica documentado na Task 5.

- [ ] **Step 11: Rodar os testes tocados**

Run:
```bash
cd backend/sinalacs_server
dart test test/unit/triage_session_service_test.dart
dart test -j 1 test/integration/health_data_encryption_test.dart \
  test/integration/patient_data_overview_endpoint_test.dart \
  test/integration/data_subject_case_store_test.dart \
  test/integration/retention_expurge_test.dart \
  test/integration/triage_session_persistence_test.dart
```
Expected: tudo PASS, incluindo os dois testes `#75`.

- [ ] **Step 12: Commit**

```bash
git add backend/sinalacs_server backend/sinalacs_client
git commit -m "fix(backend): cifra o risco da triagem e deixa de gravar resultDisplay (#75)"
```

---

### Task 3: `visits` — cifrar `riskLevelBefore` e `riskLevelAfter`

**Files:**
- Modify: `backend/sinalacs_server/lib/src/models/visit.spy.yaml:19-20`
- Modify: `backend/sinalacs_server/lib/src/infrastructure/database/orm_visit_store.dart:44-64,119-167`
- Modify (testes que constroem `Visit` com risco): `test/integration/patient_directory_and_territory_test.dart:362-386`, `test/integration/visit_legacy_sync_test.dart:469-484`, `test/integration/retention_expurge_test.dart:153-177`, `test/integration/data_subject_case_store_test.dart:282-295`, `test/integration/admin_endpoint_accounts_test.dart:~320-335`, `test/integration/upload_token_test.dart:~125-140`, `test/integration/health_data_encryption_test.dart`
- Generated (por comando): `lib/src/generated/**`, `backend/sinalacs_client/lib/src/protocol/**`, `migrations/<novo>/`

**Interfaces:**
- Consumes: `encryptRiskLevel`/`decryptRiskLevel` (Task 1); fixtures `encryptedRiskLevel`, `encryptedVisitNotes`, `_linhaBruta`, `_expectSemRiscoLegivel` (Task 2).
- Produces: modelo `Visit` com `riskLevelBeforeEncrypted`/`riskLevelBeforeKeyVersion` e `riskLevelAfterEncrypted`/`riskLevelAfterKeyVersion` (defaults `''`/`1`); `VisitRecord` **não muda** (continua `riskLevelBefore: RiskLevel`, `riskLevelAfter: RiskLevel?`).

- [ ] **Step 1: Escrever o teste que verifica a lacuna (e falha hoje)**

Em `test/integration/health_data_encryption_test.dart`, no mesmo `group`, acrescentar:

```dart
    test('#75: nenhuma coluna de visits guarda a classificação de risco em '
        'claro', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final relogio = DateTime.utc(2026, 9, 17, 12);
      final service = VisitSyncService(
        store: OrmVisitStore(session: () => session, cipher: testHealthDataCipher()),
        audit: _SilentAuditTrail(),
        clock: () => relogio,
      );

      await service.sync(
        user: _acs,
        entries: [
          VisitSyncEntry(
            localId: _localId,
            patientId: _patientId,
            scheduledAt: DateTime.utc(2026, 9, 17, 9),
            completedAt: DateTime.utc(2026, 9, 17, 10),
            status: 'realizada',
            riskLevelBefore: RiskLevel.yellow,
            riskLevelAfter: RiskLevel.green,
            notes: const {},
            version: 1,
            arrivalMethod: ArrivalMethod.manual,
          ),
        ],
      );

      final linha = await _linhaBruta(session, table: 'visits');
      _expectSemRiscoLegivel(linha);
    });
```

- [ ] **Step 2: Rodar e confirmar que a lacuna existe**

Run: `cd backend/sinalacs_server && dart test test/integration/health_data_encryption_test.dart -j 1 -N 'visits guarda a classificação'`
Expected: FAIL com `a coluna riskLevelBefore guarda o risco em claro (INV-04, #75)`.

- [ ] **Step 3: Mudar o modelo**

`lib/src/models/visit.spy.yaml` — substituir `riskLevelBefore: RiskLevel` e `riskLevelAfter: RiskLevel?` por:

```yaml
  ### Risco antes e depois da visita, cifrados (INV-04, #75): nome do
  ### RiskLevel com largura fixa, ver `encrypted_risk_level.dart`. O "depois"
  ### ausente (visita não concluída) é cifrado também, com o mesmo tamanho.
  riskLevelBeforeEncrypted: String, default=''
  riskLevelBeforeKeyVersion: int, default=1
  riskLevelAfterEncrypted: String, default=''
  riskLevelAfterKeyVersion: int, default=1
```

Run: `cd backend/sinalacs_server && serverpod generate`

- [ ] **Step 4: Cifrar e decifrar no `OrmVisitStore`**

Importar `package:sinalacs_server/src/infrastructure/crypto/encrypted_risk_level.dart`. Trocar `insert`/`update` para repassar o record em claro inteiro:

```dart
  @override
  Future<VisitRecord> insert(VisitRecord visit) async {
    final row = await Visit.db.insertRow(
      _session(),
      await _toRow(visit),
      transaction: _transaction,
    );
    // Reaproveita o texto claro que o chamador já tem (notas e riscos):
    // decifrar de volta o que acabamos de cifrar seria ida e volta à toa.
    return _toRecord(row, plain: visit);
  }

  @override
  Future<VisitRecord> update(VisitRecord visit) async {
    final row = await Visit.db.updateRow(
      _session(),
      await _toRow(visit),
      transaction: _transaction,
    );
    return _toRecord(row, plain: visit);
  }
```

Em `_toRow`, cifrar os dois riscos e trocar as linhas `riskLevelBefore:`/`riskLevelAfter:` do `Visit(...)`:

```dart
  Future<Visit> _toRow(VisitRecord record) async {
    final encrypted = await _cipher.encryptJson(record.notes);
    final before = await _cipher.encryptRiskLevel(record.riskLevelBefore);
    final after = await _cipher.encryptRiskLevel(record.riskLevelAfter);
    return Visit(
      // … campos inalterados …
      riskLevelBeforeEncrypted: before.ciphertextBase64,
      riskLevelBeforeKeyVersion: before.keyVersion,
      riskLevelAfterEncrypted: after.ciphertextBase64,
      riskLevelAfterKeyVersion: after.keyVersion,
      notesEncrypted: encrypted.ciphertextBase64,
      // … campos inalterados …
    );
  }
```

Substituir `_toRecord` por:

```dart
  Future<VisitRecord> _toRecord(Visit row, {VisitRecord? plain}) async {
    final notes = plain?.notes ??
        ((await _cipher.decryptJson(row.notesEncrypted, row.notesKeyVersion))
                as Map<String, dynamic>?)
            ?.cast<String, String>() ??
        const <String, String>{};
    final before = plain?.riskLevelBefore ??
        await _cipher.decryptRiskLevel(
          row.riskLevelBeforeEncrypted,
          row.riskLevelBeforeKeyVersion,
        );
    // Ciphertext vazio = linha anterior à migração da #75 ou gravada fora
    // deste store. Falha alto: a fila do ACS não pode receber um risco
    // inventado (INV-02). Só o id sintético vai na mensagem (VAZ-01).
    if (before == null) {
      throw StateError('Visita ${row.id} sem riskLevelBefore cifrado (#75).');
    }
    final after = plain != null
        ? plain.riskLevelAfter
        : await _cipher.decryptRiskLevel(
            row.riskLevelAfterEncrypted,
            row.riskLevelAfterKeyVersion,
          );
    return VisitRecord(
      id: row.id,
      patientId: row.patientId,
      acsId: row.acsId,
      authorship: row.authorship,
      originDeviceId: row.originDeviceId,
      scheduledAt: row.scheduledAt,
      startedAt: row.startedAt,
      completedAt: row.completedAt,
      status: row.status,
      riskLevelBefore: before,
      riskLevelAfter: after,
      notes: notes,
      syncStatus: row.syncStatus,
      arrivalMethod: row.arrivalMethod,
      localId: row.localId,
      syncAt: row.syncAt,
      version: row.version,
    );
  }
```

Atualizar o comentário da classe (linhas 13-17): "É também a única fronteira que conhece a cifragem de `visits.notes` e dos riscos `riskLevelBefore`/`riskLevelAfter` (RNF03, INV-04, #75) …".

- [ ] **Step 5: Ajustar os testes que montavam `Visit` em claro**

Testes que **leem a visita de volta** (via `pull`/store) precisam do par cifrado. Padrão (exemplo de `patient_directory_and_territory_test.dart:362`):

```dart
      final notasVazias = await encryptedVisitNotes(const {});
      final riscoVerde = await encryptedRiskLevel(RiskLevel.green);

      Visit visita({…}) => Visit(
            // …
            riskLevelBeforeEncrypted: riscoVerde.ciphertextBase64,
            riskLevelBeforeKeyVersion: riscoVerde.keyVersion,
            riskLevelAfterEncrypted: riscoVerde.ciphertextBase64,
            riskLevelAfterKeyVersion: riscoVerde.keyVersion,
            notesEncrypted: notasVazias.ciphertextBase64,
            // …
          );
```

Aplicar em `patient_directory_and_territory_test.dart` (antes `green`/`green`) e `visit_legacy_sync_test.dart:469-484` (antes só `riskLevelBefore: RiskLevel.green` → só o par `Before`; o `After` fica no default `''`, que decifra como `null`, igual ao `riskLevelAfter` ausente de antes).

Testes que **só inserem** a visita (contagem, FK, expurgo, autoria) e nunca a leem pelo store: **remover** as linhas `riskLevelBefore:`/`riskLevelAfter:` — `retention_expurge_test.dart:153-177`, `data_subject_case_store_test.dart:282-295`, `admin_endpoint_accounts_test.dart` (~327), `upload_token_test.dart` (~132). Se `dart test` mostrar `StateError … sem riskLevelBefore cifrado` em algum deles, é porque o teste lê a visita: trocar pelo par cifrado do padrão acima.

Run: `cd backend/sinalacs_server && dart analyze`
Expected: `No issues found!`

- [ ] **Step 6: Ida e volta, `After` nulo e atualização na conclusão**

No teste `#75` de visitas do Step 1, acrescentar ao fim:

```dart
      final puxadas = await service.pull(
        user: _acs,
        since: relogio.subtract(const Duration(days: 1)),
      );
      expect(puxadas.single.riskLevelBefore, RiskLevel.yellow);
      expect(puxadas.single.riskLevelAfter, RiskLevel.green);
```

E acrescentar ao `group`:

```dart
    test('#75: riskLevelAfter nulo volta nulo e, na conclusão (versão 2), o '
        'risco novo é regravado cifrado', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      var relogio = DateTime.utc(2026, 9, 17, 12);
      final service = VisitSyncService(
        store: OrmVisitStore(session: () => session, cipher: testHealthDataCipher()),
        audit: _SilentAuditTrail(),
        clock: () => relogio,
      );
      VisitSyncEntry entrada({required int version, RiskLevel? depois, DateTime? fim}) =>
          VisitSyncEntry(
            localId: _localId,
            patientId: _patientId,
            scheduledAt: DateTime.utc(2026, 9, 17, 9),
            completedAt: fim,
            status: fim == null ? 'agendada' : 'realizada',
            riskLevelBefore: RiskLevel.red,
            riskLevelAfter: depois,
            notes: const {},
            version: version,
            arrivalMethod: ArrivalMethod.manual,
          );

      await service.sync(user: _acs, entries: [entrada(version: 1)]);
      var puxadas = await service.pull(
        user: _acs,
        since: relogio.subtract(const Duration(days: 1)),
      );
      expect(puxadas.single.riskLevelAfter, isNull);

      relogio = relogio.add(const Duration(hours: 1));
      final resultado = await service.sync(
        user: _acs,
        entries: [
          entrada(version: 2, depois: RiskLevel.yellow, fim: DateTime.utc(2026, 9, 17, 10)),
        ],
      );
      expect(resultado.single.syncStatus, SyncStatus.synced);
      _expectSemRiscoLegivel(await _linhaBruta(session, table: 'visits'));
      puxadas = await service.pull(
        user: _acs,
        since: relogio.subtract(const Duration(days: 1)),
      );
      expect(puxadas.single.riskLevelBefore, RiskLevel.red);
      expect(puxadas.single.riskLevelAfter, RiskLevel.yellow);
    });

    test('#75: visita sem risco cifrado (anterior à migração) faz o pull '
        'falhar alto, sem inventar risco', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final notas = await encryptedVisitNotes(const {});
      await Visit.db.insertRow(
        session,
        Visit(
          patientId: UuidValue.fromString(_patientId),
          acsId: UuidValue.fromString(_acsId),
          scheduledAt: DateTime.utc(2026, 9, 17, 9),
          status: 'realizada',
          notesEncrypted: notas.ciphertextBase64,
          notesKeyVersion: notas.keyVersion,
          syncStatus: SyncStatus.synced,
          localId: UuidValue.fromString(_localId),
          syncAt: DateTime.utc(2026, 9, 17, 11),
          version: 1,
        ),
      );
      final service = VisitSyncService(
        store: OrmVisitStore(session: () => session, cipher: testHealthDataCipher()),
        audit: _SilentAuditTrail(),
        clock: () => DateTime.utc(2026, 9, 17, 12),
      );

      expect(
        () => service.pull(user: _acs, since: DateTime.utc(2026, 9, 16)),
        throwsA(isA<StateError>()),
      );
    });
```

Se a versão 2 voltar `conflict` em vez de `synced`, ler a regra de versão em `VisitSyncService._syncOne` (`lib/src/application/visits/visit_sync_service.dart`, ~linha 500) e ajustar só a entrada do teste (versão/campos) para o caminho de atualização aceito — **não** mudar a regra de sincronização (`CLAUDE.md`: preservar semântica de retry/fila/conflito).

- [ ] **Step 7: Gerar a migração**

Run: `cd backend/sinalacs_server && serverpod create-migration` (com `--force` se recusar por mudança destrutiva, mesmo motivo da Task 2)
Expected: `migration.sql` com `DROP COLUMN "riskLevelBefore"`, `DROP COLUMN "riskLevelAfter"` e os quatro `ADD COLUMN` com default.

- [ ] **Step 8: Rodar os testes tocados**

Run:
```bash
cd backend/sinalacs_server
dart test test/unit/visit_sync_service_test.dart
dart test -j 1 test/integration/health_data_encryption_test.dart \
  test/integration/patient_directory_and_territory_test.dart \
  test/integration/visit_legacy_sync_test.dart \
  test/integration/retention_expurge_test.dart \
  test/integration/data_subject_case_store_test.dart \
  test/integration/admin_endpoint_accounts_test.dart \
  test/integration/upload_token_test.dart
```
Expected: tudo PASS.

- [ ] **Step 9: Commit**

```bash
git add backend/sinalacs_server backend/sinalacs_client
git commit -m "fix(backend): cifra o risco antes e depois da visita (#75)"
```

---

### Task 4: `alerts.riskLevel` — teste que sustenta a decisão de mantê-lo legível

**Files:**
- Modify: `backend/sinalacs_server/test/unit/red_alert_discard_paths_test.dart`

**Interfaces:**
- Consumes: o inventário de escritores `_allowedWriters` e `_grepSources` do mesmo arquivo (já existentes).
- Produces: nenhum símbolo novo; um teste que falha se algum `Alert(…)`/`copyWith(…)` em `lib/src` gravar `riskLevel` diferente de `RiskLevel.red`.

- [ ] **Step 1: Escrever o teste**

No `main()` de `test/unit/red_alert_discard_paths_test.dart`, junto dos testes de varredura do fonte, acrescentar:

```dart
  test('INV-04 (#75): todo alerta gravado é vermelho — é o que justifica '
      'alerts.riskLevel em claro (spec/lgpd_data_audit.md §2.3)', () {
    // `(?<!\w)Alert\(` pega o construtor do modelo de tabela e deixa de fora
    // AdminAlert/AlertStatusSnapshot; `copyWith` pega uma reclassificação.
    final pattern = RegExp(
      r'(?:(?<!\w)Alert\(|\.copyWith\()[^;]*?riskLevel:\s*([\w.]+)',
      dotAll: true,
    );
    final valores = <String>{};
    for (final entry in _grepSources(pattern).entries) {
      for (final hit in entry.value) {
        valores.add(pattern.firstMatch(hit)!.group(1)!);
      }
    }
    expect(valores, isNotEmpty, reason: 'a varredura precisa achar o save() do OrmAlertStore');
    expect(
      valores,
      {'RiskLevel.red'},
      reason: 'Se um alerta amarelo/verde passou a ser gravado, alerts.riskLevel '
          'deixou de ser igual à existência da linha: cifre a coluna ou '
          'revise a decisão da #75 antes de mudar este teste.',
    );
  });
```

Observação para quem implementa: `_grepSources` devolve o trecho casado com espaços colapsados; `pattern.firstMatch(hit)` reaplica o regex nesse trecho para extrair o grupo. Se `_grepSources` não aceitar um `RegExp` com `dotAll` (ele só repassa o `pattern`), o teste funciona como está — `dotAll` é necessário porque o `Alert(` e o `riskLevel:` ficam em linhas diferentes.

- [ ] **Step 2: Rodar e ver passar**

Run: `cd backend/sinalacs_server && dart test test/unit/red_alert_discard_paths_test.dart`
Expected: PASS (o único casamento é `RiskLevel.red`, de `orm_alert_store.dart`).

- [ ] **Step 3: Provar que o teste morde**

Trocar temporariamente `riskLevel: RiskLevel.red,` por `riskLevel: RiskLevel.yellow,` em `lib/src/infrastructure/database/orm_alert_store.dart:47` e rodar o mesmo comando.
Expected: FAIL com a `reason` acima. Desfazer a troca (`git checkout -- lib/src/infrastructure/database/orm_alert_store.dart`) e rodar de novo: PASS.

- [ ] **Step 4: Commit**

```bash
git add backend/sinalacs_server/test/unit/red_alert_discard_paths_test.dart
git commit -m "test(backend): amarra alerts.riskLevel em claro a só gravar vermelho (#75)"
```

---

### Task 5: Documentação da decisão e do descarte de dados

**Files:**
- Modify: `spec/PRD_system.md:54` (linha da INV-04)
- Modify: `spec/lgpd_data_audit.md` (§1 linhas ~50-51, ~64-65, ~82; §2.3)
- Modify: `backend/CLAUDE.md` (parágrafo "The three clinical columns are encrypted at the ORM boundary only", ~linha 85)
- Modify: `CLAUDE.md` (parágrafo "Updating an existing `pg_data/` to this branch loses dev clinical data silently")
- Modify: `PROGRESS.md` (nova seção)
- Modify: `docs/auditoria-prd/2026-10-15-lacunas-prd.md` (linhas INV-04 ~75, RNF03 ~106, LGPD-RF09 ~144, item #1 ~228)

**Interfaces:**
- Consumes: os nomes de coluna das Tasks 2-3 e os ids das duas migrações geradas (`ls backend/sinalacs_server/migrations | tail -3`).
- Produces: nada de código.

- [ ] **Step 1: PRD — INV-04**

Na tabela de §1.2, substituir a terceira célula da linha **INV-04** por:

```markdown
Criptografia AES-256 em `sqflite` e PostgreSQL. **Exceção registrada (#75, 2026-10-16):** `alerts.riskLevel` fica legível — todo alerta gravado é vermelho (a coluna não diz nada além da existência da linha) e ela sustenta os predicados SQL da INV-03; ver `spec/lgpd_data_audit.md` §2.3
```

- [ ] **Step 2: Auditoria LGPD**

Em `spec/lgpd_data_audit.md` §1:
- trocar as linhas `resultRisk` e `resultDisplay` de `triage_sessions` por uma linha só:
  `| | `resultRiskEncrypted` + `resultRiskKeyVersion` | `text` (ciphertext) + `bigint` | Sensível (Saúde - Art. 5º, II) | **Cifrado em repouso (AES-256-GCM, aplicação)** — ver §2.3 | **Atualizado (2026-10-16, #75):** nome do `RiskLevel` com largura fixa (o tamanho do ciphertext não revela a classe), cifrado em `OrmTriageSessionStore` e decifrado só no histórico do "Meus Dados". `resultDisplay` deixou de existir: era o rótulo derivado do risco (minimização). |`
- trocar as linhas `riskLevelBefore`/`riskLevelAfter` de `visits` por:
  `| | `riskLevelBeforeEncrypted`/`riskLevelAfterEncrypted` + `*KeyVersion` | `text` (ciphertext) + `bigint` | Sensível (Saúde - Art. 5º, II) | **Cifrado em repouso (AES-256-GCM, aplicação)** — ver §2.3 | **Atualizado (2026-10-16, #75):** mesmo codec de largura fixa; o "depois" ausente também é cifrado, com o mesmo tamanho. Linha sem risco cifrado faz o `pull` falhar alto em vez de inventar risco. |`
- na linha `riskLevel` de `alerts` (~82), acrescentar à última célula: ` **Decisão (2026-10-16, #75): permanece em texto plano** — só `red` é gravado (teste `INV-04 (#75)` em `test/unit/red_alert_discard_paths_test.dart`), e a coluna é usada nos predicados SQL de escalonamento, guarda do expurgo e indicadores (INV-03). Se alerta não vermelho passar a existir, cifrar.`

Em §2.3, acrescentar um parágrafo ao fim:

```markdown
**Classificações de risco (2026-10-16, issue #75).** `triage_sessions.resultRisk` e `visits.riskLevelBefore`/`riskLevelAfter` passaram ao mesmo padrão (`*Encrypted`/`*KeyVersion`, codec `encrypted_risk_level.dart`). Como o AES-GCM preserva o tamanho do texto claro, o nome do nível é preenchido até a largura do maior nome (a ausência também), e o teste `test/unit/encrypted_risk_level_test.dart` prova que os quatro casos dão ciphertexts do mesmo comprimento. `triage_sessions.resultDisplay` foi removida. `alerts.riskLevel` fica legível por decisão registrada no PRD (INV-04): é constante (`red`) e é chave dos filtros SQL que impedem o descarte de alerta vermelho. O `payload` de `alert_outbox` carrega o mesmo `risk_level` constante; o risco dele é o `locationHash`, tratado em §2.2. Migrações sem backfill: um `pg_data/` anterior perde o risco das triagens (somem do histórico do "Meus Dados") e das visitas (o `pull` do ACS falha até recriar o volume).
```

- [ ] **Step 3: `backend/CLAUDE.md`**

No parágrafo "The three clinical columns are encrypted at the ORM boundary only: …", trocar o início por:

```markdown
The clinical columns are encrypted at the ORM boundary only (since #75 also the risk classifications `triage_sessions.resultRiskEncrypted` and `visits.riskLevelBefore/AfterEncrypted`, through the fixed-width codec `infrastructure/crypto/encrypted_risk_level.dart`; `alerts.riskLevel` stays plaintext by a recorded decision — see `spec/lgpd_data_audit.md` §2.3):
```

mantendo o resto do parágrafo.

- [ ] **Step 4: `CLAUDE.md` raiz — aviso do `pg_data/`**

No parágrafo **"Updating an existing `pg_data/` to this branch loses dev clinical data silently."**, acrescentar ao fim (com os ids reais das duas migrações geradas nas Tasks 2-3):

```markdown
Issue #75 repeats it: migrations `<id-da-task-2>` and `<id-da-task-3>` `DROP COLUMN` `triage_sessions.resultRisk`/`resultDisplay` and `visits.riskLevelBefore`/`riskLevelAfter` with no backfill. On an old volume, old triages drop out of the patient's "Meus Dados" risk history and the ACS `visits.pull` fails with `StateError` on any pre-migration visit until `docker compose down && rm -rf pg_data/`.
```

Substituir `<id-da-task-2>`/`<id-da-task-3>` pelos nomes dos diretórios criados (`ls backend/sinalacs_server/migrations | tail -3`) antes de salvar.

- [ ] **Step 5: `PROGRESS.md`**

Acrescentar uma seção no padrão das demais (título, data, o que foi entregue, provas, o que fica aberto):

```markdown
## Colunas de risco cifradas (#75) — 2026-10-16

- Entregue: `triage_sessions.resultRisk` e `visits.riskLevelBefore`/`riskLevelAfter` cifrados em AES-256-GCM na borda ORM, com codec de largura fixa (o tamanho do ciphertext não revela a classe); `triage_sessions.resultDisplay` removida (derivada).
- Decisão: `alerts.riskLevel` permanece legível (só `red` é gravado; chave dos filtros SQL da INV-03). Registrada no PRD (INV-04) e em `spec/lgpd_data_audit.md` §2.3; amarrada pelo teste `INV-04 (#75)` de `test/unit/red_alert_discard_paths_test.dart`.
- Provas: `test/unit/encrypted_risk_level_test.dart`; testes `#75` em `test/integration/health_data_encryption_test.dart` (linha bruta por `row_to_json` sem risco legível, ida e volta, `After` nulo e conclusão, linha antiga falha alto) e em `test/integration/patient_data_overview_endpoint_test.dart`.
- Aberto: migrações sem backfill (volume antigo precisa ser recriado); rotação de chave continua inexistente (`keyVersion` só marcador), como nas demais colunas cifradas.
```

- [ ] **Step 6: Backlog da auditoria**

Em `docs/auditoria-prd/2026-10-15-lacunas-prd.md`:
- linha **INV-04**: status `**entregue**`; na coluna de evidência acrescentar "riscos de triagem e visita cifrados (#75); `alerts.riskLevel` legível por decisão registrada no PRD"; coluna "falta": `—`;
- linha **RNF03**: coluna "falta" passa a `Ver CRIPTO-APP-CACHE.` (status segue **parcial**);
- linha **LGPD-RF09**: coluna "falta" passa a `Ver CRIPTO-APP-CACHE e RNF06.` (status segue **parcial**);
- linha do item **1** do backlog priorizado: acrescentar `**Resolvido (2026-10-16, #75).**` no início da descrição.

- [ ] **Step 7: Commit**

```bash
git add spec/PRD_system.md spec/lgpd_data_audit.md backend/CLAUDE.md CLAUDE.md PROGRESS.md docs/auditoria-prd/2026-10-15-lacunas-prd.md
git commit -m "docs: registra a cifra dos riscos e a exceção de alerts.riskLevel (#75)"
```

---

### Task 6: Verificação completa e fechamento

**Files:** nenhum novo (só `graphify-out/` regenerado).

- [ ] **Step 1: Suíte do backend inteira**

Run: `cd backend/sinalacs_server && dart analyze && dart test -j 1`
Expected: `No issues found!` e todos os testes PASS (o total cresce em ~10 em relação a `develop`).

- [ ] **Step 2: Cliente regenerado não quebra os apps**

Run:
```bash
cd /home/rock/Documents/Dev/APPs/SinalACS
for app in acs patient admin; do (cd apps/$app && flutter analyze) || echo "FALHOU: $app"; done
```
Expected: nenhum `FALHOU:` (os apps usam os DTOs de API, não `Visit`/`TriageSession`; se algum usar, adaptar ao par cifrado não é o caminho — o app deve usar o DTO de API).

- [ ] **Step 3: Pilha local do zero**

Run:
```bash
docker compose down && sudo rm -rf pg_data/ && docker compose up --build -d
docker compose logs serverpod | grep -i -E "migrat|error" | tail -20
```
Expected: as duas migrações novas aplicadas no boot, sem erro. Depois, uma rodada da validação ponta a ponta (skill `validacao-e2e`, `scripts/qa/e2e.sh`) para confirmar triagem → "Meus Dados" e sync/pull do ACS contra o backend real.

Conferir no banco que nada ficou legível:
```bash
docker compose exec postgres psql -U sinalacs_user -d sinalacs_db -c \
  'SELECT "resultRiskEncrypted" FROM triage_sessions LIMIT 3;' -c \
  'SELECT "riskLevelBeforeEncrypted", "riskLevelAfterEncrypted" FROM visits LIMIT 3;'
```
Expected: só base64, todos do mesmo comprimento.

- [ ] **Step 4: Atualizar o grafo**

Run: `cd /home/rock/Documents/Dev/APPs/SinalACS && graphify update .`

- [ ] **Step 5: PR**

```bash
git push -u origin fix/issue-75-colunas-de-risco
gh pr create --base develop --title "fix: cifra as colunas de risco e registra a exceção de alerts.riskLevel (#75)" --body "$(cat <<'EOF'
Fecha #75.

- Cifra `triage_sessions.resultRisk` e `visits.riskLevelBefore`/`riskLevelAfter` (AES-256-GCM na borda ORM, codec de largura fixa para o tamanho não revelar a classe).
- Remove `triage_sessions.resultDisplay` (derivada do risco, ninguém lia).
- Mantém `alerts.riskLevel` legível por decisão registrada no PRD (INV-04): só `red` é gravado e a coluna sustenta os filtros SQL da INV-03; teste `INV-04 (#75)` amarra a condição.
- Migrações sem backfill: `pg_data/` antigo precisa ser recriado (ver `CLAUDE.md`).

Testes: `dart test -j 1` verde; `flutter analyze` dos três apps limpo; pilha local recriada do zero.
EOF
)"
```

Os 8 checks obrigatórios da CI precisam passar antes do merge.
