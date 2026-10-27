import 'package:sinalacs_server/src/application/admin/admin_monitoring_service.dart';
import 'package:sinalacs_server/src/application/admin/admin_read_service.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:test/test.dart';

/// Pulso da monitoração do backoffice e sessão de monitoramento (#44, D5) sem
/// banco: relógio e store falsos. O pulso não grava `read`; a sessão abre com
/// START fail-closed e fecha com END best-effort. Dados sintéticos.
const _ubsA = 'ubs-a';
const _limite = Duration(seconds: 300);

final _ordem = <String>[];

class _Store implements AdminReadStore {
  final Map<String, String?> ubs = {'coord-a': _ubsA, 'coord-sem-ubs': null};
  AdminScope? ultimoEscopo;
  DateTime? ultimoAgora;
  Duration? ultimoLimite;
  int chamadas = 0;
  final maxChangedAt = DateTime.utc(2026, 10, 11, 11, 59);

  @override
  Future<String?> ubsOf(String staffId) async => ubs[staffId];

  @override
  Future<AdminIndicators> indicators(
    AdminScope scope, {
    required DateTime now,
  }) async {
    chamadas++;
    ultimoEscopo = scope;
    _ordem.add('store:indicators');
    return AdminIndicators(
      red: 3,
      yellow: 1,
      green: 2,
      openRedAlerts: 2,
      acknowledgedRedAlerts: 1,
      resolvedRedAlerts: 0,
      tmravSeconds: 42,
    );
  }

  @override
  Future<AlertsPulseCounts> pulse(
    AdminScope scope, {
    required DateTime now,
    required Duration threshold,
  }) async {
    chamadas++;
    ultimoEscopo = scope;
    ultimoAgora = now;
    ultimoLimite = threshold;
    _ordem.add('store:pulse');
    return (overdueRed: 1, maxChangedAt: maxChangedAt);
  }

  @override
  Future<List<AdminMicroArea>> microAreas(AdminScope scope) =>
      throw UnimplementedError();

  @override
  Future<AdminAlertPage> alerts(
    AdminScope scope, {
    String? microAreaId,
    AlertStatus? status,
    required int limit,
    required int offset,
    required DateTime now,
  }) => throw UnimplementedError();

  @override
  Future<AdminAuditRowPage> auditLogs(
    AdminScope scope, {
    AdminAuditFilter? filter,
    required int limit,
    int? beforeSequence,
  }) => throw UnimplementedError();
}

class _Audit extends AuditTrail {
  final events = <AuditEvent>[];
  bool falhar = false;

  @override
  Future<void> record(AuditEvent event) async {
    if (falhar) throw StateError('auditoria indisponível');
    _ordem.add('audit:${event.actionType}:${event.result}');
    events.add(event);
  }

  Iterable<String> get acoes => events.map((e) => e.actionType);
}

AuthenticatedUser _u(String id, UserRole role, {String? ma}) =>
    AuthenticatedUser(
      id: id,
      role: role,
      microAreaId: ma,
      deviceId: 'sem-aparelho',
    );

void main() {
  late _Store store;
  late _Audit audit;
  late Map<String, DateTime> sessoes;
  late DateTime agora;
  late AdminMonitoringService servico;
  final admin = _u('admin-1', UserRole.admin);
  final coordA = _u('coord-a', UserRole.coordinator);
  final coordSemUbs = _u('coord-sem-ubs', UserRole.coordinator);
  final acs = _u('acs-1', UserRole.acs, ma: 'ma-1');
  final paciente = _u('pac-1', UserRole.patient, ma: 'ma-1');
  final t0 = DateTime.utc(2026, 10, 11, 12);

  setUp(() {
    _ordem.clear();
    store = _Store();
    audit = _Audit();
    sessoes = {};
    agora = t0;
    servico = AdminMonitoringService(
      store: store,
      audit: audit,
      sessions: sessoes,
      threshold: _limite,
      clock: () => agora,
    );
  });

  group('pulso', () {
    test(
      'embute os indicadores, overdueRed, maxChangedAt e o relógio do servidor',
      () async {
        final p = await servico.alertsPulse(coordA);
        expect(p.indicators.red, 3);
        expect(p.indicators.tmravSeconds, 42);
        expect(p.overdueRed, 1);
        expect(p.maxChangedAt, store.maxChangedAt);
        expect(p.serverNow, t0);
        expect(p.serverNow.isUtc, isTrue);
        expect(store.ultimoEscopo!.ubsId, _ubsA);
        expect(store.ultimoAgora, t0);
        expect(store.ultimoLimite, _limite);
      },
    );

    test('administrador pulsa com escopo de sistema', () async {
      await servico.alertsPulse(admin);
      expect(store.ultimoEscopo!.ubsId, isNull);
    });

    test(
      'NÃO grava linha read: só o START, e ele vem antes de qualquer dado',
      () async {
        await servico.alertsPulse(coordA);
        expect(audit.acoes, ['monitoring_session_start']);
        final start = audit.events.single;
        expect(start.resourceType, 'admin_monitoring');
        expect(start.result, 'success');
        expect(start.resourceId, isNull);
        expect(start.userId, 'coord-a');
        expect(_ordem.first, 'audit:monitoring_session_start:success');
        expect(_ordem, isNot(contains(startsWith('audit:read'))));
      },
    );

    test(
      'dois pulsos dentro de 90 s: um START; o terceiro, 91 s depois do segundo, abre outro',
      () async {
        await servico.alertsPulse(coordA);
        agora = t0.add(const Duration(seconds: 30));
        await servico.alertsPulse(coordA);
        expect(audit.acoes, ['monitoring_session_start']);
        expect(sessoes['coord-a'], agora);

        agora = agora.add(const Duration(seconds: 91));
        await servico.alertsPulse(coordA);
        expect(audit.acoes, [
          'monitoring_session_start',
          'monitoring_session_start',
        ]);
      },
    );

    test(
      'exatamente 90 s ainda é sessão viva; 90 s + 1 µs abre outra',
      () async {
        await servico.alertsPulse(coordA);
        agora = t0.add(AdminMonitoringService.sessionIdle);
        await servico.alertsPulse(coordA);
        expect(audit.events, hasLength(1), reason: 'exatamente 90 s');

        agora = agora.add(
          AdminMonitoringService.sessionIdle + const Duration(microseconds: 1),
        );
        await servico.alertsPulse(coordA);
        expect(audit.events, hasLength(2), reason: '90 s + 1 µs');
      },
    );

    test('a sessão é por usuário', () async {
      await servico.alertsPulse(coordA);
      await servico.alertsPulse(admin);
      expect(audit.events.map((e) => e.userId), ['coord-a', 'admin-1']);
    });

    test(
      'START que falha: a exceção sobe, nenhum dado sai, o mapa fica como estava e o próximo pulso tenta o START de novo',
      () async {
        audit.falhar = true;
        await expectLater(servico.alertsPulse(coordA), throwsStateError);
        expect(store.chamadas, 0);
        expect(sessoes, isEmpty);

        audit.falhar = false;
        agora = t0.add(const Duration(seconds: 5));
        await servico.alertsPulse(coordA);
        expect(audit.acoes, ['monitoring_session_start']);
        expect(sessoes['coord-a'], agora);
      },
    );

    test(
      'START que falha numa sessão expirada não renova o instante antigo',
      () async {
        await servico.alertsPulse(coordA);
        agora = t0.add(const Duration(seconds: 200));
        audit.falhar = true;
        await expectLater(servico.alertsPulse(coordA), throwsStateError);
        expect(sessoes['coord-a'], t0);
      },
    );

    test(
      'ACS e paciente recusados com linha denied/read em admin_pulse, sem START nem dado',
      () async {
        for (final u in [acs, paciente, coordSemUbs]) {
          await expectLater(
            servico.alertsPulse(u),
            throwsA(
              isA<AlertPermissionException>().having(
                (e) => e.message,
                'message',
                'acesso restrito ao backoffice',
              ),
            ),
          );
        }
        expect(audit.events.map((e) => e.result), [
          'denied',
          'denied',
          'denied',
        ]);
        expect(audit.acoes, ['read', 'read', 'read']);
        expect(audit.events.map((e) => e.resourceType).toSet(), {
          'admin_pulse',
        });
        expect(store.chamadas, 0);
        expect(sessoes, isEmpty);
      },
    );
  });

  group('fim da sessão', () {
    test(
      'com sessão: grava END e remove a entrada; repetir não grava',
      () async {
        await servico.alertsPulse(coordA);
        await servico.endMonitoringSession(coordA);
        await servico.endMonitoringSession(coordA);
        expect(audit.acoes, [
          'monitoring_session_start',
          'monitoring_session_end',
        ]);
        final end = audit.events.last;
        expect(end.resourceType, 'admin_monitoring');
        expect(end.result, 'success');
        expect(end.resourceId, isNull);
        expect(sessoes, isEmpty);
      },
    );

    test('sem sessão: não grava nada', () async {
      await servico.endMonitoringSession(coordA);
      expect(audit.events, isEmpty);
    });

    test(
      'END com falha de auditoria não lança, e a entrada some (o próximo pulso abre outra sessão)',
      () async {
        await servico.alertsPulse(coordA);
        audit.falhar = true;
        await servico.endMonitoringSession(coordA);
        expect(sessoes, isEmpty);

        audit.falhar = false;
        agora = t0.add(const Duration(seconds: 10));
        await servico.alertsPulse(coordA);
        expect(audit.acoes, [
          'monitoring_session_start',
          'monitoring_session_start',
        ]);
      },
    );

    test(
      'ACS, paciente e coordenador sem UBS recusados, com linha denied, sem tocar a sessão de ninguém',
      () async {
        await servico.alertsPulse(coordA);
        for (final u in [acs, paciente, coordSemUbs]) {
          await expectLater(
            servico.endMonitoringSession(u),
            throwsA(isA<AlertPermissionException>()),
          );
        }
        expect(audit.events.skip(1).map((e) => e.result), [
          'denied',
          'denied',
          'denied',
        ]);
        expect(audit.events.skip(1).map((e) => e.resourceType).toSet(), {
          'admin_monitoring',
        });
        expect(audit.events.skip(1).map((e) => e.actionType).toSet(), {
          'monitoring_session_end',
        });
        expect(sessoes.keys, ['coord-a']);
      },
    );

    test(
      'recusa auditada que falha ao gravar propaga a falha (fail-closed)',
      () async {
        audit.falhar = true;
        await expectLater(servico.endMonitoringSession(acs), throwsStateError);
      },
    );
  });
}
