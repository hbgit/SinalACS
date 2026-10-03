import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// O padrão do `BackendClient` guarda o refresh token só em memória, porque
/// `backend_client.dart` roda também na VM do Dart (`tool/live_check.dart`),
/// onde o Keystore (`flutter_secure_storage` → `dart:ui`) não compila. Quem liga
/// o Keystore é o `main.dart`; sem ele o app perderia a sessão a cada partida
/// a frio e a retomada por digital nunca aconteceria. Estas guardas impedem que
/// as duas pontas se percam sem ninguém notar.
void main() {
  test('o main.dart liga o refresh token e o id do aparelho ao Keystore', () {
    final fonte = File('lib/main.dart').readAsStringSync();
    expect(fonte, contains('tokenStore: SecureStorageSessionTokenStore()'));
    expect(fonte, contains('deviceIds: SecureStorageDeviceIdStore()'));
  });

  test('o caminho importado pelo backend_client não puxa o Flutter', () {
    for (final arquivo in ['lib/core/security/session_token_store.dart', 'lib/core/network/backend_client.dart']) {
      final imports = File(arquivo).readAsLinesSync().where((l) => l.startsWith('import ')).join('\n');
      expect(imports, isNot(contains('package:flutter')), reason: arquivo);
      expect(imports, isNot(contains('secure_session_token_store.dart')), reason: arquivo);
    }
  });
}
