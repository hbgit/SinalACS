import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Custódia da chave que abre o banco local criptografado.
///
/// A chave **não** é derivada de PIN nem de biometria, apesar de
/// `spec/PRD_system.md` (4.2.3) prescrever PBKDF2 a partir de PIN: não existe
/// nenhum fluxo de PIN nos apps — a autenticação do ACS é institucional
/// (matrícula + senha, RF07) e não usa PIN — e um PIN esquecido significaria
/// perder visitas ainda não sincronizadas. Adotamos a leitura de
/// `spec/test_plan.md` (126), "chave gerada pelo TEE do hardware": chave
/// aleatória guardada no armazenamento seguro da plataforma.
///
/// A interface aceita um segundo fator depois, sem migrar dados: bastaria
/// envelopar a chave devolvida aqui.
abstract class DatabaseKeyStore {
  /// Devolve a chave do dispositivo, criando-a na primeira vez.
  Future<String> readOrCreate();

  /// Remove a chave. Torna o banco existente ilegível — só use ao descartar o
  /// banco junto.
  Future<void> delete();
}

/// Gera uma chave de 256 bits em hexadecimal.
///
/// São 64 caracteres hex a partir de [Random.secure]. O SQLCipher deriva a
/// chave real desta passphrase.
String generateDatabaseKey() {
  final random = Random.secure();
  return List<int>.generate(32, (_) => random.nextInt(256))
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
}

/// Guarda a chave no Android Keystore / iOS Keychain.
///
/// **Nunca registre a chave em log**, nem em mensagem de erro: "dados sensíveis
/// não são logados em texto plano" é critério de aceite do LGPD-RF09.
class SecureStorageDatabaseKeyStore implements DatabaseKeyStore {
  SecureStorageDatabaseKeyStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              // Respaldado pelo Keystore do Android; minSdk 24 atende.
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              // `first_unlock_this_device` mantém a chave fora de backup em
              // nuvem e ilegível antes do primeiro desbloqueio. Sem isso, um
              // backup restaurado em outro aparelho levaria a chave junto.
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  static const _key = 'sinalacs.local_database_key';

  final FlutterSecureStorage _storage;

  @override
  Future<String> readOrCreate() async {
    final existing = await _storage.read(key: _key);
    if (existing != null && existing.isNotEmpty) return existing;

    final created = generateDatabaseKey();
    await _storage.write(key: _key, value: created);
    return created;
  }

  @override
  Future<void> delete() => _storage.delete(key: _key);
}

/// Duplo de teste. Mantém a chave só em memória.
class InMemoryDatabaseKeyStore implements DatabaseKeyStore {
  InMemoryDatabaseKeyStore({String? initialKey}) : _key = initialKey;

  String? _key;

  @override
  Future<String> readOrCreate() async => _key ??= generateDatabaseKey();

  @override
  Future<void> delete() async => _key = null;
}
