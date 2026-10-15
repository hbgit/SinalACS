import 'dart:convert';

import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/admin/alert_escalation_service.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_admin_read_store.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_alert_escalation_store.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_audit_trail.dart';
import 'package:test/test.dart';

import '../support/health_data_fixtures.dart';
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
const _acsBId = '00000000-0000-4000-8000-0000000000e9';
const _pacienteNome = 'Maria Sintética da Silva';
const _paciente = '00000000-0000-4000-8000-0000000000f1';

final _t = DateTime.utc(2026, 10, 7, 12);

/// Aritmética de instante legível nas fixtures da auditoria com filtros.
extension on DateTime {
  DateTime operator +(Duration d) => add(d);
}

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
  DateTime? escalonadoEm,
}) => Alert.db
    .insertRow(
      s,
      Alert(
        patientId: UuidValue.fromString(_paciente),
        microAreaId: ma == null ? null : UuidValue.fromString(ma),
        triggeredAt: em,
        escalatedAt: escalonadoEm,
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
    await encryptedPatient(
      id: _paciente,
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

    test(
      'microárea com DOIS ACS aparece UMA vez (o id é a chave do filtro do app)',
      () async {
        const segundoAcs = '00000000-0000-4000-8000-0000000000e9';
        await _usuario(
          session,
          segundoAcs,
          'Bruno ACS Sintético',
          UserRole.acs,
          ma: _maA,
        );
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

        expect(
          lista.map((m) => m.id).toSet(),
          hasLength(lista.length),
          reason: 'ids únicos',
        );
        final a = lista.singleWhere((m) => m.name == 'Microárea A');
        expect(a.acsName, 'Carla ACS Sintética, Bruno ACS Sintético');
        expect(a.acsEnrollmentId, 'ACS-ADM-RD-1, ACS-ADM-RD-2');
        expect(a.acsActive, isTrue, reason: 'há ao menos um ACS ativo');
        expect(
          lista.singleWhere((m) => m.name == 'Microárea B').acsActive,
          isFalse,
        );
      },
    );

    test(
      'alertas: vencidos primeiro, depois triggeredAt desc, paginação por offset e nextOffset nulo no fim',
      () async {
        const sistema = AdminScope.system();
        final p1 = await store.alerts(sistema, limit: 3, offset: 0, now: _t);
        expect(p1.items, hasLength(3));
        expect(p1.nextOffset, 3);
        // a1 (10 min) e n1 (180 min) são vermelhos pendentes além dos 300 s:
        // vêm antes, entre si do mais recente ao mais antigo. b1 (5 min,
        // exatamente o prazo) não vence e abre os demais.
        expect(p1.items.map((a) => a.triggeredAt).toList(), [
          _t.subtract(const Duration(minutes: 10)),
          _t.subtract(const Duration(minutes: 180)),
          _t.subtract(const Duration(minutes: 5)),
        ]);
        expect(p1.items.map((a) => a.overdue).toList(), [true, true, false]);
        final p3 = await store.alerts(sistema, limit: 3, offset: 6, now: _t);
        expect(p3.items, hasLength(2));
        expect(p3.nextOffset, isNull);
        final alem = await store.alerts(sistema, limit: 3, offset: 30, now: _t);
        expect(alem.items, isEmpty);
        expect(alem.nextOffset, isNull);
      },
    );

    group('vencidos primeiro (#44): nenhum vencido fica além da 1ª página', () {
      /// UBS B, microárea B: b1 (exatamente 300 s, não vence) + 54 vermelhos
      /// recentes (1..54 s) + 1 vermelho pendente de 10 h atrás — o ÚNICO
      /// vencido, e o mais antigo de todos. 56 alertas no escopo.
      late DateTime vencidoEm;
      setUp(() async {
        for (var i = 1; i <= 54; i++) {
          await _alerta(
            session,
            risco: i.isEven ? RiskLevel.red : RiskLevel.yellow,
            status: AlertStatus.pending,
            em: _t.subtract(Duration(seconds: i)),
            ma: _maB,
          );
        }
        vencidoEm = _t.subtract(const Duration(hours: 10));
        await _alerta(
          session,
          risco: RiskLevel.red,
          status: AlertStatus.pending,
          em: vencidoEm,
          ma: _maB,
        );
      });

      test(
        'o vencido mais antigo vem na 1ª página (limit 50), à frente de todos',
        () async {
          final p1 = await store.alerts(
            const AdminScope.ubs(_ubsB),
            limit: 50,
            offset: 0,
            now: _t,
          );
          expect(p1.items, hasLength(50));
          expect(p1.items.first.triggeredAt, vencidoEm);
          expect(p1.items.first.overdue, isTrue);
          expect(p1.items.skip(1).any((a) => a.overdue), isFalse);
        },
      );

      test('a ordem dos não vencidos segue triggeredAt desc', () async {
        final p1 = await store.alerts(
          const AdminScope.ubs(_ubsB),
          limit: 50,
          offset: 0,
          now: _t,
        );
        final resto = p1.items.skip(1).map((a) => a.triggeredAt).toList();
        expect(resto, [
          for (var i = 1; i <= 49; i++) _t.subtract(Duration(seconds: i)),
        ]);
      });

      test(
        'paginação: nextOffset 50, 2ª página com 6 e nextOffset nulo, sem repetir nem perder linha',
        () async {
          const ubsB = AdminScope.ubs(_ubsB);
          final p1 = await store.alerts(ubsB, limit: 50, offset: 0, now: _t);
          expect(p1.nextOffset, 50);
          final p2 = await store.alerts(
            ubsB,
            limit: 50,
            offset: p1.nextOffset!,
            now: _t,
          );
          expect(p2.items, hasLength(6));
          expect(p2.nextOffset, isNull);
          final ids = [...p1.items, ...p2.items].map((a) => a.id).toList();
          expect(ids.toSet(), hasLength(56));
          // O último da lista é b1, o mais antigo dos não vencidos.
          expect(
            p2.items.last.triggeredAt,
            _t.subtract(const Duration(minutes: 5)),
          );
        },
      );

      test(
        'filtros e escopo seguem valendo: microárea, status e UBS',
        () async {
          final soB = await store.alerts(
            const AdminScope.system(),
            microAreaId: _maB,
            status: AlertStatus.pending,
            limit: 50,
            offset: 0,
            now: _t,
          );
          expect(soB.items.first.triggeredAt, vencidoEm);
          expect(
            soB.items.every((a) => a.microAreaName == 'Microárea B'),
            isTrue,
          );

          final reconhecidosB = await store.alerts(
            const AdminScope.system(),
            microAreaId: _maB,
            status: AlertStatus.acknowledged,
            limit: 50,
            offset: 0,
            now: _t,
          );
          expect(reconhecidosB.items, isEmpty);

          // O coordenador da UBS A não vê o vencido da UBS B; o dele (a1)
          // abre a lista dele.
          final soA = await store.alerts(
            const AdminScope.ubs(_ubsA),
            limit: 50,
            offset: 0,
            now: _t,
          );
          expect(soA.items, hasLength(6));
          expect(soA.items.any((a) => a.triggeredAt == vencidoEm), isFalse);
          expect(
            soA.items.first.triggeredAt,
            _t.subtract(const Duration(minutes: 10)),
          );
          expect(soA.items.first.overdue, isTrue);
        },
      );
    });

    test(
      'alertas trazem só rótulo do paciente, sem nome nem UUID inteiro',
      () async {
        final p = await store.alerts(
          const AdminScope.system(),
          limit: 20,
          offset: 0,
          now: _t,
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
          now: _t,
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
          now: _t,
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
        now: _t,
      );
      expect(b.items, hasLength(1));
      final reconhecidos = await store.alerts(
        const AdminScope.ubs(_ubsA),
        status: AlertStatus.acknowledged,
        limit: 50,
        offset: 0,
        now: _t,
      );
      expect(reconhecidos.items, hasLength(3));
      expect(reconhecidos.items.every((a) => !a.overdue), isTrue);
    });

    test(
      'filtro de microárea de OUTRA UBS devolve vazio para o coordenador',
      () async {
        final r = await store.alerts(
          const AdminScope.ubs(_ubsA),
          microAreaId: _maB,
          limit: 50,
          offset: 0,
          now: _t,
        );
        expect(r.items, isEmpty);
      },
    );

    group('escalonamento (#44): escalatedAt e overdue calculado no servidor', () {
      // Limite padrão: 300 s. `_t` é o "agora" do servidor.
      const limite = Duration(seconds: 300);

      /// Cria um alerta na microárea A (`em` relativo a `_t`) e devolve o item
      /// listado pelo store, localizado pelo instante exato do disparo.
      Future<AdminAlert> lido(DateTime em) async {
        final p = await store.alerts(
          const AdminScope.system(),
          limit: 100,
          offset: 0,
          now: _t,
        );
        return p.items.singleWhere(
          (a) => a.triggeredAt == em && a.microAreaName == 'Microárea A',
        );
      }

      // Pina o acordo entre a leitura (`overdue`, OrmAdminReadStore) e o
      // escalonamento (`vencido`, OrmAlertEscalationStore): o botão "Escalar"
      // depende de os dois SQLs dizerem o mesmo. Se uma das regras mudar, este
      // teste quebra. Referenciado nos dois pontos de SQL.
      test(
        'acordo: overdue da leitura == escalonar devolve escalated (mesmo now e limite)',
        () async {
          const us = Duration(microseconds: 1);
          Future<Alert> semear(
            RiskLevel risco,
            DateTime em, {
            DateTime? escalonadoEm,
          }) => Alert.db.insertRow(
            session,
            Alert(
              patientId: UuidValue.fromString(_paciente),
              microAreaId: UuidValue.fromString(_maA),
              triggeredAt: em,
              escalatedAt: escalonadoEm,
              riskLevel: risco,
              locationHash: 'hash-sintetico',
              status: AlertStatus.pending,
              mqttTopic: 'sinalacs/v1/microareas/$_maA/alerts',
              deviceId: 'device-sintetico',
              retryCount: 0,
              version: 0,
            ),
          );

          // Instantes distintos entre si e dos fixtures do _seed.
          final casos = <(String, Alert, bool, EscalationOutcome)>[
            (
              'exatamente o limite',
              await semear(RiskLevel.red, _t.subtract(limite)),
              false,
              EscalationOutcome.notDue,
            ),
            (
              'limite + 1 microssegundo',
              await semear(RiskLevel.red, _t.subtract(limite + us)),
              true,
              EscalationOutcome.escalated,
            ),
            (
              'limite - 1 microssegundo',
              await semear(RiskLevel.red, _t.subtract(limite - us)),
              false,
              EscalationOutcome.notDue,
            ),
            (
              'limite + 1 s',
              await semear(
                RiskLevel.red,
                _t.subtract(limite + const Duration(seconds: 1)),
              ),
              true,
              EscalationOutcome.escalated,
            ),
            (
              'limite - 1 s',
              await semear(
                RiskLevel.red,
                _t.subtract(limite - const Duration(seconds: 1)),
              ),
              false,
              EscalationOutcome.notDue,
            ),
            (
              'triggeredAt 2 h no futuro',
              await semear(RiskLevel.red, _t.add(const Duration(hours: 2))),
              false,
              EscalationOutcome.notDue,
            ),
            (
              'já escalonado',
              await semear(
                RiskLevel.red,
                _t.subtract(const Duration(hours: 5, minutes: 11)),
                escalonadoEm: _t.subtract(const Duration(minutes: 1)),
              ),
              false,
              EscalationOutcome.alreadyEscalated,
            ),
            (
              'amarelo',
              await semear(
                RiskLevel.yellow,
                _t.subtract(const Duration(hours: 5, minutes: 12)),
              ),
              false,
              EscalationOutcome.notRed,
            ),
          ];

          // O microssegundo precisa sobreviver à ida e volta pelo Postgres;
          // sem isso o caso "+1 µs" não exercitaria a unidade.
          final mais1us = casos[1].$2;
          expect(
            (await Alert.db.findById(session, mais1us.id!))!.triggeredAt,
            _t.subtract(limite + us),
          );

          // Leitura de TODOS antes de escalar qualquer um (escalar muta a linha).
          final lista = await store.alerts(
            const AdminScope.system(),
            limit: 100,
            offset: 0,
            now: _t,
          );
          final overdue = {
            for (final a in lista.items) a.id: a.overdue,
          };

          // Terceiro uso da mesma regra: o `overdueRed` do pulso (D5) conta
          // exatamente os `overdue` da leitura, no mesmo estado e limite.
          final pulso = await store.pulse(
            const AdminScope.system(),
            now: _t,
            threshold: limite,
          );
          expect(
            pulso.overdueRed,
            lista.items.where((a) => a.overdue).length,
            reason: 'overdueRed do pulso e overdue da leitura discordam',
          );

          final escalonador = OrmAlertEscalationStore(
            session: () => session,
            appendAudit: OrmAuditTrail(
              session: () => session,
              chainSecret: 'segredo-sintetico-de-teste',
            ).recordInTransaction,
          );
          for (final (nome, alerta, esperadoOverdue, esperadoDesfecho)
              in casos) {
            final id = alerta.id!.uuid;
            final r = await escalonador.escalate(
              const AdminScope.system(),
              alertId: id,
              actorId: _coordId,
              reason: EscalationReason.noAckTimeout,
              now: _t,
              threshold: limite,
              auditFor: (o) => AuditEvent(
                userId: _coordId,
                actionType: 'write',
                resourceType: 'admin_alert',
                resourceId: id,
                result: 'escalated:no_ack_timeout',
              ),
            );
            expect(r.outcome, esperadoDesfecho, reason: nome);
            expect(overdue[id], esperadoOverdue, reason: 'leitura: $nome');
            expect(
              overdue[id],
              r.outcome == EscalationOutcome.escalated,
              reason: 'leitura e escalonamento discordam: $nome',
            );
          }
        },
      );

      test(
        'vermelho pendente acima do limite: overdue=true, escalatedAt nulo',
        () async {
          final em = _t.subtract(limite + const Duration(seconds: 1));
          await _alerta(
            session,
            risco: RiskLevel.red,
            status: AlertStatus.pending,
            em: em,
            ma: _maA,
          );
          final a = await lido(em);
          expect(a.overdue, isTrue);
          expect(a.escalatedAt, isNull);
        },
      );

      test('vermelho pendente dentro do prazo: overdue=false', () async {
        final em = _t.subtract(limite - const Duration(seconds: 1));
        await _alerta(
          session,
          risco: RiskLevel.red,
          status: AlertStatus.pending,
          em: em,
          ma: _maA,
        );
        expect((await lido(em)).overdue, isFalse);
      });

      test(
        'exatamente no limite: overdue=false (estrito, como o escalonamento)',
        () async {
          final em = _t.subtract(limite);
          await _alerta(
            session,
            risco: RiskLevel.red,
            status: AlertStatus.pending,
            em: em,
            ma: _maA,
          );
          expect((await lido(em)).overdue, isFalse);
        },
      );

      test('triggeredAt no futuro nunca vence', () async {
        final em = _t.add(const Duration(hours: 1));
        await _alerta(
          session,
          risco: RiskLevel.red,
          status: AlertStatus.pending,
          em: em,
          ma: _maA,
        );
        expect((await lido(em)).overdue, isFalse);
      });

      test('reconhecido e amarelo antigos não são overdue', () async {
        final emAck = _t.subtract(const Duration(hours: 5, minutes: 3));
        final emAmarelo = _t.subtract(const Duration(hours: 5, minutes: 4));
        await _alerta(
          session,
          risco: RiskLevel.red,
          status: AlertStatus.acknowledged,
          em: emAck,
          ma: _maA,
          reconhecidoApos: const Duration(seconds: 10),
        );
        await _alerta(
          session,
          risco: RiskLevel.yellow,
          status: AlertStatus.pending,
          em: emAmarelo,
          ma: _maA,
        );
        expect((await lido(emAck)).overdue, isFalse);
        expect((await lido(emAmarelo)).overdue, isFalse);
      });

      test(
        'D3: escalonado continua pending, listado, no filtro pending e em openRedAlerts; overdue=false',
        () async {
          final antes = await store.indicators(
            const AdminScope.system(),
            now: _t,
          );
          final em = _t.subtract(const Duration(hours: 5, minutes: 7));
          final escalonado = _t.subtract(const Duration(minutes: 1));
          await _alerta(
            session,
            risco: RiskLevel.red,
            status: AlertStatus.pending,
            em: em,
            ma: _maA,
            escalonadoEm: escalonado,
          );

          final a = await lido(em);
          expect(a.escalatedAt, escalonado);
          expect(a.overdue, isFalse);
          expect(a.status, AlertStatus.pending);

          final pendentes = await store.alerts(
            const AdminScope.system(),
            status: AlertStatus.pending,
            limit: 100,
            offset: 0,
            now: _t,
          );
          expect(pendentes.items.any((x) => x.triggeredAt == em), isTrue);

          final depois = await store.indicators(
            const AdminScope.system(),
            now: _t,
          );
          expect(
            depois.openRedAlerts,
            antes.openRedAlerts + 1,
            reason: 'escalar nunca esconde o alerta (D3)',
          );
        },
      );

      test('o limite é injetável: com 60 s, 2 min já vence', () async {
        final menor = OrmAdminReadStore(
          session: () => session,
          escalationThreshold: const Duration(seconds: 60),
        );
        final em = _t.subtract(const Duration(minutes: 2));
        await _alerta(
          session,
          risco: RiskLevel.red,
          status: AlertStatus.pending,
          em: em,
          ma: _maA,
        );
        final p = await menor.alerts(
          const AdminScope.system(),
          limit: 100,
          offset: 0,
          now: _t,
        );
        expect(p.items.singleWhere((a) => a.triggeredAt == em).overdue, isTrue);
        expect((await lido(em)).overdue, isFalse);
      });

      test('coordenador de OUTRA UBS não enxerga o alerta vencido', () async {
        final em = _t.subtract(const Duration(hours: 5, minutes: 9));
        await _alerta(
          session,
          risco: RiskLevel.red,
          status: AlertStatus.pending,
          em: em,
          ma: _maA,
        );
        final p = await store.alerts(
          const AdminScope.ubs(_ubsB),
          limit: 100,
          offset: 0,
          now: _t,
        );
        expect(p.items.any((a) => a.triggeredAt == em), isFalse);
      });
    });

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
        expect(p.nextBeforeSequence, p.items.last.entry.sequence);
        expect(p.items.first.entry.sequence, greaterThan(p.items.last.entry.sequence));
        final proxima = await store.auditLogs(
          const AdminScope.system(),
          limit: 2,
          beforeSequence: p.nextBeforeSequence,
        );
        expect(proxima.items.first.entry.sequence, lessThan(p.items.last.entry.sequence));

        final todas = await store.auditLogs(
          const AdminScope.system(),
          limit: 50,
        );
        final rotulos = todas.items.map((e) => e.entry.userLabel).toSet();
        expect(
          rotulos,
          containsAll(['ADM-RD-1 (Administrador)', 'ACS-ADM-RD-1 (ACS)']),
        );
        // O que a tela recebe é o `entry`; o selo interno não serializa.
        final json = jsonEncode([for (final r in todas.items) r.entry.toJson()]);
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
          daUbsA.items.map((e) => e.entry.userLabel).toSet(),
          {'ACS-ADM-RD-1 (ACS)', 'Paciente #00F1'},
          reason: 'só atores com microárea na UBS A',
        );
        expect(
          daUbsA.items.map((e) => e.entry.resourceType).toSet(),
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
        expect(p1.nextBeforeSequence, p1.items.last.entry.sequence);

        final p2 = await store.auditLogs(
          soA,
          limit: 1,
          beforeSequence: p1.nextBeforeSequence,
        );
        expect(p2.items, hasLength(1));
        expect(p2.items.first.entry.sequence, lessThan(p1.items.first.entry.sequence));
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

    group('auditoria com filtros (#45, D1/D2/D10)', () {
      // 12 linhas de 3 autores (admin, ACS da UBS A, ACS da UBS B), gravadas
      // direto no ORM para controlar `timestamp` e hashes. A leitura não
      // verifica a cadeia; só o filtro e o keyset estão em teste aqui.
      // Linhas 5 e 6 têm o MESMO timestamp; a 8 tem sequence maior e
      // timestamp menor que a 7. A 12 tem ipHash/entryHash com "cafe".
      final t0 = DateTime.utc(2026, 10, 1);
      const h = Duration(hours: 1);
      late int base;

      Future<void> linha(
        int n,
        String quem,
        String acao,
        String recurso,
        String resultado,
        DateTime em, {
        String hash = '',
      }) => AuditLog.db
          .insertRow(
            session,
            AuditLog(
              userId: UuidValue.fromString(quem),
              actionType: acao,
              resourceType: recurso,
              timestamp: em,
              ipHash: hash.isEmpty ? '0' * 64 : hash,
              result: resultado,
              sequence: base + n - 1,
              previousHash: '0' * 64,
              entryHash: hash.isEmpty ? '1' * 64 : hash,
            ),
          )
          .then((_) {});

      setUp(() async {
        await _usuario(
          session,
          _acsBId,
          'Bruno ACS Sintético',
          UserRole.acs,
          ma: _maB,
        );
        await Acs.db.insertRow(
          session,
          Acs(
            id: UuidValue.fromString(_acsBId),
            enrollmentId: 'ACS-ADM-RD-2',
            ubsId: UuidValue.fromString(_ubsB),
            active: true,
          ),
        );
        final max = await session.db.unsafeQuery(
          'SELECT COALESCE(max(sequence), 0) FROM audit_logs',
        );
        base = (max.single[0] as int) + 1;
        await linha(1, _adminId, 'read', 'admin_indicators', 'success', t0 + h);
        await linha(
          2,
          _adminId,
          'read',
          'admin_audit_logs',
          'success',
          t0 + h * 2,
        );
        await linha(3, _acsId, 'login', 'session', 'granted', t0 + h * 3);
        await linha(
          4,
          _acsId,
          'read',
          'patient_directory',
          'granted',
          t0 + h * 4,
        );
        await linha(
          5,
          _acsId,
          'write',
          'visit',
          'denied_territory',
          t0 + h * 5,
        );
        await linha(6, _acsBId, 'login', 'session', 'granted', t0 + h * 5);
        await linha(
          7,
          _acsBId,
          'read',
          'patient_directory',
          'granted',
          t0 + h * 6,
        );
        await linha(
          8,
          _acsBId,
          'write',
          'visit',
          'success',
          t0 + h * 2 + h ~/ 2,
        );
        await linha(9, _adminId, 'write', 'admin_acs', 'created', t0 + h * 7);
        await linha(10, _acsId, 'read', 'alert', 'denied', t0 + h * 8);
        await linha(11, _acsBId, 'write', 'alert', 'acknowledged', t0 + h * 9);
        await linha(
          12,
          _adminId,
          'login',
          'staff_session',
          'granted',
          t0 + h * 10,
          hash: 'cafe' * 16,
        );
      });

      /// Números (1..12) das linhas devolvidas, na ordem da página.
      Future<List<int>> nums(
        AdminAuditFilter? f, {
        AdminScope scope = const AdminScope.system(),
        int limit = 50,
      }) async => [
        for (final e in (await store.auditLogs(
          scope,
          filter: f,
          limit: limit,
        )).items)
          e.entry.sequence - base + 1,
      ];

      test('sem filtro: as 12, sequence desc', () async {
        expect(await nums(null), [12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1]);
        expect(await nums(AdminAuditFilter()), hasLength(12));
      });

      test('cada filtro isolado', () async {
        expect(await nums(AdminAuditFilter(actionType: 'login')), [12, 6, 3]);
        expect(
          await nums(AdminAuditFilter(resourceType: 'session')),
          [6, 3],
          reason: 'igualdade: staff_session não entra',
        );
        expect(
          await nums(AdminAuditFilter(result: 'granted')),
          [12, 7, 6, 4, 3],
        );
        expect(
          await nums(AdminAuditFilter(from: t0 + h * 5)),
          [12, 11, 10, 9, 7, 6, 5],
          reason: 'from inclusivo: 5 e 6 (mesmo timestamp) entram',
        );
        expect(
          await nums(AdminAuditFilter(to: t0 + h * 5)),
          [8, 4, 3, 2, 1],
          reason: 'to exclusivo: 5 e 6 ficam de fora; 8 (tempo menor) entra',
        );
        expect(
          await nums(AdminAuditFilter(actorRole: UserRole.admin)),
          [12, 9, 2, 1],
        );
        expect(
          await nums(AdminAuditFilter(actorRole: UserRole.acs)),
          [11, 10, 8, 7, 6, 5, 4, 3],
        );
        expect(
          await nums(AdminAuditFilter(actorEnrollmentId: 'acs-adm-rd-2')),
          [11, 8, 7, 6],
          reason: 'matrícula por igualdade, sem caixa',
        );
        expect(
          await nums(AdminAuditFilter(actorEnrollmentId: 'ACS-ADM-RD')),
          isEmpty,
          reason: 'matrícula é igualdade, não prefixo',
        );
      });

      test('fronteira de to: um microssegundo depois inclui 5 e 6', () async {
        expect(
          await nums(
            AdminAuditFilter(
              from: t0 + h * 5,
              to: t0 + h * 5 + const Duration(microseconds: 1),
            ),
          ),
          [6, 5],
        );
      });

      test('busca: prefixo da matrícula, resourceType e result', () async {
        expect(
          await nums(AdminAuditFilter(search: 'acs-adm-rd-2')),
          [11, 8, 7, 6],
        );
        expect(
          await nums(AdminAuditFilter(search: 'ADM-RD')),
          [12, 9, 2, 1],
          reason: 'prefixo da matrícula do admin, sem caixa',
        );
        expect(
          await nums(AdminAuditFilter(search: 'RD-1')),
          isEmpty,
          reason: 'na matrícula é só prefixo, não substring',
        );
        expect(await nums(AdminAuditFilter(search: 'directory')), [7, 4]);
        expect(await nums(AdminAuditFilter(search: 'territ')), [5]);
      });

      test('busca: curingas do usuário são literais', () async {
        expect(await nums(AdminAuditFilter(search: '%')), isEmpty);
        expect(await nums(AdminAuditFilter(search: '%%')), isEmpty);
        expect(
          await nums(AdminAuditFilter(search: 'a_')),
          isEmpty,
          reason: '"_" sem escape casaria "al" de alert e "ad" de admin',
        );
        expect(await nums(AdminAuditFilter(search: r'\')), isEmpty);
        expect(
          await nums(AdminAuditFilter(search: 'n_a')),
          [9, 2],
          reason: '"_" literal ainda casa admin_acs e admin_audit_logs',
        );
      });

      test(
        'result com ":" (escalated:no_ack_timeout) filtra por igualdade',
        () async {
          await linha(
            13,
            _adminId,
            'write',
            'admin_alert',
            'escalated:no_ack_timeout',
            t0 + h * 11,
          );
          expect(
            await nums(AdminAuditFilter(result: 'escalated:no_ack_timeout')),
            [13],
          );
          expect(
            await nums(AdminAuditFilter(result: 'escalated')),
            isEmpty,
            reason: 'igualdade, não prefixo',
          );
        },
      );

      test('busca nunca casa ipHash nem entryHash', () async {
        expect(await nums(AdminAuditFilter(search: 'cafe')), isEmpty);
      });

      test('todos os filtros combinados (AND)', () async {
        final f = AdminAuditFilter(
          actorRole: UserRole.acs,
          actionType: 'write',
          resourceType: 'visit',
          from: t0 + h * 2,
          to: t0 + h * 6,
          search: 'vis',
        );
        expect(await nums(f), [8, 5]);
        expect(
          await nums(f.copyWith(actorEnrollmentId: 'ACS-ADM-RD-1')),
          [5],
        );
        expect(await nums(f.copyWith(result: 'success')), [8]);
      });

      test(
        'coordenador: o filtro nunca fura o escopo da UBS',
        () async {
          const soA = AdminScope.ubs(_ubsA);
          expect(await nums(null, scope: soA), [10, 5, 4, 3]);
          expect(
            await nums(
              AdminAuditFilter(actorEnrollmentId: 'ACS-ADM-RD-2'),
              scope: soA,
            ),
            isEmpty,
            reason: 'matrícula de outra UBS não traz linha',
          );
          expect(
            await nums(AdminAuditFilter(search: 'acs-adm-rd-2'), scope: soA),
            isEmpty,
          );
          expect(
            await nums(AdminAuditFilter(actorRole: UserRole.admin), scope: soA),
            isEmpty,
            reason: 'linhas de staff seguem invisíveis',
          );
          expect(
            await nums(AdminAuditFilter(resourceType: 'session'), scope: soA),
            [3],
          );
        },
      );

      test(
        'keyset com filtro: linha nova no topo não repete nem pula',
        () async {
          final f = AdminAuditFilter(actorRole: UserRole.acs);
          final p1 = await store.auditLogs(
            const AdminScope.system(),
            filter: f,
            limit: 3,
          );
          expect(p1.items.map((e) => e.entry.sequence - base + 1), [11, 10, 8]);
          expect(p1.nextBeforeSequence, base + 8 - 1);

          await linha(13, _acsBId, 'read', 'alert', 'granted', t0 + h * 11);

          final vistos = [...p1.items.map((e) => e.entry.sequence - base + 1)];
          int? antes = p1.nextBeforeSequence;
          while (antes != null) {
            final p = await store.auditLogs(
              const AdminScope.system(),
              filter: f,
              limit: 3,
              beforeSequence: antes,
            );
            vistos.addAll(p.items.map((e) => e.entry.sequence - base + 1));
            antes = p.nextBeforeSequence;
          }
          expect(vistos, [11, 10, 8, 7, 6, 5, 4, 3]);
        },
      );
    });
  });
}
