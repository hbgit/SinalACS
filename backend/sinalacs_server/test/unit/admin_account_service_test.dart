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

  /// Matrículas já cadastradas (a pré-checagem do serviço).
  final matriculas = <String>{};

  /// `true` = a pré-checagem passou e o índice único do banco disparou
  /// (`insertAcs` devolve `null`): a corrida que o catch de 23505 fecha.
  bool corridaDeMatricula = false;

  int insertAcsChamadas = 0;
  String? ultimaUbs;
  String? ultimaMicroArea;
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
