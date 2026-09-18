# RF15 — Consumo do pull central→dispositivo no app ACS — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dar ao app ACS uma tela que efetivamente chama `VisitPullService.pullAndMerge()` e mostra o resultado, para que RF15 (sincronização central→dispositivo) deixe de ser um contrato sem comportamento observável.

**Architecture:** `VisitPullService`, `SyncCursorStore` e o endpoint `visits.pull` já existem e já são testados (Task 10 do plano `2026-09-17-decisoes-produto-pos-validacao-implementacao.md`) — nenhum código novo de sincronização, só o fio que falta entre o serviço e a UI. O `VisitStore` (`SqlCipherVisitStore`) que hoje só a `OfflineVisitQueue` usa passa a ser compartilhado com o `VisitPullService`, porque é dele que o serviço lê para nunca reintroduzir localmente uma visita que já está na fila offline (dedupe por `localId`, ver a documentação de `VisitPullService`). A tela "Área" (`TerritorializationScreen`) — hoje um placeholder com um botão que só mostra um snackbar — passa a acionar e exibir esse pull de verdade; é a consumidora que a Task 10 deixou deliberadamente em aberto. O disparo é automático ao abrir o painel (mesmo padrão de `_restoreVisits`/`_loadCurrentPosition` em `AcsHomeShell.initState`) mais um botão manual — não um timer de sincronização em segundo plano, que é uma decisão de produto separada e fora do escopo deste item.

**Tech Stack:** Flutter/Dart (`apps/acs`), `sqflite_sqlcipher` (banco local já cifrado), cliente Serverpod gerado (`sinalacs_client`) via `AcsBackend.pullVisits`.

**Spec:** `docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md` §5 ("Sincronização central → dispositivo (RF15, metade ausente)") e `spec/validation_report.md` (linha RF15). Este plano executa o último item pendente do "Plano derivado" de §5: *"Consumo do cursor pelo app ACS (fila)..."* — a metade backend + contrato do dispositivo já está feita; só falta a tela.

## Global Constraints

- Todo texto voltado ao ACS é em português (padrão do repositório para UI/copy).
- Nenhum dado de paciente real em teste, log ou copy — usar sempre os UUIDs sintéticos de `test/support/fakes.dart` (`seedPatientId` etc.).
- `VisitPullService` **nunca** escreve na `OfflineVisitQueue`/`VisitStore` — só lê dela para dedupe (ver `apps/acs/lib/core/services/visit_pull_service.dart:14-24`). Nenhuma mudança deste plano pode violar isso: a UI só exibe `lastPulled`, nunca grava essas entradas como visitas locais.
- O cursor é por dispositivo, não por usuário (decisão §5.4) — já implementado em `SyncCursorStore`; este plano não o modifica, só o consome.
- Falha de rede/sessão ao sincronizar não pode travar nenhuma tela — sempre captura, mostra aviso, permite tentar de novo (mesmo padrão de `_connectFeed`/`_loadPatients` já usado em `apps/acs/lib/app/app.dart`).
- Cor é sinal clínico só nos alertas (`red`/`accent`/`green`); o aviso de sincronização usa o mesmo padrão neutro/azul de `_InfraBanner`, já usado para os avisos de broker e armazenamento — não vermelho.

---

## File Structure

- **Create** `apps/acs/lib/core/services/visit_pull_service_factory.dart` — monta o `VisitPullService` de produção, análogo a `visit_queue_factory.dart`; recebe o `VisitStore` compartilhado com a fila em vez de criar o seu próprio, para que o dedupe por `localId` veja exatamente o que está gravado no aparelho.
- **Modify** `apps/acs/lib/app/app.dart` — encaminha um `VisitPullService` por `SinalAcsApp` → `LoginScreen` → `AcsHomeShell` (mesmo padrão já usado para `visitQueue`); `AcsHomeShell` dispara `pullAndMerge()` na abertura do painel e guarda o resultado em estado; `TerritorializationScreen` deixa de ser `const`/estática nesse bloco e passa a mostrar o resultado real, com um botão para repetir manualmente.
- **Create** `apps/acs/test/visit_pull_service_factory_test.dart` — prova que a fábrica de produção usa o cursor e o `VisitStore` recebidos, não um substituto interno.
- **Modify** `apps/acs/test/login_flow_test.dart` — novo grupo `sincronização central→dispositivo (RF15)` cobrindo: pull automático ao abrir o painel, erro não trava a tela, botão manual repete a chamada, e entradas já presentes na fila local não contam como novidade.
- Nenhuma mudança em `backend/` — a metade servidor de RF15 (`visits.pull`, territorializado e testado) já existe e não muda.

---

### Task 1: Fábrica de produção do `VisitPullService`, compartilhando o `VisitStore` da fila

**Files:**
- Create: `apps/acs/lib/core/services/visit_pull_service_factory.dart`
- Test: `apps/acs/test/visit_pull_service_factory_test.dart`

**Interfaces:**
- Consumes: `VisitPullService` (`apps/acs/lib/core/services/visit_pull_service.dart`, construtor `VisitPullService({required AcsBackend backend, required SyncCursorStore cursorStore, required VisitStore localVisits})`), `SyncCursorStore` (`apps/acs/lib/core/database/sync_cursor_store.dart`), `SecureStorageDatabaseKeyStore` (`apps/acs/lib/core/security/database_key_store.dart`), `AcsBackend`/`VisitStore` (tipos já existentes).
- Produces: `VisitPullService buildVisitPullService({required AcsBackend backend, required VisitStore localVisits, SyncCursorStore? cursorStore})` — usado pela Task 2 em `app.dart`. `cursorStore` é um parâmetro de teste (produção nunca o passa).

- [ ] **Step 1: Escrever o teste que falha**

  Create `apps/acs/test/visit_pull_service_factory_test.dart`:

  ```dart
  import 'package:flutter_test/flutter_test.dart';
  import 'package:sinalacs_acs/core/database/encrypted_database.dart';
  import 'package:sinalacs_acs/core/database/sync_cursor_store.dart';
  import 'package:sinalacs_acs/core/security/database_key_store.dart';
  import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';
  import 'package:sinalacs_acs/core/services/visit_pull_service_factory.dart';
  import 'package:sinalacs_client/sinalacs_client.dart';

  import 'support/fakes.dart';

  void main() {
    TestWidgetsFlutterBinding.ensureInitialized();

    const dbName = 'visit_pull_service_factory_test.db';

    setUp(() => EncryptedLocalDatabase.deleteDatabaseFile(dbName));
    tearDown(() => EncryptedLocalDatabase.deleteDatabaseFile(dbName));

    test(
      'monta um VisitPullService que usa o cursor e o VisitStore recebidos, não substitutos internos',
      () async {
        final backend = FakeAcsBackend()
          ..pullEntries = [
            VisitSyncEntry(
              localId: 'ja-na-fila',
              patientId: seedPatientId,
              scheduledAt: DateTime.utc(2026, 9, 12, 9),
              status: 'realizada',
              riskLevelBefore: RiskLevel.green,
              notes: const {},
              version: 1,
              syncAt: DateTime.utc(2026, 9, 12, 10),
              arrivalMethod: ArrivalMethod.manual,
            ),
          ];
        final cursorStore = SyncCursorStore(
          keyStore: InMemoryDatabaseKeyStore(),
          databaseName: dbName,
          allowUnencryptedForTesting: true,
        );
        final localVisits = InMemoryVisitStore();
        // Já na fila offline local: é a mesma entrada que `pullEntries` devolve,
        // pelo mesmo `localId` — prova que o serviço deduplica pelo VisitStore
        // QUE FOI PASSADO, não por um interno construído à parte.
        await localVisits.save([
          OfflineVisitRecord(
            localId: 'ja-na-fila',
            patientId: seedPatientId,
            risk: 'green',
            status: 'PENDENTE',
          ),
        ]);

        final service = buildVisitPullService(
          backend: backend,
          localVisits: localVisits,
          cursorStore: cursorStore,
        );
        await service.pullAndMerge();

        // O cursor avançou no MESMO SyncCursorStore passado.
        expect(await cursorStore.read(), DateTime.utc(2026, 9, 12, 10));
        // Dedupe pelo MESMO VisitStore passado: a entrada já presente não conta
        // como novidade.
        expect(service.lastPulled, isEmpty);
      },
    );
  }
  ```

- [ ] **Step 2: Rodar e confirmar que falha**

  Run: `cd apps/acs && flutter test test/visit_pull_service_factory_test.dart`
  Expected: FAIL — `visit_pull_service_factory.dart` não existe (`Target of URI doesn't exist`).

- [ ] **Step 3: Implementar a fábrica**

  Create `apps/acs/lib/core/services/visit_pull_service_factory.dart`:

  ```dart
  import 'package:sinalacs_acs/core/database/sync_cursor_store.dart';
  import 'package:sinalacs_acs/core/network/backend_client.dart';
  import 'package:sinalacs_acs/core/security/database_key_store.dart';
  import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';
  import 'package:sinalacs_acs/core/services/visit_pull_service.dart';

  /// Monta o serviço de pull central→dispositivo (RF15, decisão §5) como ele
  /// roda em produção.
  ///
  /// [localVisits] deve ser o MESMO `VisitStore` que respalda a
  /// `OfflineVisitQueue` do app: é o que `VisitPullService` usa para nunca
  /// reintroduzir localmente uma visita que já está na fila offline (ver a
  /// documentação da própria classe). Passar um store diferente perde essa
  /// garantia sem lançar nenhum erro visível.
  ///
  /// [cursorStore] existe só para o teste poder inspecionar o cursor gravado;
  /// em produção a chamada não passa nada e usa o padrão, respaldado pelo
  /// Keystore/Keychain do aparelho.
  VisitPullService buildVisitPullService({
    required AcsBackend backend,
    required VisitStore localVisits,
    SyncCursorStore? cursorStore,
  }) =>
      VisitPullService(
        backend: backend,
        cursorStore: cursorStore ??
            SyncCursorStore(keyStore: SecureStorageDatabaseKeyStore()),
        localVisits: localVisits,
      );
  ```

- [ ] **Step 4: Rodar e confirmar que passa**

  Run: `cd apps/acs && flutter test test/visit_pull_service_factory_test.dart`
  Expected: PASS.

- [ ] **Step 5: Commit**

  ```bash
  git add apps/acs/lib/core/services/visit_pull_service_factory.dart apps/acs/test/visit_pull_service_factory_test.dart
  git commit -m "feat(acs): fábrica de produção do VisitPullService compartilhando o VisitStore da fila (RF15)"
  ```

---

### Task 2: `AcsHomeShell` dispara o pull e a tela "Área" mostra o resultado

**Files:**
- Modify: `apps/acs/lib/app/app.dart`
- Test: `apps/acs/test/login_flow_test.dart`

**Interfaces:**
- Consumes: `buildVisitPullService` (Task 1), `VisitPullService.pullAndMerge()` / `VisitPullService.lastPulled` (`apps/acs/lib/core/services/visit_pull_service.dart`), `BackendFailure` (`apps/acs/lib/core/network/backend_client.dart`), `InfraNotice` (typedef já existente em `app.dart:189`), `_InfraBanner` (classe privada já existente em `app.dart`, usada por `DashboardScreen`).
- Produces: `TerritorializationScreen({bool pulling, int? lastPulledCount, DateTime? lastPulledAt, InfraNotice? pullError, VoidCallback? onRefresh})` — usada só dentro de `app.dart`, sem consumidor externo.

#### Passo a passo

- [ ] **Step 1: Escrever os testes que falham**

  Em `apps/acs/test/login_flow_test.dart`, ajustar o `show` do import de `sinalacs_client` (linha 12-13) de:

  ```dart
  import 'package:sinalacs_client/sinalacs_client.dart'
      show MicroAreaPatient, SyncStatus, VisitSyncResult;
  ```

  para:

  ```dart
  import 'package:sinalacs_client/sinalacs_client.dart'
      show ArrivalMethod, MicroAreaPatient, RiskLevel, SyncStatus, VisitSyncEntry, VisitSyncResult;
  ```

  e adicionar, logo abaixo dos imports existentes:

  ```dart
  import 'package:sinalacs_acs/core/database/encrypted_database.dart';
  import 'package:sinalacs_acs/core/database/sync_cursor_store.dart';
  import 'package:sinalacs_acs/core/security/database_key_store.dart';
  import 'package:sinalacs_acs/core/services/visit_pull_service.dart';
  ```

  Adicionar um novo `group`, ao final do `main()` (depois do `group('fiação de produção', ...)`, antes do `}` que fecha `main`):

  ```dart
  group('sincronização central→dispositivo (RF15)', () {
    const dbName = 'login_flow_test_visit_pull.db';

    setUp(() => EncryptedLocalDatabase.deleteDatabaseFile(dbName));
    tearDown(() => EncryptedLocalDatabase.deleteDatabaseFile(dbName));

    VisitPullService pullService(FakeAcsBackend backend, {VisitStore? localVisits}) =>
        VisitPullService(
          backend: backend,
          cursorStore: SyncCursorStore(
            keyStore: InMemoryDatabaseKeyStore(),
            databaseName: dbName,
            allowUnencryptedForTesting: true,
          ),
          localVisits: localVisits ?? InMemoryVisitStore(),
        );

    VisitSyncEntry visitaRemota(String localId) => VisitSyncEntry(
          localId: localId,
          patientId: seedPatientId,
          scheduledAt: DateTime.utc(2026, 9, 12, 9),
          status: 'realizada',
          riskLevelBefore: RiskLevel.green,
          notes: const {},
          version: 1,
          syncAt: DateTime.utc(2026, 9, 12, 10),
          arrivalMethod: ArrivalMethod.manual,
        );

    testWidgets('ao abrir o painel, a aba Área mostra as visitas recebidas da central', (tester) async {
      final backend = FakeAcsBackend()
        ..pullEntries = [visitaRemota('remota-1'), visitaRemota('remota-2')];

      await tester.pumpWidget(SinalAcsApp(
        backend: backend,
        feedBuilder: (queue) => FakeAlertFeed(queue),
        visitPullService: pullService(backend),
      ));
      await tester.tap(find.byKey(const Key('login_button')));
      await tester.pumpAndSettle();

      expect(backend.pullSinceCalls, hasLength(1));

      await tester.tap(find.text('Área'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pull_status')), findsOneWidget);
      expect(find.textContaining('2 atualizações recebidas da central'), findsOneWidget);
    });

    testWidgets('uma falha ao sincronizar mostra o aviso, sem travar a tela', (tester) async {
      final backend = FakeAcsBackend()
        ..pullFailure = const BackendFailure('Sem conexão com o servidor.');

      await tester.pumpWidget(SinalAcsApp(
        backend: backend,
        feedBuilder: (queue) => FakeAlertFeed(queue),
        visitPullService: pullService(backend),
      ));
      await tester.tap(find.byKey(const Key('login_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Área'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pull_error')), findsOneWidget);
      expect(find.text('Sem conexão com o servidor.'), findsOneWidget);
      // O botão continua ativo: a falha não pode travar a única forma de
      // tentar de novo.
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('pull_visits'))).onPressed,
        isNotNull,
      );
    });

    testWidgets('"Atualizar dados da microárea" repete a sincronização manualmente', (tester) async {
      final backend = FakeAcsBackend()..pullEntries = [visitaRemota('remota-1')];

      await tester.pumpWidget(SinalAcsApp(
        backend: backend,
        feedBuilder: (queue) => FakeAlertFeed(queue),
        visitPullService: pullService(backend),
      ));
      await tester.tap(find.byKey(const Key('login_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Área'));
      await tester.pumpAndSettle();

      expect(backend.pullSinceCalls, hasLength(1));

      await tester.tap(find.byKey(const Key('pull_visits')));
      await tester.pumpAndSettle();

      expect(backend.pullSinceCalls, hasLength(2));
    });

    testWidgets('entradas já presentes na fila offline local não contam como novidade', (tester) async {
      final localVisits = InMemoryVisitStore();
      await localVisits.save([
        OfflineVisitRecord(localId: 'ja-existe', patientId: seedPatientId, risk: 'green', status: 'PENDENTE'),
      ]);
      final backend = FakeAcsBackend()
        ..pullEntries = [visitaRemota('ja-existe'), visitaRemota('nova')];

      await tester.pumpWidget(SinalAcsApp(
        backend: backend,
        feedBuilder: (queue) => FakeAlertFeed(queue),
        visitPullService: pullService(backend, localVisits: localVisits),
      ));
      await tester.tap(find.byKey(const Key('login_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Área'));
      await tester.pumpAndSettle();

      expect(find.textContaining('1 atualização recebida da central'), findsOneWidget);
    });
  });
  ```

- [ ] **Step 2: Rodar e confirmar que falha**

  Run: `cd apps/acs && flutter test test/login_flow_test.dart`
  Expected: FAIL — `SinalAcsApp` não tem parâmetro nomeado `visitPullService` (erro de compilação).

- [ ] **Step 3: Adicionar os imports novos em `app.dart`**

  Em `apps/acs/lib/app/app.dart`, substituir o bloco de imports (linhas 1-17):

  ```dart
  import 'dart:async';
  import 'dart:developer' as developer;

  import 'package:flutter/material.dart';
  import 'package:geolocator/geolocator.dart';
  import 'package:google_maps_flutter/google_maps_flutter.dart';
  import 'package:sinalacs_acs/app/acs_theme.dart';
  import 'package:sinalacs_acs/core/geo/location_cell.dart';
  import 'package:sinalacs_acs/core/network/backend_client.dart';
  import 'package:sinalacs_acs/core/network/backend_scope.dart';
  import 'package:sinalacs_acs/core/services/alert_feed.dart';
  import 'package:sinalacs_acs/core/services/alert_queue.dart';
  import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';
  import 'package:sinalacs_client/sinalacs_client.dart' show MicroAreaPatient;
  import 'package:sinalacs_acs/core/services/reconnect_schedule.dart';
  import 'package:sinalacs_acs/core/services/route_service.dart';
  import 'package:sinalacs_acs/core/services/visit_queue_factory.dart';
  ```

  por:

  ```dart
  import 'dart:async';
  import 'dart:developer' as developer;

  import 'package:flutter/material.dart';
  import 'package:geolocator/geolocator.dart';
  import 'package:google_maps_flutter/google_maps_flutter.dart';
  import 'package:sinalacs_acs/app/acs_theme.dart';
  import 'package:sinalacs_acs/core/database/sqlcipher_visit_store.dart';
  import 'package:sinalacs_acs/core/geo/location_cell.dart';
  import 'package:sinalacs_acs/core/network/backend_client.dart';
  import 'package:sinalacs_acs/core/network/backend_scope.dart';
  import 'package:sinalacs_acs/core/security/database_key_store.dart';
  import 'package:sinalacs_acs/core/services/alert_feed.dart';
  import 'package:sinalacs_acs/core/services/alert_queue.dart';
  import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';
  import 'package:sinalacs_client/sinalacs_client.dart' show MicroAreaPatient;
  import 'package:sinalacs_acs/core/services/reconnect_schedule.dart';
  import 'package:sinalacs_acs/core/services/route_service.dart';
  import 'package:sinalacs_acs/core/services/visit_pull_service.dart';
  import 'package:sinalacs_acs/core/services/visit_pull_service_factory.dart';
  import 'package:sinalacs_acs/core/services/visit_queue_factory.dart';
  ```

- [ ] **Step 4: `SinalAcsApp` ganha o parâmetro `visitPullService`**

  Substituir:

  ```dart
  class SinalAcsApp extends StatefulWidget {
    const SinalAcsApp({
      super.key,
      this.backend,
      this.feedBuilder,
      this.visitQueue,
      this.initialAlert,
      this.currentPosition,
    });

    /// Injetáveis para teste. Em execução normal são as implementações reais.
    final AcsBackend? backend;
    final AlertFeed Function(AlertQueue queue)? feedBuilder;
    final OfflineVisitQueue? visitQueue;
    final PrioritizedAlert? initialAlert;
    final LatLng? currentPosition;

    @override
    State<SinalAcsApp> createState() => _SinalAcsAppState();
  }
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
    });

    /// Injetáveis para teste. Em execução normal são as implementações reais.
    final AcsBackend? backend;
    final AlertFeed Function(AlertQueue queue)? feedBuilder;
    final OfflineVisitQueue? visitQueue;
    final VisitPullService? visitPullService;
    final PrioritizedAlert? initialAlert;
    final LatLng? currentPosition;

    @override
    State<SinalAcsApp> createState() => _SinalAcsAppState();
  }
  ```

- [ ] **Step 5: `_SinalAcsAppState` compartilha o `VisitStore` entre fila e pull**

  Substituir:

  ```dart
  class _SinalAcsAppState extends State<SinalAcsApp> {
    late final AcsBackend _backend = widget.backend ?? BackendClient();

    /// Uma única fila por execução do app.
    ///
    /// A tela de visita antes fazia `OfflineVisitQueue()` a cada gravação — uma
    /// instância nova por visita, descartada no retorno do callback. A visita
    /// simplesmente sumia.
    late final OfflineVisitQueue _visitQueue = widget.visitQueue ?? _persistentQueue();

    /// Fila respaldada pelo banco criptografado, com o sincronizador ligado.
    ///
    /// A chave vive no Keystore/Keychain, nunca no código. Deixou de ser `static`
    /// para enxergar [_backend]: sem sincronizador, `sync()` caía no ramo sem
    /// remetente e devolvia erro — as visitas nunca subiam ao servidor e o que já
    /// estava confirmado nunca era apagado do disco.
    OfflineVisitQueue _persistentQueue() => buildVisitQueue(backend: _backend);
  ```

  por:

  ```dart
  class _SinalAcsAppState extends State<SinalAcsApp> {
    late final AcsBackend _backend = widget.backend ?? BackendClient();

    /// Compartilhado entre a fila offline e o serviço de pull (RF15).
    ///
    /// `VisitPullService` lê deste MESMO store para nunca reintroduzir
    /// localmente uma visita que já está na fila offline (dedupe por
    /// `localId`, ver `visit_pull_service.dart`). Duas instâncias separadas de
    /// `SqlCipherVisitStore` apontando para o mesmo arquivo até funcionariam,
    /// mas por acaso — uma só instância é o que garante que o pull enxerga
    /// exatamente o que a fila gravou por último.
    late final VisitStore _visitStore = SqlCipherVisitStore(keyStore: SecureStorageDatabaseKeyStore());

    /// Uma única fila por execução do app.
    ///
    /// A tela de visita antes fazia `OfflineVisitQueue()` a cada gravação — uma
    /// instância nova por visita, descartada no retorno do callback. A visita
    /// simplesmente sumia.
    late final OfflineVisitQueue _visitQueue = widget.visitQueue ?? _persistentQueue();

    /// Fila respaldada pelo banco criptografado, com o sincronizador ligado.
    ///
    /// A chave vive no Keystore/Keychain, nunca no código. Deixou de ser `static`
    /// para enxergar [_backend]: sem sincronizador, `sync()` caía no ramo sem
    /// remetente e devolvia erro — as visitas nunca subiam ao servidor e o que já
    /// estava confirmado nunca era apagado do disco.
    OfflineVisitQueue _persistentQueue() => buildVisitQueue(backend: _backend, store: _visitStore);

    /// Serviço de pull central→dispositivo (RF15, decisão §5).
    ///
    /// Usa o MESMO `_visitStore` da fila — ver o comentário acima.
    late final VisitPullService _visitPullService =
        widget.visitPullService ?? buildVisitPullService(backend: _backend, localVisits: _visitStore);
  ```

- [ ] **Step 6: `build()` encaminha `_visitPullService` para `LoginScreen`**

  Substituir:

  ```dart
          home: LoginScreen(
            feedBuilder: widget.feedBuilder,
            visitQueue: _visitQueue,
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
          ),
  ```

- [ ] **Step 7: `LoginScreen` encaminha para `AcsHomeShell`**

  Substituir:

  ```dart
  class LoginScreen extends StatefulWidget {
    const LoginScreen({
      required this.visitQueue,
      super.key,
      this.feedBuilder,
      this.initialAlert,
      this.initialPosition,
    });

    final AlertFeed Function(AlertQueue queue)? feedBuilder;
    final OfflineVisitQueue visitQueue;
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
    });

    final AlertFeed Function(AlertQueue queue)? feedBuilder;
    final OfflineVisitQueue visitQueue;
    final VisitPullService visitPullService;
    final PrioritizedAlert? initialAlert;
    final LatLng? initialPosition;
  ```

  E, no método `_enter()`, substituir:

  ```dart
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => AcsHomeShell(
            microAreaId: microAreaId,
            acsId: session.userId,
            feedBuilder: widget.feedBuilder,
            visitQueue: widget.visitQueue,
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
          ),
        ));
  ```

- [ ] **Step 8: `AcsHomeShell` ganha o campo `visitPullService`**

  Substituir:

  ```dart
  class AcsHomeShell extends StatefulWidget {
    const AcsHomeShell({
      required this.microAreaId,
      required this.acsId,
      required this.visitQueue,
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

    /// Obrigatória: a tela de visita usava `widget.visitQueue ?? OfflineVisitQueue()`,
    /// e um dia em que o shell fosse construído sem fila voltaria a descartar a
    /// visita em silêncio.
    final OfflineVisitQueue visitQueue;

    @override
    State<AcsHomeShell> createState() => _AcsHomeShellState();
  }
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
    });

    final String microAreaId;
    final String acsId;
    final AlertFeed Function(AlertQueue queue)? feedBuilder;
    final PrioritizedAlert? initialAlert;
    final LatLng? initialPosition;

    /// Obrigatória: a tela de visita usava `widget.visitQueue ?? OfflineVisitQueue()`,
    /// e um dia em que o shell fosse construído sem fila voltaria a descartar a
    /// visita em silêncio.
    final OfflineVisitQueue visitQueue;

    /// Serviço de pull central→dispositivo (RF15). Obrigatório pelo mesmo
    /// motivo de [visitQueue]: construir um substituto aqui dentro, silencioso,
    /// já foi o defeito de outra fila neste mesmo arquivo.
    final VisitPullService visitPullService;

    @override
    State<AcsHomeShell> createState() => _AcsHomeShellState();
  }
  ```

- [ ] **Step 9: `_AcsHomeShellState` dispara o pull e guarda o resultado**

  Adicionar campos de estado logo após a declaração de `_reconnectDelay` (depois da linha `final ReconnectSchedule _reconnectDelay = ReconnectSchedule();`):

  ```dart
    /// `true` enquanto uma chamada a `visits.pull` está em andamento.
    bool _pullingVisits = false;

    /// Quantas entradas a última sincronização bem-sucedida trouxe que ainda
    /// não estavam na fila offline local. `null` antes da primeira tentativa
    /// desta sessão.
    int? _lastPulledCount;

    /// Quando a última sincronização bem-sucedida terminou. `null` antes da
    /// primeira tentativa desta sessão.
    DateTime? _lastPulledAt;

    /// Presente quando a última tentativa falhou. Não trava a tela: sem
    /// confirmação do servidor, o cursor local não avança
    /// (`VisitPullService.pullAndMerge`), então tentar de novo reconsulta o
    /// mesmo ponto sem risco de perder nada.
    InfraNotice? _pullError;
  ```

  No `initState()`, substituir:

  ```dart
      _feed.onConnectionChanged = _onBrokerConnectionChanged;
      _connectFeed();
      _restoreVisits();
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
    }
  ```

  Adicionar o método `_pullVisits`, logo após `_restoreVisits`:

  ```dart
    /// Sincronização central→dispositivo (RF15, decisão §5): busca no servidor
    /// as visitas da microárea alteradas desde o cursor deste aparelho.
    ///
    /// Só leitura, de propósito — `VisitPullService` nunca escreve na
    /// [OfflineVisitQueue] (ver a documentação da própria classe). O que muda
    /// aqui é só o que a tela "Área" mostra sobre o resultado, nunca a fila de
    /// visitas pendentes.
    ///
    /// Disparado automaticamente ao abrir o painel, mais um botão manual na
    /// própria tela — não um timer de sincronização em segundo plano, decisão
    /// de produto separada e fora do escopo desta task.
    Future<void> _pullVisits() async {
      setState(() { _pullingVisits = true; _pullError = null; });

      try {
        await widget.visitPullService.pullAndMerge();
        if (!mounted) return;
        setState(() {
          _lastPulledCount = widget.visitPullService.lastPulled.length;
          _lastPulledAt = DateTime.now();
        });
      } on BackendFailure catch (failure) {
        if (!mounted) return;
        setState(() {
          _pullError = (
            title: 'Não foi possível sincronizar com a central.',
            detail: failure.message,
          );
        });
      } catch (error, stackTrace) {
        developer.log(
          'falha não classificada ao sincronizar visitas da central',
          name: 'sinalacs.acs.visit_pull',
          error: error,
          stackTrace: stackTrace,
        );
        if (!mounted) return;
        setState(() {
          _pullError = (
            title: 'Não foi possível sincronizar com a central.',
            detail: 'Verifique a conexão e tente de novo.',
          );
        });
      } finally {
        if (mounted) setState(() => _pullingVisits = false);
      }
    }
  ```

- [ ] **Step 10: `build()` passa o estado do pull para `TerritorializationScreen`**

  Substituir, dentro do `switch (destination)`:

  ```dart
        AcsDestination.area => const TerritorializationScreen(),
  ```

  por:

  ```dart
        AcsDestination.area => TerritorializationScreen(
            pulling: _pullingVisits,
            lastPulledCount: _lastPulledCount,
            lastPulledAt: _lastPulledAt,
            pullError: _pullError,
            onRefresh: _pullVisits,
          ),
  ```

- [ ] **Step 11: Reescrever `TerritorializationScreen`**

  Substituir a classe inteira (hoje uma única linha):

  ```dart
  class TerritorializationScreen extends StatelessWidget { const TerritorializationScreen({super.key}); @override Widget build(BuildContext context) => _page([const Text('Microárea 12 - Zona Rural', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), const SizedBox(height: 12), const _InfoRow('Pacientes sincronizados', '142 cadastrados'), const _InfoRow('Cache local', 'Atualizado há 10 min'), const SizedBox(height: 20), FilledButton(onPressed: () => _message(context, 'Atualização será integrada à API central.'), child: const Text('Atualizar dados da microárea'))]); }
  ```

  por:

  ```dart
  /// Painel territorial da microárea, incluindo o status da sincronização
  /// central→dispositivo (RF15, decisão §5).
  ///
  /// "Pacientes sincronizados" e "Cache local" continuam literais fixos — é o
  /// débito técnico L-06 (RF08), fora do escopo desta task: aqui só o bloco de
  /// sincronização abaixo reflete dado real, vindo do `VisitPullService` via
  /// [AcsHomeShell._pullVisits].
  class TerritorializationScreen extends StatelessWidget {
    const TerritorializationScreen({
      super.key,
      this.pulling = false,
      this.lastPulledCount,
      this.lastPulledAt,
      this.pullError,
      this.onRefresh,
    });

    /// `true` enquanto uma chamada a `visits.pull` está em andamento.
    final bool pulling;

    /// Quantas entradas a última sincronização bem-sucedida trouxe que ainda
    /// não estavam na fila offline local. `null` antes da primeira tentativa
    /// desta sessão.
    final int? lastPulledCount;

    /// Quando a última sincronização bem-sucedida terminou. `null` antes da
    /// primeira tentativa desta sessão.
    final DateTime? lastPulledAt;

    /// Presente quando a última tentativa falhou.
    final InfraNotice? pullError;

    final VoidCallback? onRefresh;

    @override
    Widget build(BuildContext context) => _page([
          const Text('Microárea 12 - Zona Rural', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          const _InfoRow('Pacientes sincronizados', '142 cadastrados'),
          const _InfoRow('Cache local', 'Atualizado há 10 min'),
          const Divider(height: 32),
          const Text('Sincronização com a central', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (pullError != null)
            _InfraBanner(key: const Key('pull_error'), icon: Icons.sync_problem_outlined, notice: pullError!)
          else
            Text(key: const Key('pull_status'), _pullStatusText()),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('pull_visits'),
            onPressed: pulling ? null : onRefresh,
            child: pulling
                ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Atualizar dados da microárea'),
          ),
        ]);

    String _pullStatusText() {
      final at = lastPulledAt;
      if (at == null) return 'Ainda não sincronizado nesta sessão.';

      final novidade = switch (lastPulledCount ?? 0) {
        0 => 'Nenhuma novidade da central',
        1 => '1 atualização recebida da central',
        final count => '$count atualizações recebidas da central',
      };
      return '$novidade • ${_time(at)}';
    }

    String _time(DateTime value) {
      final local = value.toLocal();
      return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }
  }
  ```

- [ ] **Step 12: Rodar o teste novo e confirmar que passa**

  Run: `cd apps/acs && flutter test test/login_flow_test.dart`
  Expected: PASS (inclui o novo grupo `sincronização central→dispositivo (RF15)`).

- [ ] **Step 13: Rodar a suíte inteira do app ACS**

  Run: `cd apps/acs && flutter analyze && flutter test`
  Expected: PASS — nenhum teste pré-existente deve quebrar. Os testes que constroem `SinalAcsApp`/`AcsHomeShell` sem passar `visitPullService` continuam válidos: o fallback de produção (`SqlCipherVisitStore` + `SecureStorageDatabaseKeyStore`) falha graciosamente fora de Android/iOS (mesmo comportamento que `OfflineVisitQueue.restore()` já tolera hoje para a fila, quando nenhum `store` de teste é passado) e é capturado pelo `catch` de `_pullVisits`, sem travar nada.

- [ ] **Step 14: Commit**

  ```bash
  git add apps/acs/lib/app/app.dart apps/acs/test/login_flow_test.dart
  git commit -m "feat(acs): consumir o pull de visitas na tela Área (RF15, fecha o item deixado em aberto na Task 10)"
  ```

---

### Task 3: Atualizar a documentação de estado (RF15 deixa de estar sem consumidor)

**Files:**
- Modify: `spec/validation_report.md`
- Modify: `spec/PRD_system.md`
- Modify: `docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md`

**Interfaces:** Nenhuma — só texto.

- [ ] **Step 1: Atualizar a linha RF15 em `spec/validation_report.md`**

  Localizar a linha (tabela de requisitos funcionais):

  ```
  | RF15 | Sincronização bidirecional | **parcial** | Dispositivo → central funciona e é testado. O sentido central → dispositivo **não existe**: não há endpoint de leitura de visitas/alertas. |
  ```

  Substituir por:

  ```
  | RF15 | Sincronização bidirecional | **parcial** | Dispositivo → central e central → dispositivo (`visits.pull`, cursor por dispositivo) funcionam e são testados, incluindo a tela do ACS que consome o pull. Falta só o lado do paciente (RF05, `alerts.statusFor`) — ver §5 de `docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md`. |
  ```

  (Esta linha é a única mudança neste arquivo — o veredicto continua **parcial**, porque o lado paciente/RF05 ainda não existe; muda só a evidência.)

- [ ] **Step 2: Marcar o item concluído em `docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md`**

  Na seção `## 5. Sincronização central → dispositivo (RF15, metade ausente)`, subseção `### Plano derivado (não executado nesta tarefa)`, localizar:

  ```
  - Consumo do cursor pelo app ACS (fila) e app paciente (status), com teste de
    device reinstalado sem duplicar nem perder itens.
  ```

  Substituir por:

  ```
  - ~~Consumo do cursor pelo app ACS (fila)~~ — feito: `VisitPullService` (Task
    10 do plano de implementação) mais a tela "Área" que o aciona e mostra o
    resultado (`docs/superpowers/plans/2026-09-18-rf15-consumo-acs-pull-visitas.md`).
    Falta ainda o consumo pelo app paciente (status) — mesma garantia de
    device reinstalado sem duplicar nem perder itens já vale para o ACS
    (coberta em `apps/acs/test/visit_pull_service_test.dart` e
    `apps/acs/test/sync_cursor_store_test.dart`); falta provar o equivalente
    do lado paciente quando esse trabalho for feito.
  ```

- [ ] **Step 3: Nota em `spec/PRD_system.md`**

  Na tabela da seção "2.2.1 Decisões de produto pós-validação", localizar a linha:

  ```
  | RF15 (sync central→dispositivo) | Pull incremental por cursor (§5) | Não |
  ```

  Deixar como está (a decisão em si não mudou) — mas, logo abaixo da tabela, no parágrafo "Cada linha é um plano independente...", adicionar ao final:

  ```
  RF15 teve sua metade ACS (contrato + tela consumidora) implementada em
  `docs/superpowers/plans/2026-09-17-decisoes-produto-pos-validacao-implementacao.md`
  (Task 10) e `docs/superpowers/plans/2026-09-18-rf15-consumo-acs-pull-visitas.md`;
  a metade paciente (RF05) segue pendente.
  ```

- [ ] **Step 4: Commit**

  ```bash
  git add spec/validation_report.md spec/PRD_system.md docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md
  git commit -m "docs: registrar que RF15 (ACS) tem consumidor real, RF05 (paciente) segue pendente"
  ```

---

## Escopo explicitamente fora deste plano

- **Sincronização periódica em segundo plano** (timer/`WorkManager`/background fetch): este plano dispara o pull ao abrir o painel e por botão manual, não em intervalo — decisão de produto separada, não pedida pelo item original.
- **App paciente (RF05, `alerts.statusFor`)**: é a outra metade de RF15 no documento de decisão §5, mas é um plano independente (endpoint novo no backend + tela de Status deixar de ser `const`), não um ajuste ao consumidor do ACS.
- **L-06 / RF08** (literais "Microárea 12 - Zona Rural", "142 cadastrados", "Cache local: Atualizado há 10 min"): débito técnico pré-existente e documentado à parte; misturar a correção aqui inflaria o diff sem relação com RF15.
- **Marcar visitas puxadas como "já visitada por outro ACS" na fila/mapa**: exigiria estender `OfflineVisitQueue`/`AlertQueue` com um conceito de "visita de referência, só leitura" que hoje não existe — é exatamente o "próxima iteração" citado na documentação de `VisitPullService`, não este item.
