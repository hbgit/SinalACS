import 'dart:async';

import 'package:sinalacs_acs/core/security/session_token_store.dart';

/// Memória com uma comporta na escrita: enquanto [writeGate] não completa, o
/// `write` fica pendente. Serve para parar o login exatamente na janela entre
/// o incremento da época e a troca da sessão.
class GatedSessionTokenStore implements SessionTokenStore {
  GatedSessionTokenStore([String? token]) : _inner = MemorySessionTokenStore(token);

  final MemorySessionTokenStore _inner;
  Completer<void>? writeGate;
  int writes = 0;

  @override
  Future<String?> read() => _inner.read();

  @override
  Future<void> write(String token) async {
    writes++;
    final gate = writeGate;
    if (gate != null) await gate.future;
    await _inner.write(token);
  }

  @override
  Future<void> clear() => _inner.clear();

  @override
  Future<bool> contains() => _inner.contains();

  @override
  Future<SessionUnlock> unlock({required String reason}) => _inner.unlock(reason: reason);
}
