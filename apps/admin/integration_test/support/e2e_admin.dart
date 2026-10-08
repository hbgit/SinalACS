import 'dart:convert';
import 'dart:io';

const relayBase = String.fromEnvironment('OTP_RELAY_BASE', defaultValue: 'http://localhost:8765');

/// Matrícula, senha e código de ativação (#48) do administrador da fixture (sintéticas, novas a cada
/// execução), servidas pelo relé em `/admin` **uma única vez** (opt-in, via
/// `E2E_FIXTURES_FILE`); a primeira chamada busca, as seguintes reaproveitam.
Future<({String matricula, String senha, String activationCode})> adminCredentialFromRelay() =>
    _credencial ??= _buscar();

Future<({String matricula, String senha, String activationCode})>? _credencial;

Future<({String matricula, String senha, String activationCode})> _buscar() async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(relayBase).replace(path: '/admin'));
    final response = await request.close();
    final body = await utf8.decodeStream(response);
    if (response.statusCode != 200) throw StateError('o relé respondeu ${response.statusCode} a /admin');
    final json = jsonDecode(body) as Map;
    return (
      matricula: json['matricula'] as String,
      senha: json['senha'] as String,
      activationCode: json['activationCode'] as String,
    );
  } on SocketException {
    throw StateError('o relé não está no ar (scripts/qa/otp_relay.py + adb reverse tcp:8765 tcp:8765)');
  } finally {
    client.close(force: true);
  }
}
