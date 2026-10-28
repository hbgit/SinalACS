import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Pseudonimiza identificadores da telemetria com HMAC-SHA-256 chaveado por um
/// segredo do servidor. A mensagem leva o domínio (`patient`/`device`) para que
/// o mesmo valor não gere o mesmo pseudônimo em domínios diferentes.
class TelemetryPseudonymizer {
  TelemetryPseudonymizer(String key) : _hmac = Hmac(sha256, utf8.encode(key));

  final Hmac _hmac;

  /// Pseudônimo (hex, 64 caracteres) do paciente. O UUID entra em minúsculas.
  String patient(String uuid) => _digest('patient', uuid.toLowerCase());

  /// Pseudônimo (hex, 64 caracteres) do aparelho.
  String device(String deviceId) => _digest('device', deviceId);

  String _digest(String domain, String value) =>
      _hmac.convert(utf8.encode('$domain\u001f$value')).toString();
}
