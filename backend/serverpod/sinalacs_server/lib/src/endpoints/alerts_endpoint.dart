import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/mqtt/mqtt_alert_dispatcher.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';

/// Ciclo do alerta vermelho.
///
/// Substitui `POST /v1/alerts/red` e `POST /v1/alerts/{id}/ack`. Como o
/// Serverpod é RPC e não REST, três coisas que antes viajavam no HTTP mudaram
/// de lugar:
///
///  * a chave de idempotência era o header `Idempotency-Key` e agora é um
///    parâmetro do método;
///  * o mapeamento de exceção para status (400/403/503) virou exceção tipada,
///    serializada até o cliente;
///  * o 404 do ACK sem correspondência virou o campo `acknowledged: false`.
///
/// A autenticação continua sendo o token HMAC de desenvolvimento, verificado
/// aqui em vez de no laço de requisições do servidor `dart:io`.
class AlertsEndpoint extends Endpoint {
  @override
  bool get requireLogin => false;

  Future<RedAlertResult> createRedAlert(
    Session session, {
    required String accessToken,
    required String idempotencyKey,
    required String locationHash,
  }) async {
    final user = _authenticate(accessToken);
    final service = AlertRuntime.instance.serviceFor(session);

    try {
      final record = await service.create(
        user: user,
        idempotencyKey: idempotencyKey,
        locationHash: locationHash,
      );
      return RedAlertResult(
        alertId: record.delivery.alertId,
        status: AlertStatus.pending,
      );
    } on ArgumentError catch (error) {
      throw AlertValidationException(message: '${error.message}');
    } on MqttUnavailableException catch (error) {
      throw AlertDispatchUnavailableException(message: error.message);
    } on StateError catch (error) {
      throw AlertPermissionException(message: error.message);
    }
  }

  Future<AlertAckResult> acknowledge(
    Session session, {
    required String accessToken,
    required String alertId,
  }) async {
    final user = _authenticate(accessToken);
    final service = AlertRuntime.instance.serviceFor(session);

    try {
      final acknowledged =
          await service.acknowledge(user: user, alertId: alertId);
      return AlertAckResult(
        alertId: alertId,
        acknowledged: acknowledged,
        status: acknowledged ? AlertStatus.acknowledged : null,
      );
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
