import 'package:postgres/postgres.dart';
import 'package:sinalacs_backend/src/application/alerts/red_alert_service.dart';
import 'package:sinalacs_backend/src/domain/entities/alert_delivery.dart';

class PostgresAlertStore implements AlertStore {
  PostgresAlertStore({required String databaseUrl}) : _databaseUrl = databaseUrl;

  final String _databaseUrl;
  PostgreSQLConnection? _connection;

  Future<void> open() async {
    final url = Uri.parse(_databaseUrl);
    _connection = PostgreSQLConnection(
      url.host,
      url.hasPort ? url.port : 5432,
      url.pathSegments.single,
      username: url.userInfo.split(':').first,
      password: url.userInfo.contains(':') ? url.userInfo.split(':').last : null,
    );
    await _connection!.open();
  }

  @override
  Future<void> save(AlertDelivery alert, {required String deviceId}) async {
    final connection = _connection;
    if (connection == null || connection.isClosed) {
      throw StateError('A conexão com o PostgreSQL não está disponível.');
    }

    await connection.transaction((context) => context.query(
          '''
            INSERT INTO alerts (
              id, patient_id, triggered_at, risk_level, location_hash, status,
              mqtt_topic, device_id, retry_count, micro_area_id
            ) VALUES (
              @id, @patientId, @triggeredAt, @riskLevel, @locationHash, 'PENDING',
              @mqttTopic, @deviceId, 0, @microAreaId
            )
          ''',
          substitutionValues: {
            'id': alert.alertId,
            'patientId': alert.patientId,
            'triggeredAt': alert.triggeredAt.toUtc(),
            'riskLevel': alert.riskLevel.toUpperCase(),
            'locationHash': alert.locationHash,
            'mqttTopic': alert.topic,
            'deviceId': deviceId,
            'microAreaId': alert.microAreaId,
          },
        ));
  }

  @override
  Future<bool> acknowledge({required String alertId, required String acsId, required String microAreaId}) async {
    final connection = _connection;
    if (connection == null || connection.isClosed) {
      throw StateError('A conexão com o PostgreSQL não está disponível.');
    }

    final result = await connection.transaction((context) async {
      final updated = await context.query(
        '''
          UPDATE alerts
          SET acs_id = @acsId,
              received_at = COALESCE(received_at, NOW()),
              acknowledged_at = COALESCE(acknowledged_at, NOW()),
              status = 'ACKNOWLEDGED'
          WHERE id = @alertId AND micro_area_id = @microAreaId
          RETURNING id
        ''',
        substitutionValues: {'alertId': alertId, 'acsId': acsId, 'microAreaId': microAreaId},
      );
      if (updated.isEmpty) return false;
      await context.query(
        '''
          INSERT INTO alert_deliveries (alert_id, acs_id, acknowledged_at)
          VALUES (@alertId, @acsId, NOW())
          ON CONFLICT (alert_id, acs_id) DO NOTHING
        ''',
        substitutionValues: {'alertId': alertId, 'acsId': acsId},
      );
      return true;
    });
    return result == true;
  }

  Future<void> close() => _connection?.close() ?? Future.value();
}