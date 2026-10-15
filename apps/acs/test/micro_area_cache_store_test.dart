import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/database/encrypted_database.dart';
import 'package:sinalacs_acs/core/database/micro_area_cache_store.dart';
import 'package:sinalacs_acs/core/security/database_key_store.dart';
import 'package:sinalacs_client/sinalacs_client.dart' show MicroAreaPatient;

import 'support/fakes.dart';

/// Roda na VM, sem SQLCipher (`allowUnencryptedForTesting`): prova a lógica de
/// persistência e de dono, não a criptografia (isso vive em `integration_test/`).
MicroAreaPatient _paciente(int n, {bool cronico = false}) => MicroAreaPatient(
      patientId: syntheticPatientId(n),
      name: 'Paciente Sintético $n',
      isChronic: cronico,
      chronicConditions: cronico ? ['hipertensão', 'diabetes'] : const [],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const nome = 'micro_area_cache_test.db';
  late MicroAreaCacheStore store;

  setUp(() async {
    await EncryptedLocalDatabase.deleteDatabaseFile(nome);
    store = MicroAreaCacheStore(
      keyStore: InMemoryDatabaseKeyStore(),
      databaseName: nome,
      allowUnencryptedForTesting: true,
    );
  });
  tearDown(() => EncryptedLocalDatabase.deleteDatabaseFile(nome));

  test('sem nada gravado, read devolve null', () async {
    expect(await store.read(owner: 'u1|m1'), isNull);
  });

  test('grava e lê de volta a lista, a data e as condições crônicas', () async {
    final em = DateTime.utc(2026, 10, 2, 8);
    await store.write(owner: 'u1|m1', patients: [_paciente(1), _paciente(2, cronico: true)], at: em);

    final lido = await store.read(owner: 'u1|m1');

    expect(lido!.fetchedAt, em);
    expect(lido.patients.map((p) => p.patientId), [syntheticPatientId(1), syntheticPatientId(2)]);
    expect(lido.patients.last.isChronic, isTrue);
    expect(lido.patients.last.chronicConditions, ['hipertensão', 'diabetes']);
  });

  test('outro dono apaga e não serve', () async {
    await store.write(owner: 'u1|m1', patients: [_paciente(1)], at: DateTime.utc(2026, 10, 2));

    expect(await store.read(owner: 'u2|m1'), isNull, reason: 'outro usuário');
    expect(await store.read(owner: 'u1|m1'), isNull, reason: 'o cache do dono antigo foi APAGADO, não só escondido');
  });

  test('regravar substitui a lista inteira (paciente que saiu da microárea some)', () async {
    await store.write(owner: 'u1|m1', patients: [_paciente(1), _paciente(2)], at: DateTime.utc(2026, 10, 2));
    await store.write(owner: 'u1|m1', patients: [_paciente(2)], at: DateTime.utc(2026, 10, 3));

    final lido = await store.read(owner: 'u1|m1');
    expect(lido!.patients.map((p) => p.patientId), [syntheticPatientId(2)]);
  });

  test('clear apaga tudo', () async {
    await store.write(owner: 'u1|m1', patients: [_paciente(1)], at: DateTime.utc(2026, 10, 2));
    await store.clear();
    expect(await store.read(owner: 'u1|m1'), isNull);
  });
}
