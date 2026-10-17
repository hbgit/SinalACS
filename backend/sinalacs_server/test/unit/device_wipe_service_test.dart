import 'package:serverpod/serverpod.dart' show UuidValue;
import 'package:sinalacs_server/src/application/admin/admin_account_service.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/institutional_auth_service.dart';
import 'package:sinalacs_server/src/application/devices/device_wipe_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:test/test.dart';

/// Pedido de limpeza remota e listagem de aparelhos do ACS (#81) sem banco:
/// papel, escopo por UBS, recusa única e auditoria. Dados sintéticos.
final _ordem = <String>[];

/// Só a parte do store de contas que o serviço usa (`acsById`, `ubsOf`).
class _Contas implements AdminAccountStore {
  final acs = <String, AdminAcs>{
    'acs-a': AdminAcs(
      id: 'acs-a',
      name: 'Ana ACS',
      enrollmentId: 'ACS-1',
      ubsId: 'ubs-a',
      ubsName: 'UBS A',
      microAreaId: 'ma-a',
      microAreaName: 'Microárea A',
      active: true,
      mfaActive: false,
    ),
    'acs-b': AdminAcs(
      id: 'acs-b',
      name: 'Bia ACS',
      enrollmentId: 'ACS-2',
      ubsId: 'ubs-b',
      ubsName: 'UBS B',
      microAreaId: 'ma-b',
      microAreaName: 'Microárea B',
      active: true,
      mfaActive: false,
    ),
  };

  @override
  Future<AdminAcs?> acsById(AdminScope scope, String acsId) async {
    _ordem.add('contas:acsById');
    final a = acs[acsId];
    if (a == null) return null;
    if (scope.ubsId != null && a.ubsId != scope.ubsId) return null;
    return a;
  }

  @override
  Future<String?> ubsOf(String staffId) async =>
      staffId == 'coord-a' ? 'ubs-a' : null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} não é usado aqui');
}

class _Aparelhos implements DeviceWipeStore {
  /// Aparelhos de cada ACS (com token), por id.
  final donos = <String, Set<String>>{
    'acs-a': {'aaaaaaaa-1111', InstitutionalAuthService.deviceIdAbsent},
    'acs-b': {'bbbbbbbb-2222'},
  };
  DeviceWipeOrder? lastOrder;
  int orderWipeCalls = 0;

  @override
  Future<List<AdminAcsDevice>> devicesOf(String acsId) async {
    _ordem.add('store:devicesOf');
    return [
      for (final d in donos[acsId] ?? <String>{})
        AdminAcsDevice(
          deviceId: d,
          label: 'Aparelho ${d.substring(0, 8)}',
          lastSeenAt: DateTime.utc(2026, 10, 1),
        ),
    ];
  }

  @override
  Future<bool> deviceBelongsTo(String acsId, String deviceId) async =>
      (donos[acsId] ?? {}).contains(deviceId);

  @override
  Future<({DeviceWipeOrder order, bool created})> orderWipe({
    required String deviceId,
    required String targetUserId,
    required String requestedBy,
    required DeviceWipeReason reason,
    required DateTime at,
  }) async {
    orderWipeCalls++;
    final existente = lastOrder;
    if (existente != null && existente.deviceId == deviceId) {
      return (order: existente, created: false);
    }
    final nova = DeviceWipeOrder(
      id: UuidValue.fromString('00000000-0000-4000-8000-00000000c001'),
      deviceId: deviceId,
      targetUserId: UuidValue.fromString(
        '00000000-0000-4000-8000-00000000c002',
      ),
      requestedBy: UuidValue.fromString('00000000-0000-4000-8000-00000000c003'),
      reason: reason,
      requestedAt: at,
    );
    lastOrder = nova;
    return (order: nova, created: true);
  }

  DeviceWipeOrder? pedido;
  bool entregue = false;
  bool confirmado = false;
  int deliveredCalls = 0;
  int confirmedCalls = 0;

  @override
  Future<DeviceWipeOrder?> orderFor(String deviceId) async {
    final p = pedido;
    if (p == null || p.deviceId != deviceId) return null;
    return p.copyWith(
      deliveredAt: entregue ? DateTime.utc(2026, 10, 17, 13) : null,
      confirmedAt: confirmado ? DateTime.utc(2026, 10, 17, 14) : null,
    );
  }

  @override
  Future<bool> markDelivered(String orderId, DateTime at) async {
    deliveredCalls++;
    if (entregue) return false;
    entregue = true;
    return true;
  }

  @override
  Future<bool> markConfirmed(
    String deviceId,
    String orderId,
    DateTime at,
  ) async {
    confirmedCalls++;
    final p = pedido;
    if (p == null || p.deviceId != deviceId || p.id.toString() != orderId) {
      return false;
    }
    if (confirmado) return false;
    confirmado = true;
    return true;
  }
}

class _Audit extends AuditTrail {
  final events = <AuditEvent>[];

  @override
  Future<void> record(AuditEvent event) async {
    _ordem.add(
      'audit:${event.actionType}:${event.resourceType}:${event.result}',
    );
    events.add(event);
  }
}

AuthenticatedUser _u(String id, UserRole role) =>
    AuthenticatedUser(id: id, role: role, microAreaId: null, deviceId: 'x');

void main() {
  late _Contas contas;
  late _Aparelhos aparelhos;
  late _Audit audit;
  late DeviceWipeService servico;
  var agora = DateTime.utc(2026, 10, 17, 12);
  final admin = _u('admin-1', UserRole.admin);
  final coordA = _u('coord-a', UserRole.coordinator);

  setUp(() {
    _ordem.clear();
    agora = DateTime.utc(2026, 10, 17, 12);
    contas = _Contas();
    aparelhos = _Aparelhos();
    audit = _Audit();
    servico = DeviceWipeService(
      store: aparelhos,
      accounts: contas,
      audit: audit,
      clock: () => agora,
    );
  });

  test('admin pede limpeza: created, revoga e audita wipe_ordered', () async {
    final r = await servico.orderWipe(
      admin,
      acsId: 'acs-b',
      deviceId: 'bbbbbbbb-2222',
      reason: DeviceWipeReason.lost,
    );
    expect(r.alreadyOrdered, isFalse);
    expect(r.orderId, aparelhos.lastOrder!.id.toString());
    expect(r.requestedAt, agora);
    expect(aparelhos.orderWipeCalls, 1);
    final e = audit.events.single;
    expect(e.actionType, 'write');
    expect(e.resourceType, 'admin_device');
    expect(e.result, 'wipe_ordered');
    expect(e.resourceId, r.orderId);
  });

  test(
    'pedido repetido devolve alreadyOrdered com o requestedAt original e audita already_ordered',
    () async {
      final primeiro = await servico.orderWipe(
        coordA,
        acsId: 'acs-a',
        deviceId: 'aaaaaaaa-1111',
        reason: DeviceWipeReason.stolen,
      );
      agora = agora.add(const Duration(hours: 3));
      final segundo = await servico.orderWipe(
        coordA,
        acsId: 'acs-a',
        deviceId: 'aaaaaaaa-1111',
        reason: DeviceWipeReason.lost,
      );
      expect(segundo.alreadyOrdered, isTrue);
      expect(segundo.orderId, primeiro.orderId);
      expect(segundo.requestedAt, primeiro.requestedAt);
      expect(audit.events.map((e) => e.result), [
        'wipe_ordered',
        'already_ordered',
      ]);
      expect(audit.events.last.resourceId, primeiro.orderId);
    },
  );

  test(
    'coordenador fora da UBS e aparelho alheio recebem a mesma recusa sem revogar nada',
    () async {
      final casos = <(String, String)>[
        ('acs-b', 'bbbbbbbb-2222'), // ACS de outra UBS
        ('acs-a', 'zzzzzzzz-9999'), // aparelho sem token desse ACS
        ('acs-a', InstitutionalAuthService.deviceIdAbsent), // sentinela
        ('acs-inexistente', 'aaaaaaaa-1111'), // ACS que não existe
      ];
      for (final (acs, dev) in casos) {
        audit.events.clear();
        await expectLater(
          servico.orderWipe(
            coordA,
            acsId: acs,
            deviceId: dev,
            reason: DeviceWipeReason.lost,
          ),
          throwsA(
            isA<AdminInvalidRequestException>().having(
              (e) => e.message,
              'message',
              'Aparelho não encontrado.',
            ),
          ),
          reason: '$acs/$dev',
        );
        expect(audit.events.single.result, 'denied');
        expect(audit.events.single.actionType, 'write');
        expect(aparelhos.orderWipeCalls, 0);
      }
    },
  );

  test('paciente e ACS não alcançam', () async {
    for (final role in [UserRole.patient, UserRole.acs]) {
      final u = _u('u-${role.name}', role);
      await expectLater(
        servico.orderWipe(
          u,
          acsId: 'acs-a',
          deviceId: 'aaaaaaaa-1111',
          reason: DeviceWipeReason.lost,
        ),
        throwsA(isA<AlertPermissionException>()),
      );
      await expectLater(
        servico.devicesOf(u, acsId: 'acs-a'),
        throwsA(isA<AlertPermissionException>()),
      );
    }
    expect(aparelhos.orderWipeCalls, 0);
    expect(audit.events.map((e) => e.result), everyElement('denied'));
  });

  test(
    'listagem audita read admin_acs_devices antes de ler e esconde o sentinela',
    () async {
      final lista = await servico.devicesOf(coordA, acsId: 'acs-a');
      expect(lista.map((d) => d.deviceId), ['aaaaaaaa-1111']);
      expect(
        _ordem.indexOf('audit:read:admin_acs_devices:success'),
        lessThan(_ordem.indexOf('store:devicesOf')),
      );
    },
  );

  test('listagem de ACS de outra UBS recebe a recusa única', () async {
    await expectLater(
      servico.devicesOf(coordA, acsId: 'acs-b'),
      throwsA(
        isA<AdminInvalidRequestException>().having(
          (e) => e.message,
          'message',
          'Aparelho não encontrado.',
        ),
      ),
    );
    expect(audit.events.single.result, 'denied');
    expect(_ordem, isNot(contains('store:devicesOf')));
  });

  group('lado do aparelho', () {
    const idPedido = '00000000-0000-4000-8000-00000000c001';
    const aparelho = 'aaaaaaaa-1111';

    void haPedido() {
      aparelhos.pedido = DeviceWipeOrder(
        id: UuidValue.fromString(idPedido),
        deviceId: aparelho,
        targetUserId: UuidValue.fromString(
          '00000000-0000-4000-8000-00000000c002',
        ),
        requestedBy: UuidValue.fromString(
          '00000000-0000-4000-8000-00000000c003',
        ),
        reason: DeviceWipeReason.lost,
        requestedAt: DateTime.utc(2026, 10, 17, 12),
      );
    }

    test('pendingOrderId marca entrega e audita só na primeira vez', () async {
      haPedido();
      expect(await servico.pendingOrderId(aparelho), idPedido);
      expect(await servico.pendingOrderId(aparelho), idPedido);
      expect(audit.events, hasLength(1));
      final e = audit.events.single;
      expect(e.userId, '00000000-0000-4000-8000-00000000c002');
      expect(e.actionType, 'write');
      expect(e.resourceType, 'acs_device');
      expect(e.resourceId, idPedido);
      expect(e.result, 'wipe_delivered');
    });

    test(
      'pendingOrderId de aparelho sem pedido, ou já confirmado, devolve null sem auditar',
      () async {
        expect(await servico.pendingOrderId(aparelho), isNull);
        haPedido();
        aparelhos.confirmado = true;
        expect(await servico.pendingOrderId(aparelho), isNull);
        expect(audit.events, isEmpty);
        expect(aparelhos.deliveredCalls, 0);
      },
    );

    test(
      'confirm com par errado não grava nem audita; com par certo grava uma vez',
      () async {
        haPedido();
        await servico.confirm(aparelho, '00000000-0000-4000-8000-0000000000ff');
        await servico.confirm('outro-aparelho', idPedido);
        expect(aparelhos.confirmado, isFalse);
        expect(audit.events, isEmpty);

        await servico.confirm(aparelho, idPedido);
        await servico.confirm(aparelho, idPedido);
        expect(aparelhos.confirmado, isTrue);
        final e = audit.events.single;
        expect(e.result, 'wipe_confirmed');
        expect(e.resourceType, 'acs_device');
        expect(e.actionType, 'write');
        expect(e.resourceId, idPedido);
        expect(e.userId, '00000000-0000-4000-8000-00000000c002');
      },
    );

    test(
      'ensureDeviceNotMarked lança com o orderId; sentinela e vazio passam',
      () async {
        await servico.ensureDeviceNotMarked(aparelho);
        haPedido();
        await expectLater(
          servico.ensureDeviceNotMarked(aparelho),
          throwsA(
            isA<DeviceWipeRequiredException>()
                .having((e) => e.orderId, 'orderId', idPedido)
                .having(
                  (e) => e.message,
                  'message',
                  'Este aparelho precisa ser limpo a pedido da coordenação.',
                ),
          ),
        );
        // Confirmado também continua marcado: o id antigo nunca volta (D1).
        aparelhos.confirmado = true;
        await expectLater(
          servico.ensureDeviceNotMarked(aparelho),
          throwsA(isA<DeviceWipeRequiredException>()),
        );
        await servico.ensureDeviceNotMarked(null);
        await servico.ensureDeviceNotMarked('');
        await servico.ensureDeviceNotMarked(
          InstitutionalAuthService.deviceIdAbsent,
        );
      },
    );
  });
}
