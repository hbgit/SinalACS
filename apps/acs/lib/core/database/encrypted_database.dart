import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

class EncryptedLocalDatabase {
  EncryptedLocalDatabase._();

  static Future<Database> open({
    required String databaseName,
    required String passphrase,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      sqfliteFfiInit();
    }

    final databasePath = Platform.isAndroid || Platform.isIOS
        ? await sqlcipher.getDatabasesPath()
        : await databaseFactoryFfi.getDatabasesPath();
    final dbPath = '$databasePath/$databaseName';

    if (Platform.isAndroid || Platform.isIOS) {
      return sqlcipher.openDatabase(
        dbPath,
        password: passphrase,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE IF NOT EXISTS local_queue (id TEXT PRIMARY KEY)');
        },
      );
    }

    return databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE IF NOT EXISTS local_queue (id TEXT PRIMARY KEY)');
        },
      ),
    );
  }
}
