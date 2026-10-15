# RF14 — Avisos segmentados com Gorush Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fechar a revisão das specs do RF14 (Gorush no lugar do Firebase) e implementar o envio: Gorush no Docker Compose, cliente HTTP no backend, `notices.sendSegmented` com segmentação SQL restrita a quem consentiu, tela de envio no ACS e captura do token nativo no paciente por um provider Riverpod.

**Architecture:** O paciente registra o token do aparelho em `push_tokens` (já existe). O ACS chama `notices.sendSegmented`; o servidor resolve os destinatários por SQL (microárea do token do ACS, `segmentedPush` vigente, filtro opcional de crônicos), entrega a lista ao Gorush por `POST /api/push` e apaga os tokens que o provedor declara inválidos. O Gorush é um relé para FCM/APNs e não é publicado fora da rede do Compose.

**Tech Stack:** Serverpod 3.4.13, Postgres (`unsafeQuery`), `dart:io` `HttpClient` (o backend não tem pacote `http`), Gorush (`appleboy/gorush`), Flutter 3.44, `flutter_riverpod` só no app do paciente, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md` §3.2 (já revisada para Gorush, ainda sem commit); `spec/stack.md`; `spec/lgpd_design.md` (consentimento `segmentedPush` antes de enviar).

**Dependência de ordem:** executar depois de `2026-09-29-menores-do-push-e-aviso-de-mudanca-dos-termos.md`, que muda `PushTokenStore.registerIfConsented` e o teto de tokens. Este plano lê `push_tokens` e não altera o registro.

## Global Constraints

- Regenerar com `export PATH=$PATH:~/.pub-cache/bin; cd backend/sinalacs_server && serverpod generate && serverpod create-migration`. Integração: `docker compose --profile test up -d postgres-test`.
- `flutter analyze` limpo nos apps; `dart analyze` do backend no baseline vigente (44 infos, zero avisos).
- Alerta vermelho nunca é descartado nem atrasado: falha do Gorush ou do registro de push nunca bloqueia login, home nem alerta; o envio de aviso nunca passa pela fila do alerta MQTT.
- ACS só envia para a **própria microárea** (invariante do projeto): a microárea vem do token, nunca de parâmetro.
- Conteúdo do aviso não carrega dado de saúde identificável (§3.2): a mensagem é livre, mas o servidor não anexa nome, condição nem id de paciente ao payload; `data` leva só a tela a abrir.
- Segredos do Gorush seguem o padrão do repositório: variáveis `${VAR:?...}` no Compose, `.env.example` como referência e `bootstrap_env.sh` gera o que for segredo aleatório. Credenciais FCM/APNs são **arquivos fornecidos pela organização**, nunca gerados nem versionados.
- Testes de integração sem rollback usam ids próprios (`9400…`) e `enrollmentId` próprio, com limpeza manual.
- Textos de UI e comentários em português. Nenhum dado real em testes.

## Review Focus

- Titular que revogou `segmentedPush` depois de registrar o token: nunca recebe (a consulta usa a linha de consentimento mais recente, não a existência do token).
- Gorush fora do ar, lento ou respondendo 5xx: `sendSegmented` falha com erro tipado em tempo limitado e não deixa linha de auditoria dizendo "enviado".
- Token que o provedor devolve como inválido (`NotRegistered`, `BadDeviceToken`): é apagado, e o envio seguinte não o inclui.
- Microárea sem destinatário consentido: resposta `0 enviados`, sem chamada ao Gorush.
- ACS de outra microárea ou paciente chamando o endpoint: recusado; mensagem vazia ou acima do teto: recusada.

---

## Mapa de arquivos

- Backend criar: `lib/src/infrastructure/push/gorush_client.dart`, `lib/src/application/notices/notice_service.dart`, `lib/src/infrastructure/database/orm_notice_recipient_store.dart`, `lib/src/endpoints/notices_endpoint.dart`, `lib/src/models/api/notice_send_result.spy.yaml` (confirmar a pasta dos DTOs com `ls lib/src/models/api`), `test/unit/gorush_client_test.dart`, `test/unit/notice_service_test.dart`, `test/integration/notices_endpoint_test.dart`.
- Backend modificar: `lib/src/config/app_config.dart`, `lib/src/runtime/alert_runtime.dart`, `test/unit/app_config_test.dart`, `test/unit/compose_secret_agreement_test.dart` (se ele lista variáveis do Compose).
- Infra: `docker-compose.yml`, `.env.example`, `scripts/dev/bootstrap_env.sh`, `infra/docker/gorush/` (config), `.gitignore` (credenciais).
- ACS: `apps/acs/lib/app/app.dart` (`NoticesScreen`), `apps/acs/lib/core/network/…` (o cliente do backend do ACS; confirmar o arquivo), testes do ACS.
- Paciente: `apps/patient/pubspec.yaml`, `lib/core/push/push_token_provider.dart`, `lib/core/push/native_push_token_source.dart`, `lib/main.dart`, `lib/app/app.dart`, `test/push_riverpod_test.dart`.
- Docs: `PROGRESS.md`, `apps/CLAUDE.md`, `backend/CLAUDE.md`, `spec/stack.md`, `spec/lgpd_data_audit.md`, `CLAUDE.md`, memória.

---

### Task 0: Fechar e commitar a revisão das specs

**Files:** os já alterados (working tree): `PROGRESS.md`, `apps/patient/lib/core/push/push_token_source.dart`, `docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md`, `spec/PRD_system.md`, `spec/lgpd_design.md`, `spec/stack.md`, `spec/validation_report.md`.

**Interfaces:** Produces: a decisão registrada de que o **Riverpod entra só no push do paciente** (escolha do usuário em 2026-09-29), que substitui o parágrafo "O app **não** adota Riverpod" do §3.2 e a linha "Sem Riverpod" de `spec/stack.md`.

- [ ] **Step 1: Corrigir o texto sobre Riverpod**

No §3.2 e em `spec/stack.md`, troque o "não adota Riverpod" por: "O app do paciente adota `flutter_riverpod` **somente** para a captura e o registro do token de push (`pushTokenProvider`); o restante da injeção segue por `InheritedWidget` (`BackendScope`, `QrScannerScope`, `PushTokenScope`). Migrar o resto para Riverpod fica fora do RF14." Em `PROGRESS.md`, corrija a seção "Revisão do RF14" pela mesma frase e remova o item "Sem Riverpod".

- [ ] **Step 2: Conferir que nada ainda diz "bloqueado por Firebase"**

Run: `grep -rn -i "projeto Firebase\|sem Riverpod\|não adota Riverpod" spec docs/superpowers/specs PROGRESS.md apps/CLAUDE.md backend/CLAUDE.md`
Expected: nenhuma ocorrência que afirme bloqueio por Firebase ou a exclusão do Riverpod (menções históricas em "Revisão do RF14" que expliquem a mudança são aceitas).

- [ ] **Step 3: Commit**

```bash
git add PROGRESS.md apps/patient/lib/core/push/push_token_source.dart docs/superpowers spec
git commit -m "docs: RF14 passa a usar Gorush; Riverpod só no push do paciente"
```

---

### Task 1: Gorush no Compose e configuração do backend

**Files:**
- Modify: `docker-compose.yml`, `.env.example`, `scripts/dev/bootstrap_env.sh` (só se houver segredo aleatório), `.gitignore`, `backend/sinalacs_server/lib/src/config/app_config.dart`, `backend/sinalacs_server/test/unit/app_config_test.dart`, `test/unit/compose_secret_agreement_test.dart`
- Create: `infra/docker/gorush/config.yml`, `infra/docker/gorush/README.md`

**Interfaces:**
- Produces: `AppConfig.gorushUrl` (`String?`, env `GORUSH_URL`; `null` = envio de push desligado) e `AppConfig.gorushTimeout` (`Duration`, fixo em 5 s).
- Produces: serviço `gorush` no Compose, sob `profiles: [push]`, sem `ports:` publicados; o serviço `serverpod` recebe `GORUSH_URL: http://gorush:8088` **só** quando o perfil `push` está ativo (sem `depends_on` obrigatório: o backend sobe sem Gorush).

- [ ] **Step 1: Teste vermelho de configuração**

Em `app_config_test.dart`:

```dart
test('GORUSH_URL ausente desliga o envio; presente é lido sem barra final', () {
  final base = <String, String>{...envMinimo};
  expect(AppConfig.fromEnvironment(base).gorushUrl, isNull);
  expect(
    AppConfig.fromEnvironment({...base, 'GORUSH_URL': 'http://gorush:8088/'}).gorushUrl,
    'http://gorush:8088',
  );
});

test('GORUSH_URL fora de http(s) é recusada', () {
  expect(
    () => AppConfig.fromEnvironment({...envMinimo, 'GORUSH_URL': 'ftp://x'}),
    throwsA(isA<StateError>()),
  );
});
```

Use o nome real do construtor de fábrica e o mapa mínimo de ambiente que o arquivo já usa (leia `app_config_test.dart` antes; `envMinimo` acima é o rótulo do que ele já define). Run: `cd backend/sinalacs_server && dart test test/unit/app_config_test.dart`. Expected: FAIL — `gorushUrl` não existe.

- [ ] **Step 2: Implementar em `AppConfig`**

Campo `final String? gorushUrl;` (opcional no construtor, padrão `null`, para não quebrar os `AppConfig(...)` dos testes de integração) e `Duration get gorushTimeout => const Duration(seconds: 5);`. Na fábrica: lê `GORUSH_URL`, `trim`, tira uma `/` final, `null` se vazio; se não começar com `http://` ou `https://`, `throw StateError('GORUSH_URL deve começar com http:// ou https://.')`. Rode o teste (PASS).

- [ ] **Step 3: Compose, exemplo e ignore**

`docker-compose.yml`: serviço novo

```yaml
  gorush:
    image: appleboy/gorush:1.18.4
    profiles: [push]
    restart: unless-stopped
    volumes:
      - ./infra/docker/gorush/config.yml:/config.yml:ro
      - ${GORUSH_CREDENTIALS_DIR:?defina em .env o diretório com as credenciais FCM/APNs}:/credentials:ro
    command: ["-c", "/config.yml"]
    # Sem `ports:` — só o backend, na rede do Compose, fala com o Gorush.
```

Confirme a última tag estável do `appleboy/gorush` antes de fixar (a tag acima é um marcador do formato, não uma verificação) e escreva a tag confirmada. No serviço `serverpod`, acrescente `GORUSH_URL: ${GORUSH_URL:-}`. `infra/docker/gorush/config.yml` liga só o que existe: `core.port: 8088`, `android.enabled` com `credential` apontando para `/credentials/fcm-service-account.json`, `ios.enabled` com `key_path: /credentials/apns-key.p8`, `key_id` e `team_id` vindos de `GORUSH_IOS_KEY_ID`/`GORUSH_IOS_TEAM_ID`, `log.format: json`. **Confira os nomes das chaves no README do Gorush da tag escolhida**; o `infra/docker/gorush/README.md` documenta quais arquivos a organização precisa fornecer e que eles não são versionados. `.env.example`: `GORUSH_URL=` (vazio desliga), `GORUSH_CREDENTIALS_DIR=`, `GORUSH_IOS_KEY_ID=`, `GORUSH_IOS_TEAM_ID=`, com comentário de que o Gorush é relé e ainda precisa de credenciais FCM/APNs. `.gitignore`: `infra/docker/gorush/credentials/`.

- [ ] **Step 4: Verificação**

Run: `docker compose config -q && docker compose --profile push config -q; cd backend/sinalacs_server && dart test test/unit/app_config_test.dart test/unit/compose_secret_agreement_test.dart`
Expected: `docker compose config -q` passa sem o perfil `push` e sem `GORUSH_CREDENTIALS_DIR`; com o perfil `push`, falha nomeando `GORUSH_CREDENTIALS_DIR` se ele faltar; testes passam. Se `compose_secret_agreement_test` acusar o serviço novo, ajuste o teste para reconhecer `${VAR:?}` de perfil opcional.

- [ ] **Step 5: Commit**

```bash
git add docker-compose.yml .env.example .gitignore infra/docker/gorush backend/sinalacs_server
git commit -m "feat(infra): Gorush opcional no Compose e GORUSH_URL no backend (RF14)"
```

---

### Task 2: Cliente do Gorush

**Files:**
- Create: `backend/sinalacs_server/lib/src/infrastructure/push/gorush_client.dart`, `backend/sinalacs_server/test/unit/gorush_client_test.dart`

**Interfaces:**
- Produces: `abstract interface class PushSender { Future<PushSendReport> send(PushMessage message, List<PushTarget> targets); }`
- Produces: `class PushTarget { const PushTarget({required this.token, required this.platform}); }` (`platform`: `'android'` ou `'ios'`), `class PushMessage { const PushMessage({required this.title, required this.body, this.data = const {}}); }`, `class PushSendReport { const PushSendReport({required this.accepted, required this.invalidTokens}); final int accepted; final List<String> invalidTokens; }`, `class PushGatewayException implements Exception { const PushGatewayException(this.message); }`.
- Produces: `class GorushClient implements PushSender { GorushClient({required String baseUrl, required Duration timeout, HttpClient? httpClient}); }`.

- [ ] **Step 1: Teste vermelho contra um servidor HTTP local**

`gorush_client_test.dart` sobe um `HttpServer.bind(InternetAddress.loopbackIPv4, 0)` que grava o corpo recebido e responde o que o teste mandar:

```dart
test('agrupa por plataforma e usa os códigos do Gorush (1 iOS, 2 Android)', () async {
  final gw = await FakeGorush.start(response: {'counts': 3, 'logs': []});
  final client = GorushClient(baseUrl: gw.url, timeout: const Duration(seconds: 2));

  final report = await client.send(
    const PushMessage(title: 'Vacina', body: 'Amanhã, na UBS.', data: {'screen': 'notices'}),
    const [
      PushTarget(token: 'a1', platform: 'android'),
      PushTarget(token: 'a2', platform: 'android'),
      PushTarget(token: 'i1', platform: 'ios'),
    ],
  );

  final sent = gw.lastBody['notifications'] as List;
  expect(sent, hasLength(2));
  expect(sent.firstWhere((n) => n['platform'] == 2)['tokens'], ['a1', 'a2']);
  expect(sent.firstWhere((n) => n['platform'] == 1)['tokens'], ['i1']);
  expect(sent.first['title'], 'Vacina');
  expect(sent.first['data'], {'screen': 'notices'});
  expect(report.accepted, 3);
  expect(report.invalidTokens, isEmpty);
  await gw.close();
});

test('tokens que o provedor recusa como inválidos voltam em invalidTokens', () async {
  final gw = await FakeGorush.start(response: {
    'counts': 1,
    'logs': [
      {'type': 'failed-push', 'platform': 'android', 'token': 'a2', 'error': 'NotRegistered'},
      {'type': 'failed-push', 'platform': 'ios', 'token': 'i1', 'error': 'BadDeviceToken'},
      {'type': 'failed-push', 'platform': 'ios', 'token': 'i2', 'error': 'ServiceUnavailable'},
    ],
  });
  final client = GorushClient(baseUrl: gw.url, timeout: const Duration(seconds: 2));
  final report = await client.send(
    const PushMessage(title: 't', body: 'b'),
    const [PushTarget(token: 'a2', platform: 'android'), PushTarget(token: 'i1', platform: 'ios'), PushTarget(token: 'i2', platform: 'ios')],
  );
  expect(report.invalidTokens.toSet(), {'a2', 'i1'}); // erro transitório não apaga token
  await gw.close();
});

test('status 5xx vira PushGatewayException', () async {
  final gw = await FakeGorush.start(status: 503, response: {});
  final client = GorushClient(baseUrl: gw.url, timeout: const Duration(seconds: 2));
  await expectLater(
    client.send(const PushMessage(title: 't', body: 'b'), const [PushTarget(token: 'a', platform: 'android')]),
    throwsA(isA<PushGatewayException>()),
  );
  await gw.close();
});

test('servidor que não responde estoura o tempo limite como PushGatewayException', () async {
  final gw = await FakeGorush.start(hang: true);
  final client = GorushClient(baseUrl: gw.url, timeout: const Duration(milliseconds: 300));
  await expectLater(
    client.send(const PushMessage(title: 't', body: 'b'), const [PushTarget(token: 'a', platform: 'android')]),
    throwsA(isA<PushGatewayException>()),
  );
  await gw.close();
});

test('lista vazia não chama o Gorush', () async {
  final gw = await FakeGorush.start(response: {});
  final client = GorushClient(baseUrl: gw.url, timeout: const Duration(seconds: 2));
  final report = await client.send(const PushMessage(title: 't', body: 'b'), const []);
  expect(report.accepted, 0);
  expect(gw.requests, 0);
  await gw.close();
});
```

`FakeGorush` é uma classe de teste no próprio arquivo (`start({status = 200, response, hang = false})`, `url`, `lastBody`, `requests`, `close`). Run: `dart test test/unit/gorush_client_test.dart`. Expected: FAIL — `GorushClient` não existe.

- [ ] **Step 2: Implementar**

`send`: se `targets` vazio, `PushSendReport(accepted: 0, invalidTokens: [])` sem I/O. Senão agrupa por plataforma em `{'notifications': [{'tokens': [...], 'platform': 2|1, 'title', 'message': body, 'data': data}]}` e faz `POST {baseUrl}/api/push` com `Content-Type: application/json` via `HttpClient`, `.timeout(timeout)` sobre a requisição inteira (abrir, escrever e ler a resposta); `TimeoutException`, `SocketException` e status fora de 2xx viram `PushGatewayException` (a mensagem não inclui tokens nem o corpo enviado). Resposta 2xx: `accepted = counts` (int; se ausente, `targets.length` menos as falhas); `invalidTokens` = tokens dos `logs` com `type == 'failed-push'` cujo `error` contenha (sem diferenciar caixa) `NotRegistered`, `Unregistered`, `InvalidRegistration`, `BadDeviceToken`, `DeviceTokenNotForTopic` ou `MismatchSenderId`. Nada de log com token. Rode os testes (PASS).

- [ ] **Step 3: Commit**

```bash
git add backend/sinalacs_server
git commit -m "feat(backend): cliente do Gorush com tempo limite e poda de tokens inválidos (RF14)"
```

---

### Task 3: Serviço, consulta segmentada e `notices.sendSegmented`

**Files:**
- Create: `lib/src/application/notices/notice_service.dart`, `lib/src/infrastructure/database/orm_notice_recipient_store.dart`, `lib/src/endpoints/notices_endpoint.dart`, `lib/src/models/api/notice_send_result.spy.yaml`, `test/unit/notice_service_test.dart`, `test/integration/notices_endpoint_test.dart`
- Modify: `lib/src/runtime/alert_runtime.dart`, `test/unit/endpoint_auth_posture_test.dart` (só se ele enumerar endpoints)

**Interfaces:**
- Consumes: `PushSender`, `PushTarget`, `PushMessage`, `PushSendReport`, `PushGatewayException` (Task 2); `AppConfig.gorushUrl` (Task 1); `AuditTrail`, `AuditEvent`, `Authorization.require`, `DataRightsException`, `AlertPermissionException`.
- Produces: `enum NoticeAudience { everyone, chronic }` (constante no serviço, não no protocolo; o endpoint recebe `String` e valida).
- Produces: `abstract interface class NoticeRecipientStore { Future<List<PushTarget>> consentedTargets({required String microAreaId, required bool chronicOnly}); Future<int> deleteTokens(List<String> tokens); }`.
- Produces: `NoticeService({required NoticeRecipientStore store, required PushSender? sender, required AuditTrail audit})` e `Future<NoticeSendResult> sendSegmented(AuthenticatedUser user, {required String title, required String message, required String audience})`, com `class NoticeSendResult { final int recipients; final int accepted; }`.
- Produces: RPC `notices.sendSegmented(session, {required String accessToken, required String title, required String message, required String audience}) → Future<NoticeSendResult>` e o DTO `NoticeSendResult { recipients: int, accepted: int }`.
- Produces: constantes `noticeTitleMaxLength = 60`, `noticeMessageMaxLength = 240`.

- [ ] **Step 1: Testes unitários vermelhos**

`notice_service_test.dart`, com `_FakeRecipientStore` (lista fixa, `deleted`), `_FakeSender` (grava a mensagem e os alvos, devolve o relatório configurado ou lança) e o `FakeAuditTrail` (`test/support/fake_audit_trail.dart`, que a rodada anterior extrai; se ainda não existir, copie a classe):

```dart
test('só ACS da própria microárea envia; paciente é recusado', () async {
  await expectLater(
    service.sendSegmented(_patient, title: 't', message: 'm', audience: 'everyone'),
    throwsA(isA<StateError>()),
  );
  expect(sender.sent, isEmpty);
});

test('a consulta usa a microárea do token e o filtro de crônicos', () async {
  await service.sendSegmented(_acs, title: 'Vacina', message: 'Amanhã.', audience: 'chronic');
  expect(store.lastMicroAreaId, _acs.microAreaId);
  expect(store.lastChronicOnly, isTrue);
});

test('sem destinatário consentido: 0 enviados, sem chamar o provedor', () async {
  store.targets = const [];
  final r = await service.sendSegmented(_acs, title: 't', message: 'm', audience: 'everyone');
  expect((r.recipients, r.accepted), (0, 0));
  expect(sender.calls, 0);
});

test('o payload não leva dado do paciente, só título, mensagem e tela', () async {
  await service.sendSegmented(_acs, title: 'Vacina', message: 'Amanhã.', audience: 'everyone');
  expect(sender.lastMessage!.title, 'Vacina');
  expect(sender.lastMessage!.data, {'screen': 'notices'});
});

test('tokens inválidos devolvidos pelo provedor são apagados', () async {
  sender.report = const PushSendReport(accepted: 1, invalidTokens: ['tok-b']);
  await service.sendSegmented(_acs, title: 't', message: 'm', audience: 'everyone');
  expect(store.deleted, ['tok-b']);
});

test('falha do Gorush vira erro tipado e não audita "enviado"', () async {
  sender.failure = const PushGatewayException('fora do ar');
  await expectLater(
    service.sendSegmented(_acs, title: 't', message: 'm', audience: 'everyone'),
    throwsA(isA<NoticeDeliveryException>()),
  );
  expect(audit.events.where((e) => e.result == 'granted'), isEmpty);
});

test('sem Gorush configurado (sender nulo) o envio é recusado com mensagem clara', () async {
  final off = NoticeService(store: store, sender: null, audit: audit);
  await expectLater(
    off.sendSegmented(_acs, title: 't', message: 'm', audience: 'everyone'),
    throwsA(isA<NoticeDeliveryException>()),
  );
});

test('título e mensagem vazios, longos demais ou público desconhecido são recusados', () async {
  for (final a in [('', 'm', 'everyone'), ('t', '  ', 'everyone'), ('x' * 61, 'm', 'everyone'), ('t', 'x' * 241, 'everyone'), ('t', 'm', 'todos')]) {
    await expectLater(
      service.sendSegmented(_acs, title: a.$1, message: a.$2, audience: a.$3),
      throwsA(isA<DataRightsException>()),
    );
  }
  expect(sender.calls, 0);
});

test('o texto da mensagem nunca vai para a trilha de auditoria', () async {
  await service.sendSegmented(_acs, title: 'Vacina', message: 'texto sigiloso', audience: 'everyone');
  for (final e in audit.events) {
    expect('${e.resourceType} ${e.resourceId} ${e.result}'.contains('sigiloso'), isFalse);
  }
});
```

Run: `dart test test/unit/notice_service_test.dart`. Expected: FAIL — `NoticeService` não existe. `NoticeDeliveryException` é um exceção do modelo (`lib/src/models/exceptions/`, no formato de `DataRightsException`, mesma pasta e mesmo padrão `.spy.yaml`).

- [ ] **Step 2: Implementar o serviço**

`sendSegmented`: `Authorization.require(user, roles: {UserRole.acs}, onDenied: StateError('Somente o ACS envia avisos.'), requireMicroArea: true)`; `trim` em título e mensagem, validações acima com `DataRightsException` (reuse; a mensagem diz o limite); `audience` em `{'everyone','chronic'}`; se `_sender == null` → `NoticeDeliveryException(message: 'O envio de avisos não está configurado neste ambiente.')`; `targets = await _store.consentedTargets(microAreaId: user.microAreaId!, chronicOnly: audience == 'chronic')`; se vazio, audita (`result: 'no_recipients'`) e devolve `(0, 0)`; `try { report = await _sender.send(PushMessage(title:, body:, data: {'screen': 'notices'}), targets) } on PushGatewayException { throw NoticeDeliveryException(message: 'Não foi possível entregar o aviso agora. Tente de novo em instantes.'); }`; `if (report.invalidTokens.isNotEmpty) await _store.deleteTokens(report.invalidTokens);` audita `AuditEvent(userId: user.id, actionType: 'write', resourceType: 'community_notice', result: 'granted')` e devolve `NoticeSendResult(recipients: targets.length, accepted: report.accepted)`. Confirme em `AuditEvent` o campo `resourceId` (passe `user.microAreaId` se for obrigatório): a trilha registra quem enviou e para qual microárea, jamais o texto.

- [ ] **Step 3: Testes de integração da consulta (vermelhos)**

`notices_endpoint_test.dart`, grupo sem rollback com ids `9400…`, dois pacientes na microárea A, um na B, tokens `tok-a1`, `tok-a2`, `tok-b1`, e um `PushSender` de teste injetado pelo `AlertRuntime` (leia como os outros testes sobrescrevem serviços; se o runtime não tiver gancho para o sender, adicione `overrideNoticeSender(PushSender?)` no mesmo estilo de `overrideConfig`):

```dart
test('só recebe quem tem consentimento vigente na microárea do ACS', () async {
  // a1: granted; a2: granted e depois denied (com o token ainda no banco, de propósito)
  // b1: granted, mas em outra microárea
  await endpoints.notices.sendSegmented(sessionBuilder, accessToken: acsToken,
      title: 'Vacina', message: 'Amanhã.', audience: 'everyone');
  expect(sender.lastTargets.map((t) => t.token), ['tok-a1']);
});

test('filtro de crônicos usa patients.isChronic', () async {
  // a1 crônico, a3 não; ambos granted
  // audience: 'chronic' → só o token do crônico
});

test('token inválido devolvido pelo provedor some do banco', () async {
  sender.report = const PushSendReport(accepted: 0, invalidTokens: ['tok-a1']);
  await endpoints.notices.sendSegmented(...);
  expect(await PushToken.db.count(session, where: (t) => t.token.equals('tok-a1')), 0);
});

test('paciente e token inválido são recusados; ACS de outra microárea não enxerga a A', () async {
  await expectLater(
    endpoints.notices.sendSegmented(sessionBuilder, accessToken: patientToken, title: 't', message: 'm', audience: 'everyone'),
    throwsA(isA<AlertPermissionException>()),
  );
});
```

Para o token do ACS use `endpoints.auth.developmentLogin(sessionBuilder, role: 'acs')` e semeie usuários no mesmo estilo de `push_token_endpoint_test.dart` (com `enrollmentId` próprio). Run: `dart test test/integration/notices_endpoint_test.dart`. Expected: FAIL — o endpoint não existe.

- [ ] **Step 4: Implementar store, DTO, endpoint e runtime**

`orm_notice_recipient_store.dart` usa `session.db.unsafeQuery` com esta consulta (o consentimento mais recente por titular decide; o token sozinho não basta):

```sql
SELECT pt.token, pt.platform
FROM push_tokens pt
JOIN users u ON u.id = pt."userId"
JOIN patients p ON p.id = u.id
WHERE u."microAreaId" = @micro
  AND u.role = 'patient'
  AND (NOT @chronic OR p."isChronic")
  AND COALESCE((
        SELECT c.action FROM consent_logs c
        WHERE c."userId" = pt."userId" AND c.purpose = 'segmentedPush'
        ORDER BY c."timestamp" DESC LIMIT 1
      ), 'denied') = 'granted'
ORDER BY pt.token;
```

Confirme os nomes reais das colunas e do enum de `role` em `migrations/*/definition.sql` (o Serverpod guarda enums por nome em `text`; ajuste `u.role`). Parâmetros via `QueryParameters.named`, sem interpolar texto. `deleteTokens` usa `PushToken.db.deleteWhere(... t.token.inSet(tokens.toSet()))`. DTO `notice_send_result.spy.yaml` com `recipients: int` e `accepted: int`. `NoticesEndpoint extends AuthenticatedEndpoint`:

```dart
class NoticesEndpoint extends AuthenticatedEndpoint {
  /// Envia um aviso segmentado aos pacientes da microárea do ACS que
  /// consentiram com `segmentedPush` (RF14). A microárea vem do token.
  Future<NoticeSendResult> sendSegmented(
    Session session, {
    required String accessToken,
    required String title,
    required String message,
    required String audience,
  }) async {
    final user = authenticate(accessToken);
    try {
      final r = await AlertRuntime.instance
          .noticeServiceFor(session)
          .sendSegmented(user, title: title, message: message, audience: audience);
      return NoticeSendResult(recipients: r.recipients, accepted: r.accepted);
    } on StateError catch (error) {
      throw AlertPermissionException(message: error.message);
    }
  }
}
```

`AlertRuntime.noticeServiceFor(session)` monta `NoticeService(store: OrmNoticeRecipientStore(...), sender: config.gorushUrl == null ? null : GorushClient(baseUrl: config.gorushUrl!, timeout: config.gorushTimeout), audit: auditTrailFor(session))`. Rode `serverpod generate` e `create-migration` ("No changes detected" é esperado: só DTO e exceção).

- [ ] **Step 5: Suíte e commit**

Run: `cd backend/sinalacs_server && dart test && dart analyze`
Expected: verde, estável em 5 execuções seguidas, analyze no baseline com zero avisos.

```bash
git add backend/sinalacs_server apps
git commit -m "feat(backend): notices.sendSegmented com segmentação SQL e consentimento vigente (RF14)"
```

(`apps` porque `serverpod generate` regenera `sinalacs_client`; confirme o caminho com `git status`.)

---

### Task 4: Tela de envio no app do ACS

**Files:**
- Modify: `apps/acs/lib/app/app.dart` (`NoticesScreen`), o cliente de backend do ACS (confirme o arquivo com `grep -rn "requestDataCorrection\|patients\." apps/acs/lib/core`), `apps/acs/test/support/` (fake do backend do ACS), teste novo `apps/acs/test/notices_screen_test.dart`

**Interfaces:**
- Consumes: RPC `notices.sendSegmented` (Task 3) e `NoticeSendResult` do cliente gerado.
- Produces: no backend do ACS, `Future<NoticeSendResult> sendNotice({required String title, required String message, required bool chronicOnly})` (interface, implementação real, fake). O ACS já mantém um token de acesso com renovação silenciosa; use o mesmo helper dos outros métodos.

- [ ] **Step 1: Testes vermelhos**

```dart
testWidgets('enviar chama o backend com título, mensagem e público e mostra o resultado', (tester) async {
  final backend = FakeAcsBackend();
  await abrirAvisos(tester, backend);
  await tester.enterText(find.byKey(const Key('notice_title_field')), 'Vacinação');
  await tester.enterText(find.byKey(const Key('notice_message_field')), 'Amanhã, das 8h às 12h.');
  await tester.tap(find.byKey(const Key('notice_chronic_switch')));
  await tester.pump();
  await tester.tap(find.byKey(const Key('notice_send_button')));
  await tester.pumpAndSettle();

  expect(backend.notices, [('Vacinação', 'Amanhã, das 8h às 12h.', true)]);
  expect(find.textContaining('2 de 3'), findsOneWidget); // accepted de recipients
});

testWidgets('botão desabilitado com título ou mensagem vazios', (tester) async {
  await abrirAvisos(tester, FakeAcsBackend());
  expect(tester.widget<FilledButton>(find.byKey(const Key('notice_send_button'))).onPressed, isNull);
});

testWidgets('falha do envio mostra o erro do servidor e mantém o texto digitado', (tester) async {
  final backend = FakeAcsBackend()..noticeFailure = const BackendFailure('Não foi possível entregar o aviso agora.');
  await abrirAvisos(tester, backend);
  await tester.enterText(find.byKey(const Key('notice_title_field')), 'T');
  await tester.enterText(find.byKey(const Key('notice_message_field')), 'M');
  await tester.pump();
  await tester.tap(find.byKey(const Key('notice_send_button')));
  await tester.pumpAndSettle();
  expect(find.textContaining('Não foi possível entregar'), findsOneWidget);
  expect(tester.widget<TextField>(find.byKey(const Key('notice_message_field'))).controller!.text, 'M');
});

testWidgets('o aviso avisa que não deve conter dado de saúde e mostra os limites', (tester) async {
  await abrirAvisos(tester, FakeAcsBackend());
  expect(find.textContaining('não escreva nome nem condição de saúde'), findsOneWidget);
});
```

Use os helpers de montagem e as classes de fake do ACS (`FakeAcsBackend` é o rótulo do que o arquivo de suporte já chama; leia `apps/acs/test/support` antes). Run: `cd apps/acs && flutter test test/notices_screen_test.dart`. Expected: FAIL — os campos e `sendNotice` não existem.

- [ ] **Step 2: Implementar**

Troque o `NoticesScreen` decorativo por uma tela de estado próprio: `TextField` de título (`maxLength: 60`), de mensagem (`maxLength: 240`, `maxLines: 4`), `SwitchListTile` "Só pacientes com condição crônica" (`notice_chronic_switch`), texto de apoio "Só chega a quem aceitou receber avisos. Não escreva nome nem condição de saúde na mensagem.", botão `notice_send_button` (desabilitado sem título/mensagem e durante o envio, com `_busy`), resultado "Aviso enviado a X de Y pacientes." e erro do servidor em texto. Sem persistir rascunho. Cores com os tokens `*OnSurface` de `AcsColors`. Rode os testes (PASS), depois `flutter test && flutter analyze` no ACS.

- [ ] **Step 3: Commit**

```bash
git add apps/acs
git commit -m "feat(acs): tela de envio de aviso comunitário (RF14)"
```

---

### Task 5: Captura do token no paciente com Riverpod

**Files:**
- Create: `apps/patient/lib/core/push/push_token_provider.dart`, `apps/patient/lib/core/push/native_push_token_source.dart`, `apps/patient/test/push_riverpod_test.dart`
- Modify: `apps/patient/pubspec.yaml`, `apps/patient/lib/main.dart`, `apps/patient/lib/app/app.dart`, `apps/patient/lib/core/push/push_token_source.dart` (comentário)

**Interfaces:**
- Consumes: `PushTokenSource`, `PushDevice`, `registerPushDevice(PatientBackend, PushTokenSource)` (de `push_token_source.dart`), `PatientBackend.registerPushToken`.
- Produces: `final pushTokenSourceProvider = Provider<PushTokenSource>((ref) => const NativePushTokenSource());` (sobrescrevível em teste).
- Produces: `final pushRegistrationProvider = Provider<Future<void> Function(PatientBackend)>((ref) => (backend) => registerPushDevice(backend, ref.read(pushTokenSourceProvider)));`
- Produces: `class NativePushTokenSource implements PushTokenSource` que chama o `MethodChannel('sinalacs/push_token')`, método `getToken`, devolvendo `{'token': String, 'platform': 'android'|'ios'}`; `MissingPluginException`, `PlatformException` ou resposta malformada resultam em `null`.
- Produces: `SinalAcsApp` continua aceitando `pushTokens` (`PushTokenSource?`) — quando presente, tem precedência sobre o provider, para não reescrever os testes existentes.

**Limite honesto desta task:** o lado **nativo** do canal (Kotlin com a biblioteca do FCM e `google-services.json` no Android; Swift com o registro APNs no iOS) exige as credenciais que a organização ainda não forneceu, e o FCM no Android não tem alternativa "leve" sem a biblioteca do Firebase. Esta task entrega o lado Dart, o provider e o contrato do canal; até o lado nativo existir, o canal não responde e o app degrada para "sem push".

- [ ] **Step 1: Dependência**

`apps/patient/pubspec.yaml`: `flutter_riverpod: ^2.6.1` (confirme a versão estável e compatível com o SDK com `flutter pub add flutter_riverpod`; se a resolução falhar por conflito, rode `flutter pub deps` e registre o motivo). Run: `cd apps/patient && flutter pub get`. Expected: resolve sem alterar outras versões (confira `git diff pubspec.lock`).

- [ ] **Step 2: Testes vermelhos**

`push_riverpod_test.dart`:

```dart
testWidgets('o provider entrega o token da fonte e o registro chega ao backend', (tester) async {
  final backend = FakePatientBackend();
  await tester.pumpWidget(ProviderScope(
    overrides: [pushTokenSourceProvider.overrideWithValue(const _Fonte(PushDevice(token: 'tok-9', platform: 'android')))],
    child: SinalAcsApp(backend: backend),
  ));
  await login(tester);
  expect(backend.pushRegistrations, [('tok-9', 'android')]);
});

testWidgets('sem ProviderScope acima, o app ainda sobe e não registra', (tester) async {
  final backend = FakePatientBackend();
  await tester.pumpWidget(SinalAcsApp(backend: backend));
  await login(tester);
  expect(find.byType(PatientHomeShell), findsOneWidget);
  expect(backend.pushRegistrations, isEmpty);
});

test('NativePushTokenSource devolve null quando o canal não existe', () async {
  TestWidgetsFlutterBinding.ensureInitialized();
  expect(await const NativePushTokenSource().currentDevice(), isNull);
});

test('NativePushTokenSource lê o token e a plataforma do canal', () async {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('sinalacs/push_token'),
    (call) async => {'token': 'abc', 'platform': 'ios'},
  );
  addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('sinalacs/push_token'), null));
  final device = await const NativePushTokenSource().currentDevice();
  expect((device!.token, device.platform), ('abc', 'ios'));
});

test('resposta malformada ou plataforma desconhecida vira null', () async {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('sinalacs/push_token'),
    (call) async => {'token': '', 'platform': 'web'},
  );
  addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('sinalacs/push_token'), null));
  expect(await const NativePushTokenSource().currentDevice(), isNull);
});
```

com `_Fonte` (fonte fixa, no arquivo) e `login` copiado de `push_registration_test.dart`. Run: `flutter test test/push_riverpod_test.dart`. Expected: FAIL — provider e fonte nativa não existem.

- [ ] **Step 3: Implementar**

`native_push_token_source.dart`: `MethodChannel('sinalacs/push_token')`; `currentDevice()` chama `invokeMapMethod<String, String>('getToken')` dentro de `try`, valida `token` não vazio e `platform` em `{'android','ios'}`, e devolve `null` para `MissingPluginException`, `PlatformException` e qualquer outra falha. `push_token_provider.dart` define os dois providers acima. Em `app.dart`, `SinalAcsApp` continua sendo `StatefulWidget`; a fonte usada é `widget.pushTokens ?? _providerSource(context)`, onde `_providerSource` lê o `ProviderScope` com `ProviderScope.containerOf(context, listen: false)` **dentro de `try`** e cai em `NoPushTokenSource` se não houver escopo. `main.dart` envolve `runApp` em `ProviderScope`. O `PushTokenScope` (InheritedWidget) segue sendo o que as telas consomem, alimentado por esta fonte: o Riverpod fica só na borda de captura, como decidido. Rode os testes (PASS), depois `flutter test && flutter analyze` no paciente.

- [ ] **Step 4: Commit**

```bash
git add apps/patient
git commit -m "feat(paciente): provider Riverpod e canal nativo para o token de push (RF14)"
```

---

### Task 6: Documentação, memória e verificação final

**Files:**
- Modify: `PROGRESS.md` (seção do RF14 com Gorush entregue; pendências reais), `apps/CLAUDE.md` (Riverpod só no push, canal `sinalacs/push_token`, tela de avisos do ACS), `backend/CLAUDE.md` (`notices.sendSegmented`, `GorushClient`, `GORUSH_URL`, perfil `push`), `spec/stack.md` (Riverpod, Gorush com credenciais), `spec/lgpd_data_audit.md` (`audit_logs` com `community_notice`), `spec/lgpd_design.md` (o aviso de `segmentedPush` agora tem leitor: `sendSegmented` consulta o consentimento mais recente), `CLAUDE.md` (lista de endpoints, se citar), `README`/`backend/DEPLOY.md` se descreverem o Compose, memória `patient-push-and-minors-2026-09-29` (ou nova) e `MEMORY.md`.

- [ ] **Step 1:** Editar os docs, com contagens reais medidas. Registrar como **pendências que não são código**: credenciais FCM/APNs fornecidas pela organização, lado nativo do canal `sinalacs/push_token` (Kotlin/Swift) e teste real em aparelho, revisão jurídica do texto de `segmentedPush`, e a validação de ponta a ponta com um Gorush de verdade (só rodada com credenciais).

- [ ] **Step 2: Verificação completa**

Run: `cd backend/sinalacs_server && dart test && dart analyze; cd ../../apps/patient && flutter test && flutter analyze; cd ../acs && flutter test && flutter analyze; cd ../.. && docker compose config -q && ./scripts/qa/ci_invariants.sh; graphify update .`
Expected: backend verde (repetir 5 vezes, sem intermitência), paciente e ACS verdes, analyzes limpos/no baseline, `docker compose config -q` sem erro, `ci_invariants` ok. **Não** afirmar que o envio funciona de ponta a ponta: nenhum teste fala com um Gorush real.

- [ ] **Step 3: Commit**

```bash
git add PROGRESS.md apps/CLAUDE.md backend/CLAUDE.md spec CLAUDE.md
git commit -m "docs: registra o envio de avisos por Gorush e as pendências de credenciais"
```

---

## Fora deste plano (por decisão)

- Lado nativo do canal (Kotlin/Swift), `google-services.json`, chave APNs e o teste em aparelho: dependem de credenciais que a organização não forneceu.
- Migrar o restante do app do paciente para Riverpod (escolha do usuário: só o push).
- Salvar o token no SQLite local: hoje nenhum consumidor local precisa dele; o servidor é a fonte.
- Agendamento e histórico de avisos enviados, avisos com imagem ou ação, envio para outras microáreas.

## Autorrevisão

- **Cobertura:** revisão das specs → Task 0; Gorush e config → Task 1; cliente → Task 2; segmentação SQL + consentimento + auditoria + endpoint → Task 3; envio no ACS → Task 4; captura do token com Riverpod → Task 5; docs → Task 6. A arquitetura colada tem três blocos (Flutter+Riverpod, PostgreSQL, Gorush): Tasks 5, 3 e 1–2. O nome `user_push_tokens` não é adotado: a tabela `push_tokens` já existe (registrado na Task 0/PROGRESS).
- **Placeholders:** os pontos que dependem de nomes locais (pasta dos DTOs, colunas reais da consulta, chaves do `config.yml` do Gorush, tag da imagem, arquivo do cliente do ACS, campos de `AuditEvent`) trazem a instrução de confirmar; nenhum comportamento ficou por definir.
- **Tipos:** `PushSender`/`PushTarget`/`PushMessage`/`PushSendReport`/`PushGatewayException` (Task 2) são usados com a mesma assinatura na Task 3; `NoticeSendResult` (DTO com `recipients` e `accepted`) é o mesmo no serviço, no endpoint e no cliente do ACS; `pushTokenSourceProvider` e `NativePushTokenSource` (Task 5) usam `PushTokenSource`/`PushDevice` já existentes.
- **Risco declarado:** o `PushTokenService`/`PushTokenStore` são alterados pelo plano anterior (`menores-do-push…`); por isso a ordem de execução é fixa.
