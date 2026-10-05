import 'dart:math';

// Sem `package:flutter` aqui, de propósito: `backend_client.dart` importa este
// arquivo e `tool/live_check.dart` roda na VM do Dart, onde `dart:ui` não
// existe. As implementações sobre o Keystore ficam em
// `secure_session_token_store.dart`, montadas só pelo `main.dart`.

/// Resultado do desbloqueio do token guardado. `notRequired`: este store não
/// tem prompt próprio (o chamador usa o portão de interface).
enum SessionUnlock { unlocked, notRequired, cancelled, lockedOut, unavailable }

/// Custódia do refresh token rotativo do ACS (LGPD-RT06).
///
/// Fica no Android Keystore / iOS Keychain, como a chave do banco local. É o
/// que permite renovar o JWT de 15 minutos sem reter a senha em memória.
///
/// **Nunca registre o valor em log**, nem em mensagem de erro.
abstract interface class SessionTokenStore {
  Future<String?> read();

  Future<void> write(String token);

  Future<void> clear();

  /// `true` se há token guardado, **sem** decifrá-lo (nunca abre prompt).
  Future<bool> contains();

  /// Decifra o token guardado para a memória, abrindo o prompt do sistema se o
  /// store o exige. `read()` só enxerga o token depois disto.
  Future<SessionUnlock> unlock({required String reason});
}

/// Duplo de teste: só em memória.
class MemorySessionTokenStore implements SessionTokenStore {
  MemorySessionTokenStore([this._token]);

  String? _token;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> write(String token) async => _token = token;

  @override
  Future<void> clear() async => _token = null;

  @override
  Future<bool> contains() async => _token != null;

  @override
  Future<SessionUnlock> unlock({required String reason}) async => SessionUnlock.notRequired;
}

/// Identificador estável desta instalação. O servidor amarra a família do
/// refresh token a ele e recusa a troca por outro aparelho.
abstract interface class DeviceIdStore {
  Future<String> readOrCreate();
}

/// UUID v4 aleatório (sem dependência extra).
String generateDeviceId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}

class MemoryDeviceIdStore implements DeviceIdStore {
  MemoryDeviceIdStore([this._id]);

  String? _id;

  @override
  Future<String> readOrCreate() async => _id ??= generateDeviceId();
}
