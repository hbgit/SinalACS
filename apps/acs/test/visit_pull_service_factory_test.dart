import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/database/encrypted_database.dart';
import 'package:sinalacs_acs/core/database/sqlcipher_visit_store.dart';
import 'package:sinalacs_acs/core/database/sync_cursor_store.dart';
import 'package:sinalacs_acs/core/security/database_key_store.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';
import 'package:sinalacs_acs/core/services/visit_pull_service.dart';
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
        owner: 'acs-a',
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
        cursorOwner: 'acs-a',
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

  test('sem cursorStore injetado, o cursor é gravado na chave do cursorOwner', () async {
    final keyStore = InMemoryDatabaseKeyStore();
    VisitPullService build(String owner, FakeAcsBackend backend) => buildVisitPullService(
          backend: backend,
          localVisits: InMemoryVisitStore(),
          cursorOwner: owner,
          keyStore: keyStore,
          databaseName: dbName,
          allowUnencryptedForTesting: true,
        );
    final backendA = FakeAcsBackend()
      ..pullEntries = [
        VisitSyncEntry(
          localId: 'x',
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
    await build('acs-a', backendA).pullAndMerge();

    final db = VisitDatabase(
      keyStore: keyStore,
      databaseName: dbName,
      allowUnencryptedForTesting: true,
    );
    addTearDown(db.close);
    final rows = await (await db.open()).query('sync_cursor');
    expect(rows.map((r) => r['key']), ['visits_pull|acs-a']);

    final backendB = FakeAcsBackend();
    await build('acs-b', backendB).pullAndMerge();
    expect(backendB.pullSinceCalls.single, DateTime.utc(2000));
  });
}
