# Menores do push e aviso de 15 dias de mudança dos termos — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fechar os menores adiados da rodada 4 (revogação atômica, auditoria da troca de dono, teto de tokens, testes que faltam, `maybeOf`, regra de aceite duplicada) e entregar o aviso, dentro do app, de 15 dias antes de uma nova versão dos termos valer (LGPD-RF18).

**Architecture:** A revogação de `segmentedPush` passa a gravar o `denied` e apagar os tokens na mesma transação, sob o lock por titular que o registro já usa. O aviso de mudança é um agendamento constante no servidor (`TermsChangeSchedule`, hoje vazio) que se recusa a existir com menos de 15 dias entre publicação e vigência; `patients.termsChangeNotice` devolve o aviso ativo e o app o mostra como um cartão dispensável na home, sem nunca bloquear nada.

**Tech Stack:** Serverpod 3.4.13 (`serverpod generate` + `create-migration`), Postgres com `pg_advisory_xact_lock`, Flutter 3.44, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md` §2 e §3.2; `spec/lgpd_design.md` (LGPD-RF18: "aviso de mudança com 15 dias de antecedência e novo aceite quando a versão mudar").

## Global Constraints

- Regenerar com `export PATH=$PATH:~/.pub-cache/bin; cd backend/sinalacs_server && serverpod generate && serverpod create-migration`. Testes de integração: `docker compose --profile test up -d postgres-test`.
- `flutter analyze` limpo nos dois apps, infos incluídas. `dart analyze` do backend no baseline de 44 infos (avisos: zero).
- Alerta vermelho nunca é descartado nem atrasado: aviso de termos e registro de push nunca bloqueiam login, home nem o botão de urgência; falha ou lentidão vira "sem aviso".
- `userId` vem sempre de `user.id` (INV-05). Textos de UI e comentários em português. Nenhum dado real em testes.
- Testes de integração sem rollback usam ids próprios (`9300…`) e `enrollmentId` próprio, e limpam à mão; o seed de `ACS-001` derruba outros arquivos em paralelo.
- `legalDocumentsVersion` (app) continua igual a `consentPolicyVersion` (backend); esta rodada não troca a versão.

## Review Focus

- Notice cuja vigência é antes de 15 dias da publicação: o servidor se recusa a construí-la.
- Relógio do servidor exatamente na publicação e exatamente na vigência: aviso ativo na primeira, ausente na segunda (a partir daí vale o convite ao aceite).
- Servidor lento ou fora do ar ao buscar o aviso: a home abre normalmente, sem cartão e sem erro.
- Revogar `segmentedPush` com falha ao apagar tokens: nem o `denied` fica gravado (tudo ou nada).
- Mais de 10 tokens de um titular: o mais antigo sai, o registro novo entra, e o titular nunca é recusado por isso.

---

## Mapa de arquivos

- Backend criar: `lib/src/application/patients/terms_change_schedule.dart`, `lib/src/models/api/terms_change_notice.spy.yaml` (confirmar a pasta onde ficam os outros DTOs de `models/api/`), `test/unit/terms_change_schedule_test.dart`.
- Backend modificar: `data_subject_rights_service.dart`, `push_token_service.dart`, `orm_data_subject_rights_store.dart`, `orm_push_token_store.dart`, `subject_lock.dart` (sem mudança de namespace), `patients_endpoint.dart`, `devices_endpoint.dart`, `alert_runtime.dart`, `test/unit/data_subject_rights_service_test.dart`, `test/unit/push_token_service_test.dart`, `test/integration/push_token_endpoint_test.dart`.
- Paciente criar: `lib/core/legal/terms_change_notice_card.dart`, `test/terms_change_notice_test.dart`.
- Paciente modificar: `lib/core/push/push_token_source.dart`, `lib/core/network/backend_client.dart`, `lib/app/app.dart`, `test/support/fake_patient_backend.dart`, `test/push_registration_test.dart`.
- Docs: `PROGRESS.md`, `apps/CLAUDE.md`, `backend/CLAUDE.md`, `spec/lgpd_design.md`, `spec/lgpd_data_audit.md`, memória.

---

### Task 1: Revogação atômica, resultado do registro, teto de tokens e auditoria (backend)

**Files:**
- Modify: `lib/src/application/patients/data_subject_rights_service.dart`, `push_token_service.dart`, `lib/src/infrastructure/database/orm_data_subject_rights_store.dart`, `orm_push_token_store.dart`, `lib/src/runtime/alert_runtime.dart`, `lib/src/endpoints/devices_endpoint.dart`
- Test: `test/unit/data_subject_rights_service_test.dart`, `test/unit/push_token_service_test.dart`, `test/integration/push_token_endpoint_test.dart`

**Interfaces:**
- Produces: `enum PushRegistration { registered, ownerChanged, refused }` em `push_token_service.dart`.
- Produces: `PushTokenStore.registerIfConsented(...) → Future<PushRegistration>` (era `Future<bool>`); mesmos parâmetros.
- Produces: `DataSubjectRightsStore.recordConsentRevokingPush(ConsentLogEntry entry) → Future<String>`: numa transação sob `lockPerSubject(namespace: lockNamespacePushToken, key: userId)`, grava o `entry` e apaga os tokens do titular; devolve o id da linha de consentimento.
- Produces: `const int maxPushTokensPerUser = 10;` em `push_token_service.dart`.
- Consumes: `lockPerSubject`, `lockNamespacePushToken`, `lockNamespacePushTokenRow`, `signedConsentLog`.

- [ ] **Step 1: Testes unitários vermelhos**

Em `data_subject_rights_service_test.dart`, o fake store ganha `recordConsentRevokingPush` (registra em `consents` e incrementa `revokingPushCalls`), e o teste `'só a revogação de segmentedPush chama deleteAllFor'` do grupo de push vira:

```dart
test('revogar segmentedPush usa a gravação atômica; o resto usa recordConsent', () async {
  await service.updateConsent(_patient, purpose: ConsentPurpose.segmentedPush, granted: true);
  await service.updateConsent(_patient, purpose: ConsentPurpose.localReminders, granted: false);
  expect(store.revokingPushCalls, 0);

  await service.updateConsent(_patient, purpose: ConsentPurpose.segmentedPush, granted: false);
  expect(store.revokingPushCalls, 1);
  expect(store.consents.last.action, 'denied');
  expect(audit.events.last.resourceType, 'consent_log');
});
```

Remova o parâmetro `pushTokens` e a classe `FakePushTokenStore` desse arquivo. Em `push_token_service_test.dart`, o fake devolve `PushRegistration` e há três testes novos:

```dart
test('troca de dono é auditada, primeiro registro e repetição não', () async {
  await service.register(_patient, token: 'tok-1', platform: 'android');
  await service.register(_patient, token: 'tok-1', platform: 'android');
  expect(audit.events, isEmpty);

  await service.register(_otherPatient, token: 'tok-1', platform: 'android');
  expect(audit.events.single.resourceType, 'push_token');
  expect(audit.events.single.userId, _otherPatient.id);
});

test('recusa por falta de consentimento não é auditada e lança', () async {
  store.consent = false;
  await expectLater(
    service.register(_patient, token: 'tok-1', platform: 'android'),
    throwsA(isA<DataRightsException>()),
  );
  expect(audit.events, isEmpty);
});
```

(O `_FakePushTokenStore` decide `ownerChanged` quando a linha já existe com outro `userId`. `PushTokenService` passa a receber `AuditTrail audit`, e o `setUp` usa o `FakeAuditTrail` de `data_subject_rights_service_test.dart`, copiado para o arquivo ou movido para `test/support/fake_audit_trail.dart`.)

Run: `cd backend/sinalacs_server && dart test test/unit/data_subject_rights_service_test.dart test/unit/push_token_service_test.dart`
Expected: FAIL — `recordConsentRevokingPush`, `PushRegistration` e o parâmetro `audit` não existem.

- [ ] **Step 2: Implementar serviços**

`push_token_service.dart`:

```dart
/// Desfecho de [PushTokenStore.registerIfConsented].
enum PushRegistration { registered, ownerChanged, refused }

/// Teto de aparelhos por titular. Passou do teto, o token mais antigo sai: quem
/// troca de celular nunca é recusado por causa de aparelhos velhos.
const int maxPushTokensPerUser = 10;
```

A interface passa a devolver `Future<PushRegistration>`, e o comentário diz que `ownerChanged` é o caso em que o token já existia para outro titular. `register` termina com:

```dart
    final outcome = await _store.registerIfConsented(
      userId: user.id,
      microAreaId: user.microAreaId,
      token: trimmed,
      platform: platform,
      now: _clock().toUtc(),
    );
    if (outcome == PushRegistration.refused) {
      throw DataRightsException(
        message: 'Ative "Avisos da equipe de saúde" em Meus Dados para receber avisos.',
      );
    }
    // Só a troca de dono deixa rastro: é o único evento que move um vínculo
    // aparelho↔titular sem ação do titular anterior. Registrar e repetir não
    // auditam, para não gravar uma linha por login.
    if (outcome == PushRegistration.ownerChanged) {
      await _audit.recordSafely(AuditEvent(
        userId: user.id,
        actionType: 'write',
        resourceType: 'push_token',
        result: 'granted',
      ));
    }
```

Confirme em `AuditEvent` se `resourceId` é obrigatório; se for, passe `userId`. O texto do token nunca entra na trilha.

`data_subject_rights_service.dart`: na interface, `Future<String> recordConsentRevokingPush(ConsentLogEntry entry);` com comentário "grava o `denied` de `segmentedPush` e apaga os tokens do titular na mesma transação". Em `updateConsent`, para `segmentedPush` com `granted == false`, chamar um `_record` que use `_store.recordConsentRevokingPush` em vez de `recordConsent` (parametrize `_record` com `revokePush: bool`). Remova o parâmetro `pushTokens`, o campo `_pushTokens` e o import de `PushTokenStore`. Remova também `_isCurrentAcceptance` e faça `hasAcceptedCurrentTerms` chamar `_store.latestConsent(...)` e comparar com uma função pública `bool isCurrentTermsAcceptance(ConsentRecordSnapshot? latest)` no mesmo arquivo, que `orm_data_subject_rights_store.dart` também usa em `recordConsentUnlessCurrent` (uma regra só). A regra recebe `{required String version}`: use `isCurrentAcceptance(latest, version: entry.version)`.

- [ ] **Step 3: Rodar unitários**

Run: `dart test test/unit/data_subject_rights_service_test.dart test/unit/push_token_service_test.dart`
Expected: PASS.

- [ ] **Step 4: Testes de integração vermelhos**

Em `push_token_endpoint_test.dart`, grupo de corrida (ids `9200`, mesmo `cleanup`), três testes novos:

```dart
test('revogação atômica: falha ao apagar tokens não deixa denied gravado', () async {
  // seed + consentimento granted + token registrado (via store)
  // chama recordConsentRevokingPush com um entry inválido de propósito
  // (userId inexistente => violação de FK do consent_logs) e espera o erro
  // depois: o último consent do titular continua 'granted' e o token continua lá
});

test('passou do teto, o token mais antigo sai e o novo entra', () async {
  // concede; registra 'tok-a'..'tok-k' (11 tokens) em sequência, com `now` crescente
  // esperado: count == 10, 'tok-a' ausente, 'tok-k' presente
});

test('troca de dono devolve ownerChanged', () async {
  // dois titulares consentidos, mesmo token
  // primeiro: registered; segundo: ownerChanged; repetição do segundo: registered
});
```

Para o primeiro, prove a atomicidade com uma falha real do banco: `entry.userId` que não existe em `users` faz o `insertRow` violar a FK; o `deleteWhere` do mesmo bloco não pode ter efeito (`count` do token do titular real continua 1, e nenhuma linha `denied` existe para ele). Como o titular do `entry` é inexistente, mande o `entry` com o `userId` de um segundo usuário semeado e faça a falha vir de `purpose` fora do enum? Não: use a FK. O que importa é que a transação inteira reverta.

Run: `dart test test/integration/push_token_endpoint_test.dart`
Expected: FAIL — `recordConsentRevokingPush` não existe.

- [ ] **Step 5: Implementar stores**

`orm_data_subject_rights_store.dart`:

```dart
  @override
  Future<String> recordConsentRevokingPush(ConsentLogEntry entry) async {
    final session = _session();
    final userUuid = UuidValue.fromString(entry.userId);
    return session.db.transaction((transaction) async {
      await lockPerSubject(session, transaction,
          namespace: lockNamespacePushToken, key: entry.userId);
      final row = await ConsentLog.db.insertRow(
        session,
        signedConsentLog(entry, signature: _signature, origin: 'painel-titular'),
        transaction: transaction,
      );
      await PushToken.db.deleteWhere(
        session,
        where: (t) => t.userId.equals(userUuid),
        transaction: transaction,
      );
      return row.id!.uuid;
    });
  }
```

`orm_push_token_store.dart`: `registerIfConsented` devolve `PushRegistration`. Sem consentimento: apaga o token de outro titular e devolve `refused`. Existente com outro dono: atualiza e devolve `ownerChanged`. Existente do mesmo dono: atualiza e devolve `registered`. Novo: insere; depois, ainda na transação, lê os tokens do titular ordenados por `updatedAt` descendente e apaga os que passam de `maxPushTokensPerUser`:

```dart
      final mine = await PushToken.db.find(
        session,
        where: (t) => t.userId.equals(userUuid),
        orderBy: (t) => t.updatedAt,
        orderDescending: true,
        transaction: transaction,
      );
      for (final old in mine.skip(maxPushTokensPerUser)) {
        await PushToken.db.deleteRow(session, old, transaction: transaction);
      }
```

O teto roda nos dois caminhos que gravam (insere e atualiza), para que trocar de dono para quem já está no teto também respeite. `deleteAllFor` deixa de existir na interface e no ORM (o único chamador era a revogação); remova-o de `PushTokenStore` e dos fakes. Ajuste `alert_runtime.dart` (o `PushTokenService` recebe `audit: auditTrailFor(session)` e `DataSubjectRightsService` perde o `pushTokens`). `devices_endpoint.dart` ganha no comentário: "Auditoria: só a troca de dono do token grava linha (`push_token`); registrar e repetir não, porque a revogação já deixa `consent_log`."

- [ ] **Step 6: Suíte e commit**

Run: `cd backend/sinalacs_server && dart test && dart analyze`
Expected: tudo verde, estável em 5 execuções seguidas de `dart test`; analyze em 44 infos, zero avisos.

```bash
git add backend/sinalacs_server
git commit -m "fix(backend): revogação de push atômica, auditoria da troca de dono e teto de tokens (RF14)"
```

---

### Task 2: Agenda de mudança dos termos e endpoint do aviso (backend)

**Files:**
- Create: `lib/src/application/patients/terms_change_schedule.dart`, `lib/src/models/api/terms_change_notice.spy.yaml`, `test/unit/terms_change_schedule_test.dart`
- Modify: `lib/src/application/patients/data_subject_rights_service.dart`, `lib/src/endpoints/patients_endpoint.dart`, `lib/src/runtime/alert_runtime.dart` (só se o serviço precisar de relógio/agenda injetada)
- Test: `test/unit/terms_change_schedule_test.dart`, `test/unit/data_subject_rights_service_test.dart`, `test/integration/data_subject_rights_endpoint_test.dart`

**Interfaces:**
- Produces: `class TermsChangeSchedule { const TermsChangeSchedule({required this.version, required this.publishedAt, required this.effectiveFrom, required this.summary}); }` — o construtor tem `assert` de que `effectiveFrom.difference(publishedAt) >= dataSubjectRequestDeadline` (15 dias) e de que `version != consentPolicyVersion`. Método `bool isActiveAt(DateTime now)` → `!now.isBefore(publishedAt) && now.isBefore(effectiveFrom)`.
- Produces: `const TermsChangeSchedule? upcomingTermsChange = null;` (nada agendado hoje).
- Produces: DTO `TermsChangeNotice { version: String, effectiveFrom: DateTime, summary: String }` e RPC `patients.termsChangeNotice(session, {required String accessToken}) → Future<TermsChangeNotice?>`.
- Produces: `DataSubjectRightsService.termsChangeNoticeAt(AuthenticatedUser user, {TermsChangeSchedule? schedule}) → Future<TermsChangeNoticeSnapshot?>` — na verdade, sem I/O: síncrono, só paciente (mesma regra `_requirePatient`), usa o relógio injetado.

- [ ] **Step 1: Testes vermelhos**

`test/unit/terms_change_schedule_test.dart`:

```dart
import 'package:sinalacs_server/src/application/patients/terms_change_schedule.dart';
import 'package:test/test.dart';

final _pub = DateTime.utc(2026, 10, 1);

TermsChangeSchedule agenda({DateTime? vigencia, String versao = '2026.2'}) => TermsChangeSchedule(
      version: versao,
      publishedAt: _pub,
      effectiveFrom: vigencia ?? _pub.add(const Duration(days: 15)),
      summary: 'Resumo.',
    );

void main() {
  test('vigência com menos de 15 dias da publicação não existe', () {
    expect(() => agenda(vigencia: _pub.add(const Duration(days: 14, hours: 23))),
        throwsA(isA<AssertionError>()));
  });

  test('exatamente 15 dias é aceito', () {
    expect(agenda().effectiveFrom, _pub.add(const Duration(days: 15)));
  });

  test('a versão nova não pode ser a vigente', () {
    expect(() => agenda(versao: consentPolicyVersion), throwsA(isA<AssertionError>()));
  });

  test('ativa na publicação, inativa na vigência', () {
    final a = agenda();
    expect(a.isActiveAt(_pub.subtract(const Duration(seconds: 1))), isFalse);
    expect(a.isActiveAt(_pub), isTrue);
    expect(a.isActiveAt(a.effectiveFrom.subtract(const Duration(seconds: 1))), isTrue);
    expect(a.isActiveAt(a.effectiveFrom), isFalse);
  });

  test('a agenda real do repositório respeita a regra (vazia hoje)', () {
    final real = upcomingTermsChange;
    if (real != null) {
      expect(real.effectiveFrom.difference(real.publishedAt) >= const Duration(days: 15), isTrue);
    }
  });
}
```

Importe `consentPolicyVersion` de `onboarding_service.dart`. Em `data_subject_rights_service_test.dart`:

```dart
group('termsChangeNotice (LGPD-RF18, aviso de 15 dias)', () {
  final agenda = TermsChangeSchedule(
    version: '2026.2',
    publishedAt: _now.subtract(const Duration(days: 1)),
    effectiveFrom: _now.add(const Duration(days: 14)),
    summary: 'Novo canal de dúvidas.',
  );

  test('sem agenda, não há aviso', () {
    expect(service.termsChangeNotice(_patient), isNull);
  });

  test('com agenda ativa, devolve versão, vigência e resumo', () {
    final svc = DataSubjectRightsService(store: store, audit: audit, clock: () => _now, termsChange: agenda);
    final notice = svc.termsChangeNotice(_patient)!;
    expect(notice.version, '2026.2');
    expect(notice.effectiveFrom, agenda.effectiveFrom);
    expect(notice.summary, 'Novo canal de dúvidas.');
  });

  test('fora da janela (já vigente) não há aviso', () {
    final svc = DataSubjectRightsService(
        store: store, audit: audit, clock: () => agenda.effectiveFrom, termsChange: agenda);
    expect(svc.termsChangeNotice(_patient), isNull);
  });

  test('só paciente', () {
    final svc = DataSubjectRightsService(store: store, audit: audit, clock: () => _now, termsChange: agenda);
    expect(() => svc.termsChangeNotice(_acs), throwsA(isA<StateError>()));
  });
});
```

Run: `dart test test/unit/terms_change_schedule_test.dart test/unit/data_subject_rights_service_test.dart`
Expected: FAIL — `TermsChangeSchedule` e `termsChangeNotice` não existem.

- [ ] **Step 2: Implementar**

`terms_change_schedule.dart`:

```dart
import 'package:sinalacs_server/src/application/onboarding/onboarding_service.dart'
    show consentPolicyVersion;
import 'package:sinalacs_server/src/application/patients/data_subject_rights_service.dart'
    show dataSubjectRequestDeadline;

/// Antecedência mínima do aviso de mudança dos termos (LGPD-RF18): a mesma
/// contagem de 15 dias do prazo de resposta ao titular.
const Duration termsChangeNoticePeriod = dataSubjectRequestDeadline;

/// Uma versão nova dos termos anunciada antes de valer. O construtor recusa
/// (em `assert`, que roda em desenvolvimento e nos testes) uma vigência a menos
/// de 15 dias da publicação: publicar o aviso tarde é um erro de quem edita o
/// repositório, não algo que o app deva corrigir depois.
///
/// Para agendar uma mudança: acrescente uma [LegalVersion] no app, troque
/// [upcomingTermsChange] por uma agenda com a versão nova, e só depois — na
/// data de vigência — mude `consentPolicyVersion` e `legalDocumentsVersion`.
class TermsChangeSchedule {
  const TermsChangeSchedule({
    required this.version,
    required this.publishedAt,
    required this.effectiveFrom,
    required this.summary,
  })  : assert(version != consentPolicyVersion, 'a versão anunciada já é a vigente'),
        assert(
          effectiveFrom.difference(publishedAt) >= termsChangeNoticePeriod,
          'o aviso exige 15 dias entre a publicação e a vigência',
        );

  final String version;
  final DateTime publishedAt;
  final DateTime effectiveFrom;
  final String summary;

  bool isActiveAt(DateTime now) => !now.isBefore(publishedAt) && now.isBefore(effectiveFrom);
}

/// Nada agendado hoje.
const TermsChangeSchedule? upcomingTermsChange = null;
```

`DateTime.difference` não é `const`: como o `assert` só roda em runtime, o construtor `const` com `assert` que chama métodos não constantes não compila. Use então um construtor não `const` e a agenda como `final TermsChangeSchedule? upcomingTermsChange = null;`. O ciclo de imports (`terms_change_schedule` importa `data_subject_rights_service`, que importa a agenda): quebre-o movendo `dataSubjectRequestDeadline` só para uso local aqui — defina `const Duration termsChangeNoticePeriod = Duration(days: 15);` sem importar o serviço.

`DataSubjectRightsService` ganha o parâmetro nomeado opcional `TermsChangeSchedule? termsChange` (o padrão é `upcomingTermsChange`) e:

```dart
  /// Aviso de mudança dos termos ativo agora, ou `null` (LGPD-RF18). Sem I/O.
  TermsChangeNoticeSnapshot? termsChangeNotice(AuthenticatedUser user) {
    _requirePatient(user);
    final schedule = _termsChange;
    if (schedule == null || !schedule.isActiveAt(_clock().toUtc())) return null;
    return TermsChangeNoticeSnapshot(
      version: schedule.version,
      effectiveFrom: schedule.effectiveFrom,
      summary: schedule.summary,
    );
  }
```

com `class TermsChangeNoticeSnapshot { const ...; final String version; final DateTime effectiveFrom; final String summary; }` no mesmo arquivo. Nos testes acima, `termsChangeNotice` é síncrono (`expect(service.termsChangeNotice(_patient), isNull)`).

DTO `terms_change_notice.spy.yaml` (na pasta de DTOs de `models/`, conforme `patient_data_overview`, confirmando o local com `ls lib/src/models/api`):

```yaml
### Aviso de mudança dos termos (LGPD-RF18): a versão que passa a valer, a data
### de vigência e um resumo do que muda. Publicado com pelo menos 15 dias de
### antecedência (`TermsChangeSchedule`).
class: TermsChangeNotice
fields:
  version: String
  effectiveFrom: DateTime
  summary: String
```

`PatientsEndpoint`:

```dart
  /// Aviso de mudança dos termos ativo agora (LGPD-RF18), ou `null`. Só
  /// paciente; sem leitura de banco e sem linha de auditoria.
  Future<TermsChangeNotice?> termsChangeNotice(
    Session session, {
    required String accessToken,
  }) async {
    final user = authenticate(accessToken);
    try {
      final notice =
          AlertRuntime.instance.dataSubjectRightsServiceFor(session).termsChangeNotice(user);
      return notice == null
          ? null
          : TermsChangeNotice(
              version: notice.version,
              effectiveFrom: notice.effectiveFrom,
              summary: notice.summary,
            );
    } on StateError catch (error) {
      throw AlertPermissionException(message: error.message);
    }
  }
```

Rode `serverpod generate` (e `create-migration`: "No changes detected" é o esperado, é só DTO).

- [ ] **Step 3: Integração**

Em `data_subject_rights_endpoint_test.dart`, grupo principal:

```dart
test('termsChangeNotice sem agenda devolve null e não grava auditoria', () async {
  final session = sessionBuilder.build();
  await _seed(session);
  final token = await patientToken();
  final before = await AuditLog.db.count(session);

  expect(await endpoints.patients.termsChangeNotice(sessionBuilder, accessToken: token), isNull);
  expect(await AuditLog.db.count(session), before);
});

test('termsChangeNotice recusa token inválido', () async {
  await expectLater(
    endpoints.patients.termsChangeNotice(sessionBuilder, accessToken: 'lixo'),
    throwsA(isA<AlertPermissionException>()),
  );
});
```

Run: `dart test test/integration/data_subject_rights_endpoint_test.dart`
Expected: PASS. Se `endpoint_auth_posture_test.dart` ou o teste de cobertura de auditoria acusar o método novo, registre a decisão "leitura sem I/O, sem auditoria" no teste, como `hasAcceptedCurrentTerms` fez.

- [ ] **Step 4: Suíte e commit**

Run: `cd backend/sinalacs_server && dart test && dart analyze`
Expected: verde e estável em 5 execuções; 44 infos.

```bash
git add backend/sinalacs_server apps/patient/lib
git commit -m "feat(backend): agenda e aviso de 15 dias de mudança dos termos (LGPD-RF18)"
```

(`apps/patient/lib`, porque `serverpod generate` regenera `sinalacs_client` sob `backend/`; confirme o caminho real do cliente gerado com `git status` antes de adicionar.)

---

### Task 3: Aviso no app do paciente e menores do cliente

**Files:**
- Create: `apps/patient/lib/core/legal/terms_change_notice_card.dart`, `apps/patient/test/terms_change_notice_test.dart`
- Modify: `lib/core/network/backend_client.dart`, `lib/core/push/push_token_source.dart`, `lib/app/app.dart`, `test/support/fake_patient_backend.dart`, `test/push_registration_test.dart`

**Interfaces:**
- Produces: `PatientBackend.termsChangeNotice() → Future<TermsChangeNotice?>` (interface, `MisconfiguredBackend` que lança `failure`, `BackendClient` que chama `_client.patients.termsChangeNotice`).
- Produces: `PushTokenScope.maybeOf(BuildContext) → PushTokenSource` que cai em `const NoPushTokenSource()` quando não há escopo; `of` continua existindo com o `assert`.
- Produces: `class TermsChangeNoticeCard extends StatelessWidget { const TermsChangeNoticeCard({required this.notice, required this.onDismiss, required this.onRead}); }` com chaves `terms_change_notice_card`, `terms_change_notice_read`, `terms_change_notice_dismiss`.
- Consumes: `TermsChangeNotice` do cliente gerado (Task 2) e `LegalDocumentScreen` de `legal_screens.dart` (confirme o nome e os argumentos lendo o arquivo antes; o botão "Ler" abre a Política/Termo vigentes, porque o texto da versão nova só existe no app quando a versão é publicada).

- [ ] **Step 1: Testes vermelhos**

`test/terms_change_notice_test.dart` (copie o `login` de `terms_gate_flow_test.dart`; `FakePatientBackend` ganha `TermsChangeNotice? termsNotice`, `int termsNoticeCalls`, `BackendFailure? termsNoticeFailure` e `Completer<void>? termsNoticeGate`):

```dart
final _aviso = TermsChangeNotice(
  version: '2026.2',
  effectiveFrom: DateTime.utc(2026, 10, 20),
  summary: 'Novo canal de dúvidas.',
);

testWidgets('com aviso ativo, a home mostra o cartão com a data e o resumo', (tester) async {
  final backend = FakePatientBackend()..termsNotice = _aviso;
  await tester.pumpWidget(SinalAcsApp(backend: backend));
  await login(tester);

  expect(find.byKey(const Key('terms_change_notice_card')), findsOneWidget);
  expect(find.textContaining('20/10/2026'), findsOneWidget);
  expect(find.textContaining('Novo canal de dúvidas.'), findsOneWidget);
});

testWidgets('sem aviso, não há cartão', (tester) async {
  await tester.pumpWidget(SinalAcsApp(backend: FakePatientBackend()));
  await login(tester);
  expect(find.byKey(const Key('terms_change_notice_card')), findsNothing);
});

testWidgets('dispensar some com o cartão e não volta na mesma sessão', (tester) async {
  final backend = FakePatientBackend()..termsNotice = _aviso;
  await tester.pumpWidget(SinalAcsApp(backend: backend));
  await login(tester);
  await tester.tap(find.byKey(const Key('terms_change_notice_dismiss')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('terms_change_notice_card')), findsNothing);
});

testWidgets('falha ao buscar o aviso não afeta a home nem mostra erro', (tester) async {
  final backend = FakePatientBackend()
    ..termsNotice = _aviso
    ..termsNoticeFailure = const BackendFailure('sem rede');
  await tester.pumpWidget(SinalAcsApp(backend: backend));
  await login(tester);
  expect(find.byType(PatientHomeShell), findsOneWidget);
  expect(find.byKey(const Key('terms_change_notice_card')), findsNothing);
  expect(find.textContaining('sem rede'), findsNothing);
});

testWidgets('servidor que nunca responde não atrasa a home', (tester) async {
  final backend = FakePatientBackend()
    ..termsNotice = _aviso
    ..termsNoticeGate = Completer<void>();
  await tester.pumpWidget(SinalAcsApp(backend: backend));
  await login(tester);
  expect(find.byType(PatientHomeShell), findsOneWidget);
  expect(find.byKey(const Key('terms_change_notice_card')), findsNothing);
});
```

Em `push_registration_test.dart`, mais dois:

```dart
testWidgets('fonte de token que nunca completa não atrasa a home', (tester) async {
  await tester.pumpWidget(SinalAcsApp(
    backend: FakePatientBackend(),
    pushTokens: _NeverSource(),
  ));
  await login(tester);
  expect(find.byType(PatientHomeShell), findsOneWidget);
});

testWidgets('login fora do SinalAcsApp (sem PushTokenScope) degrada para sem push', (tester) async {
  final backend = FakePatientBackend();
  await tester.pumpWidget(BackendScope(
    backend: backend,
    child: /* mesmos escopos que SinalAcsApp monta, menos o PushTokenScope */,
  ));
  // login e esperado: home aberta, backend.pushRegistrations vazio
});
```

com `class _NeverSource implements PushTokenSource { @override Future<PushDevice?> currentDevice() => Completer<PushDevice?>().future; }`. Para o segundo, monte a árvore com `LocationScope`, `RemindersScope`, `QrScannerScope` e `MaterialApp(home: PatientLoginScreen())` sem o `PushTokenScope`; se montar isso à mão ficar longo, extraia um helper de teste `pumpSemPushScope`. Adapte as chaves e o `login` ao que os testes vizinhos usam.

Run: `cd apps/patient && flutter test test/terms_change_notice_test.dart test/push_registration_test.dart`
Expected: FAIL — `termsChangeNotice`, o cartão e `maybeOf` não existem; o teste "fonte que nunca completa" já passa por causa do `unawaited` (teste de caracterização, sem RED, ledgerar).

- [ ] **Step 2: Implementar**

`push_token_source.dart`: acrescente

```dart
  /// Como [of], mas sem escopo cai em [NoPushTokenSource]: o registro de push é
  /// acessório e uma tela montada fora do `SinalAcsApp` não pode quebrar o login.
  static PushTokenSource maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PushTokenScope>()?.source ??
      const NoPushTokenSource();
```

e troque `PushTokenScope.of(context)` por `maybeOf` nos três pontos de `app.dart`. `backend_client.dart`: `termsChangeNotice` na interface (com comentário "o app ignora falha e lentidão; sem aviso, sem cartão"), no `MisconfiguredBackend` (`_recusar()`) e no `BackendClient` (mesmo formato de `hasAcceptedCurrentTerms`).

`terms_change_notice_card.dart`: um `Card` com ícone, o título "Os termos vão mudar", `'A versão ${notice.version} passa a valer em ${_data(notice.effectiveFrom.toLocal())}. ${notice.summary}'`, um `TextButton` "Ler os termos atuais" (`onRead`) e um `IconButton` de fechar com `tooltip: 'Dispensar aviso'` (`onDismiss`), nas chaves acima. Cores com os tokens `*OnSurface` de `PatientColors` (regra de contraste do projeto), e o `Semantics` do botão de fechar vem do `tooltip`.

`PatientHomeShell`: um `State` novo carrega o aviso em `initState` (`unawaited(_loadNotice())`) com `.timeout(_termsNoticeTimeout)` (3 s, mesma constante de valor que `_termsCheckTimeout`; reuse-a se ficar legível) e captura `BackendFailure`, `TimeoutException` e qualquer erro, guardando `_notice` e `_noticeDismissed`. O cartão entra acima do conteúdo da aba, fora do corpo rolável do alerta, só quando `_notice != null && !_noticeDismissed`. `onRead` abre o documento com `Navigator.push(MaterialPageRoute(builder: (_) => const LegalDocumentScreen(...)))` como o menu Mais já faz (`app.dart`, entrada "Privacidade e termos"). Se o shell for construído sem `BackendScope` em algum teste existente (o teste de `PatientHomeShell` só sob `RemindersScope` mencionado nos comentários), use `context.getInheritedWidgetOfExactType<BackendScope>()` e pule a busca quando ausente, para não quebrá-lo.

- [ ] **Step 3: Rodar e ver passar**

Run: `cd apps/patient && flutter test test/terms_change_notice_test.dart test/push_registration_test.dart`
Expected: PASS.

- [ ] **Step 4: Suíte, semântica e commit**

Adicione ao `terms_change_notice_test.dart` um teste com `tester.ensureSemantics()` e `expectNenhumBotaoInerte` (helper de `test/support/semantics_scan.dart`) sobre o cartão, e um de contraste do texto do cartão contra a superfície em que ele renderiza (`contrastOn` de `test/support/contrast.dart`, mínimo 4.5).

Run: `cd apps/patient && flutter test && flutter analyze; cd ../acs && flutter test`
Expected: tudo verde (190 + os novos), analyze limpo, ACS em 172.

```bash
git add apps/patient
git commit -m "feat(paciente): cartão de aviso de mudança dos termos e push sem quebrar fora do escopo (LGPD-RF18)"
```

---

### Task 4: Documentação, memória e verificação final

**Files:**
- Modify: `PROGRESS.md` (nova seção; tirar "aviso de 15 dias" e "menores" das pendências), `apps/CLAUDE.md` (o cartão e o `maybeOf`), `backend/CLAUDE.md` (revogação atômica, auditoria da troca de dono, teto de 10 tokens, `patients.termsChangeNotice` e `TermsChangeSchedule`, com o passo a passo de agendar uma mudança), `spec/lgpd_design.md` (aviso de 15 dias implementado, dentro do app), `spec/lgpd_data_audit.md` (`audit_logs` com `resourceType: push_token`; `push_tokens` com o teto), `spec/PRD_system.md` se citar o aviso, memória `patient-push-and-minors-2026-09-29` (atualizar em vez de criar outra) e `MEMORY.md`.

- [ ] **Step 1:** Editar os docs acima, com as contagens reais medidas ao fim.

- [ ] **Step 2: Verificação completa**

Run: `cd backend/sinalacs_server && dart test && dart analyze; cd ../../apps/patient && flutter test && flutter analyze; cd ../acs && flutter test && flutter analyze; cd ../.. && ./scripts/qa/ci_invariants.sh; graphify update .`
Expected: backend verde (repetir `dart test` 5 vezes, sem falhas intermitentes), analyze do backend em 44 infos e zero avisos, paciente e ACS verdes, `ci_invariants` ok.

- [ ] **Step 3: Commit**

```bash
git add PROGRESS.md apps/CLAUDE.md backend/CLAUDE.md spec CLAUDE.md
git commit -m "docs: registra os menores do push fechados e o aviso de mudança dos termos"
```

---

## Fora desta rodada (por decisão)

- Notificação por push ou SMS do aviso: o canal escolhido é o cartão dentro do app, porque o envio de push depende do projeto Firebase (§3.2) e o SMS é gateway de OTP, não de comunicados.
- Texto novo dos termos e troca de `consentPolicyVersion`: nenhuma mudança está agendada; `upcomingTermsChange` fica `null`.
- Revisão jurídica do texto 2026.1, backoffice, Firebase e apagar tokens no atendimento da exclusão.

## Autorrevisão

- **Cobertura:** minors da rodada 4 → Task 1 (atomicidade, auditoria da troca de dono, teto, regra de aceite única) e Task 3 (teste da fonte que nunca completa, `maybeOf`); aviso de 15 dias → Tasks 2 e 3; docs → Task 4.
- **Placeholders:** os pontos que dependem de nomes locais (pasta dos DTOs, argumentos de `LegalDocumentScreen`, campos obrigatórios de `AuditEvent`, montagem sem `PushTokenScope`) trazem a instrução de confirmação no passo; o comportamento esperado está definido em todos.
- **Tipos:** `PushRegistration`, `recordConsentRevokingPush`, `maxPushTokensPerUser`, `TermsChangeSchedule`, `termsChangeNotice` (síncrono no serviço, assíncrono no endpoint e no cliente) e `maybeOf` têm o mesmo nome e a mesma assinatura em todas as tasks. `dataSubjectRequestDeadline` não é importado pela agenda, para não criar ciclo.
