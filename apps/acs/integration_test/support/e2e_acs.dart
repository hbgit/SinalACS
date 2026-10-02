import 'dart:convert';
import 'dart:io';

/// Manifesto de fixtures SEM o bloco `acs` (a senha vem do relé, nunca do
/// `--dart-define`): `--dart-define=E2E_FIXTURES='{"patients":[…]}'`.
const _fixtures = String.fromEnvironment('E2E_FIXTURES');
const relayBase = String.fromEnvironment('OTP_RELAY_BASE', defaultValue: 'http://localhost:8765');

class E2ePatient {
  const E2ePatient({
    required this.id,
    required this.role,
    required this.name,
    required this.cpf,
    required this.birthDate,
    required this.microAreaId,
  });
  final String id;
  final String role;
  final String name;
  final String cpf; // nunca em log
  final String birthDate; // AAAA-MM-DD
  final String microAreaId;
  @override
  String toString() => 'E2ePatient($role)';
}

List<E2ePatient> e2ePatients() {
  if (_fixtures.isEmpty) {
    throw StateError('sem --dart-define=E2E_FIXTURES (use scripts/qa/acs_full_e2e.sh)');
  }
  final map = (jsonDecode(_fixtures) as Map).cast<String, Object?>();
  return [
    for (final raw in (map['patients']! as List).cast<Map>())
      E2ePatient(
        id: raw['id'] as String,
        role: raw['role'] as String,
        name: raw['name'] as String,
        cpf: raw['cpf'] as String,
        birthDate: raw['birthDate'] as String,
        microAreaId: raw['microAreaId'] as String,
      ),
  ];
}

E2ePatient e2ePatient(String role) => e2ePatients().firstWhere((p) => p.role == role);

Future<String> _get(String path, {String query = ''}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(relayBase).replace(path: path, query: query));
    final response = await request.close();
    final body = await utf8.decodeStream(response);
    if (response.statusCode != 200) throw StateError('o relé respondeu ${response.statusCode} a $path');
    return body.trim();
  } on SocketException {
    throw StateError('o relé não está no ar (scripts/qa/otp_relay.py + adb reverse tcp:8765 tcp:8765)');
  } finally {
    client.close(force: true);
  }
}

/// Matrícula e senha do ACS da fixture, servidas pelo relé (opt-in).
Future<({String matricula, String senha})> acsCredentialFromRelay() async {
  final json = jsonDecode(await _get('/acs')) as Map;
  return (matricula: json['matricula'] as String, senha: json['senha'] as String);
}
