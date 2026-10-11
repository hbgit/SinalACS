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
    final idsA = {a.microAreaId, a.acs.id, a.secondAcs.id, ...a.patients.map((p) => p.id)};
    final idsB = {b.microAreaId, b.acs.id, b.secondAcs.id, ...b.patients.map((p) => p.id)};
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
    for (final id in [f.ubsId, f.microAreaId, f.otherMicroAreaId, f.acs.id, f.secondAcs.id, f.staff.id, ...f.patients.map((p) => p.id)]) {
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
    final texto = '$f ${f.patients.first} ${f.acs} ${f.secondAcs}';
    for (final p in f.patients) {
      expect(texto.contains(p.cpf), isFalse);
    }
    expect(texto.contains(f.acs.password), isFalse);
    expect(texto.contains(f.secondAcs.password), isFalse);
  });

  test('há um segundo ACS, distinto do primeiro (id, matrícula e senha), para a fila por dono', () {
    for (var seed = 0; seed < 200; seed++) {
      final f = generateE2eFixtures(Random(seed));
      expect(f.secondAcs.id, isNot(f.acs.id));
      expect(f.secondAcs.matricula, isNot(f.acs.matricula), reason: 'seed $seed');
      expect(f.secondAcs.password, isNot(f.acs.password));
      expect(f.secondAcs.matricula, startsWith('E2E-'));
    }
    final f = generateE2eFixtures(Random(11));
    expect(f.toJson()['acsB'], f.secondAcs.toJson());
  });

  test('há um admin do backoffice, distinto dos ACS, com matrícula própria e sem vazar a senha', () {
    for (var seed = 0; seed < 200; seed++) {
      final f = generateE2eFixtures(Random(seed));
      expect({f.staff.id, f.acs.id, f.secondAcs.id}, hasLength(3), reason: 'seed $seed');
      expect(f.staff.matricula, startsWith('E2E-ADM-'));
      expect({f.staff.matricula, f.acs.matricula, f.secondAcs.matricula}, hasLength(3));
      expect({f.staff.password, f.acs.password, f.secondAcs.password}, hasLength(3));
    }
    final f = generateE2eFixtures(Random(12));
    expect(f.toJson()['staff'], f.staff.toJson());
    expect(E2eFixtures.fromJson(f.toJson()).staff.matricula, f.staff.matricula);
    expect('$f ${f.staff}'.contains(f.staff.password), isFalse);
  });

  test('há um coordenador do backoffice (#43), distinto do admin e dos ACS, com código próprio', () {
    for (var seed = 0; seed < 200; seed++) {
      final f = generateE2eFixtures(Random(seed));
      expect({f.coordinator.id, f.staff.id, f.acs.id, f.secondAcs.id}, hasLength(4), reason: 'seed $seed');
      // Prefixo próprio: as matrículas de staff vivem na MESMA tabela, com
      // índice único — colidir aqui seria um seed que falha no meio.
      expect(f.coordinator.matricula, startsWith('E2E-COORD-'), reason: 'seed $seed');
      expect(
        {f.coordinator.matricula, f.staff.matricula, f.acs.matricula, f.secondAcs.matricula},
        hasLength(4),
        reason: 'seed $seed',
      );
      expect({f.coordinator.password, f.staff.password, f.acs.password, f.secondAcs.password}, hasLength(4));
      expect(f.coordinator.activationCode, isNot(f.staff.activationCode));
    }
    final f = generateE2eFixtures(Random(41));
    expect(f.toJson()['coordinator'], f.coordinator.toJson());
    expect(E2eFixtures.fromJson(f.toJson()).coordinator.matricula, f.coordinator.matricula);
    // Nem a senha nem o código de ativação saem no toString.
    expect('$f ${f.coordinator}'.contains(f.coordinator.password), isFalse);
    expect('${f.coordinator}'.contains(f.coordinator.activationCode), isFalse);
  });

  test('o staff traz um código de ativação (#48) no formato da CLI, novo a cada execução e fora do toString', () {
    final a = generateE2eFixtures(Random(21)).staff;
    final b = generateE2eFixtures(Random(22)).staff;
    expect(a.activationCode, matches(RegExp(r'^([A-Z2-7]{4}-){6}[A-Z2-7]{2}$')));
    expect(a.activationCode, isNot(b.activationCode));
    expect(a.toJson()['activationCode'], a.activationCode);
    expect(E2eStaff.fromJson(a.toJson()).activationCode, a.activationCode);
    expect('$a'.contains(a.activationCode), isFalse);
  });

  test('o painel do admin (#40) tem 3 alertas de fixture, com ids v4 distintos e que sobrevivem ao JSON', () {
    final f = generateE2eFixtures(Random(31));
    expect(f.adminAlertIds, hasLength(3));
    expect(f.adminAlertIds.toSet(), hasLength(3));
    for (final id in f.adminAlertIds) {
      expect(id.startsWith('00000000-0000-4000-8000'), isFalse);
      expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(id), isTrue);
    }
    expect(E2eFixtures.fromJson(f.toJson()).adminAlertIds, f.adminAlertIds);
    final ids = {f.staff.id, f.acs.id, f.secondAcs.id, ...f.patients.map((p) => p.id), ...f.adminAlertIds};
    expect(ids, hasLength(3 + f.patients.length + 3), reason: 'nenhum id repetido entre as entidades');
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
