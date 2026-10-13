import 'package:uuid/uuid.dart';

import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/authorization.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
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
  /// estado sem registro. Sem alerta na microárea, nada é gravado.
  Future<bool> acknowledge({
    required String alertId,
    required String acsId,
    required String microAreaId,
    required AuditEvent audit,
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
  });

  final String alertId;
  final RiskLevel riskLevel;
  final AlertStatus status;
  final DateTime triggeredAt;
  final DateTime? acknowledgedAt;
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
  })  : _store = store,
        _outbox = outbox,
        _clock = clock ?? DateTime.now;

  final AlertStore _store;
  final AlertOutbox _outbox;
  final DateTime Function() _clock;

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

  Future<bool> acknowledge({required AuthenticatedUser user, required String alertId}) {
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
    return _store.acknowledge(
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