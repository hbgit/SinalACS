# Menores adiados da rodada 3 e recebimento de push no paciente (RF14) — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fechar os menores adiados da rodada 3 (aceite simultâneo, locks, rascunho de correção, testes e docs) e entregar o lado do paciente do RF14: registro do token de push condicionado ao consentimento `segmentedPush`, sem depender do projeto Firebase, que segue não provisionado.

**Architecture:** O servidor ganha a tabela `push_tokens` e o endpoint `devices` (`registerPushToken`), que recusa registro sem consentimento vigente; revogar `segmentedPush` apaga os tokens do titular. O app obtém o token por uma interface `PushTokenSource` cuja implementação padrão devolve `null` (sem Firebase) e registra no login e ao conceder o consentimento. A troca por `firebase_messaging` fica para quando o projeto existir, sem mexer em servidor nem em telas.

**Tech Stack:** Serverpod 3.4.13 (`serverpod generate` + `create-migration`), Postgres com `pg_advisory_xact_lock`, Flutter 3.44, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md` §3.2 (contrato RF14) e §2 (consentimento); `spec/lgpd_design.md` (LGPD-RF02/RF05).

## Global Constraints

- Regenerar com `export PATH=$PATH:~/.pub-cache/bin; cd backend/sinalacs_server && serverpod generate && serverpod create-migration`. Testes de integração: `docker compose --profile test up -d postgres-test`.
- `flutter analyze` limpo nos dois apps, infos incluídas. `dart analyze` do backend no baseline de 41 infos.
- Alerta vermelho nunca é descartado nem atrasado: nenhuma falha de push (token, rede, consentimento) pode bloquear login, home ou o botão de urgência.
- Conteúdo do push não carrega dado de saúde identificável (§3.2); esta rodada não envia push, só registra token.
- `userId` vem sempre de `user.id`, nunca de parâmetro (INV-05).
- Texto de UI e comentários em português. Nenhum dado real de paciente em testes.
- Contagens de testes ao fim: backend, paciente e ACS verdes; `./scripts/qa/ci_invariants.sh` ok.

## Review Focus

- Token registrado com consentimento revogado: o servidor recusa e o app engole a recusa sem mensagem (o paciente não pediu push).
- Revogar `segmentedPush` e conceder de novo: os tokens antigos somem na revogação; a concessão registra o token atual.
- O mesmo token registrado duas vezes (login repetido, duas abas): uma linha só, `updatedAt` renovado.
- Token trocado por outro titular no mesmo aparelho: a linha muda de dono, nunca fica com dois donos.
- Duas chamadas simultâneas de `acceptTermsOfUse`: uma linha em `consent_logs`.

---

## Mapa de arquivos

- Backend criar: `lib/src/models/push_token.spy.yaml`, `lib/src/application/patients/push_token_service.dart`, `lib/src/infrastructure/database/orm_push_token_store.dart`, `lib/src/infrastructure/database/subject_lock.dart`, `lib/src/endpoints/devices_endpoint.dart`, `test/unit/push_token_service_test.dart`, `test/integration/push_token_endpoint_test.dart`.
- Backend modificar: `data_subject_rights_service.dart`, `orm_data_subject_rights_store.dart`, `runtime/alert_runtime.dart` (fábrica do serviço), `patients_endpoint.dart` (comentário), `test/unit/data_subject_rights_service_test.dart`, `test/integration/data_subject_rights_endpoint_test.dart`.
- Paciente criar: `lib/core/push/push_token_source.dart`, `test/push_registration_test.dart`.
- Paciente modificar: `lib/app/app.dart`, `lib/core/network/backend_client.dart`, `test/support/fake_patient_backend.dart`, `test/patient_app_mvp_test.dart`.
- Docs: `apps/CLAUDE.md`, `backend/CLAUDE.md`, `PROGRESS.md`, `spec/lgpd_data_audit.md`, `spec/PRD_system.md`, memória.

---

### Task 1: Aceite do termo atômico e locks de duas chaves (backend)

**Files:**
- Create: `backend/sinalacs_server/lib/src/infrastructure/database/subject_lock.dart`
- Modify: `lib/src/application/patients/data_subject_rights_service.dart`, `lib/src/infrastructure/database/orm_data_subject_rights_store.dart`, `lib/src/endpoints/patients_endpoint.dart`
- Test: `test/unit/data_subject_rights_service_test.dart`, `test/integration/data_subject_rights_endpoint_test.dart`

**Interfaces:**
- Produces: `Future<void> lockPerSubject(Session session, Transaction transaction, {required int namespace, required String key})` em `subject_lock.dart`; constantes `lockNamespaceDeletion = 1`, `lockNamespaceTerms = 2` (o `OrmAuditTrail` continua na forma de uma chave, espaço separado).
- Produces: `DataSubjectRightsStore.recordConsentUnlessCurrent(ConsentLogEntry entry) → Future<({String? id, ConsentRecordSnapshot? existing})>`: sob lock, se a linha mais recente do propósito já é `granted` na `entry.version`, devolve `existing` e não grava; senão grava e devolve `id`.
- Consumes: `signedConsentLog`, `ConsentLogEntry`, `ConsentRecordSnapshot` (já existem).

- [ ] **Step 1: Teste unitário vermelho — o serviço delega a idempotência ao store**

Em `test/unit/data_subject_rights_service_test.dart`, o fake store ganha `recordConsentUnlessCurrent` (mesma regra do real, sobre a lista em memória) e um contador `unlessCurrentCalls`. Teste novo:

```dart
test('acceptTermsOfUse usa a gravação condicional e não audita a repetição', () async {
  await service.acceptTermsOfUse(patient);
  await service.acceptTermsOfUse(patient);

  expect(store.unlessCurrentCalls, 2);
  expect(store.consents.where((c) => c.purpose == ConsentPurpose.termsOfUse.name), hasLength(1));
  expect(audit.events.where((e) => e.resourceType == 'consent_log'), hasLength(1));
});
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd backend/sinalacs_server && dart test test/unit/data_subject_rights_service_test.dart`
Expected: FAIL — `recordConsentUnlessCurrent` não existe na interface.

- [ ] **Step 3: Implementar o serviço e a interface**

Em `data_subject_rights_service.dart`, na interface:

```dart
  /// Grava `entry` **só se** a linha mais recente do propósito ainda não for um
  /// `granted` na mesma versão, de forma atômica por titular: duas chamadas
  /// simultâneas resultam em uma linha, e a segunda recebe a da primeira em
  /// `existing`.
  Future<({String? id, ConsentRecordSnapshot? existing})> recordConsentUnlessCurrent(
    ConsentLogEntry entry,
  );
```

E `acceptTermsOfUse` vira:

```dart
  Future<ConsentRecordSnapshot> acceptTermsOfUse(AuthenticatedUser user) async {
    _requirePatient(user);
    final now = _clock().toUtc();
    final result = await _store.recordConsentUnlessCurrent(ConsentLogEntry(
      userId: user.id,
      purpose: ConsentPurpose.termsOfUse,
      action: 'granted',
      version: consentPolicyVersion,
      timestamp: now,
    ));
    // Idempotente: já aceitou a versão vigente, devolve a linha existente em
    // vez de crescer o histórico e a trilha de auditoria a cada chamada.
    if (result.existing != null) return result.existing!;
    await _auditConsent(user, result.id!);
    return ConsentRecordSnapshot(
      purpose: ConsentPurpose.termsOfUse.name,
      action: 'granted',
      version: consentPolicyVersion,
      timestamp: now,
    );
  }
```

Extrair de `_record` o trecho `_audit.recordSafely(...)` para `_auditConsent(user, id)` (mesma chamada, `resourceType: 'consent_log'`, `result: 'granted'`) e usá-lo nos dois lugares.

- [ ] **Step 4: Rodar e ver passar**

Run: `dart test test/unit/data_subject_rights_service_test.dart`
Expected: PASS.

- [ ] **Step 5: Teste de integração vermelho — corrida de aceites**

No grupo de corrida de `test/integration/data_subject_rights_endpoint_test.dart` (usa `RollbackDatabase.disabled`, `_seedRace` e `_cleanupRace`), teste novo:

```dart
test('dois acceptTermsOfUse simultâneos gravam uma linha só', () async {
  final race = await _seedRace(session);
  addTearDown(() => _cleanupRace(session, race));

  await Future.wait([
    endpoint.acceptTermsOfUse(session, accessToken: race.token),
    endpoint.acceptTermsOfUse(session, accessToken: race.token),
  ]);

  final rows = await ConsentLog.db.find(
    session,
    where: (t) => t.userId.equals(race.userId) & t.purpose.equals(ConsentPurpose.termsOfUse.name),
  );
  expect(rows, hasLength(1));
});
```

Se `_seedRace` já semeia uma linha `termsOfUse`, ajustar o `where` para contar só as criadas depois (`timestamp`), ou semear um paciente sem aceite.

Run: `docker compose --profile test up -d postgres-test && cd backend/sinalacs_server && dart test test/integration/data_subject_rights_endpoint_test.dart -N "simultâneos gravam uma linha"`
Expected: FAIL — `Expected: an object with length of <1>  Actual: [..., ...]` (o store ainda não existe; comece implementando só a interface com uma versão sem lock que grave sempre, para ver a duplicata, e troque no Step 6).

- [ ] **Step 6: Implementar o lock e o store**

`subject_lock.dart`:

```dart
import 'package:serverpod/serverpod.dart';

/// Namespaces dos advisory locks por titular. A forma de duas chaves de
/// `pg_advisory_xact_lock(int, int)` não compartilha espaço com a de uma chave
/// (`OrmAuditTrail`), então um `hashtext` nunca colide com a cadeia de auditoria.
const int lockNamespaceDeletion = 1;
const int lockNamespaceTerms = 2;

/// Serializa, dentro de [transaction], quem disputa a mesma [key] no mesmo
/// [namespace]. Solta sozinho no fim da transação.
Future<void> lockPerSubject(
  Session session,
  Transaction transaction, {
  required int namespace,
  required String key,
}) async {
  await session.db.unsafeExecute(
    'SELECT pg_advisory_xact_lock(@ns::int, hashtext(@key));',
    parameters: QueryParameters.named({'ns': namespace, 'key': key}),
    transaction: transaction,
  );
}
```

Em `orm_data_subject_rights_store.dart`, `createDeletionRequestIfNoneOpen` troca o `unsafeExecute` por `lockPerSubject(session, transaction, namespace: lockNamespaceDeletion, key: userId)`. E o método novo:

```dart
  @override
  Future<({String? id, ConsentRecordSnapshot? existing})> recordConsentUnlessCurrent(
    ConsentLogEntry entry,
  ) async {
    final session = _session();
    final userUuid = UuidValue.fromString(entry.userId);
    return session.db.transaction((transaction) async {
      await lockPerSubject(session, transaction,
          namespace: lockNamespaceTerms, key: '${entry.purpose.name}:${entry.userId}');
      final latest = await ConsentLog.db.findFirstRow(
        session,
        where: (t) => t.userId.equals(userUuid) & t.purpose.equals(entry.purpose.name),
        orderBy: (t) => t.timestamp,
        orderDescending: true,
        transaction: transaction,
      );
      if (latest != null && latest.action == 'granted' && latest.version == entry.version) {
        return (
          id: null,
          existing: ConsentRecordSnapshot(
            purpose: latest.purpose,
            action: latest.action,
            version: latest.version,
            timestamp: latest.timestamp,
          ),
        );
      }
      final row = await ConsentLog.db.insertRow(
        session,
        signedConsentLog(entry, signature: _signature, origin: 'painel-titular'),
        transaction: transaction,
      );
      return (id: row.id!.uuid, existing: null);
    });
  }
```

Atualizar o comentário de `acceptTermsOfUse` em `patients_endpoint.dart` ("grava uma linha nova" → "grava uma linha só se a versão vigente ainda não foi aceita; repetir devolve a existente"), e o mesmo em `apps/patient/lib/core/network/backend_client.dart` (`acceptTermsOfUse`).

- [ ] **Step 7: Rodar tudo do backend**

Run: `cd backend/sinalacs_server && dart test`
Expected: PASS (346 anteriores + 2 novos = 348), inclusive o teste de corrida da exclusão, agora com o lock de duas chaves. `dart analyze` no baseline de 41 infos.

- [ ] **Step 8: Commit**

```bash
git add backend/sinalacs_server
git commit -m "fix(backend): aceite do termo atômico e advisory locks de duas chaves (LGPD-RF18)"
```

---

### Task 2: Tabela `push_tokens`, serviço e endpoint `devices` (backend)

**Files:**
- Create: `lib/src/models/push_token.spy.yaml`, `lib/src/application/patients/push_token_service.dart`, `lib/src/infrastructure/database/orm_push_token_store.dart`, `lib/src/endpoints/devices_endpoint.dart`
- Modify: `lib/src/runtime/alert_runtime.dart` (fábrica `pushTokenServiceFor(session)`, ao lado de `dataSubjectRightsServiceFor`), `data_subject_rights_service.dart` (revogação apaga tokens)
- Test: `test/unit/push_token_service_test.dart`, `test/integration/push_token_endpoint_test.dart`

**Interfaces:**
- Produces: `PushTokenStore` com `Future<bool> hasGrantedConsent(String userId)`, `Future<void> upsert({required String userId, required String? microAreaId, required String token, required String platform, required DateTime now})`, `Future<int> deleteAllFor(String userId)`.
- Produces: `PushTokenService.register(AuthenticatedUser user, {required String token, required String platform})` — só paciente; recusa com `DataRightsException` se não houver consentimento `segmentedPush` vigente, se `token` vazio ou maior que 4096 caracteres, ou se `platform` não for `android`/`ios`.
- Produces: RPC `devices.registerPushToken(session, {required String accessToken, required String token, required String platform}) → Future<void>`.
- Consumes: `latestConsent` de `DataSubjectRightsStore` (o store de push usa o mesmo `ConsentLog`), `lockPerSubject` da Task 1 (namespace novo `lockNamespacePushToken = 3`).

- [ ] **Step 1: Modelo**

`push_token.spy.yaml`:

```yaml
### Token de push (FCM/APNs) do aparelho de um paciente que consentiu com
### `segmentedPush` (RF14, decisão §3.2). Uma linha por token: se o mesmo token
### aparece para outro titular, a linha muda de dono, nunca duplica.
###
### O token identifica um aparelho, não uma pessoa, mas junto de `userId` liga
### aparelho a titular — por isso some na revogação do consentimento.
class: PushToken
table: push_tokens
fields:
  id: UuidValue?, defaultPersist=random
  userId: UuidValue, relation(parent=users)
  microAreaId: UuidValue?
  token: String
  platform: String
  createdAt: DateTime
  updatedAt: DateTime
indexes:
  push_tokens_token_key:
    fields: token
    unique: true
  push_tokens_user_id_idx:
    fields: userId
```

Run: `export PATH=$PATH:~/.pub-cache/bin; cd backend/sinalacs_server && serverpod generate && serverpod create-migration`
Expected: gera `push_token.dart`, atualiza `protocol.dart` e cria uma migração nova com `CREATE TABLE "push_tokens"`.

- [ ] **Step 2: Testes unitários vermelhos**

`test/unit/push_token_service_test.dart` com um `_FakePushTokenStore` (mapa token→linha, `consent` booleano, `deleted` contador):

```dart
test('sem consentimento vigente, recusa e não grava', () async {
  store.consent = false;
  await expectLater(
    service.register(patient, token: 'tok-1', platform: 'android'),
    throwsA(isA<DataRightsException>()),
  );
  expect(store.rows, isEmpty);
});

test('registra e repete sem duplicar', () async {
  await service.register(patient, token: 'tok-1', platform: 'android');
  await service.register(patient, token: 'tok-1', platform: 'android');
  expect(store.rows.keys, ['tok-1']);
});

test('o mesmo token de outro titular troca de dono', () async {
  await service.register(patient, token: 'tok-1', platform: 'android');
  await service.register(otherPatient, token: 'tok-1', platform: 'android');
  expect(store.rows['tok-1']!.userId, otherPatient.id);
});

test('recusa token vazio, longo demais e plataforma desconhecida', () async {
  for (final args in [('', 'android'), ('x' * 4097, 'android'), ('tok', 'web')]) {
    await expectLater(
      service.register(patient, token: args.$1, platform: args.$2),
      throwsA(isA<DataRightsException>()),
    );
  }
});

test('ACS não registra token', () async {
  await expectLater(
    service.register(acs, token: 'tok-1', platform: 'android'),
    throwsA(isA<StateError>()),
  );
});
```

Mais um teste em `data_subject_rights_service_test.dart` (o fake store de lá ganha `pushTokensDeleted`, ou o serviço recebe um `PushTokenStore` opcional — ver Step 3): `updateConsent(segmentedPush, granted: false)` chama `deleteAllFor(user.id)` uma vez; `granted: true` e outras finalidades não chamam.

Run: `dart test test/unit/push_token_service_test.dart`
Expected: FAIL — `PushTokenService` não existe.

- [ ] **Step 3: Implementar serviço, store e revogação**

```dart
abstract interface class PushTokenStore {
  Future<bool> hasGrantedConsent(String userId);
  Future<void> upsert({
    required String userId,
    required String? microAreaId,
    required String token,
    required String platform,
    required DateTime now,
  });
  Future<int> deleteAllFor(String userId);
}

const int pushTokenMaxLength = 4096;
const Set<String> pushPlatforms = {'android', 'ios'};

class PushTokenService {
  PushTokenService({required PushTokenStore store, DateTime Function()? clock})
      : _store = store,
        _clock = clock ?? DateTime.now;

  final PushTokenStore _store;
  final DateTime Function() _clock;

  Future<void> register(AuthenticatedUser user,
      {required String token, required String platform}) async {
    Authorization.require(
      user,
      roles: {UserRole.patient},
      onDenied: () => StateError('Somente o próprio paciente registra o aparelho para avisos.'),
      requireMicroArea: false,
    );
    final trimmed = token.trim();
    if (trimmed.isEmpty || trimmed.length > pushTokenMaxLength || !pushPlatforms.contains(platform)) {
      throw DataRightsException(message: 'Aparelho inválido para receber avisos.');
    }
    if (!await _store.hasGrantedConsent(user.id)) {
      throw DataRightsException(
        message: 'Ative "Avisos da equipe de saúde" em Meus Dados para receber avisos.',
      );
    }
    await _store.upsert(
      userId: user.id,
      microAreaId: user.microAreaId,
      token: trimmed,
      platform: platform,
      now: _clock().toUtc(),
    );
  }
}
```

`DataSubjectRightsService` ganha o parâmetro nomeado opcional `PushTokenStore? pushTokens` e, em `updateConsent`, depois de `_record`, `if (purpose == ConsentPurpose.segmentedPush && !granted) await _pushTokens?.deleteAllFor(user.id);`. A fábrica `dataSubjectRightsServiceFor` em `alert_runtime.dart` passa o `OrmPushTokenStore`.

`OrmPushTokenStore`: `hasGrantedConsent` lê o `ConsentLog` mais recente de `segmentedPush` do titular (`action == 'granted'`); `upsert` roda em transação com `lockPerSubject(namespace: lockNamespacePushToken, key: token)`, busca `PushToken` por `token`, atualiza `userId`/`microAreaId`/`platform`/`updatedAt` se existir, senão insere; `deleteAllFor` usa `PushToken.db.deleteWhere(session, where: (t) => t.userId.equals(uuid))` e devolve o tamanho da lista removida.

`DevicesEndpoint extends AuthenticatedEndpoint`:

```dart
class DevicesEndpoint extends AuthenticatedEndpoint {
  /// Registra o token de push do aparelho do paciente autenticado (RF14, §3.2).
  /// Só grava com o consentimento `segmentedPush` vigente.
  Future<void> registerPushToken(
    Session session, {
    required String accessToken,
    required String token,
    required String platform,
  }) async {
    final user = authenticate(accessToken);
    try {
      await AlertRuntime.instance
          .pushTokenServiceFor(session)
          .register(user, token: token, platform: platform);
    } on StateError catch (error) {
      throw AlertPermissionException(message: error.message);
    }
  }
}
```

Adicionar `pushTokenServiceFor` em `alert_runtime.dart` no mesmo formato de `dataSubjectRightsServiceFor`.

- [ ] **Step 4: Rodar os unitários**

Run: `dart test test/unit/push_token_service_test.dart test/unit/data_subject_rights_service_test.dart`
Expected: PASS.

- [ ] **Step 5: Integração**

`test/integration/push_token_endpoint_test.dart` (mesmo esqueleto de `data_subject_rights_endpoint_test.dart`: `withServerpod` e um paciente semeado com token):

```dart
test('paciente com consentimento registra e repete sem duplicar', () async {
  await patients.updateConsent(session, accessToken: token, purpose: ConsentPurpose.segmentedPush, granted: true);
  await devices.registerPushToken(session, accessToken: token, token: 'tok-1', platform: 'android');
  await devices.registerPushToken(session, accessToken: token, token: 'tok-1', platform: 'android');
  expect(await PushToken.db.count(session, where: (t) => t.token.equals('tok-1')), 1);
});

test('sem consentimento a chamada falha e nada é gravado', () async {
  await expectLater(
    devices.registerPushToken(session, accessToken: token, token: 'tok-2', platform: 'android'),
    throwsA(isA<DataRightsException>()),
  );
  expect(await PushToken.db.count(session, where: (t) => t.token.equals('tok-2')), 0);
});

test('revogar segmentedPush apaga os tokens do titular', () async {
  await patients.updateConsent(session, accessToken: token, purpose: ConsentPurpose.segmentedPush, granted: true);
  await devices.registerPushToken(session, accessToken: token, token: 'tok-3', platform: 'ios');
  await patients.updateConsent(session, accessToken: token, purpose: ConsentPurpose.segmentedPush, granted: false);
  expect(await PushToken.db.count(session, where: (t) => t.token.equals('tok-3')), 0);
});

test('token inexistente ou de ACS: token inválido é recusado', () async {
  await expectLater(
    devices.registerPushToken(session, accessToken: 'lixo', token: 'tok', platform: 'android'),
    throwsA(isA<AlertPermissionException>()),
  );
});
```

Run: `dart test test/integration/push_token_endpoint_test.dart`
Expected: PASS. Se o teste de postura de endpoints (`endpoint_auth_posture_test.dart`) ou de cobertura de auditoria falhar por causa do endpoint novo, tratar como achado: o endpoint estende `AuthenticatedEndpoint`, e a decisão de auditar (ou não) o registro fica registrada no teste, como em `hasAcceptedCurrentTerms` (leitura, sem linha de auditoria; aqui é escrita de metadado de aparelho: auditar com `resourceType: 'push_token'` só se o teste de cobertura exigir).

- [ ] **Step 6: Suíte do backend e commit**

Run: `cd backend/sinalacs_server && dart test && dart analyze`
Expected: tudo verde; analyze no baseline.

```bash
git add backend/sinalacs_server
git commit -m "feat(backend): registro de token de push condicionado ao consentimento (RF14)"
```

---

### Task 3: Menores do app paciente (rascunho, testes que faltam)

**Files:**
- Modify: `apps/patient/lib/app/app.dart` (`_requestCorrection`)
- Test: `apps/patient/test/patient_app_mvp_test.dart`, `apps/patient/test/terms_gate_flow_test.dart` (ou `onboarding_flow_test.dart` para o scanner, onde o teste de câmera vive)

**Interfaces:**
- Consumes: `FakePatientBackend.correctionRequests`, `QrScannerScope` e o helper de câmera falsa já usados em `onboarding_flow_test.dart`.

- [ ] **Step 1: Testes vermelhos**

No grupo de correção de `patient_app_mvp_test.dart` (mesmos helpers `tapByKey`, `outlined` e o `drag` do teste de falha):

```dart
testWidgets('tocar fora do diálogo de correção não descarta o rascunho', (tester) async {
  await abrirMeusDadosComBackend(tester, FakePatientBackend());
  await tapByKey(tester, 'request_correction_button');
  await tester.enterText(find.byKey(const Key('correction_details_field')), 'Meu contato mudou.');
  await tester.pump();

  await tester.tapAt(const Offset(4, 4)); // fora do diálogo
  await tester.pumpAndSettle();

  expect(find.byKey(const Key('correction_details_field')), findsOneWidget);
  expect(
    tester.widget<TextField>(find.byKey(const Key('correction_details_field'))).controller!.text,
    'Meu contato mudou.',
  );
});

testWidgets('Cancelar descarta o rascunho: reabrir vem vazio', (tester) async {
  await abrirMeusDadosComBackend(tester, FakePatientBackend());
  await tapByKey(tester, 'request_correction_button');
  await tester.enterText(find.byKey(const Key('correction_details_field')), 'Meu contato mudou.');
  await tester.pump();
  await tester.tap(find.byKey(const Key('correction_request_cancel')));
  await tester.pumpAndSettle();

  await tapByKey(tester, 'request_correction_button');
  expect(
    tester.widget<TextField>(find.byKey(const Key('correction_details_field'))).controller!.text,
    isEmpty,
  );
});
```

Usar o nome real do helper de abertura de "Meus dados" que o grupo já emprega (ler as linhas 1140-1230 do arquivo antes; o snippet acima segue o padrão delas).

Para o scanner, em `onboarding_flow_test.dart`, junto do teste de toque duplo:

```dart
testWidgets('o botão de escanear volta a funcionar depois que o leitor lança', (tester) async {
  var chamadas = 0;
  final scanner = FakeQrScanner((context) async {
    chamadas++;
    if (chamadas == 1) throw StateError('câmera indisponível');
    return enrollmentTokenValido;
  });
  // monta o app sob QrScannerScope(scanner: scanner), abre o onboarding
  await tapKey(tester, 'scan_qr_button');
  expect(find.byKey(const Key('scan_qr_button')), findsOneWidget);
  await tapKey(tester, 'scan_qr_button');
  expect(chamadas, 2);
});
```

Adaptar `FakeQrScanner`, `enrollmentTokenValido` e a montagem aos nomes que o teste vizinho do toque duplo já usa.

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd apps/patient && flutter test test/patient_app_mvp_test.dart test/onboarding_flow_test.dart`
Expected: FAIL só no teste de toque fora (o diálogo fecha e o campo some). Os outros dois passam de primeira: registrar no ledger como testes de caracterização, sem RED observado.

- [ ] **Step 3: Implementar**

Em `_requestCorrection`, `showDialog<String>(context: context, barrierDismissible: false, builder: ...)`. O comentário do `details == null` continua correto (só "Cancelar" devolve `null`).

- [ ] **Step 4: Rodar a suíte e commitar**

Run: `cd apps/patient && flutter test && flutter analyze`
Expected: PASS (182 + 3 = 185), analyze limpo.

```bash
git add apps/patient
git commit -m "fix(paciente): tocar fora do diálogo de correção não apaga o rascunho"
```

---

### Task 4: Registro do token de push no app paciente (RF14, lado cliente)

**Files:**
- Create: `apps/patient/lib/core/push/push_token_source.dart`, `apps/patient/test/push_registration_test.dart`
- Modify: `apps/patient/lib/core/network/backend_client.dart`, `apps/patient/lib/app/app.dart`, `apps/patient/test/support/fake_patient_backend.dart`

**Interfaces:**
- Produces: `abstract interface class PushTokenSource { Future<PushDevice?> currentDevice(); }`, `class PushDevice { const PushDevice({required this.token, required this.platform}); }`, `class NoPushTokenSource implements PushTokenSource` (sempre `null`).
- Produces: `PatientBackend.registerPushToken({required String token, required String platform}) → Future<void>` (interface, `MisconfiguredBackend` e `BackendClient` → `_client.devices.registerPushToken`).
- Produces: `SinalAcsApp({..., PushTokenSource pushTokens = const NoPushTokenSource()})`.
- Consumes: `serverpod generate` da Task 2 regenera o cliente com `devices`.

- [ ] **Step 1: Testes vermelhos**

`test/push_registration_test.dart`, com `FakePatientBackend` ganhando `pushRegistrations` (lista de `(token, platform)`), `pushRegistrationFailure` (lançado se não nulo) e um `_FakeSource(PushDevice?)`:

```dart
testWidgets('depois do login registra o token do aparelho', (tester) async {
  final backend = FakePatientBackend();
  await tester.pumpWidget(SinalAcsApp(backend: backend, pushTokens: _FakeSource(const PushDevice(token: 'tok-1', platform: 'android'))));
  await login(tester);
  expect(backend.pushRegistrations, [('tok-1', 'android')]);
});

testWidgets('sem token (sem Firebase) não chama o servidor', (tester) async {
  final backend = FakePatientBackend();
  await tester.pumpWidget(SinalAcsApp(backend: backend));
  await login(tester);
  expect(backend.pushRegistrations, isEmpty);
});

testWidgets('recusa do servidor não afeta a home nem mostra erro', (tester) async {
  final backend = FakePatientBackend()..pushRegistrationFailure = const BackendFailure('sem consentimento');
  await tester.pumpWidget(SinalAcsApp(backend: backend, pushTokens: _FakeSource(const PushDevice(token: 'tok-1', platform: 'android'))));
  await login(tester);
  expect(find.text('Registrar alerta de urgência'), findsOneWidget);
  expect(find.textContaining('sem consentimento'), findsNothing);
});

testWidgets('conceder "Avisos da equipe" em Meus Dados registra o token', (tester) async {
  // login com consentimento de push negado, abrir Meus Dados, ligar o switch do segmentedPush
  // esperado: backend.pushRegistrations tem exatamente um item depois do toque
});

testWidgets('revogar não registra nada', (tester) async {
  // mesmo cenário com o switch já ligado, desligar; pushRegistrations não cresce
});
```

Copiar `login` de `terms_gate_flow_test.dart` (ou movê-lo para `test/support/`, se já houver um terceiro consumidor) e usar as chaves reais do switch de consentimento no painel (ler o trecho de `updateConsent` em `app.dart:1755` e o teste de consentimento existente para os nomes).

Run: `cd apps/patient && flutter test test/push_registration_test.dart`
Expected: FAIL — `PushTokenSource` e o parâmetro `pushTokens` não existem.

- [ ] **Step 2: Implementar**

`push_token_source.dart`:

```dart
/// Aparelho apto a receber push: o token do provedor e a plataforma.
class PushDevice {
  const PushDevice({required this.token, required this.platform});

  final String token;

  /// `android` ou `ios`, o mesmo vocabulário que o servidor valida.
  final String platform;
}

/// De onde o app tira o token de push. A implementação real (FCM) entra quando
/// existir um projeto Firebase (decisão §3.2 do documento de decisões de
/// produto); até lá [NoPushTokenSource] mantém o registro inerte, e servidor e
/// telas já estão prontos para a troca.
abstract interface class PushTokenSource {
  /// `null` quando o aparelho não tem token (sem provedor, sem permissão).
  Future<PushDevice?> currentDevice();
}

class NoPushTokenSource implements PushTokenSource {
  const NoPushTokenSource();

  @override
  Future<PushDevice?> currentDevice() async => null;
}
```

`backend_client.dart`: método `registerPushToken` na interface (com doc: "Falha se não houver consentimento `segmentedPush` vigente; quem chama ignora a falha"), no `MisconfiguredBackend` (`throw failure`, como os vizinhos) e no `BackendClient`, no mesmo formato de `updateConsent` (linha 528): `_call(() => _client.devices.registerPushToken(accessToken: token, token: pushToken, platform: platform))`, ajustando ao nome real do helper e dos parâmetros.

`app.dart`: `SinalAcsApp` recebe `pushTokens`; guardá-lo no `State` que faz o login e chamar, depois de `_entrar` autenticar (e ao concluir o onboarding), `unawaited(_registerPush())`:

```dart
  /// Registra o aparelho para avisos (RF14). Silencioso de propósito: o
  /// paciente não pediu isto na tela, e uma recusa (consentimento desligado) ou
  /// uma falha de rede nunca pode atrasar a home nem o botão de urgência.
  Future<void> _registerPush() async {
    try {
      final device = await widget.pushTokens.currentDevice();
      if (device == null || !mounted) return;
      await BackendScope.of(context).registerPushToken(token: device.token, platform: device.platform);
    } on BackendFailure {
      // sem consentimento ou sem rede: tenta de novo no próximo login
    } catch (_) {
      // token indisponível não é erro do paciente
    }
  }
```

No painel "Meus Dados", depois de `updateConsent` com `purpose == ConsentPurpose.segmentedPush && granted` bem-sucedido, chamar a mesma rotina (extraí-la para função de nível de biblioteca que recebe `backend`, `source` e um `mounted`, para os dois pontos de uso). Obter a fonte via um `PushTokenScope` (InheritedWidget no estilo de `QrScannerScope`) montado em `SinalAcsApp`, para não passar por construtores de telas.

- [ ] **Step 3: Rodar e ver passar**

Run: `cd apps/patient && flutter test test/push_registration_test.dart`
Expected: PASS (5).

- [ ] **Step 4: Suíte e commit**

Run: `cd apps/patient && flutter test && flutter analyze`
Expected: tudo verde (185 + 5 = 190), analyze limpo. `cd ../acs && flutter test` continua 172.

```bash
git add apps/patient
git commit -m "feat(paciente): registra o token de push do aparelho quando há consentimento (RF14)"
```

---

### Task 5: Documentação, memória e verificação final

**Files:**
- Modify: `apps/CLAUDE.md` (trocar "failed myData()" pela regra real: login consulta `hasAcceptedCurrentTerms`; registro de push silencioso), `backend/CLAUDE.md` (locks: duas chaves, três namespaces; `push_tokens`; reposicionar a cláusula do lock que está no meio da lista), `PROGRESS.md` (nova seção; corrigir "Aceite do termo no login OTP", que descreve o comportamento antigo de `myData`, e as linhas de "seguem pendentes"), `spec/lgpd_data_audit.md` (entrada de `push_tokens`, recontar tabelas na `definition.sql` da migração mais recente), `spec/PRD_system.md` (linha RF14: lado paciente pronto, envio e Firebase pendentes), `CLAUDE.md` (se citar contagem de tabelas), memória em `~/.claude/projects/-home-rock-Documents-Dev-APPs-SinalACS/memory/` (novo arquivo + linha no `MEMORY.md`).

- [ ] **Step 1: Editar os docs acima** com a contagem real medida (`grep -c 'CREATE TABLE' backend/sinalacs_server/migrations/<mais recente>/definition.sql`) e as contagens finais de testes.

- [ ] **Step 2: Verificação completa**

Run: `cd backend/sinalacs_server && dart test && dart analyze; cd ../../apps/patient && flutter test && flutter analyze; cd ../acs && flutter test && flutter analyze; cd ../.. && ./scripts/qa/ci_invariants.sh; graphify update .`
Expected: backend 348+N, paciente 190, ACS 172, analyzes no baseline/limpos, `ci_invariants` ok.

- [ ] **Step 3: Commit**

```bash
git add PROGRESS.md apps/CLAUDE.md backend/CLAUDE.md spec CLAUDE.md
git commit -m "docs: registra os menores fechados e o registro de push do paciente"
```

---

## Fora desta rodada (por decisão)

- Envio segmentado (`notices.sendSegmented`), tela de avisos do ACS e SDK `firebase_messaging`: dependem do projeto Firebase, que o §3.2 marca como bloqueio externo.
- Apagar tokens no atendimento do pedido de exclusão: pertence ao backoffice que atende os pedidos, ainda inexistente.
- Aviso de 15 dias de mudança dos termos: não escolhido.

## Autorrevisão

- **Cobertura:** minors da rodada 3 → Tasks 1, 3, 5 (aceite simultâneo, locks, rascunho, dois testes, docs). O erro de "Meus dados" fora da tela para quem rolou até o botão é pré-existente e fica de fora, por decisão de escopo. RF14 do lado do paciente → Tasks 2, 4.
- **Placeholders:** os trechos de teste das Tasks 3 e 4 nomeiam helpers e chaves a confirmar lendo os testes vizinhos (indicado em cada passo); nenhum comportamento ficou por definir.
- **Tipos:** `recordConsentUnlessCurrent`, `lockPerSubject`, `PushTokenStore`, `PushDevice`, `registerPushToken` usam o mesmo nome e a mesma assinatura em todas as tasks.
