// Sem `package:flutter` aqui, de propósito (mesmo motivo de
// `session_token_store.dart`): `backend_client.dart` importa este arquivo e
// `tool/live_check.dart` roda na VM do Dart, onde `dart:ui` não existe. A
// implementação sobre o Keystore fica em `secure_upload_token_store.dart`,
// montada só pelo `main.dart`.

/// Chave do token de envio de [ownerId] no Keystore (D7).
String uploadTokenKey(String ownerId) => '$uploadTokenKeyPrefix$ownerId';

/// Prefixo comum das chaves dos tokens de envio.
const uploadTokenKeyPrefix = 'acs_upload_token|';

/// Custódia dos **tokens de envio diferido** (D7 do plano 2026-10-03), um por
/// dono (`userId` do ACS).
///
/// O token é emitido pelo `auth.loginInstitutional` junto do refresh token e só
/// serve para `visits.syncDeferred` e `visits.revokeUploadToken`: é o que
/// permite subir as visitas de A, com a autoria de A, depois que A saiu. Ele
/// **sobrevive ao "Sair"** enquanto houver visita pendente de A; é revogado e
/// apagado quando a fila de A zera.
///
/// **Nunca registre o valor em log**, nem em mensagem de erro.
abstract interface class UploadTokenStore {
  Future<String?> read(String ownerId);

  Future<void> write(String ownerId, String token);

  Future<void> clear(String ownerId);

  /// Donos que têm token guardado neste aparelho.
  Future<List<String>> owners();
}

/// Duplo de teste: só em memória.
class MemoryUploadTokenStore implements UploadTokenStore {
  MemoryUploadTokenStore([Map<String, String>? initial]) : _tokens = {...?initial};

  final Map<String, String> _tokens;

  @override
  Future<String?> read(String ownerId) async => _tokens[ownerId];

  @override
  Future<void> write(String ownerId, String token) async => _tokens[ownerId] = token;

  @override
  Future<void> clear(String ownerId) async => _tokens.remove(ownerId);

  @override
  Future<List<String>> owners() async => _tokens.keys.toList();
}
