import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/app/app.dart';
import 'package:sinalacs_acs/core/database/encrypted_database.dart';
import 'package:sinalacs_acs/core/database/sqlcipher_visit_store.dart';
import 'package:sinalacs_acs/core/database/sync_cursor_store.dart';
import 'package:sinalacs_acs/core/network/auth_session.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/security/biometric_gate.dart';
import 'package:sinalacs_acs/core/security/database_key_store.dart';
import 'package:sinalacs_acs/core/services/backend_visit_synchronizer.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';
import 'package:sinalacs_acs/core/services/visit_pull_service.dart';
import 'package:sinalacs_acs/core/services/visit_queue_factory.dart';
import 'package:sinalacs_client/sinalacs_client.dart';

import 'support/fakes.dart';
import 'support/layout_harness.dart' show assentar, irParaDaBarra, irParaDoMais;

/// Fila e pull de visitas POR SESSÃO: depois de "Sair" ou do login de outro
/// ACS, as visitas do anterior não aparecem, não sobem, não são atribuídas a
/// outro e não são descartáveis por ele. Ids e pacientes sintéticos.
void main() {
  const acsA = 'acs-a';
  const acsB = 'acs-b';

  OfflineVisitRecord pendente(String localId) =>
      OfflineVisitRecord(localId: localId, patientId: seedPatientId, risk: 'red', status: 'PENDENTE');

  OfflineVisitRecord recusada(String localId) => OfflineVisitRecord(
        localId: localId,
        patientId: seedPatientId,
        risk: 'red',
        status: 'PENDENTE',
        rejectionReason: 'paciente fora da sua microárea',
      );

  AuthSession sessao({required String userId, String microAreaId = seedMicroAreaId}) => AuthSession(
        accessToken: 'token-de-teste',
        tokenType: 'Bearer',
        userId: userId,
        role: 'acs',
        microAreaId: microAreaId,
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 15)),
      );

  group('no app', () {
    late InMemoryVisitStorage storage;
    late FakeAcsBackend backend;
    late FakeBiometricGate gate;
    late GlobalKey<NavigatorState> navKey;

    setUp(() async {
      storage = InMemoryVisitStorage();
      // A: 1 pendente e 1 recusada. B: 2 pendentes e 1 recusada.
      await storage.forOwner(acsA).save([pendente('local-a1'), recusada('local-a2')]);
      await storage.forOwner(acsB).save([pendente('local-b2'), pendente('local-b3'), recusada('local-b1')]);
      backend = FakeAcsBackend()..nextUserId = acsA;
      gate = FakeBiometricGate();
      navKey = GlobalKey<NavigatorState>();
    });

    Future<void> abrirApp(WidgetTester tester, {Duration? lockAfter}) async {
      await tester.pumpWidget(SinalAcsApp(
        backend: backend,
        visitStorage: storage,
        biometricGate: gate,
        navigatorKey: navKey,
        lockAfter: lockAfter,
        feedBuilder: (q) => FakeAlertFeed(q),
      ));
      await assentar(tester);
    }

    Finder painel() => find.text('Painel operacional');
    Finder formulario() => find.byKey(const Key('login_button'));

    Future<void> entrarComo(WidgetTester tester, String userId) async {
      backend.nextUserId = userId;
      await tester.enterText(find.byKey(const Key('matricula_field')), 'ACS-001');
      await tester.enterText(find.byKey(const Key('senha_field')), 'senha-sintetica');
      await tester.ensureVisible(formulario());
      await tester.pump();
      await tester.tap(formulario());
      await assentar(tester);
      expect(painel(), findsOneWidget);
    }

    Future<void> sair(WidgetTester tester) async {
      await irParaDoMais(tester, 'Preferências');
      final botao = find.byKey(const Key('logout_button'));
      await tester.ensureVisible(botao);
      await tester.pump();
      await tester.tap(botao);
      await assentar(tester);
      await tester.tap(find.byKey(const Key('logout_confirm')));
      await assentar(tester);
      expect(formulario(), findsOneWidget);
    }

    Future<void> irEVoltar(WidgetTester tester) async {
      for (final s in const [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused,
          AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
      await assentar(tester);
    }

    /// Abre a aba Visita e devolve o texto do contador de pendentes.
    Future<String> pendentesNaTela(WidgetTester tester) async {
      await irParaDaBarra(tester, 'Visita');
      final contador = find.byKey(const Key('pending_visits_count'));
      await tester.ensureVisible(contador);
      await tester.pump();
      return tester.widget<Text>(contador).data!;
    }

    testWidgets('Sair e entrar com OUTRO ACS: o novo não vê, não envia nem descarta a visita do anterior',
        (tester) async {
      await abrirApp(tester);
      await entrarComo(tester, acsA);
      expect(await pendentesNaTela(tester), 'Pendentes de sincronização: 1');
      expect(find.byKey(const Key('rejected_visits_count')), findsOneWidget);

      await sair(tester);
      await entrarComo(tester, acsB);

      expect(await pendentesNaTela(tester), 'Pendentes de sincronização: 2', reason: 'só as visitas de B');
      expect(tester.widget<Text>(find.byKey(const Key('rejected_visits_count'))).data, contains(': 1'));

      // "Sincronizar agora" de B: nenhum localId de A sai do aparelho.
      final sincronizar = find.byKey(const Key('sync_visits'));
      await tester.ensureVisible(sincronizar);
      await tester.pump();
      await tester.tap(sincronizar);
      await assentar(tester);
      final enviados = [for (final lote in backend.syncedVisitBatches) ...lote.map((e) => e.localId)];
      expect(enviados, unorderedEquals(['local-b2', 'local-b3']));

      // Descartar a recusada de B não toca no armazenamento de A.
      final descartar = find.byKey(const Key('discard_rejected'));
      await tester.ensureVisible(descartar);
      await tester.pump();
      await tester.tap(descartar);
      await assentar(tester);
      await tester.tap(find.text('Descartar'));
      await assentar(tester);

      expect(await storage.forOwner(acsB).load(), isEmpty);
      final deA = await storage.forOwner(acsA).load();
      expect(deA.map((v) => v.localId), unorderedEquals(['local-a1', 'local-a2']));
    });

    testWidgets('o mesmo ACS que sai e volta recupera as próprias visitas', (tester) async {
      await abrirApp(tester);
      await entrarComo(tester, acsA);
      expect(await pendentesNaTela(tester), 'Pendentes de sincronização: 1');
      await sair(tester);

      await entrarComo(tester, acsB);
      expect(await pendentesNaTela(tester), 'Pendentes de sincronização: 2');
      await sair(tester);

      await entrarComo(tester, acsA);
      expect(await pendentesNaTela(tester), 'Pendentes de sincronização: 1');
      expect(find.byKey(const Key('rejected_visits_count')), findsOneWidget);
    });

    testWidgets('reautenticação do MESMO usuário pelo bloqueio preserva o painel e a fila', (tester) async {
      backend.patients = [
        MicroAreaPatient(patientId: syntheticPatientId(5), name: 'Paciente Sintético', isChronic: false, chronicConditions: const []),
      ];
      await abrirApp(tester, lockAfter: Duration.zero);
      await entrarComo(tester, acsA);
      expect(await pendentesNaTela(tester), 'Pendentes de sincronização: 1');
      await tester.ensureVisible(find.byKey(const Key('patient_search')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('patient_search')), 'busca em andamento');
      await tester.pump();

      gate.result = UnlockResult.cancelled;
      await irEVoltar(tester);
      await tester.tap(find.text('Entrar com senha'));
      await assentar(tester);
      await entrarComo(tester, acsA);

      expect(tester.widget<TextField>(find.byKey(const Key('patient_search'))).controller!.text, 'busca em andamento');
      expect(await pendentesNaTela(tester), 'Pendentes de sincronização: 1');
    });

    testWidgets('login de outro usuário pelo bloqueio ("Entrar com senha") também troca a fila', (tester) async {
      await abrirApp(tester, lockAfter: Duration.zero);
      await entrarComo(tester, acsA);
      expect(await pendentesNaTela(tester), 'Pendentes de sincronização: 1');

      gate.result = UnlockResult.cancelled;
      await irEVoltar(tester);
      await tester.tap(find.text('Entrar com senha'));
      await assentar(tester);
      await entrarComo(tester, acsB);

      expect(await pendentesNaTela(tester), 'Pendentes de sincronização: 2');
      expect(navKey.currentState!.canPop(), isFalse, reason: 'o painel de A foi descartado');
    });

    testWidgets('retomada de sessão na partida abre a fila do dono da sessão retomada', (tester) async {
      backend
        ..storedRefreshToken = 'refresh-salvo'
        ..nextUserId = acsB;
      await abrirApp(tester);

      expect(backend.resumeCount, 1);
      expect(painel(), findsOneWidget);
      expect(await pendentesNaTela(tester), 'Pendentes de sincronização: 2');
    });

    testWidgets('fila de A só em RAM (gravação falhando) sobrevive a B entrar e A voltar', (tester) async {
      // A visão de A recusa gravar: a visita registrada existe só na memória.
      final memoria = _GravacaoDeAFalha(storage);
      late FakeAlertFeed feed;
      await tester.pumpWidget(SinalAcsApp(
        backend: backend,
        visitStorage: memoria,
        biometricGate: gate,
        navigatorKey: navKey,
        feedBuilder: (q) => feed = FakeAlertFeed(q),
      ));
      await assentar(tester);
      await storage.forOwner(acsA).save([]);
      await entrarComo(tester, acsA);

      feed.deliver(testAlert(alertId: 'alerta-ram', riskLevel: 'yellow'));
      await assentar(tester);
      await tester.tap(find.text('Iniciar rota de visita'));
      await assentar(tester);
      await tester.tap(find.byKey(const Key('arrival_confirmation')));
      await assentar(tester);
      final salvar = find.byKey(const Key('save_visit'));
      await tester.ensureVisible(salvar);
      await tester.pump();
      await tester.tap(salvar);
      await assentar(tester);
      if (find.byType(BackButton).evaluate().isNotEmpty) {
        await tester.tap(find.byType(BackButton).first);
        await assentar(tester);
      }
      expect(await pendentesNaTela(tester), 'Pendentes de sincronização: 1 (em memória)');
      expect(await storage.forOwner(acsA).load(), isEmpty, reason: 'nada chegou ao disco');
      // O aviso da gravação (SnackBar) cobre o botão de sair até sumir.
      await tester.pump(const Duration(seconds: 10));
      await assentar(tester);

      await sair(tester);
      await entrarComo(tester, acsB);
      await sair(tester);
      await entrarComo(tester, acsA);

      expect(await pendentesNaTela(tester), 'Pendentes de sincronização: 1 (em memória)',
          reason: 'a visita só existia em RAM: a fila de A não pode ser descartada');
    });

    testWidgets('a quarentena (linhas sem dono) não aparece para ninguém', (tester) async {
      storage = InMemoryVisitStorage(legacyVisits: [pendente('local-legado')]);
      await abrirApp(tester);
      await entrarComo(tester, acsA);
      expect(await pendentesNaTela(tester), 'Pendentes de sincronização: 0');
      expect(backend.syncedVisitBatches, isEmpty);
      expect(await storage.legacy.load(), hasLength(1));
    });
  });

  group('no app, com o banco real (SQLCipher sem cifra, FFI)', () {
    const dbName = 'visit_owner_flow_widget_test.db';

    setUp(() => EncryptedLocalDatabase.deleteDatabaseFile(dbName));
    tearDown(() => EncryptedLocalDatabase.deleteDatabaseFile(dbName));

    testWidgets('o pull de cada ACS usa o cursor DELE, no mesmo banco da fila', (tester) async {
      final storage = SqlCipherVisitStorage(
        keyStore: InMemoryDatabaseKeyStore(),
        databaseName: dbName,
        allowUnencryptedForTesting: true,
      );
      final syncAt = DateTime.utc(2026, 10, 3, 10);
      final backend = FakeAcsBackend()
        ..pullEntries = [
          VisitSyncEntry(
            localId: 'remota-1',
            patientId: seedPatientId,
            scheduledAt: DateTime.utc(2026, 10, 3, 9),
            status: 'realizada',
            riskLevelBefore: RiskLevel.green,
            notes: const {},
            version: 1,
            syncAt: syncAt,
            arrivalMethod: ArrivalMethod.manual,
          ),
        ];
      await tester.pumpWidget(SinalAcsApp(
        backend: backend,
        visitStorage: storage,
        feedBuilder: (q) => FakeAlertFeed(q),
      ));
      await assentar(tester);

      Future<void> entrarComo(String userId) async {
        backend.nextUserId = userId;
        await tester.enterText(find.byKey(const Key('matricula_field')), 'ACS-001');
        await tester.enterText(find.byKey(const Key('senha_field')), 'senha-sintetica');
        await tester.ensureVisible(find.byKey(const Key('login_button')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('login_button')));
        await assentar(tester);
        expect(find.text('Painel operacional'), findsOneWidget);
      }

      Future<void> sair() async {
        await irParaDoMais(tester, 'Preferências');
        final botao = find.byKey(const Key('logout_button'));
        await tester.ensureVisible(botao);
        await tester.pump();
        await tester.tap(botao);
        await assentar(tester);
        await tester.tap(find.byKey(const Key('logout_confirm')));
        await assentar(tester);
      }

      await entrarComo(acsA);
      expect(backend.pullSinceCalls, [VisitPullService.epoch], reason: 'primeiro pull de A');
      expect(find.byKey(const Key('pull_error'), skipOffstage: false), findsNothing,
          reason: 'o cursor abriu no banco compartilhado, não num banco à parte pelo Keystore');
      final chaves = await tester.runAsync(() async {
        final db = await storage.database.open();
        return [for (final row in await db.query('sync_cursor')) row['key']! as String];
      });
      expect(chaves, contains('visits_pull|$acsA|$seedMicroAreaId'));

      await sair();
      await entrarComo(acsB);
      expect(backend.pullSinceCalls, [VisitPullService.epoch, VisitPullService.epoch],
          reason: 'B não herda o cursor de A');

      await sair();
      await entrarComo(acsA);
      expect(backend.pullSinceCalls, [VisitPullService.epoch, VisitPullService.epoch, syncAt],
          reason: 'A retoma o PRÓPRIO cursor');

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(storage.close);
    });
  });

  group('sincronizador com dono', () {
    test('BackendVisitSynchronizer recusa enviar com a sessão de outro usuário', () async {
      final backend = FakeAcsBackend()..session = sessao(userId: acsB);
      final sync = BackendVisitSynchronizer(backend: backend, ownerId: acsA);

      await expectLater(
        sync.push([pendente('local-a1')]),
        throwsA(isA<BackendFailure>().having((f) => f.isRecoverable, 'isRecoverable', isTrue)),
      );
      expect(backend.syncedVisitBatches, isEmpty, reason: 'nada saiu');
    });

    test('BackendVisitSynchronizer recusa enviar sem sessão', () async {
      final backend = FakeAcsBackend();
      final sync = BackendVisitSynchronizer(backend: backend, ownerId: acsA);

      await expectLater(sync.push([pendente('local-a1')]), throwsA(isA<BackendFailure>()));
      expect(backend.syncedVisitBatches, isEmpty);
    });

    test('BackendVisitSynchronizer envia com a sessão do próprio dono', () async {
      final backend = FakeAcsBackend()..session = sessao(userId: acsA);
      final sync = BackendVisitSynchronizer(backend: backend, ownerId: acsA);

      final resultado = await sync.push([pendente('local-a1')]);

      expect(resultado.single.status, 'synced');
      expect(backend.syncedVisitBatches.single.single.localId, 'local-a1');
    });

    test('a fila de A em voo, com B logado: o lote de A continua PENDENTE (não é enviado nem perdido)', () async {
      final storage = InMemoryVisitStorage();
      final backend = FakeAcsBackend()..session = sessao(userId: acsA);
      final fila = OfflineVisitQueue(
        store: storage.forOwner(acsA),
        synchronizer: BackendVisitSynchronizer(backend: backend, ownerId: acsA),
      );
      await fila.add(pendente('local-a1'));
      backend.session = sessao(userId: acsB);

      final r = await fila.sync();

      expect(r.kind, SyncOutcomeKind.error);
      expect(fila.pendingCount, 1);
      expect(backend.syncedVisitBatches, isEmpty);
      expect((await storage.forOwner(acsA).load()).single.localId, 'local-a1');
    });

    test('buildVisitQueue liga o sincronizador ao dono pedido', () {
      final queue = buildVisitQueue(backend: FakeAcsBackend(), store: InMemoryVisitStore(), ownerId: acsA);
      expect(queue.synchronizer, isA<BackendVisitSynchronizer>().having((s) => s.ownerId, 'ownerId', acsA));
    });
  });

  group('fiação de produção por dono (um só VisitDatabase)', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const dbName = 'visit_owner_flow_test.db';

    setUp(() => EncryptedLocalDatabase.deleteDatabaseFile(dbName));
    tearDown(() => EncryptedLocalDatabase.deleteDatabaseFile(dbName));

    VisitSyncEntry entrada(String localId, DateTime syncAt) => VisitSyncEntry(
          localId: localId,
          patientId: seedPatientId,
          scheduledAt: DateTime.utc(2026, 10, 3, 9),
          status: 'realizada',
          riskLevelBefore: RiskLevel.green,
          notes: const {},
          version: 1,
          syncAt: syncAt,
          arrivalMethod: ArrivalMethod.manual,
        );

    test('fila e cursor do dono compartilham UM VisitDatabase', () async {
      final storage = SqlCipherVisitStorage(
        keyStore: InMemoryDatabaseKeyStore(),
        databaseName: dbName,
        allowUnencryptedForTesting: true,
      );
      addTearDown(storage.close);
      final syncAt = DateTime.utc(2026, 10, 3, 10);
      final backend = FakeAcsBackend()
        ..session = sessao(userId: acsA)
        ..pullEntries = [entrada('local-a1', syncAt), entrada('de-outro-aparelho', syncAt)];

      final escopo = buildOwnerVisitScope(backend: backend, storage: storage, session: sessao(userId: acsA));
      await escopo.queue.restore();
      await escopo.queue.add(pendente('local-a1'));

      // Sem o banco compartilhado o pull abriria outro banco pelo Keystore
      // (inexistente na VM) e lançaria.
      await escopo.pullService.pullAndMerge();

      expect(escopo.pullService.lastPulled.map((e) => e.localId), ['de-outro-aparelho'],
          reason: 'dedupe pela fila do MESMO dono');
      const cursorOwner = '$acsA|$seedMicroAreaId';
      expect(await SyncCursorStore.on(storage.database, owner: cursorOwner).read(), syncAt);
      final db = await storage.database.open();
      final linhas = await db.query('sync_cursor', where: 'key = ?', whereArgs: ['visits_pull|$cursorOwner']);
      expect(linhas, hasLength(1));
      expect(
        await db.query('offline_visits', where: 'owner = ?', whereArgs: [acsA]),
        hasLength(1),
        reason: 'a visita da fila está no mesmo arquivo do cursor',
      );

      // B, no mesmo aparelho: cursor próprio (epoch) e nenhuma visita de A.
      final backendB = FakeAcsBackend()..session = sessao(userId: acsB);
      final escopoB = buildOwnerVisitScope(backend: backendB, storage: storage, session: sessao(userId: acsB));
      await escopoB.queue.restore();
      expect(escopoB.queue.pendingCount, 0);
      await escopoB.pullService.pullAndMerge();
      expect(backendB.pullSinceCalls, [VisitPullService.epoch]);
    });
  });
}

/// Só a visão de `acs-a` recusa gravar (`persistenceFailed` na fila de A).
class _GravacaoDeAFalha implements VisitStorage {
  _GravacaoDeAFalha(this._inner);

  final VisitStorage _inner;

  @override
  LegacyVisitStore get legacy => _inner.legacy;

  @override
  Future<Map<String, int>> countsByOwner() => _inner.countsByOwner();

  @override
  VisitStore forOwner(String ownerId) =>
      ownerId == 'acs-a' ? FailingVisitStore(failOnLoad: false) : _inner.forOwner(ownerId);
}
