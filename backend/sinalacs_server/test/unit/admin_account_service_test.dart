import 'dart:math';

import 'package:sinalacs_server/src/application/admin/admin_account_service.dart';
import 'package:sinalacs_server/src/application/admin/initial_password.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/institutional_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/password_hasher.dart';
import 'package:sinalacs_server/src/application/auth/staff_activation_code.dart';
import 'package:sinalacs_server/src/application/auth/totp_secret_vault.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:test/test.dart';

/// Regras da gestão de contas do backoffice (#43) sem banco: papel, escopo por
/// UBS e a auditoria de cada leitura. Dados sintéticos.
const _ubsDoCoordenador = 'ubs-a';

/// Id em UUID de verdade da prova de normalização: `UuidValue` e o `::uuid` do
/// Postgres normalizam a caixa, então a mesma conta pode chegar grafada de duas
/// formas — e nenhuma delas pode ser tratada como outra conta.
const _uuidDoCoordenador = '00000000-0000-4000-8000-00000000ab01';

/// Registra cada chamada com a ordem global, para provar "auditoria antes do dado".
final _ordem = <String>[];

class _Store implements AdminAccountStore {
  AdminScope? ultimoEscopo;
  int chamadas = 0;
  final Map<String, String?> ubs = {
    'coord-a': _ubsDoCoordenador,
    'coord-sem-ubs': null,
  };

  /// Microáreas conhecidas: a UBS de cada uma é o que decide se o coordenador
  /// pode cadastrar nela. `ma-b` é de outra UBS de propósito.
  final Map<String, ({String? ubsId, String? name})> microAreas = {
    'ma-a': (ubsId: _ubsDoCoordenador, name: 'Microárea A'),
    'ma-b': (ubsId: 'ubs-b', name: 'Microárea B'),
  };

  /// ACS conhecidos, por id: o `ubsId` de cada um é o que o escopo compara.
  /// `acs-a` é da UBS do coordenador; `acs-b`, da outra.
  final acs = <String, AdminAcs>{
    'acs-a': AdminAcs(
      id: 'acs-a',
      name: 'Ana ACS',
      enrollmentId: 'ACS-1',
      ubsId: _ubsDoCoordenador,
      ubsName: 'UBS A',
      microAreaId: 'ma-antiga',
      microAreaName: 'Microárea Antiga',
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

  /// Matrículas já cadastradas (a pré-checagem do serviço).
  final matriculas = <String>{};

  /// `true` = a pré-checagem passou e o índice único do banco disparou
  /// (`insertAcs` devolve `null`): a corrida que o catch de 23505 fecha.
  bool corridaDeMatricula = false;

  /// `true` = a pré-checagem de [setAcsMicroArea] achou o ACS e o `UPDATE`
  /// condicional do banco não (o ACS saiu do escopo no meio): a corrida que o
  /// `WHERE` com o predicado de escopo fecha.
  bool corridaDeVinculo = false;

  /// Mesma corrida de [corridaDeVinculo], para [setAcsActive].
  bool corridaDeAtivacao = false;

  int insertAcsChamadas = 0;
  int setAcsMicroAreaChamadas = 0;
  int setAcsActiveChamadas = 0;
  String? ultimaUbs;
  String? ultimaMicroArea;
  bool? ultimoActive;
  PasswordDigest? ultimoDigest;
  DateTime? ultimoAt;

  void _marca(String nome, [AdminScope? escopo]) {
    chamadas++;
    ultimoEscopo = escopo;
    _ordem.add('store:$nome');
  }

  @override
  Future<({String? ubsId, String? name})?> microAreaFor(String microAreaId) async {
    _marca('microAreaFor');
    return microAreas[microAreaId];
  }

  @override
  Future<bool> enrollmentIdTaken(String enrollmentId) async {
    _marca('enrollmentIdTaken');
    return matriculas.contains(enrollmentId);
  }

  @override
  Future<AdminAcs?> insertAcs({
    required String name,
    required String enrollmentId,
    required String microAreaId,
    required String ubsId,
    required PasswordDigest digest,
    required DateTime at,
  }) async {
    _marca('insertAcs');
    insertAcsChamadas++;
    ultimaUbs = ubsId;
    ultimaMicroArea = microAreaId;
    ultimoDigest = digest;
    ultimoAt = at;
    if (corridaDeMatricula) return null;
    return AdminAcs(
      id: 'acs-novo-1',
      name: name,
      enrollmentId: enrollmentId,
      ubsId: ubsId,
      ubsName: 'UBS A',
      microAreaId: microAreaId,
      microAreaName: 'Microárea A',
      active: true,
      mfaActive: false,
    );
  }

  @override
  Future<AdminAcs?> acsById(AdminScope scope, String acsId) async {
    _marca('acsById', scope);
    final encontrado = acs[acsId];
    if (encontrado == null) return null;
    if (scope.ubsId != null && encontrado.ubsId != scope.ubsId) return null;
    return encontrado;
  }

  @override
  Future<AdminAcs?> setAcsMicroArea({
    required String acsId,
    required String microAreaId,
    required String ubsId,
    required AdminScope scope,
    required DateTime at,
  }) async {
    _marca('setAcsMicroArea', scope);
    setAcsMicroAreaChamadas++;
    ultimaUbs = ubsId;
    ultimaMicroArea = microAreaId;
    ultimoAt = at;
    final encontrado = acs[acsId];
    if (encontrado == null) return null;
    if (scope.ubsId != null && encontrado.ubsId != scope.ubsId) return null;
    if (corridaDeVinculo) return null;
    final movido = encontrado.copyWith(
      ubsId: ubsId,
      microAreaId: microAreaId,
      microAreaName: microAreas[microAreaId]?.name,
    );
    acs[acsId] = movido;
    return movido;
  }

  @override
  Future<bool> setAcsActive({
    required String acsId,
    required AdminScope scope,
    required bool active,
    required DateTime at,
  }) async {
    _marca('setAcsActive', scope);
    setAcsActiveChamadas++;
    ultimoActive = active;
    ultimoAt = at;
    final encontrado = acs[acsId];
    if (encontrado == null) return false;
    if (scope.ubsId != null && encontrado.ubsId != scope.ubsId) return false;
    if (corridaDeAtivacao) return false;
    acs[acsId] = encontrado.copyWith(active: active);
    return true;
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

  /// Contas de equipe conhecidas, por id: é o alvo da redefinição da MFA do
  /// staff. `staff-inativo` existe e está desativada — a mesma recusa do
  /// inexistente, para que o administrador não descubra a existência de uma
  /// conta que não pode operar.
  final staff = <String, AdminStaff>{
    'admin-1': AdminStaff(
      id: 'admin-1',
      name: 'Elisa Administradora',
      enrollmentId: 'ADM-1',
      role: UserRole.admin,
      ubsName: null,
      active: true,
      mfaActive: true,
    ),
    'coord-a': AdminStaff(
      id: 'coord-a',
      name: 'Fábio Coordenador',
      enrollmentId: 'COO-1',
      role: UserRole.coordinator,
      ubsName: _ubsDoCoordenador,
      active: true,
      mfaActive: true,
    ),
    'staff-inativo': AdminStaff(
      id: 'staff-inativo',
      name: 'Gilda Coordenadora Inativa',
      enrollmentId: 'COO-2',
      role: UserRole.coordinator,
      ubsName: _ubsDoCoordenador,
      active: false,
      mfaActive: false,
    ),
    _uuidDoCoordenador: AdminStaff(
      id: _uuidDoCoordenador,
      name: 'Hélio Coordenador UUID',
      enrollmentId: 'COO-3',
      role: UserRole.coordinator,
      ubsName: _ubsDoCoordenador,
      active: true,
      mfaActive: false,
    ),
  };

  @override
  Future<AdminStaff?> staffById(String staffId) async {
    _marca('staffById');
    return staff[staffId];
  }

  /// O `resetStaffMfa` do store real: `clearTotp` e `issue` numa transação só.
  /// Aqui fica o pedido do serviço — o que o teste observa é o que ele mandou
  /// gravar (as duas escritas no banco têm prova na suíte de integração).
  final resetsDoStaff =
      <({String staffId, String codeHash, DateTime expiresAt, String issuedBy, DateTime at})>[];

  /// `true` = o alvo sumiu (ou foi desativado) entre a checagem do serviço e a
  /// transação: o `WHERE` do banco não alcança linha nenhuma e o store devolve
  /// `false` — o mesmo desfecho de "não existe".
  bool corridaDeResetStaff = false;

  @override
  Future<bool> resetStaffMfa({
    required String staffId,
    required String codeHash,
    required DateTime expiresAt,
    required String issuedBy,
    required DateTime at,
  }) async {
    _marca('resetStaffMfa');
    if (corridaDeResetStaff) return false;
    resetsDoStaff.add((
      staffId: staffId,
      codeHash: codeHash,
      expiresAt: expiresAt,
      issuedBy: issuedBy,
      at: at,
    ));
    return true;
  }

  @override
  Future<String?> ubsOf(String staffId) async => ubs[staffId];
}

/// Código de ativação do staff: guarda a emissão pedida pela redefinição da MFA
/// (#43). `find`/`clear` não são do caminho da redefinição — chamá-los aqui é
/// erro de montagem do teste, como no `_NaoUsado` que este fake substitui.
class _Ativacoes implements StaffActivationStore {
  final emissoes =
      <({String staffId, String codeHash, DateTime expiresAt, String issuedBy, DateTime at})>[];

  @override
  Future<void> issue(
    String staffId, {
    required String codeHash,
    required DateTime expiresAt,
    required String issuedBy,
    required DateTime at,
  }) async {
    _ordem.add('activation:issue');
    emissoes.add((
      staffId: staffId,
      codeHash: codeHash,
      expiresAt: expiresAt,
      issuedBy: issuedBy,
      at: at,
    ));
  }

  @override
  Future<StaffActivationRecord?> find(String staffId) =>
      throw UnimplementedError('find não é usado aqui');

  @override
  Future<void> clear(String staffId) =>
      throw UnimplementedError('clear não é usado aqui');
}

/// Credencial do ACS: guarda a substituição pedida pela redefinição de senha —
/// é o que o teste observa, porque o serviço não tem retorno daqui.
class _Credenciais implements AcsCredentialStore {
  final trocas = <(String, PasswordDigest, DateTime)>[];

  @override
  Future<void> saveCredential(String acsId, PasswordDigest digest, DateTime at) async {
    _ordem.add('credentials:saveCredential');
    trocas.add((acsId, digest, at));
  }

  @override
  Future<AcsCredentialRecord?> findByEnrollmentId(String enrollmentId) =>
      throw UnimplementedError('findByEnrollmentId não é usado aqui');

  @override
  Future<void> registerFailedAttempt(
    String acsId, {
    required bool restartCounter,
    required int maxFailedAttempts,
    required DateTime lockUntil,
    required DateTime at,
  }) => throw UnimplementedError('registerFailedAttempt não é usado aqui');

  @override
  Future<void> registerSuccessfulLogin(String acsId, DateTime at) =>
      throw UnimplementedError('registerSuccessfulLogin não é usado aqui');
}

/// Estado da MFA: guarda as limpezas pedidas pela redefinição de MFA.
class _Totp implements TotpStore {
  final limpezas = <(String, DateTime)>[];

  @override
  Future<void> clearTotp(String acsId, DateTime at) async {
    _ordem.add('totp:clearTotp');
    limpezas.add((acsId, at));
  }

  @override
  Future<bool> saveSecret(String acsId, SealedSecret secret, DateTime at) =>
      throw UnimplementedError('saveSecret não é usado aqui');

  @override
  Future<bool> enable(String acsId, SealedSecret pending, int step, DateTime at) =>
      throw UnimplementedError('enable não é usado aqui');

  @override
  Future<bool> registerStep(String acsId, int step) =>
      throw UnimplementedError('registerStep não é usado aqui');
}

/// Hasher de mentira: guarda a senha em claro que recebeu, para o teste provar
/// que a credencial gravada é exatamente a que o serviço devolve ao operador.
/// O custo do Argon2id não é o que se prova aqui — a derivação de verdade tem
/// os próprios testes.
class _Hasher implements PasswordHasher {
  final senhas = <String>[];

  static const digest = PasswordDigest(
    hashBase64: 'hash-sintetico',
    saltBase64: 'salt-sintetico',
    memoryKb: 512,
    iterations: 1,
    parallelism: 1,
  );

  @override
  Future<PasswordDigest> derive(String password) async {
    senhas.add(password);
    return digest;
  }

  @override
  Future<bool> matches(String password, PasswordDigest digest) async => false;
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
  late _Hasher hasher;
  late _Credenciais credenciais;
  late _Totp totp;
  late _Ativacoes ativacoes;
  late AdminAccountService servico;
  final admin = _u('admin-1', UserRole.admin);
  final coordA = _u('coord-a', UserRole.coordinator);
  final coordSemUbs = _u('coord-sem-ubs', UserRole.coordinator);

  setUp(() {
    _ordem.clear();
    store = _Store();
    audit = _Audit();
    hasher = _Hasher();
    credenciais = _Credenciais();
    totp = _Totp();
    ativacoes = _Ativacoes();
    servico = AdminAccountService(
      store: store,
      credentials: credenciais,
      totpStore: totp,
      activationStore: ativacoes,
      hasher: hasher,
      audit: audit,
      // Sorteio e relógio fixos: o teste compara a senha devolvida com a que o
      // hasher recebeu, não com um valor escrito à mão.
      random: Random(1),
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

  group('createAcs', () {
    test(
      'nome/matrícula/microárea inválidos → AdminInvalidRequestException, nada escrito, recusa auditada',
      () async {
        final casos = <(AuthenticatedUser, String, String, String, String)>[
          // (operador, nome, matrícula, microárea, mensagem)
          (admin, '   ', 'ACS-43-1', 'ma-a', 'Informe nome e matrícula do ACS.'),
          (admin, 'Nova ACS', '   ', 'ma-a', 'Informe nome e matrícula do ACS.'),
          (admin, 'Nova ACS', 'ACS-43-1', 'inexistente', 'Microárea não encontrada.'),
          // Microárea de OUTRA UBS recebe a MESMA mensagem de "não existe": o
          // coordenador não descobre território alheio por tentativa.
          (coordA, 'Nova ACS', 'ACS-43-1', 'ma-b', 'Microárea não encontrada.'),
        ];
        for (final (operador, nome, matricula, microarea, mensagem) in casos) {
          await expectLater(
            servico.createAcs(
              operador,
              name: nome,
              enrollmentId: matricula,
              microAreaId: microarea,
            ),
            throwsA(
              isA<AdminInvalidRequestException>().having(
                (e) => e.message,
                'message',
                mensagem,
              ),
            ),
          );
        }
        // Os limites de tamanho entram na mesma validação do vazio.
        for (final (nome, matricula) in [
          ('N' * 121, 'ACS-43-1'),
          ('Nova ACS', 'A' * 33),
        ]) {
          await expectLater(
            servico.createAcs(
              admin,
              name: nome,
              enrollmentId: matricula,
              microAreaId: 'ma-a',
            ),
            throwsA(isA<AdminInvalidRequestException>()),
          );
        }

        expect(audit.events, hasLength(casos.length + 2));
        expect(audit.events.map((e) => e.actionType), everyElement('write'));
        expect(audit.events.map((e) => e.result), everyElement('denied'));
        expect(store.insertAcsChamadas, 0, reason: 'nada é escrito');
        expect(hasher.senhas, isEmpty, reason: 'nem a senha chega a ser sorteada');
      },
    );

    test(
      'coordenador cadastra na própria UBS e a auditoria registra created com o id do novo ACS',
      () async {
        final resultado = await servico.createAcs(
          coordA,
          name: '  Nova ACS  ',
          enrollmentId: '  ACS-43-1  ',
          microAreaId: 'ma-a',
        );

        expect(resultado.acs.name, 'Nova ACS', reason: 'trim do nome');
        expect(resultado.acs.enrollmentId, 'ACS-43-1', reason: 'trim da matrícula');
        expect(
          resultado.acs.ubsId,
          _ubsDoCoordenador,
          reason: 'a UBS vem da microárea escolhida, nunca do pedido',
        );
        expect(store.ultimaUbs, _ubsDoCoordenador);
        expect(store.ultimaMicroArea, 'ma-a');
        expect(store.ultimoAt, DateTime.utc(2026, 10, 8, 12));
        expect(store.ultimoDigest, _Hasher.digest);

        expect(
          resultado.initialPassword,
          matches(
            RegExp(
              r'^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{4}'
              r'(-[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{4}){3}$',
            ),
          ),
        );
        expect(
          hasher.senhas,
          [resultado.initialPassword],
          reason: 'a credencial gravada é exatamente a senha devolvida ao operador',
        );

        expect(
          _ordem,
          [
            'store:microAreaFor',
            'store:enrollmentIdTaken',
            'store:insertAcs',
            'audit:write:admin_acs:created',
          ],
          reason: 'a linha de sucesso entra DEPOIS do commit',
        );
        final linha = audit.events.single;
        expect(linha.userId, 'coord-a');
        expect(linha.actionType, 'write');
        expect(linha.resourceType, 'admin_acs');
        expect(linha.result, 'created');
        expect(linha.resourceId, resultado.acs.id);
      },
    );

    test('matrícula duplicada → mesma mensagem de validação, nunca erro de servidor', () async {
      const mensagem = 'Já existe um ACS com esta matrícula.';

      // Caso comum: a pré-checagem vê a matrícula e nada é escrito.
      store.matriculas.add('ACS-43-1');
      await expectLater(
        servico.createAcs(
          admin,
          name: 'Nova ACS',
          enrollmentId: 'ACS-43-1',
          microAreaId: 'ma-a',
        ),
        throwsA(
          isA<AdminInvalidRequestException>().having(
            (e) => e.message,
            'message',
            mensagem,
          ),
        ),
      );
      expect(store.insertAcsChamadas, 0);

      // Corrida: a pré-checagem passou e quem barrou foi o índice único do
      // banco (`insertAcs` devolveu null) — a mesma resposta, não um 500.
      store.matriculas.clear();
      store.corridaDeMatricula = true;
      await expectLater(
        servico.createAcs(
          admin,
          name: 'Nova ACS',
          enrollmentId: 'ACS-43-1',
          microAreaId: 'ma-a',
        ),
        throwsA(
          isA<AdminInvalidRequestException>().having(
            (e) => e.message,
            'message',
            mensagem,
          ),
        ),
      );
      expect(store.insertAcsChamadas, 1);

      expect(audit.events, hasLength(2));
      expect(audit.events.map((e) => e.actionType), everyElement('write'));
      expect(audit.events.map((e) => e.result), everyElement('denied'));
      expect(hasher.senhas, hasLength(1), reason: 'só a corrida chega a sortear a senha');
    });

    test('papel fora do backoffice e coordenador sem UBS recebem recusa auditada', () async {
      for (final usuario in [
        _u('u-acs', UserRole.acs),
        _u('u-paciente', UserRole.patient),
        coordSemUbs,
      ]) {
        await expectLater(
          servico.createAcs(
            usuario,
            name: 'Nova ACS',
            enrollmentId: 'ACS-43-1',
            microAreaId: 'ma-a',
          ),
          throwsA(isA<AlertPermissionException>()),
        );
      }
      expect(store.chamadas, 0);
      expect(audit.events, hasLength(3));
      expect(
        audit.events.map((e) => e.actionType),
        everyElement('write'),
        reason: 'a linha descreve a TENTATIVA de escrita, não uma leitura',
      );
      expect(audit.events.map((e) => e.result), everyElement('denied'));
    });
  });

  group('setAcsMicroArea', () {
    test(
      'microárea inexistente e microárea de outra UBS → mesma mensagem, nada escrito, recusa auditada',
      () async {
        final casos = <(AuthenticatedUser, String, String)>[
          // (operador, acsId, microárea-alvo)
          (admin, 'acs-a', 'inexistente'),
          // Microárea de OUTRA UBS recebe a MESMA mensagem de "não existe".
          (coordA, 'acs-a', 'ma-b'),
        ];
        for (final (operador, acsId, microarea) in casos) {
          await expectLater(
            servico.setAcsMicroArea(operador, acsId: acsId, microAreaId: microarea),
            throwsA(
              isA<AdminInvalidRequestException>().having(
                (e) => e.message,
                'message',
                'Microárea não encontrada.',
              ),
            ),
          );
        }
        expect(store.setAcsMicroAreaChamadas, 0, reason: 'nada é escrito');
        expect(
          _ordem.where((c) => c.startsWith('store:')),
          ['store:microAreaFor', 'store:microAreaFor'],
          reason: 'a microárea-alvo é validada antes de qualquer leitura do ACS',
        );
        expect(audit.events, hasLength(casos.length));
        expect(audit.events.map((e) => e.actionType), everyElement('write'));
        expect(audit.events.map((e) => e.result), everyElement('denied'));
      },
    );

    test('ACS inexistente e ACS de outra UBS → mesma recusa auditada', () async {
      final casos = <(AuthenticatedUser, String)>[
        (admin, 'acs-inexistente'),
        // ACS da outra UBS: o coordenador não descobre território alheio.
        (coordA, 'acs-b'),
      ];
      for (final (operador, acsId) in casos) {
        await expectLater(
          servico.setAcsMicroArea(operador, acsId: acsId, microAreaId: 'ma-a'),
          throwsA(
            isA<AdminInvalidRequestException>().having(
              (e) => e.message,
              'message',
              'ACS não encontrado.',
            ),
          ),
        );
      }
      expect(store.setAcsMicroAreaChamadas, 0, reason: 'nada é escrito');
      expect(audit.events, hasLength(casos.length));
      expect(audit.events.map((e) => e.actionType), everyElement('write'));
      expect(audit.events.map((e) => e.result), everyElement('denied'));
    });

    test('coordenador move o ACS da própria UBS e a trilha registra micro_area_changed com o id', () async {
      final resultado = await servico.setAcsMicroArea(
        coordA,
        acsId: 'acs-a',
        microAreaId: 'ma-a',
      );

      expect(resultado.id, 'acs-a');
      expect(resultado.microAreaId, 'ma-a');
      expect(resultado.microAreaName, 'Microárea A');
      expect(resultado.ubsId, _ubsDoCoordenador, reason: 'a UBS vem da microárea-alvo');
      expect(store.ultimaUbs, _ubsDoCoordenador);
      expect(store.ultimaMicroArea, 'ma-a');
      expect(store.ultimoAt, DateTime.utc(2026, 10, 8, 12));

      expect(
        _ordem,
        [
          'store:microAreaFor',
          'store:acsById',
          'store:setAcsMicroArea',
          'store:acsById',
          'audit:write:admin_acs:micro_area_changed',
        ],
        reason: 'a linha de sucesso entra DEPOIS do commit, e a releitura é do serviço',
      );
      final linha = audit.events.single;
      expect(linha.userId, 'coord-a');
      expect(linha.actionType, 'write');
      expect(linha.resourceType, 'admin_acs');
      expect(linha.result, 'micro_area_changed');
      expect(linha.resourceId, 'acs-a');
    });

    test('administrador move entre UBS: a UBS nova vem da microárea-alvo, não do escopo', () async {
      final resultado = await servico.setAcsMicroArea(
        admin,
        acsId: 'acs-a',
        microAreaId: 'ma-b',
      );

      expect(
        store.ultimaUbs,
        'ubs-b',
        reason: 'o escopo do administrador é nulo; a UBS do vínculo é a da microárea',
      );
      expect(resultado.ubsId, 'ubs-b');
      expect(resultado.microAreaId, 'ma-b');
      expect(resultado.microAreaName, 'Microárea B');
    });

    test('corrida: o ACS sai do escopo entre a pré-checagem e o UPDATE → mesma recusa', () async {
      // A pré-checagem viu o ACS; o UPDATE condicional do banco não achou
      // (`setAcsMicroArea` devolve null). A resposta é a mesma de "não existe".
      store.corridaDeVinculo = true;
      await expectLater(
        servico.setAcsMicroArea(coordA, acsId: 'acs-a', microAreaId: 'ma-a'),
        throwsA(
          isA<AdminInvalidRequestException>().having(
            (e) => e.message,
            'message',
            'ACS não encontrado.',
          ),
        ),
      );
      expect(store.setAcsMicroAreaChamadas, 1);
      expect(audit.events.single.actionType, 'write');
      expect(audit.events.single.result, 'denied');
    });

    test('papel fora do backoffice e coordenador sem UBS recebem recusa auditada', () async {
      for (final usuario in [
        _u('u-acs', UserRole.acs),
        _u('u-paciente', UserRole.patient),
        coordSemUbs,
      ]) {
        await expectLater(
          servico.setAcsMicroArea(usuario, acsId: 'acs-a', microAreaId: 'ma-a'),
          throwsA(isA<AlertPermissionException>()),
        );
      }
      expect(store.chamadas, 0, reason: 'nem a microárea-alvo é consultada');
      expect(audit.events, hasLength(3));
      expect(
        audit.events.map((e) => e.actionType),
        everyElement('write'),
        reason: 'a linha descreve a TENTATIVA de escrita, não uma leitura',
      );
      expect(audit.events.map((e) => e.result), everyElement('denied'));
    });
  });

  group('setAcsActive', () {
    test(
      'desativar devolve a linha inativa e audita deactivated DEPOIS do commit',
      () async {
        final resultado = await servico.setAcsActive(
          admin,
          acsId: 'acs-a',
          active: false,
        );

        expect(resultado.id, 'acs-a');
        expect(resultado.active, isFalse);
        expect(store.ultimoActive, isFalse);
        expect(store.ultimoAt, DateTime.utc(2026, 10, 8, 12));
        expect(store.ultimoEscopo!.ubsId, isNull, reason: 'escopo do administrador');

        expect(
          _ordem,
          [
            'store:acsById',
            'store:setAcsActive',
            'store:acsById',
            'audit:write:admin_acs:deactivated',
          ],
          reason: 'a linha de sucesso entra DEPOIS do commit, e a releitura é do serviço',
        );
        final linha = audit.events.single;
        expect(linha.userId, 'admin-1');
        expect(linha.actionType, 'write');
        expect(linha.resourceType, 'admin_acs');
        expect(linha.result, 'deactivated');
        expect(linha.resourceId, 'acs-a');
      },
    );

    test('coordenador desativa o ACS da própria UBS no escopo de UBS', () async {
      final resultado = await servico.setAcsActive(
        coordA,
        acsId: 'acs-a',
        active: false,
      );

      expect(store.ultimoEscopo!.ubsId, _ubsDoCoordenador);
      expect(resultado.active, isFalse);
      expect(audit.events.single.result, 'deactivated');
      expect(audit.events.single.resourceId, 'acs-a');
    });

    test(
      'reativar audita activated e devolve a linha ativa de novo',
      () async {
        await servico.setAcsActive(admin, acsId: 'acs-a', active: false);
        final resultado = await servico.setAcsActive(
          admin,
          acsId: 'acs-a',
          active: true,
        );

        expect(resultado.active, isTrue);
        expect(store.ultimoActive, isTrue);
        expect(
          audit.events.map((e) => e.result),
          ['deactivated', 'activated'],
          reason: 'cada pedido do operador vira uma linha, com o desfecho do pedido',
        );
        expect(audit.events.map((e) => e.resourceId), everyElement('acs-a'));
      },
    );

    test('desativar um ACS já inativo é idempotente e audita uma linha nova', () async {
      final primeira = await servico.setAcsActive(admin, acsId: 'acs-a', active: false);
      final segunda = await servico.setAcsActive(admin, acsId: 'acs-a', active: false);

      expect(primeira.active, isFalse);
      expect(segunda.active, isFalse);
      expect(store.setAcsActiveChamadas, 2, reason: 'o segundo pedido também escreve');
      expect(
        audit.events.map((e) => e.result),
        ['deactivated', 'deactivated'],
        reason: 'idempotente não é silencioso: a trilha registra os dois pedidos',
      );
    });

    test('ACS inexistente e ACS de outra UBS → mesma recusa auditada, nada escrito', () async {
      final casos = <(AuthenticatedUser, String)>[
        (admin, 'acs-inexistente'),
        // ACS da outra UBS: o coordenador não descobre território alheio.
        (coordA, 'acs-b'),
      ];
      for (final (operador, acsId) in casos) {
        await expectLater(
          servico.setAcsActive(operador, acsId: acsId, active: false),
          throwsA(
            isA<AdminInvalidRequestException>().having(
              (e) => e.message,
              'message',
              'ACS não encontrado.',
            ),
          ),
        );
      }
      expect(store.setAcsActiveChamadas, 0, reason: 'nada é escrito');
      expect(audit.events, hasLength(casos.length));
      expect(audit.events.map((e) => e.actionType), everyElement('write'));
      expect(audit.events.map((e) => e.result), everyElement('denied'));
    });

    test('corrida: o ACS sai do escopo entre a pré-checagem e o UPDATE → mesma recusa', () async {
      store.corridaDeAtivacao = true;
      await expectLater(
        servico.setAcsActive(coordA, acsId: 'acs-a', active: false),
        throwsA(
          isA<AdminInvalidRequestException>().having(
            (e) => e.message,
            'message',
            'ACS não encontrado.',
          ),
        ),
      );
      expect(store.setAcsActiveChamadas, 1);
      expect(audit.events.single.actionType, 'write');
      expect(audit.events.single.result, 'denied');
    });

    test('papel fora do backoffice e coordenador sem UBS recebem recusa auditada', () async {
      for (final usuario in [
        _u('u-acs', UserRole.acs),
        _u('u-paciente', UserRole.patient),
        coordSemUbs,
      ]) {
        await expectLater(
          servico.setAcsActive(usuario, acsId: 'acs-a', active: false),
          throwsA(isA<AlertPermissionException>()),
        );
      }
      expect(store.chamadas, 0, reason: 'nem o alvo é lido');
      expect(audit.events, hasLength(3));
      expect(
        audit.events.map((e) => e.actionType),
        everyElement('write'),
        reason: 'a linha descreve a TENTATIVA de escrita, não uma leitura',
      );
      expect(audit.events.map((e) => e.result), everyElement('denied'));
    });
  });

  group('resetAcsPassword', () {
    test(
      'admin redefine: senha nova sorteada, Argon2id derivado e auditoria password_reset DEPOIS do commit',
      () async {
        final resultado = await servico.resetAcsPassword(admin, acsId: 'acs-a');

        expect(
          resultado.newPassword,
          matches(
            RegExp(
              r'^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{4}'
              r'(-[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{4}){3}$',
            ),
          ),
          reason: 'o mesmo formato da senha inicial: o operador não escolhe a senha',
        );
        expect(
          hasher.senhas,
          [resultado.newPassword],
          reason: 'a credencial gravada é exatamente a senha devolvida ao operador',
        );
        expect(credenciais.trocas, [
          ('acs-a', _Hasher.digest, DateTime.utc(2026, 10, 8, 12)),
        ]);

        expect(
          _ordem,
          [
            'store:acsById',
            'credentials:saveCredential',
            'audit:write:admin_acs:password_reset',
          ],
          reason: 'o alvo é validado antes do sorteio e a linha de sucesso entra DEPOIS do commit',
        );
        final linha = audit.events.single;
        expect(linha.userId, 'admin-1');
        expect(linha.actionType, 'write');
        expect(linha.resourceType, 'admin_acs');
        expect(linha.result, 'password_reset');
        expect(linha.resourceId, 'acs-a');
      },
    );

    test('coordenador redefine a senha do ACS da própria UBS, com o escopo de UBS', () async {
      final resultado = await servico.resetAcsPassword(coordA, acsId: 'acs-a');

      expect(resultado.newPassword, isNotEmpty);
      expect(store.ultimoEscopo!.ubsId, _ubsDoCoordenador);
      expect(audit.events.single.result, 'password_reset');
      expect(audit.events.single.resourceId, 'acs-a');
    });

    test('ACS inexistente e ACS de outra UBS → mesma recusa auditada, nada escrito', () async {
      final casos = <(AuthenticatedUser, String)>[
        (admin, 'acs-inexistente'),
        // ACS da outra UBS: o coordenador não descobre território alheio.
        (coordA, 'acs-b'),
      ];
      for (final (operador, acsId) in casos) {
        await expectLater(
          servico.resetAcsPassword(operador, acsId: acsId),
          throwsA(
            isA<AdminInvalidRequestException>().having(
              (e) => e.message,
              'message',
              'ACS não encontrado.',
            ),
          ),
        );
      }
      expect(credenciais.trocas, isEmpty, reason: 'a credencial antiga fica como está');
      expect(
        hasher.senhas,
        isEmpty,
        reason: 'nem a senha é sorteada para um alvo fora do escopo (derivar é caro)',
      );
      expect(audit.events, hasLength(casos.length));
      expect(audit.events.map((e) => e.actionType), everyElement('write'));
      expect(audit.events.map((e) => e.result), everyElement('denied'));
    });

    test('papel fora do backoffice e coordenador sem UBS recebem recusa auditada', () async {
      for (final usuario in [
        _u('u-acs', UserRole.acs),
        _u('u-paciente', UserRole.patient),
        coordSemUbs,
      ]) {
        await expectLater(
          servico.resetAcsPassword(usuario, acsId: 'acs-a'),
          throwsA(isA<AlertPermissionException>()),
        );
      }
      expect(store.chamadas, 0, reason: 'nem o alvo é lido');
      expect(audit.events, hasLength(3));
      expect(
        audit.events.map((e) => e.actionType),
        everyElement('write'),
        reason: 'a linha descreve a TENTATIVA de escrita, não uma leitura',
      );
      expect(audit.events.map((e) => e.result), everyElement('denied'));
    });
  });

  group('resetAcsMfa', () {
    test('zera as quatro colunas totp* e audita mfa_reset com o id DEPOIS da limpeza', () async {
      await servico.resetAcsMfa(admin, acsId: 'acs-a');

      expect(totp.limpezas, [('acs-a', DateTime.utc(2026, 10, 8, 12))]);
      expect(_ordem, [
        'store:acsById',
        'totp:clearTotp',
        'audit:write:admin_acs:mfa_reset',
      ]);
      final linha = audit.events.single;
      expect(linha.userId, 'admin-1');
      expect(linha.actionType, 'write');
      expect(linha.resourceType, 'admin_acs');
      expect(linha.result, 'mfa_reset');
      expect(linha.resourceId, 'acs-a');
    });

    test('ACS sem MFA é idempotente: a limpeza é pedida do mesmo jeito e audita mfa_reset', () async {
      // `acs-a` não tem MFA (a limpeza não acha nada a apagar): a operação
      // conclui, e o que a trilha registra é o pedido do operador.
      await servico.resetAcsMfa(coordA, acsId: 'acs-a');
      await servico.resetAcsMfa(coordA, acsId: 'acs-a');

      expect(totp.limpezas, hasLength(2));
      expect(audit.events, hasLength(2));
      expect(audit.events.map((e) => e.result), ['mfa_reset', 'mfa_reset']);
      expect(audit.events.map((e) => e.resourceId), everyElement('acs-a'));
    });

    test('ACS inexistente e ACS de outra UBS → mesma recusa auditada, nada limpo', () async {
      final casos = <(AuthenticatedUser, String)>[
        (admin, 'acs-inexistente'),
        (coordA, 'acs-b'),
      ];
      for (final (operador, acsId) in casos) {
        await expectLater(
          servico.resetAcsMfa(operador, acsId: acsId),
          throwsA(
            isA<AdminInvalidRequestException>().having(
              (e) => e.message,
              'message',
              'ACS não encontrado.',
            ),
          ),
        );
      }
      expect(totp.limpezas, isEmpty, reason: 'a MFA de um alvo fora do escopo fica como está');
      expect(audit.events, hasLength(casos.length));
      expect(audit.events.map((e) => e.actionType), everyElement('write'));
      expect(audit.events.map((e) => e.result), everyElement('denied'));
    });

    test('papel fora do backoffice e coordenador sem UBS recebem recusa auditada', () async {
      for (final usuario in [
        _u('u-acs', UserRole.acs),
        _u('u-paciente', UserRole.patient),
        coordSemUbs,
      ]) {
        await expectLater(
          servico.resetAcsMfa(usuario, acsId: 'acs-a'),
          throwsA(isA<AlertPermissionException>()),
        );
      }
      expect(store.chamadas, 0);
      expect(audit.events, hasLength(3));
      expect(audit.events.map((e) => e.actionType), everyElement('write'));
      expect(audit.events.map((e) => e.result), everyElement('denied'));
    });
  });

  group('resetStaffMfa do staff', () {
    test(
      'admin redefine: código novo de 24 h, só o SHA-256 gravado, issuedBy do ator e trilha mfa_reset DEPOIS do commit',
      () async {
        final resultado = await servico.resetStaffMfa(admin, staffId: 'coord-a');

        expect(
          resultado.activationCode,
          matches(RegExp(r'^[A-Z2-7]{4}(-[A-Z2-7]{4}){5}-[A-Z2-7]{2}$')),
          reason: 'o mesmo formato do código da CLI (#48): 130 bits em grupos de 4',
        );
        final gravado = store.resetsDoStaff.single;
        expect(gravado.staffId, 'coord-a');
        expect(
          gravado.issuedBy,
          'admin-1',
          reason: 'a coluna guarda o UUID do ator; o rótulo humano vem da linha de auditoria',
        );
        expect(gravado.at, DateTime.utc(2026, 10, 8, 12));
        expect(
          gravado.expiresAt,
          DateTime.utc(2026, 10, 8, 12).add(const Duration(hours: 24)),
          reason: 'a validade é a do código da CLI (`StaffActivationCode.defaultValidity`)',
        );
        expect(resultado.activationCodeExpiresAt, gravado.expiresAt);
        expect(
          StaffActivationCode.matches(resultado.activationCode, gravado.codeHash),
          isTrue,
          reason: 'o código devolvido é o único que casa com o hash gravado',
        );
        expect(
          gravado.codeHash,
          isNot(contains(resultado.activationCode)),
          reason: 'o código em claro não existe no servidor: só o SHA-256 chega ao store',
        );
        expect(
          resultado.activationCode,
          isNot(gravado.codeHash),
          reason: 'nem o próprio hash é o código: a resposta devolve o valor sorteado',
        );

        expect(_ordem, [
          'store:staffById',
          'store:resetStaffMfa',
          'audit:write:admin_staff:mfa_reset',
        ]);
        final linha = audit.events.single;
        expect(linha.userId, 'admin-1');
        expect(linha.actionType, 'write');
        expect(linha.resourceType, 'admin_staff');
        expect(linha.result, 'mfa_reset');
        expect(linha.resourceId, 'coord-a');
      },
    );

    test('cada pedido emite um código novo: o anterior deixa de valer', () async {
      final primeiro = await servico.resetStaffMfa(admin, staffId: 'coord-a');
      final segundo = await servico.resetStaffMfa(admin, staffId: 'coord-a');

      expect(segundo.activationCode, isNot(primeiro.activationCode));
      expect(store.resetsDoStaff, hasLength(2));
      expect(store.resetsDoStaff.map((r) => r.codeHash).toSet(), hasLength(2));
      expect(
        StaffActivationCode.matches(segundo.activationCode, store.resetsDoStaff.last.codeHash),
        isTrue,
      );
    });

    test(
      'só o administrador redefine a MFA do staff: o coordenador é recusado, inclusive para a própria conta',
      () async {
        for (final alvo in ['coord-a', 'coord-sem-ubs']) {
          await expectLater(
            servico.resetStaffMfa(coordA, staffId: alvo),
            throwsA(isA<AlertPermissionException>()),
          );
        }
        expect(store.chamadas, 0, reason: 'nem o alvo é lido: a recusa é de papel');
        expect(ativacoes.emissoes, isEmpty);
        expect(store.resetsDoStaff, isEmpty);
        expect(audit.events, hasLength(2));
        expect(audit.events.map((e) => e.actionType), everyElement('write'));
        expect(audit.events.map((e) => e.resourceType), everyElement('admin_staff'));
        expect(audit.events.map((e) => e.result), everyElement('denied'));
        expect(audit.events.map((e) => e.userId), everyElement('coord-a'));
      },
    );

    test('papel fora do backoffice é recusado com a mesma trilha denied', () async {
      for (final usuario in [
        _u('u-acs', UserRole.acs),
        _u('u-paciente', UserRole.patient),
      ]) {
        await expectLater(
          servico.resetStaffMfa(usuario, staffId: 'coord-a'),
          throwsA(isA<AlertPermissionException>()),
        );
      }
      expect(store.chamadas, 0);
      expect(audit.events, hasLength(2));
      expect(audit.events.map((e) => e.actionType), everyElement('write'));
      expect(audit.events.map((e) => e.result), everyElement('denied'));
    });

    test('uma conta não redefine a própria MFA: pede a outro administrador', () async {
      await expectLater(
        servico.resetStaffMfa(admin, staffId: 'admin-1'),
        throwsA(
          isA<AdminInvalidRequestException>().having(
            (e) => e.message,
            'message',
            'Uma conta não redefine a própria MFA: peça a outro administrador.',
          ),
        ),
      );
      expect(
        store.chamadas,
        0,
        reason: 'a recusa é do chamador sobre si mesmo: nem o alvo é lido',
      );
      expect(store.resetsDoStaff, isEmpty);
      expect(audit.events.single.result, 'denied');
      expect(audit.events.single.actionType, 'write');
      expect(audit.events.single.resourceType, 'admin_staff');
      expect(audit.events.single.userId, 'admin-1');
    });

    test(
      'a própria conta com o id em maiúsculas também é recusada: a comparação é canônica',
      () async {
        // `UuidValue` e o `::uuid` do Postgres normalizam a caixa; a comparação
        // ingênua de strings, não — e o administrador que manda o próprio id
        // com uma letra maiúscula redefiniria a própria MFA, exatamente o que a
        // decisão 9.4 do plano proíbe.
        const meuId = '00000000-0000-4000-8000-00000000ab01';
        final eu = _u(meuId, UserRole.admin);

        await expectLater(
          servico.resetStaffMfa(eu, staffId: meuId.toUpperCase()),
          throwsA(
            isA<AdminInvalidRequestException>().having(
              (e) => e.message,
              'message',
              'Uma conta não redefine a própria MFA: peça a outro administrador.',
            ),
          ),
        );
        expect(store.chamadas, 0, reason: 'a recusa vem antes de ler o alvo');
        expect(store.resetsDoStaff, isEmpty);
        expect(audit.events.single.result, 'denied');
        expect(audit.events.single.userId, meuId);
      },
    );

    test('o alvo é normalizado: o store e a trilha recebem o id canônico', () async {
      // O alvo chega com letra maiúscula e sai em minúsculas: duas linhas de
      // auditoria do mesmo alvo não podem parecer dois alvos diferentes.
      final resultado = await servico.resetStaffMfa(
        admin,
        staffId: _uuidDoCoordenador.toUpperCase(),
      );

      expect(store.resetsDoStaff.single.staffId, _uuidDoCoordenador);
      expect(audit.events.single.resourceId, _uuidDoCoordenador);
      expect(
        StaffActivationCode.matches(
          resultado.activationCode,
          store.resetsDoStaff.single.codeHash,
        ),
        isTrue,
      );
    });

    test(
      'alvo inexistente e conta inativa recebem a mesma recusa auditada, sem emissão',
      () async {
        final casos = ['staff-inexistente', 'staff-inativo'];
      for (final staffId in casos) {
        await expectLater(
          servico.resetStaffMfa(admin, staffId: staffId),
          throwsA(
            isA<AdminInvalidRequestException>().having(
              (e) => e.message,
              'message',
              'Conta de equipe não encontrada.',
            ),
          ),
        );
      }
      expect(
        store.resetsDoStaff,
        isEmpty,
        reason: 'nem o código é sorteado para um alvo que não pode entrar',
      );
      expect(audit.events, hasLength(casos.length));
      expect(audit.events.map((e) => e.result), everyElement('denied'));
      expect(audit.events.map((e) => e.resourceType), everyElement('admin_staff'));
    });

    test(
      'corrida: o alvo sai do ar entre a checagem e a transação → mesma recusa, nada emitido',
      () async {
        // A pré-checagem acha a conta; o `WHERE` da transação (existência e
        // `active`) não. O desfecho é o de "não existe", e a trilha não mente
        // dizendo que a MFA foi redefinida.
        store.corridaDeResetStaff = true;

        await expectLater(
          servico.resetStaffMfa(admin, staffId: 'coord-a'),
          throwsA(
            isA<AdminInvalidRequestException>().having(
              (e) => e.message,
              'message',
              'Conta de equipe não encontrada.',
            ),
          ),
        );
        expect(store.resetsDoStaff, isEmpty);
        expect(audit.events.single.result, 'denied');
      },
    );
  });

  group('AcsInitialPassword', () {
    test('generate: 16 caracteres do alfabeto, em 4 grupos de 4', () {
      final senha = AcsInitialPassword.generate(Random(1));
      expect(senha, hasLength(19), reason: '16 caracteres e 3 hífens');
      expect(
        senha,
        matches(
          RegExp(
            r'^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{4}'
            r'(-[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{4}){3}$',
          ),
        ),
      );
      expect(
        senha,
        isNot(contains(RegExp('[01ILO]'))),
        reason: 'o alfabeto exclui os caracteres que se confundem ao ler e ao digitar',
      );
    });

    test('generate: dois sorteios diferem', () {
      expect(
        AcsInitialPassword.generate(Random(1)),
        isNot(AcsInitialPassword.generate(Random(2))),
      );
      final semSemente = {for (var i = 0; i < 8; i++) AcsInitialPassword.generate()};
      expect(semSemente, hasLength(8), reason: 'sem semente, o sorteio é `Random.secure()`');
    });
  });
}
