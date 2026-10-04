import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'upload_token_store.dart';

export 'upload_token_store.dart';

/// Mesmas opções de `SecureStorageSessionTokenStore`: respaldo no Keystore e
/// fora de backup em nuvem.
const FlutterSecureStorage _defaultSecureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
  iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
);

/// Tokens de envio diferido no Keystore, um por dono, sob
/// `acs_upload_token|<userId>` (D7). Separado de `upload_token_store.dart`
/// para que `backend_client.dart` (que roda também na VM) não puxe o Flutter.
///
/// [owners] lê um ÍNDICE próprio (`acs_upload_token_owners`, lista JSON de
/// ids) em vez de `readAll()`: listar donos não pode carregar para a memória
/// do Dart os outros segredos do Keystore (refresh token, chave do banco).
/// Índice ausente ou corrompido vale como vazio; a próxima gravação o refaz.
class SecureStorageUploadTokenStore implements UploadTokenStore {
  SecureStorageUploadTokenStore({FlutterSecureStorage? storage}) : _storage = storage ?? _defaultSecureStorage;

  static const ownersIndexKey = 'acs_upload_token_owners';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String ownerId) async {
    final value = await _storage.read(key: uploadTokenKey(ownerId));
    return value == null || value.isEmpty ? null : value;
  }

  /// Cauda da fila das mutações. Sempre completa sem erro.
  Future<void> _tail = Future<void>.value();

  /// Toda mutação (token + índice) passa por aqui, uma por vez: o índice é
  /// ler-modificar-gravar, e duas intercaladas (o login gravando A enquanto o
  /// envio diferido apaga B) perderiam uma das atualizações.
  Future<T> _serial<T>(Future<T> Function() body) {
    final done = Completer<void>();
    final previous = _tail;
    _tail = done.future;
    return previous.then((_) => body()).whenComplete(done.complete);
  }

  /// Token primeiro, índice depois: um índice que aponta para um token
  /// ausente é inofensivo ([read] devolve `null`); o contrário esconderia o
  /// token de [owners] — e por isso o envio diferido também procura o token
  /// dos donos que têm visitas no disco ([repairIndex]).
  @override
  Future<void> write(String ownerId, String token) => _serial(() async {
        await _storage.write(key: uploadTokenKey(ownerId), value: token);
        final index = await _readIndex();
        if (!index.contains(ownerId)) await _writeIndex([...index, ownerId]);
      });

  @override
  Future<void> clear(String ownerId) => _serial(() async {
        await _storage.delete(key: uploadTokenKey(ownerId));
        final index = await _readIndex();
        if (index.contains(ownerId)) await _writeIndex([for (final o in index) if (o != ownerId) o]);
      });

  @override
  Future<void> repairIndex(String ownerId) => _serial(() async {
        if (await read(ownerId) == null) return;
        final index = await _readIndex();
        if (!index.contains(ownerId)) await _writeIndex([...index, ownerId]);
      });

  @override
  Future<List<String>> owners() => _readIndex();

  Future<List<String>> _readIndex() async {
    final raw = await _storage.read(key: ownersIndexKey);
    if (raw == null || raw.isEmpty) return <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String>[];
      return [for (final item in decoded) if (item is String && item.isNotEmpty) item];
    } on FormatException {
      return <String>[];
    }
  }

  Future<void> _writeIndex(List<String> owners) => _storage.write(key: ownersIndexKey, value: jsonEncode(owners));
}
