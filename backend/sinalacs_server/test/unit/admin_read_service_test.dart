import 'package:sinalacs_server/src/application/admin/admin_read_service.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:test/test.dart';

/// Regras do backoffice (#40) sem banco: papel, escopo, auditoria que vem ANTES
/// do dado e validação de paginação. Dados sintéticos.
const _ubsDoCoordenador = 'ubs-a';

/// Registra cada chamada com a ordem global, para provar "auditoria antes do dado".
final _ordem = <String>[];

class _Store implements AdminReadStore {
  AdminScope? ultimoEscopo;
  int chamadas = 0;
  int? ultimoLimit;
  final Map<String, String?> ubs = {
    'coord-a': _ubsDoCoordenador,
    'coord-sem-ubs': null,
  };

  void _marca(String nome, [AdminScope? escopo]) {
    chamadas++;
    ultimoEscopo = escopo;
    _ordem.add('store:$nome');
  }

  @override
  Future<AdminIndicators> indicators(
    AdminScope scope, {
    required DateTime now,
  }) async {
    _marca('indicators', scope);
    return AdminIndicators(
      red: 1,
      yellow: 0,
      green: 0,
      openRedAlerts: 1,
      acknowledgedRedAlerts: 0,
      tmravSeconds: null,
    );
  }

  @override
  Future<List<AdminMicroArea>> microAreas(AdminScope scope) async {
    _marca('microAreas', scope);
    return [];
  }

  @override
  Future<AdminAlertPage> alerts(
    AdminScope scope, {
    String? microAreaId,
    AlertStatus? status,
    required int limit,
    required int offset,
  }) async {
    _marca('alerts', scope);
    ultimoLimit = limit;
    return AdminAlertPage(items: []);
  }

  @override
  Future<AdminAuditPage> auditLogs(
    AdminScope scope, {
    required int limit,
    int? beforeSequence,
  }) async {
    _marca('auditLogs', scope);
    ultimoLimit = limit;
    return AdminAuditPage(items: []);
  }

  @override
  Future<String?> ubsOf(String staffId) async => ubs[staffId];
}

class _Audit extends AuditTrail {
  final events = <AuditEvent>[];
  bool falhar = false;

  @override
  Future<void> record(AuditEvent event) async {
    if (falhar) throw StateError('auditoria indisponível');
    _ordem.add('audit:${event.resourceType}:${event.result}');
    events.add(event);
  }
}

AuthenticatedUser _u(String id, UserRole role) => AuthenticatedUser(
  id: id,
  role: role,
  microAreaId: null,
  deviceId: 'sem-aparelho',
);

void main() {
  late _Store store;
  late _Audit audit;
  late AdminReadService servico;
  final admin = _u('admin-1', UserRole.admin);
  final coordA = _u('coord-a', UserRole.coordinator);
  final coordSemUbs = _u('coord-sem-ubs', UserRole.coordinator);

  setUp(() {
    _ordem.clear();
    store = _Store();
    audit = _Audit();
    servico = AdminReadService(
      store: store,
      audit: audit,
      clock: () => DateTime.utc(2026, 10, 7, 12),
    );
  });

  test(
    'admin lê com escopo de sistema e a leitura é auditada ANTES do dado',
    () async {
      await servico.indicators(admin);
      expect(store.ultimoEscopo!.ubsId, isNull);
      expect(_ordem, ['audit:admin_indicators:success', 'store:indicators']);
      expect(audit.events.single.actionType, 'read');
      expect(audit.events.single.userId, 'admin-1');
    },
  );

  test('coordenador lê só a sua UBS', () async {
    await servico.alerts(coordA);
    expect(store.ultimoEscopo!.ubsId, _ubsDoCoordenador);
  });

  test(
    'coordenador sem UBS é recusado em indicators, microAreas e alerts, com auditoria denied',
    () async {
      for (final chamada in <Future<Object?> Function()>[
        () => servico.indicators(coordSemUbs),
        () => servico.microAreas(coordSemUbs),
        () => servico.alerts(coordSemUbs),
      ]) {
        await expectLater(chamada(), throwsA(isA<AlertPermissionException>()));
      }
      expect(store.chamadas, 0, reason: 'nenhum dado sai');
      expect(audit.events.map((e) => e.result), everyElement('denied'));
      expect(audit.events, hasLength(3));
    },
  );

  test(
    'coordenador lê a auditoria escopada à sua UBS, auditada ANTES do dado',
    () async {
      await servico.auditLogs(coordA, limit: 10);
      expect(store.ultimoEscopo!.ubsId, _ubsDoCoordenador);
      expect(store.ultimoLimit, 10);
      expect(_ordem, ['audit:admin_audit_logs:success', 'store:auditLogs']);
      expect(audit.events.single.result, 'success');
    },
  );

  test('coordenador sem UBS é recusado na auditoria (fail-closed)', () async {
    await expectLater(
      servico.auditLogs(coordSemUbs),
      throwsA(isA<AlertPermissionException>()),
    );
    expect(store.chamadas, 0, reason: 'nenhum dado sai');
    expect(audit.events.single.result, 'denied');
  });

  test('admin lê a auditoria com escopo de sistema', () async {
    await servico.auditLogs(admin);
    expect(store.chamadas, 1);
    expect(store.ultimoEscopo!.ubsId, isNull);
    expect(audit.events.single.resourceType, 'admin_audit_logs');
  });

  test(
    'acs e patient são recusados em todos os métodos e a recusa é auditada',
    () async {
      for (final role in [UserRole.acs, UserRole.patient]) {
        final u = _u('u-${role.name}', role);
        for (final chamada in <Future<Object?> Function()>[
          () => servico.indicators(u),
          () => servico.microAreas(u),
          () => servico.alerts(u),
          () => servico.auditLogs(u),
        ]) {
          await expectLater(
            chamada(),
            throwsA(isA<AlertPermissionException>()),
          );
        }
      }
      expect(store.chamadas, 0);
      expect(audit.events, hasLength(8));
      expect(audit.events.map((e) => e.result), everyElement('denied'));
    },
  );

  test('se a auditoria falha, o store não é chamado (fail-closed)', () async {
    audit.falhar = true;
    await expectLater(servico.alerts(admin), throwsA(isA<StateError>()));
    expect(store.chamadas, 0);
  });

  test(
    'limit 0, 101 e -1 são recusados com a mensagem de paginação, sem tocar o store',
    () async {
      for (final limit in [0, 101, -1]) {
        await expectLater(
          servico.alerts(admin, limit: limit),
          throwsA(
            isA<AdminInvalidRequestException>().having(
              (e) => e.message,
              'message',
              'Parâmetro de paginação inválido.',
            ),
          ),
        );
      }
      await expectLater(
        servico.auditLogs(admin, limit: 0),
        throwsA(isA<AdminInvalidRequestException>()),
      );
      expect(store.chamadas, 0);
    },
  );

  test('offset negativo é recusado; limit 1 e 100 passam', () async {
    await expectLater(
      servico.alerts(admin, offset: -1),
      throwsA(isA<AdminInvalidRequestException>()),
    );
    await servico.alerts(admin, limit: 1);
    await servico.alerts(admin, limit: 100);
    expect(store.ultimoLimit, 100);
  });
}
