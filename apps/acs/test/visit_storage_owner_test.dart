import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/database/encrypted_database.dart';
import 'package:sinalacs_acs/core/database/sqlcipher_visit_store.dart';
import 'package:sinalacs_acs/core/security/database_key_store.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fakes.dart';

OfflineVisitRecord _visita(String localId, {bool rejeitada = false}) =>
    OfflineVisitRecord(
      patientId: seedPatientId,
      risk: 'red',
      status: 'PENDENTE',
      outcome: 'realizada',
      localId: localId,
      rejectionReason: rejeitada ? 'recusada' : null,
    );

Future<int> _contar(Database db, String where) async =>
    (await db.rawQuery('SELECT COUNT(*) AS n FROM offline_visits WHERE $where'))
        .single['n']! as int;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const nome = 'visit_storage_owner_test.db';
  late SqlCipherVisitStorage storage;

  SqlCipherVisitStorage abrir() => SqlCipherVisitStorage(
        keyStore: InMemoryDatabaseKeyStore(),
        databaseName: nome,
        allowUnencryptedForTesting: true,
      );

  setUp(() async {
    await EncryptedLocalDatabase.deleteDatabaseFile(nome);
    storage = abrir();
  });

  tearDown(() async {
    await storage.close();
    await EncryptedLocalDatabase.deleteDatabaseFile(nome);
  });

  test('cada dono vê só as próprias visitas', () async {
    final a = storage.forOwner('acs-a'), b = storage.forOwner('acs-b');
    await a.save([_visita('local-a1'), _visita('local-a2', rejeitada: true)]);
    expect(await b.load(), isEmpty);
    expect((await a.load()).map((v) => v.localId), ['local-a1', 'local-a2']);
  });

  test('save de B nunca apaga nem altera as linhas de A', () async {
    final a = storage.forOwner('acs-a'), b = storage.forOwner('acs-b');
    await a.save([_visita('local-a1')]);
    await b.save([_visita('local-b1')]);
    await b.save([]);
    expect((await a.load()).map((v) => v.localId), ['local-a1']);
    final db = await storage.database.open();
    expect(await _contar(db, "owner='acs-a'"), 1);
    expect(await _contar(db, "owner='acs-b'"), 0);
  });

  test('migração v6 → v7 preserva as linhas em QUARENTENA: nenhum dono as vê', () async {
    sqfliteFfiInit();
    final v6 = await databaseFactoryFfi.openDatabase(
      await EncryptedLocalDatabase.pathFor(nome),
      options: OpenDatabaseOptions(
        version: 6,
        onCreate: (db, version) => db.execute('''
CREATE TABLE offline_visits (
  local_id TEXT PRIMARY KEY, patient_id TEXT NOT NULL, risk TEXT NOT NULL,
  status TEXT NOT NULL, outcome TEXT NOT NULL, notes TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL, version INTEGER NOT NULL, rejection_reason TEXT
)'''),
      ),
    );
    for (final (i, id) in ['local-v6-1', 'local-v6-2'].indexed) {
      await v6.insert('offline_visits', {
        'local_id': id,
        'patient_id': seedPatientId,
        'risk': 'red',
        'status': 'PENDENTE',
        'outcome': '',
        'notes': '',
        'created_at': DateTime.utc(2026, 1, 1 + i).toIso8601String(),
        'version': 1,
      });
    }
    await v6.close();

    expect(await storage.forOwner('acs-a').load(), isEmpty);
    expect(await storage.forOwner('acs-b').load(), isEmpty);
    expect((await storage.legacy.load()).map((v) => v.localId),
        ['local-v6-1', 'local-v6-2']);
    await storage.forOwner('acs-a').save([_visita('local-a1')]);
    expect((await storage.legacy.load()).length, 2);
    // save vazio de A também não toca na quarentena.
    await storage.forOwner('acs-a').save([]);
    expect((await storage.legacy.load()).length, 2);
  });

  test('legacy.remove apaga só os localIds pedidos e só os legados', () async {
    final db = await storage.database.open();
    for (final id in ['leg-1', 'leg-2']) {
      await db.insert('offline_visits', {
        'local_id': id,
        'patient_id': seedPatientId,
        'risk': 'red',
        'status': 'PENDENTE',
        'outcome': '',
        'notes': '',
        'created_at': DateTime.utc(2026).toIso8601String(),
        'version': 1,
      });
    }
    await storage.forOwner('acs-a').save([_visita('dono-1')]);

    await storage.legacy.remove(['leg-1', 'dono-1', 'inexistente']);

    expect((await storage.legacy.load()).map((v) => v.localId), ['leg-2']);
    expect((await storage.forOwner('acs-a').load()).map((v) => v.localId),
        ['dono-1']);
  });

  test('local_id é único globalmente: B não consegue sobrescrever a visita de A', () async {
    // Comportamento escolhido: o save de B LANÇA VisitLocalIdConflict e a
    // transação inteira é desfeita; a linha de A fica intacta (e as de B
    // anteriores ao save também, pois o DELETE de B é revertido).
    final a = storage.forOwner('acs-a'), b = storage.forOwner('acs-b');
    await a.save([_visita('local-x')]);
    await b.save([_visita('local-b1')]);

    await expectLater(
      b.save([_visita('local-b2'), _visita('local-x')]),
      throwsA(isA<VisitLocalIdConflict>()),
    );

    expect((await a.load()).map((v) => v.localId), ['local-x']);
    expect((await b.load()).map((v) => v.localId), ['local-b1']);
  });

  test('o mesmo dono pode regravar o próprio local_id', () async {
    final a = storage.forOwner('acs-a');
    await a.save([_visita('local-x')]);
    await a.save([_visita('local-x'), _visita('local-y')]);
    expect((await a.load()).map((v) => v.localId), ['local-x', 'local-y']);
  });

  test('InMemoryVisitStorage: um store por dono e quarentena própria', () async {
    final mem = InMemoryVisitStorage();
    await mem.forOwner('a').save([_visita('l1')]);
    expect(await mem.forOwner('b').load(), isEmpty);
    expect(identical(mem.forOwner('a'), mem.forOwner('a')), isTrue);
    expect(await mem.legacy.load(), isEmpty);
  });
}
