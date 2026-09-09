import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/alerts/red_alert_service.dart';
import 'package:sinalacs_server/src/domain/entities/alert_delivery.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// Implementação de [AlertStore] sobre o ORM do Serverpod.
///
/// Substitui o `PostgresAlertStore`, que executava SQL cru sobre o cliente
/// `postgres` v2 — API incompatível com a v3 que o Serverpod usa.
///
/// A sessão é obtida por chamada, e não guardada no construtor, porque o
/// Serverpod amarra o ciclo de vida da conexão à `Session` da requisição.
///
/// Quando [transaction] é fornecida, todas as escritas participam dela: é o que
/// torna atômico o trio gravar alerta, registrar chave de idempotência e
/// publicar no broker.
class OrmAlertStore implements AlertStore {
  OrmAlertStore({
    required Session Function() session,
    Transaction? transaction,
  })  : _session = session,
        _transaction = transaction;

  final Session Function() _session;
  final Transaction? _transaction;

  @override
  Future<void> save(AlertDelivery alert, {required String deviceId}) async {
    await Alert.db.insertRow(
      _session(),
      Alert(
        id: UuidValue.fromString(alert.alertId),
        patientId: UuidValue.fromString(alert.patientId),
        microAreaId: UuidValue.fromString(alert.microAreaId),
        triggeredAt: alert.triggeredAt,
        riskLevel: RiskLevel.red,
        locationHash: alert.locationHash,
        status: AlertStatus.pending,
        mqttTopic: alert.topic,
        deviceId: deviceId,
        retryCount: 0,
        version: 1,
      ),
      transaction: _transaction,
    );
  }

  @override
  Future<RedAlertRecord?> findByIdempotencyKey(String idempotencyKey) async {
    final session = _session();
    final stored = await AlertIdempotencyKey.db.findFirstRow(
      session,
      where: (t) => t.key.equals(idempotencyKey),
      transaction: _transaction,
    );
    if (stored == null) return null;

    final alert = await Alert.db.findById(
      session,
      stored.alertId,
      transaction: _transaction,
    );
    if (alert == null) return null;

    return RedAlertRecord(
      delivery: AlertDelivery(
        alertId: alert.id!.uuid,
        patientId: alert.patientId.uuid,
        microAreaId: alert.microAreaId!.uuid,
        riskLevel: alert.riskLevel.name,
        locationHash: alert.locationHash,
        triggeredAt: alert.triggeredAt,
      ),
      idempotencyKey: idempotencyKey,
    );
  }

  @override
  Future<void> rememberIdempotencyKey(RedAlertRecord record) async {
    await AlertIdempotencyKey.db.insertRow(
      _session(),
      AlertIdempotencyKey(
        key: record.idempotencyKey,
        alertId: UuidValue.fromString(record.delivery.alertId),
        locationHash: record.delivery.locationHash,
        createdAt: DateTime.now().toUtc(),
      ),
      transaction: _transaction,
    );
  }

  @override
  Future<bool> acknowledge({
    required String alertId,
    required String acsId,
    required String microAreaId,
  }) async {
    final session = _session();
    final alertUuid = UuidValue.fromString(alertId);
    final acsUuid = UuidValue.fromString(acsId);
    final microAreaUuid = UuidValue.fromString(microAreaId);

    Future<bool> run(Transaction transaction) async {
      // O predicado de microárea é a barreira de territorialização: um ACS
      // nunca confirma alerta fora do seu território (INV-01).
      final alert = await Alert.db.findFirstRow(
        session,
        where: (t) =>
            t.id.equals(alertUuid) & t.microAreaId.equals(microAreaUuid),
        transaction: transaction,
      );
      if (alert == null) return false;

      final now = DateTime.now().toUtc();
      await Alert.db.updateRow(
        session,
        alert.copyWith(
          acsId: acsUuid,
          receivedAt: alert.receivedAt ?? now,
          acknowledgedAt: alert.acknowledgedAt ?? now,
          status: AlertStatus.acknowledged,
        ),
        transaction: transaction,
      );

      // Reconfirmação pelo mesmo ACS não duplica a linha de entrega — o par
      // (alertId, acsId) tem índice UNIQUE.
      final already = await AlertDeliveryRecord.db.findFirstRow(
        session,
        where: (t) => t.alertId.equals(alertUuid) & t.acsId.equals(acsUuid),
        transaction: transaction,
      );
      if (already == null) {
        await AlertDeliveryRecord.db.insertRow(
          session,
          AlertDeliveryRecord(
            alertId: alertUuid,
            acsId: acsUuid,
            acknowledgedAt: now,
          ),
          transaction: transaction,
        );
      }

      return true;
    }

    final existing = _transaction;
    return existing != null ? run(existing) : session.db.transaction(run);
  }
}
