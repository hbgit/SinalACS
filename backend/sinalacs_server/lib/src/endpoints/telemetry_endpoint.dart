import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/endpoints/authenticated_endpoint.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';

/// Porta de entrada da telemetria que o app do ACS gerou offline (#83, PRD
/// §1.3).
class TelemetryEndpoint extends AuthenticatedEndpoint {
  /// Grava um lote de eventos do aparelho. Idempotente por `eventId`: o reenvio
  /// do mesmo lote (resposta perdida) devolve os mesmos aceitos sem duplicar
  /// linha. Só o ACS; o autor vem do token. Regras de recusa em
  /// `TelemetryService.ingestFromDevice`.
  ///
  /// Não grava linha de auditoria: é métrica operacional, não acesso a dado de
  /// titular, e o app chama a cada sincronização — o mesmo critério de
  /// `alerts.openForMicroArea`. O paciente só chega à tabela pseudonimizado.
  Future<TelemetryIngestResult> ingest(
    Session session, {
    required String accessToken,
    required String deviceId,
    required DateTime sentAt,
    required List<TelemetryEventInput> events,
  }) async {
    final user = authenticate(accessToken);
    final service = AlertRuntime.instance.telemetryServiceFor(session);

    try {
      return await service.ingestFromDevice(
        user: user,
        deviceId: deviceId,
        sentAt: sentAt,
        events: events,
      );
    } on ArgumentError catch (error) {
      throw AlertValidationException(message: '${error.message}');
    } on StateError catch (error) {
      throw AlertPermissionException(message: error.message);
    }
  }
}
