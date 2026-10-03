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

  test('dono: cada ACS vê só as próprias visitas e a quarentena fica isolada', () async {
    // Mesma lógica de test/visit_storage_owner_test.dart, mas sobre SQLCipher
    // de verdade (o caminho de upgrade/ALTER é o do sqflite_sqlcipher).
    final storage = SqlCipherVisitStorage(
      keyStore: InMemoryDatabaseKeyStore(),
      databaseName: databaseName,
    );
    final a = storage.forOwner('acs-a');
    final b = storage.forOwner('acs-b');
    await a.save([
      OfflineVisitRecord(patientId: seedPatientId, risk: 'red', status: 'PENDENTE'),
    ]);

    expect(await b.load(), isEmpty);
    await b.save([]);
    expect(await a.load(), hasLength(1));
    expect(await storage.legacy.load(), isEmpty);

    await storage.close();
    await EncryptedLocalDatabase.deleteDatabaseFile(databaseName);
  });

  test('v6 → v7 cifrado: linhas sem dono ficam em quarentena', () async {
    final key = generateDatabaseKey();
    final path = await EncryptedLocalDatabase.pathFor(databaseName);

    final legado = await sqlcipher.openDatabase(
      path,
      password: key,
      version: 6,
      onCreate: (db, version) => db.execute('''
CREATE TABLE offline_visits (
  local_id TEXT PRIMARY KEY, patient_id TEXT NOT NULL, risk TEXT NOT NULL,
  status TEXT NOT NULL, outcome TEXT NOT NULL, notes TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL, version INTEGER NOT NULL, rejection_reason TEXT
)'''),
    );
    await legado.insert('offline_visits', {
      'local_id': 'local-v6-1',
      'patient_id': seedPatientId,
      'risk': 'red',
      'status': 'PENDENTE',
      'outcome': '',
      'notes': '',
      'created_at': DateTime.utc(2026).toIso8601String(),
      'version': 1,
    });
    await legado.close();

    final storage = SqlCipherVisitStorage(
      keyStore: InMemoryDatabaseKeyStore(initialKey: key),
      databaseName: databaseName,
    );
    expect(await storage.forOwner('acs-a').load(), isEmpty);
    expect((await storage.legacy.load()).map((v) => v.localId), ['local-v6-1']);

    await storage.close();
    await EncryptedLocalDatabase.deleteDatabaseFile(databaseName);
  });
}
