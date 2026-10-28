# Issue #76 — Paciente vê "Atendido" (alerta chega a `resolved`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dar ao ACS a ação "Concluir atendimento", que leva o alerta vermelho de `acknowledged` a `resolved` no backend, para o paciente ver "Atendido" no painel de status (RF05, MVP-STATUS, M2.1).

**Architecture:** Novo método RPC `alerts.resolve` → `RedAlertService.resolve` → `AlertStore.resolve` (ORM com `SELECT … FOR UPDATE`, auditoria na mesma transação, fail-closed), coluna nova `alerts.resolvedAt` (migração aditiva). O ACK passa a travar a linha e nunca rebaixa `resolved` para `acknowledged`. O app do ACS ganha o botão no cartão já confirmado (com diálogo de confirmação); o app do paciente rotula `resolved` como "Atendido" e mostra a hora. O pulso do backoffice passa a enxergar a conclusão.

**Tech Stack:** Serverpod 3.4.13 (Dart), PostgreSQL, Flutter (apps `acs` e `patient`), `flutter_test`, `package:test` + harness `withServerpod`.

**Spec:** issue #76 (`gh issue view 76`), item 2 (P0) de `docs/auditoria-prd/2026-10-15-lacunas-prd.md`; requisito em `spec/PRD_system.md` §2.2 (RF05) e §6.1 ("Paciente visualiza 'Enviado → Visualizado → Atendido'").

## Global Constraints

- Idioma: código comentado, mensagens e documentação em português, como o resto do repositório.
- Nunca editar à mão `lib/src/generated/` nem `migrations/`: `serverpod generate` + `serverpod create-migration` (de `backend/sinalacs_server`).
- INV-01: o ACS só conclui alerta da própria microárea; a microárea vem do token, nunca de parâmetro.
- INV-03: alerta vermelho nunca é descartado em silêncio — `resolve` só sai de `acknowledged`; um `pending` **não** pode ser concluído (precisa de ACK antes), e toda mudança de status é auditada na mesma transação (fail-closed).
- Toda escrita em `alerts` fica em arquivo listado em `_allowedWriters` de `test/unit/red_alert_discard_paths_test.dart`.
- Cor é sinal clínico: textos/ícones sobre `Card` usam os tokens `*OnSurface` (`context.acsRisk.greenOnSurface`, `context.patientRisk.accentOnSurface`).
- Alvos de toque ≥ 48×52 dp (`minimumSize: const Size(48, 52)`).
- Sem dado real de paciente em teste, log ou captura; ids sintéticos.
- Commits sem atribuição de IA (regra do `CLAUDE.md` da raiz, que prevalece sobre o lembrete de atribuição).
- Testes de integração do backend: `docker compose --profile test up -d postgres-test` e `dart test -j 1`.

## Review Focus

1. **ACK depois da conclusão** (reentrega MQTT, toque atrasado em outro aparelho): o alerta deve continuar `resolved`; o ACK antigo sobrescrevia o status sem reler. Pinado na Task 2 (`confirmar de novo depois de concluído não volta a acknowledged`).
2. **Concluir um alerta ainda `pending`** (ACS pula a confirmação, ou o ACK falhou em silêncio): recusa com mensagem clara, alerta segue `pending` e a recusa entra na trilha. Pinado nas Tasks 1 e 2.
3. **Concluir duas vezes** (toque duplo, retry de rede): resposta idempotente, `resolvedAt` original preservado, sem segunda transição. Pinado nas Tasks 1 e 2 (`already_resolved`); a trava `_concluindo` da Task 4 é só defesa, e o servidor é a garantia.
4. **Alerta de outra microárea ou id que não é UUID**: `resolved: false`, nada muda, nada é gravado (mesma resposta do ACK para inexistente). Pinado na Task 2.
5. **Backoffice não percebe a conclusão** (o pulso só olhava `triggeredAt`/`acknowledgedAt`/`escalatedAt`): a lista de Alertas ficaria mostrando "Reconhecido" até outro evento. Pinado na Task 3.

---

## File Structure

| Arquivo | Responsabilidade |
|---|---|
| `backend/sinalacs_server/lib/src/application/alerts/red_alert_service.dart` | `AlertResolveOutcome`, `AlertResolveAttempt`, `AlertStore.resolve`, `RedAlertService.resolve`, `AlertStatusSnapshot.resolvedAt` |
| `backend/sinalacs_server/lib/src/models/alert.spy.yaml` | coluna `resolvedAt` |
| `backend/sinalacs_server/lib/src/models/api/alert_status_result.spy.yaml` | campo `resolvedAt` |
| `backend/sinalacs_server/lib/src/models/api/alert_resolve_result.spy.yaml` (novo) | resultado do `alerts.resolve` |
| `backend/sinalacs_server/lib/src/infrastructure/database/orm_alert_store.dart` | `resolve` com trava; ACK trava e preserva `resolved`; `latestForPatient` com `resolvedAt` |
| `backend/sinalacs_server/lib/src/endpoints/alerts_endpoint.dart` | `alerts.resolve`; `statusFor` devolve `resolvedAt` |
| `backend/sinalacs_server/lib/src/infrastructure/database/orm_admin_read_store.dart` | `pulse.maxChangedAt` inclui `resolvedAt` |
| `apps/acs/lib/core/network/backend_client.dart` | `AcsBackend.resolveAlert` |
| `apps/acs/lib/core/services/alert_queue.dart` | `PrioritizedAlert.resolved`, `AlertQueue.markResolved`, ordenação |
| `apps/acs/lib/app/app.dart` | botão "Concluir atendimento", diálogo, `_resolve` |
| `apps/patient/lib/app/app.dart` | rótulo "Atendido" e hora da conclusão |
| docs (`PROGRESS.md`, `spec/lgpd_data_audit.md`, `docs/auditoria-prd/2026-10-15-lacunas-prd.md`, `CLAUDE.md`, `backend/CLAUDE.md`) | registro |

---

### Task 1: Regra de conclusão no serviço (hermético)

**Files:**
- Modify: `backend/sinalacs_server/lib/src/application/alerts/red_alert_service.dart`
- Modify (fakes): `backend/sinalacs_server/test/unit/red_alert_service_test.dart`, `test/unit/red_alert_discard_paths_test.dart` (`_MemoryStore`), `test/unit/red_alert_lifecycle_test.dart` (`RecordingStore`)
- Test: `backend/sinalacs_server/test/unit/red_alert_service_test.dart`

**Interfaces:**
- Consumes: `Authorization.require`, `AuditEvent`, `AuthenticatedUser`, `UserRole` (existentes).
- Produces:
  - `enum AlertResolveOutcome { notFound, notAcknowledged, resolved, alreadyResolved }`
  - `class AlertResolveAttempt { const AlertResolveAttempt(this.outcome, {this.resolvedAt}); final AlertResolveOutcome outcome; final DateTime? resolvedAt; }`
  - `AlertStore.resolve({required String alertId, required String microAreaId, required DateTime now, required AuditEvent Function(AlertResolveOutcome outcome) auditFor}) → Future<AlertResolveAttempt>`
  - `RedAlertService.resolve({required AuthenticatedUser user, required String alertId}) → Future<AlertResolveAttempt>` (lança `StateError` para papel/território, `ArgumentError` para id vazio e para `notAcknowledged`)
  - `RedAlertService.notAcknowledgedMessage = 'Confirme o recebimento antes de concluir o atendimento.'`
  - `AlertStatusSnapshot.resolvedAt` (`DateTime?`, parâmetro nomeado opcional)

- [ ] **Step 1: Escrever os testes que falham**

Em `test/unit/red_alert_service_test.dart`, acrescentar ao `FakeAlertStore` (logo depois de `latestForPatient`):

```dart
  /// Desfecho que o "banco" decide para o próximo `resolve` (#76).
  AlertResolveOutcome resolveOutcome = AlertResolveOutcome.resolved;
  final List<({String alertId, String microAreaId, DateTime now})> resolveCalls = [];

  @override
  Future<AlertResolveAttempt> resolve({
    required String alertId,
    required String microAreaId,
    required DateTime now,
    required AuditEvent Function(AlertResolveOutcome outcome) auditFor,
  }) async {
    resolveCalls.add((alertId: alertId, microAreaId: microAreaId, now: now));
    // Mesma regra do store real: inexistente/fora do território não grava.
    if (resolveOutcome != AlertResolveOutcome.notFound) {
      audits.add(auditFor(resolveOutcome));
    }
    final carimbo = switch (resolveOutcome) {
      AlertResolveOutcome.resolved || AlertResolveOutcome.alreadyResolved => now,
      _ => null,
    };
    return AlertResolveAttempt(resolveOutcome, resolvedAt: carimbo);
  }
```

E, antes de `group('statusFor (RF05)'`, o grupo novo:

```dart
  group('resolve (#76)', () {
    const acs = AuthenticatedUser(
      id: 'acs-001',
      role: UserRole.acs,
      microAreaId: 'area-12',
      deviceId: 'device-001',
    );
    final agora = DateTime.utc(2026, 10, 16, 14);

    RedAlertService servico(FakeAlertStore store) => RedAlertService(
          store: store,
          outbox: FakeAlertOutbox(),
          clock: () => agora,
        );

    test('conclui no território do token e audita resolved', () async {
      final store = FakeAlertStore();

      final r = await servico(store).resolve(user: acs, alertId: 'alerta-1');

      expect(r.outcome, AlertResolveOutcome.resolved);
      expect(r.resolvedAt, agora);
      expect(store.resolveCalls.single.microAreaId, 'area-12');
      expect(store.resolveCalls.single.now, agora);
      final audit = store.audits.single;
      expect(audit.userId, 'acs-001');
      expect(audit.actionType, 'write');
      expect(audit.resourceType, 'alert');
      expect(audit.resourceId, 'alerta-1');
      expect(audit.result, 'resolved');
    });

    test('repetir a conclusão é idempotente e audita already_resolved', () async {
      final store = FakeAlertStore()..resolveOutcome = AlertResolveOutcome.alreadyResolved;

      final r = await servico(store).resolve(user: acs, alertId: 'alerta-1');

      expect(r.outcome, AlertResolveOutcome.alreadyResolved);
      expect(store.audits.single.result, 'already_resolved');
    });

    test('alerta ainda pending é recusado com a mensagem e a recusa é auditada', () async {
      final store = FakeAlertStore()..resolveOutcome = AlertResolveOutcome.notAcknowledged;

      await expectLater(
        servico(store).resolve(user: acs, alertId: 'alerta-1'),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          RedAlertService.notAcknowledgedMessage,
        )),
      );
      expect(store.audits.single.result, 'denied_not_acknowledged');
    });

    test('alerta inexistente ou de outra microárea devolve notFound sem auditar', () async {
      final store = FakeAlertStore()..resolveOutcome = AlertResolveOutcome.notFound;

      final r = await servico(store).resolve(user: acs, alertId: 'alerta-1');

      expect(r.outcome, AlertResolveOutcome.notFound);
      expect(r.resolvedAt, isNull);
      expect(store.audits, isEmpty);
    });

    test('paciente não conclui atendimento', () async {
      final store = FakeAlertStore();
      const paciente = AuthenticatedUser(
        id: 'paciente-1',
        role: UserRole.patient,
        microAreaId: 'area-12',
        deviceId: 'device-1',
      );

      await expectLater(
        servico(store).resolve(user: paciente, alertId: 'alerta-1'),
        throwsA(isA<StateError>()),
      );
      expect(store.resolveCalls, isEmpty);
    });

    test('ACS sem microárea não conclui atendimento', () async {
      final store = FakeAlertStore();
      const semArea = AuthenticatedUser(
        id: 'acs-002',
        role: UserRole.acs,
        microAreaId: null,
        deviceId: 'device-2',
      );

      await expectLater(
        servico(store).resolve(user: semArea, alertId: 'alerta-1'),
        throwsA(isA<StateError>()),
      );
      expect(store.resolveCalls, isEmpty);
    });

    test('identificador vazio é recusado antes do store', () async {
      final store = FakeAlertStore();

      await expectLater(
        servico(store).resolve(user: acs, alertId: '  '),
        throwsA(isA<ArgumentError>()),
      );
      expect(store.resolveCalls, isEmpty);
    });
  });
```

Nos outros dois fakes, só para compilar (nenhum teste deles conclui alerta):

`test/unit/red_alert_discard_paths_test.dart`, dentro de `_MemoryStore`:

```dart
  @override
  Future<AlertResolveAttempt> resolve({
    required String alertId,
    required String microAreaId,
    required DateTime now,
    required AuditEvent Function(AlertResolveOutcome outcome) auditFor,
  }) async {
    if (status[alertId] != 'acknowledged') {
      return const AlertResolveAttempt(AlertResolveOutcome.notAcknowledged);
    }
    audits.add(auditFor(AlertResolveOutcome.resolved));
    status[alertId] = 'resolved';
    return AlertResolveAttempt(AlertResolveOutcome.resolved, resolvedAt: now);
  }
```

`test/unit/red_alert_lifecycle_test.dart`, dentro de `RecordingStore`:

```dart
  @override
  Future<AlertResolveAttempt> resolve({
    required String alertId,
    required String microAreaId,
    required DateTime now,
    required AuditEvent Function(AlertResolveOutcome outcome) auditFor,
  }) async {
    throw UnimplementedError('não usado nos testes deste arquivo');
  }
```

(Se `red_alert_lifecycle_test.dart` não importar `audit_trail.dart`, acrescente `import 'package:sinalacs_server/src/application/audit/audit_trail.dart';`.)

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd backend/sinalacs_server && dart test test/unit/red_alert_service_test.dart`
Expected: FAIL de compilação — `AlertResolveOutcome`/`AlertResolveAttempt` não definidos.

- [ ] **Step 3: Implementar**

Em `lib/src/application/alerts/red_alert_service.dart`:

1. Na interface `AlertStore`, depois de `acknowledge`:

```dart
  /// Conclui o atendimento (#76): leva o alerta de `acknowledged` a
  /// `resolved` no território do ACS. O desfecho é decidido sob trava da
  /// linha, e `auditFor(desfecho)` é gravado na MESMA transação (fail-closed)
  /// — exceto [AlertResolveOutcome.notFound], que não grava nada, como o ACK.
  Future<AlertResolveAttempt> resolve({
    required String alertId,
    required String microAreaId,
    required DateTime now,
    required AuditEvent Function(AlertResolveOutcome outcome) auditFor,
  });
```

2. Depois da classe `RedAlertRecord`:

```dart
/// Desfecho de [AlertStore.resolve] (#76).
enum AlertResolveOutcome {
  /// Inexistente ou de outra microárea: a mesma resposta, nada gravado.
  notFound,

  /// Ainda `pending`: o recebimento precisa ser confirmado antes (INV-03 —
  /// concluir sem ACK apagaria do painel um vermelho que ninguém confirmou).
  notAcknowledged,

  /// `acknowledged` → `resolved` agora.
  resolved,

  /// Já estava `resolved`: nada muda e o `resolvedAt` original volta.
  alreadyResolved,
}

class AlertResolveAttempt {
  const AlertResolveAttempt(this.outcome, {this.resolvedAt});

  final AlertResolveOutcome outcome;

  /// Quando o atendimento foi concluído; nulo em [AlertResolveOutcome.notFound]
  /// e [AlertResolveOutcome.notAcknowledged].
  final DateTime? resolvedAt;
}
```

3. Em `AlertStatusSnapshot`, acrescentar `this.resolvedAt,` ao construtor e o campo:

```dart
  /// Conclusão do atendimento pelo ACS (#76); nulo até lá.
  final DateTime? resolvedAt;
```

4. Em `RedAlertService`, depois de `acknowledge`:

```dart
  /// Texto da recusa de concluir um alerta que ninguém confirmou (#76).
  static const notAcknowledgedMessage =
      'Confirme o recebimento antes de concluir o atendimento.';

  /// Conclui o atendimento (#76, RF05): é a transição que faz o paciente ver
  /// "Atendido". Só o ACS do território do alerta, e só depois do ACK.
  /// Cada ato que encontra o alerta é auditado, inclusive a repetição e a
  /// recusa por falta de ACK; a recusa vira [ArgumentError] DEPOIS de a
  /// trilha gravar.
  Future<AlertResolveAttempt> resolve({
    required AuthenticatedUser user,
    required String alertId,
  }) async {
    Authorization.require(
      user,
      roles: {UserRole.acs},
      onDenied: () =>
          StateError('Somente ACS territorializados podem concluir atendimentos.'),
    );
    if (alertId.trim().isEmpty) {
      throw ArgumentError('O identificador do alerta é obrigatório.');
    }
    final attempt = await _store.resolve(
      alertId: alertId,
      microAreaId: user.microAreaId!,
      now: _clock().toUtc(),
      auditFor: (outcome) => AuditEvent(
        userId: user.id,
        actionType: 'write',
        resourceType: 'alert',
        resourceId: alertId,
        result: switch (outcome) {
          AlertResolveOutcome.resolved => 'resolved',
          AlertResolveOutcome.alreadyResolved => 'already_resolved',
          AlertResolveOutcome.notAcknowledged => 'denied_not_acknowledged',
          // O store não grava este; o texto existe só para o switch ser total.
          AlertResolveOutcome.notFound => 'denied_not_found',
        },
      ),
    );
    if (attempt.outcome == AlertResolveOutcome.notAcknowledged) {
      throw ArgumentError(notAcknowledgedMessage);
    }
    return attempt;
  }
```

5. Em `lib/src/infrastructure/database/orm_alert_store.dart`, um stub temporário só para compilar (a Task 2 o substitui; não faça commit sem a Task 2 se preferir commits verdes ponta a ponta — o stub mantém `dart analyze` limpo):

```dart
  @override
  Future<AlertResolveAttempt> resolve({
    required String alertId,
    required String microAreaId,
    required DateTime now,
    required AuditEvent Function(AlertResolveOutcome outcome) auditFor,
  }) =>
      throw UnimplementedError('Task 2 (#76)');
```

- [ ] **Step 4: Rodar e ver passar**

Run: `cd backend/sinalacs_server && dart test test/unit && dart analyze`
Expected: PASS (todos os unitários, incluindo os 7 novos de `resolve (#76)`); analyze sem issues.

- [ ] **Step 5: Commit**

```bash
git add backend/sinalacs_server/lib/src/application/alerts/red_alert_service.dart \
  backend/sinalacs_server/lib/src/infrastructure/database/orm_alert_store.dart \
  backend/sinalacs_server/test/unit/red_alert_service_test.dart \
  backend/sinalacs_server/test/unit/red_alert_discard_paths_test.dart \
  backend/sinalacs_server/test/unit/red_alert_lifecycle_test.dart
git commit -m "feat(backend): regra de concluir o atendimento do alerta (#76)"
```

---

### Task 2: Coluna, store ORM, ACK que não rebaixa e `alerts.resolve`

**Files:**
- Modify: `backend/sinalacs_server/lib/src/models/alert.spy.yaml`
- Modify: `backend/sinalacs_server/lib/src/models/api/alert_status_result.spy.yaml`
- Create: `backend/sinalacs_server/lib/src/models/api/alert_resolve_result.spy.yaml`
- Modify: `backend/sinalacs_server/lib/src/infrastructure/database/orm_alert_store.dart`
- Modify: `backend/sinalacs_server/lib/src/endpoints/alerts_endpoint.dart`
- Modify: `backend/sinalacs_server/test/unit/red_alert_discard_paths_test.dart` (só o texto de `_allowedWriters`)
- Generated: `lib/src/generated/**`, `backend/sinalacs_client/**`, `test/integration/test_tools/serverpod_test_tools.dart`, `migrations/<novo>/`
- Test: `backend/sinalacs_server/test/integration/red_alert_cycle_test.dart`

**Interfaces:**
- Consumes: tudo o que a Task 1 produz.
- Produces:
  - Coluna `alerts."resolvedAt"` (`timestamp without time zone`, nula).
  - `AlertStatusResult.resolvedAt: DateTime?`.
  - `AlertResolveResult { String alertId; bool resolved; AlertStatus? status; DateTime? resolvedAt; }` (no cliente gerado também).
  - RPC `alerts.resolve(accessToken: String, alertId: String) → AlertResolveResult`; lança `AlertValidationException` (id vazio, `notAcknowledged`) e `AlertPermissionException` (papel/território do token).

- [ ] **Step 1: Modelos**

`lib/src/models/alert.spy.yaml`, logo depois de `acknowledgedAt: DateTime?`:

```yaml
  ### Atendimento concluído pelo ACS (#76): carimbado uma única vez, na
  ### transição acknowledged → resolved. Nulo enquanto não foi atendido.
  resolvedAt: DateTime?
```

`lib/src/models/api/alert_status_result.spy.yaml`, ao fim de `fields:`:

```yaml
  resolvedAt: DateTime?
```

Criar `lib/src/models/api/alert_resolve_result.spy.yaml`:

```yaml
### Resultado de alerts.resolve (#76).
###
### Mesmo desenho de AlertAckResult: resolved: false significa que não havia
### alerta com esse id na microárea do ACS. Concluir duas vezes devolve
### resolved: true com o resolvedAt da primeira conclusão.
class: AlertResolveResult
fields:
  alertId: String
  resolved: bool
  status: AlertStatus?
  resolvedAt: DateTime?
```

- [ ] **Step 2: Gerar código e migração**

```bash
cd backend/sinalacs_server
serverpod generate
serverpod create-migration
```

Expected: novo diretório em `migrations/` cujo `migration.sql` contém só `ALTER TABLE "alerts" ADD COLUMN "resolvedAt" timestamp without time zone;` (aditiva, sem `DROP`). Confira: `rtk proxy grep -c DROP migrations/$(ls migrations | grep -v registry | tail -1)/migration.sql` deve dar `0`.

- [ ] **Step 3: Escrever os testes de integração que falham**

Em `test/integration/red_alert_cycle_test.dart`, dentro de `withServerpod('Dado o ciclo de alerta vermelho', …)`, depois do teste `'paciente consulta o status do próprio alerta mais recente'`:

```dart
    group('concluir o atendimento (#76)', () {
      Future<({String alertId, String acs})> alertaConfirmado() async {
        await _seed(sessionBuilder.build());
        final paciente =
            await endpoints.auth.developmentLogin(sessionBuilder, role: 'patient');
        final criado = await endpoints.alerts.createRedAlert(
          sessionBuilder,
          accessToken: paciente.accessToken,
          idempotencyKey: 'resolve-${DateTime.now().microsecondsSinceEpoch}',
          locationHash: 'hash-sintetico',
        );
        final acs = await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs');
        await endpoints.alerts.acknowledge(
          sessionBuilder,
          accessToken: acs.accessToken,
          alertId: criado.alertId,
        );
        return (alertId: criado.alertId, acs: acs.accessToken);
      }

      Future<List<String>> resultadosDaTrilha(String alertId) async {
        final linhas = await AuditLog.db.find(
          sessionBuilder.build(),
          where: (t) =>
              t.resourceType.equals('alert') &
              t.resourceId.equals(UuidValue.fromString(alertId)),
          orderBy: (t) => t.sequence,
        );
        return linhas.map((l) => l.result).toList();
      }

      test('leva a resolved, o paciente vê e repetir preserva o resolvedAt', () async {
        final (:alertId, :acs) = await alertaConfirmado();

        final r = await endpoints.alerts.resolve(
          sessionBuilder,
          accessToken: acs,
          alertId: alertId,
        );
        expect(r.resolved, isTrue);
        expect(r.status, AlertStatus.resolved);
        expect(r.resolvedAt, isNotNull);

        final paciente =
            await endpoints.auth.developmentLogin(sessionBuilder, role: 'patient');
        final status = await endpoints.alerts.statusFor(
          sessionBuilder,
          accessToken: paciente.accessToken,
        );
        expect(status.status, AlertStatus.resolved);
        expect(status.resolvedAt, r.resolvedAt);
        expect(status.acknowledgedAt, isNotNull);

        final deNovo = await endpoints.alerts.resolve(
          sessionBuilder,
          accessToken: acs,
          alertId: alertId,
        );
        expect(deNovo.resolved, isTrue);
        expect(deNovo.resolvedAt, r.resolvedAt);

        expect(await resultadosDaTrilha(alertId),
            ['acknowledged', 'resolved', 'already_resolved']);
      });

      test('alerta ainda pending é recusado e segue pending', () async {
        await _seed(sessionBuilder.build());
        final paciente =
            await endpoints.auth.developmentLogin(sessionBuilder, role: 'patient');
        final criado = await endpoints.alerts.createRedAlert(
          sessionBuilder,
          accessToken: paciente.accessToken,
          idempotencyKey: 'resolve-pending',
          locationHash: 'hash-sintetico',
        );
        final acs = await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs');

        await expectLater(
          endpoints.alerts.resolve(
            sessionBuilder,
            accessToken: acs.accessToken,
            alertId: criado.alertId,
          ),
          throwsA(isA<AlertValidationException>().having(
            (e) => e.message,
            'message',
            RedAlertService.notAcknowledgedMessage,
          )),
        );

        final linha = await Alert.db.findById(
          sessionBuilder.build(),
          UuidValue.fromString(criado.alertId),
        );
        expect(linha!.status, AlertStatus.pending);
        expect(linha.resolvedAt, isNull);
        expect(await resultadosDaTrilha(criado.alertId), ['denied_not_acknowledged']);
      });

      test('confirmar de novo depois de concluído não volta a acknowledged', () async {
        final (:alertId, :acs) = await alertaConfirmado();
        await endpoints.alerts.resolve(sessionBuilder, accessToken: acs, alertId: alertId);

        final ack = await endpoints.alerts.acknowledge(
          sessionBuilder,
          accessToken: acs,
          alertId: alertId,
        );
        expect(ack.acknowledged, isTrue);

        final linha = await Alert.db.findById(
          sessionBuilder.build(),
          UuidValue.fromString(alertId),
        );
        expect(linha!.status, AlertStatus.resolved);
        expect(linha.resolvedAt, isNotNull);
      });

      test('alerta de outra microárea: resolved false, nada muda nem é auditado', () async {
        await _seed(sessionBuilder.build());
        final session = sessionBuilder.build();
        final outro = await Alert.db.insertRow(
          session,
          Alert(
            patientId: UuidValue.fromString(_patientId),
            microAreaId: UuidValue.fromString('00000000-0000-4000-8000-0000000076aa'),
            triggeredAt: DateTime.now().toUtc(),
            acknowledgedAt: DateTime.now().toUtc(),
            riskLevel: RiskLevel.red,
            locationHash: 'hash-sintetico',
            status: AlertStatus.acknowledged,
            mqttTopic: 'sinalacs/v1/microareas/outra/alerts',
            deviceId: 'device-sintetico',
            retryCount: 0,
            version: 1,
          ),
        );
        final acs = await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs');

        final r = await endpoints.alerts.resolve(
          sessionBuilder,
          accessToken: acs.accessToken,
          alertId: outro.id!.uuid,
        );

        expect(r.resolved, isFalse);
        expect(r.status, isNull);
        expect((await Alert.db.findById(session, outro.id!))!.status,
            AlertStatus.acknowledged);
        expect(await resultadosDaTrilha(outro.id!.uuid), isEmpty);
      });

      test('identificador que não é UUID devolve resolved false', () async {
        await _seed(sessionBuilder.build());
        final acs = await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs');

        final r = await endpoints.alerts.resolve(
          sessionBuilder,
          accessToken: acs.accessToken,
          alertId: 'nao-e-uuid',
        );

        expect(r.resolved, isFalse);
      });

      test('paciente não conclui atendimento', () async {
        final (:alertId, acs: _) = await alertaConfirmado();
        final paciente =
            await endpoints.auth.developmentLogin(sessionBuilder, role: 'patient');

        await expectLater(
          endpoints.alerts.resolve(
            sessionBuilder,
            accessToken: paciente.accessToken,
            alertId: alertId,
          ),
          throwsA(isA<AlertPermissionException>()),
        );
      });
    });
```

Se o arquivo ainda não importar `red_alert_service.dart`, ele já importa (linha 3); `AuditLog` vem de `generated/protocol.dart`.

- [ ] **Step 4: Rodar e ver falhar**

Run: `docker compose --profile test up -d postgres-test && cd backend/sinalacs_server && dart test -j 1 test/integration/red_alert_cycle_test.dart`
Expected: FAIL — `UnimplementedError('Task 2 (#76)')` (o endpoint `resolve` ainda não existe → também falha de compilação; qualquer um dos dois serve como "vermelho").

- [ ] **Step 5: Implementar o store**

Em `lib/src/infrastructure/database/orm_alert_store.dart`:

1. Import: `import 'package:uuid/uuid.dart';` (já dependência do servidor — `red_alert_service.dart` a usa).

2. Substituir o stub de `resolve` por:

```dart
  @override
  Future<AlertResolveAttempt> resolve({
    required String alertId,
    required String microAreaId,
    required DateTime now,
    required AuditEvent Function(AlertResolveOutcome outcome) auditFor,
  }) async {
    // Id que não é UUID é "não existe", não erro de servidor: mesma resposta
    // de um alerta de outra microárea.
    if (!Uuid.isValidUUID(fromString: alertId) ||
        !Uuid.isValidUUID(fromString: microAreaId)) {
      return const AlertResolveAttempt(AlertResolveOutcome.notFound);
    }
    final session = _session();

    Future<AlertResolveAttempt> run(Transaction transaction) async {
      // Escopo e trava numa instrução. O predicado de microárea é a barreira
      // de territorialização (INV-01); o FOR UPDATE serializa com o ACK e com
      // o escalonamento, que releem o status sob a mesma trava.
      final linhas = await session.db.unsafeQuery(
        '''
        SELECT status, "resolvedAt"
        FROM alerts
        WHERE id = @id::uuid AND "microAreaId" = @ma::uuid
        FOR UPDATE
        ''',
        parameters: QueryParameters.named({'id': alertId, 'ma': microAreaId}),
        transaction: transaction,
      );
      if (linhas.isEmpty) {
        return const AlertResolveAttempt(AlertResolveOutcome.notFound);
      }

      final status = linhas.single[0] as String;
      final AlertResolveAttempt attempt;
      if (status == AlertStatus.resolved.name) {
        attempt = AlertResolveAttempt(
          AlertResolveOutcome.alreadyResolved,
          resolvedAt: (linhas.single[1] as DateTime?)?.toUtc(),
        );
      } else if (status != AlertStatus.acknowledged.name) {
        attempt = const AlertResolveAttempt(AlertResolveOutcome.notAcknowledged);
      } else {
        final agora = now.toUtc();
        // Só status e resolvedAt: as colunas do ACK e do escalonamento ficam.
        await session.db.unsafeExecute(
          '''
          UPDATE alerts
          SET status = @resolvido, "resolvedAt" = @agora::timestamp
          WHERE id = @id::uuid
          ''',
          parameters: QueryParameters.named({
            'id': alertId,
            'resolvido': AlertStatus.resolved.name,
            'agora': agora,
          }),
          transaction: transaction,
        );
        attempt = AlertResolveAttempt(AlertResolveOutcome.resolved, resolvedAt: agora);
      }

      // Fail-closed e por último, como no ACK: a trava da cadeia nunca
      // precede outra.
      await _appendAudit(session, transaction, auditFor(attempt.outcome));
      return attempt;
    }

    final existing = _transaction;
    return existing != null ? run(existing) : session.db.transaction(run);
  }
```

3. Em `acknowledge`, dentro de `run`, trocar a leitura sem trava

```dart
      final alert = await Alert.db.findFirstRow(
        session,
        where: (t) =>
            t.id.equals(alertUuid) & t.microAreaId.equals(microAreaUuid),
        transaction: transaction,
      );
      if (alert == null) return false;
```

por

```dart
      // Trava antes de ler (#76): um `resolve` concorrente que já gravou
      // `resolved` é visto aqui, em vez de ser sobrescrito por um ACK que leu
      // a linha antes dele.
      final travado = await session.db.unsafeQuery(
        '''
        SELECT id FROM alerts
        WHERE id = @id::uuid AND "microAreaId" = @ma::uuid
        FOR UPDATE
        ''',
        parameters: QueryParameters.named({'id': alertId, 'ma': microAreaId}),
        transaction: transaction,
      );
      if (travado.isEmpty) return false;
      final alert =
          (await Alert.db.findById(session, alertUuid, transaction: transaction))!;
```

e, no `copyWith` do `updateRow`, trocar `status: AlertStatus.acknowledged,` por:

```dart
          // ACK depois da conclusão (reentrega, outro aparelho) não rebaixa
          // o atendimento já concluído (#76).
          status: alert.status == AlertStatus.resolved
              ? AlertStatus.resolved
              : AlertStatus.acknowledged,
```

4. Em `latestForPatient`, acrescentar `resolvedAt: row.resolvedAt,` ao `AlertStatusSnapshot(...)`.

- [ ] **Step 6: Implementar o endpoint**

Em `lib/src/endpoints/alerts_endpoint.dart`:

1. Depois de `acknowledge`:

```dart
  /// Conclui o atendimento de um alerta já confirmado (#76, RF05): é o que
  /// faz o paciente ver "Atendido". Alerta inexistente ou de outra microárea
  /// devolve `resolved: false`, como o ACK; alerta ainda não confirmado é
  /// [AlertValidationException] com o texto de
  /// `RedAlertService.notAcknowledgedMessage`.
  Future<AlertResolveResult> resolve(
    Session session, {
    required String accessToken,
    required String alertId,
  }) async {
    final user = authenticate(accessToken);
    final service = AlertRuntime.instance.serviceFor(session);

    try {
      final attempt = await service.resolve(user: user, alertId: alertId);
      final found = attempt.outcome != AlertResolveOutcome.notFound;
      return AlertResolveResult(
        alertId: alertId,
        resolved: found,
        status: found ? AlertStatus.resolved : null,
        resolvedAt: attempt.resolvedAt,
      );
    } on ArgumentError catch (error) {
      throw AlertValidationException(message: '${error.message}');
    } on StateError catch (error) {
      throw AlertPermissionException(message: error.message);
    }
  }
```

e o import `import 'package:sinalacs_server/src/application/alerts/red_alert_service.dart';` (para `AlertResolveOutcome`).

2. Em `statusFor`, acrescentar `resolvedAt: snapshot.resolvedAt,` ao `AlertStatusResult(...)`.

3. Em `test/unit/red_alert_discard_paths_test.dart`, atualizar o motivo de `orm_alert_store.dart` em `_allowedWriters`:

```dart
  'infrastructure/database/orm_alert_store.dart':
      'save() insere o alerta como pending; acknowledge() leva a acknowledged '
      '(e preserva resolved); resolve() leva acknowledged → resolved, sob '
      'trava e auditado na mesma transação (#76)',
```

- [ ] **Step 7: Regenerar e rodar**

```bash
cd backend/sinalacs_server
serverpod generate   # o método novo entra no cliente e no test_tools
dart test -j 1 test/integration/red_alert_cycle_test.dart test/integration/red_alert_discard_paths_db_test.dart test/unit
dart analyze
```

Expected: PASS em todos (os 6 novos de `concluir o atendimento (#76)` incluídos); analyze limpo. Se `endpoint_auth_posture_test.dart` reclamar, confira que `resolve` chama `authenticate(accessToken)` (é o que ele exige).

- [ ] **Step 8: Commit**

```bash
git add backend/sinalacs_server/lib backend/sinalacs_server/migrations \
  backend/sinalacs_server/test backend/sinalacs_client
git commit -m "feat(backend): alerts.resolve leva o alerta confirmado a resolved (#76)"
```

---

### Task 3: Pulso do backoffice enxerga a conclusão

**Files:**
- Modify: `backend/sinalacs_server/lib/src/infrastructure/database/orm_admin_read_store.dart` (SQL de `pulse`, ~linha 95)
- Test: `backend/sinalacs_server/test/integration/admin_monitoring_store_test.dart`

**Interfaces:**
- Consumes: coluna `alerts."resolvedAt"` (Task 2).
- Produces: `AlertsPulseCounts.maxChangedAt` também avança com `resolvedAt`.

- [ ] **Step 1: Escrever o teste que falha**

Em `test/integration/admin_monitoring_store_test.dart`, logo depois de `test('maxChangedAt anda com o ACK do alerta', …)`:

```dart
    test('maxChangedAt anda com a conclusão do atendimento (#76)', () async {
      final a = await _alerta(
        session,
        em: _t.subtract(const Duration(hours: 1)),
      );
      final ack = _t.subtract(const Duration(minutes: 10));
      final concluido = _t.subtract(const Duration(minutes: 2));
      await Alert.db.updateRow(
        session,
        a.copyWith(
          status: AlertStatus.resolved,
          acknowledgedAt: ack,
          resolvedAt: concluido,
        ),
      );

      final r = await pulso(const AdminScope.ubs(_ubsA));
      expect(r.maxChangedAt, concluido);
      expect(r.overdueRed, 0);
    });
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd backend/sinalacs_server && dart test -j 1 test/integration/admin_monitoring_store_test.dart`
Expected: FAIL — `maxChangedAt` é `ack`, não `concluido`.

- [ ] **Step 3: Implementar**

No SQL de `pulse`, trocar

```sql
        max(GREATEST(a."triggeredAt",
                     COALESCE(a."acknowledgedAt", a."triggeredAt"),
                     COALESCE(a."escalatedAt", a."triggeredAt")))
```

por

```sql
        max(GREATEST(a."triggeredAt",
                     COALESCE(a."acknowledgedAt", a."triggeredAt"),
                     COALESCE(a."escalatedAt", a."triggeredAt"),
                     COALESCE(a."resolvedAt", a."triggeredAt")))
```

- [ ] **Step 4: Rodar e ver passar**

Run: `cd backend/sinalacs_server && dart test -j 1 test/integration/admin_monitoring_store_test.dart test/integration/admin_read_store_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/sinalacs_server/lib/src/infrastructure/database/orm_admin_read_store.dart \
  backend/sinalacs_server/test/integration/admin_monitoring_store_test.dart
git commit -m "fix(backend): pulso do backoffice anda com a conclusão do alerta (#76)"
```

---

### Task 4: App do ACS — "Concluir atendimento"

**Files:**
- Modify: `apps/acs/lib/core/network/backend_client.dart` (interface `AcsBackend` ~linha 128, recusador ~linha 251, `BackendClient` ~linha 718)
- Modify: `apps/acs/lib/core/services/alert_queue.dart`
- Modify: `apps/acs/lib/app/app.dart` (`_acknowledge` ~linha 1610, `onAcknowledge:` ~1966, `DashboardScreen` ~2171, `_AlertCard` ~2285)
- Modify: `apps/acs/test/support/fakes.dart` (`FakeAcsBackend`)
- Modify: `apps/acs/integration_test/full_journey_e2e.dart` (`_EnvioDeVisitasForaDoAr`, só repasse)
- Create: `apps/acs/test/alert_resolve_test.dart`

**Interfaces:**
- Consumes: `AlertResolveResult` e `endpoint alerts.resolve` do cliente gerado (Task 2).
- Produces:
  - `AcsBackend.resolveAlert({required String alertId}) → Future<AlertResolveResult>`
  - `PrioritizedAlert.resolved` (`bool`, padrão `false`); `copyWith({bool? acknowledged, bool? escalated, bool? resolved})`
  - `AlertQueue.markResolved(String alertId) → bool`
  - `DashboardScreen(onResolve: void Function(PrioritizedAlert)?)`; chaves `resolve_<alertId>`, `confirmar_conclusao`, `cancelar_conclusao`, `resolved_<alertId>`

- [ ] **Step 1: Fakes**

`FakeAcsBackend` (`test/support/fakes.dart`), ao lado de `acknowledge`:

```dart
  final List<String> resolvedAlertIds = <String>[];

  /// `false` simula alerta que a central não encontra na microárea.
  bool resolved = true;

  /// Quando presente, `resolveAlert` lança esta falha (ex.: alerta pending).
  BackendFailure? resolveFailure;

  @override
  Future<AlertResolveResult> resolveAlert({required String alertId}) async {
    final falha = resolveFailure;
    if (falha != null) throw falha;
    resolvedAlertIds.add(alertId);
    return AlertResolveResult(
      alertId: alertId,
      resolved: resolved,
      status: resolved ? AlertStatus.resolved : null,
      resolvedAt: resolved ? DateTime.utc(2026, 10, 16, 14) : null,
    );
  }
```

`integration_test/full_journey_e2e.dart`, em `_EnvioDeVisitasForaDoAr`, seguindo o padrão dos outros repasses da classe:

```dart
  @override
  Future<AlertResolveResult> resolveAlert({required String alertId}) =>
      _inner.resolveAlert(alertId: alertId);
```

- [ ] **Step 2: Escrever os testes que falham**

Criar `apps/acs/test/alert_resolve_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/app/acs_theme.dart';
import 'package:sinalacs_acs/app/app.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/services/alert_queue.dart';

import 'support/fakes.dart';

/// "Concluir atendimento" (#76): a ação do ACS que faz o paciente ver
/// "Atendido".
void main() {
  group('AlertQueue.markResolved', () {
    test('marca concluído, implica confirmado e desce abaixo dos confirmados', () {
      final queue = AlertQueue(microAreaId: seedMicroAreaId)
        ..upsert(testAlert(alertId: 'a', triggeredAt: DateTime.utc(2026, 10, 16, 8)))
        ..upsert(testAlert(alertId: 'b', triggeredAt: DateTime.utc(2026, 10, 16, 9)))
        ..markAcknowledged('a')
        ..markAcknowledged('b');

      expect(queue.markResolved('a'), isTrue);

      expect(queue.alerts.map((x) => x.alertId), ['b', 'a']);
      expect(queue.alerts.last.resolved, isTrue);
      expect(queue.alerts.last.acknowledged, isTrue);
      expect(queue.unacknowledgedCount, 0);
    });

    test('alerta fora da fila devolve false', () {
      final queue = AlertQueue(microAreaId: seedMicroAreaId);
      expect(queue.markResolved('nao-existe'), isFalse);
    });

    test('reentrega de um alerta concluído não o reabre', () {
      final queue = AlertQueue(microAreaId: seedMicroAreaId)
        ..upsert(testAlert(alertId: 'a'))
        ..markAcknowledged('a')
        ..markResolved('a');

      expect(queue.upsert(testAlert(alertId: 'a')), isFalse);
      expect(queue.upsert(testAlert(alertId: 'a', escalated: true)), isFalse);
      expect(queue.alerts.single.resolved, isTrue);
    });
  });

  group('cartão do alerta', () {
    Future<void> pintar(WidgetTester tester, AlertQueue queue, {void Function(PrioritizedAlert)? onResolve}) =>
        tester.pumpWidget(MaterialApp(
          theme: buildAcsDarkTheme(),
          home: Scaffold(body: DashboardScreen(queue: queue, onResolve: onResolve)),
        ));

    testWidgets('só o alerta confirmado oferece "Concluir atendimento"', (tester) async {
      final queue = AlertQueue(microAreaId: seedMicroAreaId)
        ..upsert(testAlert(alertId: 'novo'))
        ..upsert(testAlert(alertId: 'visto'))
        ..markAcknowledged('visto');
      await pintar(tester, queue, onResolve: (_) {});

      expect(find.byKey(const Key('resolve_novo')), findsNothing);
      expect(find.byKey(const Key('resolve_visto')), findsOneWidget);
      final altura = tester.getSize(find.byKey(const Key('resolve_visto'))).height;
      expect(altura, greaterThanOrEqualTo(48));
    });

    testWidgets('concluído mostra rótulo e ícone, sem botões de ação', (tester) async {
      final handle = tester.ensureSemantics();
      final queue = AlertQueue(microAreaId: seedMicroAreaId)
        ..upsert(testAlert(alertId: 'a1'))
        ..markAcknowledged('a1')
        ..markResolved('a1');
      await pintar(tester, queue, onResolve: (_) {});

      expect(find.byKey(const Key('resolved_a1')), findsOneWidget);
      expect(find.byKey(const Key('resolve_a1')), findsNothing);
      expect(find.byKey(const Key('ack_a1')), findsNothing);
      expect(find.text('Acionar SAMU / Atender'), findsNothing);
      expect(find.text('Iniciar rota de visita'), findsNothing);
      expect(find.bySemanticsLabel(RegExp('atendimento concluído')), findsOneWidget);
      final texto = tester.widget<Text>(find.byKey(const Key('resolved_a1')));
      expect(texto.style?.color, AcsRiskColors.dark.greenOnSurface);
      handle.dispose();
    });
  });

  group('fluxo no painel', () {
    Future<FakeAlertFeed> abrirComAlertaConfirmado(WidgetTester tester, FakeAcsBackend backend) async {
      late FakeAlertFeed feed;
      await tester.pumpWidget(SinalAcsApp(
        backend: backend,
        feedBuilder: (queue) => feed = FakeAlertFeed(queue),
      ));
      await entrar(tester);
      await tester.pumpAndSettle();
      feed.deliver(testAlert(alertId: 'alerta-1'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ack_alerta-1')));
      await tester.pumpAndSettle();
      return feed;
    }

    testWidgets('confirma no diálogo, chama o servidor e marca concluído', (tester) async {
      final backend = FakeAcsBackend();
      await abrirComAlertaConfirmado(tester, backend);

      await tester.tap(find.byKey(const Key('resolve_alerta-1')));
      await tester.pumpAndSettle();
      expect(find.text('Concluir o atendimento?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirmar_conclusao')));
      await tester.pumpAndSettle();

      expect(backend.resolvedAlertIds, ['alerta-1']);
      expect(find.byKey(const Key('resolved_alerta-1')), findsOneWidget);
      expect(find.text('Atendimento concluído. O paciente já vê "Atendido".'), findsOneWidget);
    });

    testWidgets('cancelar o diálogo não chama o servidor', (tester) async {
      final backend = FakeAcsBackend();
      await abrirComAlertaConfirmado(tester, backend);

      await tester.tap(find.byKey(const Key('resolve_alerta-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cancelar_conclusao')));
      await tester.pumpAndSettle();

      expect(backend.resolvedAlertIds, isEmpty);
      expect(find.byKey(const Key('resolve_alerta-1')), findsOneWidget);
    });

    testWidgets('recusa do servidor aparece e o alerta segue por concluir', (tester) async {
      final backend = FakeAcsBackend()
        ..resolveFailure = const BackendFailure(
          'Confirme o recebimento antes de concluir o atendimento.',
          isRecoverable: false,
        );
      await abrirComAlertaConfirmado(tester, backend);

      await tester.tap(find.byKey(const Key('resolve_alerta-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmar_conclusao')));
      await tester.pumpAndSettle();

      expect(find.text('Confirme o recebimento antes de concluir o atendimento.'), findsOneWidget);
      expect(find.byKey(const Key('resolve_alerta-1')), findsOneWidget);
      expect(find.byKey(const Key('resolved_alerta-1')), findsNothing);
    });

    testWidgets('alerta que a central não encontra não é marcado concluído', (tester) async {
      final backend = FakeAcsBackend()..resolved = false;
      await abrirComAlertaConfirmado(tester, backend);

      await tester.tap(find.byKey(const Key('resolve_alerta-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmar_conclusao')));
      await tester.pumpAndSettle();

      expect(find.text('A central não reconheceu este alerta.'), findsOneWidget);
      expect(find.byKey(const Key('resolved_alerta-1')), findsNothing);
    });
  });
}
```

(`testAlert`, `seedMicroAreaId`, `FakeAlertFeed` e `entrar` já existem em `test/support/`; confira o import de `entrar` usado por `test/login_flow_test.dart` e replique-o se ele vier de outro arquivo de suporte.)

- [ ] **Step 3: Rodar e ver falhar**

Run: `cd apps/acs && flutter test test/alert_resolve_test.dart`
Expected: FAIL de compilação — `resolveAlert`, `markResolved`, `onResolve` não existem.

- [ ] **Step 4: Implementar a rede**

`lib/core/network/backend_client.dart`:

Interface, depois de `acknowledge`:

```dart
  /// Conclui o atendimento de um alerta já confirmado (#76): o paciente passa
  /// a ver "Atendido".
  Future<AlertResolveResult> resolveAlert({required String alertId});
```

Recusador (classe do `_recusar()`, ~linha 251):

```dart
  @override
  Future<AlertResolveResult> resolveAlert({required String alertId}) async => _recusar();
```

`BackendClient`, depois de `acknowledge`:

```dart
  /// Conclui o atendimento (#76). Alerta inexistente ou de outra microárea
  /// volta `resolved: false`; alerta ainda não confirmado é recusado pelo
  /// servidor com texto pronto, que o `_guard` repassa.
  @override
  Future<AlertResolveResult> resolveAlert({required String alertId}) async {
    final token = await _requireToken();
    return _guard(
      () => _client.alerts.resolve(accessToken: token, alertId: alertId),
    );
  }
```

- [ ] **Step 5: Implementar a fila**

`lib/core/services/alert_queue.dart`:

- Construtor de `PrioritizedAlert`: `this.resolved = false,` depois de `this.escalated = false,`.
- Campo:

```dart
  /// O ACS concluiu o atendimento (#76). Implica [acknowledged].
  final bool resolved;
```

- `copyWith({bool? acknowledged, bool? escalated, bool? resolved})` com `resolved: resolved ?? this.resolved,`.
- Depois de `markAcknowledged`:

```dart
  /// Marca o atendimento como concluído (e, por consequência, confirmado).
  /// Devolve `false` se o alerta não está na fila.
  bool markResolved(String alertId) {
    final index = _alerts.indexWhere((item) => item.alertId == alertId);
    if (index < 0) return false;

    _alerts[index] = _alerts[index].copyWith(acknowledged: true, resolved: true);
    _sort();
    notifyListeners();
    return true;
  }
```

- Em `_sort`, depois da linha dos confirmados:

```dart
      // Concluídos descem abaixo dos confirmados: já não pedem ação.
      if (a.resolved != b.resolved) return a.resolved ? 1 : -1;
```

(`upsert` já devolve `false` para alerta confirmado, o que cobre o concluído.)

- [ ] **Step 6: Implementar a tela**

`lib/app/app.dart`:

1. Depois de `_acknowledge`:

```dart
  /// Trava o toque duplo do "Concluir atendimento".
  final Set<String> _concluindo = <String>{};

  /// "Concluir atendimento" (#76): confirma com o ACS, porque o paciente passa
  /// a ver "Atendido" e o servidor não volta atrás.
  Future<void> _resolve(PrioritizedAlert alert) async {
    if (_concluindo.contains(alert.alertId)) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    void aviso(String texto) => messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Concluir o atendimento?'),
        content: const Text(
          'O paciente verá "Atendido" no aplicativo. Conclua só depois de atender o paciente.',
        ),
        actions: [
          TextButton(
            key: const Key('cancelar_conclusao'),
            onPressed: () => Navigator.of(dialog).pop(false),
            style: TextButton.styleFrom(minimumSize: const Size(48, 52)),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('confirmar_conclusao'),
            onPressed: () => Navigator.of(dialog).pop(true),
            style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
            child: const Text('Concluir'),
          ),
        ],
      ),
    );
    if (confirmou != true || !mounted) return;
    _concluindo.add(alert.alertId);
    try {
      final result = await BackendScope.of(context).resolveAlert(alertId: alert.alertId);
      if (result.resolved && mounted) _queue.markResolved(alert.alertId);
      aviso(result.resolved
          ? 'Atendimento concluído. O paciente já vê "Atendido".'
          : 'A central não reconheceu este alerta.');
    } on BackendFailure catch (failure) {
      // Nunca engolir: o alerta segue confirmado e por concluir.
      aviso(failure.message);
    } finally {
      _concluindo.remove(alert.alertId);
    }
  }
```

2. Onde o painel monta `DashboardScreen` (~linha 1966), ao lado de `onAcknowledge: _acknowledge,`: `onResolve: _resolve,`.

3. `DashboardScreen`: novo parâmetro `this.onResolve,`, campo `final void Function(PrioritizedAlert alert)? onResolve;` e repasse `onResolve: onResolve,` ao `_AlertCard` (~linha 2231), seguindo exatamente o desenho de `onAcknowledge`.

4. `_AlertCard`: construtor `const _AlertCard({required this.alert, this.onAcknowledge, this.onEscalate, this.onVisit, this.onResolve});` e campo `final void Function(PrioritizedAlert alert)? onResolve;`.

- No `label` do `Semantics`, depois do trecho de `acknowledged`:

```dart
                '${alert.resolved ? ', atendimento concluído' : ''}'
```

- Substituir o bloco `if (alert.acknowledged) Padding(… 'Recebimento confirmado' …)` por:

```dart
              if (alert.resolved) Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  Icon(Icons.task_alt, size: 16, color: context.acsRisk.greenOnSurface),
                  const SizedBox(width: 6),
                  Text('Atendimento concluído',
                      key: Key('resolved_${alert.alertId}'),
                      style: TextStyle(color: context.acsRisk.greenOnSurface)),
                ]),
              ) else if (alert.acknowledged) Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  Icon(Icons.check_circle, size: 16, color: context.acsRisk.greenOnSurface),
                  const SizedBox(width: 6),
                  Text('Recebimento confirmado', style: TextStyle(color: context.acsRisk.greenOnSurface)),
                ]),
              ),
```

- Depois do bloco `if (!alert.acknowledged) SizedBox(… ack …)`, acrescentar:

```dart
          if (alert.acknowledged && !alert.resolved) SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: Key('resolve_${alert.alertId}'),
              onPressed: onResolve == null ? null : () => onResolve!(alert),
              style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
              icon: const Icon(Icons.task_alt),
              label: const Text('Concluir atendimento'),
            ),
          ),
```

- Envolver o `const SizedBox(height: 8)` e o `SizedBox(… OutlinedButton … 'Acionar SAMU / Atender' …)` finais em `if (!alert.resolved) ...[ … ]`.

- [ ] **Step 7: Rodar e ver passar**

```bash
cd apps/acs
flutter test test/alert_resolve_test.dart
flutter test
flutter analyze
```

Expected: PASS (os 9 novos e a suíte inteira, inclusive `text_scale_test.dart`, `login_flow_test.dart`, `alert_card_escalation_test.dart`); analyze limpo.

- [ ] **Step 8: Commit**

```bash
git add apps/acs/lib apps/acs/test apps/acs/integration_test/full_journey_e2e.dart
git commit -m "feat(acs): concluir o atendimento do alerta confirmado (#76)"
```

---

### Task 5: App do paciente — "Atendido"

**Files:**
- Modify: `apps/patient/lib/app/app.dart` (`_StatusCard`, ~linha 2503)
- Test: `apps/patient/test/patient_app_mvp_test.dart` (grupo do status, ~linha 1547)

**Interfaces:**
- Consumes: `AlertStatusResult.resolvedAt` (cliente gerado, Task 2).
- Produces: chave `status_resolved_at`.

- [ ] **Step 1: Escrever o teste que falha**

Depois de `testWidgets('mostra o status real devolvido pelo servidor', …)`:

```dart
    testWidgets('alerta concluído pela equipe aparece como "Atendido" (#76)', (tester) async {
      final backend = FakePatientBackend()
        ..statusResult = AlertStatusResult(
          found: true,
          alertId: 'alerta-1',
          riskLevel: RiskLevel.red,
          status: AlertStatus.resolved,
          triggeredAt: DateTime.utc(2026, 9, 18, 9),
          acknowledgedAt: DateTime.utc(2026, 9, 18, 9, 5),
          resolvedAt: DateTime.utc(2026, 9, 18, 10, 40),
        );
      await tester.pumpWidget(SinalAcsApp(backend: backend));
      await login(tester);

      await tester.tap(find.text('Status'));
      await tester.pumpAndSettle();

      expect(find.text('Atendido pela equipe de saúde'), findsOneWidget);
      expect(find.byKey(const Key('status_resolved_at')), findsOneWidget);
      expect(find.textContaining('Atendimento concluído às'), findsOneWidget);
      // A confirmação continua visível: é a etapa "Visualizado" do PRD §6.1.
      expect(find.textContaining('Confirmado pela equipe às'), findsOneWidget);
    });
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd apps/patient && flutter test test/patient_app_mvp_test.dart --plain-name 'Atendido'`
Expected: FAIL — o rótulo atual é "Atendimento concluído" e não há `status_resolved_at`.

- [ ] **Step 3: Implementar**

Em `_StatusCard.build`:

- Trocar `AlertStatus.resolved => 'Atendimento concluído',` por `AlertStatus.resolved => 'Atendido pela equipe de saúde',`.
- Depois de `final acknowledgedAt = status.acknowledgedAt;`: `final resolvedAt = status.resolvedAt;`.
- Depois do bloco `if (acknowledgedAt != null) ...[ … ]`:

```dart
            if (resolvedAt != null) ...[
              const SizedBox(height: 4),
              Text(
                key: const Key('status_resolved_at'),
                'Atendimento concluído às ${_formatTime(resolvedAt)}',
              ),
            ],
```

- [ ] **Step 4: Rodar e ver passar**

```bash
cd apps/patient
flutter test
flutter analyze
```

Expected: PASS; analyze limpo.

- [ ] **Step 5: Commit**

```bash
git add apps/patient/lib/app/app.dart apps/patient/test/patient_app_mvp_test.dart
git commit -m "feat(patient): status mostra Atendido quando a equipe conclui (#76)"
```

---

### Task 6: Documentação, verificação completa e grafo

**Files:**
- Modify: `PROGRESS.md`, `spec/lgpd_data_audit.md` (tabela `alerts`, ~linha 75), `docs/auditoria-prd/2026-10-15-lacunas-prd.md` (linhas RF05 ~24, M2.1 ~173, MVP-STATUS ~192, backlog item 2 ~229), `CLAUDE.md` (lista de endpoints: `alerts`), `backend/CLAUDE.md` (lista de endpoints, ao lado de `alerts.acknowledge`)

- [ ] **Step 1: Atualizar os documentos**

- `spec/lgpd_data_audit.md`, na tabela de `alerts`, logo depois da linha de `acknowledgedAt`:

```markdown
| | `resolvedAt` | `timestamp without time zone` | Metadado Operacional | Timestamp de conclusão | Conclusão do atendimento pelo ACS (#76); é o que o paciente vê como "Atendido" (RF05). Sem dado pessoal. |
```

- `PROGRESS.md`, nova seção depois de "Colunas de risco cifradas (#75)":

```markdown
## Estado "Atendido" do alerta (#76) — 2026-10-16

- Entregue: `alerts.resolve` (só ACS do território, só de `acknowledged`, idempotente, auditado na mesma transação: `resolved`, `already_resolved`, `denied_not_acknowledged`); coluna `alerts.resolvedAt` (migração aditiva); o ACK trava a linha e não rebaixa `resolved`; `alerts.statusFor` devolve `resolvedAt`; o pulso do backoffice anda com a conclusão. ACS: botão "Concluir atendimento" no cartão confirmado, com diálogo. Paciente: "Atendido pela equipe de saúde" e a hora da conclusão.
- Provas: `test/unit/red_alert_service_test.dart` (grupo `resolve (#76)`), `test/integration/red_alert_cycle_test.dart` (grupo `concluir o atendimento (#76)`), `test/integration/admin_monitoring_store_test.dart`, `apps/acs/test/alert_resolve_test.dart`, `apps/patient/test/patient_app_mvp_test.dart`.
- Aberto: sem prova no emulador (o e2e do paciente não tem ACS concluindo); o contador "reconhecidos" do backoffice (`acknowledgedRedAlerts`) conta só `acknowledged`, então um alerta concluído sai dele (o TMRAV não muda); a conclusão vive só na fila em memória do ACS, como o ACK.
```

- `docs/auditoria-prd/2026-10-15-lacunas-prd.md`: RF05 e MVP-STATUS para **entregue** com a evidência (`alerts.resolve`, os testes acima) e falta `—`; M2.1 continua **parcial**, com a falta reduzida a "SMS real (RF01)"; no backlog, item 2 prefixado com `**Resolvido (2026-10-16, #76).**`, como o item 1.
- `CLAUDE.md` (raiz): na lista de endpoints, `alerts` (`createRedAlert`, `acknowledge`, `resolve`, `statusFor`).
- `backend/CLAUDE.md`: depois de `` `alerts.acknowledge`, `` acrescentar `` `alerts.resolve` (#76: só de `acknowledged` para `resolved`, sob trava, no território do token, auditado na mesma transação; `resolved: false` para inexistente/fora do território; o ACK não rebaixa `resolved`), ``.

- [ ] **Step 2: Conferir a contagem do relatório**

Run: `cd /home/rock/Documents/Dev/APPs/SinalACS && python3 scripts/qa/cobertura_prd.py --final`
Expected: sai com 0. Se acusar divergência de contagem, ajuste o cabeçalho de contagem do relatório (e a linha correspondente em `PROGRESS.md`, seção "Auditoria de lacunas do PRD") para os números que o script imprimir.

- [ ] **Step 3: Verificação completa**

```bash
cd /home/rock/Documents/Dev/APPs/SinalACS/backend && dart analyze
cd sinalacs_server && dart test -j 1
cd ../../apps/acs && flutter analyze && flutter test
cd ../patient && flutter analyze && flutter test
cd ../admin && flutter analyze && flutter test
```

Expected: tudo verde. O admin não muda de código, mas consome o cliente regenerado — por isso entra na verificação. Anote as contagens de testes impressas para o PR.

- [ ] **Step 4: Atualizar o grafo**

Run: `cd /home/rock/Documents/Dev/APPs/SinalACS && graphify update .`
Expected: termina sem erro.

- [ ] **Step 5: Commit**

```bash
git add PROGRESS.md spec/lgpd_data_audit.md docs/auditoria-prd/2026-10-15-lacunas-prd.md CLAUDE.md backend/CLAUDE.md graphify-out
git commit -m "docs: registra o estado Atendido do alerta (#76)"
```

(Se `graphify-out/` não for versionado — confira com `git check-ignore graphify-out` —, tire-o do `git add`.)
