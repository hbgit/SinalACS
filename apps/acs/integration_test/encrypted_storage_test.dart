/// Prova de que o banco local está **realmente** cifrado.
///
/// É o único teste do repositório que verifica isso, e só funciona em
/// dispositivo: no Linux o `flutter test` cai no FFI, onde o SQLCipher não
/// existe. Foi essa distinção que faltou no teste original — ele se chamava
/// "deve abrir banco criptografado com senha configurada" e, no CI, exercitava
/// o caminho sem criptografia nenhuma.
///
///   flutter test integration_test/encrypted_storage_test.dart
///
/// Responde ao risco nomeado em spec/test_plan.md:51 — "o roubo do celular do
/// ACS não pode resultar em vazamento da base territorial" — e ao INV-04 do PRD.
///
/// PRIVACIDADE: usa um marcador e um UUID sintéticos, nunca dado real.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sinalacs_acs/core/database/encrypted_database.dart';
import 'package:sinalacs_acs/core/database/sqlcipher_visit_store.dart';
import 'package:sinalacs_acs/core/security/database_key_store.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

import 'support/legacy_v6.dart';

/// Marcador sintético que precisa NÃO aparecer no arquivo.
const marcador = 'MARCADOR-SINTETICO-NAO-DEVE-VAZAR';

/// UUID do paciente no seed de desenvolvimento. Dado sintético.
///
/// Desde que o registro guarda o identificador em vez de um rótulo truncado,
/// provar que ELE não vaza vale mais do que provar que o rótulo não vazava.
const seedPatientId = '00000000-0000-4000-8000-000000000001';

const databaseName = 'sinalacs_crypto_probe.db';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => EncryptedLocalDatabase.deleteDatabaseFile(databaseName));

  test('o arquivo do banco não contém o conteúdo da visita em texto plano', () async {
    final store = SqlCipherVisitStore(
      owner: 'acs-teste',
      keyStore: InMemoryDatabaseKeyStore(),
      databaseName: databaseName,
    );

    await store.save([
      OfflineVisitRecord(
        patientId: seedPatientId,
        risk: 'red',
        status: 'PENDENTE',
        // O desfecho também é conteúdo clínico, e é onde o marcador cabe agora
        // que o campo do paciente só aceita UUID.
        outcome: marcador,
      ),
    ]);
    // Fechar garante que tudo foi para o disco, e não ficou só no WAL em memória.
    await store.close();

    final file = File(await EncryptedLocalDatabase.pathFor(databaseName));
    expect(await file.exists(), isTrue, reason: 'o banco não foi criado');

    final bytes = await file.readAsBytes();
    expect(bytes, isNotEmpty);

    // 1. Um SQLite em claro começa com o cabeçalho "SQLite format 3\0".
    //    Um banco cifrado pelo SQLCipher não tem esse cabeçalho.
    final header = String.fromCharCodes(bytes.take(15));
    expect(
      header,
      isNot('SQLite format 3'),
      reason: 'o banco está em texto plano — viola o INV-04 do PRD',
    );

    // 2. O conteúdo gravado não pode ser legível no arquivo.
    final conteudo = String.fromCharCodes(bytes);
    expect(
      conteudo.contains(marcador),
      isFalse,
      reason: 'o conteúdo da visita aparece legível no arquivo do banco',
    );

    // 3. Nem o identificador do paciente, que é o que o registro passou a
    //    guardar para poder sincronizar.
    expect(
      conteudo.contains(seedPatientId),
      isFalse,
      reason: 'o identificador do paciente aparece legível no arquivo do banco',
    );

    await EncryptedLocalDatabase.deleteDatabaseFile(databaseName);
  });

  test('o banco não abre com a chave errada', () async {
    // Se abrisse, a criptografia não estaria protegendo nada.
    final store = SqlCipherVisitStore(
      owner: 'acs-teste',
      keyStore: InMemoryDatabaseKeyStore(initialKey: generateDatabaseKey()),
      databaseName: databaseName,
    );
    await store.save([
      OfflineVisitRecord(patientId: seedPatientId, risk: 'red', status: 'PENDENTE'),
    ]);
    await store.close();

    // Abertura direta com outra chave, sem passar pela recuperação automática
    // do SqlCipherVisitStore (que apagaria o arquivo e recomeçaria).
    expect(
      () => EncryptedLocalDatabase.open(
        databaseName: databaseName,
        passphrase: generateDatabaseKey(),
      ),
      throwsA(anything),
    );

    await EncryptedLocalDatabase.deleteDatabaseFile(databaseName);
  });

  test('o banco v1 de uma versão anterior migra sem travar o app', () async {
    // O caminho de upgrade do sqflite_sqlcipher não é o do FFI, então só aqui
    // isto se prova. A versão anterior do app criava `local_queue`; abrir esse
    // arquivo sem migração deixaria a fila sem a tabela que ela lê, e o ACS
    // veria "as visitas não estão sendo salvas" a cada abertura.
    final key = generateDatabaseKey();
    final path = await EncryptedLocalDatabase.pathFor(databaseName);

    final legado = await sqlcipher.openDatabase(
      path,
      password: key,
      version: 1,
      onCreate: (db, version) =>
          db.execute('CREATE TABLE IF NOT EXISTS local_queue (id TEXT PRIMARY KEY)'),
    );
    await legado.insert('local_queue', {'id': 'antigo'});
    await legado.close();

    final store = SqlCipherVisitStore(
      owner: 'acs-teste',
      keyStore: InMemoryDatabaseKeyStore(initialKey: key),
      databaseName: databaseName,
    );

    // Se a migração lançasse, o `catch` do store apagaria o arquivo e isto
    // passaria mesmo assim — por isso o teste também grava e relê.
    expect(await store.load(), isEmpty);
    await store.save([
      OfflineVisitRecord(patientId: seedPatientId, risk: 'red', status: 'PENDENTE'),
    ]);
    expect((await store.load()).single.patientId, seedPatientId);
    await store.close();

    await EncryptedLocalDatabase.deleteDatabaseFile(databaseName);
  });

  test('chave perdida: o app recomeça em vez de travar', () async {
    // Reinstalação ou restauração de backup deixa o arquivo sem a chave
    // correspondente. Sem recuperação, o app ficaria travado para sempre.
    final keyStore = InMemoryDatabaseKeyStore();
    final first = SqlCipherVisitStore(
      owner: 'acs-teste',
      keyStore: keyStore,
      databaseName: databaseName,
    );
    await first.save([
      OfflineVisitRecord(patientId: seedPatientId, risk: 'red', status: 'PENDENTE'),
    ]);
    await first.close();

    // A chave some, o arquivo fica.
    await keyStore.delete();

    final second = SqlCipherVisitStore(
      owner: 'acs-teste',
      keyStore: keyStore,
      databaseName: databaseName,
    );

    // Não lança: descarta o arquivo ilegível e recomeça vazio.
    expect(await second.load(), isEmpty);
    await second.close();

    await EncryptedLocalDatabase.deleteDatabaseFile(databaseName);
  });

  // ---- Fila por dono (schema v7) no SQLCipher real -------------------------
  //
  // Mesma lógica de test/visit_storage_owner_test.dart, mas no caminho do
  // sqflite_sqlcipher (ALTER/upgrade e transações no arquivo cifrado), que o
  // `flutter test` na VM não exercita.

  test('dois donos e a quarentena no mesmo arquivo: B grava e limpa sem tocar em A nem no legado', () async {
    final key = generateDatabaseKey();
    await createV6Database(
      databaseName: databaseName,
      passphrase: key,
      rows: [legacyV6Row(localId: 'legado-1', patientId: seedPatientId, notes: '$marcador-LEGADO')],
    );
    final storage = SqlCipherVisitStorage(
      keyStore: InMemoryDatabaseKeyStore(initialKey: key),
      databaseName: databaseName,
    );
    final a = storage.forOwner('acs-a');
    final b = storage.forOwner('acs-b');

    final visitaA1 = OfflineVisitRecord(patientId: seedPatientId, risk: 'red', status: 'PENDENTE', notes: '$marcador-A1');
    final visitaA2 = OfflineVisitRecord(
      patientId: seedPatientId,
      risk: 'yellow',
      status: 'PENDENTE',
      rejectionReason: 'recusada (sintético)',
    );
    await a.save([visitaA1, visitaA2]);
    final visitaB = OfflineVisitRecord(patientId: seedPatientId, risk: 'green', status: 'PENDENTE', notes: '$marcador-B');
    await b.save([visitaB]);

    // Cada dono vê só as suas; a quarentena só pelo legado.
    expect((await a.load()).map((v) => v.localId).toSet(), {visitaA1.localId, visitaA2.localId});
    expect((await b.load()).map((v) => v.localId), [visitaB.localId]);
    expect((await storage.legacy.load()).map((v) => v.localId), ['legado-1']);
    expect(await storage.countsByOwner(), {'acs-a': 2, 'acs-b': 1}, reason: 'a quarentena não é de dono nenhum');
    expect((await a.load()).firstWhere((v) => v.localId == visitaA2.localId).rejectionReason, 'recusada (sintético)');

    // B tenta gravar um localId de A: tudo ou nada, a linha de A fica.
    await expectLater(b.save([visitaB, visitaA1]), throwsA(isA<VisitLocalIdConflict>()));
    // ...e um localId da quarentena: idem.
    await expectLater(
      b.save([OfflineVisitRecord(localId: 'legado-1', patientId: seedPatientId, risk: 'red', status: 'PENDENTE')]),
      throwsA(isA<VisitLocalIdConflict>()),
    );
    expect((await b.load()).map((v) => v.localId), [visitaB.localId], reason: 'a gravação recusada foi desfeita');
    expect(await a.load(), hasLength(2));

    // B limpa a própria fila (o que a fila faz depois de sincronizar tudo).
    await b.save([]);
    expect(await b.load(), isEmpty);
    expect(await a.load(), hasLength(2), reason: 'o save de B nunca apaga linhas de A');
    expect(await storage.legacy.load(), hasLength(1), reason: 'nem da quarentena');

    // A remoção legada por localId não alcança linhas com dono.
    await storage.legacy.remove([visitaA1.localId]);
    expect(await a.load(), hasLength(2));

    await storage.close();

    // Nenhuma nota (de A, de B, do legado) nem o UUID do paciente em claro.
    final bytes = await File(await EncryptedLocalDatabase.pathFor(databaseName)).readAsBytes();
    final conteudo = String.fromCharCodes(bytes);
    expect(String.fromCharCodes(bytes.take(15)), isNot('SQLite format 3'));
    expect(conteudo.contains(marcador), isFalse, reason: 'texto de nota legível no arquivo');
    expect(conteudo.contains(seedPatientId), isFalse);
    expect(conteudo.contains('acs-a'), isFalse, reason: 'nem o dono');

    await EncryptedLocalDatabase.deleteDatabaseFile(databaseName);
  });

  test('banco v6 criado no aparelho migra para v7: as linhas vão para a QUARENTENA, cache e cursor ficam', () async {
    final key = generateDatabaseKey();
    await createV6Database(
      databaseName: databaseName,
      passphrase: key,
      rows: [
        legacyV6Row(localId: 'v6-pendente', patientId: seedPatientId, notes: '$marcador-V6'),
        legacyV6Row(
          localId: 'v6-recusada',
          patientId: seedPatientId,
          rejectionReason: 'fora da microárea (sintético)',
          createdAt: DateTime.utc(2026, 9, 2),
        ),
      ],
      cacheRows: [
        {'patient_id': seedPatientId, 'name': 'Paciente Sintético', 'is_chronic': 0, 'chronic_conditions': '[]'},
      ],
      cursor: {'pull|acs-antigo': '2026-09-01T00:00:00.000Z'},
    );

    // Antes: v6, sem `owner`.
    final antes = await sqlcipher.openDatabase(await EncryptedLocalDatabase.pathFor(databaseName), password: key);
    expect(await antes.getVersion(), 6);
    final colunasAntes = await antes.rawQuery("PRAGMA table_info('offline_visits')");
    expect(colunasAntes.any((c) => c['name'] == 'owner'), isFalse);
    await antes.close();

    // Abre pelas classes do app: migra.
    final storage = SqlCipherVisitStorage(
      keyStore: InMemoryDatabaseKeyStore(initialKey: key),
      databaseName: databaseName,
    );
    final legado = await storage.legacy.load();
    expect(legado.map((v) => v.localId), ['v6-pendente', 'v6-recusada'], reason: 'nenhuma linha perdida na migração');
    expect(legado.first.notes, '$marcador-V6', reason: 'conteúdo preservado');
    expect(legado.last.rejectionReason, 'fora da microárea (sintético)');

    // Invisível a QUALQUER dono, inclusive um que grave em seguida.
    for (final dono in ['acs-a', 'acs-b', 'acs-antigo']) {
      expect(await storage.forOwner(dono).load(), isEmpty, reason: '$dono não pode adotar o legado');
    }
    await storage.forOwner('acs-a').save([OfflineVisitRecord(patientId: seedPatientId, risk: 'red', status: 'PENDENTE')]);
    await storage.forOwner('acs-a').save([]);
    expect(await storage.legacy.load(), hasLength(2), reason: 'o save de um dono não apaga a quarentena');
    expect(await storage.countsByOwner(), isEmpty);

    // O schema ficou na v7, com `owner` nulo nas linhas antigas; o resto da v6 intacto.
    final db = await storage.database.open();
    expect(await db.getVersion(), EncryptedLocalDatabase.schemaVersion);
    expect(EncryptedLocalDatabase.schemaVersion, 7);
    final semDono = await db.rawQuery('SELECT COUNT(*) AS n FROM offline_visits WHERE owner IS NULL');
    expect(semDono.single['n'], 2);
    expect((await db.query('micro_area_cache')).single['patient_id'], seedPatientId);
    expect((await db.query('sync_cursor')).single['key'], 'pull|acs-antigo');

    await storage.close();
    final bytes = await File(await EncryptedLocalDatabase.pathFor(databaseName)).readAsBytes();
    expect(String.fromCharCodes(bytes).contains(marcador), isFalse);
    await EncryptedLocalDatabase.deleteDatabaseFile(databaseName);
  });

  test('wipeAllData: recusa com linha recusada, legada ou de outro dono; com tudo enviado apaga as quatro tabelas', () async {
    final key = generateDatabaseKey();
    await createV6Database(
      databaseName: databaseName,
      passphrase: key,
      rows: [legacyV6Row(localId: 'legado-wipe', patientId: seedPatientId)],
      cacheRows: [
        {'patient_id': seedPatientId, 'name': 'Paciente Sintético', 'is_chronic': 0, 'chronic_conditions': '[]'},
      ],
      cursor: {'pull|acs-a': '2026-09-01T00:00:00.000Z'},
    );
    final storage = SqlCipherVisitStorage(
      keyStore: InMemoryDatabaseKeyStore(initialKey: key),
      databaseName: databaseName,
    );
    final a = storage.forOwner('acs-a');
    final b = storage.forOwner('acs-b');
    final db = await storage.database.open();
    await db.insert('micro_area_cache_meta', {'key': 'owner', 'value': 'acs-a|area'});

    Future<Map<String, int>> contagens() async => {
          for (final t in ['offline_visits', 'sync_cursor', 'micro_area_cache', 'micro_area_cache_meta'])
            t: ((await db.rawQuery('SELECT COUNT(*) AS n FROM $t')).single['n']! as int),
        };
    Future<void> recusa(int esperado, String motivo) async {
      final antes = await contagens();
      await expectLater(
        storage.wipeAllData(),
        throwsA(isA<WipeBlocked>().having((e) => e.unsent, 'unsent', esperado)),
        reason: motivo,
      );
      expect(await contagens(), antes, reason: 'recusado = nada apagado ($motivo)');
    }

    // 1) Só o legado (quarentena).
    await recusa(1, 'linha legada');
    await storage.legacy.remove(['legado-wipe']);

    // 2) Só uma visita RECUSADA de A (fora da fila de reenvio, mas não enviada).
    final recusada = OfflineVisitRecord(
      patientId: seedPatientId,
      risk: 'red',
      status: 'PENDENTE',
      rejectionReason: 'recusada (sintético)',
    );
    await a.save([recusada]);
    await recusa(1, 'linha recusada');
    await a.save([]);

    // 3) Só uma pendente de OUTRO dono (B), com A como "sessão atual".
    await b.save([OfflineVisitRecord(patientId: seedPatientId, risk: 'green', status: 'PENDENTE')]);
    await recusa(1, 'linha de outro dono');
    await b.save([]);

    // 4) Tudo enviado: apaga visitas, cursor e cache da microárea.
    expect(await contagens(), {'offline_visits': 0, 'sync_cursor': 1, 'micro_area_cache': 1, 'micro_area_cache_meta': 1});
    await storage.wipeAllData();
    expect(await contagens(), {'offline_visits': 0, 'sync_cursor': 0, 'micro_area_cache': 0, 'micro_area_cache_meta': 0});

    // O arquivo e a chave continuam: o banco segue utilizável depois do wipe.
    await a.save([OfflineVisitRecord(patientId: seedPatientId, risk: 'red', status: 'PENDENTE')]);
    expect(await a.load(), hasLength(1));

    await storage.close();
    await EncryptedLocalDatabase.deleteDatabaseFile(databaseName);
  });
}
