import 'package:uuid/uuid.dart';

import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/authorization.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/telemetry/telemetry_service.dart';
import 'package:sinalacs_server/src/domain/entities/alert_delivery.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

const _uuid = Uuid();

abstract interface class AlertPublisher {
  /// Completa quando o broker confirma a entrega (PUBACK do QoS 1) e falha
  /// quando não há conexão, quando ela cai antes da confirmação ou quando a
  /// confirmação não chega no prazo (H5, #56). Só depois de completar a
  /// entrega pode ser dada como publicada.
  Future<void> publish(AlertDelivery alert);
}

abstract interface class AlertStore {
  Future<void> save(AlertDelivery alert, {required String deviceId});

  /// Confirma o alerta no território do ACS. Quando o alerta existe na
  /// microárea, grava [audit] na MESMA transação da mudança de status (#44):
  /// se a trilha falhar, o ACK é desfeito — nenhum alerta vermelho muda de
  /// estado sem registro. Sem alerta na microárea, nada é gravado e volta
  /// `null`; senão volta o [AlertAckRecord] lido sob a trava da linha.
  Future<AlertAckRecord?> acknowledge({
    required String alertId,
    required String acsId,
    required String microAreaId,
    required AuditEvent audit,
  });

  /// Conclui o atendimento (#76): leva o alerta de `acknowledged` a
  /// `resolved` no território do ACS. O desfecho é decidido sob trava da
  /// linha, e `auditFor(desfecho)` é gravado na MESMA transação (fail-closed)
  /// — exceto [AlertResolveOutcome.notFound], que não grava nada, como o ACK.
  Future<AlertResolveAttempt> resolve({
    required String alertId,
    required String microAreaId,
    required DateTime now,
    required AuditEvent Function(AlertResolveOutcome outcome) auditFor,
  });

  /// Recupera o alerta já criado para esta chave de idempotência, se houver.
  ///
  /// A deduplicação vive no armazenamento, e não em memória, para sobreviver a
  /// restart e valer entre instâncias.
  Future<RedAlertRecord?> findByIdempotencyKey(String idempotencyKey);

  /// Registra a chave na mesma unidade de trabalho do alerta.
  Future<void> rememberIdempotencyKey(RedAlertRecord record);

  /// Alerta mais recente do paciente, para RF05 (`alerts.statusFor`). `null`
  /// quando o paciente nunca disparou um alerta.
  Future<AlertStatusSnapshot?> latestForPatient(String patientId);

  /// Alertas não concluídos da microárea (#80, R2): primeiro os não
  /// confirmados (`pending` e o `escalated` legado), depois os confirmados,
  /// cada grupo do mais antigo ao mais novo, cortado em [limit] — o corte
  /// descarta os mais ANTIGOS de cada grupo, nunca o mais novo.
  Future<List<OpenAlertSnapshot>> openInMicroArea(String microAreaId, {required int limit});
}

/// Fila durável de entregas pendentes.
///
/// O enfileiramento participa da transação do alerta; a publicação acontece
/// depois do commit. É o que impede que um alerta seja entregue sem registro,
/// ou registrado sem nunca ser entregue.
abstract interface class AlertOutbox {
  /// Registra a intenção de publicar. Chamado dentro da transação do alerta.
  Future<void> enqueue(AlertDelivery alert);

  /// Reclama entregas vencidas para publicação, marcando a tentativa.
  Future<List<PendingDelivery>> claimDue({int limit});

  Future<void> markPublished(String entryId);

  Future<void> markFailed(String entryId, String error, DateTime nextAttemptAt);
}

/// Uma entrega reclamada do outbox, pronta para publicação.
class PendingDelivery {
  const PendingDelivery({
    required this.entryId,
    required this.delivery,
    required this.attempts,
  });

  final String entryId;
  final AlertDelivery delivery;

  /// Tentativas já realizadas, incluindo esta. Alimenta o backoff.
  final int attempts;
}

class RedAlertRecord {
  const RedAlertRecord({required this.delivery, required this.idempotencyKey});

  final AlertDelivery delivery;
  final String idempotencyKey;
}

/// Desfecho de [AlertStore.resolve] (#76).
enum AlertResolveOutcome {
  /// Inexistente ou de outra microárea: a mesma resposta, nada gravado.
  notFound,

  /// Ainda `pending`: o recebimento precisa ser confirmado antes (INV-03 —
  /// concluir sem ACK apagaria do painel um vermelho que ninguém confirmou).
  notAcknowledged,

  /// `acknowledged` → `resolved` agora.
  resolved,

  /// Já estava `resolved`: nada muda e o `resolvedAt` original volta.
  alreadyResolved,
}

class AlertResolveAttempt {
  const AlertResolveAttempt(this.outcome, {this.resolvedAt});

  final AlertResolveOutcome outcome;

  /// Quando o atendimento foi concluído; nulo em [AlertResolveOutcome.notFound]
  /// e [AlertResolveOutcome.notAcknowledged].
  final DateTime? resolvedAt;
}

/// O que [AlertStore.acknowledge] leu e gravou sob a trava da linha (#83).
class AlertAckRecord {
  const AlertAckRecord({
    required this.triggeredAt,
    required this.acknowledgedAt,
    required this.firstAcknowledgement,
  });

  final DateTime triggeredAt;

  /// O `acknowledgedAt` gravado: o do primeiro ACK, que a repetição preserva.
  final DateTime acknowledgedAt;

  /// Verdadeiro só quando a linha ainda não tinha `acknowledgedAt` antes deste
  /// ACK; é o que faz `alert_received_acs` sair uma vez por alerta.
  final bool firstAcknowledgement;
}

/// Status do alerta mais recente de um paciente, para RF05.
///
/// Espelha os campos que `Alert` guarda além de [AlertDelivery] — `status` e
/// `acknowledgedAt` não existem no envelope MQTT, só na linha persistida.
class AlertStatusSnapshot {
  const AlertStatusSnapshot({
    required this.alertId,
    required this.riskLevel,
    required this.status,
    required this.triggeredAt,
    this.acknowledgedAt,
    this.resolvedAt,
  });

  final String alertId;
  final RiskLevel riskLevel;
  final AlertStatus status;
  final DateTime triggeredAt;
  final DateTime? acknowledgedAt;

  /// Conclusão do atendimento pelo ACS (#76); nulo até lá.
  final DateTime? resolvedAt;
}

/// Alerta aberto da microárea, para a reserva por HTTP do ACS (#80).
///
/// Mesmos campos de `AcsOpenAlert`: o envelope MQTT mais o estado persistido.
class OpenAlertSnapshot {
  const OpenAlertSnapshot({
    required this.alertId,
    required this.patientId,
    required this.microAreaId,
    required this.riskLevel,
    required this.locationHash,
    this.locationCell,
    required this.triggeredAt,
    required this.status,
    this.acknowledgedAt,
    required this.escalated,
  });

  final String alertId;
  final String patientId;
  final String microAreaId;
  final RiskLevel riskLevel;
  final String locationHash;
  final String? locationCell;
  final DateTime triggeredAt;
  final AlertStatus status;
  final DateTime? acknowledgedAt;

  /// Reforçado pelo backoffice (#44): `escalatedAt` preenchido ou a linha
  /// legada com `status: escalated`.
  final bool escalated;
}

/// Formato produzido por `locationCellFrom()` (apps/patient/lib/core/privacy/location_cell.dart):
/// `"<latCell>:<lngCell>"`, dois inteiros (a célula é `(coordenada /
/// cellSizeDegrees).floor()`, então pode ser negativa) separados por `:`.
final _locationCellFormat = RegExp(r'^-?\d{1,6}:-?\d{1,6}$');

class RedAlertService {
  /// `deviceId` sentinela do ACK que chega por MQTT (`lib/server.dart`): esse
  /// caminho não tem token, e `acsId`/`microAreaId` vêm do payload. Único
  /// lugar onde o valor existe; o servidor o usa ao montar o usuário do ACK e
  /// [acknowledge] o usa para não auditar esse ACK como o do RPC (F3, #44).
  static const mqttAckDeviceId = 'mqtt';

  RedAlertService({
    required AlertStore store,
    required AlertOutbox outbox,
    DateTime Function()? clock,
    TelemetryService? telemetry,
  })  : _store = store,
        _outbox = outbox,
        _clock = clock ?? DateTime.now,
        _telemetry = telemetry;

  final AlertStore _store;
  final AlertOutbox _outbox;
  final DateTime Function() _clock;

  /// Telemetria do PRD §1.3 (#83); nula não emite nada.
  final TelemetryService? _telemetry;

  Future<RedAlertRecord> create({
    required AuthenticatedUser user,
    required String idempotencyKey,
    required String locationHash,
    String? locationCell,
  }) async {
    Authorization.require(
      user,
      roles: {UserRole.patient},
      onDenied: () =>
          StateError('Somente pacientes territorializados podem criar alertas.'),
    );
    if (idempotencyKey.isEmpty || locationHash.isEmpty) {
      throw ArgumentError('A chave de idempotência e a localização são obrigatórias.');
    }
    if (locationCell != null && locationCell.isNotEmpty && !_locationCellFormat.hasMatch(locationCell)) {
      // `locationCell` é opcional (GPS pode estar indisponível no
      // dispositivo), mas quando presente precisa ser exatamente o formato
      // que `locationCellFrom()` produz (apps/patient/lib/core/privacy/location_cell.dart):
      // dois inteiros, possivelmente negativos, separados por `:`. Sem esta
      // checagem, um valor malformado (coordenada decimal, texto arbitrário)
      // entraria direto em `AlertDelivery.locationCell` e quebraria o mapa do
      // ACS, que espera célula, não ponto.
      throw ArgumentError('locationCell inválido — formato esperado "<latCell>:<lngCell>".');
    }

    final existing = await _store.findByIdempotencyKey(idempotencyKey);
    if (existing != null) {
      if (existing.delivery.locationHash != locationHash) {
        throw StateError('A chave de idempotência já foi usada com outra localização.');
      }
      return existing;
    }

    final triggeredAt = _clock().toUtc();
    final alert = AlertDelivery(
      alertId: _newAlertId(),
      patientId: user.id,
      microAreaId: user.microAreaId!,
      riskLevel: 'red',
      locationHash: locationHash,
      locationCell: locationCell,
      triggeredAt: triggeredAt,
    );
    final record = RedAlertRecord(delivery: alert, idempotencyKey: idempotencyKey);

    // A gravação do alerta, o registro da chave e a publicação formam uma
    // unidade só. Sob o Serverpod isto roda dentro da transação da requisição:
    // se a publicação falhar, nada fica no banco, e a chave não é consumida —
    // o cliente pode retentar de verdade em vez de receber sucesso por um
    // alerta que nunca foi publicado (INV-03).
    // As três escritas formam uma unidade. A publicação NÃO acontece aqui: o
    // outbox guarda a intenção, e a entrega vira consequência do commit.
    await _store.save(alert, deviceId: user.deviceId);
    await _store.rememberIdempotencyKey(record);
    await _outbox.enqueue(alert);
    return record;
  }

  // O gerador anterior derivava o ID do relógio
  // ('00000000-0000-4000-8000-' + microssegundos % 1e12), o que colidia a cada
  // ~11,6 dias e entre duas requisições no mesmo microssegundo. Um alerta
  // vermelho nunca pode ser descartado por colisão de identificador (INV-03).
  String _newAlertId() => _uuid.v4();

  Future<bool> acknowledge({required AuthenticatedUser user, required String alertId}) async {
    Authorization.require(
      user,
      roles: {UserRole.acs},
      onDenied: () =>
          StateError('Somente ACS territorializados podem confirmar alertas.'),
    );
    if (alertId.trim().isEmpty) {
      throw ArgumentError('O identificador do alerta é obrigatório.');
    }
    // Toda confirmação que encontra o alerta é auditada, inclusive a repetida
    // do mesmo ACS: o log é append-only e registra cada ato (decisão #44).
    // Sem identidade de paciente: só quem confirmou e qual alerta. O ACK por
    // MQTT não é autenticado (a identidade vem do payload), então a trilha o
    // marca `acknowledged_mqtt` em vez de atribuí-lo como um ACK do RPC.
    final porMqtt = user.deviceId == mqttAckDeviceId;
    final ack = await _store.acknowledge(
      alertId: alertId,
      acsId: user.id,
      microAreaId: user.microAreaId!,
      audit: AuditEvent(
        userId: user.id,
        actionType: 'write',
        resourceType: 'alert',
        resourceId: alertId,
        result: porMqtt ? 'acknowledged_mqtt' : 'acknowledged',
      ),
    );
    if (ack == null) return false;
    // Depois do commit da transação própria do store: nenhum caminho de
    // produção chama `acknowledge` com transação externa (o único
    // `serviceFor(session, transaction: …)` é o `createRedAlert`). Best-effort:
    // `alertReceived` nunca lança, então o ACK não depende dela (INV-03).
    final telemetry = _telemetry;
    if (ack.firstAcknowledgement && telemetry != null) {
      await telemetry.alertReceived(
        alertId: alertId,
        acsId: user.id,
        triggeredAt: ack.triggeredAt,
        acknowledgedAt: ack.acknowledgedAt,
        channel: porMqtt ? 'mqtt' : 'rpc',
      );
    }
    return true;
  }

  /// Texto da recusa de concluir um alerta que ninguém confirmou (#76).
  static const notAcknowledgedMessage =
      'Confirme o recebimento antes de concluir o atendimento.';

  /// Conclui o atendimento (#76, RF05): é a transição que faz o paciente ver
  /// "Atendido". Só o ACS do território do alerta, e só depois do ACK.
  /// Cada ato que encontra o alerta é auditado, inclusive a repetição e a
  /// recusa por falta de ACK; a recusa vira [ArgumentError] DEPOIS de a
  /// trilha gravar.
  Future<AlertResolveAttempt> resolve({
    required AuthenticatedUser user,
    required String alertId,
  }) async {
    Authorization.require(
      user,
      roles: {UserRole.acs},
      onDenied: () =>
          StateError('Somente ACS territorializados podem concluir atendimentos.'),
    );
    if (alertId.trim().isEmpty) {
      throw ArgumentError('O identificador do alerta é obrigatório.');
    }
    final attempt = await _store.resolve(
      alertId: alertId,
      microAreaId: user.microAreaId!,
      now: _clock().toUtc(),
      auditFor: (outcome) => AuditEvent(
        userId: user.id,
        actionType: 'write',
        resourceType: 'alert',
        resourceId: alertId,
        result: switch (outcome) {
          AlertResolveOutcome.resolved => 'resolved',
          AlertResolveOutcome.alreadyResolved => 'already_resolved',
          AlertResolveOutcome.notAcknowledged => 'denied_not_acknowledged',
          // O store não grava este; o texto existe só para o switch ser total.
          AlertResolveOutcome.notFound => 'denied_not_found',
        },
      ),
    );
    if (attempt.outcome == AlertResolveOutcome.notAcknowledged) {
      throw ArgumentError(notAcknowledgedMessage);
    }
    return attempt;
  }

  /// Teto de [openForAcs]: muito acima do que uma microárea tem aberto ao
  /// mesmo tempo, e os não confirmados vêm antes, então o corte nunca troca um
  /// pendente por um confirmado.
  static const int openAlertsLimit = 200;

  /// Alertas abertos da microárea do ACS autenticado (#80, R2): a reserva por
  /// HTTP quando o MQTT do aparelho não está conectado. A microárea vem do
  /// token (INV-01), nunca de parâmetro.
  Future<List<OpenAlertSnapshot>> openForAcs({required AuthenticatedUser user}) async {
    Authorization.require(
      user,
      roles: {UserRole.acs},
      onDenied: () => StateError('Somente ACS territorializados podem listar alertas.'),
    );
    return _store.openInMicroArea(user.microAreaId!, limit: openAlertsLimit);
  }

  /// Status do alerta mais recente do próprio paciente autenticado (RF05,
  /// decisão §5). O paciente nunca informa `patientId` — vem sempre do token
  /// (INV-05), mesma disciplina de `TriageSessionService`/`VisitSyncService`.
  Future<AlertStatusSnapshot?> statusFor({required AuthenticatedUser user}) async {
    // `requireMicroArea: false` preserva a regra de hoje: `statusFor` é
    // escopado ao próprio titular pelo `user.id` do token (INV-05), então um
    // paciente sem microárea continua podendo ver o próprio status.
    Authorization.require(
      user,
      roles: {UserRole.patient},
      onDenied: () =>
          StateError('Somente pacientes podem consultar o status do próprio alerta.'),
      requireMicroArea: false,
    );
    return _store.latestForPatient(user.id);
  }
}