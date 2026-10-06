import 'dart:io';
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
    required this.secondAcs,
    required this.patients,
  });

  final String ubsId;
  final String microAreaId;
  final String otherMicroAreaId;
  final E2eAcs acs;

  /// Segundo ACS, na MESMA microárea de [acs]: prova no aparelho que a fila
  /// offline é por dono (B não vê nem envia as visitas de A) e que o envio
  /// diferido sobe as visitas de A com a autoria de A.
  final E2eAcs secondAcs;
  final List<E2ePatient> patients;

  E2ePatient byRole(String role) => patients.singleWhere((p) => p.role == role);

  Map<String, Object?> toJson() => {
        'ubsId': ubsId,
        'microAreaId': microAreaId,
        'otherMicroAreaId': otherMicroAreaId,
        'acs': acs.toJson(),
        'acsB': secondAcs.toJson(),
        'patients': [for (final p in patients) p.toJson()],
      };

  factory E2eFixtures.fromJson(Map<String, Object?> j) => E2eFixtures(
        ubsId: j['ubsId']! as String,
        microAreaId: j['microAreaId']! as String,
        otherMicroAreaId: j['otherMicroAreaId']! as String,
        acs: E2eAcs.fromJson((j['acs']! as Map).cast<String, Object?>()),
        secondAcs: E2eAcs.fromJson((j['acsB']! as Map).cast<String, Object?>()),
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

  final acs = E2eAcs(
    id: generateUuidV4(random),
    matricula: 'E2E-${1000 + random.nextInt(9000)}',
    password: _password(random),
  );
  String matriculaB;
  do {
    matriculaB = 'E2E-${1000 + random.nextInt(9000)}';
  } while (matriculaB == acs.matricula);

  return E2eFixtures(
    ubsId: generateUuidV4(random),
    microAreaId: microAreaId,
    otherMicroAreaId: otherMicroAreaId,
    acs: acs,
    secondAcs: E2eAcs(
      id: generateUuidV4(random),
      matricula: matriculaB,
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

/// Por que o seed de e2e deve RECUSAR rodar neste ambiente, ou `null` se pode.
///
/// Só escreve no banco `sinalacs_e2e` do `postgres-test` local (publicado em
/// `localhost:9090`): o nome sozinho não basta, porque um banco de mesmo nome em
/// outro servidor passaria. Exigir host local e a porta do `postgres-test` fecha
/// esse caminho (o banco de desenvolvimento fica em `postgres:5432`).
String? e2eSeedRefusal(Map<String, String> env) {
  if ((env['APP_ENV'] ?? 'development') != 'development') {
    return 'APP_ENV=${env['APP_ENV']}; este seed é só de desenvolvimento.';
  }
  if (env['SERVERPOD_DATABASE_NAME'] != 'sinalacs_e2e') {
    return 'este seed só escreve no banco sinalacs_e2e.';
  }
  final host = (env['SERVERPOD_DATABASE_HOST'] ?? 'localhost').toLowerCase();
  if (host != 'localhost' && host != '127.0.0.1') {
    return 'o host do banco deve ser local (localhost ou 127.0.0.1), e não "$host".';
  }
  if ((env['SERVERPOD_DATABASE_PORT'] ?? '9090') != '9090') {
    return 'a porta do banco deve ser a 9090 do postgres-test.';
  }
  if ((env['SERVERPOD_DATABASE_PASSWORD'] ?? '').isEmpty) {
    return 'SERVERPOD_DATABASE_PASSWORD não definida.';
  }
  return null;
}

/// Grava o manifesto já PRIVADO: o diretório em 0700 e o arquivo em 0600 ANTES de
/// receber o conteúdo (criar com o umask e só depois restringir deixaria uma
/// janela em que a senha do ACS é legível por outros usuários da máquina).
void writeManifestPrivately(File file, String content) {
  file.parent.createSync(recursive: true);
  _chmod('700', file.parent.path);
  if (!file.existsSync()) file.createSync();
  _chmod('600', file.path);
  file.writeAsStringSync(content);
}

void _chmod(String mode, String path) {
  final result = Process.runSync('chmod', [mode, path]);
  if (result.exitCode != 0) {
    throw StateError('chmod $mode falhou em $path: ${result.stderr}'.trim());
  }
}
