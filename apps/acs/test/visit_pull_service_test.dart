import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/database/encrypted_database.dart';
import 'package:sinalacs_acs/core/database/sync_cursor_store.dart';
import 'package:sinalacs_acs/core/security/database_key_store.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';
import 'package:sinalacs_acs/core/services/visit_pull_service.dart';
import 'package:sinalacs_client/sinalacs_client.dart';

import 'support/fakes.dart';

VisitSyncEntry entry({
  required String localId,
  String patientId = seedPatientId,
  int version = 1,
}) {
  return VisitSyncEntry(
    localId: localId,
    patientId: patientId,
    scheduledAt: DateTime.utc(2026, 9, 12, 9),
    status: 'realizada',
    riskLevelBefore: RiskLevel.green,
    notes: const {},
    version: version,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAcsBackend backend;
  late SyncCursorStore cursorStore;
  const dbName = 'visit_pull_service_test.db';

  setUp(() async {
    await EncryptedLocalDatabase.deleteDatabaseFile(dbName);
    backend = FakeAcsBackend();
    cursorStore = SyncCursorStore(
      keyStore: InMemoryDatabaseKeyStore(),
      databaseName: dbName,
      allowUnencryptedForTesting: true,
    );
  });

  tearDown(() => EncryptedLocalDatabase.deleteDatabaseFile(dbName));

  test('primeira execução: sem cursor gravado, chama pullVisits com uma época bem antiga', () async {
    expect(await cursorStore.read(), isNull);
    final service = VisitPullService(
      backend: backend,
      cursorStore: cursorStore,
      localVisits: InMemoryVisitStore(),
    );

    await service.pullAndMerge();

    expect(backend.pullSinceCalls, hasLength(1));
    expect(backend.pullSinceCalls.single, DateTime.utc(2000));
  });

  test('depois de um pull bem-sucedido, o cursor é atualizado para agora', () async {
    final before = DateTime.now().toUtc();
    final service = VisitPullService(
      backend: backend,
      cursorStore: cursorStore,
      localVisits: InMemoryVisitStore(),
    );

    await service.pullAndMerge();
    final after = DateTime.now().toUtc();

    final cursor = await cursorStore.read();
    expect(cursor, isNotNull);
    expect(cursor!.isBefore(before), isFalse);
    expect(cursor.isAfter(after), isFalse);
  });

  test('uma segunda execução usa o cursor gravado pela primeira, não a época inicial', () async {
    final service = VisitPullService(
      backend: backend,
      cursorStore: cursorStore,
      localVisits: InMemoryVisitStore(),
    );

    await service.pullAndMerge();
    final firstCursor = await cursorStore.read();
    await service.pullAndMerge();

    expect(backend.pullSinceCalls, hasLength(2));
    expect(backend.pullSinceCalls[1], firstCursor);
  });

  test('entradas recebidas com localId já presente na fila offline local não duplicam', () async {
    final localStore = InMemoryVisitStore();
    await localStore.save([
      OfflineVisitRecord(
        localId: 'ja-existe',
        patientId: seedPatientId,
        risk: 'green',
        status: 'PENDENTE',
      ),
    ]);
    backend.pullEntries = [
      entry(localId: 'ja-existe'),
      entry(localId: 'nova-visita'),
    ];
    final service = VisitPullService(
      backend: backend,
      cursorStore: cursorStore,
      localVisits: localStore,
    );

    await service.pullAndMerge();

    expect(service.lastPulled.map((e) => e.localId), ['nova-visita']);
  });

  test('sem entradas duplicadas, o pull não lança nem trava', () async {
    backend.pullEntries = [entry(localId: 'visita-1'), entry(localId: 'visita-2')];
    final service = VisitPullService(
      backend: backend,
      cursorStore: cursorStore,
      localVisits: InMemoryVisitStore(),
    );

    await service.pullAndMerge();

    expect(service.lastPulled, hasLength(2));
  });
}
