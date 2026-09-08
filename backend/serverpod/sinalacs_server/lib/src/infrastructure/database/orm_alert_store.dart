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
class OrmAlertStore implements AlertStore {
  OrmAlertStore({required Session Function() session}) : _session = session;

  final Session Function() _session;

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

    return session.db.transaction((transaction) async {
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
        where: (t) =>
            t.alertId.equals(alertUuid) & t.acsId.equals(acsUuid),
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
    });
  }
}
