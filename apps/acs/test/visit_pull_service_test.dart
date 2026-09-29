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
  DateTime? syncAt,
}) {
  return VisitSyncEntry(
    localId: localId,
    patientId: patientId,
    scheduledAt: DateTime.utc(2026, 9, 12, 9),
    status: 'realizada',
    riskLevelBefore: RiskLevel.green,
    notes: const {},
    version: version,
    syncAt: syncAt,
    arrivalMethod: ArrivalMethod.manual,
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

  test(
    'avança o cursor para o MAIOR syncAt entre as entradas recebidas, não para o relógio do dispositivo',
    () async {
      // Datas deliberadamente distantes de "agora" (o teste roda em 2026+,
      // isto é 2021): se o serviço gravasse `DateTime.now()` em vez do
      // `syncAt` do servidor, o cursor lido a seguir ficaria muito à frente
      // destes valores — o teste falharia e distinguiria os dois
      // comportamentos, exatamente o que o achado de revisão pediu.
      final maisAntigo = DateTime.utc(2021, 1, 1);
      final maisRecente = DateTime.utc(2021, 6, 1);
      backend.pullEntries = [
        entry(localId: 'a', syncAt: maisAntigo),
        entry(localId: 'b', syncAt: maisRecente),
      ];
      final service = VisitPullService(
        backend: backend,
        cursorStore: cursorStore,
        localVisits: InMemoryVisitStore(),
      );

      await service.pullAndMerge();

      expect(await cursorStore.read(), maisRecente);
    },
  );

  test(
    'uma segunda execução usa o cursor gravado pela primeira (o maior syncAt), não a época inicial',
    () async {
      final syncAtPrimeiraRodada = DateTime.utc(2021, 3, 10);
      backend.pullEntries = [entry(localId: 'a', syncAt: syncAtPrimeiraRodada)];
      final service = VisitPullService(
        backend: backend,
        cursorStore: cursorStore,
        localVisits: InMemoryVisitStore(),
      );

      await service.pullAndMerge();
      backend.pullEntries = [entry(localId: 'b', syncAt: DateTime.utc(2021, 4, 1))];
      await service.pullAndMerge();

      expect(backend.pullSinceCalls, hasLength(2));
      expect(backend.pullSinceCalls[1], syncAtPrimeiraRodada);
    },
  );

  test('lista de entradas vazia não avança o cursor', () async {
    final cursorPrevio = DateTime.utc(2021, 1, 1);
    await cursorStore.write(cursorPrevio);
    backend.pullEntries = const [];
    final service = VisitPullService(
      backend: backend,
      cursorStore: cursorStore,
      localVisits: InMemoryVisitStore(),
    );

    await service.pullAndMerge();

    // Sem confirmação nenhuma do servidor sobre até onde a microárea foi
    // varrida, o cursor fica como estava — a próxima chamada reconsulta o
    // mesmo `since`, idempotente, sem risco de pular visitas.
    expect(await cursorStore.read(), cursorPrevio);
    expect(backend.pullSinceCalls.single, cursorPrevio);
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
      entry(localId: 'ja-existe', syncAt: DateTime.utc(2021, 1, 1)),
      entry(localId: 'nova-visita', syncAt: DateTime.utc(2021, 1, 2)),
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
    backend.pullEntries = [
      entry(localId: 'visita-1', syncAt: DateTime.utc(2021, 1, 1)),
      entry(localId: 'visita-2', syncAt: DateTime.utc(2021, 1, 2)),
    ];
    final service = VisitPullService(
      backend: backend,
      cursorStore: cursorStore,
      localVisits: InMemoryVisitStore(),
    );

    await service.pullAndMerge();

    expect(service.lastPulled, hasLength(2));
  });
}
