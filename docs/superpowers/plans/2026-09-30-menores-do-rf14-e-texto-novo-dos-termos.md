# Menores do RF14 e texto novo dos termos durante os 15 dias — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fechar os menores adiados do RF14 e do aviso de termos (poda do teto, desempates, rastro do dono anterior, cliente do Gorush, auditoria com 0 aceitos, contraste e semântica do cartão) e permitir que o paciente leia o **texto novo** dos termos durante os 15 dias de aviso.

**Architecture:** O texto futuro é conteúdo constante do app (como o texto vigente: precisa abrir sem rede e antes do cadastro), embarcado numa versão do app **antes** de o servidor publicar o aviso. O cartão só oferece "Ler o texto novo" quando a versão do aviso devolvida pelo servidor for a mesma que o app carrega; senão cai em "Ler os termos atuais". Um teste amarra as duas pontas (agenda do backend × texto do app). Os menores do backend são correções pontuais nos stores e no serviço de avisos, cada uma com um teste que já falha hoje.

**Tech Stack:** Serverpod 3.4.13 (`serverpod generate` só se um `.spy.yaml` mudar — aqui não muda), Postgres, `dart:io`, Flutter 3.44, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md` §2 e §3.2; `spec/lgpd_design.md` (LGPD-RF18/RF19: atualização comunicada com 15 dias de antecedência, versão consultável).

## Global Constraints

- Rodar `docker compose --profile test up -d postgres-test` antes dos testes de integração. `flutter analyze` limpo nos apps; `dart analyze` do backend no baseline de 51 infos, zero avisos.
- Alerta vermelho nunca é descartado nem atrasado: nada aqui pode bloquear login, home nem o botão de urgência. O cartão continua **fora** da aba de urgência.
- Textos de UI e comentários em português. Nenhum dado real em testes.
- Testes de integração sem rollback usam ids próprios (o grupo de corrida do push usa `9200…`; o de avisos, se precisar de um grupo sem rollback, `9500…`) e semente enxuta; esses grupos commitam linhas e já deixaram a suíte intermitente. Repetir `dart test` 5 vezes antes de dar uma tarefa de backend por concluída.
- `legalDocumentsVersion` (app) == `consentPolicyVersion` (backend) continua valendo; esta rodada **não** troca a versão vigente nem agenda uma mudança real (`upcomingTermsChange` e `upcomingLegalDocuments` ficam `null`).
- Contrastes medidos com `test/support/contrast.dart` (mínimo 4.5 para texto, 3.0 para ícone/UI) contra a superfície em que o widget realmente renderiza (`PatientColors.surfaceRaised`, o `Card`).

## Review Focus

- Aviso do servidor com versão que o app não conhece: o cartão não oferece um texto novo que não existe; oferece só o vigente, sem erro.
- Texto novo embarcado com versão diferente da agenda do backend (ou agenda ativa sem texto no app): o teste de amarração falha no CI, não em produção.
- Corpo 2xx do Gorush ilegível: o pedido pode ter sido entregue, então o erro é "resultado desconhecido", nunca "tente de novo".
- Falha ao apagar tokens inválidos depois de um envio bem-sucedido: o ACS recebe o resultado do envio, não um erro; a auditoria registra o envio.
- Paciente com token e consentimento mas sem linha clínica em `patients`: recebe o aviso "para todos" e fica fora do filtro de crônicos.

---

## Mapa de arquivos

- Backend modificar: `lib/src/application/patients/push_token_service.dart`, `data_subject_rights_service.dart`, `lib/src/application/notices/notice_service.dart`, `lib/src/infrastructure/database/orm_push_token_store.dart`, `orm_data_subject_rights_store.dart`, `orm_notice_recipient_store.dart`, `lib/src/infrastructure/push/gorush_client.dart`, `lib/src/runtime/alert_runtime.dart`, e os testes `test/unit/push_token_service_test.dart`, `data_subject_rights_service_test.dart`, `notice_service_test.dart`, `gorush_client_test.dart`, `test/integration/push_token_endpoint_test.dart`, `notices_endpoint_test.dart`.
- Paciente criar: `apps/patient/test/upcoming_legal_documents_test.dart`. Modificar: `lib/core/legal/legal_documents.dart`, `lib/core/legal/terms_change_notice_card.dart`, `lib/app/legal_screens.dart`, `lib/app/app.dart`, `test/terms_change_notice_test.dart`, `test/contrast_tokens_test.dart`, `test/legal_documents_test.dart`.
- Docs: `PROGRESS.md`, `apps/CLAUDE.md`, `backend/CLAUDE.md`, `spec/lgpd_design.md`, `spec/lgpd_data_audit.md`, memória.

---

### Task 1: Menores do registro de token e do consentimento (backend)

**Files:**
- Modify: `lib/src/application/patients/push_token_service.dart`, `lib/src/infrastructure/database/orm_push_token_store.dart`, `lib/src/infrastructure/database/orm_data_subject_rights_store.dart`, `lib/src/application/patients/data_subject_rights_service.dart`
- Test: `test/unit/push_token_service_test.dart`, `test/unit/data_subject_rights_service_test.dart`, `test/integration/push_token_endpoint_test.dart`

**Interfaces:**
- Produces: `class PushRegistrationResult { const PushRegistrationResult(this.outcome, {this.previousOwnerId}); final PushRegistration outcome; final String? previousOwnerId; }` em `push_token_service.dart`. `PushTokenStore.registerIfConsented(...)` passa a devolver `Future<PushRegistrationResult>` (`previousOwnerId` só é preenchido quando `outcome == ownerChanged`).
- Produces: `DataSubjectRightsService({..., TermsChangeSchedule? Function()? termsChangeReader})` no lugar do parâmetro `termsChange`; o padrão é `() => upcomingTermsChange`. (Remova `TermsChangeSchedule? termsChange` e ajuste os testes que o usam.)
- Consumes: `PushRegistration`, `maxPushTokensPerUser`, `lockPerSubject`, `lockNamespacePushToken`, `lockNamespacePushTokenRow`, `isCurrentAcceptance`.

- [ ] **Step 1: Testes vermelhos (unitários)**

Em `push_token_service_test.dart`, o `_FakePushTokenStore` passa a devolver `PushRegistrationResult` (`ownerChanged` traz `previousOwnerId: previous.userId`). Trocar o teste da troca de dono por:

```dart
test('troca de dono audita o novo dono E o anterior, sem o token', () async {
  await service.register(_patient, token: 'tok-1', platform: 'android');
  await service.register(_patient, token: 'tok-1', platform: 'android');
  expect(audit.events, isEmpty);

  await service.register(_otherPatient, token: 'tok-1', platform: 'android');

  expect(audit.events.map((e) => e.userId).toSet(), {_otherPatient.id, _patient.id});
  for (final e in audit.events) {
    expect(e.resourceType, 'push_token');
    expect('${e.resourceId} ${e.result}'.contains('tok-1'), isFalse);
  }
  expect(audit.events.map((e) => e.result), containsAll(['granted', 'lost']));
});
```

Em `data_subject_rights_service_test.dart`, trocar `termsChange: agenda` por `termsChangeReader: () => agenda` e acrescentar:

```dart
test('um leitor que devolve null vence a constante do repositório', () {
  final svc = DataSubjectRightsService(
    store: store,
    audit: audit,
    clock: () => _now,
    termsChangeReader: () => null,
  );
  expect(svc.termsChangeNotice(_patient), isNull);
});
```

Run: `cd backend/sinalacs_server && dart test test/unit/push_token_service_test.dart test/unit/data_subject_rights_service_test.dart`
Expected: FAIL (compilação: `PushRegistrationResult`, `termsChangeReader`).

- [ ] **Step 2: Implementar serviço e interface**

`push_token_service.dart`: acrescentar `PushRegistrationResult` (acima), trocar o retorno da interface, e no `register`:

```dart
    final result = await _store.registerIfConsented(...); // mesmos argumentos
    if (result.outcome == PushRegistration.refused) {
      throw DataRightsException(
        message: 'Ative "Avisos da equipe de saúde" em Meus Dados para receber avisos.',
      );
    }
    if (result.outcome == PushRegistration.ownerChanged) {
      await _audit.recordSafely(AuditEvent(
        userId: user.id, actionType: 'write', resourceType: 'push_token', result: 'granted',
      ));
      // Rastro para o titular anterior (LGPD-RF08): ele perdeu o vínculo sem agir.
      final previous = result.previousOwnerId;
      if (previous != null) {
        await _audit.recordSafely(AuditEvent(
          userId: previous, actionType: 'write', resourceType: 'push_token', result: 'lost',
        ));
      }
    }
```

`data_subject_rights_service.dart`: construtor recebe `TermsChangeSchedule? Function()? termsChangeReader`, guarda `_termsChangeReader = termsChangeReader ?? (() => upcomingTermsChange)` e `termsChangeNotice` usa `_termsChangeReader()`.

- [ ] **Step 3: Rodar os unitários**

Run: `dart test test/unit/push_token_service_test.dart test/unit/data_subject_rights_service_test.dart`
Expected: PASS.

- [ ] **Step 4: Testes de integração vermelhos**

Em `push_token_endpoint_test.dart`, no grupo de corrida (ids `9200…`, `_seedRaceLean`, `cleanup` já apaga `PushToken` e `ConsentLog` dos dois titulares). Envolver cada `await _seedRaceLean(session);` do grupo **dentro** do `try` (o `cleanup` no `finally` é idempotente; assim uma semente que falha no meio não deixa ids fixos commitados). Adaptar os três usos de `registerIfConsented` para `(...).outcome`. Testes novos:

```dart
test('a poda do teto só apaga tokens do próprio titular', () async {
  final session = sessionBuilder.build();
  try {
    await _seedRaceLean(session);
    final consents = consentStore();
    await grant(consents, _racePatientId);
    await grant(consents, _raceAcsId);
    final tokens = OrmPushTokenStore(session: () => sessionBuilder.build());
    final base = DateTime.now().toUtc();
    // B (_raceAcsId) está no teto; o token mais antigo dele é 'tok-b-0'.
    for (var i = 0; i < maxPushTokensPerUser; i++) {
      await tokens.registerIfConsented(
        userId: _raceAcsId, microAreaId: _raceMicroAreaId,
        token: 'tok-b-$i', platform: 'android', now: base.add(Duration(seconds: i)),
      );
    }
    // C (_racePatientId) recebe o token mais antigo de B: troca de dono.
    await tokens.registerIfConsented(
      userId: _racePatientId, microAreaId: _raceMicroAreaId,
      token: 'tok-b-0', platform: 'android', now: base.add(const Duration(minutes: 1)),
    );
    // B registra um 11º token: a poda dele NÃO pode levar o 'tok-b-0' que agora é de C.
    await tokens.registerIfConsented(
      userId: _raceAcsId, microAreaId: _raceMicroAreaId,
      token: 'tok-b-novo', platform: 'android', now: base.add(const Duration(minutes: 2)),
    );
    final donoDeB0 = await PushToken.db.findFirstRow(session, where: (t) => t.token.equals('tok-b-0'));
    expect(donoDeB0?.userId, UuidValue.fromString(_racePatientId));
  } finally {
    await cleanup(session);
  }
});

test('relógio que voltou: o token recém-gravado nunca é o podado', () async {
  final session = sessionBuilder.build();
  try {
    await _seedRaceLean(session);
    await grant(consentStore(), _racePatientId);
    final tokens = OrmPushTokenStore(session: () => sessionBuilder.build());
    final futuro = DateTime.now().toUtc().add(const Duration(hours: 1));
    for (var i = 0; i < maxPushTokensPerUser; i++) {
      await tokens.registerIfConsented(
        userId: _racePatientId, microAreaId: _raceMicroAreaId,
        token: 'tok-f-$i', platform: 'android', now: futuro,
      );
    }
    // `now` MENOR que o de todos os outros: por updatedAt ele seria o mais antigo.
    final result = await tokens.registerIfConsented(
      userId: _racePatientId, microAreaId: _raceMicroAreaId,
      token: 'tok-agora', platform: 'android', now: DateTime.now().toUtc(),
    );
    expect(result.outcome, PushRegistration.registered);
    expect(await PushToken.db.count(session, where: (t) => t.token.equals('tok-agora')), 1);
    expect(
      await PushToken.db.count(session, where: (t) => t.userId.equals(UuidValue.fromString(_racePatientId))),
      maxPushTokensPerUser,
    );
  } finally {
    await cleanup(session);
  }
});

test('troca de dono devolve o dono anterior', () async {
  // dois titulares consentidos; A registra 'tok-dono'; B registra o mesmo
  // esperado: result.outcome == ownerChanged e result.previousOwnerId == _racePatientId
});

test('consentimentos com o MESMO timestamp: o desempate é estável (id maior vence)', () async {
  // insere duas linhas segmentedPush do mesmo titular com o mesmo `timestamp`:
  //   id menor  = 'granted'  (inserida primeiro)
  //   id maior  = 'denied'   (inserida depois)
  // registerIfConsented deve recusar (o de id maior vence => 'denied'), sempre.
  // Use ConsentLog.db.insertRow com `id: UuidValue.fromString('…-000000000001')` e '…-000000000002'.
});
```

O terceiro e o quarto testes: complete com o mesmo esqueleto do primeiro (semente, `grant`/inserção direta, `try/finally cleanup`); no quarto, insira as duas linhas na ordem "id menor primeiro" para que, sem desempate, a leitura devolva o `granted` (ordem de heap) e o teste falhe.

Run: `dart test test/integration/push_token_endpoint_test.dart`
Expected: FAIL nos quatro (compilação por `.outcome`/`previousOwnerId`; depois: a poda apaga o token de C, o token novo é podado, o desempate devolve `granted`).

- [ ] **Step 5: Implementar os stores**

`orm_push_token_store.dart`, em `registerIfConsented`:
1. Leitura do consentimento com desempate: `orderByList: (t) => [Order(column: t.timestamp, orderDescending: true), Order(column: t.id, orderDescending: true)]` no lugar de `orderBy`/`orderDescending`.
2. `previousOwnerId = ownerChanged ? existing!.userId.uuid : null` guardado antes do `updateRow`.
3. Poda, sempre poupando o token recém-gravado e apagando **por id E titular**:

```dart
      final mine = await PushToken.db.find(
        session,
        where: (t) => t.userId.equals(userUuid) & t.token.notEquals(token),
        orderByList: (t) => [
          Order(column: t.updatedAt, orderDescending: true),
          Order(column: t.createdAt, orderDescending: true),
        ],
        transaction: transaction,
      );
      final doomed = mine.skip(maxPushTokensPerUser - 1).map((t) => t.id!).toSet();
      if (doomed.isNotEmpty) {
        await PushToken.db.deleteWhere(
          session,
          where: (t) => t.id.inSet(doomed) & t.userId.equals(userUuid),
          transaction: transaction,
        );
      }
```

4. Devolver `PushRegistrationResult(PushRegistration.refused)`, `.registered` ou `PushRegistrationResult(PushRegistration.ownerChanged, previousOwnerId: previousOwnerId)`.

`orm_data_subject_rights_store.dart`: `latestConsent` e a leitura dentro de `recordConsentUnlessCurrent` passam ao mesmo `orderByList` (timestamp desc, id desc). Confirme com `grep -n "orderBy" lib/src/infrastructure/database/orm_data_subject_rights_store.dart`.

- [ ] **Step 6: Suíte e commit**

Run: `cd backend/sinalacs_server && dart analyze && for i in 1 2 3 4 5; do dart test 2>&1 | tail -1; done`
Expected: analyze em 51 infos e zero avisos; 5 de 5 verdes. Se um arquivo de integração ficar intermitente, a causa é uma semente que commita demais: enxugue-a, não repita até passar.

```bash
git add backend/sinalacs_server
git commit -m "fix(backend): poda do teto por titular, desempates estáveis e rastro do dono anterior do token (RF14)"
```

---

### Task 2: Menores do envio de avisos (backend)

**Files:**
- Modify: `lib/src/infrastructure/push/gorush_client.dart`, `lib/src/application/notices/notice_service.dart`, `lib/src/infrastructure/database/orm_notice_recipient_store.dart`, `lib/src/runtime/alert_runtime.dart`
- Test: `test/unit/gorush_client_test.dart`, `test/unit/notice_service_test.dart`, `test/integration/notices_endpoint_test.dart`

**Interfaces:**
- Produces: `GorushClient.close()` (fecha o `HttpClient`; um `send` depois de fechado lança `PushGatewayException`).
- Produces: em `AlertRuntime`, `PushSender? _gorush` criado uma vez por `GorushClient` (não por requisição), recriado/fechado em `overrideConfig`.
- Consumes: `PushSender`, `PushGatewayException(message, {outcomeUnknown})`, `NoticeService`, `NoticeRecipientStore`, `AuditTrail`.

- [ ] **Step 1: Testes vermelhos (unitários)**

`gorush_client_test.dart` (o `FakeGorush.start` aceita `response` como `Map`; estenda-o para aceitar `rawBody` (String) que, se presente, é escrito no lugar do JSON):

```dart
test('corpo 2xx ilegível: resultado desconhecido, nunca "tente de novo"', () async {
  for (final raw in ['isto não é json', '[1,2,3]', '{"logs":"não-é-lista"}']) {
    final gw = await FakeGorush.start(rawBody: raw);
    addTearDown(gw.close);
    final client = GorushClient(baseUrl: gw.url, timeout: const Duration(seconds: 2));
    final envio = client.send(_msg, const [PushTarget(token: 'a', platform: 'android')]);
    if (raw.contains('não-é-lista')) {
      final report = await envio; // forma inesperada em `logs`: tolerada, sem falhas
      expect(report.accepted, 1);
    } else {
      await expectLater(
        envio,
        throwsA(isA<PushGatewayException>().having((e) => e.outcomeUnknown, 'outcomeUnknown', isTrue)),
        reason: raw,
      );
    }
  }
});

test('depois de close(), send falha com PushGatewayException e não com StateError', () async {
  final gw = await FakeGorush.start(response: {});
  addTearDown(gw.close);
  final client = GorushClient(baseUrl: gw.url, timeout: const Duration(seconds: 2))..close();
  await expectLater(
    client.send(_msg, const [PushTarget(token: 'a', platform: 'android')]),
    throwsA(isA<PushGatewayException>()),
  );
});
```

`notice_service_test.dart` (o `_FakeRecipientStore` ganha `Object? deleteFailure` lançado por `deleteTokens`):

```dart
test('falha ao apagar tokens inválidos não vira erro: o envio já aconteceu', () async {
  sender.report = const PushSendReport(accepted: 1, invalidTokens: ['tok-b']);
  store.deleteFailure = StateError('banco fora do ar');
  final r = await service.sendSegmented(_acs, title: 't', message: 'm', audience: 'everyone');
  expect((r.recipients, r.accepted), (2, 1));
  expect(audit.events.single.result, 'granted');
});

test('nenhum aceito: não audita "granted"', () async {
  sender.report = const PushSendReport(accepted: 0, invalidTokens: []);
  final r = await service.sendSegmented(_acs, title: 't', message: 'm', audience: 'everyone');
  expect(r.accepted, 0);
  expect(audit.events.single.result, 'not_delivered');
});
```

Run: `dart test test/unit/gorush_client_test.dart test/unit/notice_service_test.dart`
Expected: FAIL (`close` e `deleteFailure` não existem; `rawBody` idem; depois: o erro escapa, a auditoria diz `granted`).

- [ ] **Step 2: Implementar cliente e serviço**

`gorush_client.dart`:
- `void close() => _http.close(force: true);`
- em `send`, acrescentar `on StateError { throw const PushGatewayException('O cliente do Gorush foi encerrado.'); }` e trocar o tratamento de `FormatException` por `outcomeUnknown: true` (a resposta era 2xx: o Gorush pode ter entregue).
- em `_post`, `jsonDecode` só é aceito se `is Map<String, dynamic>`; senão `throw const PushGatewayException('O Gorush respondeu algo ilegível.', outcomeUnknown: true)`. `logs` que não é lista vale como vazio (`final logs = json['logs'] is List ? json['logs'] as List : const []`).

`notice_service.dart`: cercar o apagamento de tokens (best effort) e escolher o resultado da auditoria:

```dart
    if (report.invalidTokens.isNotEmpty) {
      try {
        await _store.deleteTokens(report.invalidTokens);
      } catch (_) {
        // A poda é higiene: o aviso já saiu, e um erro aqui levaria o ACS a reenviar.
      }
    }
    await _record(user, microAreaId, report.accepted > 0 ? 'granted' : 'not_delivered');
```

- [ ] **Step 3: Rodar os unitários**

Run: `dart test test/unit/gorush_client_test.dart test/unit/notice_service_test.dart`
Expected: PASS.

- [ ] **Step 4: Testes de integração vermelhos**

Em `notices_endpoint_test.dart`:
1. Renomear o teste `grava uma linha community_notice sem o texto do aviso` para `grava uma linha community_notice só com ACS e microárea` e acrescentar `expect(jsonEncode(rows.single.toJson()).contains('Amanhã, das 8h'), isFalse);` (importe `dart:convert`).
2. `_addPatient` ganha `bool withPatientRow = true` (pula o `Patient.db.insertRow` quando `false`). Teste novo:

```dart
test('paciente sem linha clínica recebe "para todos" e fica fora do filtro de crônicos', () async {
  final session = await seedAll();
  await _addPatient(session, id: _noClinicalId, microAreaId: _microAreaId, chronic: false, withPatientRow: false);
  await _consent(session, _noClinicalId, 'granted', DateTime.utc(2026, 9, 1));
  await _token(session, _noClinicalId, 'tok-sem-clinica', _microAreaId);

  await send(await tokenOf('acs'));
  expect(sender.lastTargets.map((t) => t.token), contains('tok-sem-clinica'));

  await send(await tokenOf('acs'), audience: 'chronic');
  expect(sender.lastTargets.map((t) => t.token), isNot(contains('tok-sem-clinica')));
});

test('consentimentos com o mesmo timestamp: o de id maior decide', () async {
  // mesmo titular, `timestamp` igual: 'granted' com id menor (inserido primeiro),
  // 'denied' com id maior. O token dele NÃO pode receber o aviso.
});
```

(`_noClinicalId = '00000000-0000-4000-8000-000000000024'`; para o segundo teste use ids explícitos em `ConsentLog(id: UuidValue.fromString(...))`.)

Run: `dart test test/integration/notices_endpoint_test.dart`
Expected: FAIL nos dois novos (o `INNER JOIN` exclui o paciente sem linha clínica; o desempate devolve `granted`).

- [ ] **Step 5: Implementar o store e o runtime**

`orm_notice_recipient_store.dart`: `JOIN patients p` vira `LEFT JOIN patients p ON p."id" = u."id"`, o filtro vira `(NOT @chronic OR COALESCE(p."isChronic", false))`, e o subselect do consentimento ganha o desempate: `ORDER BY c."timestamp" DESC, c."id" DESC LIMIT 1`.

`alert_runtime.dart`: guardar `GorushClient? _gorush` (e a URL com que foi criado). `noticeServiceFor` reaproveita o cliente quando `config.gorushUrl` não mudou; `overrideConfig` e `overrideNoticeSender` chamam `_gorush?.close(); _gorush = null;`.

- [ ] **Step 6: Suíte e commit**

Run: `cd backend/sinalacs_server && dart analyze && for i in 1 2 3 4 5; do dart test 2>&1 | tail -1; done`
Expected: analyze em 51 infos, zero avisos; 5 de 5 verdes.

```bash
git add backend/sinalacs_server
git commit -m "fix(backend): cliente do Gorush encerrável e tolerante, envio não vira erro por falha de poda, LEFT JOIN e desempate (RF14)"
```

---

### Task 3: Texto novo dos termos, contraste e semântica do cartão (app paciente)

**Files:**
- Create: `apps/patient/test/upcoming_legal_documents_test.dart`
- Modify: `lib/core/legal/legal_documents.dart`, `lib/core/legal/terms_change_notice_card.dart`, `lib/app/legal_screens.dart`, `lib/app/app.dart`, `test/terms_change_notice_test.dart`, `test/contrast_tokens_test.dart`, `test/legal_documents_test.dart`

**Interfaces:**
- Produces em `legal_documents.dart`: `class UpcomingLegalDocuments { const UpcomingLegalDocuments({required this.version, required this.privacy, required this.terms}); final String version; final LegalDocument privacy; final LegalDocument terms; }` e `const UpcomingLegalDocuments? upcomingLegalDocuments = null;`.
- Produces: `LegalDocumentsScreen({super.key, this.upcoming})` — com `upcoming != null` lista os documentos futuros e o título passa a ser "Termos que passam a valer".
- Produces: `TermsChangeNoticeCard({required notice, required onRead, required onDismiss, this.onReadNew})` — `onReadNew` só é passado quando o app carrega o texto da versão do aviso; a nova chave é `terms_change_notice_read_new`.
- Consumes: `TermsChangeNotice` (`version`, `effectiveFrom`, `summary`) do cliente gerado; `LegalDocument`, `privacyPolicy`, `termsOfUse`.

- [ ] **Step 1: Testes vermelhos**

`test/upcoming_legal_documents_test.dart` prova a amarração entre o backend e o app com uma função de leitura testada por si mesma:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/core/legal/legal_documents.dart';

/// Versão anunciada no backend, ou `null` quando `upcomingTermsChange = null`.
String? backendUpcomingVersion(String source) {
  if (RegExp(r'upcomingTermsChange\s*=\s*null').hasMatch(source)) return null;
  final match = RegExp(r"upcomingTermsChange[^;]*version:\s*'([^']+)'", dotAll: true).firstMatch(source);
  return match?.group(1);
}

void main() {
  test('o leitor devolve null com a agenda vazia e a versão quando há agenda', () {
    expect(backendUpcomingVersion('final TermsChangeSchedule? upcomingTermsChange = null;'), isNull);
    expect(
      backendUpcomingVersion("final TermsChangeSchedule? upcomingTermsChange = TermsChangeSchedule(version: '2026.2', publishedAt: x);"),
      '2026.2',
    );
  });

  test('agenda do backend e texto do app andam juntos', () {
    final source = File(
      '../../backend/sinalacs_server/lib/src/application/patients/terms_change_schedule.dart',
    ).readAsStringSync();
    final anunciada = backendUpcomingVersion(source);
    expect(
      upcomingLegalDocuments?.version,
      anunciada,
      reason: 'o aviso anunciado no servidor precisa ter o texto novo embarcado no app '
          '(e vice-versa): publique o app antes de publicar o aviso',
    );
  });

  test('o texto novo, quando existe, não pode repetir a versão vigente', () {
    final novo = upcomingLegalDocuments;
    if (novo != null) {
      expect(novo.version, isNot(legalDocumentsVersion));
      expect(novo.privacy.version, novo.version);
      expect(novo.terms.version, novo.version);
    }
  });
}
```

Em `test/terms_change_notice_test.dart` acrescentar (o `_textoNovo` é um `UpcomingLegalDocuments` de teste com a versão `'2026.2'`, montado com cópias de `privacyPolicy`/`termsOfUse`; o `SinalAcsApp` ganha o parâmetro de teste `upcomingDocuments`, `UpcomingLegalDocuments?`, que tem precedência sobre a constante):

```dart
testWidgets('com o texto novo embarcado na mesma versão do aviso, oferece "Ler o texto novo"', (tester) async {
  final backend = FakePatientBackend()..termsNotice = _aviso; // version 2026.2
  await tester.pumpWidget(SinalAcsApp(backend: backend, upcomingDocuments: _textoNovo));
  await login(tester);

  await tester.tap(find.byKey(const Key('terms_change_notice_read_new')));
  await tester.pumpAndSettle();

  expect(find.text('Termos que passam a valer'), findsOneWidget);
  expect(find.textContaining('Versão 2026.2'), findsWidgets);
});

testWidgets('aviso de versão que o app não conhece: só o texto vigente, sem erro', (tester) async {
  final backend = FakePatientBackend()..termsNotice = _aviso;
  await tester.pumpWidget(SinalAcsApp(backend: backend)); // sem texto novo embarcado
  await login(tester);
  expect(find.byKey(const Key('terms_change_notice_read_new')), findsNothing);
  expect(find.byKey(const Key('terms_change_notice_read')), findsOneWidget);
});

testWidgets('texto novo de OUTRA versão que a do aviso não é oferecido', (tester) async {
  final backend = FakePatientBackend()..termsNotice = _aviso; // 2026.2
  await tester.pumpWidget(SinalAcsApp(backend: backend, upcomingDocuments: _textoNovoDe('2026.3')));
  await login(tester);
  expect(find.byKey(const Key('terms_change_notice_read_new')), findsNothing);
});

testWidgets('o título do cartão é um cabeçalho semântico', (tester) async {
  final handle = tester.ensureSemantics();
  final backend = FakePatientBackend()..termsNotice = _aviso;
  await tester.pumpWidget(SinalAcsApp(backend: backend));
  await login(tester);
  expect(
    tester.getSemantics(find.text('Os termos vão mudar')),
    matchesSemantics(label: 'Os termos vão mudar', isHeader: true),
  );
  handle.dispose();
});
```

Em `test/contrast_tokens_test.dart`, acrescentar à matriz os três pares que o cartão usa e que o tema gera a partir do seed (o `Card` renderiza sobre `PatientColors.surfaceRaised`):

```dart
final scheme = buildPatientTheme().colorScheme;
// dentro da lista `cases`:
('texto do cartão (onSurface) sobre card', scheme.onSurface, PatientColors.surfaceRaised, normalText),
('TextButton do cartão (primary) sobre card', scheme.primary, PatientColors.surfaceRaised, normalText),
('ícone de fechar do cartão (onSurfaceVariant) sobre card', scheme.onSurfaceVariant, PatientColors.surfaceRaised, largeTextOrUi),
```

(`cases` é `const`; troque para `final` para aceitar valores do tema.)

Run: `cd apps/patient && flutter test test/upcoming_legal_documents_test.dart test/terms_change_notice_test.dart test/contrast_tokens_test.dart`
Expected: FAIL (compilação: `upcomingLegalDocuments`, `upcomingDocuments`, `terms_change_notice_read_new`; depois o cabeçalho semântico). Os três pares de contraste podem passar de primeira (caracterização): se algum falhar, a mensagem traz a razão medida e o passo 2 corrige a cor do cartão.

- [ ] **Step 2: Implementar**

`legal_documents.dart`: acrescentar `UpcomingLegalDocuments` e `const UpcomingLegalDocuments? upcomingLegalDocuments = null;`, com este comentário: "Texto da versão que **ainda não vale** e já foi anunciada (LGPD-RF18, 15 dias). O app embarca o texto antes de o servidor publicar o aviso: publique uma versão do app com este valor, só depois troque `upcomingTermsChange` no backend, e na vigência mude `legalDocumentsVersion` e `consentPolicyVersion` e mova o texto para `privacyPolicy`/`termsOfUse`. O teste `upcoming_legal_documents_test.dart` falha se as duas pontas divergirem."

`legal_screens.dart`: `LegalDocumentsScreen({super.key, this.upcoming})`; a lista e o subtítulo usam `upcoming?.privacy`/`upcoming?.terms` quando presente (subtítulo "Versão X · passa a valer em <effectiveFrom>" é responsabilidade do chamador: passe a data por um parâmetro `String? effectiveLabel`); o título do `AppBar` é `upcoming == null ? 'Privacidade e termos' : 'Termos que passam a valer'`.

`terms_change_notice_card.dart`: parâmetro `VoidCallback? onReadNew`; quando não nulo, um `FilledButton.tonal` com a chave `terms_change_notice_read_new` e o rótulo "Ler o texto novo" antes do "Ler os termos atuais". O título vira `Semantics(header: true, child: Text('Os termos vão mudar', ...))`. Se algum par de contraste falhou no passo 1, defina explicitamente a cor do `TextButton`/ícone com `PatientColors.accentOnSurface`/`Colors.white70` e repita a medição.

`app.dart`: `SinalAcsApp` ganha `final UpcomingLegalDocuments? upcomingDocuments;` (documentar: "injetável para teste; o padrão é `upcomingLegalDocuments`"). O shell lê a fonte do texto novo por um `InheritedWidget` mínimo `UpcomingDocumentsScope` (mesmo padrão de `QrScannerScope`), e passa `onReadNew` ao cartão **só se** `docs != null && docs.version == notice.version`, abrindo `LegalDocumentsScreen(upcoming: docs, effectiveLabel: ...)`.

- [ ] **Step 3: Rodar e ver passar**

Run: `cd apps/patient && flutter test test/upcoming_legal_documents_test.dart test/terms_change_notice_test.dart test/contrast_tokens_test.dart test/legal_documents_test.dart test/legal_screens_test.dart`
Expected: PASS.

- [ ] **Step 4: Mutação, suíte e commit**

Prove que a amarração pega o defeito: troque temporariamente `upcomingTermsChange = null` por uma agenda com `version: '2026.2'` no backend (sem tocar no app) e confirme que `agenda do backend e texto do app andam juntos` falha; restaure.

Run: `cd apps/patient && flutter test && flutter analyze; cd ../acs && flutter test`
Expected: tudo verde, analyze limpo, ACS 178.

```bash
git add apps/patient
git commit -m "feat(paciente): texto novo dos termos durante os 15 dias, contraste e semântica do cartão (LGPD-RF18)"
```

---

### Task 4: Documentação, memória e verificação final

**Files:**
- Modify: `PROGRESS.md` (nova seção; riscar os minors resolvidos), `apps/CLAUDE.md` (texto novo e `UpcomingDocumentsScope`), `backend/CLAUDE.md` (procedimento de agendar agora inclui embarcar o texto no app antes; poda por titular; cliente do Gorush encerrável), `spec/lgpd_design.md` (a comunicação dos 15 dias oferece o texto novo), `spec/lgpd_data_audit.md` (`push_token` com `result = lost` para o dono anterior; `community_notice` com `not_delivered`), memória (atualizar `push-minors-and-terms-notice-2026-09-29` ou criar uma nova) e `MEMORY.md`.

- [ ] **Step 1:** Editar os docs. No `backend/CLAUDE.md`, o passo a passo de agendar uma mudança passa a ser: (1) escrever o texto novo em `upcomingLegalDocuments` no app e publicar essa versão do app; (2) só então trocar `upcomingTermsChange` no backend (a regra dos 15 dias compara datas declaradas); (3) na vigência, mudar `consentPolicyVersion` e `legalDocumentsVersion`, mover o texto para `privacyPolicy`/`termsOfUse` e voltar as duas constantes para `null`. Registrar como **limite**: um app antigo, sem o texto embarcado, vê só "Ler os termos atuais" durante os 15 dias.

- [ ] **Step 2: Verificação completa**

Run: `cd backend/sinalacs_server && for i in 1 2 3 4 5; do dart test 2>&1 | tail -1; done; dart analyze | tail -1; cd ../../apps/patient && flutter test && flutter analyze; cd ../acs && flutter test && flutter analyze; cd ../.. && docker compose config -q && ./scripts/qa/ci_invariants.sh; graphify update .`
Expected: backend verde 5 de 5, analyze em 51 infos e zero avisos, paciente e ACS verdes, `ci_invariants` ok.

- [ ] **Step 3: Commit**

```bash
git add PROGRESS.md apps/CLAUDE.md backend/CLAUDE.md spec CLAUDE.md
git commit -m "docs: registra os menores do RF14 fechados e o texto novo dos termos"
```

---

## Fora desta rodada (por decisão)

- Agendar uma mudança real dos termos (`upcomingTermsChange` e `upcomingLegalDocuments` ficam `null`), revisão jurídica do texto, lado nativo do token de push, credenciais FCM/APNs e Gorush real.
- Mostrar o texto novo a app antigo (sem o texto embarcado): só vê o vigente.
- Marcar dentro do texto novo o que mudou em relação ao vigente (diff), e avisar quem já está com o app aberto.

## Autorrevisão

- **Cobertura:** minors do RF14 → Tasks 1 e 2 (poda por titular, desempate da poda e dos consentimentos, rastro do dono anterior, injeção de "sem agenda", `HttpClient` encerrável, JSON de forma inesperada e corpo ilegível, falha na poda depois do envio, auditoria com 0 aceitos, `LEFT JOIN`, nome do teste de auditoria, cleanup do grupo de corrida); contraste e `Semantics(header)` → Task 3; texto novo → Task 3; docs → Task 4.
- **Placeholders:** os passos 4 de Tasks 1 e 2 deixam dois testes como esqueleto comentado (troca de dono devolve o dono anterior; desempate por id) com instrução explícita do que semear e afirmar; os nomes locais a confirmar (`grep` do `orderBy` do store de consentimento, campos de `AuditEvent`) trazem o comando.
- **Tipos:** `PushRegistrationResult` (Task 1) é o único retorno de `registerIfConsented` em serviço, store e testes; `termsChangeReader` substitui `termsChange` em todos os usos; `UpcomingLegalDocuments`/`upcomingLegalDocuments`/`upcomingDocuments`/`UpcomingDocumentsScope` (Task 3) usam o mesmo nome em app, cartão, tela e testes.
- **Riscos declarados:** o teste do desempate por id depende da ordem de heap do Postgres para ser vermelho antes da correção (documentado no passo); o par de contraste do `TextButton` vem do tema gerado por seed e pode exigir cor explícita; sem `upcomingTermsChange` real, a amarração só é provada por mutação temporária.
