import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/database/encrypted_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('deve abrir banco criptografado com senha configurada', () async {
    final db = await EncryptedLocalDatabase.open(
      databaseName: 'sinalacs_acs_test.db',
      passphrase: 'test-passphrase',
    );

    expect(db.isOpen, isTrue);
    await db.execute('CREATE TABLE IF NOT EXISTS test_table (id INTEGER PRIMARY KEY)');
    await db.close();
  });
}
