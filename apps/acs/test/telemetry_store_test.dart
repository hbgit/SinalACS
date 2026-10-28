import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/database/encrypted_database.dart';
import 'package:sinalacs_acs/core/database/sqlcipher_telemetry_store.dart';
import 'package:sinalacs_acs/core/database/sqlcipher_visit_store.dart';
import 'package:sinalacs_acs/core/security/database_key_store.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';
import 'package:sinalacs_acs/core/telemetry/telemetry_event.dart';
import 'package:sinalacs_acs/core/telemetry/telemetry_store.dart';

import 'support/fakes.dart';

/// Eventos sintéticos, sem PII. O mesmo contrato roda sobre a implementação em
/// memória e sobre o SQLCipher (sem criptografia na VM).
TelemetryEventRecord _evento(String id, String dono, DateTime em, {String nome = 'alert_received_acs'}) =>
    TelemetryEventRecord(
      eventId: id,
      owner: dono,
      name: nome,
      occurredAt: em,
      payload: {'n': 1, 'ok': true},
    );

void _contrato(String titulo, Future<TelemetryStore> Function({int? teto}) criar) {
  group(titulo, () {
    final base = DateTime.utc(2026, 10, 25, 12);

    test('oldestForOwner só vê o dono', () async {
      final store = await criar();
      await store.append(_evento('a1', 'acs-a', base));
      await store.append(_evento('b1', 'acs-b', base));

      expect((await store.oldestForOwner('acs-a', limit: 10)).map((e) => e.eventId), ['a1']);
      expect((await store.oldestForOwner('acs-b', limit: 10)).map((e) => e.eventId), ['b1']);
      expect(await store.countForOwner('acs-a'), 1);
    });

    test('ordem por occurred_at, payload e data em UTC voltam', () async {
      final store = await criar();
      await store.append(_evento('tarde', 'acs-a', base.add(const Duration(minutes: 5))));
      await store.append(_evento('cedo', 'acs-a', base));

      final lidos = await store.oldestForOwner('acs-a', limit: 10);
      expect(lidos.map((e) => e.eventId), ['cedo', 'tarde']);
      expect(lidos.first.occurredAt, base);
      expect(lidos.first.occurredAt.isUtc, isTrue);
      expect(lidos.first.payload, {'n': 1, 'ok': true});
      expect((await store.oldestForOwner('acs-a', limit: 1)).single.eventId, 'cedo');
    });

    test('event_id repetido é ignorado', () async {
      final store = await criar();
      await store.append(_evento('x', 'acs-a', base));
      await store.append(_evento('x', 'acs-a', base.add(const Duration(hours: 1))));
      expect(await store.countForOwner('acs-a'), 1);
    });

    test('teto apaga o mais antigo do mesmo dono e não toca no outro', () async {
      final store = await criar(teto: 3);
      for (var i = 0; i < 3; i++) {
        await store.append(_evento('b$i', 'acs-b', base.add(Duration(minutes: i))));
      }
      for (var i = 0; i < 5; i++) {
        await store.append(_evento('a$i', 'acs-a', base.add(Duration(minutes: i))));
      }

      expect((await store.oldestForOwner('acs-a', limit: 10)).map((e) => e.eventId), ['a2', 'a3', 'a4']);
      expect(await store.countForOwner('acs-b'), 3);
    });

    test('deleteByIds ignora id desconhecido', () async {
      final store = await criar();
      await store.append(_evento('a1', 'acs-a', base));
      await store.append(_evento('a2', 'acs-a', base));

      await store.deleteByIds(['a1', 'nao-existe']);
      expect((await store.oldestForOwner('acs-a', limit: 10)).map((e) => e.eventId), ['a2']);
      await store.deleteByIds(const []);
      expect(await store.countForOwner('acs-a'), 1);
    });
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('o teto padrão é 5000', () => expect(maxTelemetryEventsPerOwner, 5000));

  _contrato('InMemoryTelemetryStore', ({int? teto}) async => InMemoryTelemetryStore(maxPerOwner: teto ?? maxTelemetryEventsPerOwner));

  const nome = 'telemetry_store_test.db';
  late VisitDatabase db;
  setUp(() async {
    await EncryptedLocalDatabase.deleteDatabaseFile(nome);
    db = VisitDatabase(
      keyStore: InMemoryDatabaseKeyStore(),
      databaseName: nome,
      allowUnencryptedForTesting: true,
    );
  });
  tearDown(() async {
    await db.close();
    await EncryptedLocalDatabase.deleteDatabaseFile(nome);
  });

  _contrato(
    'SqlCipherTelemetryStore',
    ({int? teto}) async => SqlCipherTelemetryStore(db, maxPerOwner: teto ?? maxTelemetryEventsPerOwner),
  );

  group('SqlCipherTelemetryStore', () {
    test('dono vazio dá ArgumentError', () async {
      final store = SqlCipherTelemetryStore(db);
      final e = _evento('v', '  ', DateTime.utc(2026));
      expect(() => store.append(e), throwsArgumentError);
      expect(() => store.oldestForOwner('', limit: 1), throwsArgumentError);
      expect(() => store.countForOwner(' '), throwsArgumentError);
    });

    test('wipeAllData com só telemetria não é WipeBlocked e apaga a telemetria', () async {
      final store = SqlCipherTelemetryStore(db);
      await store.append(_evento('a1', 'acs-a', DateTime.utc(2026)));

      await db.wipeAllData();

      expect(await store.countForOwner('acs-a'), 0);
    });

    test('visita não enviada ainda bloqueia o wipe e a telemetria fica', () async {
      final store = SqlCipherTelemetryStore(db);
      await store.append(_evento('a1', 'acs-a', DateTime.utc(2026)));
      final conn = await db.open();
      await conn.insert('offline_visits', {
        'local_id': 'l1',
        'patient_id': seedPatientId,
        'risk': 'red',
        'status': 'PENDENTE',
        'outcome': '',
        'created_at': DateTime.utc(2026).toIso8601String(),
        'version': 1,
        'owner': 'acs-a',
      });

      await expectLater(db.wipeAllData(), throwsA(isA<WipeBlocked>()));
      expect(await store.countForOwner('acs-a'), 1);
    });
  });

  // Limpeza remota (#81): `VisitDatabase.open()` reabre depois do `destroy`,
  // com chave e arquivo novos. O selo do store impede que um evento tardio
  // (um `sync_result` que volta da rede depois, um flush em voo) recrie o
  // banco que a coordenação mandou apagar.
  group('SqlCipherTelemetryStore selado (#81)', () {
    const seladoNome = 'telemetry_store_seal_test.db';
    late _ChaveContada chave;
    late VisitDatabase contado;
    var aberturas = 0;

    setUp(() async {
      await EncryptedLocalDatabase.deleteDatabaseFile(seladoNome);
      aberturas = 0;
      chave = _ChaveContada();
      contado = VisitDatabase(
        keyStore: chave,
        databaseName: seladoNome,
        allowUnencryptedForTesting: true,
        opener: (nome, senha, semCifra) {
          aberturas++;
          return EncryptedLocalDatabase.open(
            databaseName: nome,
            passphrase: senha,
            allowUnencryptedForTesting: semCifra,
          );
        },
      );
    });
    tearDown(() async {
      await contado.close();
      await EncryptedLocalDatabase.deleteDatabaseFile(seladoNome);
    });

    test('com o selo fechado, nenhuma operação abre o banco', () async {
      final store = SqlCipherTelemetryStore(contado)..seal();

      await store.append(_evento('a1', 'acs-a', DateTime.utc(2026)));
      expect(await store.oldestForOwner('acs-a', limit: 10), isEmpty);
      await store.deleteByIds(['a1']);
      expect(await store.countForOwner('acs-a'), 0);

      expect(aberturas, 0);
    });

    test('append tardio depois do destroy não recria arquivo nem chave', () async {
      final store = SqlCipherTelemetryStore(contado);
      await store.append(_evento('a1', 'acs-a', DateTime.utc(2026)));
      expect(aberturas, 1);

      store.seal();
      await contado.destroy();
      await store.append(_evento('tarde', 'acs-a', DateTime.utc(2026)));
      await store.oldestForOwner('acs-a', limit: 10);

      expect(aberturas, 1);
      expect(chave.criadas, 0);
      expect(await File(await EncryptedLocalDatabase.pathFor(seladoNome)).exists(), isFalse);
    });

    test('reaberto o selo, volta a gravar', () async {
      final store = SqlCipherTelemetryStore(contado)..seal();
      await store.append(_evento('perdido', 'acs-a', DateTime.utc(2026)));

      store.unseal();
      await store.append(_evento('a1', 'acs-a', DateTime.utc(2026)));

      expect((await store.oldestForOwner('acs-a', limit: 10)).map((e) => e.eventId), ['a1']);
      expect(await store.countForOwner('acs-a'), 1);
      await store.deleteByIds(['a1']);
      expect(await store.countForOwner('acs-a'), 0);
    });
  });
}

/// Conta as chaves NOVAS criadas depois de um `delete` (o `destroy` apaga a
/// chave; uma reabertura tardia criaria outra).
class _ChaveContada extends InMemoryDatabaseKeyStore {
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
