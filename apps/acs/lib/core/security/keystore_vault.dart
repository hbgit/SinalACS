import 'package:flutter/services.dart';

enum VaultFailure { cancelled, lockedOut, invalidated, unavailable }

class VaultException implements Exception {
  const VaultException(this.failure);
  final VaultFailure failure;
  // Sem mensagem de propósito: nunca carregar detalhe do Keystore para logs.
  @override
  String toString() => 'VaultException($failure)';
}

/// Cofre cuja decifra exige autenticação do usuário imposta pelo Keystore.
abstract interface class KeystoreVault {
  Future<bool> get isSupported;
  Future<bool> contains(String alias);

  /// Cifra com a chave pública: NÃO abre prompt.
  Future<void> seal(String alias, String plaintext);

  /// Abre o prompt biométrico/PIN e decifra. `null` se não há blob.
  /// Lança [VaultException].
  Future<String?> unseal(String alias, {required String reason});

  Future<void> delete(String alias);
}

class MethodChannelKeystoreVault implements KeystoreVault {
  MethodChannelKeystoreVault([MethodChannel? channel])
    : _channel =
          channel ??
          const MethodChannel('br.com.prismrr.sinalacs.acs/keystore_vault');

  final MethodChannel _channel;

  @override
  Future<bool> get isSupported async {
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> contains(String alias) async {
    try {
      return await _channel.invokeMethod<bool>('contains', {'alias': alias}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> seal(String alias, String plaintext) async {
    try {
      await _channel.invokeMethod<void>('seal', {
        'alias': alias,
        'plaintext': plaintext,
      });
    } on PlatformException {
      throw const VaultException(VaultFailure.unavailable);
    }
  }

  @override
  Future<String?> unseal(String alias, {required String reason}) async {
    try {
      return await _channel.invokeMethod<String>('unseal', {
        'alias': alias,
        'reason': reason,
      });
    } on PlatformException catch (e) {
      throw VaultException(switch (e.code) {
        'cancelled' => VaultFailure.cancelled,
        'lockedOut' => VaultFailure.lockedOut,
        'invalidated' => VaultFailure.invalidated,
        _ => VaultFailure.unavailable,
      });
    } on MissingPluginException {
      throw const VaultException(VaultFailure.unavailable);
    }
  }

  @override
  Future<void> delete(String alias) async {
    try {
      await _channel.invokeMethod<void>('delete', {'alias': alias});
    } catch (_) {}
  }
}

/// Duplo de teste (RAM).
class FakeKeystoreVault implements KeystoreVault {
  bool supported = true;
  bool failSeal = false;
  VaultFailure? nextUnsealFailure;
  int unsealCalls = 0; // = unlockCalls: quantos prompts foram abertos
  int readCalls =
      0; // quantas vezes `contains` foi consultado (nunca abre prompt)
  final Map<String, String> sealed = {};

  @override
  Future<bool> get isSupported async => supported;

  @override
  Future<bool> contains(String alias) async {
    readCalls++;
    return sealed.containsKey(alias);
  }

  @override
  Future<void> seal(String alias, String plaintext) async {
    if (failSeal) throw const VaultException(VaultFailure.unavailable);
    sealed[alias] = plaintext;
  }

  @override
  Future<String?> unseal(String alias, {required String reason}) async {
    unsealCalls++;
    final failure = nextUnsealFailure;
    if (failure != null) {
      nextUnsealFailure = null;
      if (failure == VaultFailure.invalidated) sealed.remove(alias);
      throw VaultException(failure);
    }
    return sealed[alias];
  }

  @override
  Future<void> delete(String alias) async => sealed.remove(alias);
}
