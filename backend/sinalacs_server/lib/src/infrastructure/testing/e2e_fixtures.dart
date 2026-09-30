import 'dart:math';

/// Dados SINTÉTICOS de uma execução de e2e. Nada aqui é estável entre
/// execuções: UUIDs e CPFs mudam a cada chamada (quem precisa deles lê o
/// manifesto). Nunca um dado real (LGPD).
class E2ePatient {
  const E2ePatient({
    required this.id,
    required this.role,
    required this.name,
    required this.cpf,
    required this.birthDate,
    required this.chronic,
    required this.microAreaId,
  });

  final String id;

  /// `main` e `chronic` (jornada pela tela), `api` (testes sem tela), `push`
  /// (testes de push) ou `outsider` (outra microárea).
  final String role;
  final String name;

  /// Só dígitos; nunca em log nem em mensagem de erro.
  final String cpf;

  /// AAAA-MM-DD.
  final String birthDate;
  final bool chronic;
  final String microAreaId;

  Map<String, Object?> toJson() => {
        'id': id,
        'role': role,
        'name': name,
        'cpf': cpf,
        'birthDate': birthDate,
        'chronic': chronic,
        'microAreaId': microAreaId,
      };

  factory E2ePatient.fromJson(Map<String, Object?> j) => E2ePatient(
        id: j['id']! as String,
        role: j['role']! as String,
        name: j['name']! as String,
        cpf: j['cpf']! as String,
        birthDate: j['birthDate']! as String,
        chronic: j['chronic']! as bool,
        microAreaId: j['microAreaId']! as String,
      );

  @override
  String toString() => 'E2ePatient($role)';
}

class E2eAcs {
  const E2eAcs({required this.id, required this.matricula, required this.password});

  final String id;
  final String matricula;
  final String password;

  Map<String, Object?> toJson() => {'id': id, 'matricula': matricula, 'password': password};

  factory E2eAcs.fromJson(Map<String, Object?> j) => E2eAcs(
        id: j['id']! as String,
        matricula: j['matricula']! as String,
        password: j['password']! as String,
      );

  @override
  String toString() => 'E2eAcs(${id.substring(0, 8)}…)';
}

class E2eFixtures {
  const E2eFixtures({
    required this.ubsId,
    required this.microAreaId,
    required this.otherMicroAreaId,
    required this.acs,
    required this.patients,
  });

  final String ubsId;
  final String microAreaId;
  final String otherMicroAreaId;
  final E2eAcs acs;
  final List<E2ePatient> patients;

  E2ePatient byRole(String role) => patients.singleWhere((p) => p.role == role);

  Map<String, Object?> toJson() => {
        'ubsId': ubsId,
        'microAreaId': microAreaId,
        'otherMicroAreaId': otherMicroAreaId,
        'acs': acs.toJson(),
        'patients': [for (final p in patients) p.toJson()],
      };

  factory E2eFixtures.fromJson(Map<String, Object?> j) => E2eFixtures(
        ubsId: j['ubsId']! as String,
        microAreaId: j['microAreaId']! as String,
        otherMicroAreaId: j['otherMicroAreaId']! as String,
        acs: E2eAcs.fromJson((j['acs']! as Map).cast<String, Object?>()),
        patients: [
          for (final p in (j['patients']! as List)) E2ePatient.fromJson((p as Map).cast<String, Object?>()),
        ],
      );

  @override
  String toString() => 'E2eFixtures(${patients.length} pacientes)';
}

String generateUuidV4(Random random) {
  String hex(int n) => List.generate(n, (_) => random.nextInt(16).toRadixString(16)).join();
  final variant = '89ab'[random.nextInt(4)];
  return '${hex(8)}-${hex(4)}-4${hex(3)}-$variant${hex(3)}-${hex(12)}';
}

/// 11 dígitos com os dois dígitos verificadores corretos e sem todos iguais.
String generateValidCpfDigits(Random random) {
  int dv(List<int> base) {
    var sum = 0;
    for (var i = 0; i < base.length; i++) {
      sum += base[i] * (base.length + 1 - i);
    }
    final r = (sum * 10) % 11;
    return r == 10 ? 0 : r;
  }

  while (true) {
    final d = List<int>.generate(9, (_) => random.nextInt(10));
    if (d.toSet().length == 1) continue;
    final d1 = dv(d);
    final d2 = dv([...d, d1]);
    return [...d, d1, d2].join();
  }
}

String _birthDate(Random random) {
  final year = 1950 + random.nextInt(50);
  final month = (1 + random.nextInt(12)).toString().padLeft(2, '0');
  final day = (1 + random.nextInt(28)).toString().padLeft(2, '0');
  return '$year-$month-$day';
}

String _password(Random random) {
  const alphabet = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  return List.generate(20, (_) => alphabet[random.nextInt(alphabet.length)]).join();
}

E2eFixtures generateE2eFixtures(Random random) {
  final microAreaId = generateUuidV4(random);
  final otherMicroAreaId = generateUuidV4(random);
  final usedCpfs = <String>{};
  E2ePatient patient(String role, String name, {required bool chronic, required String microAreaId}) {
    String cpf;
    do {
      cpf = generateValidCpfDigits(random);
    } while (!usedCpfs.add(cpf));
    return E2ePatient(
      id: generateUuidV4(random),
      role: role,
      name: name,
      cpf: cpf,
      birthDate: _birthDate(random),
      chronic: chronic,
      microAreaId: microAreaId,
    );
  }

  return E2eFixtures(
    ubsId: generateUuidV4(random),
    microAreaId: microAreaId,
    otherMicroAreaId: otherMicroAreaId,
    acs: E2eAcs(
      id: generateUuidV4(random),
      matricula: 'E2E-${1000 + random.nextInt(9000)}',
      password: _password(random),
    ),
    patients: [
      patient('main', 'Paciente E2E Principal', chronic: false, microAreaId: microAreaId),
      patient('chronic', 'Paciente E2E Crônico', chronic: true, microAreaId: microAreaId),
      // Um paciente por consumidor: o OTP impõe 60 s entre dois pedidos do MESMO
      // paciente, então testes que rodam em sequência não podem dividir um.
      patient('api', 'Paciente E2E API', chronic: false, microAreaId: microAreaId),
      patient('push', 'Paciente E2E Push', chronic: false, microAreaId: microAreaId),
      patient('outsider', 'Paciente E2E Outra Área', chronic: false, microAreaId: otherMicroAreaId),
    ],
  );
}
