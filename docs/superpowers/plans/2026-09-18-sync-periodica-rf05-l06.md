# Sincronização periódica, RF05 (paciente) e débito L-06/RF08 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fechar três itens deixados em aberto por planos anteriores de RF15: (1) sincronização periódica em segundo plano nos apps ACS e paciente, além do disparo manual/ao-abrir já existente; (2) a metade paciente de RF15 (RF05, `alerts.statusFor`), que fecha L-03 ("Tela de Status mente para o paciente"); (3) o débito técnico L-06/RF08 — a tela "Área" do ACS mostra números fixos ("142 cadastrados") que contradizem o backend real (a microárea semeada tem 5 pacientes).

**Architecture:** Nenhum canal de transporte novo — tudo é RPC Serverpod comum, mesmo padrão de `visits.pull` (RF15, decisão §5). O backend ganha `alerts.statusFor(accessToken)`, espelhando `visits.pull`: território/identidade vêm sempre do token, nunca de parâmetro (INV-05). O app ACS já tem pull manual+automático-ao-abrir (`_AcsHomeShellState._pullVisits`, já implementado); este plano adiciona um `Timer.periodic` no mesmo shell, mais uma segunda chamada territorializada (`listPatients()`, que já existe) para números reais na tela "Área". O app paciente ganha uma tela de Status com estado próprio (`StatusScreen` deixa de ser `const`), que busca o status ao abrir e repete em intervalo — desenho self-contained, não no shell, porque um teste existente (`RemindersScreen`) constrói `PatientHomeShell` sem `BackendScope` ancestor, e buscar dado de backend no nível do shell quebraria esse teste.

**Tech Stack:** Dart/Serverpod (`backend/sinalacs_server`, `backend/sinalacs_client`), Flutter (`apps/acs`, `apps/patient`), `serverpod generate` para o modelo novo.

**Spec:** `docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md` §5 ("Sincronização central → dispositivo (RF15, metade ausente)"), `docs/superpowers/plans/2026-09-18-rf15-consumo-acs-pull-visitas.md` (já executado — implementa a metade ACS e deixa explicitamente de fora os três itens deste plano), `spec/validation_report.md` (linhas RF05, RF08, RF15, L-03, L-06).

## Global Constraints

- Todo texto voltado ao paciente/ACS é em português (padrão do repositório).
- Nenhum dado de paciente real em teste, log ou copy — usar sempre os UUIDs sintéticos de `test/support/fakes.dart` (ACS) / `test/support/fake_patient_backend.dart` (paciente).
- `alerts.statusFor` nunca recebe `patientId` como parâmetro — sempre `user.id` do token (INV-05), mesma disciplina de `triage.evaluate`/`VisitSyncService.pull`.
- Falha de rede/sessão ao sincronizar (periódico ou manual) não pode travar nenhuma tela — sempre captura, mostra aviso, permite tentar de novo.
- Cor é sinal clínico só nos níveis de risco (`red`/`yellow`/`green` → vermelho/amarelo/verde); avisos de sincronização usam tom neutro, nunca vermelho.
- Um `Timer` em segundo plano no Android não é confiável e só gasta bateria: todo timer periódico deste plano cancela em `AppLifecycleState.paused` e retoma (com uma sincronização imediata) em `resumed` — mesmo padrão já usado por `ReconnectSchedule`/`_reconnectTimer` em `apps/acs/lib/app/app.dart`.
- Depois de mudar `.spy.yaml`, sempre `cd backend/sinalacs_server && serverpod generate` antes de compilar os apps.

---

## File Structure

- **Modify** `apps/acs/lib/app/app.dart` — `_AcsHomeShellState` ganha `_loadMicroAreaPatients()` (Task 1) e um `Timer.periodic` que repete `_pullVisits()`+`_loadMicroAreaPatients()` (Task 5); `AcsHomeShell`/`LoginScreen`/`SinalAcsApp` ganham `syncInterval` opcional; `TerritorializationScreen` mostra números reais em vez de "142 cadastrados"/"Atualizado há 10 min".
- **Modify** `backend/sinalacs_server/lib/src/application/alerts/red_alert_service.dart` — `AlertStatusSnapshot`, `AlertStore.latestForPatient`, `RedAlertService.statusFor`.
- **Modify** `backend/sinalacs_server/lib/src/infrastructure/database/orm_alert_store.dart` — implementa `latestForPatient`.
- **Create** `backend/sinalacs_server/lib/src/models/api/alert_status_result.spy.yaml` — DTO `AlertStatusResult`.
- **Modify** `backend/sinalacs_server/lib/src/endpoints/alerts_endpoint.dart` — endpoint `statusFor`.
- **Modify** `apps/patient/lib/core/network/backend_client.dart` — `PatientBackend.statusFor()` + implementação real.
- **Modify** `apps/patient/lib/app/app.dart` — `StatusScreen` deixa de ser `const`/estática, ganha estado próprio com busca ao abrir + `Timer.periodic` (Tasks 4 e 6); `_StatusStep` (não usada depois da troca) é removida.
- **Modify** `apps/patient/test/support/fake_patient_backend.dart`, `apps/acs/test/login_flow_test.dart`, `apps/patient/test/patient_app_mvp_test.dart`, `backend/sinalacs_server/test/unit/red_alert_service_test.dart`, `backend/sinalacs_server/test/integration/red_alert_cycle_test.dart` — cobertura de cada task.
- **Modify** `spec/validation_report.md`, `spec/PRD_system.md`, `docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md` — Task 7, só documentação.

---

### Task 1: ACS — número real de pacientes na tela "Área" (L-06/RF08)

**Files:**
- Modify: `apps/acs/lib/app/app.dart`
- Test: `apps/acs/test/login_flow_test.dart`

**Interfaces:**
- Consumes: `AcsBackend.listPatients()` (`apps/acs/lib/core/network/backend_client.dart:45`, já existe — mesma chamada que `VisitRegistrationScreen` usa para o seletor de paciente), `BackendScope.of(context)` (já usado em `_AcsHomeShellState._acknowledge`), `InfraNotice` typedef (`app.dart:215`).
- Produces: `TerritorializationScreen` ganha `loadingPatients: bool`, `patientCount: int?`, `patientsLoadedAt: DateTime?`, `patientsError: InfraNotice?` — consumidos só dentro de `app.dart`.

- [x] **Step 1: Escrever o teste que falha**

  Em `apps/acs/test/login_flow_test.dart`, adicionar um novo `group`, depois do `group('sincronização central→dispositivo (RF15)', ...)` (antes do `}` que fecha `main()`):

  ```dart
  group('território real na tela Área (L-06/RF08)', () {
    testWidgets('mostra o número real de pacientes da microárea, não o literal fixo', (tester) async {
      final backend = FakeAcsBackend()
        ..patients = const [
          MicroAreaPatient(patientId: seedPatientId, name: 'Paciente 1', isChronic: false, chronicConditions: []),
          MicroAreaPatient(patientId: 'p2', name: 'Paciente 2', isChronic: true, chronicConditions: ['Hipertensão']),
        ];

      await tester.pumpWidget(SinalAcsApp(
        backend: backend,
        feedBuilder: (queue) => FakeAlertFeed(queue),
      ));
      await tester.tap(find.byKey(const Key('login_button')));
      await tester.pumpAndSettle();

      expect(backend.listPatientsCount, 1);

      await tester.tap(find.text('Área'));
      await tester.pumpAndSettle();

      expect(find.text('2 cadastrados'), findsOneWidget);
      expect(find.text('142 cadastrados'), findsNothing);
    });

    testWidgets('uma falha ao carregar os pacientes mostra o motivo, sem travar a tela', (tester) async {
      final backend = FakeAcsBackend()
        ..listPatientsFailure = const BackendFailure('Sem conexão com o servidor.');

      await tester.pumpWidget(SinalAcsApp(
        backend: backend,
        feedBuilder: (queue) => FakeAlertFeed(queue),
      ));
      await tester.tap(find.byKey(const Key('login_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Área'));
      await tester.pumpAndSettle();

      expect(find.text('Não foi possível carregar'), findsOneWidget);
    });
  });
  ```

- [x] **Step 2: Rodar e confirmar que falha**

  Run: `cd apps/acs && flutter test test/login_flow_test.dart`
  Expected: FAIL — `find.text('2 cadastrados')` não encontra nada (a tela ainda mostra "142 cadastrados").

- [x] **Step 3: `_AcsHomeShellState` carrega os pacientes da microárea**

  Em `apps/acs/lib/app/app.dart`, dentro de `_AcsHomeShellState`, adicionar campos logo após `InfraNotice? _pullError;` (perto do bloco de estado do pull de RF15):

  ```dart
    /// `true` enquanto `patients.listMicroArea` está em andamento.
    bool _loadingMicroAreaPatients = false;

    /// Pacientes cadastrados na microárea, segundo o servidor. `null` antes da
    /// primeira carga desta sessão.
    ///
    /// Corrige L-06: a tela "Área" mostrava "142 cadastrados" fixo,
    /// contradizendo o servidor — a microárea semeada em desenvolvimento tem 5
    /// pacientes (spec/validation_report.md). `patients.listMicroArea` já
    /// territorializa pelo token do ACS (INV-01), mesma chamada que alimenta o
    /// seletor de paciente da visita de rotina.
    List<MicroAreaPatient>? _microAreaPatients;

    /// Quando a última carga bem-sucedida terminou.
    DateTime? _microAreaPatientsLoadedAt;

    /// Presente quando a última tentativa falhou.
    InfraNotice? _microAreaPatientsError;

    bool _patientsRequested = false;
  ```

  Adicionar `didChangeDependencies`, logo antes de `_restoreVisits`:

  ```dart
    @override
    void didChangeDependencies() {
      super.didChangeDependencies();
      // BackendScope.of(context) só é seguro a partir daqui, não em initState —
      // mesmo motivo de VisitRegistrationScreen._patientsRequested.
      if (!_patientsRequested) {
        _patientsRequested = true;
        _loadMicroAreaPatients();
      }
    }

    Future<void> _loadMicroAreaPatients() async {
      setState(() { _loadingMicroAreaPatients = true; _microAreaPatientsError = null; });

      try {
        final patients = await BackendScope.of(context).listPatients();
        if (!mounted) return;
        setState(() {
          _microAreaPatients = patients;
          _microAreaPatientsLoadedAt = DateTime.now();
        });
      } on BackendFailure catch (failure) {
        if (!mounted) return;
        setState(() {
          _microAreaPatientsError = (
            title: 'Não foi possível carregar os pacientes da microárea.',
            detail: failure.message,
          );
        });
      } finally {
        if (mounted) setState(() => _loadingMicroAreaPatients = false);
      }
    }
  ```

- [x] **Step 4: `build()` passa os dados reais para `TerritorializationScreen`**

  Substituir:

  ```dart
      AcsDestination.area => TerritorializationScreen(
          pulling: _pullingVisits,
          lastPulledCount: _lastPulledCount,
          lastPulledAt: _lastPulledAt,
          pullError: _pullError,
          onRefresh: _pullVisits,
        ),
  ```

  por:

  ```dart
      AcsDestination.area => TerritorializationScreen(
          pulling: _pullingVisits,
          lastPulledCount: _lastPulledCount,
          lastPulledAt: _lastPulledAt,
          pullError: _pullError,
          onRefresh: _pullVisits,
          loadingPatients: _loadingMicroAreaPatients,
          patientCount: _microAreaPatients?.length,
          patientsLoadedAt: _microAreaPatientsLoadedAt,
          patientsError: _microAreaPatientsError,
        ),
  ```

- [x] **Step 5: `TerritorializationScreen` mostra os números reais**

  Substituir a doc do topo da classe:

  ```dart
  /// Painel territorial da microárea, incluindo o status da sincronização
  /// central→dispositivo (RF15, decisão §5).
  ///
  /// "Pacientes sincronizados" e "Cache local" continuam literais fixos — é o
  /// débito técnico L-06 (RF08), fora do escopo desta task: aqui só o bloco de
  /// sincronização abaixo reflete dado real, vindo do `VisitPullService` via
  /// [AcsHomeShell._pullVisits].
  ```

  por:

  ```dart
  /// Painel territorial da microárea, incluindo o status da sincronização
  /// central→dispositivo (RF15, decisão §5) e o número real de pacientes da
  /// microárea (L-06/RF08, fechado nesta task: antes mostrava "142
  /// cadastrados" fixo, contradizendo o servidor).
  ```

  Substituir o construtor e os campos (adicionar os quatro novos, mantendo os já existentes):

  ```dart
    const TerritorializationScreen({
      super.key,
      this.pulling = false,
      this.lastPulledCount,
      this.lastPulledAt,
      this.pullError,
      this.onRefresh,
    });
  ```

  por:

  ```dart
    const TerritorializationScreen({
      super.key,
      this.pulling = false,
      this.lastPulledCount,
      this.lastPulledAt,
      this.pullError,
      this.onRefresh,
      this.loadingPatients = false,
      this.patientCount,
      this.patientsLoadedAt,
      this.patientsError,
    });

    /// `true` enquanto `patients.listMicroArea` está em andamento.
    final bool loadingPatients;

    /// Pacientes cadastrados na microárea. `null` antes da primeira carga.
    final int? patientCount;

    /// Quando a última carga bem-sucedida terminou.
    final DateTime? patientsLoadedAt;

    /// Presente quando a última tentativa falhou.
    final InfraNotice? patientsError;
  ```

  Substituir as duas linhas literais dentro de `build()`:

  ```dart
        const _InfoRow('Pacientes sincronizados', '142 cadastrados'),
        const _InfoRow('Cache local', 'Atualizado há 10 min'),
  ```

  por:

  ```dart
        _InfoRow('Pacientes sincronizados', _patientCountText()),
        _InfoRow('Cache local', _cacheFreshnessText()),
  ```

  E adicionar os dois métodos auxiliares, logo abaixo de `_time`:

  ```dart
    String _patientCountText() {
      if (patientsError != null) return 'Não foi possível carregar';
      final count = patientCount;
      if (count == null) return loadingPatients ? 'Carregando...' : 'Ainda não carregado';
      return count == 1 ? '1 cadastrado' : '$count cadastrados';
    }

    String _cacheFreshnessText() {
      final at = patientsLoadedAt;
      return at == null ? 'Ainda não sincronizado' : 'Atualizado às ${_time(at)}';
    }
  ```

- [x] **Step 6: Rodar e confirmar que passa**

  Run: `cd apps/acs && flutter test test/login_flow_test.dart`
  Expected: PASS.

- [x] **Step 7: Rodar a suíte inteira do app ACS**

  Run: `cd apps/acs && flutter analyze && flutter test`
  Expected: PASS — nenhum teste pré-existente quebra (`_loadMicroAreaPatients` usa `BackendScope.of(context)`, já seguro em todo teste que constrói `SinalAcsApp`).

- [x] **Step 8: Commit**

  ```bash
  git add apps/acs/lib/app/app.dart apps/acs/test/login_flow_test.dart
  git commit -m "fix(acs): mostrar o número real de pacientes da microárea na tela Área (L-06/RF08)"
  ```

---

### Task 2: Backend — `RedAlertService.statusFor` (RF05, unitário)

**Files:**
- Modify: `backend/sinalacs_server/lib/src/application/alerts/red_alert_service.dart`
- Test: `backend/sinalacs_server/test/unit/red_alert_service_test.dart`

**Interfaces:**
- Consumes: `AuthenticatedUser` (`application/auth/development_auth_service.dart`), `RiskLevel`/`AlertStatus` (gerados).
- Produces: `class AlertStatusSnapshot { alertId, riskLevel, status, triggeredAt, acknowledgedAt }`; `AlertStore.latestForPatient(String patientId) → Future<AlertStatusSnapshot?>`; `RedAlertService.statusFor({required AuthenticatedUser user}) → Future<AlertStatusSnapshot?>` — consumidos pela Task 3 (endpoint) e por `OrmAlertStore`/`FakeAlertStore`.

- [x] **Step 1: Escrever o teste que falha**

  Em `backend/sinalacs_server/test/unit/red_alert_service_test.dart`, adicionar ao `FakeAlertStore` (logo após `rememberIdempotencyKey`):

  ```dart
    final Map<String, AlertStatusSnapshot> statusByPatient = {};

    @override
    Future<AlertStatusSnapshot?> latestForPatient(String patientId) async =>
        statusByPatient[patientId];
  ```

  Adicionar, ao final do arquivo (antes do último `}` que fecha `main()`), um novo `group`:

  ```dart
  group('statusFor (RF05)', () {
    test('devolve o status guardado para o paciente do token, não por parâmetro', () async {
      final store = FakeAlertStore()
        ..statusByPatient['paciente-1'] = AlertStatusSnapshot(
          alertId: 'alerta-1',
          riskLevel: RiskLevel.red,
          status: AlertStatus.pending,
          triggeredAt: DateTime.utc(2026, 9, 18, 9),
        );
      final service = RedAlertService(store: store, outbox: FakeAlertOutbox());

      final status = await service.statusFor(
        user: const AuthenticatedUser(
          id: 'paciente-1',
          role: UserRole.patient,
          microAreaId: 'area-1',
          deviceId: 'device-1',
        ),
      );

      expect(status?.alertId, 'alerta-1');
      expect(status?.status, AlertStatus.pending);
    });

    test('paciente que nunca disparou alerta recebe null, não erro', () async {
      final service = RedAlertService(store: FakeAlertStore(), outbox: FakeAlertOutbox());

      final status = await service.statusFor(
        user: const AuthenticatedUser(
          id: 'paciente-sem-alerta',
          role: UserRole.patient,
          microAreaId: 'area-1',
          deviceId: 'device-1',
        ),
      );

      expect(status, isNull);
    });

    test('um ACS não pode consultar status de paciente', () async {
      final service = RedAlertService(store: FakeAlertStore(), outbox: FakeAlertOutbox());

      expect(
        () => service.statusFor(
          user: const AuthenticatedUser(
            id: 'acs-1',
            role: UserRole.acs,
            microAreaId: 'area-1',
            deviceId: 'device-1',
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
  ```

- [x] **Step 2: Rodar e confirmar que falha**

  Run: `cd backend/sinalacs_server && dart test test/unit/red_alert_service_test.dart`
  Expected: FAIL — compilação quebra (`AlertStatusSnapshot`/`latestForPatient`/`statusFor` não existem).

- [x] **Step 3: Implementar em `red_alert_service.dart`**

  Adicionar à interface `AlertStore` (logo após `rememberIdempotencyKey`):

  ```dart
    /// Alerta mais recente do paciente, para RF05 (`alerts.statusFor`). `null`
    /// quando o paciente nunca disparou um alerta.
    Future<AlertStatusSnapshot?> latestForPatient(String patientId);
  ```

  Adicionar a classe nova, logo após `class RedAlertRecord { ... }`:

  ```dart
  /// Status do alerta mais recente de um paciente, para RF05.
  ///
  /// Espelha os campos que `Alert` guarda além de [AlertDelivery] — `status` e
  /// `acknowledgedAt` não existem no envelope MQTT, só na linha persistida.
  class AlertStatusSnapshot {
    const AlertStatusSnapshot({
      required this.alertId,
      required this.riskLevel,
      required this.status,
      required this.triggeredAt,
      this.acknowledgedAt,
    });

    final String alertId;
    final RiskLevel riskLevel;
    final AlertStatus status;
    final DateTime triggeredAt;
    final DateTime? acknowledgedAt;
  }
  ```

  Adicionar o método a `RedAlertService`, logo após `acknowledge`:

  ```dart
    /// Status do alerta mais recente do próprio paciente autenticado (RF05,
    /// decisão §5). O paciente nunca informa `patientId` — vem sempre do token
    /// (INV-05), mesma disciplina de `TriageSessionService`/`VisitSyncService`.
    Future<AlertStatusSnapshot?> statusFor({required AuthenticatedUser user}) async {
      if (user.role != UserRole.patient) {
        throw StateError('Somente pacientes podem consultar o status do próprio alerta.');
      }
      return _store.latestForPatient(user.id);
    }
  ```

- [x] **Step 4: Rodar e confirmar que passa**

  Run: `cd backend/sinalacs_server && dart test test/unit/red_alert_service_test.dart`
  Expected: PASS.

- [x] **Step 5: Commit**

  ```bash
  git add backend/sinalacs_server/lib/src/application/alerts/red_alert_service.dart backend/sinalacs_server/test/unit/red_alert_service_test.dart
  git commit -m "feat(backend): RedAlertService.statusFor — status do alerta escopado ao token do paciente (RF05)"
  ```

---

### Task 3: Backend — modelo `AlertStatusResult` + endpoint `alerts.statusFor` + `OrmAlertStore`

**Files:**
- Create: `backend/sinalacs_server/lib/src/models/api/alert_status_result.spy.yaml`
- Modify: `backend/sinalacs_server/lib/src/infrastructure/database/orm_alert_store.dart`
- Modify: `backend/sinalacs_server/lib/src/endpoints/alerts_endpoint.dart`
- Test: `backend/sinalacs_server/test/integration/red_alert_cycle_test.dart`

**Interfaces:**
- Consumes: `RedAlertService.statusFor` (Task 2), `AlertRuntime.instance.serviceFor(session)` (já existe).
- Produces: `AlertStatusResult` (gerado — `found: bool`, `alertId: String?`, `riskLevel: RiskLevel?`, `status: AlertStatus?`, `triggeredAt: DateTime?`, `acknowledgedAt: DateTime?`), `AlertsEndpoint.statusFor(Session, {required String accessToken}) → Future<AlertStatusResult>` — consumidos pela Task 4 (`sinalacs_client`).

- [x] **Step 1: Criar o modelo**

  Create `backend/sinalacs_server/lib/src/models/api/alert_status_result.spy.yaml`:

  ```yaml
  ### Status do alerta mais recente do paciente autenticado (RF05, decisão §5,
  ### docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md).
  ###
  ### `found: false` quando o paciente nunca disparou um alerta — os demais
  ### campos ficam nulos, mesmo padrão de AlertAckResult.acknowledged: false.
  class: AlertStatusResult
  fields:
    found: bool
    alertId: String?
    riskLevel: RiskLevel?
    status: AlertStatus?
    triggeredAt: DateTime?
    acknowledgedAt: DateTime?
  ```

- [x] **Step 2: Implementar `OrmAlertStore.latestForPatient`**

  Em `backend/sinalacs_server/lib/src/infrastructure/database/orm_alert_store.dart`, adicionar ao final da classe, antes do `}` de fechamento:

  ```dart
    @override
    Future<AlertStatusSnapshot?> latestForPatient(String patientId) async {
      final row = await Alert.db.findFirstRow(
        _session(),
        where: (t) => t.patientId.equals(UuidValue.fromString(patientId)),
        orderBy: (t) => t.triggeredAt,
        orderDescending: true,
        transaction: _transaction,
      );
      if (row == null) return null;

      return AlertStatusSnapshot(
        alertId: row.id!.uuid,
        riskLevel: row.riskLevel,
        status: row.status,
        triggeredAt: row.triggeredAt,
        acknowledgedAt: row.acknowledgedAt,
      );
    }
  ```

- [x] **Step 3: Adicionar o endpoint**

  Em `backend/sinalacs_server/lib/src/endpoints/alerts_endpoint.dart`, adicionar o método logo após `acknowledge`, antes de `_authenticate`:

  ```dart
    /// Status do alerta mais recente do PRÓPRIO paciente (RF05, decisão §5).
    /// `patientId` nunca é parâmetro — vem do token (INV-05).
    Future<AlertStatusResult> statusFor(
      Session session, {
      required String accessToken,
    }) async {
      final user = _authenticate(accessToken);
      final service = AlertRuntime.instance.serviceFor(session);

      try {
        final snapshot = await service.statusFor(user: user);
        if (snapshot == null) return AlertStatusResult(found: false);

        return AlertStatusResult(
          found: true,
          alertId: snapshot.alertId,
          riskLevel: snapshot.riskLevel,
          status: snapshot.status,
          triggeredAt: snapshot.triggeredAt,
          acknowledgedAt: snapshot.acknowledgedAt,
        );
      } on StateError catch (error) {
        throw AlertPermissionException(message: error.message);
      }
    }
  ```

- [x] **Step 4: Regenerar o protocolo**

  Run: `cd backend/sinalacs_server && serverpod generate`
  Expected: sucesso, sem diff em `migrations/` — `AlertStatusResult` é um DTO sem tabela, mesmo padrão de `RedAlertResult`/`AlertAckResult`.

- [x] **Step 5: Escrever os testes de integração que falham**

  Em `backend/sinalacs_server/test/integration/red_alert_cycle_test.dart`, adicionar, logo após o teste `'confirmar um alerta inexistente devolve acknowledged false, sem erro'` (antes do próximo `test(`):

  ```dart
      test('paciente consulta o status do próprio alerta mais recente', () async {
        await _seed(sessionBuilder.build());
        final token =
            await endpoints.auth.developmentLogin(sessionBuilder, role: 'patient');

        final semAlerta =
            await endpoints.alerts.statusFor(sessionBuilder, accessToken: token.accessToken);
        expect(semAlerta.found, isFalse);
        expect(semAlerta.alertId, isNull);

        final criado = await endpoints.alerts.createRedAlert(
          sessionBuilder,
          accessToken: token.accessToken,
          idempotencyKey: 'status-1',
          locationHash: 'hash-sintetico',
        );

        final status =
            await endpoints.alerts.statusFor(sessionBuilder, accessToken: token.accessToken);
        expect(status.found, isTrue);
        expect(status.alertId, criado.alertId);
        expect(status.status, AlertStatus.pending);
        expect(status.acknowledgedAt, isNull);

        final tokenAcs =
            await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs');
        await endpoints.alerts.acknowledge(
          sessionBuilder,
          accessToken: tokenAcs.accessToken,
          alertId: criado.alertId,
        );

        final statusDepoisDoAck =
            await endpoints.alerts.statusFor(sessionBuilder, accessToken: token.accessToken);
        expect(statusDepoisDoAck.status, AlertStatus.acknowledged);
        expect(statusDepoisDoAck.acknowledgedAt, isNotNull);
      });

      test('um ACS não pode consultar alerts.statusFor', () async {
        await _seed(sessionBuilder.build());
        final tokenAcs =
            await endpoints.auth.developmentLogin(sessionBuilder, role: 'acs');

        expect(
          () => endpoints.alerts.statusFor(sessionBuilder, accessToken: tokenAcs.accessToken),
          throwsA(isA<AlertPermissionException>()),
        );
      });
  ```

- [x] **Step 6: Rodar e confirmar que falha, depois implementar até passar**

  Run: `cd backend/sinalacs_server && dart test test/integration/red_alert_cycle_test.dart`
  Expected: FAIL antes do Step 4 (método/modelo não existem); depois do `serverpod generate` (Step 4) e dos Steps 2-3 já aplicados, PASS.

  Pré-requisito: banco de teste no ar (`docker compose --profile test up -d postgres-test`, ver `backend/CLAUDE.md`).

- [x] **Step 7: Rodar a suíte inteira do backend**

  Run: `cd backend/sinalacs_server && dart analyze && dart test`
  Expected: PASS (96+ testes anteriores, mais os novos).

- [x] **Step 8: Commit**

  ```bash
  git add backend/sinalacs_server/lib/src/models/api/alert_status_result.spy.yaml \
          backend/sinalacs_server/lib/src/infrastructure/database/orm_alert_store.dart \
          backend/sinalacs_server/lib/src/endpoints/alerts_endpoint.dart \
          backend/sinalacs_server/lib/src/generated \
          backend/sinalacs_client/lib/src/protocol \
          backend/sinalacs_server/test/integration/red_alert_cycle_test.dart
  git commit -m "feat(backend): endpoint alerts.statusFor (RF05, decisão §5)"
  ```

---

### Task 4: Paciente — `alerts.statusFor` real na tela Status (fecha L-03, RF05)

**Files:**
- Modify: `apps/patient/lib/core/network/backend_client.dart`
- Modify: `apps/patient/lib/app/app.dart`
- Modify: `apps/patient/test/support/fake_patient_backend.dart`
- Test: `apps/patient/test/patient_app_mvp_test.dart`

**Interfaces:**
- Consumes: `Client.alerts.statusFor` (gerado, Task 3), `BackendScope.of(context)` (já usado em `_PatientLoginScreenState`/`_EmergencyScreenState`).
- Produces: `PatientBackend.statusFor() → Future<AlertStatusResult>`; `StatusScreen` deixa de ser `const` — usado só dentro de `app.dart` (via `PatientHomeShell`'s `switch`).

- [x] **Step 1: Escrever os testes que falham**

  Em `apps/patient/lib/main.dart`/imports não mudam. Em `apps/patient/test/patient_app_mvp_test.dart`, ajustar o import de `sinalacs_client` (linha 4):

  ```dart
  import 'package:sinalacs_client/sinalacs_client.dart' show RiskLevel;
  ```

  para:

  ```dart
  import 'package:sinalacs_client/sinalacs_client.dart'
      show AlertStatus, AlertStatusResult, RiskLevel;
  ```

  Adicionar, ao final de `main()` (depois do `group('Lembretes locais (RF06)', ...)`, antes do `}` que fecha `main`):

  ```dart
    group('Status da solicitação (RF05)', () {
      testWidgets('sem alerta disparado, mostra que não há solicitação — não mais o ticket falso', (tester) async {
        final backend = FakePatientBackend();
        await tester.pumpWidget(SinalAcsApp(backend: backend));
        await login(tester);

        await tester.tap(find.text('Status'));
        await tester.pumpAndSettle();

        expect(backend.statusForCallCount, 1);
        expect(find.byKey(const Key('status_empty')), findsOneWidget);
        expect(find.text('Nenhuma solicitação registrada ainda.'), findsOneWidget);
        expect(find.textContaining('Solicitação de visita #4082'), findsNothing);
      });

      testWidgets('mostra o status real devolvido pelo servidor', (tester) async {
        final backend = FakePatientBackend()
          ..statusResult = AlertStatusResult(
            found: true,
            alertId: 'alerta-1',
            riskLevel: RiskLevel.red,
            status: AlertStatus.acknowledged,
            triggeredAt: DateTime.utc(2026, 9, 18, 9),
            acknowledgedAt: DateTime.utc(2026, 9, 18, 9, 5),
          );
        await tester.pumpWidget(SinalAcsApp(backend: backend));
        await login(tester);

        await tester.tap(find.text('Status'));
        await tester.pumpAndSettle();

        expect(find.text('Risco: Vermelho'), findsOneWidget);
        expect(find.text('Recebido pela equipe de saúde'), findsOneWidget);
      });

      testWidgets('uma falha ao consultar mostra o aviso, sem travar o botão de tentar de novo', (tester) async {
        final backend = FakePatientBackend()
          ..statusFailure = const BackendFailure('Sem conexão com o servidor.');
        await tester.pumpWidget(SinalAcsApp(backend: backend));
        await login(tester);

        await tester.tap(find.text('Status'));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('status_error')), findsOneWidget);
        expect(find.text('Sem conexão com o servidor.'), findsOneWidget);
        expect(
          tester.widget<FilledButton>(find.byKey(const Key('refresh_status'))).onPressed,
          isNotNull,
        );
      });

      testWidgets('"Verificar status agora" repete a consulta manualmente', (tester) async {
        final backend = FakePatientBackend();
        await tester.pumpWidget(SinalAcsApp(backend: backend));
        await login(tester);
        await tester.tap(find.text('Status'));
        await tester.pumpAndSettle();
        expect(backend.statusForCallCount, 1);

        await tester.tap(find.byKey(const Key('refresh_status')));
        await tester.pumpAndSettle();
        expect(backend.statusForCallCount, 2);
      });
    });
  ```

- [x] **Step 2: Rodar e confirmar que falha**

  Run: `cd apps/patient && flutter test test/patient_app_mvp_test.dart`
  Expected: FAIL — `FakePatientBackend` não implementa `statusFor`/`statusForCallCount`/`statusResult`/`statusFailure` (erro de compilação).

- [x] **Step 3: `PatientBackend.statusFor()`**

  Em `apps/patient/lib/core/network/backend_client.dart`, adicionar à interface `PatientBackend`, logo após `evaluateTriage`:

  ```dart
    /// Status do alerta mais recente do paciente autenticado (RF05, decisão
    /// §5). `found: false` quando o paciente nunca disparou um alerta.
    Future<AlertStatusResult> statusFor();
  ```

  Adicionar a implementação em `BackendClient`, logo após `evaluateTriage`:

  ```dart
    /// Ver ressalva de [PatientBackend.statusFor]. `patientId` nunca é
    /// argumento — o servidor deriva do token (INV-05).
    @override
    Future<AlertStatusResult> statusFor() async {
      final token = await _requireToken();
      return _guard(() => _client.alerts.statusFor(accessToken: token));
    }
  ```

- [x] **Step 4: `FakePatientBackend.statusFor()`**

  Em `apps/patient/test/support/fake_patient_backend.dart`, adicionar campos logo após `enrollmentFailure`:

  ```dart
    AlertStatusResult statusResult = AlertStatusResult(found: false);
    BackendFailure? statusFailure;
    int statusForCallCount = 0;
  ```

  Adicionar o método, logo após `evaluateTriage`:

  ```dart
    @override
    Future<AlertStatusResult> statusFor() async {
      statusForCallCount++;
      final failure = statusFailure;
      if (failure != null) throw failure;
      return statusResult;
    }
  ```

- [x] **Step 5: `StatusScreen` deixa de ser `const`, busca o status real**

  Em `apps/patient/lib/app/app.dart`, ajustar o import de `sinalacs_client` (linha 3):

  ```dart
  import 'package:sinalacs_client/sinalacs_client.dart' show RiskLevel;
  ```

  para:

  ```dart
  import 'package:sinalacs_client/sinalacs_client.dart'
      show AlertStatus, AlertStatusResult, RiskLevel;
  ```

  Substituir a classe inteira `StatusScreen` e `_StatusStep` (removida — sem outro uso):

  ```dart
  class StatusScreen extends StatelessWidget {
    const StatusScreen({super.key});

    @override
    Widget build(BuildContext context) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Solicitação de visita #4082', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text('Triagem Vermelha • criada hoje às 09:30'),
                  SizedBox(height: 28),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_StatusStep('Enviado', true), _StatusStep('Visualizado', true), _StatusStep('Em análise', true), _StatusStep('Agendado', false)]),
                  SizedBox(height: 28),
                  Divider(),
                  SizedBox(height: 12),
                  Text('Última atualização pelo ACS', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text('Chamado recebido e priorizado na fila da microárea.'),
                ],
              ),
            ),
          ),
        ],
      );
    }
  }

  class _StatusStep extends StatelessWidget { const _StatusStep(this.label, this.done); final String label; final bool done; @override Widget build(BuildContext context) => Column(children: [Icon(done ? Icons.check_circle : Icons.calendar_today_outlined, color: done ? PatientColors.accent : Colors.white54), const SizedBox(height: 6), SizedBox(width: 65, child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)))]); }
  ```

  por:

  ```dart
  /// Acompanhamento da solicitação do paciente (RF05, decisão §5) — consome
  /// `alerts.statusFor`, escopado ao próprio paciente pelo token.
  ///
  /// Antes mostrava sempre "Solicitação de visita #4082" com passos fixos,
  /// inclusive para quem nunca disparou um alerta (L-03, "Tela de Status
  /// mente para o paciente" em spec/validation_report.md). Estado próprio
  /// (não no shell): um teste existente constrói `PatientHomeShell` só sob
  /// `RemindersScope`, sem `BackendScope` — buscar o status no shell quebraria
  /// esse teste mesmo quando a aba aberta é outra.
  class StatusScreen extends StatelessWidget {
    const StatusScreen({super.key});

    @override
    Widget build(BuildContext context) => const _StatusScreenBody();
  }

  class _StatusScreenBody extends StatefulWidget {
    const _StatusScreenBody();

    @override
    State<_StatusScreenBody> createState() => _StatusScreenBodyState();
  }

  class _StatusScreenBodyState extends State<_StatusScreenBody> {
    bool _loading = false;
    AlertStatusResult? _status;
    String? _error;
    DateTime? _checkedAt;
    bool _requestedLoad = false;

    @override
    void didChangeDependencies() {
      super.didChangeDependencies();
      // BackendScope.of(context) só é seguro a partir daqui, não em
      // initState — mesmo padrão de RemindersScreen._requestedLoad.
      if (!_requestedLoad) {
        _requestedLoad = true;
        _load();
      }
    }

    Future<void> _load() async {
      setState(() { _loading = true; _error = null; });
      try {
        final status = await BackendScope.of(context).statusFor();
        if (!mounted) return;
        setState(() {
          _status = status;
          _checkedAt = DateTime.now();
        });
      } on BackendFailure catch (failure) {
        if (!mounted) return;
        setState(() => _error = failure.message);
      } catch (_) {
        if (!mounted) return;
        setState(() => _error = 'Não foi possível verificar o status da solicitação.');
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }

    @override
    Widget build(BuildContext context) {
      final current = _status;
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              // SC 4.1.3, mesmo padrão do erro de login/onboarding/lembretes.
              child: Semantics(
                liveRegion: true,
                child: Text(
                  key: const Key('status_error'),
                  _error!,
                  style: const TextStyle(color: PatientColors.dangerOnSurface, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          if (current == null || !current.found)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      key: const Key('status_empty'),
                      _loading ? 'Verificando...' : 'Nenhuma solicitação registrada ainda.',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Um alerta de urgência ou uma triagem concluída aparece aqui assim que a equipe recebe.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            )
          else
            _StatusCard(status: current),
          const SizedBox(height: 20),
          FilledButton(
            key: const Key('refresh_status'),
            onPressed: _loading ? null : _load,
            style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
            child: _loading
                ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Verificar status agora'),
          ),
          if (_checkedAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Verificado às ${_formatTime(_checkedAt!)}',
                style: const TextStyle(fontSize: 12, color: Colors.white54),
              ),
            ),
        ],
      );
    }
  }

  class _StatusCard extends StatelessWidget {
    const _StatusCard({required this.status});

    final AlertStatusResult status;

    @override
    Widget build(BuildContext context) {
      // Mesma disciplina de cor de `_TriageResult`: `OnSurface` porque o tom
      // aparece como texto sobre `Card`, não como preenchimento.
      final (riskLabel, riskColor) = switch (status.riskLevel) {
        RiskLevel.red => ('Vermelho', PatientColors.dangerOnSurface),
        RiskLevel.yellow => ('Amarelo', const Color(0xFFE0A800)),
        RiskLevel.green => ('Verde', PatientColors.accentOnSurface),
        null => ('Não classificado', Colors.white70),
      };
      final statusLabel = switch (status.status) {
        AlertStatus.pending => 'Enviado — aguardando confirmação da equipe',
        AlertStatus.acknowledged => 'Recebido pela equipe de saúde',
        AlertStatus.resolved => 'Atendimento concluído',
        AlertStatus.escalated => 'Encaminhado para o SAMU',
        null => 'Sem status',
      };
      final triggeredAt = status.triggeredAt;
      final acknowledgedAt = status.acknowledgedAt;

      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                key: const Key('status_risk'),
                'Risco: $riskLabel',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: riskColor),
              ),
              if (triggeredAt != null) ...[
                const SizedBox(height: 8),
                Text('Disparado às ${_formatTime(triggeredAt)}'),
              ],
              const SizedBox(height: 16),
              Text(
                key: const Key('status_label'),
                statusLabel,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (acknowledgedAt != null) ...[
                const SizedBox(height: 4),
                Text('Confirmado pela equipe às ${_formatTime(acknowledgedAt)}'),
              ],
            ],
          ),
        ),
      );
    }
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
  ```

- [x] **Step 6: Rodar e confirmar que passa**

  Run: `cd apps/patient && flutter test test/patient_app_mvp_test.dart`
  Expected: PASS.

- [x] **Step 7: Rodar a suíte inteira do app paciente**

  Run: `cd apps/patient && flutter analyze && flutter test`
  Expected: PASS — inclusive o teste de Lembretes que constrói `PatientHomeShell` sem `BackendScope` (não passa pela aba Status, então `_StatusScreenBodyState` nunca monta).

- [x] **Step 8: Commit**

  ```bash
  git add apps/patient/lib/core/network/backend_client.dart apps/patient/lib/app/app.dart \
          apps/patient/test/support/fake_patient_backend.dart apps/patient/test/patient_app_mvp_test.dart
  git commit -m "feat(patient): tela Status consome alerts.statusFor (RF05, fecha L-03)"
  ```

---

### Task 5: ACS — sincronização periódica em segundo plano

**Files:**
- Modify: `apps/acs/lib/app/app.dart`
- Test: `apps/acs/test/login_flow_test.dart`

**Interfaces:**
- Consumes: `_pullVisits()` (RF15, já existe), `_loadMicroAreaPatients()` (Task 1), `ReconnectSchedule`/`_reconnectTimer` (padrão de lifecycle já existente no mesmo state).
- Produces: `AcsHomeShell`/`LoginScreen`/`SinalAcsApp` ganham `syncInterval: Duration?` opcional — default de produção `AcsHomeShell.defaultSyncInterval` (5 minutos), testes passam um valor curto.

- [x] **Step 1: Escrever os testes que falham**

  Em `apps/acs/test/login_flow_test.dart`, adicionar um novo `group`, depois do `group('território real na tela Área (L-06/RF08)', ...)` (Task 1), antes do `}` que fecha `main()`:

  ```dart
  group('sincronização periódica em segundo plano', () {
    testWidgets('repete a sincronização com a central em intervalos, sem toque manual', (tester) async {
      final backend = FakeAcsBackend();

      await tester.pumpWidget(SinalAcsApp(
        backend: backend,
        feedBuilder: (queue) => FakeAlertFeed(queue),
        syncInterval: const Duration(seconds: 10),
      ));
      await tester.tap(find.byKey(const Key('login_button')));
      await tester.pumpAndSettle();

      expect(backend.listPatientsCount, 1);

      await tester.pump(const Duration(seconds: 10));
      expect(backend.listPatientsCount, 2);

      await tester.pump(const Duration(seconds: 10));
      expect(backend.listPatientsCount, 3);
    });

    testWidgets('sair do primeiro plano cancela o ciclo; voltar sincroniza na hora e recomeça', (tester) async {
      final backend = FakeAcsBackend();

      await tester.pumpWidget(SinalAcsApp(
        backend: backend,
        feedBuilder: (queue) => FakeAlertFeed(queue),
        syncInterval: const Duration(seconds: 10),
      ));
      await tester.tap(find.byKey(const Key('login_button')));
      await tester.pumpAndSettle();
      expect(backend.listPatientsCount, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 30));
      // Em segundo plano, nenhum ciclo novo dispara.
      expect(backend.listPatientsCount, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      // Retomar sincroniza imediatamente...
      expect(backend.listPatientsCount, 2);

      // ...e o ciclo periódico recomeça do zero a partir daqui.
      await tester.pump(const Duration(seconds: 10));
      expect(backend.listPatientsCount, 3);
    });
  });
  ```

- [x] **Step 2: Rodar e confirmar que falha**

  Run: `cd apps/acs && flutter test test/login_flow_test.dart`
  Expected: FAIL — `SinalAcsApp` não tem parâmetro nomeado `syncInterval` (erro de compilação).

- [x] **Step 3: Threadear `syncInterval` por `SinalAcsApp` → `LoginScreen` → `AcsHomeShell`**

  Em `apps/acs/lib/app/app.dart`, substituir:

  ```dart
  class SinalAcsApp extends StatefulWidget {
    const SinalAcsApp({
      super.key,
      this.backend,
      this.feedBuilder,
      this.visitQueue,
      this.visitPullService,
      this.initialAlert,
      this.currentPosition,
    });

    /// Injetáveis para teste. Em execução normal são as implementações reais.
    final AcsBackend? backend;
    final AlertFeed Function(AlertQueue queue)? feedBuilder;
    final OfflineVisitQueue? visitQueue;
    final VisitPullService? visitPullService;
    final PrioritizedAlert? initialAlert;
    final LatLng? currentPosition;
  ```

  por:

  ```dart
  class SinalAcsApp extends StatefulWidget {
    const SinalAcsApp({
      super.key,
      this.backend,
      this.feedBuilder,
      this.visitQueue,
      this.visitPullService,
      this.initialAlert,
      this.currentPosition,
      this.syncInterval,
    });

    /// Injetáveis para teste. Em execução normal são as implementações reais.
    final AcsBackend? backend;
    final AlertFeed Function(AlertQueue queue)? feedBuilder;
    final OfflineVisitQueue? visitQueue;
    final VisitPullService? visitPullService;
    final PrioritizedAlert? initialAlert;
    final LatLng? currentPosition;

    /// Intervalo da sincronização periódica em segundo plano (visitas +
    /// pacientes da microárea). `null` usa `AcsHomeShell.defaultSyncInterval`
    /// — testes passam um valor curto para não esperar 5 minutos reais.
    final Duration? syncInterval;
  ```

  Em `_SinalAcsAppState.build()`, substituir:

  ```dart
          home: LoginScreen(
            feedBuilder: widget.feedBuilder,
            visitQueue: _visitQueue,
            visitPullService: _visitPullService,
            initialAlert: widget.initialAlert,
            initialPosition: widget.currentPosition,
          ),
  ```

  por:

  ```dart
          home: LoginScreen(
            feedBuilder: widget.feedBuilder,
            visitQueue: _visitQueue,
            visitPullService: _visitPullService,
            initialAlert: widget.initialAlert,
            initialPosition: widget.currentPosition,
            syncInterval: widget.syncInterval,
          ),
  ```

  Em `LoginScreen`, substituir:

  ```dart
  class LoginScreen extends StatefulWidget {
    const LoginScreen({
      required this.visitQueue,
      required this.visitPullService,
      super.key,
      this.feedBuilder,
      this.initialAlert,
      this.initialPosition,
    });

    final AlertFeed Function(AlertQueue queue)? feedBuilder;
    final OfflineVisitQueue visitQueue;
    final VisitPullService visitPullService;
    final PrioritizedAlert? initialAlert;
    final LatLng? initialPosition;
  ```

  por:

  ```dart
  class LoginScreen extends StatefulWidget {
    const LoginScreen({
      required this.visitQueue,
      required this.visitPullService,
      super.key,
      this.feedBuilder,
      this.initialAlert,
      this.initialPosition,
      this.syncInterval,
    });

    final AlertFeed Function(AlertQueue queue)? feedBuilder;
    final OfflineVisitQueue visitQueue;
    final VisitPullService visitPullService;
    final PrioritizedAlert? initialAlert;
    final LatLng? initialPosition;
    final Duration? syncInterval;
  ```

  Em `_LoginScreenState._enter()`, substituir:

  ```dart
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => AcsHomeShell(
            microAreaId: microAreaId,
            acsId: session.userId,
            feedBuilder: widget.feedBuilder,
            visitQueue: widget.visitQueue,
            visitPullService: widget.visitPullService,
            initialAlert: widget.initialAlert,
            initialPosition: widget.initialPosition,
          ),
        ));
  ```

  por:

  ```dart
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => AcsHomeShell(
            microAreaId: microAreaId,
            acsId: session.userId,
            feedBuilder: widget.feedBuilder,
            visitQueue: widget.visitQueue,
            visitPullService: widget.visitPullService,
            initialAlert: widget.initialAlert,
            initialPosition: widget.initialPosition,
            syncInterval: widget.syncInterval,
          ),
        ));
  ```

  Em `AcsHomeShell`, substituir:

  ```dart
  class AcsHomeShell extends StatefulWidget {
    const AcsHomeShell({
      required this.microAreaId,
      required this.acsId,
      required this.visitQueue,
      required this.visitPullService,
      super.key,
      this.feedBuilder,
      this.initialAlert,
      this.initialPosition,
    });

    final String microAreaId;
    final String acsId;
    final AlertFeed Function(AlertQueue queue)? feedBuilder;
    final PrioritizedAlert? initialAlert;
    final LatLng? initialPosition;
  ```

  por:

  ```dart
  class AcsHomeShell extends StatefulWidget {
    const AcsHomeShell({
      required this.microAreaId,
      required this.acsId,
      required this.visitQueue,
      required this.visitPullService,
      super.key,
      this.feedBuilder,
      this.initialAlert,
      this.initialPosition,
      this.syncInterval,
    });

    final String microAreaId;
    final String acsId;
    final AlertFeed Function(AlertQueue queue)? feedBuilder;
    final PrioritizedAlert? initialAlert;
    final LatLng? initialPosition;

    /// Intervalo entre sincronizações automáticas com a central (visitas +
    /// pacientes da microárea), além do disparo ao abrir o painel e do botão
    /// manual. `null` usa [defaultSyncInterval].
    final Duration? syncInterval;

    /// Produção: 5 minutos é frequente o bastante para um ACS ver, sem apertar
    /// botão, uma visita registrada por outro colega — sem virar polling
    /// agressivo que gasta bateria/dados em campo.
    static const defaultSyncInterval = Duration(minutes: 5);
  ```

- [x] **Step 4: `_AcsHomeShellState` roda o ciclo periódico**

  Adicionar campo, logo após `final ReconnectSchedule _reconnectDelay = ReconnectSchedule();`:

  ```dart
    /// `null` quando nenhum ciclo periódico está agendado (app em segundo
    /// plano, ou ainda não iniciado).
    Timer? _periodicSyncTimer;

    Duration get _syncInterval => widget.syncInterval ?? AcsHomeShell.defaultSyncInterval;
  ```

  Em `initState()`, substituir:

  ```dart
      _feed.onConnectionChanged = _onBrokerConnectionChanged;
      _connectFeed();
      _restoreVisits();
      _pullVisits();
      _loadCurrentPosition();
    }
  ```

  por:

  ```dart
      _feed.onConnectionChanged = _onBrokerConnectionChanged;
      _connectFeed();
      _restoreVisits();
      _pullVisits();
      _loadCurrentPosition();
      _startPeriodicSync();
    }

    /// Sincronização periódica em segundo plano: repete `_pullVisits()` e
    /// `_loadMicroAreaPatients()` a cada [_syncInterval] enquanto o painel está
    /// aberto e o app em primeiro plano — sem isso, um ACS só via dado novo ao
    /// reabrir a aba "Área" ou apertar "Atualizar dados da microárea" (decisão
    /// de produto adiada em
    /// docs/superpowers/plans/2026-09-18-rf15-consumo-acs-pull-visitas.md).
    void _startPeriodicSync() {
      _periodicSyncTimer?.cancel();
      _periodicSyncTimer = Timer.periodic(_syncInterval, (_) {
        _pullVisits();
        _loadMicroAreaPatients();
      });
    }
  ```

  Em `didChangeAppLifecycleState`, substituir:

  ```dart
    @override
    void didChangeAppLifecycleState(AppLifecycleState state) {
      if (state == AppLifecycleState.paused) {
        // Um Timer em segundo plano no Android não é confiável e só gastaria
        // bateria; a tentativa volta ao primeiro plano.
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
      } else if (state == AppLifecycleState.resumed && _feedErrorIsTransient) {
        // O gatilho que mais importa na prática: o sinal costuma voltar com a
        // tela apagada, e o ACS tira o aparelho do bolso já esperando o alerta.
        _reconnectDelay.reset();
        _connectFeed();
      }
    }
  ```

  por:

  ```dart
    @override
    void didChangeAppLifecycleState(AppLifecycleState state) {
      if (state == AppLifecycleState.paused) {
        // Um Timer em segundo plano no Android não é confiável e só gastaria
        // bateria; a tentativa volta ao primeiro plano.
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        _periodicSyncTimer?.cancel();
        _periodicSyncTimer = null;
      } else if (state == AppLifecycleState.resumed) {
        if (_feedErrorIsTransient) {
          // O gatilho que mais importa na prática: o sinal costuma voltar com
          // a tela apagada, e o ACS tira o aparelho do bolso já esperando o
          // alerta.
          _reconnectDelay.reset();
          _connectFeed();
        }
        // Retomar sincroniza na hora — sem isto, um app que passou minutos em
        // segundo plano só voltaria a sincronizar no próximo toque manual ou
        // na próxima virada do ciclo, que pode estar longe.
        _pullVisits();
        _loadMicroAreaPatients();
        _startPeriodicSync();
      }
    }
  ```

  Em `dispose()`, substituir:

  ```dart
    @override
    void dispose() {
      _reconnectTimer?.cancel();
      WidgetsBinding.instance.removeObserver(this);
      _feed.stop();
      _queue.dispose();
      super.dispose();
    }
  ```

  por:

  ```dart
    @override
    void dispose() {
      _reconnectTimer?.cancel();
      _periodicSyncTimer?.cancel();
      WidgetsBinding.instance.removeObserver(this);
      _feed.stop();
      _queue.dispose();
      super.dispose();
    }
  ```

- [x] **Step 5: Rodar e confirmar que passa**

  Run: `cd apps/acs && flutter test test/login_flow_test.dart`
  Expected: PASS.

- [x] **Step 6: Rodar a suíte inteira do app ACS**

  Run: `cd apps/acs && flutter analyze && flutter test`
  Expected: PASS — nenhum teste pré-existente quebra: todo teste que não passa `syncInterval` usa o default de 5 minutos, tempo demais para qualquer teste (que roda em segundos de tempo simulado) disparar um segundo ciclo por acidente.

- [x] **Step 7: Commit**

  ```bash
  git add apps/acs/lib/app/app.dart apps/acs/test/login_flow_test.dart
  git commit -m "feat(acs): sincronização periódica em segundo plano (visitas + microárea), pausada fora do primeiro plano"
  ```

---

### Task 6: Paciente — sincronização periódica em segundo plano

**Files:**
- Modify: `apps/patient/lib/app/app.dart`
- Test: `apps/patient/test/patient_app_mvp_test.dart`

**Interfaces:**
- Consumes: `_StatusScreenBodyState._load()` (Task 4).
- Produces: `StatusScreen` ganha `syncInterval: Duration` (default `Duration(minutes: 5)`, `const`-compatível) — usado só em teste; nenhum outro arquivo consome.

- [x] **Step 1: Escrever os testes que falham**

  Em `apps/patient/test/patient_app_mvp_test.dart`, adicionar um helper e um novo `group`, depois do `group('Status da solicitação (RF05)', ...)` (Task 4), antes do `}` que fecha `main()`:

  ```dart
    group('sincronização periódica em segundo plano (RF05)', () {
      Widget buildStatusScreen(FakePatientBackend backend, {required Duration syncInterval}) {
        return MaterialApp(
          home: BackendScope(
            backend: backend,
            child: StatusScreen(syncInterval: syncInterval),
          ),
        );
      }

      testWidgets('repete a consulta de status em intervalos, sem toque manual', (tester) async {
        final backend = FakePatientBackend();
        await tester.pumpWidget(buildStatusScreen(backend, syncInterval: const Duration(seconds: 10)));
        await tester.pumpAndSettle();

        expect(backend.statusForCallCount, 1);

        await tester.pump(const Duration(seconds: 10));
        expect(backend.statusForCallCount, 2);

        await tester.pump(const Duration(seconds: 10));
        expect(backend.statusForCallCount, 3);
      });

      testWidgets('sair do primeiro plano cancela o ciclo; voltar consulta na hora e recomeça', (tester) async {
        final backend = FakePatientBackend();
        await tester.pumpWidget(buildStatusScreen(backend, syncInterval: const Duration(seconds: 10)));
        await tester.pumpAndSettle();
        expect(backend.statusForCallCount, 1);

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump(const Duration(seconds: 30));
        expect(backend.statusForCallCount, 1);

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pumpAndSettle();
        expect(backend.statusForCallCount, 2);

        await tester.pump(const Duration(seconds: 10));
        expect(backend.statusForCallCount, 3);
      });
    });
  ```

- [x] **Step 2: Rodar e confirmar que falha**

  Run: `cd apps/patient && flutter test test/patient_app_mvp_test.dart`
  Expected: FAIL — `StatusScreen` não tem parâmetro nomeado `syncInterval` (erro de compilação).

- [x] **Step 3: `StatusScreen` ganha `syncInterval` e o ciclo periódico**

  Em `apps/patient/lib/app/app.dart`, adicionar `import 'dart:async';` ao topo dos imports (antes de `import 'package:flutter/material.dart';`).

  Substituir:

  ```dart
  class StatusScreen extends StatelessWidget {
    const StatusScreen({super.key});

    @override
    Widget build(BuildContext context) => const _StatusScreenBody();
  }

  class _StatusScreenBody extends StatefulWidget {
    const _StatusScreenBody();

    @override
    State<_StatusScreenBody> createState() => _StatusScreenBodyState();
  }

  class _StatusScreenBodyState extends State<_StatusScreenBody> {
    bool _loading = false;
    AlertStatusResult? _status;
    String? _error;
    DateTime? _checkedAt;
    bool _requestedLoad = false;

    @override
    void didChangeDependencies() {
      super.didChangeDependencies();
      // BackendScope.of(context) só é seguro a partir daqui, não em
      // initState — mesmo padrão de RemindersScreen._requestedLoad.
      if (!_requestedLoad) {
        _requestedLoad = true;
        _load();
      }
    }

    Future<void> _load() async {
  ```

  por:

  ```dart
  class StatusScreen extends StatelessWidget {
    const StatusScreen({super.key, this.syncInterval = const Duration(minutes: 5)});

    /// Intervalo da sincronização periódica em segundo plano, além da busca ao
    /// abrir a aba e do botão manual. Produção usa o default (5 minutos);
    /// testes passam um valor curto para não esperar tempo real.
    final Duration syncInterval;

    @override
    Widget build(BuildContext context) => _StatusScreenBody(syncInterval: syncInterval);
  }

  class _StatusScreenBody extends StatefulWidget {
    const _StatusScreenBody({required this.syncInterval});

    final Duration syncInterval;

    @override
    State<_StatusScreenBody> createState() => _StatusScreenBodyState();
  }

  class _StatusScreenBodyState extends State<_StatusScreenBody> with WidgetsBindingObserver {
    bool _loading = false;
    AlertStatusResult? _status;
    String? _error;
    DateTime? _checkedAt;
    bool _requestedLoad = false;

    /// `null` quando nenhum ciclo periódico está agendado (app em segundo
    /// plano, ou ainda não iniciado).
    Timer? _syncTimer;

    @override
    void initState() {
      super.initState();
      WidgetsBinding.instance.addObserver(this);
    }

    @override
    void didChangeDependencies() {
      super.didChangeDependencies();
      // BackendScope.of(context) só é seguro a partir daqui, não em
      // initState — mesmo padrão de RemindersScreen._requestedLoad.
      if (!_requestedLoad) {
        _requestedLoad = true;
        _load();
        _startPeriodicSync();
      }
    }

    /// Sincronização periódica em segundo plano: repete `_load()` a cada
    /// `widget.syncInterval` enquanto a aba Status está montada e o app em
    /// primeiro plano — sem isto, o paciente só via um status novo reabrindo
    /// a aba ou apertando "Verificar status agora".
    void _startPeriodicSync() {
      _syncTimer?.cancel();
      _syncTimer = Timer.periodic(widget.syncInterval, (_) => _load());
    }

    @override
    void didChangeAppLifecycleState(AppLifecycleState state) {
      if (state == AppLifecycleState.paused) {
        // Um Timer em segundo plano no Android não é confiável e só gastaria
        // bateria; a tentativa volta ao primeiro plano — mesmo padrão do ACS
        // (`_AcsHomeShellState._periodicSyncTimer`).
        _syncTimer?.cancel();
        _syncTimer = null;
      } else if (state == AppLifecycleState.resumed) {
        _load();
        _startPeriodicSync();
      }
    }

    @override
    void dispose() {
      _syncTimer?.cancel();
      WidgetsBinding.instance.removeObserver(this);
      super.dispose();
    }

    Future<void> _load() async {
  ```

- [x] **Step 4: Rodar e confirmar que passa**

  Run: `cd apps/patient && flutter test test/patient_app_mvp_test.dart`
  Expected: PASS.

- [x] **Step 5: Rodar a suíte inteira do app paciente**

  Run: `cd apps/patient && flutter analyze && flutter test`
  Expected: PASS — inclusive o teste de Lembretes sem `BackendScope` (continua sem montar a aba Status) e os testes de Status da Task 4 (usam o default de 5 minutos, tempo demais para disparar um segundo ciclo em segundos de tempo simulado).

- [x] **Step 6: Commit**

  ```bash
  git add apps/patient/lib/app/app.dart apps/patient/test/patient_app_mvp_test.dart
  git commit -m "feat(patient): sincronização periódica em segundo plano na tela Status, pausada fora do primeiro plano"
  ```

---

### Task 7: Documentação — RF05, RF15, L-03, L-06, sincronização periódica

**Files:**
- Modify: `spec/validation_report.md`
- Modify: `spec/PRD_system.md`
- Modify: `docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md`

**Interfaces:** Nenhuma — só texto.

- [x] **Step 1: Atualizar `spec/validation_report.md`**

  Localizar a linha RF15 (já atualizada pelo plano de 2026-09-18 anterior):

  ```
  | RF15 | Sincronização bidirecional | **parcial** | Dispositivo → central e central → dispositivo (`visits.pull`, cursor por dispositivo) funcionam e são testados, incluindo a tela do ACS que consome o pull. Falta só o lado do paciente (RF05, `alerts.statusFor`) — ver §5 de `docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md`. |
  ```

  Substituir por:

  ```
  | RF15 | Sincronização bidirecional | **sim** | Dispositivo → central e central → dispositivo funcionam e são testados dos dois lados: ACS (`visits.pull`) e paciente (`alerts.statusFor`, RF05). Ambos rodam automaticamente ao abrir a tela, em ciclo periódico enquanto o app está em primeiro plano, e por botão manual. |
  ```

  Localizar a linha RF08:

  ```
  | RF08 | Territorialização (cache da microárea) | **parcial** | `patients.listMicroArea` é real e territorializado. A tela "Área" mostra literais — ver L-06. |
  ```

  Substituir por:

  ```
  | RF08 | Territorialização (cache da microárea) | **parcial** | `patients.listMicroArea` é real, territorializado, e a tela "Área" agora mostra o número real de pacientes (L-06 fechado). Continua parcial: a chamada é ao vivo a cada abertura/ciclo periódico, não um cache `sqflite` persistido em disco que sobrevive offline — esse é o trabalho que falta para RF08 completo. |
  ```

  Localizar e remover da lista P1 (Alto risco):

  ```
  - **L-06 · Tela "Área" com números falsos** que contradizem o backend (142 vs 5).
  ```

  Adicionar, na seção de itens fechados (mesmo formato usado para outros itens já resolvidos nesta tabela — buscar por "~~" ou "fechado" no arquivo para seguir o padrão local), uma linha registrando que L-06 e L-03 foram fechados por este plano, citando este arquivo.

- [x] **Step 2: Marcar RF05/RF15 concluídos em `docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md`**

  Na seção `## 5. Sincronização central → dispositivo (RF15, metade ausente)`, subseção `### Plano derivado (não executado nesta tarefa)`, localizar:

  ```
  - `visits.pull` e/ou `alerts.pull` no backend, com teste de território
    (reaproveitando os casos de `patients.listMicroArea`).
  - `alerts.statusFor` escopado ao token do paciente, com teste de que um
    token não pode ler o status de outro paciente (fecha INV-05 com evidência,
    não por ausência de endpoint).
  - Tela de Status do paciente deixa de ser `const` (fecha L-03 do relatório de
    validação, hoje classificada como "Tela de Status mente para o paciente").
  - ~~Consumo do cursor pelo app ACS (fila)~~ — feito: `VisitPullService` (Task
    10 do plano de implementação) mais a tela "Área" que o aciona e mostra o
    resultado (`docs/superpowers/plans/2026-09-18-rf15-consumo-acs-pull-visitas.md`).
    Falta ainda o consumo pelo app paciente (status) — mesma garantia de
    device reinstalado sem duplicar nem perder itens já vale para o ACS
    (coberta em `apps/acs/test/visit_pull_service_test.dart` e
    `apps/acs/test/sync_cursor_store_test.dart`); falta provar o equivalente
    do lado paciente quando esse trabalho for feito.
  ```

  Substituir por:

  ```
  - ~~`visits.pull` no backend, com teste de território~~ — feito (plano de
    2026-09-17/18, Task 10 + consumo pelo ACS).
  - ~~`alerts.statusFor` escopado ao token do paciente~~ — feito
    (`docs/superpowers/plans/2026-09-18-sync-periodica-rf05-l06.md`, Tasks
    2-3): sem `patientId` como parâmetro, então um token só pode ler o
    próprio status por construção (INV-05).
  - ~~Tela de Status do paciente deixa de ser `const`~~ — feito (mesmo plano,
    Task 4): fecha L-03 do relatório de validação.
  - ~~Consumo do cursor pelo app ACS (fila)~~ — feito: `VisitPullService` (Task
    10 do plano de implementação) mais a tela "Área" que o aciona e mostra o
    resultado (`docs/superpowers/plans/2026-09-18-rf15-consumo-acs-pull-visitas.md`).
  - ~~Sincronização periódica em segundo plano~~ — feito (mesmo plano, Tasks 5
    e 6): `Timer.periodic` no shell do ACS e na tela Status do paciente, além
    do disparo ao abrir e do botão manual, pausado fora do primeiro plano.

  RF15 está completo dos dois lados (ACS e paciente). O que falta para RF08
  completo — cache `sqflite` persistido, não só a chamada ao vivo — é
  trabalho novo, não coberto aqui.
  ```

- [x] **Step 3: Nota em `spec/PRD_system.md`**

  Na seção "2.2.1 Decisões de produto pós-validação", no parágrafo "Cada linha é um plano independente...", localizar o parágrafo adicionado pelo plano anterior:

  ```
  RF15 teve sua metade ACS (contrato + tela consumidora) implementada em
  `docs/superpowers/plans/2026-09-17-decisoes-produto-pos-validacao-implementacao.md`
  (Task 10) e `docs/superpowers/plans/2026-09-18-rf15-consumo-acs-pull-visitas.md`;
  a metade paciente (RF05) segue pendente.
  ```

  Substituir por:

  ```
  RF15 teve sua metade ACS (contrato + tela consumidora) implementada em
  `docs/superpowers/plans/2026-09-17-decisoes-produto-pos-validacao-implementacao.md`
  (Task 10) e `docs/superpowers/plans/2026-09-18-rf15-consumo-acs-pull-visitas.md`;
  a metade paciente (RF05, `alerts.statusFor`) e a sincronização periódica em
  segundo plano nos dois apps foram implementadas em
  `docs/superpowers/plans/2026-09-18-sync-periodica-rf05-l06.md`, que também
  fechou o débito L-06/RF08 (números reais na tela "Área" do ACS).
  ```

- [x] **Step 4: Commit**

  ```bash
  git add spec/validation_report.md spec/PRD_system.md docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md
  git commit -m "docs: registrar RF05/RF15 completos, L-03/L-06 fechados e sincronização periódica"
  ```

---

## Escopo explicitamente fora deste plano

- **Cache `sqflite` persistido da microárea (RF08 completo).** Este plano corrige o número mentiroso na tela "Área" (L-06) usando a mesma chamada ao vivo que já existe (`patients.listMicroArea`); não adiciona um cache local que sobrevive offline. Isso é o que falta para reclassificar RF08 de "parcial" para "sim" — trabalho novo, fora daqui.
- **`WorkManager`/background fetch nativo (execução com o app fechado).** "Segundo plano" aqui significa "app aberto, mesmo que não na aba", igual ao vocabulário já usado em `spec/stack.md`/`spec/sys_flow.md` para a sincronização de visitas por conectividade. Sincronizar com o app processo morto exigiria integração nativa por plataforma (`WorkManager`/`BGTaskScheduler`), fora do stack decidido em `spec/stack.md` e desproporcional ao estágio de protótipo do projeto.
- **Escalonamento SAMU (L-07)** e **RPC sem TLS (L-08)** — débitos técnicos documentados à parte em `spec/validation_report.md`, sem relação com sincronização/RF05/RF08.
- **Histórico de múltiplos alertas do paciente.** `alerts.statusFor` devolve só o mais recente — suficiente para a tela de Status (que sempre mostrou uma única "solicitação"); uma lista histórica é extensão de produto separada.
