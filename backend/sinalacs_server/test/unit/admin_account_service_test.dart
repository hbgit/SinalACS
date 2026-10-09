import 'package:sinalacs_server/src/application/admin/admin_account_service.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/institutional_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/password_hasher.dart';
import 'package:sinalacs_server/src/application/auth/refresh_token_service.dart';
import 'package:sinalacs_server/src/application/auth/upload_token_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:test/test.dart';

/// Regras da gestão de contas do backoffice (#43) sem banco: papel, escopo por
/// UBS e a auditoria de cada leitura. Dados sintéticos.
const _ubsDoCoordenador = 'ubs-a';

/// Registra cada chamada com a ordem global, para provar "auditoria antes do dado".
final _ordem = <String>[];

class _Store implements AdminAccountStore {
  AdminScope? ultimoEscopo;
  int chamadas = 0;
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
  Future<List<AdminAcs>> acsList(AdminScope scope) async {
    _marca('acsList', scope);
    return [];
  }

  @override
  Future<List<AdminStaff>> staffList() async {
    _marca('staffList');
    return [];
  }

  @override
  Future<AdminAcs?> acsById(AdminScope scope, String acsId) =>
      throw UnimplementedError('acsById é das tarefas de escrita da #43');

  @override
  Future<AdminStaff?> staffById(String staffId) =>
      throw UnimplementedError('staffById é das tarefas de escrita da #43');

  @override
  Future<String?> ubsOf(String staffId) async => ubs[staffId];
}

/// Stubs das portas que esta tarefa (leitura) ainda não usa: as operações de
/// escrita da #43 é que passam por credencial, MFA, ativação, refresh e envio
/// diferido. Chamar qualquer uma aqui é erro de montagem do teste.
class _NaoUsado
    implements
        AcsCredentialStore,
        TotpStore,
        StaffActivationStore,
        RefreshTokenStore,
        UploadTokenStore,
        PasswordHasher {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} não é usado aqui');

  /// `RefreshTokenStore` e `UploadTokenStore` declaram este método com tipos de
  /// retorno incompatíveis entre si; por isso ele precisa de uma assinatura
  /// própria (`Never` satisfaz os dois) em vez de vir do `noSuchMethod`.
  @override
  Never findByHash(String tokenHash) =>
      throw UnimplementedError('findByHash não é usado aqui');
}

class _Audit extends AuditTrail {
  final events = <AuditEvent>[];
  bool falhar = false;

  @override
  Future<void> record(AuditEvent event) async {
    if (falhar) throw StateError('auditoria indisponível');
    _ordem.add('audit:${event.actionType}:${event.resourceType}:${event.result}');
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
  late AdminAccountService servico;
  final admin = _u('admin-1', UserRole.admin);
  final coordA = _u('coord-a', UserRole.coordinator);
  final coordSemUbs = _u('coord-sem-ubs', UserRole.coordinator);

  setUp(() {
    _ordem.clear();
    store = _Store();
    audit = _Audit();
    servico = AdminAccountService(
      store: store,
      credentials: _NaoUsado(),
      totpStore: _NaoUsado(),
      activationStore: _NaoUsado(),
      refreshStore: _NaoUsado(),
      uploadStore: _NaoUsado(),
      hasher: _NaoUsado(),
      audit: audit,
      clock: () => DateTime.utc(2026, 10, 8, 12),
    );
  });

  test(
    'admin lista ACS com escopo de sistema e a leitura é auditada ANTES do dado',
    () async {
      await servico.acsList(admin);
      expect(store.ultimoEscopo!.ubsId, isNull);
      expect(_ordem, ['audit:read:admin_acs:success', 'store:acsList']);
      expect(audit.events.single.actionType, 'read');
      expect(audit.events.single.userId, 'admin-1');
      expect(audit.events.single.resourceType, 'admin_acs');
    },
  );

  test(
    'coordenador lista só a própria UBS; a leitura é auditada com o recurso admin_acs',
    () async {
      await servico.acsList(coordA);
      expect(store.ultimoEscopo!.ubsId, 'ubs-a');
      expect(
        audit.events.single,
        isA<AuditEvent>()
            .having((e) => e.actionType, 'actionType', 'read')
            .having((e) => e.resourceType, 'resourceType', 'admin_acs'),
      );
    },
  );

  test('staffList é só do administrador: coordenador recebe recusa auditada', () async {
    await expectLater(
      servico.staffList(coordA),
      throwsA(isA<AlertPermissionException>()),
    );
    expect(audit.events.single.result, 'denied');
    expect(audit.events.single.resourceType, 'admin_staff');
    expect(store.chamadas, 0, reason: 'nenhum dado sai');
  });

  test('admin lista a equipe e a leitura é auditada ANTES do dado', () async {
    await servico.staffList(admin);
    expect(_ordem, ['audit:read:admin_staff:success', 'store:staffList']);
    expect(audit.events.single.resourceType, 'admin_staff');
  });

  test(
    'coordenador sem UBS é recusado em acsList e staffList, com auditoria denied',
    () async {
      await expectLater(
        servico.acsList(coordSemUbs),
        throwsA(isA<AlertPermissionException>()),
      );
      await expectLater(
        servico.staffList(coordSemUbs),
        throwsA(isA<AlertPermissionException>()),
      );
      expect(store.chamadas, 0);
      expect(audit.events, hasLength(2));
      expect(audit.events.map((e) => e.result), everyElement('denied'));
    },
  );

  test(
    'acs e patient com token válido são recusados nas duas listagens',
    () async {
      for (final role in [UserRole.acs, UserRole.patient]) {
        final u = _u('u-${role.name}', role);
        await expectLater(
          servico.acsList(u),
          throwsA(isA<AlertPermissionException>()),
        );
        await expectLater(
          servico.staffList(u),
          throwsA(isA<AlertPermissionException>()),
        );
      }
      expect(store.chamadas, 0);
      expect(audit.events, hasLength(4));
      expect(audit.events.map((e) => e.result), everyElement('denied'));
    },
  );

  test('se a auditoria falha, o store não é chamado (fail-closed)', () async {
    audit.falhar = true;
    await expectLater(servico.acsList(admin), throwsA(isA<StateError>()));
    expect(store.chamadas, 0);
  });
}
