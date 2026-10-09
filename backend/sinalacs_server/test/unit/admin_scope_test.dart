import 'package:sinalacs_server/src/application/admin/admin_scope.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:test/test.dart';

/// A regra única de papel/escopo do backoffice (#43) sem banco: papel, escopo,
/// recusa auditada e fail-closed. Dados sintéticos.
const _ubsDoCoordenador = 'ubs-a';

class _Store implements AdminScopeStore {
  _Store({Map<String, String?>? ubs}) : ubs = ubs ?? const {};

  final Map<String, String?> ubs;
  int chamadas = 0;

  @override
  Future<String?> ubsOf(String staffId) async {
    chamadas++;
    return ubs[staffId];
  }
}

class _Audit extends AuditTrail {
  final events = <AuditEvent>[];
  bool falhar = false;

  @override
  Future<void> record(AuditEvent event) async {
    if (falhar) throw StateError('auditoria indisponível');
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
  late AdminScopeResolver resolver;
  final admin = _u('admin-1', UserRole.admin);
  final coordA = _u('coord-a', UserRole.coordinator);
  final coordSemUbs = _u('coord-sem-ubs', UserRole.coordinator);

  setUp(() {
    store = _Store(ubs: {'coord-a': _ubsDoCoordenador, 'coord-sem-ubs': null});
    audit = _Audit();
    resolver = AdminScopeResolver(store: store, audit: audit);
  });

  test(
    'admin resolve para o sistema inteiro e a UBS nem é consultada',
    () async {
      final escopo = await resolver.resolve(admin, recurso: 'admin_indicators');
      expect(escopo.ubsId, isNull);
      expect(store.chamadas, 0);
      expect(audit.events, isEmpty);
    },
  );

  test(
    'coordenador resolve para a própria UBS, sem linha de auditoria',
    () async {
      final escopo = await resolver.resolve(
        coordA,
        recurso: 'admin_indicators',
      );
      expect(escopo.ubsId, _ubsDoCoordenador);
      expect(audit.events, isEmpty);
    },
  );

  test(
    'coordenador sem UBS é recusado, fail-closed, com denied na trilha',
    () async {
      final audit = _Audit();
      final r = AdminScopeResolver(
        store: _Store(ubs: {'coord': null}),
        audit: audit,
      );
      await expectLater(
        r.resolve(_u('coord', UserRole.coordinator), recurso: 'admin_acs'),
        throwsA(isA<AlertPermissionException>()),
      );
      expect(audit.events.single.result, 'denied');
      expect(audit.events.single.resourceType, 'admin_acs');
    },
  );

  test(
    'acs e patient são recusados mesmo com token válido, com denied na trilha',
    () async {
      for (final role in [UserRole.acs, UserRole.patient]) {
        final u = _u('u-${role.name}', role);
        await expectLater(
          resolver.resolve(u, recurso: 'admin_indicators'),
          throwsA(
            isA<AlertPermissionException>().having(
              (e) => e.message,
              'message',
              AdminScopeResolver.negado,
            ),
          ),
        );
        expect(audit.events.last.userId, u.id);
        expect(audit.events.last.actionType, 'read');
        expect(audit.events.last.resourceType, 'admin_indicators');
        expect(audit.events.last.result, 'denied');
      }
      expect(store.chamadas, 0, reason: 'papel recusado nem chega ao store');
    },
  );

  test('requireAdmin recusa coordenador e audita; admin passa', () async {
    await expectLater(
      resolver.requireAdmin(coordA, recurso: 'admin_audit_logs'),
      throwsA(
        isA<AlertPermissionException>().having(
          (e) => e.message,
          'message',
          AdminScopeResolver.negado,
        ),
      ),
    );
    expect(audit.events.single.result, 'denied');
    expect(audit.events.single.resourceType, 'admin_audit_logs');

    await resolver.requireAdmin(admin, recurso: 'admin_audit_logs');
    expect(audit.events, hasLength(1), reason: 'quem passa não gera denied');
  });

  test('requireAdmin recusa acs e patient', () async {
    for (final role in [UserRole.acs, UserRole.patient]) {
      await expectLater(
        resolver.requireAdmin(_u('u-${role.name}', role), recurso: 'admin_acs'),
        throwsA(isA<AlertPermissionException>()),
      );
    }
    expect(audit.events, hasLength(2));
    expect(audit.events.map((e) => e.result), everyElement('denied'));
  });

  test('recusa em caminho de escrita audita a TENTATIVA: actionType write', () async {
    // Papel fora do backoffice (resolve) e coordenador sem UBS (escopo).
    await expectLater(
      resolver.resolve(
        _u('u-acs', UserRole.acs),
        recurso: 'admin_acs',
        actionType: 'write',
      ),
      throwsA(isA<AlertPermissionException>()),
    );
    await expectLater(
      resolver.resolve(coordSemUbs, recurso: 'admin_acs', actionType: 'write'),
      throwsA(isA<AlertPermissionException>()),
    );
    // requireAdmin aceita o mesmo parâmetro.
    await expectLater(
      resolver.requireAdmin(
        coordA,
        recurso: 'admin_staff',
        actionType: 'write',
      ),
      throwsA(isA<AlertPermissionException>()),
    );

    expect(audit.events, hasLength(3));
    expect(
      audit.events.map((e) => e.actionType),
      everyElement('write'),
      reason: 'a linha descreve o que foi TENTADO: uma escrita',
    );
    expect(audit.events.map((e) => e.result), everyElement('denied'));

    // O default continua `read`: nenhuma linha do caminho de leitura muda de forma.
    await expectLater(
      resolver.resolve(coordSemUbs, recurso: 'admin_indicators'),
      throwsA(isA<AlertPermissionException>()),
    );
    expect(audit.events.last.actionType, 'read');
    expect(audit.events.last.resourceType, 'admin_indicators');
    expect(audit.events.last.result, 'denied');
  });

  test('se a auditoria falha, a exceção sobe no lugar da recusa', () async {
    audit.falhar = true;
    await expectLater(
      resolver.resolve(coordSemUbs, recurso: 'admin_indicators'),
      throwsA(isA<StateError>()),
    );
  });
}
