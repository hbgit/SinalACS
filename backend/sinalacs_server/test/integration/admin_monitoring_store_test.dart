import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/admin/admin_read_service.dart';
import 'package:sinalacs_server/src/application/admin/alert_escalation_service.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_admin_read_store.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_alert_escalation_store.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_audit_trail.dart';
import 'package:test/test.dart';

import '../support/health_data_fixtures.dart';
import 'test_tools/serverpod_test_tools.dart';

/// `OrmAdminReadStore.pulse` (#44, D5) contra Postgres real: `overdueRed` com a
/// regra de `overdue` da leitura, `maxChangedAt` que anda com ACK e
/// escalonamento, e escopo por UBS. Dados sintéticos; ids próprios.
const _ubsA = '00000000-0000-4000-8000-0000000045a1';
const _ubsB = '00000000-0000-4000-8000-0000000045a2';
const _ubsC = '00000000-0000-4000-8000-0000000045a3';
const _maA = '00000000-0000-4000-8000-0000000045a4';
const _maB = '00000000-0000-4000-8000-0000000045a5';
const _coord = '00000000-0000-4000-8000-0000000045a6';
const _paciente = '00000000-0000-4000-8000-0000000045a7';

final _t = DateTime.utc(2026, 10, 11, 12);
const _limite = Duration(seconds: 300);

Future<void> _seed(Session s) async {
  for (final (id, nome) in [
    (_ubsA, 'UBS A'),
    (_ubsB, 'UBS B'),
    (_ubsC, 'UBS C'),
  ]) {
    await Ubs.db.insertRow(
      s,
      Ubs(
        id: UuidValue.fromString(id),
        name: nome,
        address: 'Endereço sintético',
        city: 'São Paulo',
        state: 'SP',
      ),
    );
  }
  for (final (id, ubs) in [(_maA, _ubsA), (_maB, _ubsB)]) {
    await MicroArea.db.insertRow(
      s,
      MicroArea(
        id: UuidValue.fromString(id),
        name: 'Microárea $id',
        ubsId: UuidValue.fromString(ubs),
        geoJsonBoundary: '{}',
      ),
    );
  }
  for (final (id, role) in [
    (_paciente, UserRole.patient),
    (_coord, UserRole.coordinator),
  ]) {
    await User.db.insertRow(
      s,
      User(
        id: UuidValue.fromString(id),
        cpfHash: 'admin-pulse-$id',
        name: 'Sintético $id',
        birthDate: DateTime.utc(1980),
        role: role,
        microAreaId: role == UserRole.patient
            ? UuidValue.fromString(_maA)
            : null,
        createdAt: _t,
        updatedAt: _t,
      ),
    );
  }
  await Patient.db.insertRow(
    s,
    await encryptedPatient(
      id: _paciente,
      emergencyContact: 'contato sintético',
      isChronic: false,
    ),
  );
}

Future<Alert> _alerta(
  Session s, {
  required DateTime em,
  String? ma = _maA,
  RiskLevel risco = RiskLevel.red,
  AlertStatus status = AlertStatus.pending,
  DateTime? escalonadoEm,
}) => Alert.db.insertRow(
  s,
  Alert(
    patientId: UuidValue.fromString(_paciente),
    microAreaId: ma == null ? null : UuidValue.fromString(ma),
    triggeredAt: em,
    escalatedAt: escalonadoEm,
    riskLevel: risco,
    locationHash: 'hash-sintetico',
    status: status,
    mqttTopic: 'sinalacs/v1/microareas/${ma ?? 'x'}/alerts',
    deviceId: 'device-sintetico',
    retryCount: 0,
    version: 0,
  ),
);

void main() {
  withServerpod('Dado o pulso da monitoração (#44, D5)', (
    sessionBuilder,
    endpoints,
  ) {
    late Session session;
    late OrmAdminReadStore store;

    setUp(() async {
      session = sessionBuilder.build();
      await _seed(session);
      store = OrmAdminReadStore(
        session: () => session,
        escalationThreshold: _limite,
      );
    });

    Future<AlertsPulseCounts> pulso(AdminScope escopo, {DateTime? now}) =>
        store.pulse(escopo, now: now ?? _t, threshold: _limite);

    test('escopo sem alerta: overdueRed 0 e maxChangedAt nulo', () async {
      await _alerta(session, em: _t.subtract(const Duration(hours: 1)));
      final r = await pulso(const AdminScope.ubs(_ubsC));
      expect(r.overdueRed, 0);
      expect(r.maxChangedAt, isNull);
    });

    test(
      'overdueRed segue a regra de overdue: só vermelho pendente não escalonado, estritamente além do limite',
      () async {
        const us = Duration(microseconds: 1);
        await _alerta(session, em: _t.subtract(_limite + us)); // vence
        await _alerta(session, em: _t.subtract(_limite)); // exatamente: não
        await _alerta(session, em: _t.add(const Duration(hours: 1))); // futuro
        await _alerta(
          session,
          em: _t.subtract(const Duration(hours: 2)),
          escalonadoEm: _t.subtract(const Duration(minutes: 1)),
        ); // escalonado: não
        await _alerta(
          session,
          em: _t.subtract(const Duration(hours: 3)),
          risco: RiskLevel.yellow,
        ); // amarelo: não
        await _alerta(
          session,
          em: _t.subtract(const Duration(hours: 4)),
          status: AlertStatus.acknowledged,
        ); // reconhecido: não
        await _alerta(
          session,
          em: _t.subtract(const Duration(hours: 5)),
          ma: null,
        ); // sem microárea: só o sistema vê

        expect((await pulso(const AdminScope.ubs(_ubsA))).overdueRed, 1);
        expect((await pulso(const AdminScope.system())).overdueRed, 2);

        // Concorda, alerta a alerta, com a lista da leitura no mesmo estado.
        for (final escopo in [
          const AdminScope.ubs(_ubsA),
          const AdminScope.system(),
        ]) {
          final lista = await store.alerts(
            escopo,
            limit: 100,
            offset: 0,
            now: _t,
          );
          expect(
            (await pulso(escopo)).overdueRed,
            lista.items.where((a) => a.overdue).length,
            reason: 'escopo ${escopo.ubsId ?? 'sistema'}',
          );
        }
      },
    );

    test(
      'coordenador da UBS B não vê os alertas da UBS A: contagem e maxChangedAt só de B',
      () async {
        final b = await _alerta(
          session,
          em: _t.subtract(const Duration(hours: 2)),
          ma: _maB,
        );
        await _alerta(session, em: _t.subtract(const Duration(minutes: 30)));
        await _alerta(session, em: _t.subtract(const Duration(minutes: 20)));

        final r = await pulso(const AdminScope.ubs(_ubsB));
        expect(r.overdueRed, 1);
        expect(r.maxChangedAt, b.triggeredAt);
      },
    );

    test('maxChangedAt anda com o ACK do alerta', () async {
      final a = await _alerta(
        session,
        em: _t.subtract(const Duration(hours: 1)),
      );
      final antes = (await pulso(const AdminScope.ubs(_ubsA))).maxChangedAt;
      expect(antes, a.triggeredAt);

      final ack = _t.subtract(const Duration(minutes: 1));
      await Alert.db.updateRow(
        session,
        a.copyWith(status: AlertStatus.acknowledged, acknowledgedAt: ack),
      );
      final depois = await pulso(const AdminScope.ubs(_ubsA));
      expect(depois.maxChangedAt, ack);
      expect(depois.overdueRed, 0);
    });

    test(
      'maxChangedAt anda com o escalonamento, e escalonar tira o alerta de overdueRed',
      () async {
        final a = await _alerta(
          session,
          em: _t.subtract(const Duration(hours: 1)),
        );
        expect((await pulso(const AdminScope.ubs(_ubsA))).overdueRed, 1);

        final r =
            await OrmAlertEscalationStore(
              session: () => session,
              appendAudit: OrmAuditTrail(
                session: () => session,
                chainSecret: 'segredo-sintetico-de-teste',
              ).recordInTransaction,
            ).escalate(
              const AdminScope.system(),
              alertId: a.id!.uuid,
              actorId: _coord,
              reason: EscalationReason.noAckTimeout,
              now: _t,
              threshold: _limite,
              auditFor: (_) => AuditEvent(
                userId: _coord,
                actionType: 'write',
                resourceType: 'admin_alert',
                resourceId: a.id!.uuid,
                result: 'escalated:no_ack_timeout',
              ),
            );
        expect(r.outcome, EscalationOutcome.escalated);

        final depois = await pulso(const AdminScope.ubs(_ubsA));
        expect(depois.maxChangedAt, _t);
        expect(depois.overdueRed, 0);
      },
    );
  });
}
