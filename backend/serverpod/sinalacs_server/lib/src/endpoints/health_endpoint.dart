import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';

/// Sonda de saúde.
///
/// Preserva a forma do antigo `GET /health` — `{status, mqtt_connected,
/// db_connected}` — porque o `HEALTHCHECK` do Dockerfile e o runbook de
/// free-tier dependem dela.
///
/// Responde `ok` assim que o servidor está de pé, independentemente do estado
/// do broker e do banco: hosts free-tier hibernam, e um healthcheck que falha
/// junto com a dependência impede o host de acordar.
class HealthEndpoint extends Endpoint {
  @override
  bool get requireLogin => false;

  Future<ServiceHealth> check(Session session) async {
    return ServiceHealth(
      status: 'ok',
      mqttConnected: AlertRuntime.instance.isMqttConnected,
      dbConnected: await _isDatabaseReachable(session),
    );
  }

  Future<bool> _isDatabaseReachable(Session session) async {
    try {
      await session.db.unsafeSimpleQuery('SELECT 1');
      return true;
    } catch (_) {
      // Reportar o estado, nunca derrubar o healthcheck junto com o banco.
      return false;
    }
  }
}
