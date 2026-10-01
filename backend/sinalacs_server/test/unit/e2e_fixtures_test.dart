import 'dart:io';
import 'dart:math';

import 'package:sinalacs_server/src/application/auth/cpf.dart';
import 'package:sinalacs_server/src/infrastructure/testing/e2e_fixtures.dart';
import 'package:test/test.dart';

void main() {
  test('todo CPF gerado tem dígito verificador válido (mil amostras)', () {
    final random = Random(1);
    for (var i = 0; i < 1000; i++) {
      expect(Cpf.tryParse(generateValidCpfDigits(random)), isNotNull);
    }
  });

  test('duas execuções não compartilham UUID nem CPF', () {
    final a = generateE2eFixtures(Random(1));
    final b = generateE2eFixtures(Random(2));
    final idsA = {a.microAreaId, a.acs.id, ...a.patients.map((p) => p.id)};
    final idsB = {b.microAreaId, b.acs.id, ...b.patients.map((p) => p.id)};
    expect(idsA.intersection(idsB), isEmpty);
    expect(a.patients.map((p) => p.cpf).toSet().intersection(b.patients.map((p) => p.cpf).toSet()), isEmpty);
  });

  test('dentro de uma execução tudo é único e o forasteiro está em outra microárea', () {
    final f = generateE2eFixtures(Random(7));
    expect(f.patients.map((p) => p.cpf).toSet(), hasLength(f.patients.length));
    expect(f.patients.map((p) => p.id).toSet(), hasLength(f.patients.length));
    final outsider = f.byRole('outsider');
    expect(outsider.microAreaId, f.otherMicroAreaId);
    expect(f.patients.where((p) => p.role != 'outsider').every((p) => p.microAreaId == f.microAreaId), isTrue);
  });

  test('nenhum UUID é do formato fixo do seed de desenvolvimento', () {
    final f = generateE2eFixtures(Random(3));
    for (final id in [f.ubsId, f.microAreaId, f.otherMicroAreaId, f.acs.id, ...f.patients.map((p) => p.id)]) {
      expect(id.startsWith('00000000-0000-4000-8000'), isFalse);
      expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(id), isTrue);
    }
  });

  test('há um paciente por consumidor: jornada, api, push e forasteiro', () {
    final f = generateE2eFixtures(Random(5));
    expect(f.patients.map((p) => p.role).toSet(), {'main', 'chronic', 'api', 'push', 'outsider'});
    expect(f.patients.singleWhere((p) => p.role == 'chronic').chronic, isTrue);
  });

  test('o manifesto ida e volta é idêntico', () {
    final f = generateE2eFixtures(Random(9));
    expect(E2eFixtures.fromJson(f.toJson()).toJson(), f.toJson());
  });

  test('toString não vaza CPF nem senha', () {
    final f = generateE2eFixtures(Random(4));
    final texto = '$f ${f.patients.first} ${f.acs}';
    for (final p in f.patients) {
      expect(texto.contains(p.cpf), isFalse);
    }
    expect(texto.contains(f.acs.password), isFalse);
  });

  group('guarda do seeder (e2eSeedRefusal)', () {
    const ok = {
      'APP_ENV': 'development',
      'SERVERPOD_DATABASE_NAME': 'sinalacs_e2e',
      'SERVERPOD_DATABASE_HOST': 'localhost',
      'SERVERPOD_DATABASE_PORT': '9090',
      'SERVERPOD_DATABASE_PASSWORD': 'x',
    };

    test('o ambiente esperado passa', () => expect(e2eSeedRefusal(ok), isNull));

    test('recusa outro APP_ENV, outro banco e senha ausente', () {
      expect(e2eSeedRefusal({...ok, 'APP_ENV': 'production'}), contains('APP_ENV'));
      expect(e2eSeedRefusal({...ok, 'SERVERPOD_DATABASE_NAME': 'sinalacs_db'}), contains('sinalacs_e2e'));
      expect(e2eSeedRefusal({...ok}..remove('SERVERPOD_DATABASE_PASSWORD')), contains('PASSWORD'));
    });

    test('recusa um banco de mesmo nome em OUTRO servidor, e a porta do banco de desenvolvimento', () {
      expect(e2eSeedRefusal({...ok, 'SERVERPOD_DATABASE_HOST': 'db.exemplo.interno'}), contains('host'));
      expect(e2eSeedRefusal({...ok, 'SERVERPOD_DATABASE_HOST': 'postgres'}), contains('host'));
      expect(e2eSeedRefusal({...ok, 'SERVERPOD_DATABASE_PORT': '5432'}), contains('9090'));
    });

    test('aceita 127.0.0.1 além de localhost', () {
      expect(e2eSeedRefusal({...ok, 'SERVERPOD_DATABASE_HOST': '127.0.0.1'}), isNull);
    });
  });

  test('o manifesto nasce privado: arquivo 600 e diretório 700, nunca legível por outros', () {
    final dir = Directory.systemTemp.createTempSync('e2e_manifest_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/sub/fixtures.json');

    writeManifestPrivately(file, '{"a":1}');

    expect(file.readAsStringSync(), '{"a":1}');
    expect(file.statSync().mode & 0x1ff, 384, reason: '0600');
    expect(file.parent.statSync().mode & 0x1ff, 448, reason: '0700');
  });
}
