import 'package:uuid/uuid.dart';

import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/domain/entities/alert_delivery.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

const _uuid = Uuid();

abstract interface class AlertPublisher {
  void publish(AlertDelivery alert);
}

abstract interface class AlertStore {
  Future<void> save(AlertDelivery alert, {required String deviceId});

  Future<bool> acknowledge({required String alertId, required String acsId, required String microAreaId});

  /// Recupera o alerta já criado para esta chave de idempotência, se houver.
  ///
  /// A deduplicação vive no armazenamento, e não em memória, para sobreviver a
  /// restart e valer entre instâncias.
  Future<RedAlertRecord?> findByIdempotencyKey(String idempotencyKey);

  /// Registra a chave na mesma unidade de trabalho do alerta.
  Future<void> rememberIdempotencyKey(RedAlertRecord record);
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

class RedAlertService {
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
  }) async {
    if (user.role != UserRole.patient || user.microAreaId == null) {
      throw StateError('Somente pacientes territorializados podem criar alertas.');
    }
    if (idempotencyKey.isEmpty || locationHash.isEmpty) {
      throw ArgumentError('A chave de idempotência e a localização são obrigatórias.');
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
    if (user.role != UserRole.acs || user.microAreaId == null) {
      throw StateError('Somente ACS territorializados podem confirmar alertas.');
    }
    if (alertId.trim().isEmpty) {
      throw ArgumentError('O identificador do alerta é obrigatório.');
    }
    return _store.acknowledge(alertId: alertId, acsId: user.id, microAreaId: user.microAreaId!);
  }
}