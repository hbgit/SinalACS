import 'dart:math';

import 'package:sinalacs_server/src/application/admin/admin_account_service.dart';
import 'package:sinalacs_server/src/application/admin/initial_password.dart';
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
  late AdminAccountService servico;
  final admin = _u('admin-1', UserRole.admin);
  final coordA = _u('coord-a', UserRole.coordinator);
  final coordSemUbs = _u('coord-sem-ubs', UserRole.coordinator);

  setUp(() {
    _ordem.clear();
    store = _Store();
    audit = _Audit();
    hasher = _Hasher();
    servico = AdminAccountService(
      store: store,
      credentials: _NaoUsado(),
      totpStore: _NaoUsado(),
      activationStore: _NaoUsado(),
      refreshStore: _NaoUsado(),
      uploadStore: _NaoUsado(),
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
