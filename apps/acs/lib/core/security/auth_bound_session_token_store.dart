import 'dart:async';

import 'keystore_vault.dart';
import 'session_token_store.dart';

/// Refresh token do ACS cuja decifra só acontece depois de uma autenticação
/// biométrica/PIN imposta pelo Keystore (TEE), não por um portão de interface.
///
/// - `write` cifra com a chave pública (sem prompt: a rotação de 15 min segue
///   silenciosa) e mantém o valor em RAM.
/// - `read` devolve só a RAM e **nunca** abre prompt (é chamado dentro de
///   `BackendClient._exclusive`).
/// - `unlock` é o único lugar que decifra, uma vez por partida a frio.
///
/// Sem suporte (sem bloqueio de tela, API < 30 sem biometria forte) ou com
/// falha ao selar, o token fica só em RAM: a próxima partida a frio exige login
/// completo. Nunca registre o valor em log.
class AuthBoundSessionTokenStore implements SessionTokenStore {
  AuthBoundSessionTokenStore({
    required KeystoreVault vault,
    required SessionTokenStore legacy,
    Duration unsealTimeout = defaultUnsealTimeout,
  }) : _vault = vault,
       _legacy = legacy,
       _unsealTimeout = unsealTimeout;

  static const alias = 'acs_refresh_token';

  /// Teto generoso para o prompt: se o lado nativo nunca responder (ex.: o
  /// BiometricPrompt descartou o pedido em silêncio), `_unlocking` não pode
  /// ficar preso para sempre — senão todo unlock seguinte esperaria o mesmo
  /// future e o portão travaria até matar o processo.
  static const defaultUnsealTimeout = Duration(minutes: 2);

  final Duration _unsealTimeout;

  final KeystoreVault _vault;
  final SessionTokenStore _legacy;
  String? _cache;
  Future<SessionUnlock>? _unlocking;
  // Ligado quando a migração do legado terminou (ou não havia legado): daí em
  // diante `contains()` só consulta o cofre, sem tocar no armazenamento legado.
  bool _migrated = false;

  @override
  Future<String?> read() async => _cache;

  @override
  Future<bool> contains() async {
    if (_cache != null) return true;
    if (!await _vault.isSupported) return false;
    if (!_migrated) await _migrateLegacy();
    return _vault.contains(alias);
  }

  @override
  Future<SessionUnlock> unlock({required String reason}) {
    if (_cache != null) return Future.value(SessionUnlock.unlocked);
    return _unlocking ??= _unlock(reason).whenComplete(() => _unlocking = null);
  }

  Future<SessionUnlock> _unlock(String reason) async {
    try {
      await _migrateLegacy();
      final token = await _vault
          .unseal(alias, reason: reason)
          .timeout(_unsealTimeout);
      if (token == null || token.isEmpty) return SessionUnlock.unavailable;
      _cache = token;
      return SessionUnlock.unlocked;
    } on VaultException catch (e) {
      switch (e.failure) {
        case VaultFailure.cancelled:
          return SessionUnlock.cancelled;
        case VaultFailure.lockedOut:
          return SessionUnlock.lockedOut;
        case VaultFailure.invalidated:
          // Nova digital cadastrada: a chave morreu, o token é irrecuperável.
          await _vault.delete(alias);
          return SessionUnlock.unavailable;
        case VaultFailure.unavailable:
          return SessionUnlock.unavailable;
      }
    } on TimeoutException {
      // Sem resposta do cofre: trata como cancelado e NÃO apaga o token; a
      // próxima tentativa abre um prompt novo.
      return SessionUnlock.cancelled;
    }
  }

  @override
  Future<void> write(String token) async {
    _cache = token;
    _migrated = true; // o legado é apagado abaixo; nada mais a migrar
    try {
      if (await _vault.isSupported) {
        await _vault.seal(alias, token);
        await _legacy.clear();
        return;
      }
    } on VaultException {
      // Degrada para RAM.
    }
    // Sem cofre: não deixa um blob antigo ressuscitar um token já rotacionado.
    await _vault.delete(alias);
    await _legacy.clear();
  }

  @override
  Future<void> clear() async {
    _cache = null;
    await _vault.delete(alias);
    await _legacy.clear();
  }

  /// Instalações antigas guardam o token no `flutter_secure_storage`. Sela-o
  /// (sem prompt) e apaga o original; o `unseal` seguinte já pede biometria.
  Future<void> _migrateLegacy() async {
    if (_migrated) return;
    final old = await _legacy.read();
    if (old == null || old.isEmpty) {
      _migrated = true;
      return;
    }
    if (await _vault.contains(alias)) {
      await _legacy.clear();
      _migrated = true;
      return;
    }
    try {
      await _vault.seal(alias, old);
      await _legacy.clear();
      _migrated = true;
    } on VaultException {
      // Mantém o legado e NÃO liga o flag: a próxima chamada tenta de novo.
      // Melhor um token no Keystore comum que perder a sessão.
    }
  }
}
