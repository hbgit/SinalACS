import 'dart:convert';

import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/admin/alert_escalation_service.dart';
import 'package:sinalacs_server/src/application/alerts/red_alert_service.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_alert_escalation_store.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_alert_store.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_audit_trail.dart';
import 'package:test/test.dart';

import '../support/health_data_fixtures.dart';
import 'test_tools/serverpod_test_tools.dart';

/// Colunas de escalonamento de `alerts` e o store ORM do escalonamento (#44),
/// com Postgres real. Dados sintéticos; ids próprios.
const _paciente = '00000000-0000-4000-8000-0000000000a1';
const _ubsA = '00000000-0000-4000-8000-0000000044e1';
const _ubsB = '00000000-0000-4000-8000-0000000044e2';
const _maA = '00000000-0000-4000-8000-0000000044e3';
const _maB = '00000000-0000-4000-8000-0000000044e4';
const _coord = '00000000-0000-4000-8000-0000000044e5';
const _acs = '00000000-0000-4000-8000-0000000044e6';
/// Segundo ACS da MESMA microárea (#88): o ACK dele sobre um alerta já
/// confirmado não pode trocar o responsável.
const _acsB = '00000000-0000-4000-8000-0000000044e7';
const _inexistente = '00000000-0000-4000-8000-0000000044ff';
const _segredo = 'segredo-sintetico-da-cadeia';
final _t = DateTime.utc(2026, 10, 11, 12);
const _limite = Duration(seconds: 300);

Future<Alert> _alerta(
  Session s, {
  Alert? base,
  String? ma = _maA,
  Duration idade = const Duration(seconds: 301),
  RiskLevel risco = RiskLevel.red,
  AlertStatus status = AlertStatus.pending,
}) => Alert.db.insertRow(
  s,
  base ??
      Alert(
        patientId: UuidValue.fromString(_paciente),
        microAreaId: ma == null ? null : UuidValue.fromString(ma),
        triggeredAt: _t.subtract(idade),
        riskLevel: risco,
        locationHash: 'hash-sintetico',
        locationCell: '-1580:-4783',
        status: status,
        mqttTopic: 'sinalacs/v1/microareas/${ma ?? 'x'}/alerts',
        deviceId: 'device-sintetico',
        retryCount: 0,
        version: 1,
      ),
);

Future<void> _semear(Session s) async {
  await User.db.insertRow(
    s,
    User(
      id: UuidValue.fromString(_paciente),
      cpfHash: 'alert-escalation-paciente',
      name: 'Paciente Sintético',
      birthDate: DateTime.utc(1980),
      role: UserRole.patient,
      createdAt: _t,
      updatedAt: _t,
    ),
  );
  await Patient.db.insertRow(
    s,
    await encryptedPatient(
      id: _paciente,
      emergencyContact: 'x',
      isChronic: false,
    ),
  );
  for (final (id, nome) in [(_ubsA, 'UBS A esc'), (_ubsB, 'UBS B esc')]) {
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
  // Dois ACS na mesma microárea (#88).
  for (final (id, matricula) in [(_acs, 'ACS-ESC-1'), (_acsB, 'ACS-ESC-2')]) {
    await User.db.insertRow(
      s,
      User(
        id: UuidValue.fromString(id),
        cpfHash: 'alert-escalation-$matricula',
        name: 'ACS Sintético $matricula',
        birthDate: DateTime.utc(1980),
        role: UserRole.acs,
        microAreaId: UuidValue.fromString(_maA),
        createdAt: _t,
        updatedAt: _t,
      ),
    );
    await Acs.db.insertRow(
      s,
      Acs(
        id: UuidValue.fromString(id),
        enrollmentId: matricula,
        ubsId: UuidValue.fromString(_ubsA),
        active: true,
      ),
    );
  }
  // Autor das linhas de auditoria (`audit_logs.userId` referencia `users`).
  await User.db.insertRow(
    s,
    User(
      id: UuidValue.fromString(_coord),
      cpfHash: 'alert-escalation-coord',
      name: 'Coordenação Sintética',
      birthDate: DateTime.utc(1980),
      role: UserRole.coordinator,
      createdAt: _t,
      updatedAt: _t,
    ),
  );
  await StaffAccount.db.insertRow(
    s,
    StaffAccount(
      id: UuidValue.fromString(_coord),
      enrollmentId: 'COO-ESC-1',
      active: true,
      ubsId: UuidValue.fromString(_ubsA),
    ),
  );
}

/// Mesma forma do `auditFor` do serviço: o store só a chama nos dois desfechos
/// que audita.
AuditEvent Function(EscalationOutcome) _auditFor(
  String alertId, {
  String reason = 'no_ack_timeout',
}) =>
    (o) => AuditEvent(
      userId: _coord,
      actionType: 'write',
      resourceType: 'admin_alert',
      resourceId: alertId,
      result:
          '${o == EscalationOutcome.alreadyEscalated ? 'already_escalated' : 'escalated'}:$reason',
    );

/// Trilha em memória: grava o que o store pediu dentro da transação.
class _AuditoriaGravada {
  final eventos = <AuditEvent>[];
  bool falhar = false;

  Future<void> call(Session s, Transaction t, AuditEvent e) async {
    if (falhar) throw StateError('falha injetada na auditoria (só em teste)');
    eventos.add(e);
  }
}

Future<int> _outbox(Session s, UuidValue alertId) =>
    AlertOutboxEntry.db.count(s, where: (t) => t.alertId.equals(alertId));

Future<List<String>> _resultados(Session s, UuidValue alertId) async => [
  for (final l in await AuditLog.db.find(
    s,
    where: (t) => t.resourceId.equals(alertId),
    orderBy: (t) => t.sequence,
  ))
    l.result,
];

void main() {
  withServerpod('Dado as colunas de escalonamento de alerts (#44)', (
    sessionBuilder,
    endpoints,
  ) {
    late Session session;
    setUp(() async {
      session = sessionBuilder.build();
      await _semear(session);
    });

    test('um alerta novo nasce sem escalonamento', () async {
      final criado = await _alerta(session);
      final lido = await Alert.db.findById(session, criado.id!);
      expect(lido!.escalatedAt, isNull);
      expect(lido.escalatedBy, isNull);
      expect(lido.escalationReason, isNull);
    });

    test('o escalonamento persiste data, autor e motivo fechado', () async {
      final autor = UuidValue.fromString(_paciente);
      final criado = await _alerta(session);
      await Alert.db.updateRow(
        session,
        criado.copyWith(
          escalatedAt: _t,
          escalatedBy: autor,
          escalationReason: EscalationReason.noAckTimeout,
        ),
      );
      final lido = await Alert.db.findById(session, criado.id!);
      expect(lido!.escalatedAt, _t);
      expect(lido.escalatedBy, autor);
      expect(lido.escalationReason, EscalationReason.noAckTimeout);
    });
  });

  withServerpod('Dado o store ORM do escalonamento (#44)', (
    sessionBuilder,
    endpoints,
  ) {
    late Session session;
    late OrmAlertEscalationStore store;

    setUp(() async {
      session = sessionBuilder.build();
      await _semear(session);
      store = OrmAlertEscalationStore(
        session: () => session,
        appendAudit: OrmAuditTrail(
          session: () => session,
          chainSecret: _segredo,
        ).recordInTransaction,
      );
    });

    Future<EscalationAttempt> escalar(
      String alertId, {
      AdminScope scope = const AdminScope.ubs(_ubsA),
      EscalationReason reason = EscalationReason.noAckTimeout,
      String reasonSnake = 'no_ack_timeout',
      DateTime? now,
      OrmAlertEscalationStore? via,
    }) => (via ?? store).escalate(
      scope,
      alertId: alertId,
      actorId: _coord,
      reason: reason,
      now: now ?? _t,
      threshold: _limite,
      auditFor: _auditFor(alertId, reason: reasonSnake),
    );

    test(
      'vencido: grava as 3 colunas, 1 reforço no outbox e 1 auditoria',
      () async {
        final a = await _alerta(session);
        final r = await escalar(a.id!.uuid);
        expect(r.outcome, EscalationOutcome.escalated);
        expect(r.escalatedAt, _t);

        final lido = (await Alert.db.findById(session, a.id!))!;
        expect(lido.escalatedAt, _t);
        expect(lido.escalatedBy, UuidValue.fromString(_coord));
        expect(lido.escalationReason, EscalationReason.noAckTimeout);
        // D3: o alerta segue pendente; nada além das 3 colunas muda.
        expect(lido.status, AlertStatus.pending);
        expect(lido.acknowledgedAt, isNull);
        expect(lido.acsId, isNull);
        expect(lido.version, a.version);
        expect(lido.riskLevel, RiskLevel.red);
        expect(lido.triggeredAt, a.triggeredAt);

        final entradas = await AlertOutboxEntry.db.find(
          session,
          where: (t) => t.alertId.equals(a.id!),
        );
        expect(entradas, hasLength(1));
        final e = entradas.single;
        expect(e.topic, 'sinalacs/v1/microareas/$_maA/alerts');
        expect(e.publishedAt, isNull);
        expect(e.attempts, 0);
        expect(e.nextAttemptAt, _t, reason: 'elegível já');
        final payload = jsonDecode(e.payload) as Map<String, dynamic>;
        // Sem identidade além do envelope que o alerta já tinha.
        expect(payload.keys.toSet(), {
          'version',
          'alert_id',
          'patient_id',
          'micro_area_id',
          'risk_level',
          'location_hash',
          'location_cell',
          'triggered_at',
          'escalated',
        });
        expect(payload['alert_id'], a.id!.uuid);
        expect(payload['micro_area_id'], _maA);
        expect(payload['risk_level'], 'red');
        expect(payload['escalated'], isTrue);
        expect(payload.values.join(' '), isNot(contains(_coord)));

        expect(await _resultados(session, a.id!), ['escalated:no_ack_timeout']);
      },
    );

    test(
      'replay: alreadyEscalated, carimbo original, sem 2º reforço',
      () async {
        final a = await _alerta(session);
        await escalar(a.id!.uuid);
        final depois = _t.add(const Duration(minutes: 10));
        final r = await escalar(
          a.id!.uuid,
          now: depois,
          reason: EscalationReason.acsUnreachable,
          reasonSnake: 'acs_unreachable',
        );
        expect(r.outcome, EscalationOutcome.alreadyEscalated);
        expect(r.escalatedAt, _t);

        final lido = (await Alert.db.findById(session, a.id!))!;
        expect(lido.escalatedAt, _t);
        expect(lido.escalationReason, EscalationReason.noAckTimeout);
        expect(lido.escalatedBy, UuidValue.fromString(_coord));
        expect(await _outbox(session, a.id!), 1);
        expect(await _resultados(session, a.id!), [
          'escalated:no_ack_timeout',
          'already_escalated:acs_unreachable',
        ]);
      },
    );

    test(
      'precedência e recusas: nada é escrito e o store não audita',
      () async {
        final casos = <(String, Future<String> Function(), EscalationOutcome)>[
          ('inexistente', () async => _inexistente, EscalationOutcome.notFound),
          (
            'outra UBS',
            () async => (await _alerta(session, ma: _maB)).id!.uuid,
            EscalationOutcome.notFound,
          ),
          (
            'sem microárea, para o coordenador',
            () async => (await _alerta(session, ma: null)).id!.uuid,
            EscalationOutcome.notFound,
          ),
          (
            // Precedência: escopo antes de cor.
            'amarelo de outra UBS',
            () async => (await _alerta(
              session,
              ma: _maB,
              risco: RiskLevel.yellow,
            )).id!.uuid,
            EscalationOutcome.notFound,
          ),
          (
            'amarelo',
            () async =>
                (await _alerta(session, risco: RiskLevel.yellow)).id!.uuid,
            EscalationOutcome.notRed,
          ),
          (
            'verde',
            () async =>
                (await _alerta(session, risco: RiskLevel.green)).id!.uuid,
            EscalationOutcome.notRed,
          ),
          (
            // Precedência: cor antes de status.
            'verde confirmado',
            () async => (await _alerta(
              session,
              risco: RiskLevel.green,
              status: AlertStatus.acknowledged,
            )).id!.uuid,
            EscalationOutcome.notRed,
          ),
          (
            'confirmado',
            () async => (await _alerta(
              session,
              status: AlertStatus.acknowledged,
            )).id!.uuid,
            EscalationOutcome.notPending,
          ),
          (
            'exatamente no prazo (300 s)',
            () async => (await _alerta(session, idade: _limite)).id!.uuid,
            EscalationOutcome.notDue,
          ),
          (
            '1 µs antes do prazo',
            () async => (await _alerta(
              session,
              idade: _limite - const Duration(microseconds: 1),
            )).id!.uuid,
            EscalationOutcome.notDue,
          ),
          (
            'abaixo do prazo',
            () async => (await _alerta(
              session,
              idade: const Duration(seconds: 10),
            )).id!.uuid,
            EscalationOutcome.notDue,
          ),
          (
            'triggeredAt no futuro',
            () async => (await _alerta(
              session,
              idade: const Duration(hours: -2),
            )).id!.uuid,
            EscalationOutcome.notDue,
          ),
        ];
        for (final (nome, criar, esperado) in casos) {
          final id = await criar();
          final r = await escalar(id);
          expect(r.outcome, esperado, reason: nome);
          expect(r.escalatedAt, isNull, reason: nome);
          final uuid = UuidValue.fromString(id);
          final lido = await Alert.db.findById(session, uuid);
          expect(lido?.escalatedAt, isNull, reason: nome);
          expect(await _outbox(session, uuid), 0, reason: nome);
          expect(await _resultados(session, uuid), isEmpty, reason: nome);
        }
      },
    );

    test('precedência: confirmado E já escalonado → notPending', () async {
      final a = await _alerta(session);
      await escalar(a.id!.uuid);
      await Alert.db.updateRow(
        session,
        (await Alert.db.findById(
          session,
          a.id!,
        ))!.copyWith(status: AlertStatus.acknowledged),
      );
      final r = await escalar(a.id!.uuid);
      expect(r.outcome, EscalationOutcome.notPending);
    });

    test(
      'precedência: já escalonado antes do prazo → alreadyEscalated',
      () async {
        final a = await _alerta(session);
        await escalar(a.id!.uuid);
        // Um relógio que voltou para dentro do prazo não troca o desfecho.
        final r = await escalar(
          a.id!.uuid,
          now: _t.subtract(const Duration(seconds: 200)),
        );
        expect(r.outcome, EscalationOutcome.alreadyEscalated);
        expect(r.escalatedAt, _t);
      },
    );

    test('1 s além do prazo: vence', () async {
      final a = await _alerta(
        session,
        idade: _limite + const Duration(seconds: 1),
      );
      expect((await escalar(a.id!.uuid)).outcome, EscalationOutcome.escalated);
    });

    test('1 µs além do prazo: vence (estritamente maior)', () async {
      final a = await _alerta(
        session,
        idade: _limite + const Duration(microseconds: 1),
      );
      expect((await escalar(a.id!.uuid)).outcome, EscalationOutcome.escalated);
    });

    test('administrador: qualquer UBS e alerta sem microárea', () async {
      final b = await _alerta(session, ma: _maB);
      expect(
        (await escalar(b.id!.uuid, scope: const AdminScope.system())).outcome,
        EscalationOutcome.escalated,
      );
      expect(await _outbox(session, b.id!), 1);

      // Sem microárea não há tópico de território: escalona e audita, sem
      // reforço (não há a quem entregar).
      final semMa = await _alerta(session, ma: null);
      expect(
        (await escalar(
          semMa.id!.uuid,
          scope: const AdminScope.system(),
        )).outcome,
        EscalationOutcome.escalated,
      );
      expect(await _outbox(session, semMa.id!), 0);
      expect(await _resultados(session, semMa.id!), [
        'escalated:no_ack_timeout',
      ]);
    });

    test('id que não é UUID: notFound sem consultar o banco', () async {
      final r = await escalar("x'; DROP TABLE alerts;--");
      expect(r.outcome, EscalationOutcome.notFound);
    });

    test('auditoria falhando desfaz UPDATE e reforço (fail-closed)', () async {
      final a = await _alerta(session);
      final trilha = _AuditoriaGravada()..falhar = true;
      final quebrado = OrmAlertEscalationStore(
        session: () => session,
        appendAudit: trilha.call,
      );
      await expectLater(
        escalar(a.id!.uuid, via: quebrado),
        throwsA(isA<StateError>()),
      );
      final lido = (await Alert.db.findById(session, a.id!))!;
      expect(lido.escalatedAt, isNull);
      expect(lido.escalatedBy, isNull);
      expect(lido.escalationReason, isNull);
      expect(await _outbox(session, a.id!), 0);
      expect(await AuditLog.db.count(session), 0);
    });

    test(
      'ACK depois do escalonamento preserva as colunas de escalonamento',
      () async {
        final a = await _alerta(session);
        await escalar(a.id!.uuid);
        final ok =
            await OrmAlertStore(
              session: () => session,
              appendAudit: (s, t, e) async {},
            ).acknowledge(
              alertId: a.id!.uuid,
              acsId: _acs,
              microAreaId: _maA,
              auditFor: (_) => const AuditEvent(
                userId: _acs,
                actionType: 'write',
                resourceType: 'alert',
                resourceId: _paciente,
                result: 'acknowledged',
              ),
            );
        expect(ok!.outcome, AlertAckOutcome.acknowledged);
        final lido = (await Alert.db.findById(session, a.id!))!;
        expect(lido.status, AlertStatus.acknowledged);
        expect(lido.escalatedAt, _t);
        expect(lido.escalationReason, EscalationReason.noAckTimeout);
      },
    );

    test(
      'ubsOf: UBS do coordenador; id inválido ou sem conta → null',
      () async {
        expect(await store.ubsOf(_coord), _ubsA);
        expect(await store.ubsOf(_inexistente), isNull);
        expect(await store.ubsOf('nao-e-uuid'), isNull);
      },
    );
  });

  // ACK sob a trava (#86): o status devolvido é o da linha travada, e o
  // ACK que não muda o status não pede a auditoria de uma mudança.
  withServerpod('Dado o ACK do store ORM (#86)', (sessionBuilder, endpoints) {
    late Session session;
    late _AuditoriaGravada trilha;
    late OrmAlertStore store;

    setUp(() async {
      session = sessionBuilder.build();
      await _semear(session);
      trilha = _AuditoriaGravada();
      store = OrmAlertStore(session: () => session, appendAudit: trilha.call);
    });

    Future<AlertAckRecord?> confirmar(String alertId, {String ma = _maA, String acs = _acs}) =>
        store.acknowledge(
          alertId: alertId,
          acsId: acs,
          microAreaId: ma,
          auditFor: (o) => AuditEvent(
            userId: acs,
            actionType: 'write',
            resourceType: 'alert',
            resourceId: alertId,
            result: o.name,
          ),
        );

    Future<Alert> alertaCom(AlertStatus status) async {
      final a = await _alerta(session);
      return Alert.db.updateRow(
        session,
        a.copyWith(
          status: status,
          acknowledgedAt:
              status == AlertStatus.acknowledged || status == AlertStatus.resolved
                  ? _t
                  : null,
          resolvedAt: status == AlertStatus.resolved ? _t : null,
        ),
      );
    }

    test('matriz: status lido → desfecho, status gravado e uma linha de auditoria', () async {
      const matriz = <(AlertStatus, AlertAckOutcome, AlertStatus)>[
        (AlertStatus.pending, AlertAckOutcome.acknowledged, AlertStatus.acknowledged),
        (AlertStatus.escalated, AlertAckOutcome.acknowledged, AlertStatus.acknowledged),
        (AlertStatus.acknowledged, AlertAckOutcome.alreadyAcknowledged, AlertStatus.acknowledged),
        (AlertStatus.resolved, AlertAckOutcome.alreadyResolved, AlertStatus.resolved),
      ];
      for (final (lido, desfecho, gravado) in matriz) {
        trilha.eventos.clear();
        final a = await alertaCom(lido);

        final r = await confirmar(a.id!.uuid);

        expect(r!.outcome, desfecho, reason: '$lido');
        expect(r.status, gravado, reason: '$lido');
        final depois = (await Alert.db.findById(session, a.id!))!;
        expect(depois.status, gravado, reason: '$lido');
        expect(trilha.eventos.single.result, desfecho.name, reason: '$lido');
      }
    });

    test('ACK sobre resolved não muda o status gravado nem o resolvedAt', () async {
      final a = await alertaCom(AlertStatus.resolved);

      await confirmar(a.id!.uuid);

      final depois = (await Alert.db.findById(session, a.id!))!;
      expect(depois.status, AlertStatus.resolved);
      expect(depois.resolvedAt, _t);
    });

    test('ACK de outro ACS sobre alerta já confirmado não troca acsId (#88)', () async {
      final a = await alertaCom(AlertStatus.acknowledged);
      await Alert.db.updateRow(session, a.copyWith(acsId: UuidValue.fromString(_acs)));

      final r = await confirmar(a.id!.uuid, acs: _acsB);

      expect(r!.outcome, AlertAckOutcome.alreadyAcknowledged);
      final depois = (await Alert.db.findById(session, a.id!))!;
      expect(depois.acsId!.uuid, _acs, reason: 'acsId é de quem confirmou primeiro');
      expect(depois.acknowledgedAt, _t);
      expect(trilha.eventos.single.result, 'alreadyAcknowledged');
      expect(trilha.eventos.single.userId, _acsB);
    });

    test('matriz #88: só pending/escalated escrevem alerts; acsId/receivedAt/acknowledgedAt preservados', () async {
      const matriz = <(AlertStatus, String)>[
        (AlertStatus.pending, _acsB),
        (AlertStatus.escalated, _acsB),
        (AlertStatus.acknowledged, _acs),
        (AlertStatus.resolved, _acs),
      ];
      for (final (lido, esperado) in matriz) {
        trilha.eventos.clear();
        final a = await alertaCom(lido);
        // acsId já preenchido mesmo em pending (os scripts de e2e inserem
        // assim): pending é "ninguém confirmou", e o primeiro ACK o troca.
        final semeado = await Alert.db.updateRow(
          session,
          a.copyWith(acsId: UuidValue.fromString(_acs), receivedAt: _t),
        );

        final r = await confirmar(a.id!.uuid, acs: _acsB);

        final depois = (await Alert.db.findById(session, a.id!))!;
        expect(depois.acsId!.uuid, esperado, reason: '$lido');
        expect(depois.receivedAt, _t, reason: '$lido');
        if (lido == AlertStatus.acknowledged || lido == AlertStatus.resolved) {
          expect(depois.acknowledgedAt, semeado.acknowledgedAt, reason: '$lido');
          expect(r!.acknowledgedAt, semeado.acknowledgedAt, reason: '$lido');
          expect(r.firstAcknowledgement, isFalse, reason: '$lido');
        } else {
          expect(r!.firstAcknowledgement, isTrue, reason: '$lido');
          expect(depois.acknowledgedAt, r.acknowledgedAt, reason: '$lido');
        }
        expect(trilha.eventos.single.userId, _acsB, reason: '$lido');
      }
    });

    test('ACK repetido pelo mesmo ACS não escreve alerts nem duplica a entrega', () async {
      final a = await alertaCom(AlertStatus.acknowledged);
      await Alert.db.updateRow(session, a.copyWith(acsId: UuidValue.fromString(_acs)));

      await confirmar(a.id!.uuid);

      final entregas = await AlertDeliveryRecord.db.find(
        session,
        where: (t) => t.alertId.equals(a.id!),
      );
      expect(entregas, hasLength(1));
      expect(entregas.single.acsId.uuid, _acs);
    });

    test('entrega do segundo ACS é registrada e desfeita se a trilha falhar (fail-closed)', () async {
      final a = await alertaCom(AlertStatus.acknowledged);
      await Alert.db.updateRow(session, a.copyWith(acsId: UuidValue.fromString(_acs)));
      final falha = OrmAlertStore(
        session: () => session,
        appendAudit: (s, t, e) async => throw StateError('trilha fora'),
      );

      await expectLater(
        falha.acknowledge(
          alertId: a.id!.uuid,
          acsId: _acsB,
          microAreaId: _maA,
          auditFor: (o) => AuditEvent(
            userId: _acsB,
            actionType: 'write',
            resourceType: 'alert',
            resourceId: a.id!.uuid,
            result: o.name,
          ),
        ),
        throwsStateError,
      );

      expect(
        await AlertDeliveryRecord.db.count(
          session,
          where: (t) => t.alertId.equals(a.id!) & t.acsId.equals(UuidValue.fromString(_acsB)),
        ),
        0,
      );
    });

    test('alerta de outra microárea: null e nenhuma linha de auditoria', () async {
      final a = await _alerta(session, ma: _maB);

      expect(await confirmar(a.id!.uuid), isNull);
      expect(trilha.eventos, isEmpty);
    });

    test('o índice único de alert_deliveries é sobre o par (alertId, acsId) (#88)', () async {
      final linhas = await session.db.unsafeQuery(
        "SELECT indexdef FROM pg_indexes WHERE tablename = 'alert_deliveries' "
        "AND indexname = 'alert_deliveries_alert_acs_key'",
      );
      final def = linhas.single[0] as String;
      expect(def, contains('UNIQUE INDEX'));
      expect(def, contains('("alertId", "acsId")'));
    });

    test('a reentrega não duplica e o segundo ACS entra: um par por ACS', () async {
      final a = await alertaCom(AlertStatus.acknowledged);
      await confirmar(a.id!.uuid); // A, reentrega
      await confirmar(a.id!.uuid, acs: _acsB); // B
      await confirmar(a.id!.uuid, acs: _acsB); // B, reentrega
      final entregas = await AlertDeliveryRecord.db.find(
        session,
        where: (t) => t.alertId.equals(a.id!),
      );
      expect(entregas.map((e) => e.acsId.uuid).toSet(), {_acs, _acsB});
      expect(entregas, hasLength(2));
    });

    test('entrega já registrada para alerta ainda pending: o ACK não falha e não duplica', () async {
      final a = await _alerta(session);
      await AlertDeliveryRecord.db.insertRow(
        session,
        AlertDeliveryRecord(
          alertId: a.id!,
          acsId: UuidValue.fromString(_acs),
          acknowledgedAt: _t,
        ),
      );
      final r = await confirmar(a.id!.uuid);
      expect(r!.outcome, AlertAckOutcome.acknowledged);
      final entregas = await AlertDeliveryRecord.db.find(
        session,
        where: (t) => t.alertId.equals(a.id!),
      );
      expect(entregas, hasLength(1));
      expect(entregas.single.acknowledgedAt, _t, reason: 'a primeira entrega não é reescrita');
    });
  });

  // Corrida: rollback desligado (com ele, sessões concorrentes colidem no
  // savepoint compartilhado do harness). Trilha em memória, para não commitar
  // linhas em `audit_logs` que as suítes paralelas conferem sem filtro; a
  // limpeza do `finally` remove o resto.
  withServerpod(
    'Dado o store ORM do escalonamento (#44), sem rollback (corrida)',
    (sessionBuilder, endpoints) {
      const rodadas = 5;

      Future<void> limpar(Session s) async {
        final alertas = await Alert.db.find(
          s,
          where: (t) => t.patientId.equals(UuidValue.fromString(_paciente)),
        );
        for (final a in alertas) {
          await AlertDeliveryRecord.db.deleteWhere(
            s,
            where: (t) => t.alertId.equals(a.id!),
          );
          await AlertOutboxEntry.db.deleteWhere(
            s,
            where: (t) => t.alertId.equals(a.id!),
          );
        }
        await Alert.db.deleteWhere(
          s,
          where: (t) => t.patientId.equals(UuidValue.fromString(_paciente)),
        );
        await Acs.db.deleteWhere(
          s,
          where: (t) =>
              t.id.equals(UuidValue.fromString(_acs)) |
              t.id.equals(UuidValue.fromString(_acsB)),
        );
        await StaffAccount.db.deleteWhere(
          s,
          where: (t) => t.id.equals(UuidValue.fromString(_coord)),
        );
        await Patient.db.deleteWhere(
          s,
          where: (t) => t.id.equals(UuidValue.fromString(_paciente)),
        );
        await User.db.deleteWhere(
          s,
          where: (t) =>
              t.id.equals(UuidValue.fromString(_paciente)) |
              t.id.equals(UuidValue.fromString(_acs)) |
              t.id.equals(UuidValue.fromString(_acsB)) |
              t.id.equals(UuidValue.fromString(_coord)),
        );
        await MicroArea.db.deleteWhere(
          s,
          where: (t) =>
              t.id.equals(UuidValue.fromString(_maA)) |
              t.id.equals(UuidValue.fromString(_maB)),
        );
        await Ubs.db.deleteWhere(
          s,
          where: (t) =>
              t.id.equals(UuidValue.fromString(_ubsA)) |
              t.id.equals(UuidValue.fromString(_ubsB)),
        );
      }

      test(
        'duas chamadas simultâneas: 1 escalatedAt, 1 reforço, 1+1 auditoria',
        () async {
          final s = sessionBuilder.build();
          await limpar(s);
          try {
            await _semear(s);
            for (var i = 0; i < rodadas; i++) {
              final a = await _alerta(s);
              final trilha = _AuditoriaGravada();
              Future<EscalationAttempt> tentar(DateTime now) =>
                  OrmAlertEscalationStore(
                    session: sessionBuilder.build,
                    appendAudit: trilha.call,
                  ).escalate(
                    const AdminScope.ubs(_ubsA),
                    alertId: a.id!.uuid,
                    actorId: _coord,
                    reason: EscalationReason.noAckTimeout,
                    now: now,
                    threshold: _limite,
                    auditFor: _auditFor(a.id!.uuid),
                  );

              final r = await Future.wait([
                tentar(_t),
                tentar(_t.add(const Duration(seconds: 1))),
              ]);
              final desfechos = r.map((x) => x.outcome).toList();
              expect(
                desfechos.where((o) => o == EscalationOutcome.escalated),
                hasLength(1),
                reason: 'rodada $i: $desfechos',
              );
              expect(
                desfechos.where((o) => o == EscalationOutcome.alreadyEscalated),
                hasLength(1),
                reason: 'rodada $i: $desfechos',
              );
              // Os dois devolvem o MESMO carimbo: o do vencedor.
              expect(r[0].escalatedAt, r[1].escalatedAt, reason: 'rodada $i');
              final lido = (await Alert.db.findById(s, a.id!))!;
              expect(lido.escalatedAt, r[0].escalatedAt, reason: 'rodada $i');
              expect(lido.status, AlertStatus.pending, reason: 'rodada $i');
              expect(await _outbox(s, a.id!), 1, reason: 'rodada $i');
              expect(
                trilha.eventos.map((e) => e.result).toList()..sort(),
                [
                  'already_escalated:no_ack_timeout',
                  'escalated:no_ack_timeout',
                ],
                reason: 'rodada $i',
              );
            }
          } finally {
            await limpar(s);
          }
        },
      );

      test(
        'ACK e conclusão simultâneos: o status devolvido é o da linha travada (#86)',
        () async {
          final s = sessionBuilder.build();
          await limpar(s);
          try {
            await _semear(s);
            for (var i = 0; i < rodadas; i++) {
              final criado = await _alerta(s);
              final a = await Alert.db.updateRow(
                s,
                criado.copyWith(status: AlertStatus.acknowledged, acknowledgedAt: _t),
              );
              // Uma trilha só: ela é gravada dentro de cada transação, sob a
              // trava da linha, então a ordem dos eventos é a ordem da trava.
              final trilha = _AuditoriaGravada();
              OrmAlertStore novo() => OrmAlertStore(
                    session: sessionBuilder.build,
                    appendAudit: trilha.call,
                  );
              AuditEvent evento(String result) => AuditEvent(
                    userId: _acs,
                    actionType: 'write',
                    resourceType: 'alert',
                    resourceId: a.id!.uuid,
                    result: result,
                  );

              final r = await Future.wait<Object?>([
                novo().acknowledge(
                  alertId: a.id!.uuid,
                  acsId: _acs,
                  microAreaId: _maA,
                  auditFor: (o) => evento('ack:${o.name}'),
                ),
                novo().resolve(
                  alertId: a.id!.uuid,
                  microAreaId: _maA,
                  now: _t,
                  auditFor: (o) => evento('resolve:${o.name}'),
                ),
              ]);
              final ack = r[0]! as AlertAckRecord;
              final resolvido = r[1]! as AlertResolveAttempt;

              expect(resolvido.outcome, AlertResolveOutcome.resolved, reason: 'rodada $i');
              final lido = (await Alert.db.findById(s, a.id!))!;
              expect(lido.status, AlertStatus.resolved, reason: 'rodada $i');
              final ordem = trilha.eventos.map((e) => e.result).toList();
              if (ordem.first == 'resolve:resolved') {
                expect(ack.outcome, AlertAckOutcome.alreadyResolved, reason: 'rodada $i: $ordem');
                expect(ack.status, AlertStatus.resolved, reason: 'rodada $i: $ordem');
              } else {
                expect(ack.outcome, AlertAckOutcome.alreadyAcknowledged, reason: 'rodada $i: $ordem');
                expect(ack.status, AlertStatus.acknowledged, reason: 'rodada $i: $ordem');
              }
            }
          } finally {
            await limpar(s);
          }
        },
      );

      test(
        'dois ACS confirmam o mesmo pendente: o UPDATE que casa vira acsId, o outro é idempotente (#88)',
        () async {
          final s = sessionBuilder.build();
          await limpar(s);
          try {
            await _semear(s);
            for (var i = 0; i < rodadas; i++) {
              final a = await _alerta(s);
              // Trilha única, gravada sob a trava: ordem = ordem da trava.
              final trilha = _AuditoriaGravada();
              OrmAlertStore novo() => OrmAlertStore(
                    session: sessionBuilder.build,
                    appendAudit: trilha.call,
                  );
              AuditEvent evento(String userId, String result) => AuditEvent(
                    userId: userId,
                    actionType: 'write',
                    resourceType: 'alert',
                    resourceId: a.id!.uuid,
                    result: result,
                  );

              final r = await Future.wait([
                novo().acknowledge(
                  alertId: a.id!.uuid,
                  acsId: _acs,
                  microAreaId: _maA,
                  auditFor: (o) => evento(_acs, 'ack:${o.name}'),
                ),
                novo().acknowledge(
                  alertId: a.id!.uuid,
                  acsId: _acsB,
                  microAreaId: _maA,
                  auditFor: (o) => evento(_acsB, 'ack:${o.name}'),
                ),
              ]);
              final desfechos = r.map((x) => x!.outcome).toList();
              expect(
                desfechos.where((o) => o == AlertAckOutcome.acknowledged),
                hasLength(1),
                reason: 'rodada $i: $desfechos',
              );
              expect(
                desfechos.where((o) => o == AlertAckOutcome.alreadyAcknowledged),
                hasLength(1),
                reason: 'rodada $i: $desfechos',
              );
              final vencedor = trilha.eventos.first.userId;
              expect(trilha.eventos.first.result, 'ack:acknowledged', reason: 'rodada $i');
              expect(trilha.eventos.last.result, 'ack:alreadyAcknowledged', reason: 'rodada $i');
              final lido = (await Alert.db.findById(s, a.id!))!;
              expect(lido.acsId!.uuid, vencedor, reason: 'rodada $i');
              expect(lido.status, AlertStatus.acknowledged, reason: 'rodada $i');
              // Os dois devolvem o carimbo do vencedor.
              expect(r[0]!.acknowledgedAt, r[1]!.acknowledgedAt, reason: 'rodada $i');
              expect(r.where((x) => x!.firstAcknowledgement), hasLength(1), reason: 'rodada $i');
              expect(
                await AlertDeliveryRecord.db.count(s, where: (t) => t.alertId.equals(a.id!)),
                2,
                reason: 'rodada $i',
              );
            }
          } finally {
            await limpar(s);
          }
        },
      );
    },
    rollbackDatabase: RollbackDatabase.disabled,
  );
}
