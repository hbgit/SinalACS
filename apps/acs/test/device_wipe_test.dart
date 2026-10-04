import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/app/app.dart';
import 'package:sinalacs_acs/core/database/encrypted_database.dart';
import 'package:sinalacs_acs/core/database/micro_area_cache_store.dart';
import 'package:sinalacs_acs/core/database/sqlcipher_visit_store.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/security/database_key_store.dart';
import 'package:sinalacs_acs/core/security/session_token_store.dart';
import 'package:sinalacs_acs/core/security/upload_token_store.dart';
import 'package:sinalacs_acs/core/services/micro_area_directory.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';
import 'package:sinalacs_client/sinalacs_client.dart';

import 'support/fakes.dart';
import 'support/layout_harness.dart' show assentar, irParaDaBarra, irParaDoMais;

/// "Limpar este aparelho" (D9): só apaga com TUDO enviado — de todos os donos,
/// da quarentena e da memória. Nunca apaga visita não enviada. Ids, pacientes
/// e tokens sintéticos.
void main() {
  const acsA = 'acs-a';
  const acsB = 'acs-b';
  const tabelas = ['offline_visits', 'sync_cursor', 'micro_area_cache', 'micro_area_cache_meta'];
  const semRede = BackendFailure('Sem conexão com o servidor.');

  OfflineVisitRecord pendente(String localId) =>
      OfflineVisitRecord(localId: localId, patientId: seedPatientId, risk: 'red', status: 'PENDENTE');

  SqlCipherVisitStorage abrirBanco(String dbName) => SqlCipherVisitStorage(
        keyStore: InMemoryDatabaseKeyStore(),
        databaseName: dbName,
        allowUnencryptedForTesting: true,
      );

  /// Linha sem dono (quarentena, D2), como um aparelho que veio do schema v6.
  Future<void> gravarLegada(SqlCipherVisitStorage storage, String localId, {String? rejectionReason}) async {
    final db = await storage.database.open();
    await db.insert('offline_visits', {
      'local_id': localId,
      'patient_id': seedPatientId,
      'risk': 'red',
      'status': 'PENDENTE',
      'outcome': 'PENDENTE',
      'created_at': DateTime.utc(2026, 10, 1).toIso8601String(),
      'version': 1,
      'rejection_reason': rejectionReason,
    });
  }

  /// Cursor do pull e cache da microárea: o que o wipe apaga junto.
  Future<void> gravarCursorECache(SqlCipherVisitStorage storage) async {
    final db = await storage.database.open();
    await db.insert('sync_cursor', {'key': 'visits_pull|$acsA|$seedMicroAreaId', 'value': '2026-10-03T10:00:00.000Z'});
    await db.insert('micro_area_cache', {
      'patient_id': syntheticPatientId(7),
      'name': 'Paciente Sintético',
      'is_chronic': 0,
      'chronic_conditions': '[]',
    });
    await db.insert('micro_area_cache_meta', {'key': 'owner', 'value': '$acsA|$seedMicroAreaId'});
  }

  Future<Map<String, int>> contarTabelas(SqlCipherVisitStorage storage) async {
    final db = await storage.database.open();
    return {
      for (final tabela in tabelas)
        tabela: ((await db.rawQuery('SELECT COUNT(*) AS n FROM $tabela')).single['n']! as int),
    };
  }

  group('VisitDatabase.wipeAllData (banco real, FFI)', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const dbName = 'device_wipe_unit_test.db';

    setUp(() => EncryptedLocalDatabase.deleteDatabaseFile(dbName));
    tearDown(() => EncryptedLocalDatabase.deleteDatabaseFile(dbName));

    test('recusa com visita de um dono e não apaga nada', () async {
      final storage = abrirBanco(dbName);
      addTearDown(storage.close);
      await storage.forOwner(acsA).save([pendente('a-1')]);
      await gravarCursorECache(storage);
      final antes = await contarTabelas(storage);

      await expectLater(storage.database.wipeAllData(), throwsA(isA<WipeBlocked>().having((e) => e.unsent, 'unsent', 1)));
      expect(await contarTabelas(storage), antes);
    });

    test('recusa com uma linha SEM dono (quarentena) e não apaga nada', () async {
      final storage = abrirBanco(dbName);
      addTearDown(storage.close);
      await gravarLegada(storage, 'legada-1');
      await gravarCursorECache(storage);
      final antes = await contarTabelas(storage);

      await expectLater(storage.database.wipeAllData(), throwsA(isA<WipeBlocked>().having((e) => e.unsent, 'unsent', 1)));
      expect(await contarTabelas(storage), antes);
      expect(await storage.legacy.load(), hasLength(1));
    });

    test('recusa com só uma visita RECUSADA de um dono e não apaga nada', () async {
      final storage = abrirBanco(dbName);
      addTearDown(storage.close);
      await storage.forOwner(acsA).save([
        OfflineVisitRecord(
          localId: 'a-recusada',
          patientId: seedPatientId,
          risk: 'red',
          status: 'PENDENTE',
          rejectionReason: 'paciente fora da sua microárea',
        ),
      ]);
      await gravarCursorECache(storage);
      final antes = await contarTabelas(storage);

      await expectLater(storage.database.wipeAllData(), throwsA(isA<WipeBlocked>().having((e) => e.unsent, 'unsent', 1)));
      expect(await contarTabelas(storage), antes);
    });

    test('recusa com só uma visita RECUSADA sem dono (quarentena) e não apaga nada', () async {
      final storage = abrirBanco(dbName);
      addTearDown(storage.close);
      await gravarLegada(storage, 'legada-recusada', rejectionReason: 'visita já registrada com autor — versão diferente');
      await gravarCursorECache(storage);
      final antes = await contarTabelas(storage);

      await expectLater(storage.database.wipeAllData(), throwsA(isA<WipeBlocked>().having((e) => e.unsent, 'unsent', 1)));
      expect(await contarTabelas(storage), antes);
    });

    test('sem visita pendente apaga cursor e cache; o arquivo continua e reabre', () async {
      final storage = abrirBanco(dbName);
      addTearDown(storage.close);
      await gravarCursorECache(storage);

      await storage.database.wipeAllData();

      expect(await contarTabelas(storage), {for (final t in tabelas) t: 0});
      expect(File(await EncryptedLocalDatabase.pathFor(dbName)).existsSync(), isTrue,
          reason: 'limpeza de dados, não troca de chave nem apagamento do arquivo');
      await storage.forOwner(acsA).save([pendente('depois')]);
      expect(await storage.forOwner(acsA).load(), hasLength(1), reason: 'o banco segue utilizável');
    });
  });

  group('"Limpar este aparelho" no app', () {
    const dbName = 'device_wipe_widget_test.db';

    late SqlCipherVisitStorage storage;
    late FakeAcsBackend backend;
    late MemoryUploadTokenStore tokens;

    setUp(() async {
      await EncryptedLocalDatabase.deleteDatabaseFile(dbName);
      storage = abrirBanco(dbName);
      backend = FakeAcsBackend()..nextUserId = acsA;
      tokens = MemoryUploadTokenStore({acsA: 'upload-a', acsB: 'upload-b'});
    });

    tearDown(() async {
      await storage.close();
      await EncryptedLocalDatabase.deleteDatabaseFile(dbName);
    });

    Future<void> abrirApp(WidgetTester tester, {VisitStorage? visitStorage}) async {
      await tester.pumpWidget(SinalAcsApp(
        backend: backend,
        visitStorage: visitStorage ?? storage,
        uploadTokens: tokens,
        deviceIds: MemoryDeviceIdStore('aparelho-sintetico'),
        feedBuilder: (q) => FakeAlertFeed(q),
      ));
      await assentar(tester);
    }

    Future<void> entrarComo(WidgetTester tester, String userId) async {
      backend.nextUserId = userId;
      await tester.enterText(find.byKey(const Key('matricula_field')), 'ACS-001');
      await tester.enterText(find.byKey(const Key('senha_field')), 'senha-sintetica');
      final botao = find.byKey(const Key('login_button'));
      await tester.ensureVisible(botao);
      await tester.pump();
      await tester.tap(botao);
      await assentar(tester);
      expect(find.text('Painel operacional'), findsOneWidget);
    }

    Future<void> tocarEmLimpar(WidgetTester tester) async {
      await irParaDoMais(tester, 'Preferências');
      final limpar = find.byKey(const Key('wipe_button'));
      await tester.ensureVisible(limpar);
      await tester.pump();
      await tester.tap(limpar);
      await assentar(tester);
    }

    Future<T> io<T>(WidgetTester tester, Future<T> Function() op) async => (await tester.runAsync(op)) as T;

    /// Bloqueado: diálogo com a contagem e o MOTIVO certo, nada apagado, sem
    /// logout. [motivo]: 'envio' (não enviada), 'revisao' (recusada) ou
    /// 'semToken' (dono sem chave de envio). Nunca fala de revisão sem visita
    /// recusada.
    Future<void> esperarBloqueio(
      WidgetTester tester, {
      required int visitas,
      required Map<String, int> antes,
      bool tokenDeAFica = true,
      String motivo = 'envio',
    }) async {
      expect(find.byKey(const Key('wipe_blocked')), findsOneWidget);
      expect(find.byKey(const Key('wipe_confirm')), findsNothing);
      final um = visitas == 1;
      final conecte = find.textContaining('conecte e tente de novo; se não puderem ser enviadas, procure a coordenação');
      final revisao = find.textContaining('de revisão pelo ACS dono (reenvie ou descarte-as ao entrar com a conta dele)');
      final semToken = find.textContaining('entre com a conta do agente para enviar');
      switch (motivo) {
        case 'envio':
          expect(find.textContaining(um ? '1 visita ainda não foi enviada' : '$visitas visitas ainda não foram enviadas'),
              findsOneWidget);
          expect(conecte, findsOneWidget);
          expect(revisao, findsNothing);
          expect(semToken, findsNothing);
        case 'revisao':
          expect(find.textContaining(um ? '1 visita precisa de revisão' : '$visitas visitas precisam de revisão'),
              findsOneWidget);
          expect(revisao, findsOneWidget);
          expect(conecte, findsNothing);
        case 'semToken':
          expect(semToken, findsOneWidget);
          expect(revisao, findsNothing);
          expect(conecte, findsNothing);
      }
      expect(find.textContaining('revisão'), motivo == 'revisao' ? findsWidgets : findsNothing);
      await tester.tap(find.text('Entendi'));
      await assentar(tester);

      expect(await io(tester, () => contarTabelas(storage)), antes, reason: 'o wipe bloqueado não apaga nada');
      if (tokenDeAFica) expect(await tokens.read(acsA), 'upload-a');
      expect(backend.logoutCount, 0);
      expect(find.text('Painel operacional'), findsOneWidget);
    }

    testWidgets('bloqueia com 1 visita do PRÓPRIO ACS não enviada', (tester) async {
      await io(tester, () async {
        await storage.forOwner(acsA).save([pendente('a-1')]);
        await gravarCursorECache(storage);
      });
      backend.syncFailure = semRede;
      final antes = await io(tester, () => contarTabelas(storage));
      await abrirApp(tester);
      await entrarComo(tester, acsA);

      await tocarEmLimpar(tester);

      expect(backend.callLog, contains('syncVisits'), reason: 'tentou enviar antes de decidir');
      await esperarBloqueio(tester, visitas: 1, antes: antes);
      expect(await io(tester, () => storage.forOwner(acsA).load()), hasLength(1));
    });

    testWidgets('bloqueia com 1 visita de OUTRO ACS não enviada', (tester) async {
      await io(tester, () async {
        await storage.forOwner(acsB).save([pendente('b-1')]);
        await gravarCursorECache(storage);
      });
      backend.deferredFailure = semRede;
      final antes = await io(tester, () => contarTabelas(storage));
      await abrirApp(tester);
      await entrarComo(tester, acsA);

      await tocarEmLimpar(tester);

      await esperarBloqueio(tester, visitas: 1, antes: antes);
      expect(await io(tester, () => storage.forOwner(acsB).load()), hasLength(1));
      expect(await tokens.read(acsB), 'upload-b', reason: 'o token de B segue enquanto a visita dele não sobe');
    });

    testWidgets('bloqueia com 1 visita LEGADA (sem dono) não enviada', (tester) async {
      await io(tester, () async {
        await gravarLegada(storage, 'legada-1');
        await gravarCursorECache(storage);
      });
      backend.legacyFailure = semRede;
      final antes = await io(tester, () => contarTabelas(storage));
      await abrirApp(tester);
      await entrarComo(tester, acsA);

      await tocarEmLimpar(tester);

      await esperarBloqueio(tester, visitas: 1, antes: antes);
      expect(await io(tester, () => storage.legacy.load()), hasLength(1));
    });

    testWidgets('bloqueia com 1 visita que só existe na MEMÓRIA (fila de outro ACS que não gravou)', (tester) async {
      await io(tester, () => gravarCursorECache(storage));
      backend.syncFailure = semRede;
      backend.deferredFailure = semRede;
      final antes = await io(tester, () => contarTabelas(storage));
      late FakeAlertFeed feed;
      await tester.pumpWidget(SinalAcsApp(
        backend: backend,
        visitStorage: _GravacaoDeAFalha(storage),
        uploadTokens: tokens,
        deviceIds: MemoryDeviceIdStore('aparelho-sintetico'),
        feedBuilder: (q) => feed = FakeAlertFeed(q),
      ));
      await assentar(tester);
      await entrarComo(tester, acsA);

      // A registra uma visita; a gravação falha e ela fica só na RAM.
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
      await tester.pump(const Duration(seconds: 10)); // o SnackBar da falha some
      await assentar(tester);

      // A sai (sem rede); B entra no mesmo aparelho e tenta limpar.
      await irParaDoMais(tester, 'Preferências');
      final sair = find.byKey(const Key('logout_button'));
      await tester.ensureVisible(sair);
      await tester.pump();
      await tester.tap(sair);
      await assentar(tester);
      await tester.tap(find.byKey(const Key('logout_confirm')));
      await assentar(tester);
      backend.logoutCount = 0;
      await entrarComo(tester, acsB);

      await tocarEmLimpar(tester);
      // O token de A pode ter sido revogado pelo envio diferido (o disco de A
      // está vazio); a visita só em RAM sobe pela sessão de A, que ganha
      // outro token ao entrar.
      await esperarBloqueio(tester, visitas: 1, antes: antes, tokenDeAFica: false);

      // A visita de A continua na memória: A volta e a encontra.
      await irParaDoMais(tester, 'Preferências');
      await tester.ensureVisible(sair);
      await tester.pump();
      await tester.tap(sair);
      await assentar(tester);
      await tester.tap(find.byKey(const Key('logout_confirm')));
      await assentar(tester);
      await entrarComo(tester, acsA);
      await irParaDaBarra(tester, 'Visita');
      final contador = find.byKey(const Key('pending_visits_count'));
      await tester.ensureVisible(contador);
      await tester.pump();
      expect(tester.widget<Text>(contador).data, 'Pendentes de sincronização: 1 (em memória)');
    });

    testWidgets('bloqueia com 1 visita RECUSADA do próprio ACS, pedindo revisão (não "conecte")', (tester) async {
      await io(tester, () async {
        await storage.forOwner(acsA).save([
          OfflineVisitRecord(
            localId: 'a-recusada',
            patientId: seedPatientId,
            risk: 'red',
            status: 'PENDENTE',
            rejectionReason: 'paciente fora da sua microárea',
          ),
        ]);
        await gravarCursorECache(storage);
      });
      final antes = await io(tester, () => contarTabelas(storage));
      await abrirApp(tester);
      await entrarComo(tester, acsA);

      await tocarEmLimpar(tester);

      await esperarBloqueio(tester, visitas: 1, antes: antes, motivo: 'revisao');
    });

    testWidgets('bloqueia com visita de OUTRO ACS sem chave de envio: "entre com a conta do agente"', (tester) async {
      tokens = MemoryUploadTokenStore({acsA: 'upload-a'});
      await io(tester, () async {
        await storage.forOwner(acsB).save([pendente('b-1')]);
        await gravarCursorECache(storage);
      });
      final antes = await io(tester, () => contarTabelas(storage));
      await abrirApp(tester);
      await entrarComo(tester, acsA);

      await tocarEmLimpar(tester);

      await esperarBloqueio(tester, visitas: 1, antes: antes, motivo: 'semToken');
    });

    /// Abre o diálogo de confirmação (tudo enviado até ali).
    Future<void> ateAConfirmacao(WidgetTester tester) async {
      await tocarEmLimpar(tester);
      expect(find.byKey(const Key('wipe_confirm')), findsOneWidget);
    }

    testWidgets('visita que entra na MEMÓRIA depois da confirmação aberta: a limpeza recusa e nada é apagado', (tester) async {
      await io(tester, () => gravarCursorECache(storage));
      // Fila do painel que não grava: o que entrar nela só existe na RAM.
      final fila = OfflineVisitQueue(store: FailingVisitStore(failOnLoad: false));
      await tester.pumpWidget(SinalAcsApp(
        backend: backend,
        visitStorage: storage,
        visitQueue: fila,
        uploadTokens: tokens,
        deviceIds: MemoryDeviceIdStore('aparelho-sintetico'),
        feedBuilder: (q) => FakeAlertFeed(q),
      ));
      await assentar(tester);
      await entrarComo(tester, acsA);
      final antes = await io(tester, () => contarTabelas(storage));
      await ateAConfirmacao(tester);

      await fila.add(pendente('chegou-depois'));
      expect(fila.persistenceFailed, isTrue);
      await tester.tap(find.byKey(const Key('wipe_confirm')));
      await assentar(tester);

      await esperarBloqueio(tester, visitas: 1, antes: antes);
      expect(fila.pendingCount, 1);
    });

    testWidgets('visita que chega ao DISCO depois da confirmação aberta: a transação recusa e nada é apagado', (tester) async {
      await io(tester, () => gravarCursorECache(storage));
      await abrirApp(tester);
      await entrarComo(tester, acsA);
      await ateAConfirmacao(tester);

      await io(tester, () => storage.forOwner(acsB).save([pendente('b-depois')]));
      final antes = await io(tester, () => contarTabelas(storage));
      await tester.tap(find.byKey(const Key('wipe_confirm')));
      await assentar(tester);

      await esperarBloqueio(tester, visitas: 1, antes: antes);
      expect(await io(tester, () => storage.forOwner(acsB).load()), hasLength(1));
    });

    testWidgets('atualização da área em voo na confirmação: nada de cache nem cursor é regravado depois da limpeza',
        (tester) async {
      final syncAt = DateTime.utc(2026, 10, 3, 10);
      backend.pullEntries = [
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
      Completer<void>? listaGate;
      final directory = MicroAreaDirectory(
        fetch: () async {
          await listaGate?.future;
          return [
            MicroAreaPatient(patientId: syntheticPatientId(5), name: 'Paciente Sintético', isChronic: false, chronicConditions: const []),
          ];
        },
        session: () => backend.session,
        store: MicroAreaCacheStore(keyStore: InMemoryDatabaseKeyStore(), databaseName: dbName, allowUnencryptedForTesting: true),
      );
      await tester.pumpWidget(SinalAcsApp(
        backend: backend,
        visitStorage: storage,
        microAreaDirectory: directory,
        uploadTokens: tokens,
        deviceIds: MemoryDeviceIdStore('aparelho-sintetico'),
        feedBuilder: (q) => FakeAlertFeed(q),
      ));
      await assentar(tester);
      await entrarComo(tester, acsA);
      final carregado = await io(tester, () => contarTabelas(storage));
      expect(carregado['micro_area_cache'], 1);
      expect(carregado['sync_cursor'], 1);

      await ateAConfirmacao(tester);
      // Volta do segundo plano: atualização da área em voo, presa na rede.
      listaGate = Completer<void>();
      backend.pullGate = Completer<void>();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      await tester.tap(find.byKey(const Key('wipe_confirm')));
      await assentar(tester);
      // A rede responde depois que a pessoa confirmou.
      listaGate.complete();
      backend.pullGate!.complete();
      await assentar(tester);
      await assentar(tester);

      expect(find.byKey(const Key('login_button')), findsOneWidget);
      expect(await io(tester, () => contarTabelas(storage)), {for (final t in tabelas) t: 0},
          reason: 'nada do território é regravado depois de "dados apagados"');
    });

    testWidgets('com TUDO enviado: confirma, esvazia as tabelas e as chaves de envio, sai e volta ao login', (tester) async {
      await io(tester, () async {
        await storage.forOwner(acsA).save([pendente('a-1')]);
        await storage.forOwner(acsB).save([pendente('b-1')]);
        await gravarLegada(storage, 'legada-1');
        await gravarCursorECache(storage);
      });
      await abrirApp(tester);
      await entrarComo(tester, acsA);

      await tocarEmLimpar(tester);

      expect(find.byKey(const Key('wipe_blocked')), findsNothing);
      expect(
        find.text('Isto apaga neste aparelho as visitas já enviadas, o cache da microárea, o cursor de sincronização e as chaves de envio. Não pode ser desfeito.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancelar'));
      await assentar(tester);
      expect(await io(tester, () => contarTabelas(storage)), isNot({for (final t in tabelas) t: 0}),
          reason: 'cancelar não apaga');
      expect(backend.logoutCount, 0);

      await tocarEmLimpar(tester);
      await tester.tap(find.byKey(const Key('wipe_confirm')));
      await assentar(tester);
      await assentar(tester); // E/S real do banco (FFI) + transição para o login

      expect(await io(tester, () => contarTabelas(storage)), {for (final t in tabelas) t: 0});
      expect(await tokens.owners(), isEmpty);
      expect(await tokens.read(acsA), isNull);
      expect(await tokens.read(acsB), isNull);
      expect(backend.revokedUploadTokens, containsAll(['upload-a', 'upload-b']));
      expect(backend.logoutCount, 1);
      expect(backend.callLog.lastIndexOf('revokeUploadToken'), lessThan(backend.callLog.lastIndexOf('logout')));
      expect(find.byKey(const Key('login_button')), findsOneWidget);
      expect(find.text('Painel operacional'), findsNothing);
      expect(find.text('Os dados deste aparelho foram apagados.'), findsOneWidget);
    });
  });
}

/// Só a visão de `acs-a` recusa gravar: a visita de A fica só na RAM.
class _GravacaoDeAFalha implements VisitStorage {
  _GravacaoDeAFalha(this._inner);

  final VisitStorage _inner;

  @override
  LegacyVisitStore get legacy => _inner.legacy;

  @override
  Future<Map<String, int>> countsByOwner() => _inner.countsByOwner();

  @override
  Future<void> wipeAllData() => _inner.wipeAllData();

  @override
  VisitStore forOwner(String ownerId) =>
      ownerId == 'acs-a' ? FailingVisitStore(failOnLoad: false) : _inner.forOwner(ownerId);
}
