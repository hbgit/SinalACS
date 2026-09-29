import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/core/consent/sqflite_consent_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SqfliteConsentPreferences store;

  setUp(() {
    // Banco em memória por teste — mesmo padrão de sqflite_reminder_store_test.dart.
    store = SqfliteConsentPreferences(databaseName: inMemoryDatabasePath);
  });

  tearDown(() => store.close());

  test('sem registro local, retorna null (nem aceite nem recusa)', () async {
    expect(await store.localRemindersGranted(), isNull);
  });

  test('grava aceite e recupera', () async {
    await store.saveLocalRemindersConsent(true);
    expect(await store.localRemindersGranted(), isTrue);
  });

  test('grava recusa e recupera', () async {
    await store.saveLocalRemindersConsent(true);
    await store.saveLocalRemindersConsent(false);
    expect(await store.localRemindersGranted(), isFalse);
  });

  test('gravar de novo substitui o valor anterior sem duplicar linha', () async {
    await store.saveLocalRemindersConsent(false);
    await store.saveLocalRemindersConsent(true);
    await store.saveLocalRemindersConsent(true);
    expect(await store.localRemindersGranted(), isTrue);
  });
}
