import 'package:meta/meta.dart';
import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';

/// Verifica o token de acesso e devolve o usuário, ou recusa.
///
/// Era o corpo idêntico de cinco métodos privados `_authenticate`, um por
/// endpoint. Fica numa função só para que exista **um** lugar onde a
/// verificação pode ser lida — e para que um endpoint novo tenha de onde
/// herdá-la em vez de reescrevê-la.
AuthenticatedUser authenticateToken(String accessToken) {
  final user = AlertRuntime.instance.auth.verifyToken(accessToken);
  if (user == null) {
    throw AlertPermissionException(message: 'token inválido ou expirado');
  }
  return user;
}

/// Endpoint cujos métodos exigem credencial.
///
/// A existência desta classe é o que permite ao teste de postura
/// (`test/unit/endpoint_auth_posture_test.dart`) distinguir, no texto-fonte,
/// um endpoint autenticado de um público. `requireLogin` continua `false`: o
/// stack de autenticação do próprio Serverpod (`AuthenticationHandler`) não
/// está conectado neste projeto — a autenticação é feita à mão, com
/// `verifyToken`, e ligar a flag sem conectar o handler rejeitaria *todas* as
/// chamadas. O que muda aqui é a postura ficar declarada e verificável, que é
/// o que o achado F4 de spec/security_assessment.md pede.
abstract class AuthenticatedEndpoint extends Endpoint {
  @override
  bool get requireLogin => false;

  /// Delega para [authenticateToken]; existe como método para que os endpoints
  /// chamem `authenticate(...)` como sempre chamaram.
  @protected
  AuthenticatedUser authenticate(String accessToken) =>
      authenticateToken(accessToken);
}
