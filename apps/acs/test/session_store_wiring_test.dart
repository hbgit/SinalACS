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
    expect(fonte, contains('tokenStore: AuthBoundSessionTokenStore('));
    expect(fonte, contains('vault: MethodChannelKeystoreVault()'));
    expect(fonte, contains('legacy: SecureStorageSessionTokenStore()'));
    expect(fonte, contains('final deviceIds = SecureStorageDeviceIdStore();'));
    expect(fonte, contains('deviceIds: deviceIds'));
  });

  test('o main.dart liga o token de envio diferido ao Keystore, no cliente E no app', () {
    final fonte = File('lib/main.dart').readAsStringSync();
    expect(fonte, contains('final uploadTokens = SecureStorageUploadTokenStore();'));
    expect(RegExp(r'uploadTokens: uploadTokens').allMatches(fonte), hasLength(2));
    expect(fonte, contains('connectivityChanges: Connectivity()'));
  });

  test('o main.dart liga o diário da limpeza remota ao shared_preferences (#81)', () {
    final fonte = File('lib/main.dart').readAsStringSync();
    expect(fonte, contains('wipeJournal: SharedPreferencesWipeJournal()'));
  });

  test('o caminho importado pelo backend_client não puxa o Flutter', () {
    for (final arquivo in [
      'lib/core/security/session_token_store.dart',
      'lib/core/security/upload_token_store.dart',
      'lib/core/network/backend_client.dart',
      // O envio da telemetria (#83) e o que ele importa.
      'lib/core/telemetry/telemetry_uploader.dart',
      'lib/core/telemetry/telemetry_store.dart',
      'lib/core/telemetry/telemetry_event.dart',
      'lib/core/telemetry/app_version.dart',
      'lib/core/services/owner_id.dart',
    ]) {
      final imports = File(arquivo).readAsLinesSync().where((l) => l.startsWith('import ')).join('\n');
      expect(imports, isNot(contains('package:flutter')), reason: arquivo);
      // A fila de visitas importa o gravador, e o gravador o connectivity_plus
      // (Flutter): nenhum dos dois pode entrar por este caminho.
      expect(imports, isNot(contains('offline_visit_queue.dart')), reason: arquivo);
      expect(imports, isNot(contains('telemetry_recorder.dart')), reason: arquivo);
      expect(imports, isNot(contains('network_probe.dart')), reason: arquivo);
      expect(imports, isNot(contains('connectivity_plus')), reason: arquivo);
      expect(imports, isNot(contains('secure_session_token_store.dart')), reason: arquivo);
      expect(imports, isNot(contains('secure_upload_token_store.dart')), reason: arquivo);
    }
  });
}
