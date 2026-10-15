import 'package:sinalacs_acs/core/security/session_token_store.dart';

/// MemorySessionTokenStore que conta quantas vezes `read()` foi chamado.
class CountingSessionTokenStore extends MemorySessionTokenStore {
  CountingSessionTokenStore([super.token]);

  int reads = 0;

  @override
  Future<String?> read() {
    reads++;
    return super.read();
  }
}
