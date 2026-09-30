/// Manifesto das fixtures de e2e (gerado por `bin/seed_e2e_fixtures.dart`).
/// Chega aos testes de dispositivo como UM define JSON
/// (`--dart-define=E2E_FIXTURES="$(cat .e2e/fixtures.json)"`) e às ferramentas do
/// host pelo arquivo `.e2e/fixtures.json`. Não importar em código de produção.
class E2ePatientFixture {
  const E2ePatientFixture({
    required this.role,
    required this.name,
    required this.cpf,
    required this.birthDate,
    required this.microAreaId,
  });

  final String role;
  final String name;

  /// Só dígitos; nunca em log nem em mensagem de erro.
  final String cpf;
  final DateTime birthDate;
  final String microAreaId;

  @override
  String toString() => 'E2ePatientFixture($role)'; // sem CPF
}

class E2eConfig {
  const E2eConfig({
    required this.patients,
    required this.microAreaId,
    required this.acsMatricula,
    required this.acsPassword,
  });

  final List<E2ePatientFixture> patients;
  final String microAreaId;
  final String acsMatricula;
  final String acsPassword;

  E2ePatientFixture patient(String role) => patients.firstWhere(
        (p) => p.role == role,
        orElse: () => throw StateError('sem paciente "$role" no manifesto'),
      );

  static E2eConfig? fromMap(Map<String, Object?> map) {
    final list = map['patients'];
    if (list is! List) return null;
    final acs = (map['acs']! as Map).cast<String, Object?>();
    return E2eConfig(
      patients: [
        for (final raw in list.cast<Map>())
          E2ePatientFixture(
            role: raw['role'] as String,
            name: raw['name'] as String,
            cpf: raw['cpf'] as String,
            birthDate: DateTime.parse(raw['birthDate'] as String),
            microAreaId: raw['microAreaId'] as String,
          ),
      ],
      microAreaId: map['microAreaId']! as String,
      acsMatricula: acs['matricula']! as String,
      acsPassword: acs['password']! as String,
    );
  }

  @override
  String toString() => 'E2eConfig(${patients.length} pacientes)';
}
