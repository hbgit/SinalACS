import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/app/app.dart';
import 'package:sinalacs_acs/core/database/encrypted_database.dart';
import 'package:sinalacs_acs/core/database/micro_area_cache_store.dart';
import 'package:sinalacs_acs/core/database/sqlcipher_visit_store.dart';
import 'package:sinalacs_acs/core/security/database_key_store.dart';
import 'package:sinalacs_acs/core/security/session_token_store.dart';
import 'package:sinalacs_acs/core/security/upload_token_store.dart';
import 'package:sinalacs_acs/core/services/micro_area_directory.dart';
import 'package:sinalacs_acs/core/services/remote_wipe.dart';
import 'package:sinalacs_client/sinalacs_client.dart';

import 'support/fakes.dart';
import 'support/layout_harness.dart' show assentar;

/// Chave em memória que conta quantas vezes uma chave NOVA foi criada: uma
/// escrita atrasada depois da limpeza remota criaria (e guardaria) uma.
class _ChaveContada extends InMemoryDatabaseKeyStore {
  _ChaveContada() : super(initialKey: 'a' * 64);

  bool temChave = true;
  int criadas = 0;

  @override
  Future<String> readOrCreate() async {
    if (!temChave) criadas++;
    temChave = true;
    return super.readOrCreate();
  }

  @override
  Future<void> delete() async {
    temChave = false;
    await super.delete();
  }
}

/// Limpeza remota (#81, I1): a lista da microárea e o pull que respondem
/// DEPOIS do apagador não recriam o banco, nem a chave, nem gravam nomes e
/// condições crônicas no aparelho que o servidor registra como limpo. E o
/// próximo login volta a ter o cache. Banco real (FFI), dados sintéticos.
void main() {
  const dbName = 'remote_wipe_late_writes_test.db';
  const acsA = 'acs-a';
  const ordem = 'ordem-tardia';
  const tabelas = ['offline_visits', 'sync_cursor', 'micro_area_cache', 'micro_area_cache_meta'];

  late _ChaveContada chave;
  late SqlCipherVisitStorage storage;
  late MicroAreaCacheStore cache;
  late FakeAcsBackend backend;
  late MemoryDeviceIdStore deviceIds;
  late MemoryWipeJournal journal;
  Completer<void>? listaGate;

  Future<T> io<T>(WidgetTester tester, Future<T> Function() op) async => (await tester.runAsync(op)) as T;

  Future<bool> arquivoExiste(WidgetTester tester) =>
      io(tester, () async => File(await EncryptedLocalDatabase.pathFor(dbName)).exists());

  Future<Map<String, int>> contarTabelas(WidgetTester tester) => io(tester, () async {
        final db = await storage.database.open();
        return {
          for (final tabela in tabelas)
            tabela: ((await db.rawQuery('SELECT COUNT(*) AS n FROM $tabela')).single['n']! as int),
        };
      });

  setUp(() async {
    await EncryptedLocalDatabase.deleteDatabaseFile(dbName);
    chave = _ChaveContada();
    storage = SqlCipherVisitStorage(keyStore: chave, databaseName: dbName, allowUnencryptedForTesting: true);
    cache = MicroAreaCacheStore(keyStore: chave, databaseName: dbName, allowUnencryptedForTesting: true);
    deviceIds = MemoryDeviceIdStore('00000000-0000-4000-8000-0000000000d1');
    backend = FakeAcsBackend()
      ..nextUserId = acsA
      ..deviceIds = deviceIds
      ..pullEntries = [
        VisitSyncEntry(
          localId: 'remota-1',
          patientId: seedPatientId,
          scheduledAt: DateTime.utc(2026, 10, 3, 9),
          status: 'realizada',
          riskLevelBefore: RiskLevel.green,
          notes: const {},
          version: 1,
          syncAt: DateTime.utc(2026, 10, 3, 10),
          arrivalMethod: ArrivalMethod.manual,
        ),
      ];
    journal = MemoryWipeJournal();
    listaGate = null;
  });

  tearDown(() async {
    await storage.close();
    await EncryptedLocalDatabase.deleteDatabaseFile(dbName);
  });

  Future<void> abrirApp(WidgetTester tester) async {
    await tester.pumpWidget(SinalAcsApp(
      backend: backend,
      visitStorage: storage,
      microAreaDirectory: MicroAreaDirectory(
        fetch: () async {
          await listaGate?.future;
          return [
            MicroAreaPatient(
              patientId: syntheticPatientId(5),
              name: 'Paciente Sintético',
              isChronic: true,
              chronicConditions: const ['condição sintética'],
            ),
          ];
        },
        session: () => backend.session,
        store: cache,
      ),
      uploadTokens: MemoryUploadTokenStore(),
      deviceIds: deviceIds,
      wipeJournal: journal,
      biometricGate: FakeBiometricGate(),
      feedBuilder: (q) => FakeAlertFeed(q),
    ));
    await assentar(tester);
  }

  Future<void> entrar(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('matricula_field')), 'ACS-001');
    await tester.enterText(find.byKey(const Key('senha_field')), 'senha-sintetica');
    final botao = find.byKey(const Key('login_button'));
    await tester.ensureVisible(botao);
    await tester.pump();
    await tester.tap(botao);
    await assentar(tester);
    expect(find.text('Painel operacional'), findsOneWidget);
  }

  testWidgets('lista da microárea e pull que respondem depois do apagador não recriam banco nem chave',
      (tester) async {
    await abrirApp(tester);
    await entrar(tester);
    final carregado = await contarTabelas(tester);
    expect(carregado['micro_area_cache'], 1, reason: 'a abertura do painel gravou o cache');
    expect(carregado['sync_cursor'], 1, reason: 'e o cursor do pull');

    // Volta do segundo plano: o painel atualiza a área (presa na rede) e, em
    // paralelo, a consulta encontra o pedido de limpeza.
    listaGate = Completer<void>();
    backend.pullGate = Completer<void>();
    backend.pendingWipeOrderId = ordem;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await assentar(tester);
    await assentar(tester);

    expect(find.byKey(const Key('device_wiped')), findsOneWidget);
    expect(backend.confirmedWipes, hasLength(1));
    expect(await arquivoExiste(tester), isFalse, reason: 'o apagador levou o arquivo');
    expect(chave.temChave, isFalse, reason: 'e a chave');

    // A rede responde só agora, depois da limpeza.
    listaGate!.complete();
    backend.pullGate!.complete();
    await assentar(tester);
    await assentar(tester);

    expect(chave.criadas, 0, reason: 'nenhuma escrita atrasada criou uma chave nova');
    expect(chave.temChave, isFalse);
    expect(await arquivoExiste(tester), isFalse, reason: 'nem um arquivo novo com nomes e condições crônicas');
    expect(backend.acknowledgedAlertIds, isEmpty);
    expect(backend.resolvedAlertIds, isEmpty);
  });

  testWidgets('depois de Entrar de novo o cache e o cursor voltam a ser gravados', (tester) async {
    await abrirApp(tester);
    await entrar(tester);

    listaGate = Completer<void>();
    backend.pullGate = Completer<void>();
    backend.pendingWipeOrderId = ordem;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await assentar(tester);
    listaGate!.complete();
    backend.pullGate!.complete();
    await assentar(tester);
    expect(find.byKey(const Key('device_wiped')), findsOneWidget);
    expect(await arquivoExiste(tester), isFalse);

    listaGate = null;
    backend.pullGate = null;
    backend.pendingWipeOrderId = null; // o id novo não tem pedido
    final botao = find.byKey(const Key('device_wiped_login'));
    await tester.ensureVisible(botao);
    await tester.tap(botao);
    await assentar(tester);
    await entrar(tester);
    await assentar(tester);

    final depois = await contarTabelas(tester);
    expect(depois['micro_area_cache'], 1, reason: 'o login novo volta a ter o cache da microárea');
    expect(depois['sync_cursor'], 1, reason: 'e o cursor do pull');
    expect(chave.criadas, 1, reason: 'uma chave nova, criada pelo login novo');
  });
}
