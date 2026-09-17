import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/database/encrypted_database.dart';
import 'package:sinalacs_acs/core/database/sync_cursor_store.dart';
import 'package:sinalacs_acs/core/security/database_key_store.dart';

/// Roda na VM, onde o SQLCipher não existe — por isso `allowUnencryptedForTesting`.
/// Mesmo padrão de `encrypted_database_test.dart`/`SqlCipherVisitStore`: prova a
/// lógica de persistência, não a criptografia (isso vive em `integration_test/`).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SyncCursorStore', () {
    const nome = 'sync_cursor_test.db';

    setUp(() => EncryptedLocalDatabase.deleteDatabaseFile(nome));
    tearDown(() => EncryptedLocalDatabase.deleteDatabaseFile(nome));

    test('sem cursor gravado, read() devolve null', () async {
      final store = SyncCursorStore(
        keyStore: InMemoryDatabaseKeyStore(),
        databaseName: nome,
        allowUnencryptedForTesting: true,
      );

      expect(await store.read(), isNull);
    });

    test('write grava e um read seguinte devolve o mesmo valor', () async {
      final store = SyncCursorStore(
        keyStore: InMemoryDatabaseKeyStore(),
        databaseName: nome,
        allowUnencryptedForTesting: true,
      );
      final since = DateTime.utc(2026, 9, 17, 12, 30);

      await store.write(since);

      expect(await store.read(), since);
    });

    test('uma nova instância apontando para o mesmo arquivo lê o cursor gravado pela anterior', () async {
      final keyStore = InMemoryDatabaseKeyStore();
      final first = SyncCursorStore(
        keyStore: keyStore,
        databaseName: nome,
        allowUnencryptedForTesting: true,
      );
      final since = DateTime.utc(2026, 9, 1);
      await first.write(since);

      final second = SyncCursorStore(
        keyStore: keyStore,
        databaseName: nome,
        allowUnencryptedForTesting: true,
      );

      expect(await second.read(), since);
    });

    test('escrever de novo substitui o cursor anterior', () async {
      final store = SyncCursorStore(
        keyStore: InMemoryDatabaseKeyStore(),
        databaseName: nome,
        allowUnencryptedForTesting: true,
      );

      await store.write(DateTime.utc(2026, 1, 1));
      await store.write(DateTime.utc(2026, 6, 1));

      expect(await store.read(), DateTime.utc(2026, 6, 1));
    });
  });
}
