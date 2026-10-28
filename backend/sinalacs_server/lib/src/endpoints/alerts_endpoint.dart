import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/alerts/red_alert_service.dart';
import 'package:sinalacs_server/src/endpoints/authenticated_endpoint.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
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
class AlertsEndpoint extends AuthenticatedEndpoint {
  Future<RedAlertResult> createRedAlert(
    Session session, {
    required String accessToken,
    required String idempotencyKey,
    required String locationHash,
    String? locationCell,
  }) async {
    final user = authenticate(accessToken);

    try {
      // Gravar o alerta, registrar a chave de idempotência e publicar no broker
      // formam uma unidade só: se a publicação falhar, a transação desfaz as
      // escritas e a chave não é consumida, então o cliente pode retentar de
      // verdade em vez de receber sucesso por um alerta nunca publicado.
      // Gravar o alerta, registrar a chave de idempotência e enfileirar a
      // entrega formam uma unidade. A publicação NÃO participa: acontece logo
      // depois do commit, para que um alerta nunca seja entregue sem registro.
      final record = await session.db.transaction((transaction) async {
        final service =
            AlertRuntime.instance.serviceFor(session, transaction: transaction);
        return service.create(
          user: user,
          idempotencyKey: idempotencyKey,
          locationHash: locationHash,
          locationCell: locationCell,
        );
      });

      // Tentativa imediata, para não custar latência no caminho feliz. Se o
      // broker estiver fora, isto devolve false sem lançar e a varredura
      // periódica assume a entrega.
      final published = await AlertRuntime.instance
          .dispatcherFor(session)
          .publishNow(record.delivery.alertId);

      // Telemetria fora da transação e depois da publicação: best-effort, não
      // lança e nunca atrasa nem desfaz o alerta (INV-03). Replay idempotente.
      await AlertRuntime.instance
          .telemetryServiceFor(session)
          .alertTriggered(alert: record.delivery, published: published);

      return RedAlertResult(
        alertId: record.delivery.alertId,
        status: AlertStatus.pending,
        published: published,
      );
    } on ArgumentError catch (error) {
      throw AlertValidationException(message: '${error.message}');
    } on StateError catch (error) {
      throw AlertPermissionException(message: error.message);
    }
  }

  /// Confirma o recebimento. `status` é o da linha travada: um alerta já
  /// concluído (outro aparelho, reentrega do MQTT) volta `resolved`, não
  /// `acknowledged` (#86). Alerta inexistente ou de outra microárea devolve
  /// `acknowledged: false` e `status` nulo.
  Future<AlertAckResult> acknowledge(
    Session session, {
    required String accessToken,
    required String alertId,
  }) async {
    final user = authenticate(accessToken);
    final service = AlertRuntime.instance.serviceFor(session);

    try {
      final status = await service.acknowledge(user: user, alertId: alertId);
      return AlertAckResult(
        alertId: alertId,
        acknowledged: status != null,
        status: status,
      );
    } on ArgumentError catch (error) {
      throw AlertValidationException(message: '${error.message}');
    } on StateError catch (error) {
      throw AlertPermissionException(message: error.message);
    }
  }

  /// Conclui o atendimento de um alerta já confirmado (#76, RF05): é o que
  /// faz o paciente ver "Atendido". Alerta inexistente ou de outra microárea
  /// devolve `resolved: false`, como o ACK; alerta ainda não confirmado é
  /// [AlertValidationException] com o texto de
  /// `RedAlertService.notAcknowledgedMessage`.
  Future<AlertResolveResult> resolve(
    Session session, {
    required String accessToken,
    required String alertId,
  }) async {
    final user = authenticate(accessToken);
    final service = AlertRuntime.instance.serviceFor(session);

    try {
      final attempt = await service.resolve(user: user, alertId: alertId);
      final found = attempt.outcome != AlertResolveOutcome.notFound;
      return AlertResolveResult(
        alertId: alertId,
        resolved: found,
        status: found ? AlertStatus.resolved : null,
        resolvedAt: attempt.resolvedAt,
      );
    } on ArgumentError catch (error) {
      throw AlertValidationException(message: '${error.message}');
    } on StateError catch (error) {
      throw AlertPermissionException(message: error.message);
    }
  }

  /// Alertas não concluídos da microárea do ACS (#80, R2): a reserva por HTTP
  /// para quando o MQTT do aparelho não está conectado. A microárea vem do
  /// token (INV-01). Não grava linha de auditoria de leitura: o app repete a
  /// consulta a cada 30 s com o broker fora, e o mesmo conteúdo chega pelo
  /// MQTT sem auditoria; ACK e conclusão seguem auditados.
  Future<List<AcsOpenAlert>> openForMicroArea(
    Session session, {
    required String accessToken,
  }) async {
    final user = authenticate(accessToken);
    final service = AlertRuntime.instance.serviceFor(session);

    try {
      final abertos = await service.openForAcs(user: user);
      return [
        for (final a in abertos)
          AcsOpenAlert(
            alertId: a.alertId,
            patientId: a.patientId,
            microAreaId: a.microAreaId,
            riskLevel: a.riskLevel,
            locationHash: a.locationHash,
            locationCell: a.locationCell,
            triggeredAt: a.triggeredAt,
            status: a.status,
            acknowledgedAt: a.acknowledgedAt,
            escalated: a.escalated,
          ),
      ];
    } on StateError catch (error) {
      throw AlertPermissionException(message: error.message);
    }
  }

  /// Status do alerta mais recente do PRÓPRIO paciente (RF05, decisão §5).
  /// `patientId` nunca é parâmetro — vem do token (INV-05).
  Future<AlertStatusResult> statusFor(
    Session session, {
    required String accessToken,
  }) async {
    final user = authenticate(accessToken);
    final service = AlertRuntime.instance.serviceFor(session);

    try {
      final snapshot = await service.statusFor(user: user);
      if (snapshot == null) return AlertStatusResult(found: false);

      return AlertStatusResult(
        found: true,
        alertId: snapshot.alertId,
        riskLevel: snapshot.riskLevel,
        status: snapshot.status,
        triggeredAt: snapshot.triggeredAt,
        acknowledgedAt: snapshot.acknowledgedAt,
        resolvedAt: snapshot.resolvedAt,
      );
    } on StateError catch (error) {
      throw AlertPermissionException(message: error.message);
    }
  }
}
