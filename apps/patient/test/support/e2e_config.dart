/// Manifesto das fixtures de e2e (gerado por `bin/seed_e2e_fixtures.dart`).
/// Chega aos testes de dispositivo como UM define JSON
/// (`--dart-define=E2E_FIXTURES="$(cat .e2e/fixtures.json)"`) e às ferramentas do
/// host pelo arquivo `.e2e/fixtures.json`. Não importar em código de produção.
class E2ePatientFixture {
  E2ePatientFixture({
    required this.role,
    required this.name,
    required this.cpf,
    required this.birthDate,
    required this.microAreaId,
    required List<String> inviteTokens,
  }) : _inviteTokens = [...inviteTokens];

  final String role;
  final String name;

  /// Só dígitos; nunca em log nem em mensagem de erro.
  final String cpf;
  final DateTime birthDate;
  final String microAreaId;

  /// Convites de uso único gerados pelo seed (C-05: o login do piloto é por
  /// convite QR + PIN). Um por chamada de [takeInviteToken] — cada processo de
  /// teste consome o seu, sem dividir o mesmo convite entre dois logins.
  final List<String> _inviteTokens;

  /// Pega um convite ainda não usado desta execução. O manifesto do aparelho
  /// é imutável (define de compilação), então o "consumo" é só em memória.
  String takeInviteToken() {
    if (_inviteTokens.isEmpty) {
      throw StateError('sem convites restantes para o paciente "$role" no manifesto');
    }
    return _inviteTokens.removeAt(0);
  }

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
    // O manifesto que vai ao aparelho (`--dart-define`) NÃO traz o bloco `acs`: a
    // senha nunca vai para o argv do `flutter test` nem para o APK.
    final acs = (map['acs'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{};
    return E2eConfig(
      patients: [
        for (final raw in list.cast<Map>())
          E2ePatientFixture(
            role: raw['role'] as String,
            name: raw['name'] as String,
            cpf: raw['cpf'] as String,
            birthDate: DateTime.parse(raw['birthDate'] as String),
            microAreaId: raw['microAreaId'] as String,
            inviteTokens: (raw['inviteTokens'] as List?)?.cast<String>() ??
                const <String>[],
          ),
      ],
      microAreaId: map['microAreaId']! as String,
      acsMatricula: (acs['matricula'] as String?) ?? '',
      acsPassword: (acs['password'] as String?) ?? '',
    );
  }

  @override
  String toString() => 'E2eConfig(${patients.length} pacientes)';
}
