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
}

class RedAlertRecord {
  const RedAlertRecord({required this.delivery, required this.idempotencyKey});

  final AlertDelivery delivery;
  final String idempotencyKey;
}

class RedAlertService {
  RedAlertService({required AlertPublisher publisher, required AlertStore store, DateTime Function()? clock})
      : _publisher = publisher,
        _store = store,
        _clock = clock ?? DateTime.now;

  final AlertPublisher _publisher;
  final AlertStore _store;
  final DateTime Function() _clock;
  final Map<String, RedAlertRecord> _alertsByIdempotencyKey = {};

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

    final existing = _alertsByIdempotencyKey[idempotencyKey];
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
    _alertsByIdempotencyKey[idempotencyKey] = record;
    await _store.save(alert, deviceId: user.deviceId);
    _publisher.publish(alert);
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