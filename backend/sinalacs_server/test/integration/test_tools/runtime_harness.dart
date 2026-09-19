import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/institutional_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/password_hasher.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/argon2_password_hasher.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_acs_credential_store.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';

/// Atalhos para os testes de integração alcançarem as peças de processo do
/// `AlertRuntime` sem duplicar a construção delas.
abstract final class AlertRuntimeHarness {
  /// Custo reduzido: a integração prova o caminho, não o custo do Argon2id.
  static final PasswordHasher hasher =
      const Argon2PasswordHasher(memoryKb: 512, iterations: 1, parallelism: 1);

  static AcsCredentialStore store(Session session) =>
      OrmAcsCredentialStore(session: () => session);

  static AuthenticatedUser? verify(String token) =>
      AlertRuntime.instance.auth.verifyToken(token);
}
