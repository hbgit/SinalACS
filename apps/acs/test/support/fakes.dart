import 'package:sinalacs_acs/core/network/auth_session.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/services/alert_feed.dart';
import 'package:sinalacs_acs/core/services/alert_queue.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';
import 'package:sinalacs_client/sinalacs_client.dart';

/// UUIDs do seed de desenvolvimento. Dados sintéticos.
const seedAcsId = '00000000-0000-4000-8000-000000000002';
const seedMicroAreaId = '00000000-0000-4000-8000-000000000003';
const otherMicroAreaId = '00000000-0000-4000-8000-000000000099';

class FakeAcsBackend implements AcsBackend {
  FakeAcsBackend({this.loginFailure, this.acknowledged = true, this.microAreaId = seedMicroAreaId});

  BackendFailure? loginFailure;
  bool acknowledged;
  String? microAreaId;

  final List<String> acknowledgedAlertIds = <String>[];
  int loginCount = 0;

  AuthSession? _session;

  @override
  AuthSession? get session => _session;

  @override
  bool get isAuthenticated => _session != null;

  @override
  Future<ServiceHealth> health() async =>
      ServiceHealth(status: 'ok', mqttConnected: true, dbConnected: true);

  @override
  Future<AuthSession> login() async {
    loginCount++;
    final failure = loginFailure;
    if (failure != null) throw failure;

    final session = AuthSession(
      accessToken: 'token-de-teste',
      tokenType: 'Bearer',
      userId: seedAcsId,
      role: 'acs',
      microAreaId: microAreaId,
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 15)),
    );
    _session = session;
    return session;
  }

  @override
  Future<AlertAckResult> acknowledge({required String alertId}) async {
    acknowledgedAlertIds.add(alertId);
    return AlertAckResult(
      alertId: alertId,
      acknowledged: acknowledged,
      status: acknowledged ? AlertStatus.acknowledged : null,
    );
  }

  final List<List<VisitSyncEntry>> syncedVisitBatches = <List<VisitSyncEntry>>[];

  @override
  Future<List<VisitSyncResult>> syncVisits(List<VisitSyncEntry> visits) async {
    syncedVisitBatches.add(List.of(visits));
    return [
      for (final visit in visits)
        VisitSyncResult(
          localId: visit.localId,
          syncStatus: SyncStatus.synced,
          serverVersion: visit.version + 1,
        ),
    ];
  }

  @override
  void close() {}
}

/// Feed de alertas controlado pelo teste.
///
/// Expõe a [AlertQueue] para que o teste empurre alertas como se tivessem
/// chegado pelo broker, sem precisar de rede nem de emulador.
class FakeAlertFeed implements AlertFeed {
  FakeAlertFeed(this.queue, {this.failOnStart = false});

  final AlertQueue queue;
  final bool failOnStart;

  bool started = false;
  bool stopped = false;
  String? startedTopicMicroArea;

  @override
  bool get isConnected => started;

  @override
  Future<void> start({required String microAreaId, required String acsId}) async {
    if (failOnStart) throw StateError('broker indisponível');
    started = true;
    startedTopicMicroArea = microAreaId;
  }

  @override
  void stop() {
    started = false;
    stopped = true;
  }

  /// Simula a chegada de um alerta pelo tópico assinado.
  void deliver(PrioritizedAlert alert) => queue.upsert(alert);
}

/// Sincronizador que devolve o resultado programado pelo teste.
class FakeVisitSynchronizer implements VisitSynchronizer {
  FakeVisitSynchronizer({this.statusFor, this.throwOnPush = false});

  /// Status por localId; ausente significa `synced`.
  String Function(OfflineVisitRecord visit)? statusFor;
  bool throwOnPush;

  final List<List<OfflineVisitRecord>> batches = <List<OfflineVisitRecord>>[];

  @override
  Future<List<VisitSyncOutcome>> push(List<OfflineVisitRecord> visits) async {
    batches.add(List.of(visits));
    if (throwOnPush) throw StateError('sem rede');

    return [
      for (final visit in visits)
        VisitSyncOutcome(
          localId: visit.localId,
          status: statusFor?.call(visit) ?? 'synced',
          serverVersion: visit.version + 1,
        ),
    ];
  }
}

PrioritizedAlert testAlert({
  required String alertId,
  String riskLevel = 'red',
  String microAreaId = seedMicroAreaId,
  DateTime? triggeredAt,
}) {
  return PrioritizedAlert(
    alertId: alertId,
    patientId: '00000000-0000-4000-8000-000000000001',
    microAreaId: microAreaId,
    riskLevel: riskLevel,
    locationHash: 'sem-local-00',
    triggeredAt: triggeredAt ?? DateTime.utc(2026, 9, 11, 12),
  );
}
