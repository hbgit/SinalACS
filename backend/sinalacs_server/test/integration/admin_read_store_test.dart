import 'dart:convert';

import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/admin/admin_read_service.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_admin_read_store.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_audit_trail.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

/// Leitura do backoffice (#40) contra Postgres real: escopo por UBS, TMRAV,
/// paginação e minimização de PII. Dados sintéticos; ids próprios.
///
/// UBS A: microárea A (1 ACS, 5 alertas recentes + 1 vermelho fora da janela de
/// 30 dias). UBS B: microárea B (1 vermelho pendente). Mais um alerta vermelho
/// SEM microárea, que só o escopo de sistema enxerga.
const _ubsA = '00000000-0000-4000-8000-0000000000e1';
const _ubsB = '00000000-0000-4000-8000-0000000000e2';
const _maA = '00000000-0000-4000-8000-0000000000e3';
const _maB = '00000000-0000-4000-8000-0000000000e4';
const _acsId = '00000000-0000-4000-8000-0000000000e5';
const _coordId = '00000000-0000-4000-8000-0000000000e6';
const _adminId = '00000000-0000-4000-8000-0000000000e7';
const _semUbsId = '00000000-0000-4000-8000-0000000000e8';
const _pacienteNome = 'Maria Sintética da Silva';
const _paciente = '00000000-0000-4000-8000-0000000000f1';

final _t = DateTime.utc(2026, 10, 7, 12);

Future<void> _usuario(
  Session s,
  String id,
  String nome,
  UserRole role, {
  String? ma,
}) => User.db
    .insertRow(
      s,
      User(
        id: UuidValue.fromString(id),
        cpfHash: 'admin-read-$id',
        name: nome,
        birthDate: DateTime.utc(1980),
        role: role,
        microAreaId: ma == null ? null : UuidValue.fromString(ma),
        createdAt: _t,
        updatedAt: _t,
      ),
    )
    .then((_) {});

Future<void> _alerta(
  Session s, {
  required RiskLevel risco,
  required AlertStatus status,
  required DateTime em,
  String? ma,
  Duration? reconhecidoApos,
}) => Alert.db
    .insertRow(
      s,
      Alert(
        patientId: UuidValue.fromString(_paciente),
        microAreaId: ma == null ? null : UuidValue.fromString(ma),
        triggeredAt: em,
        acknowledgedAt: reconhecidoApos == null
            ? null
            : em.add(reconhecidoApos),
        riskLevel: risco,
        locationHash: 'hash-sintetico',
        status: status,
        mqttTopic: 'sinalacs/v1/microareas/${ma ?? 'x'}/alerts',
        deviceId: 'device-sintetico',
        retryCount: 0,
        version: 0,
      ),
    )
    .then((_) {});

Future<void> _seed(Session s) async {
  for (final (id, nome) in [(_ubsA, 'UBS A'), (_ubsB, 'UBS B')]) {
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
  for (final (id, nome, ubs) in [
    (_maA, 'Microárea A', _ubsA),
    (_maB, 'Microárea B', _ubsB),
  ]) {
    await MicroArea.db.insertRow(
      s,
      MicroArea(
        id: UuidValue.fromString(id),
        name: nome,
        ubsId: UuidValue.fromString(ubs),
        geoJsonBoundary: '{}',
      ),
    );
  }
  await _usuario(s, _acsId, 'Carla ACS Sintética', UserRole.acs, ma: _maA);
  await Acs.db.insertRow(
    s,
    Acs(
      id: UuidValue.fromString(_acsId),
      enrollmentId: 'ACS-ADM-RD-1',
      ubsId: UuidValue.fromString(_ubsA),
      active: true,
    ),
  );
  await _usuario(s, _paciente, _pacienteNome, UserRole.patient, ma: _maA);
  await Patient.db.insertRow(
    s,
    Patient(
      id: UuidValue.fromString(_paciente),
      emergencyContact: 'x',
      isChronic: false,
    ),
  );

  await _usuario(s, _adminId, 'Admin Sintético', UserRole.admin);
  await StaffAccount.db.insertRow(
    s,
    StaffAccount(
      id: UuidValue.fromString(_adminId),
      enrollmentId: 'ADM-RD-1',
      active: true,
    ),
  );
  await _usuario(s, _coordId, 'Coord Sintético', UserRole.coordinator);
  await StaffAccount.db.insertRow(
    s,
    StaffAccount(
      id: UuidValue.fromString(_coordId),
      enrollmentId: 'COO-RD-1',
      active: true,
      ubsId: UuidValue.fromString(_ubsA),
    ),
  );
  await _usuario(s, _semUbsId, 'Coord Sem UBS', UserRole.coordinator);
  await StaffAccount.db.insertRow(
    s,
    StaffAccount(
      id: UuidValue.fromString(_semUbsId),
      enrollmentId: 'COO-RD-2',
      active: true,
    ),
  );

  const min = Duration(minutes: 1);
  await _alerta(
    s,
    risco: RiskLevel.red,
    status: AlertStatus.pending,
    em: _t.subtract(min * 10),
    ma: _maA,
  ); // a1
  await _alerta(
    s,
    risco: RiskLevel.red,
    status: AlertStatus.acknowledged,
    em: _t.subtract(min * 120),
    ma: _maA,
    reconhecidoApos: const Duration(seconds: 60),
  ); // a2
  await _alerta(
    s,
    risco: RiskLevel.red,
    status: AlertStatus.acknowledged,
    em: _t.subtract(min * 60),
    ma: _maA,
    reconhecidoApos: const Duration(seconds: 120),
  ); // a3
  await _alerta(
    s,
    risco: RiskLevel.yellow,
    status: AlertStatus.pending,
    em: _t.subtract(min * 30),
    ma: _maA,
  ); // a4
  await _alerta(
    s,
    risco: RiskLevel.green,
    status: AlertStatus.pending,
    em: _t.subtract(min * 40),
    ma: _maA,
  ); // a5
  await _alerta(
    s,
    risco: RiskLevel.red,
    status: AlertStatus.pending,
    em: _t.subtract(min * 5),
    ma: _maB,
  ); // b1
  await _alerta(
    s,
    risco: RiskLevel.red,
    status: AlertStatus.pending,
    em: _t.subtract(min * 180),
  ); // n1: sem microárea
  await _alerta(
    s,
    risco: RiskLevel.red,
    status: AlertStatus.acknowledged,
    em: _t.subtract(const Duration(days: 40)),
    ma: _maA,
    reconhecidoApos: const Duration(seconds: 1000),
  ); // o1: fora dos 30 dias
}

void main() {
  withServerpod('Dado a leitura do backoffice (#40)', (
    sessionBuilder,
    endpoints,
  ) {
    late Session session;
    late OrmAdminReadStore store;
    setUp(() async {
      session = sessionBuilder.build();
      await _seed(session);
      store = OrmAdminReadStore(session: () => session);
    });

    test(
      'indicadores do sistema contam por risco e calculam o TMRAV só na janela de 30 dias',
      () async {
        final r = await store.indicators(const AdminScope.system(), now: _t);
        expect(r.red, 6); // a1 a2 a3 b1 n1 o1
        expect(r.yellow, 1);
        expect(r.green, 1);
        expect(r.openRedAlerts, 3); // a1 b1 n1
        expect(r.acknowledgedRedAlerts, 3); // a2 a3 o1
        expect(
          r.tmravSeconds,
          90,
          reason: 'média de 60 s e 120 s; o1 (40 dias) fica de fora',
        );
      },
    );

    test(
      'indicadores da UBS A não enxergam a UBS B nem o alerta sem microárea',
      () async {
        final r = await store.indicators(const AdminScope.ubs(_ubsA), now: _t);
        expect(r.red, 4); // a1 a2 a3 o1
        expect(r.openRedAlerts, 1);
        expect(r.acknowledgedRedAlerts, 3);
      },
    );

    test(
      'UBS B enxerga só o seu alerta e TMRAV nulo sem vermelho reconhecido',
      () async {
        final r = await store.indicators(const AdminScope.ubs(_ubsB), now: _t);
        expect(r.red, 1);
        expect(r.openRedAlerts, 1);
        expect(r.tmravSeconds, isNull);
      },
    );

    test('microáreas trazem o ACS vinculado e respeitam a UBS', () async {
      final sistema = await store.microAreas(const AdminScope.system());
      expect(
        sistema.map((m) => m.name),
        containsAll(['Microárea A', 'Microárea B']),
      );
      final a = sistema.firstWhere((m) => m.name == 'Microárea A');
      expect(a.acsName, 'Carla ACS Sintética');
      expect(a.acsEnrollmentId, 'ACS-ADM-RD-1');
      expect(a.acsActive, isTrue);
      final b = sistema.firstWhere((m) => m.name == 'Microárea B');
      expect(b.acsName, 'Sem ACS vinculado');
      expect(b.acsActive, isFalse);

      final soA = await store.microAreas(const AdminScope.ubs(_ubsA));
      expect(soA.map((m) => m.name), ['Microárea A']);
    });

    test('microárea com DOIS ACS aparece UMA vez (o id é a chave do filtro do app)', () async {
      const segundoAcs = '00000000-0000-4000-8000-0000000000e9';
      await _usuario(session, segundoAcs, 'Bruno ACS Sintético', UserRole.acs, ma: _maA);
      await Acs.db.insertRow(
        session,
        Acs(
          id: UuidValue.fromString(segundoAcs),
          enrollmentId: 'ACS-ADM-RD-2',
          ubsId: UuidValue.fromString(_ubsA),
          active: false,
        ),
      );

      final lista = await store.microAreas(const AdminScope.system());

      expect(lista.map((m) => m.id).toSet(), hasLength(lista.length), reason: 'ids únicos');
      final a = lista.singleWhere((m) => m.name == 'Microárea A');
      expect(a.acsName, 'Carla ACS Sintética, Bruno ACS Sintético');
      expect(a.acsEnrollmentId, 'ACS-ADM-RD-1, ACS-ADM-RD-2');
      expect(a.acsActive, isTrue, reason: 'há ao menos um ACS ativo');
      expect(lista.singleWhere((m) => m.name == 'Microárea B').acsActive, isFalse);
    });

    test(
      'alertas: ordem triggeredAt desc, paginação por offset e nextOffset nulo no fim',
      () async {
        const sistema = AdminScope.system();
        final p1 = await store.alerts(sistema, limit: 3, offset: 0);
        expect(p1.items, hasLength(3));
        expect(p1.nextOffset, 3);
        expect(p1.items.map((a) => a.triggeredAt).toList(), [
          _t.subtract(const Duration(minutes: 5)),
          _t.subtract(const Duration(minutes: 10)),
          _t.subtract(const Duration(minutes: 30)),
        ]);
        final p3 = await store.alerts(sistema, limit: 3, offset: 6);
        expect(p3.items, hasLength(2));
        expect(p3.nextOffset, isNull);
        final alem = await store.alerts(sistema, limit: 3, offset: 30);
        expect(alem.items, isEmpty);
        expect(alem.nextOffset, isNull);
      },
    );

    test(
      'alertas trazem só rótulo do paciente, sem nome nem UUID inteiro',
      () async {
        final p = await store.alerts(
          const AdminScope.system(),
          limit: 20,
          offset: 0,
        );
        for (final a in p.items) {
          expect(a.patientLabel, matches(RegExp(r'^#[0-9A-F]{4}$')));
        }
        final json = jsonEncode(p.toJson());
        expect(json, isNot(contains(_pacienteNome)));
        expect(json, isNot(contains(_paciente)));
      },
    );

    test(
      'alerta sem microárea: conta no sistema, não aparece na UBS',
      () async {
        final sistema = await store.alerts(
          const AdminScope.system(),
          limit: 50,
          offset: 0,
        );
        expect(sistema.items, hasLength(8));
        expect(
          sistema.items.where((a) => a.microAreaName == 'Sem microárea'),
          hasLength(1),
        );
        final soA = await store.alerts(
          const AdminScope.ubs(_ubsA),
          limit: 50,
          offset: 0,
        );
        expect(soA.items, hasLength(6));
        expect(
          soA.items.any((a) => a.microAreaName == 'Sem microárea'),
          isFalse,
        );
      },
    );

    test('alertas filtram por microárea e por status', () async {
      final b = await store.alerts(
        const AdminScope.system(),
        microAreaId: _maB,
        limit: 50,
        offset: 0,
      );
      expect(b.items, hasLength(1));
      final reconhecidos = await store.alerts(
        const AdminScope.ubs(_ubsA),
        status: AlertStatus.acknowledged,
        limit: 50,
        offset: 0,
      );
      expect(reconhecidos.items, hasLength(3));
    });

    test(
      'filtro de microárea de OUTRA UBS devolve vazio para o coordenador',
      () async {
        final r = await store.alerts(
          const AdminScope.ubs(_ubsA),
          microAreaId: _maB,
          limit: 50,
          offset: 0,
        );
        expect(r.items, isEmpty);
      },
    );

    test(
      'auditoria: sequence desc, keyset, rótulo sem nome e sem hash nem IP',
      () async {
        final trilha = OrmAuditTrail(
          session: () => session,
          chainSecret: 'segredo-sintetico-de-teste',
        );
        for (final (quem, recurso) in [
          (_adminId, 'admin_indicators'),
          (_adminId, 'admin_alerts'),
          (_acsId, 'session'),
        ]) {
          await trilha.record(
            AuditEvent(
              userId: quem,
              actionType: 'read',
              resourceType: recurso,
              result: 'success',
            ),
          );
        }
        final p = await store.auditLogs(const AdminScope.system(), limit: 2);
        expect(p.items, hasLength(2));
        expect(p.nextBeforeSequence, p.items.last.sequence);
        expect(p.items.first.sequence, greaterThan(p.items.last.sequence));
        final proxima = await store.auditLogs(
          const AdminScope.system(),
          limit: 2,
          beforeSequence: p.nextBeforeSequence,
        );
        expect(proxima.items.first.sequence, lessThan(p.items.last.sequence));

        final todas = await store.auditLogs(
          const AdminScope.system(),
          limit: 50,
        );
        final rotulos = todas.items.map((e) => e.userLabel).toSet();
        expect(
          rotulos,
          containsAll(['ADM-RD-1 (Administrador)', 'ACS-ADM-RD-1 (ACS)']),
        );
        final json = jsonEncode(todas.toJson());
        expect(json, isNot(contains('Admin Sintético')));
        expect(json, isNot(contains('Hash')));
        expect(json, isNot(contains('ip')));
      },
    );

    test(
      'auditoria do coordenador: só atores com microárea da UBS dele; staff fica invisível',
      () async {
        final trilha = OrmAuditTrail(
          session: () => session,
          chainSecret: 'segredo-sintetico-de-teste',
        );
        // Dois staff (sem microárea: administrador e coordenador), o ACS da
        // microárea A e o paciente dela — os dois últimos são da UBS A.
        for (final (quem, recurso) in [
          (_adminId, 'admin_indicators'),
          (_coordId, 'admin_audit_logs'),
          (_acsId, 'session'),
          (_paciente, 'triage_session'),
        ]) {
          await trilha.record(
            AuditEvent(
              userId: quem,
              actionType: 'read',
              resourceType: recurso,
              result: 'success',
            ),
          );
        }

        final sistema = await store.auditLogs(
          const AdminScope.system(),
          limit: 50,
        );
        expect(sistema.items, hasLength(4), reason: 'o administrador vê tudo');

        final daUbsA = await store.auditLogs(
          const AdminScope.ubs(_ubsA),
          limit: 50,
        );
        expect(daUbsA.items, hasLength(2));
        expect(
          daUbsA.items.map((e) => e.userLabel).toSet(),
          {'ACS-ADM-RD-1 (ACS)', 'Paciente #00F1'},
          reason: 'só atores com microárea na UBS A',
        );
        expect(
          daUbsA.items.map((e) => e.resourceType).toSet(),
          {'session', 'triage_session'},
          reason:
              'as linhas de staff (admin_indicators, admin_audit_logs) ficam de fora',
        );

        expect(
          (await store.auditLogs(const AdminScope.ubs(_ubsB), limit: 50)).items,
          isEmpty,
          reason: 'nenhum ator com microárea na UBS B',
        );
      },
    );

    test(
      'auditoria escopada pagina por keyset dentro do escopo',
      () async {
        final trilha = OrmAuditTrail(
          session: () => session,
          chainSecret: 'segredo-sintetico-de-teste',
        );
        for (final (quem, recurso) in [
          (_adminId, 'admin_indicators'),
          (_acsId, 'session'),
          (_paciente, 'triage_session'),
        ]) {
          await trilha.record(
            AuditEvent(
              userId: quem,
              actionType: 'read',
              resourceType: recurso,
              result: 'success',
            ),
          );
        }

        final soA = const AdminScope.ubs(_ubsA);
        final p1 = await store.auditLogs(soA, limit: 1);
        expect(p1.items, hasLength(1));
        expect(p1.nextBeforeSequence, p1.items.last.sequence);

        final p2 = await store.auditLogs(
          soA,
          limit: 1,
          beforeSequence: p1.nextBeforeSequence,
        );
        expect(p2.items, hasLength(1));
        expect(p2.items.first.sequence, lessThan(p1.items.first.sequence));
        expect(
          p2.nextBeforeSequence,
          isNull,
          reason: 'a terceira linha (do staff) não pertence ao escopo',
        );
      },
    );

    test(
      'ubsOf devolve a UBS do coordenador e null para administrador e sem UBS',
      () async {
        expect(await store.ubsOf(_coordId), _ubsA);
        expect(await store.ubsOf(_adminId), isNull);
        expect(await store.ubsOf(_semUbsId), isNull);
        expect(
          await store.ubsOf('00000000-0000-4000-8000-0000000000ff'),
          isNull,
        );
      },
    );
  });
}
