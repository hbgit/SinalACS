import 'dart:convert';

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

  /// O `exp − iat` do token, em segundos: o TTL da sessão que o servidor
  /// emitiu.
  ///
  /// Lê o payload **sem** verificar a assinatura — quem verifica é o [verify]
  /// acima, e o que se mede aqui é o número que o emissor gravou, não a
  /// autenticidade dele. Existe porque o TTL não é observável de outra forma:
  /// o `AuthenticatedUser` que [verify] devolve não carrega `exp` nem `iat`, e
  /// era isso que deixava o TTL de cada papel sem nenhuma asserção na suíte.
  static Duration tokenLifetime(String token) {
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[1]))),
    ) as Map<String, dynamic>;
    return Duration(seconds: (payload['exp'] as int) - (payload['iat'] as int));
  }
}
