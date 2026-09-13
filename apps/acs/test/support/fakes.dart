import 'package:sinalacs_acs/core/network/auth_session.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/services/alert_feed.dart';
import 'package:sinalacs_acs/core/services/alert_queue.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';
import 'package:sinalacs_client/sinalacs_client.dart';

/// UUIDs do seed de desenvolvimento. Dados sintéticos.
const seedAcsId = '00000000-0000-4000-8000-000000000002';
const seedPatientId = '00000000-0000-4000-8000-000000000001';
const seedMicroAreaId = '00000000-0000-4000-8000-000000000003';
const otherMicroAreaId = '00000000-0000-4000-8000-000000000099';

/// UUIDs sintéticos distintos, para os testes que precisam de mais de um
/// paciente. Nome próprio não entra em teste de repositório de saúde.
String syntheticPatientId(int n) =>
    '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

class FakeAcsBackend implements AcsBackend {
  FakeAcsBackend({this.loginFailure, this.acknowledged = true, this.microAreaId = seedMicroAreaId});

  BackendFailure? loginFailure;
  bool acknowledged;
  String? microAreaId;

  /// Pacientes que `listPatients()` devolve. Vazio por padrão: um teste que
  /// não configurar isto exercita o caminho "sem paciente na microárea".
  List<MicroAreaPatient> patients = const [];

  /// Falha da chamada, como uma queda de rede ao carregar a lista.
  BackendFailure? listPatientsFailure;

  int listPatientsCount = 0;

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

  /// Falha da chamada inteira, como uma queda de rede.
  BackendFailure? syncFailure;

  /// Resultado por visita; ausente significa `synced`.
  VisitSyncResult Function(VisitSyncEntry entry)? syncResultFor;

  @override
  Future<List<VisitSyncResult>> syncVisits(List<VisitSyncEntry> visits) async {
    syncedVisitBatches.add(List.of(visits));
    final failure = syncFailure;
    if (failure != null) throw failure;

    final custom = syncResultFor;
    if (custom != null) return [for (final visit in visits) custom(visit)];

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
  Future<List<MicroAreaPatient>> listPatients() async {
    listPatientsCount++;
    final failure = listPatientsFailure;
    if (failure != null) throw failure;
    return patients;
  }

  @override
  void close() {}
}

/// Feed de alertas controlado pelo teste.
///
/// Expõe a [AlertQueue] para que o teste empurre alertas como se tivessem
/// chegado pelo broker, sem precisar de rede nem de emulador.
class FakeAlertFeed implements AlertFeed {
  FakeAlertFeed(this.queue, {this.failOnStart = false, this.failure, this.failuresBeforeSuccess = 0});

  final AlertQueue queue;
  final bool failOnStart;

  /// Falha já classificada, para exercitar cada banner do painel.
  ///
  /// `failOnStart` continua lançando um erro genérico de propósito: é o ramo de
  /// defesa do shell, o que nenhum `AlertFeedFailure` cobre.
  final AlertFeedFailure? failure;

  /// Quantas chamadas a [start] devem falhar antes de uma que conecta.
  ///
  /// É o que prova que a retentativa do shell não só acontece, mas **dá
  /// certo**: sem isto, todo teste de reconexão ficaria preso numa falha para
  /// sempre.
  final int failuresBeforeSuccess;

  bool started = false;
  bool stopped = false;
  String? startedTopicMicroArea;

  /// Quantas vezes [start] foi chamado — inclusive as que falharam.
  int startCount = 0;

  @override
  bool get isConnected => started;

  @override
  void Function(bool connected)? onConnectionChanged;

  @override
  Future<void> start({required String microAreaId, required String acsId}) async {
    startCount++;
    if (startCount <= failuresBeforeSuccess) {
      throw failure ?? const AlertFeedFailure(
        AlertFeedFailureKind.unreachable,
        title: 'Sem conexão com a central de alertas.',
        detail: 'Novos alertas podem não estar chegando.',
        transient: true,
      );
    }
    final classified = failure;
    if (classified != null) throw classified;
    if (failOnStart) throw StateError('broker indisponível');
    started = true;
    startedTopicMicroArea = microAreaId;
    onConnectionChanged?.call(true);
  }

  @override
  void stop() {
    started = false;
    stopped = true;
  }

  /// Simula a chegada de um alerta pelo tópico assinado.
  void deliver(PrioritizedAlert alert) => queue.upsert(alert);
}

/// Armazenamento que recusa gravar, para acender `persistenceFailed`.
///
/// Separar `load` de `save` importa: um banco que abre e depois falha ao gravar
/// é o caso em que o sinalizador precisa acender **depois** do `initState` —
/// exatamente o que um campo congelado ali não enxergava.
class FailingVisitStore implements VisitStore {
  FailingVisitStore({this.failOnLoad = true, this.failOnSave = true});

  final bool failOnLoad;
  final bool failOnSave;

  List<OfflineVisitRecord> _visits = <OfflineVisitRecord>[];

  @override
  Future<List<OfflineVisitRecord>> load() async {
    if (failOnLoad) throw StateError('sem banco');
    return List.of(_visits);
  }

  @override
  Future<void> save(List<OfflineVisitRecord> visits) async {
    if (failOnSave) throw StateError('sem banco');
    _visits = List.of(visits);
  }
}

/// Sincronizador que devolve o resultado programado pelo teste.
class FakeVisitSynchronizer implements VisitSynchronizer {
  FakeVisitSynchronizer({this.statusFor, this.messageFor, this.throwOnPush = false});

  /// Status por localId; ausente significa `synced`.
  String Function(OfflineVisitRecord visit)? statusFor;

  /// Motivo devolvido pelo servidor, como em `VisitSyncResult.message`.
  String? Function(OfflineVisitRecord visit)? messageFor;
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
          message: messageFor?.call(visit),
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
    patientId: seedPatientId,
    microAreaId: microAreaId,
    riskLevel: riskLevel,
    locationHash: 'sem-local-00',
    triggeredAt: triggeredAt ?? DateTime.utc(2026, 9, 11, 12),
  );
}
