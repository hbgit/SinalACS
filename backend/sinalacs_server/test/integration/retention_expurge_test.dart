import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/retention/expurge_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_retention_store.dart';
import 'package:test/test.dart';

import '../support/health_data_fixtures.dart';
import 'test_tools/serverpod_test_tools.dart';

/// Prova, contra Postgres real, o expurgo LGPD-RF07 (decisões B1 + B3):
///
/// 1. linhas vencidas saem (`alerts`, `visits`, `triage_sessions`) e as
///    recentes ficam;
/// 2. os dependentes de `alerts` (`alert_deliveries`,
///    `alert_idempotency_keys`, `alert_outbox`) saem junto, antes do pai —
///    as FKs são ON DELETE NO ACTION;
/// 3. as contagens voltam corretas, apuradas ANTES do DELETE (B3).
///
/// O corte de `visits` usa COALESCE("completedAt", "scheduledAt"): a visita
/// antiga sem `completedAt` é alcançada pelo `scheduledAt` (NOT NULL) — sem o
/// fallback, ela escaparia do expurgo para sempre.
///
/// Dados sintéticos apenas (LGPD).
const _ubsId = '00000000-0000-4000-8000-0000000000c1';
const _patientId = '00000000-0000-4000-8000-0000000000c2';
const _acsId = '00000000-0000-4000-8000-0000000000c3';

final _now = DateTime.utc(2026, 10, 7, 3, 30);
final _cutoffAlerts = _now.subtract(const Duration(days: 730));
final _cutoffVisits = _now.subtract(const Duration(days: 1825));
final _cutoffTriage = _now.subtract(const Duration(days: 1825));

RetentionCutoffs get _cutoffs => RetentionCutoffs(
      alerts: _cutoffAlerts,
      visits: _cutoffVisits,
      triageSessions: _cutoffTriage,
    );

Future<void> _seed(Session session) async {
  await Ubs.db.insertRow(
    session,
    Ubs(
      id: UuidValue.fromString(_ubsId),
      name: 'UBS Retenção',
      address: 'Endereço sintético',
      city: 'São Paulo',
      state: 'SP',
    ),
  );
  await User.db.insertRow(
    session,
    User(
      id: UuidValue.fromString(_patientId),
      cpfHash: 'retencao-paciente',
      name: 'Paciente Retenção',
      birthDate: DateTime.utc(1990, 1, 1),
      role: UserRole.patient,
      createdAt: _now,
      updatedAt: _now,
    ),
  );
  await User.db.insertRow(
    session,
    User(
      id: UuidValue.fromString(_acsId),
      cpfHash: 'retencao-acs',
      name: 'ACS Retenção',
      birthDate: DateTime.utc(1985, 1, 1),
      role: UserRole.acs,
      createdAt: _now,
      updatedAt: _now,
    ),
  );
  await Patient.db.insertRow(
    session,
    await encryptedPatient(
      id: _patientId,
      emergencyContact: 'Contato retenção',
      isChronic: false,
    ),
  );
  await Acs.db.insertRow(
    session,
    Acs(
      id: UuidValue.fromString(_acsId),
      enrollmentId: 'RET-001',
      ubsId: UuidValue.fromString(_ubsId),
      active: true,
    ),
  );

  // Alerta vencido + os três dependentes; um alerta recente sem dependentes.
  final alertaVencido = await Alert.db.insertRow(
    session,
    Alert(
      patientId: UuidValue.fromString(_patientId),
      triggeredAt: _cutoffAlerts.subtract(const Duration(days: 1)),
      riskLevel: RiskLevel.red,
      locationHash: 'hash-vencido',
      status: AlertStatus.pending,
      mqttTopic: 'sinalacs/v1/alerts/retencao',
      deviceId: 'device-retencao',
      retryCount: 0,
      version: 0,
    ),
  );
  final alertaVencidoId = alertaVencido.id!;
  await AlertDeliveryRecord.db.insertRow(
    session,
    AlertDeliveryRecord(
      alertId: alertaVencidoId,
      acsId: UuidValue.fromString(_acsId),
      acknowledgedAt: _now,
    ),
  );
  await AlertIdempotencyKey.db.insertRow(
    session,
    AlertIdempotencyKey(
      key: 'chave-vencida',
      alertId: alertaVencidoId,
      locationHash: 'hash-vencido',
      createdAt: _now,
    ),
  );
  await AlertOutboxEntry.db.insertRow(
    session,
    AlertOutboxEntry(
      alertId: alertaVencidoId,
      topic: 'sinalacs/v1/alerts/retencao',
      payload: '{}',
      createdAt: _now,
      attempts: 1,
      nextAttemptAt: _now,
    ),
  );
  await Alert.db.insertRow(
    session,
    Alert(
      patientId: UuidValue.fromString(_patientId),
      triggeredAt: _now,
      riskLevel: RiskLevel.yellow,
      locationHash: 'hash-recente',
      status: AlertStatus.pending,
      mqttTopic: 'sinalacs/v1/alerts/retencao',
      deviceId: 'device-retencao',
      retryCount: 0,
      version: 0,
    ),
  );

  // Visita vencida SEM completedAt (prova o fallback para scheduledAt) e uma
  // visita recente.
  await Visit.db.insertRow(
    session,
    Visit(
      patientId: UuidValue.fromString(_patientId),
      scheduledAt: _cutoffVisits.subtract(const Duration(days: 10)),
      status: 'agendada',
      riskLevelBefore: RiskLevel.green,
      syncStatus: SyncStatus.synced,
      localId: UuidValue.fromString('00000000-0000-4000-8000-0000000000d1'),
      version: 1,
    ),
  );
  await Visit.db.insertRow(
    session,
    Visit(
      patientId: UuidValue.fromString(_patientId),
      scheduledAt: _now,
      completedAt: _now,
      status: 'realizada',
      riskLevelBefore: RiskLevel.green,
      syncStatus: SyncStatus.synced,
      localId: UuidValue.fromString('00000000-0000-4000-8000-0000000000d2'),
      version: 1,
    ),
  );

  // Triagem vencida e triagem recente.
  await TriageSession.db.insertRow(
    session,
    TriageSession(
      patientId: UuidValue.fromString(_patientId),
      resultRisk: RiskLevel.green,
      resultDisplay: 'Verde',
      createdAt: _cutoffTriage.subtract(const Duration(days: 1)),
      deviceId: 'device-retencao',
    ),
  );
  await TriageSession.db.insertRow(
    session,
    TriageSession(
      patientId: UuidValue.fromString(_patientId),
      resultRisk: RiskLevel.yellow,
      resultDisplay: 'Amarelo',
      createdAt: _now,
      deviceId: 'device-retencao',
    ),
  );
}

void main() {
  withServerpod('Expurgo LGPD-RF07 (B1 + contadores B3)', (sessionBuilder, _) {
    test('remove só o vencido — com dependentes — e conta antes de apagar',
        () async {
      final session = sessionBuilder.build();
      await _seed(session);

      final store = OrmRetentionStore(session: () => session);
      final counts = await store.purgeDue(_cutoffs);

      // B3: contagens apuradas antes do DELETE, incluindo o desdobramento
      // por risco.
      expect(counts.alerts, 1);
      expect(counts.alertsByRisk, {'red': 1});
      expect(counts.alertDeliveries, 1);
      expect(counts.alertIdempotencyKeys, 1);
      expect(counts.alertOutbox, 1);
      expect(counts.visits, 1);
      expect(counts.triageSessions, 1);

      // B1: o vencido saiu; o recente ficou.
      expect(await Alert.db.count(session), 1);
      expect(await AlertDeliveryRecord.db.count(session), 0);
      expect(await AlertIdempotencyKey.db.count(session), 0);
      expect(await AlertOutboxEntry.db.count(session), 0);
      expect(await Visit.db.count(session), 1);
      expect(await TriageSession.db.count(session), 1);

      // A visita que ficou é a recente.
      final visita = await Visit.db.findFirstRow(session);
      expect(visita!.localId.uuid, '00000000-0000-4000-8000-0000000000d2');
    });

    test('o corte sem nada vencido devolve contagens zeradas e não apaga nada',
        () async {
      final session = sessionBuilder.build();
      await _seed(session);

      final futuro = RetentionCutoffs(
        alerts: _now.subtract(const Duration(days: 36500)),
        visits: _now.subtract(const Duration(days: 36500)),
        triageSessions: _now.subtract(const Duration(days: 36500)),
      );
      final counts = await OrmRetentionStore(session: () => session)
          .purgeDue(futuro);

      expect(counts.alerts, 0);
      expect(counts.visits, 0);
      expect(counts.triageSessions, 0);
      expect(await Alert.db.count(session), 2);
      expect(await Visit.db.count(session), 2);
      expect(await TriageSession.db.count(session), 2);
    });
  });
}
