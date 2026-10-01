# Fechamento das pendências do app paciente — Plano de Implementação

> **Para agentes:** SUB-SKILL OBRIGATÓRIA: use superpowers:subagent-driven-development (recomendado) ou superpowers:executing-plans para executar este plano tarefa a tarefa. Os passos usam checkbox (`- [ ]`).

**Objetivo:** fechar os menores adiados das duas últimas entregas (QR do onboarding, aceite do termo) e as pendências dos direitos do titular (exclusão simultânea, texto de correção perdido, `resourceId` da auditoria de consentimento), sem criar feature nova.

**Arquitetura:** o backend ganha `patients.hasAcceptedCurrentTerms` (um `bool`, sem ler o painel "Meus dados" inteiro), torna `acceptTermsOfUse` idempotente e serializa o pedido de exclusão com um advisory lock do Postgres; o app paciente troca a leitura de `myData()` no login por essa consulta e corrige três arestas de UI; o app do ACS esconde o convite quando ele expira.

**Tech Stack:** Serverpod 3.4.13 (backend), Flutter 3.44 (`apps/patient`, `apps/acs`).

**Spec:** `spec/lgpd_design.md` (LGPD-RF05, RF07, RF08, RF18) e `spec/PRD_system.md` (RF02). Invariante de `CLAUDE.md`: "Red alerts must never be silently dropped".

**Fora do escopo, de propósito:**
- `ipHash`/`userAgent` `nao-aplicavel-<origem>` nas linhas de `consent_logs` do painel: é um marcador de ausência **deliberado** e documentado em `signed_consent_log.dart` (o request HTTP já é auditado em `audit_logs`). Guardar o IP do titular em `consent_logs` seria decisão de privacidade, não um conserto. A Tarefa 4 só corrige o texto do PROGRESS.md, que o chama de "placeholder".
- Backoffice que atende os pedidos, push (RF14) e `healthDataProcessing` sem interruptor: dependem de admin backend/Firebase.

## Global Constraints

- Nunca editar à mão `backend/sinalacs_server/lib/src/generated/`, `backend/sinalacs_client/`, `migrations/` nem `test/integration/test_tools/serverpod_test_tools.dart`; regenerar com `export PATH=$PATH:~/.pub-cache/bin; cd backend/sinalacs_server && serverpod generate`.
- Nenhuma mudança de modelo (`.spy.yaml`): `serverpod create-migration` deve dizer "No changes detected". Se criar migração, algo saiu do plano.
- Sem dado real de paciente em testes, logs ou seed: só valores sintéticos.
- Texto de UI e docs em português. Commits terminam com `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- `flutter analyze` limpo (infos incluídas) em `apps/patient` e `apps/acs`; `dart analyze` do backend fica no baseline de 41 infos.
- Não rodar `dart format` em nenhum `app.dart`.
- Banco de teste: `docker compose --profile test up -d postgres-test`.
- O alerta de urgência nunca espera por aceite, leitura ou timer desta entrega.

## Review Focus

1. **Dois pedidos de exclusão simultâneos** → exatamente uma linha aberta. Teste na Tarefa 1 (integração, `Future.wait`).
2. **Aceite de versão anterior, ou último registro `denied`** → o login mostra o aviso. Testes na Tarefa 1 (regra no serviço) e na Tarefa 2 (fluxo).
3. **`acceptTermsOfUse` chamado de novo já com aceite vigente** → nenhuma linha nova em `consent_logs`. Teste na Tarefa 1.
4. **Envio da correção falha** → ao reabrir o diálogo o texto digitado está lá; some depois de um envio bem-sucedido. Teste na Tarefa 2.
5. **Toque duplo em "Ler QR Code"** → uma leitura só. Teste na Tarefa 2.
6. **Convite expira com a tela aberta** → o QR some e a tela pede um novo; gerar outro zera o aviso. Teste na Tarefa 3.

---

### Tarefa 1: backend — status do aceite, aceite idempotente, exclusão serializada, `resourceId`

**Files:**
- Modify: `backend/sinalacs_server/lib/src/application/patients/data_subject_rights_service.dart`
- Modify: `backend/sinalacs_server/lib/src/infrastructure/database/orm_data_subject_rights_store.dart`
- Modify: `backend/sinalacs_server/lib/src/endpoints/patients_endpoint.dart`
- Regenerar: `lib/src/generated/`, `backend/sinalacs_client/`, `test/integration/test_tools/serverpod_test_tools.dart`
- Test: `backend/sinalacs_server/test/unit/data_subject_rights_service_test.dart`, `backend/sinalacs_server/test/integration/data_subject_rights_endpoint_test.dart`

**Interfaces:**
- Consumes: `ConsentRecordSnapshot({purpose, action, version, timestamp})`, `DataSubjectRequestSnapshot`, `consentPolicyVersion`, `AuditEvent(resourceId:)`.
- Produces:
  - `DataSubjectRightsStore.recordConsent(ConsentLogEntry) → Future<String>` (id da linha gravada; era `Future<void>`).
  - `DataSubjectRightsStore.latestConsent(String userId, ConsentPurpose purpose) → Future<ConsentRecordSnapshot?>` (a de maior `timestamp`).
  - `DataSubjectRightsStore.createDeletionRequestIfNoneOpen({required String userId, required DateTime createdAt, required DateTime dueAt}) → Future<({DataSubjectRequestSnapshot request, bool created})>`.
  - `Future<bool> DataSubjectRightsService.hasAcceptedCurrentTerms(AuthenticatedUser)`.
  - RPC `Future<bool> patients.hasAcceptedCurrentTerms(Session, {required String accessToken})`; no cliente, `client.patients.hasAcceptedCurrentTerms(accessToken: ...)`.

- [ ] **Step 1: Testes de unidade que falham**

Em `test/unit/data_subject_rights_service_test.dart`, primeiro adapte o `FakeDataSubjectRightsStore` à nova interface (isto **não** compila até o Step 3, é esperado):

```dart
class FakeDataSubjectRightsStore implements DataSubjectRightsStore {
  final consents = <ConsentLogEntry>[];
  final requests = <({String userId, DataSubjectRequestSnapshot snapshot})>[];
  var _nextId = 1;

  @override
  Future<String> recordConsent(ConsentLogEntry entry) async {
    consents.add(entry);
    return 'consentimento-${consents.length}';
  }

  @override
  Future<ConsentRecordSnapshot?> latestConsent(String userId, ConsentPurpose purpose) async {
    ConsentLogEntry? latest;
    for (final e in consents) {
      if (e.userId != userId || e.purpose != purpose) continue;
      if (latest == null || e.timestamp.isAfter(latest.timestamp)) latest = e;
    }
    return latest == null
        ? null
        : ConsentRecordSnapshot(
            purpose: latest.purpose.name,
            action: latest.action,
            version: latest.version,
            timestamp: latest.timestamp,
          );
  }

  @override
  Future<({DataSubjectRequestSnapshot request, bool created})> createDeletionRequestIfNoneOpen({
    required String userId,
    required DateTime createdAt,
    required DateTime dueAt,
  }) async {
    final open = await findOpenRequest(userId, DataSubjectRequestType.deletion);
    if (open != null) return (request: open, created: false);
    final created = await createRequest(
      userId: userId,
      type: DataSubjectRequestType.deletion,
      details: null,
      createdAt: createdAt,
      dueAt: dueAt,
    );
    return (request: created, created: true);
  }

  // findOpenRequest e createRequest: como já estão.
}
```

Depois, dentro do grupo `acceptTermsOfUse (LGPD-RF18)` acrescente, e em um grupo novo `hasAcceptedCurrentTerms`, estes testes:

```dart
    test('aceitar de novo com o aceite vigente não grava nada', () async {
      await service.acceptTermsOfUse(_patient);
      final again = await service.acceptTermsOfUse(_patient);

      expect(store.consents, hasLength(1));
      expect(audit.events, hasLength(1));
      expect(again.action, 'granted');
      expect(again.version, consentPolicyVersion);
    });

    test('aceite de versão anterior não conta: grava de novo', () async {
      store.consents.add(ConsentLogEntry(
        userId: _patientId,
        purpose: ConsentPurpose.termsOfUse,
        action: 'granted',
        version: '2025.9',
        timestamp: _now.subtract(const Duration(days: 30)),
      ));

      await service.acceptTermsOfUse(_patient);

      expect(store.consents, hasLength(2));
      expect(store.consents.last.version, consentPolicyVersion);
    });
```

```dart
  group('hasAcceptedCurrentTerms (LGPD-RF18)', () {
    ConsentLogEntry linha(String action, String version, int minutos,
            {ConsentPurpose purpose = ConsentPurpose.termsOfUse}) =>
        ConsentLogEntry(
          userId: _patientId,
          purpose: purpose,
          action: action,
          version: version,
          timestamp: _now.add(Duration(minutes: minutos)),
        );

    test('sem nenhuma linha de termsOfUse, não aceitou', () async {
      expect(await service.hasAcceptedCurrentTerms(_patient), isFalse);
      store.consents.add(linha('granted', consentPolicyVersion, 0, purpose: ConsentPurpose.localReminders));
      expect(await service.hasAcceptedCurrentTerms(_patient), isFalse);
    });

    test('aceite da versão vigente conta', () async {
      store.consents.add(linha('granted', consentPolicyVersion, 0));
      expect(await service.hasAcceptedCurrentTerms(_patient), isTrue);
    });

    test('aceite de versão anterior não conta', () async {
      store.consents.add(linha('granted', '2025.9', 0));
      expect(await service.hasAcceptedCurrentTerms(_patient), isFalse);
    });

    test('vale a linha mais recente, seja qual for a ordem em que foram gravadas', () async {
      store.consents.add(linha('granted', consentPolicyVersion, 5));
      store.consents.add(linha('granted', '2025.9', 0));
      expect(await service.hasAcceptedCurrentTerms(_patient), isTrue);
    });

    test('linha mais recente que não é "granted" não conta', () async {
      store.consents.add(linha('granted', consentPolicyVersion, 0));
      store.consents.add(linha('denied', consentPolicyVersion, 5));
      expect(await service.hasAcceptedCurrentTerms(_patient), isFalse);
    });

    test('só paciente consulta: ACS é recusado', () async {
      await expectLater(service.hasAcceptedCurrentTerms(_acs), throwsA(isA<StateError>()));
    });
  });
```

No grupo `updateConsent (LGPD-RF05)`, acrescente:

```dart
    test('a linha de auditoria aponta para a linha de consentimento gravada', () async {
      await service.updateConsent(_patient, purpose: ConsentPurpose.localReminders, granted: false);

      expect(audit.events.single.resourceId, 'consentimento-1');
    });
```

E, no grupo do pedido de exclusão (procure `requestDeletion` no arquivo e ponha ao lado dos testes existentes):

```dart
    test('pedir exclusão de novo devolve o mesmo pedido e audita a repetição', () async {
      final first = await service.requestDeletion(_patient);
      final second = await service.requestDeletion(_patient);

      expect(second.id, first.id);
      expect(store.requests, hasLength(1));
      expect(audit.events, hasLength(2));
      expect(audit.events.last.resourceId, first.id);
      expect(audit.events.last.result, 'repeated');
    });
```

- [ ] **Step 2: Ver falhar**

Run: `cd backend/sinalacs_server && dart test test/unit/data_subject_rights_service_test.dart`
Expected: FAIL na compilação — o fake implementa métodos que a interface não tem e `hasAcceptedCurrentTerms` não existe.

- [ ] **Step 3: Serviço**

Em `data_subject_rights_service.dart`, na interface `DataSubjectRightsStore`:

- trocar `Future<void> recordConsent(ConsentLogEntry entry);` por `Future<String> recordConsent(ConsentLogEntry entry);` e ajustar o doc: "…devolve o id da linha gravada, que a auditoria usa como `resourceId`.";
- acrescentar:

```dart
  /// A linha mais recente (por `timestamp`) daquela finalidade, ou `null`.
  Future<ConsentRecordSnapshot?> latestConsent(String userId, ConsentPurpose purpose);

  /// Cria o pedido de exclusão **só se** não houver um aberto, de forma atômica:
  /// dois chamadores simultâneos resultam em uma única linha aberta, e o segundo
  /// recebe a do primeiro com `created == false`.
  Future<({DataSubjectRequestSnapshot request, bool created})> createDeletionRequestIfNoneOpen({
    required String userId,
    required DateTime createdAt,
    required DateTime dueAt,
  });
```

No serviço:

```dart
  bool _isCurrentAcceptance(ConsentRecordSnapshot? latest) =>
      latest != null && latest.action == 'granted' && latest.version == consentPolicyVersion;

  /// `true` quando a linha mais recente de `termsOfUse` é um `granted` na versão
  /// vigente (LGPD-RF18). É o que o app consulta depois do login por OTP: um
  /// `bool`, em vez do painel "Meus dados" inteiro — que também gravaria uma
  /// linha de auditoria de leitura a cada login.
  Future<bool> hasAcceptedCurrentTerms(AuthenticatedUser user) async {
    _requirePatient(user);
    return _isCurrentAcceptance(await _store.latestConsent(user.id, ConsentPurpose.termsOfUse));
  }
```

`acceptTermsOfUse` passa a ser idempotente:

```dart
  Future<ConsentRecordSnapshot> acceptTermsOfUse(AuthenticatedUser user) async {
    _requirePatient(user);
    final latest = await _store.latestConsent(user.id, ConsentPurpose.termsOfUse);
    if (latest != null && _isCurrentAcceptance(latest)) return latest;
    return _record(user, purpose: ConsentPurpose.termsOfUse, action: 'granted');
  }
```

Em `_record`, guardar o id e passá-lo à auditoria: `final id = await _store.recordConsent(...)` e `AuditEvent(..., resourceType: 'consent_log', resourceId: id, result: 'granted')`.

`requestDeletion` passa a usar a operação atômica e a auditar também a repetição:

```dart
  Future<DataSubjectRequestSnapshot> requestDeletion(AuthenticatedUser user) async {
    _requirePatient(user);
    final now = _clock().toUtc();
    final result = await _store.createDeletionRequestIfNoneOpen(
      userId: user.id,
      createdAt: now,
      dueAt: now.add(dataSubjectRequestDeadline),
    );
    await _audit.recordSafely(AuditEvent(
      userId: user.id,
      actionType: 'write',
      resourceType: 'data_subject_request',
      resourceId: result.request.id,
      result: result.created ? 'granted' : 'repeated',
    ));
    return result.request;
  }
```

`_create` continua servindo só à correção. Se `findOpenRequest` ficar sem chamador no serviço, mantenha-o só se o fake ou o store ainda o usam; senão remova-o da interface, do ORM e do fake (rode `grep -rn findOpenRequest backend/`).

- [ ] **Step 4: Store ORM**

Em `orm_data_subject_rights_store.dart`:

```dart
  @override
  Future<String> recordConsent(ConsentLogEntry entry) async {
    final row = await ConsentLog.db.insertRow(
      _session(),
      signedConsentLog(entry, signature: _signature, origin: 'painel-titular'),
    );
    return row.id!.toString();
  }

  @override
  Future<ConsentRecordSnapshot?> latestConsent(String userId, ConsentPurpose purpose) async {
    final row = await ConsentLog.db.findFirstRow(
      _session(),
      where: (t) => t.userId.equals(UuidValue.fromString(userId)) & t.purpose.equals(purpose.name),
      orderBy: (t) => t.timestamp,
      orderDescending: true,
    );
    return row == null
        ? null
        : ConsentRecordSnapshot(
            purpose: row.purpose,
            action: row.action,
            version: row.version,
            timestamp: row.timestamp,
          );
  }

  /// Serializa por titular com `pg_advisory_xact_lock`, o mesmo recurso que
  /// `OrmAuditTrail` usa para a cadeia: o Serverpod não declara `WHERE` em
  /// índice, então um índice único parcial ("um pedido aberto por titular")
  /// não é possível. O lock solta sozinho no fim da transação.
  @override
  Future<({DataSubjectRequestSnapshot request, bool created})> createDeletionRequestIfNoneOpen({
    required String userId,
    required DateTime createdAt,
    required DateTime dueAt,
  }) async {
    final session = _session();
    final userUuid = UuidValue.fromString(userId);
    final encrypted = await _cipher.encryptJson(null);
    return session.db.transaction((transaction) async {
      await session.db.unsafeExecute(
        'SELECT pg_advisory_xact_lock(hashtext(@key));',
        parameters: QueryParameters.named({'key': 'exclusao:$userId'}),
        transaction: transaction,
      );
      final open = await DataSubjectRequest.db.findFirstRow(
        session,
        where: (t) =>
            t.userId.equals(userUuid) &
            t.requestType.equals(DataSubjectRequestType.deletion) &
            t.status.equals(DataSubjectRequestStatus.open),
        orderBy: (t) => t.createdAt,
        orderDescending: true,
        transaction: transaction,
      );
      if (open != null) {
        return (request: dataSubjectRequestSnapshotOf(open, _cipher), created: false);
      }
      final row = await DataSubjectRequest.db.insertRow(
        session,
        DataSubjectRequest(
          userId: userUuid,
          requestType: DataSubjectRequestType.deletion,
          detailsEncrypted: encrypted.ciphertextBase64,
          detailsKeyVersion: encrypted.keyVersion,
          status: DataSubjectRequestStatus.open,
          createdAt: createdAt,
          dueAt: dueAt,
        ),
        transaction: transaction,
      );
      return (request: dataSubjectRequestSnapshotOf(row, _cipher), created: true);
    });
  }
```

Se `dataSubjectRequestSnapshotOf` for assíncrono ou tiver outra assinatura, siga a que `findOpenRequest` usa hoje. `ConsentRecordSnapshot` já é importado ali? Se não, importe de `patient_data_overview_service.dart`.

- [ ] **Step 5: Endpoint e regeneração**

Em `patients_endpoint.dart`, logo depois de `acceptTermsOfUse`:

```dart
  /// Se o paciente já aceitou o Termo de Uso e a Política de Privacidade da
  /// versão vigente (LGPD-RF18). O app consulta depois do login por OTP para
  /// decidir se mostra o convite ao aceite — um `bool`, sem ler o painel
  /// "Meus dados". Não grava auditoria: devolve ao próprio titular um fato
  /// sobre o consentimento dele.
  Future<bool> hasAcceptedCurrentTerms(
    Session session, {
    required String accessToken,
  }) async {
    final user = authenticate(accessToken);

    try {
      return await AlertRuntime.instance
          .dataSubjectRightsServiceFor(session)
          .hasAcceptedCurrentTerms(user);
    } on StateError catch (error) {
      throw AlertPermissionException(message: error.message);
    }
  }
```

Run: `export PATH=$PATH:~/.pub-cache/bin; cd backend/sinalacs_server && serverpod generate && serverpod create-migration`
Expected: geração sem erro; "No changes detected".

- [ ] **Step 6: Testes de integração**

Em `test/integration/data_subject_rights_endpoint_test.dart`, junto dos testes de `acceptTermsOfUse` (mesmo `withServerpod` de rollback):

```dart
    test('hasAcceptedCurrentTerms: falso antes, verdadeiro depois de aceitar', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final token = await patientToken();

      expect(await endpoints.patients.hasAcceptedCurrentTerms(sessionBuilder, accessToken: token), isFalse);
      await endpoints.patients.acceptTermsOfUse(sessionBuilder, accessToken: token);
      expect(await endpoints.patients.hasAcceptedCurrentTerms(sessionBuilder, accessToken: token), isTrue);
    });

    test('hasAcceptedCurrentTerms recusa token de ACS', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final acsToken =
          (await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs')).accessToken;

      await expectLater(
        endpoints.patients.hasAcceptedCurrentTerms(sessionBuilder, accessToken: acsToken),
        throwsA(isA<AlertPermissionException>()),
      );
    });

    test('acceptTermsOfUse duas vezes grava uma linha só', () async {
      final session = sessionBuilder.build();
      await _seed(session);
      final token = await patientToken();

      await endpoints.patients.acceptTermsOfUse(sessionBuilder, accessToken: token);
      await endpoints.patients.acceptTermsOfUse(sessionBuilder, accessToken: token);

      expect(await ConsentLog.db.count(session), 1);
    });
```

E, **no fim do arquivo**, um grupo novo com `rollbackDatabase: RollbackDatabase.disabled`, copiando o formato de `onboarding_endpoint_test.dart` (o grupo que termina na linha ~518: `_seedRace`/`_cleanupRace`, `try`/`finally` com limpeza manual). Leia aquele grupo antes e reproduza a semeadura e a limpeza, acrescentando à limpeza as linhas de `DataSubjectRequest` do paciente. O teste:

```dart
      test('dois pedidos de exclusão simultâneos deixam um só pedido aberto', () async {
        final session = sessionBuilder.build();
        try {
          // (semear como o grupo de corrida do onboarding: Ubs, MicroArea, User paciente)
          final token =
              (await endpoints.auth.developmentLogin(sessionBuilder, role: 'patient')).accessToken;

          Future<Object> attempt() async {
            try {
              return await endpoints.patients.requestDataDeletion(sessionBuilder, accessToken: token);
            } catch (error) {
              return error;
            }
          }

          final results = await Future.wait([attempt(), attempt(), attempt()]);

          expect(results.whereType<PatientDataSubjectRequestRecord>(), hasLength(3),
              reason: 'as três chamadas devem responder com um pedido, sem erro');
          final open = await DataSubjectRequest.db.find(
            session,
            where: (t) =>
                t.userId.equals(UuidValue.fromString(_patientId)) &
                t.requestType.equals(DataSubjectRequestType.deletion) &
                t.status.equals(DataSubjectRequestStatus.open),
          );
          expect(open, hasLength(1));
        } finally {
          // (limpeza manual, como o grupo de corrida do onboarding)
        }
      });
```

Se o token de `developmentLogin` depender de uma linha semeada com id fixo (`_patientId`), use o mesmo `_seed` do arquivo dentro do `try` e limpe o que ele criou.

- [ ] **Step 7: Ver o RED da corrida, depois passar**

Antes do Step 4 aplicado (ou revertendo-o temporariamente com `git stash` no ORM), rode `dart test test/integration/data_subject_rights_endpoint_test.dart --name "simultâneos"` algumas vezes: sem o lock, o esperado é `Expected: <1>, Actual: <2 ou 3>`. **Se nunca falhar, registre no ledger que o RED da corrida não foi observável e siga — o teste fica como guarda de regressão.**

Run: `cd backend/sinalacs_server && docker compose --profile test up -d postgres-test && dart test`
Expected: PASS, tudo verde (333 + os novos).

- [ ] **Step 8: Commit**

```bash
git add backend/sinalacs_server backend/sinalacs_client
git commit -m "feat(backend): status do aceite sem ler o painel, aceite idempotente, exclusão serializada (LGPD-RF08/RF18)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Tarefa 2: app paciente — status do aceite, câmera, erro do QR, correção e testes

**Files:**
- Modify: `apps/patient/lib/core/network/backend_client.dart`
- Modify: `apps/patient/lib/app/app.dart`
- Delete: `apps/patient/lib/core/legal/terms_acceptance.dart`, `apps/patient/test/terms_acceptance_test.dart` (a regra passou para o servidor e é testada na Tarefa 1)
- Modify: `apps/patient/test/support/fake_patient_backend.dart`, `apps/patient/test/terms_gate_flow_test.dart`, `apps/patient/test/patient_app_mvp_test.dart`, `apps/patient/test/onboarding_flow_test.dart`

**Interfaces:**
- Consumes: `client.patients.hasAcceptedCurrentTerms(accessToken:)` da Tarefa 1; `legalDocumentsVersion`.
- Produces: `Future<bool> PatientBackend.hasAcceptedCurrentTerms()`; no fake `termsAccepted` (bool, padrão `true`), `termsStatusCalls`, `termsStatusFailure`, `termsStatusGate`.

- [ ] **Step 1: Testes que falham**

**Fake** (`test/support/fake_patient_backend.dart`), acrescente `import 'package:sinalacs_patient/core/legal/legal_documents.dart';` e:

```dart
  /// O que o servidor responderia a [hasAcceptedCurrentTerms].
  bool termsAccepted = true;
  int termsStatusCalls = 0;
  BackendFailure? termsStatusFailure;

  /// Quando definido, [hasAcceptedCurrentTerms] só responde depois que ele
  /// completa — simula um backend lento ou pendurado.
  Completer<void>? termsStatusGate;

  @override
  Future<bool> hasAcceptedCurrentTerms() async {
    termsStatusCalls++;
    await termsStatusGate?.future;
    final failure = termsStatusFailure;
    if (failure != null) throw failure;
    return termsAccepted;
  }
```

Ajustes no mesmo fake: remover `myDataGate` e o `await myDataGate?.future;` de `myData()` (a Tarefa 2 do plano anterior o criou; agora quem trava é `termsStatusGate`); voltar `consents:` do `myDataResult` padrão a `const []`; trocar todo `'2026.1'` por `legalDocumentsVersion` (em `updateConsent` e em `acceptTermsOfUse`); e em `acceptTermsOfUse` acrescentar `termsAccepted = true;` antes do `return record;`.

**`terms_gate_flow_test.dart`**: troque `semAceite()` por

```dart
FakePatientBackend semAceite() => FakePatientBackend()..termsAccepted = false;
```

e ajuste os testes que dependiam de `myData`: no de "falha ao ler os consentimentos", use `semAceite()..termsStatusFailure = const BackendFailure('sem rede')`; no da leitura pendurada, `semAceite()..termsStatusGate = Completer<void>()`; no "já aceitou a versão vigente", troque as asserções por `expect(backend.termsStatusCalls, 1); expect(backend.myDataCallCount, 0);`. Acrescente:

```dart
  testWidgets('"Agora não" leva à tela inicial e nada é gravado', (tester) async {
    final backend = semAceite();
    await tester.pumpWidget(SinalAcsApp(backend: backend));
    await login(tester);

    await tapKey(tester, 'terms_gate_later_button');

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(backend.acceptTermsCalls, 0);
  });

  testWidgets('quem tocou "Agora não" vê o aviso de novo no login seguinte', (tester) async {
    final backend = semAceite();
    await tester.pumpWidget(SinalAcsApp(backend: backend));
    await login(tester);
    await tapKey(tester, 'terms_gate_later_button');
    expect(find.byType(NavigationBar), findsOneWidget);

    // Novo início do app sobre o mesmo backend: a árvore é refeita do zero.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(SinalAcsApp(backend: backend));
    await login(tester);

    expect(find.byKey(const Key('terms_gate_accept_button')), findsOneWidget);
    expect(backend.acceptTermsCalls, 0);
  });
```

**`patient_app_mvp_test.dart`**: desfazer o remendo do plano anterior. Em `openMyData`, remover o bloco `final later = find.byKey(const Key('terms_gate_later_button')); if (...) {...}` e o comentário dele; e voltar `expect(backend.myDataCallCount, 2);` (teste "mostra o cadastro e as condições crônicas…") para `1`, removendo o comentário "Uma leitura do login…". Como o login já não lê `myData()`, os 23 testes do grupo voltam a passar sem o remendo.

Dentro do grupo `Meus dados (LGPD)`, ao lado de "correção: só envia com texto de verdade…":

```dart
    testWidgets('correção que falhou volta com o texto ao reabrir; sai do rascunho depois de enviada', (tester) async {
      final backend = FakePatientBackend()
        ..myDataResult = overview()
        ..dataRequestFailure = const BackendFailure('Sem conexão com o servidor.');
      await pumpMyData(tester, backend);

      await tapByKey(tester, 'request_correction_button');
      await tester.enterText(find.byKey(const Key('correction_details_field')), 'Meu contato mudou.');
      await tester.tap(find.byKey(const Key('correction_request_submit')));
      await tester.pumpAndSettle();
      expect(find.text('Sem conexão com o servidor.'), findsOneWidget);

      backend.dataRequestFailure = null;
      await tapByKey(tester, 'request_correction_button');
      expect(
        tester.widget<TextField>(find.byKey(const Key('correction_details_field'))).controller!.text,
        'Meu contato mudou.',
      );
      await tester.tap(find.byKey(const Key('correction_request_submit')));
      await tester.pumpAndSettle();
      expect(backend.correctionRequests, ['Meu contato mudou.']);

      await tapByKey(tester, 'request_correction_button');
      expect(
        tester.widget<TextField>(find.byKey(const Key('correction_details_field'))).controller!.text,
        isEmpty,
      );
    });
```

**`onboarding_flow_test.dart`**, ao final de `main()`:

```dart
  testWidgets('toque duplo em "Ler QR Code" abre uma leitura só', (tester) async {
    final gate = Completer<String?>();
    var calls = 0;
    await tester.pumpWidget(SinalAcsApp(
      backend: FakePatientBackend(),
      qrScanner: (_) {
        calls++;
        return gate.future;
      },
    ));
    await openOnboarding(tester);

    await tester.tap(find.byKey(const Key('scan_qr_button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('scan_qr_button')), warnIfMissed: false);
    await tester.pump();
    expect(calls, 1);

    gate.complete(null);
    await tester.pumpAndSettle();
    await tapKey(tester, 'scan_qr_button');
    expect(calls, 2, reason: 'depois de voltar, dá para ler de novo');
  });

  testWidgets('o aviso do QR some quando a pessoa volta a digitar', (tester) async {
    await tester.pumpWidget(SinalAcsApp(
      backend: FakePatientBackend(),
      qrScanner: (_) async => 'https://exemplo.invalid/pagina',
    ));
    await openOnboarding(tester);
    await tapKey(tester, 'scan_qr_button');
    expect(find.textContaining('não é um convite do SinalACS'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('onboarding_token_field')), 'convite-123');
    await tester.pump();

    expect(find.textContaining('não é um convite do SinalACS'), findsNothing);
  });
```

(`import 'dart:async';` no topo, se ainda não houver.)

- [ ] **Step 2: Ver falhar**

Run: `cd apps/patient && flutter test test/terms_gate_flow_test.dart test/onboarding_flow_test.dart test/patient_app_mvp_test.dart`
Expected: FAIL — `hasAcceptedCurrentTerms` não existe em `PatientBackend`; depois de compilar, os testes de toque duplo, aviso do QR e correção falham.

- [ ] **Step 3: Camada de rede**

Em `backend_client.dart`: na interface, depois de `acceptTermsOfUse`:

```dart
  /// Se o paciente já aceitou o Termo de Uso e a Política de Privacidade da
  /// versão vigente (LGPD-RF18). O login por OTP consulta isto para decidir se
  /// mostra o convite ao aceite.
  Future<bool> hasAcceptedCurrentTerms();
```

`MisconfiguredBackend`: `@override Future<bool> hasAcceptedCurrentTerms() async => _recusar();`. `BackendClient`:

```dart
  @override
  Future<bool> hasAcceptedCurrentTerms() async {
    final token = await _requireToken();
    return _guard(() => _client.patients.hasAcceptedCurrentTerms(accessToken: token));
  }
```

- [ ] **Step 4: `app.dart`**

1. Login: em `_needsTerms`, trocar o corpo do `try` por

```dart
      final accepted =
          await BackendScope.of(context).hasAcceptedCurrentTerms().timeout(_termsCheckTimeout);
      return !accepted;
```

   e remover `import 'package:sinalacs_patient/core/legal/terms_acceptance.dart';`. Apagar `lib/core/legal/terms_acceptance.dart` e `test/terms_acceptance_test.dart` (`git rm`).

2. Onboarding, em `_OnboardingScreenState`: campo `bool _scanning = false;`; o botão passa a `onPressed: _busy || _scanning ? null : _scan,`; `_scan` marca e libera:

```dart
  Future<void> _scan() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    try {
      await _readQr();
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }
```

   com o corpo atual de `_scan` renomeado para `Future<void> _readQr() async { ... }` (sem mudar nada dentro). No `onChanged` do campo `onboarding_token_field`, trocar `(_) => setState(() {})` por `(_) => setState(() => _error = null)`.

3. Correção, na tela "Meus dados": campo `String? _pendingCorrection;`. `_submitRequest` passa a devolver `Future<bool>` (`true` só quando a chamada não lançou `BackendFailure`; os `return` de dentro do `try`/`catch` viram `return true`/`return false`, mantendo o `finally`). `_requestCorrection`:

```dart
  Future<void> _requestCorrection() async {
    if (_busy) return;
    final details = await showDialog<String>(
      context: context,
      builder: (_) => _CorrectionRequestDialog(initialText: _pendingCorrection),
    );
    if (details == null || !mounted) {
      // Cancelou de propósito: o rascunho não fica para trás.
      _pendingCorrection = null;
      return;
    }
    // Guardado até o servidor aceitar: se o envio falhar, o texto volta quando
    // a pessoa reabrir o diálogo, em vez de ser digitado de novo.
    _pendingCorrection = details;
    final ok = await _submitRequest(
      (backend) => backend.requestDataCorrection(details),
      'Pedido de correção registrado',
    );
    if (ok) _pendingCorrection = null;
  }
```

   `_CorrectionRequestDialog` ganha `const _CorrectionRequestDialog({this.initialText});` e `final String? initialText;`, e o estado inicia `final _controller = TextEditingController();` por `late final _controller = TextEditingController(text: widget.initialText);`.

- [ ] **Step 5: Ver passar**

Run: `cd apps/patient && flutter analyze && flutter test`
Expected: `No issues found!`, suíte verde. Se algum teste antigo contava `myDataCallCount` ou linhas de consentimento por causa do remendo desfeito, ajuste e registre no ledger.

- [ ] **Step 6: Commit**

```bash
git add apps/patient
git commit -m "fix(paciente): login consulta só o status do aceite; toque duplo na câmera, aviso do QR e texto de correção

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Tarefa 3: app do ACS — convite expirado some da tela

**Files:**
- Modify: `apps/acs/lib/app/invite_screen.dart`
- Modify: `apps/acs/test/support/fakes.dart` (`generateInvite`)
- Test: `apps/acs/test/invite_screen_test.dart`

**Interfaces:**
- Consumes: `EnrollmentTokenResult({token, expiresAt})`.
- Produces: tela que esconde o QR e o código quando `expiresAt` passa, com `Key('invite_expired')`.

- [ ] **Step 1: Teste que falha**

Em `test/support/fakes.dart`, `generateInvite` devolve hoje `expiresAt: DateTime.utc(2026, 9, 29, 10, 15)`, uma data fixa que a tela vai passar a comparar com o relógio. Troque por um prazo relativo, configurável:

```dart
  /// Validade do convite devolvido por `generateInvite`, contada de agora.
  Duration inviteLifetime = const Duration(minutes: 15);
```

e `expiresAt: DateTime.now().toUtc().add(inviteLifetime),`. Os testes existentes que afirmam o texto `Válido até HH:MM` devem passar a calcular o esperado a partir do valor devolvido (leia `invite_screen_test.dart` e ajuste as asserções de horário; registre no ledger).

Acrescente em `test/invite_screen_test.dart`:

```dart
  testWidgets('convite que expira com a tela aberta some e pede um novo', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = backendComPacientes()..inviteLifetime = const Duration(minutes: 15);
    await tester.pumpWidget(
      SinalAcsApp(backend: backend, feedBuilder: (queue) => FakeAlertFeed(queue)),
    );
    await entrar(tester);
    await abrirConvite(tester);
    await tapKey(tester, 'invite_patient_${syntheticPatientId(5)}');
    await tapKey(tester, 'generate_invite_button');
    expect(find.byType(QrImageView), findsOneWidget);

    await tester.pump(const Duration(minutes: 15, seconds: 1));

    expect(find.byType(QrImageView), findsNothing);
    expect(find.byKey(const Key('invite_token_text')), findsNothing);
    expect(find.byKey(const Key('invite_expired')), findsOneWidget);

    await tapKey(tester, 'generate_invite_button');
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.byKey(const Key('invite_expired')), findsNothing);
  });

  testWidgets('trocar de paciente cancela o aviso de expiração do convite anterior', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = backendComPacientes();
    await tester.pumpWidget(
      SinalAcsApp(backend: backend, feedBuilder: (queue) => FakeAlertFeed(queue)),
    );
    await entrar(tester);
    await abrirConvite(tester);
    await tapKey(tester, 'invite_patient_${syntheticPatientId(5)}');
    await tapKey(tester, 'generate_invite_button');
    await tapKey(tester, 'invite_patient_${syntheticPatientId(6)}');

    await tester.pump(const Duration(minutes: 16));

    expect(find.byKey(const Key('invite_expired')), findsNothing,
        reason: 'o convite já tinha saído da tela; nada a avisar');
  });
```

- [ ] **Step 2: Ver falhar**

Run: `cd apps/acs && flutter test test/invite_screen_test.dart`
Expected: FAIL — o QR continua na tela depois de 15 min, e `invite_expired` não existe.

- [ ] **Step 3: Implementação**

Em `invite_screen.dart`: `import 'dart:async';`; no estado, `Timer? _expiryTimer;` e `bool _expired = false;`.

```dart
  void _clearExpiry() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _expired = false;
  }

  /// Agenda o aviso para o instante em que o convite deixa de valer. O relógio
  /// do aparelho pode estar errado: o servidor é quem recusa um convite
  /// expirado, e isto só evita deixar um QR morto na tela como se valesse.
  void _watchExpiry(DateTime expiresAt) {
    _clearExpiry();
    final remaining = expiresAt.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      _expired = true;
      return;
    }
    _expiryTimer = Timer(remaining, () {
      if (mounted) setState(() => _expired = true);
    });
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }
```

(Se já existir um `dispose`, acrescente só o `cancel`.) Chamadas: em `_select`, dentro do `if (_selected?.patientId != patient.patientId)`, além de `_invite = null`, `_clearExpiry();`. Em `_generate`, no ramo em que `_invite = invite` é aceito, `_watchExpiry(invite.expiresAt);`; no `on BackendFailure`, `_clearExpiry();` junto de `_invite = null`. Em `build`, `final invite = _invite;` passa a ser usado assim: o bloco `if (invite != null && _selected != null) ...[` fica `if (invite != null && _selected != null && !_expired) ...[`, e logo antes dele:

```dart
        if (invite != null && _expired)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Semantics(
              liveRegion: true,
              child: const Text(
                'O convite expirou. Gere um novo.',
                key: Key('invite_expired'),
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
```

- [ ] **Step 4: Ver passar, suíte e commit**

Run: `cd apps/acs && flutter analyze && flutter test`
Expected: `No issues found!`, suíte verde.

```bash
git add apps/acs
git commit -m "fix(acs): convite expirado some da tela e pede um novo

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Tarefa 4: Documentação e registro

**Files:**
- Modify: `PROGRESS.md`, `apps/CLAUDE.md`, `backend/CLAUDE.md`

**Interfaces:** Consumes: tudo acima. Produces: nada de código.

- [ ] **Step 1: apps/CLAUDE.md e backend/CLAUDE.md**

Em `apps/CLAUDE.md`, no parágrafo do login do paciente, trocar "the app reads `myData()` and, when the latest `termsOfUse` consent row is not `granted` in `legalDocumentsVersion`, shows `TermsAcceptanceScreen`" por "the app asks `patients.hasAcceptedCurrentTerms` (a `bool` — not the whole \"Meus dados\" panel, which would write a read-audit row on every login) with a 3 s timeout and, when the answer is `false`, shows `TermsAcceptanceScreen`". Em `backend/CLAUDE.md`, na entrada de `patients.acceptTermsOfUse`, acrescentar "idempotente (aceite vigente já gravado devolve a linha existente) e `patients.hasAcceptedCurrentTerms` (o `bool` que o login consulta)"; e onde falar de `requestDataDeletion`, se falar, que a criação é serializada por `pg_advisory_xact_lock` por titular.

- [ ] **Step 2: PROGRESS.md**

Na seção "Direitos do titular…", trocar o item "Corrida de dois pedidos de exclusão simultâneos…" por uma nota "**Resolvido (2026-09-29):** a criação passou a ser atômica (`createDeletionRequestIfNoneOpen`, advisory lock por titular)". Na seção "QR Code do onboarding e documentos legais", nos bullets "não há mecanismo de reaceite no login" e "Falta um aceite no primeiro login", acrescentar "— **resolvido**, ver 'Aceite do termo no login OTP'". Onde o PROGRESS.md chama `ipHash` de "placeholder", trocar por "marcador deliberado de ausência (`nao-aplicavel-painel-titular`, ver `signed_consent_log.dart`)". Ao final, uma seção `## Fechamento das pendências do paciente (2026-09-29)` com: o que foi fechado (status do aceite sem ler o painel, aceite idempotente, exclusão serializada, `resourceId` da auditoria de consentimento e auditoria da repetição da exclusão, toque duplo na câmera, aviso do QR, texto de correção, convite expirado no ACS, lacunas de teste), o que ficou de fora de propósito (o marcador `nao-aplicavel-*` de `consent_logs`; admin backend; push RF14) e as contagens reais de teste (rode as três suítes e copie os números).

- [ ] **Step 3: Verificações e commit**

Run:
```bash
./scripts/qa/ci_invariants.sh
graphify update .
```
Expected: invariantes OK; grafo atualizado.

```bash
git add PROGRESS.md apps/CLAUDE.md backend/CLAUDE.md
git commit -m "docs: registra o fechamento das pendências do app paciente

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```
