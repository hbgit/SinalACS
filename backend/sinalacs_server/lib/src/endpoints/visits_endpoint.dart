import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';

/// Sincronização das visitas domiciliares registradas offline.
///
/// É a contraparte da fila offline do app do ACS: o dispositivo grava a visita
/// localmente durante a visita (onde normalmente não há rede) e envia o lote
/// quando a conexão volta.
///
/// O lote inteiro roda em uma transação: ou todas as visitas são aplicadas, ou
/// nenhuma. Um resultado parcial deixaria o dispositivo sem saber o que
/// reenviar.
class VisitsEndpoint extends Endpoint {
  @override
  bool get requireLogin => false;

  Future<List<VisitSyncResult>> sync(
    Session session, {
    required String accessToken,
    required List<VisitSyncEntry> visits,
  }) async {
    final user = _authenticate(accessToken);

    if (visits.isEmpty) return <VisitSyncResult>[];

    try {
      return await session.db.transaction((transaction) async {
        final service =
            AlertRuntime.instance.visitSyncServiceFor(session, transaction: transaction);
        return service.sync(user: user, entries: visits);
      });
    } on ArgumentError catch (error) {
      throw AlertValidationException(message: '${error.message}');
    } on StateError catch (error) {
      throw AlertPermissionException(message: error.message);
    }
  }

  AuthenticatedUser _authenticate(String accessToken) {
    final user = AlertRuntime.instance.auth.verifyToken(accessToken);
    if (user == null) {
      throw AlertPermissionException(message: 'token inválido ou expirado');
    }
    return user;
  }
}
