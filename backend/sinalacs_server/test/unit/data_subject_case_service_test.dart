import 'package:sinalacs_server/src/application/admin/admin_read_service.dart';
import 'package:sinalacs_server/src/application/admin/data_subject_case_service.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:test/test.dart';

/// Regras do atendimento de pedidos do titular (#42) sem banco: papel, escopo
/// por UBS, auditoria antes do dado, transições e validação de nota. Dados
/// sintéticos; o store é um falso em memória.
const _ubsA = 'ubs-a';
const _agora = '2026-10-08T12:00:00Z';

final _ordem = <String>[];

class _Pedido {
  _Pedido(this.ubs, this.detalhe);
  final String ubs;
  AdminDataSubjectRequestDetail detalhe;
}

class _DecisaoChamada {
  _DecisaoChamada({
    required this.id,
    required this.from,
    required this.to,
    required this.resolution,
    required this.decidedBy,
    required this.anonymize,
    required this.audit,
  });
  final String id;
  final Set<DataSubjectRequestStatus> from;
  final DataSubjectRequestStatus to;
  final String? resolution;
  final String decidedBy;
  final bool anonymize;
  final AuditEvent audit;
}

class _Store implements DataSubjectCaseStore {
  final Map<String, String?> ubs = {'coord-a': _ubsA, 'coord-sem-ubs': null};
  final Map<String, _Pedido> pedidos = {};
  final decisoes = <_DecisaoChamada>[];
  AdminScope? ultimoEscopo;
  bool decideDevolve = true;
  bool decideForaDoEscopo = false;
  StateError? decideLanca;
  int chamadas = 0;

  @override
  Future<String?> ubsOf(String staffId) async => ubs[staffId];

  @override
  Future<String?> subjectOf(String requestId) async => 'titular-$requestId';

  @override
  Future<AdminDataSubjectRequestPage> list(
    AdminScope scope, {
    DataSubjectRequestStatus? status,
    required int limit,
    required int offset,
    required DateTime now,
  }) async {
    chamadas++;
    ultimoEscopo = scope;
    _ordem.add('store:list');
    return AdminDataSubjectRequestPage(
      items: [
        for (final p in pedidos.values)
          if (scope.ubsId == null || scope.ubsId == p.ubs)
            AdminDataSubjectRequest(
              id: p.detalhe.id,
              type: p.detalhe.type,
              status: p.detalhe.status,
              createdAt: p.detalhe.createdAt,
              dueAt: p.detalhe.dueAt,
              overdue: false,
              patientLabel: p.detalhe.patientLabel,
            ),
      ],
    );
  }

  @override
  Future<AdminDataSubjectRequestDetail?> find(
    AdminScope scope,
    String id, {
    required DateTime now,
  }) async {
    chamadas++;
    ultimoEscopo = scope;
    _ordem.add('store:find');
    final p = pedidos[id];
    if (p == null) return null;
    if (scope.ubsId != null && scope.ubsId != p.ubs) return null;
    return p.detalhe;
  }

  @override
  Future<bool> decide(
    AdminScope scope,
    String id, {
    required Set<DataSubjectRequestStatus> from,
    required DataSubjectRequestStatus to,
    required String? resolution,
    required String decidedBy,
    required bool anonymize,
    required AuditEvent audit,
    required DateTime now,
  }) async {
    _ordem.add('store:decide');
    if (decideLanca != null) throw decideLanca!;
    // Simula o pedido que saiu do escopo entre o find e o decide.
    if (decideForaDoEscopo) return false;
    decisoes.add(
      _DecisaoChamada(
        id: id,
        from: from,
        to: to,
        resolution: resolution,
        decidedBy: decidedBy,
        anonymize: anonymize,
        audit: audit,
      ),
    );
    final p = pedidos[id];
    if (!decideDevolve || p == null || !from.contains(p.detalhe.status)) {
      return false;
    }
    final d = p.detalhe;
    p.detalhe = AdminDataSubjectRequestDetail(
      id: d.id,
      type: d.type,
      status: to,
      createdAt: d.createdAt,
      dueAt: d.dueAt,
      overdue: d.overdue,
      patientLabel: d.patientLabel,
      details: d.details,
      resolution: resolution,
    );
    return true;
  }
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

class _Notificador implements DataSubjectNotifier {
  final chamadas = <(String, DataSubjectRequestStatus)>[];
  Object? lanca;

  @override
  Future<void> decided(String userId, DataSubjectRequestStatus status) async {
    chamadas.add((userId, status));
    if (lanca != null) throw lanca!;
  }
}

AuthenticatedUser _u(String id, UserRole role) => AuthenticatedUser(
  id: id,
  role: role,
  microAreaId: null,
  deviceId: 'sem-aparelho',
);

AdminDataSubjectRequestDetail _detalhe(
  String id, {
  DataSubjectRequestType type = DataSubjectRequestType.deletion,
  DataSubjectRequestStatus status = DataSubjectRequestStatus.open,
  DateTime? dueAt,
}) => AdminDataSubjectRequestDetail(
  id: id,
  type: type,
  status: status,
  createdAt: DateTime.utc(2026, 9, 30),
  dueAt: dueAt ?? DateTime.utc(2026, 10, 15),
  overdue: false,
  patientLabel: '#A18F',
  details: type == DataSubjectRequestType.correction
      ? 'texto sintético do pedido'
      : null,
);

void main() {
  late _Store store;
  late _Audit audit;
  late DataSubjectCaseService servico;
  final agora = DateTime.parse(_agora);
  final admin = _u('admin-1', UserRole.admin);
  final coordA = _u('coord-a', UserRole.coordinator);
  final coordB = _u('coord-b', UserRole.coordinator);
  final coordSemUbs = _u('coord-sem-ubs', UserRole.coordinator);

  setUp(() {
    _ordem.clear();
    store = _Store()..ubs['coord-b'] = 'ubs-b';
    audit = _Audit();
    servico = DataSubjectCaseService(
      store: store,
      audit: audit,
      clock: () => agora,
    );
    store.pedidos['del-1'] = _Pedido(_ubsA, _detalhe('del-1'));
    store.pedidos['cor-1'] = _Pedido(
      _ubsA,
      _detalhe('cor-1', type: DataSubjectRequestType.correction),
    );
  });

  test('acs e patient são recusados e a recusa é auditada', () async {
    for (final papel in [UserRole.acs, UserRole.patient]) {
      final u = _u('u-${papel.name}', papel);
      audit.events.clear();
      for (final chamada in <Future<Object?> Function()>[
        () => servico.list(u),
        () => servico.get(u, 'del-1'),
        () => servico.startReview(u, 'del-1'),
        () => servico.complete(u, 'del-1'),
        () => servico.reject(u, 'del-1', reason: 'motivo válido'),
      ]) {
        await expectLater(chamada(), throwsA(isA<AlertPermissionException>()));
      }
      expect(audit.events, hasLength(5));
      expect(audit.events.every((e) => e.result == 'denied'), isTrue);
    }
    expect(store.chamadas, 0);
    expect(store.decisoes, isEmpty);
  });

  test('coordenador sem UBS é recusado em todos os métodos', () async {
    for (final chamada in <Future<Object?> Function()>[
      () => servico.list(coordSemUbs),
      () => servico.get(coordSemUbs, 'del-1'),
      () => servico.startReview(coordSemUbs, 'del-1'),
      () => servico.complete(coordSemUbs, 'del-1'),
      () => servico.reject(coordSemUbs, 'del-1', reason: 'motivo válido'),
    ]) {
      await expectLater(chamada(), throwsA(isA<AlertPermissionException>()));
    }
    expect(audit.events, hasLength(5));
    expect(audit.events.every((e) => e.result == 'denied'), isTrue);
    expect(store.chamadas, 0);
    expect(store.decisoes, isEmpty);
  });

  test(
    'coordenador de outra UBS recebe "não encontrado", igual a id inexistente',
    () async {
      Future<String> mensagem(Future<Object?> Function() chamada) async {
        try {
          await chamada();
        } on AdminInvalidRequestException catch (e) {
          return e.message;
        }
        fail('deveria ter lançado AdminInvalidRequestException');
      }

      final outraUbs = await mensagem(() => servico.get(coordB, 'del-1'));
      final inexistente = await mensagem(() => servico.get(coordB, 'nada'));
      expect(outraUbs, inexistente);

      final decOutra = await mensagem(
        () => servico.startReview(coordB, 'del-1'),
      );
      final decNada = await mensagem(() => servico.startReview(coordB, 'nada'));
      expect(decOutra, decNada);
      expect(store.decisoes, isEmpty);
      expect(
        store.pedidos['del-1']!.detalhe.status,
        DataSubjectRequestStatus.open,
      );
    },
  );

  test(
    'get audita read ANTES de devolver o dado, e falha de auditoria impede a leitura',
    () async {
      final d = await servico.get(coordA, 'cor-1');
      expect(d.details, 'texto sintético do pedido');
      expect(store.ultimoEscopo!.ubsId, _ubsA);
      expect(_ordem, [
        'audit:admin_data_subject_requests:success',
        'store:find',
      ]);
      expect(audit.events.single.actionType, 'read');
      expect(audit.events.single.resourceId, 'cor-1');

      _ordem.clear();
      store.chamadas = 0;
      audit.falhar = true;
      await expectLater(
        servico.get(coordA, 'cor-1'),
        throwsA(isA<StateError>()),
      );
      await expectLater(servico.list(coordA), throwsA(isA<StateError>()));
      expect(store.chamadas, 0);
    },
  );

  test('overdue só para open/inReview com now > dueAt', () async {
    store.pedidos.clear();
    store.pedidos['a'] = _Pedido(
      _ubsA,
      _detalhe('a', dueAt: agora.subtract(const Duration(seconds: 1))),
    );
    store.pedidos['b'] = _Pedido(
      _ubsA,
      _detalhe(
        'b',
        status: DataSubjectRequestStatus.completed,
        dueAt: agora.subtract(const Duration(days: 3)),
      ),
    );
    store.pedidos['c'] = _Pedido(_ubsA, _detalhe('c', dueAt: agora));
    store.pedidos['d'] = _Pedido(
      _ubsA,
      _detalhe(
        'd',
        status: DataSubjectRequestStatus.inReview,
        dueAt: agora.subtract(const Duration(days: 1)),
      ),
    );

    final pagina = await servico.list(admin);
    final porId = {for (final i in pagina.items) i.id: i.overdue};
    expect(porId, {'a': true, 'b': false, 'c': false, 'd': true});

    expect((await servico.get(admin, 'a')).overdue, isTrue);
    expect((await servico.get(admin, 'b')).overdue, isFalse);
    expect((await servico.get(admin, 'c')).overdue, isFalse);
  });

  test(
    'startReview: open→inReview; repetir devolve erro de transição',
    () async {
      await servico.startReview(coordA, 'del-1');
      expect(
        store.pedidos['del-1']!.detalhe.status,
        DataSubjectRequestStatus.inReview,
      );
      final c = store.decisoes.single;
      expect(c.from, {DataSubjectRequestStatus.open});
      expect(c.to, DataSubjectRequestStatus.inReview);
      expect(c.decidedBy, 'coord-a');
      expect(c.anonymize, isFalse);
      expect(c.audit.actionType, 'write');
      expect(c.audit.resourceType, 'data_subject_request');
      expect(c.audit.resourceId, 'del-1');
      expect(c.audit.result, 'in_review');

      final antes = store.decisoes.length;
      await expectLater(
        servico.startReview(coordA, 'del-1'),
        throwsA(isA<AdminInvalidRequestException>()),
      );
      expect(store.decisoes.length, antes); // nem chega a travar o pedido
    },
  );

  test(
    'complete de correção sem nota é recusado; com nota de 501 caracteres também',
    () async {
      await expectLater(
        servico.complete(coordA, 'cor-1'),
        throwsA(isA<AdminInvalidRequestException>()),
      );
      await expectLater(
        servico.complete(coordA, 'cor-1', note: '   '),
        throwsA(isA<AdminInvalidRequestException>()),
      );
      await expectLater(
        servico.complete(coordA, 'cor-1', note: 'x' * 501),
        throwsA(isA<AdminInvalidRequestException>()),
      );
      expect(store.decisoes, isEmpty);

      await servico.complete(coordA, 'cor-1', note: '  Dado corrigido.  ');
      expect(store.decisoes.single.resolution, 'Dado corrigido.');
      expect(store.decisoes.single.audit.result, 'completed');
    },
  );

  test(
    'complete de exclusão chama decide(anonymize: true); de correção, anonymize: false',
    () async {
      await servico.complete(coordA, 'del-1');
      final del = store.decisoes.single;
      expect(del.anonymize, isTrue);
      expect(del.to, DataSubjectRequestStatus.completed);
      expect(del.from, {
        DataSubjectRequestStatus.open,
        DataSubjectRequestStatus.inReview,
      });
      expect(del.resolution, isNull);

      await servico.complete(
        coordA,
        'cor-1',
        note: 'Corrigido conforme pedido.',
      );
      expect(store.decisoes.last.anonymize, isFalse);

      // reject nunca anonimiza, nem em pedido de exclusão.
      store.pedidos['del-2'] = _Pedido(_ubsA, _detalhe('del-2'));
      await servico.reject(
        coordA,
        'del-2',
        reason: 'Titular não identificado.',
      );
      expect(store.decisoes.last.anonymize, isFalse);
      expect(store.decisoes.last.audit.result, 'rejected');
    },
  );

  test('reject exige motivo de 3 a 500 caracteres após trim', () async {
    for (final ruim in ['', '  ', 'ab', '  ab  ', 'x' * 501]) {
      await expectLater(
        servico.reject(coordA, 'del-1', reason: ruim),
        throwsA(isA<AdminInvalidRequestException>()),
      );
    }
    expect(store.decisoes, isEmpty);

    await servico.reject(coordA, 'del-1', reason: '  abc  ');
    expect(store.decisoes.single.resolution, 'abc');

    store.pedidos['del-3'] = _Pedido(_ubsA, _detalhe('del-3'));
    await servico.reject(coordA, 'del-3', reason: 'x' * 500);
    expect(store.decisoes.last.resolution, hasLength(500));
  });

  test(
    'decide devolvendo false vira erro de transição inválida e não audita sucesso',
    () async {
      store.decideDevolve = false;
      await expectLater(
        servico.complete(coordA, 'del-1'),
        throwsA(isA<AdminInvalidRequestException>()),
      );
      await expectLater(
        servico.startReview(coordA, 'del-1'),
        throwsA(isA<AdminInvalidRequestException>()),
      );
      // a auditoria de sucesso viaja dentro de decide (mesma transação); o
      // serviço nunca a grava por fora.
      expect(audit.events.where((e) => e.result != 'denied'), isEmpty);
      expect(
        store.pedidos['del-1']!.detalhe.status,
        DataSubjectRequestStatus.open,
      );
    },
  );

  test(
    'corrida perdida (decide == false) dá mensagem neutra: não fala de estado e '
    'é a mesma para pedido que existe e para pedido que sumiu do escopo',
    () async {
      Future<String> mensagem(Future<Object?> Function() chamada) async {
        try {
          await chamada();
        } on AdminInvalidRequestException catch (e) {
          return e.message;
        }
        fail('deveria ter lançado AdminInvalidRequestException');
      }

      // Pedido no escopo, outro analista decidiu entre o find e o lock.
      store.decideDevolve = false;
      final corrida = await mensagem(() => servico.complete(coordA, 'del-1'));
      // Pedido que o find viu, mas que saiu do escopo antes do decide (o store
      // devolve false para fora do escopo): mesma mensagem.
      store.decideDevolve = true;
      store.decideForaDoEscopo = true;
      final foraDoEscopo = await mensagem(
        () => servico.startReview(coordA, 'del-1'),
      );
      expect(corrida, foraDoEscopo);
      expect(corrida, isNot(contains('estado')));
      // A mensagem de estado inválido segue existindo só para quem viu o
      // pedido (find) num estado final.
      store.pedidos['del-9'] = _Pedido(
        _ubsA,
        _detalhe('del-9', status: DataSubjectRequestStatus.completed),
      );
      store.decideForaDoEscopo = false;
      final finalizado = await mensagem(
        () => servico.complete(coordA, 'del-9'),
      );
      expect(finalizado, isNot(corrida));
    },
  );

  test(
    'StateError do store (dado inconsistente) vira AdminInvalidRequestException '
    'genérica, sem o texto do erro',
    () async {
      store.decideLanca = StateError(
        'titular do pedido de exclusão não é paciente',
      );
      try {
        await servico.complete(coordA, 'del-1');
        fail('deveria recusar');
      } on AdminInvalidRequestException catch (e) {
        expect(e.message, isNot(contains('paciente')));
        expect(e.message, isNot(contains('titular')));
      }
      expect(audit.events.where((e) => e.result != 'denied'), isEmpty);
    },
  );

  test('nota nunca aparece na mensagem de exceção nem no AuditEvent', () async {
    const segredo = 'SEGREDO-sintetico-xyz';
    // exceção de validação (nota longa demais contendo o segredo)
    try {
      await servico.complete(coordA, 'cor-1', note: segredo * 40);
      fail('deveria recusar');
    } on AdminInvalidRequestException catch (e) {
      expect(e.message, isNot(contains(segredo)));
    }
    // exceção de transição (decide devolve false)
    store.decideDevolve = false;
    try {
      await servico.reject(coordA, 'del-1', reason: 'motivo $segredo');
      fail('deveria recusar');
    } on AdminInvalidRequestException catch (e) {
      expect(e.message, isNot(contains(segredo)));
    }
    // evento de auditoria da decisão e os gravados pelo serviço
    final evento = store.decisoes.single.audit;
    for (final e in [evento, ...audit.events]) {
      expect(
        '${e.userId}|${e.actionType}|${e.resourceType}|${e.resourceId}|${e.result}',
        isNot(contains(segredo)),
      );
    }
  });

  group('aviso', () {
    late _Notificador notificador;
    late DataSubjectCaseService comAviso;

    setUp(() {
      notificador = _Notificador();
      comAviso = DataSubjectCaseService(
        store: store,
        audit: audit,
        clock: () => agora,
        notifier: notificador,
      );
    });

    test('correção atendida chama decided uma vez, depois do commit', () async {
      await comAviso.complete(coordA, 'cor-1', note: 'Dado corrigido.');
      expect(notificador.chamadas, [
        ('titular-cor-1', DataSubjectRequestStatus.completed),
      ]);
    });

    test('recusa chama decided com rejected', () async {
      await comAviso.reject(coordA, 'del-1', reason: 'Pedido sem fundamento.');
      expect(notificador.chamadas, [
        ('titular-del-1', DataSubjectRequestStatus.rejected),
      ]);
    });

    test('exclusão atendida e início de análise não chamam decided', () async {
      await comAviso.startReview(coordA, 'cor-1');
      await comAviso.complete(coordA, 'del-1');
      expect(notificador.chamadas, isEmpty);
    });

    test('decisão perdida (decide false) não avisa', () async {
      store.decideDevolve = false;
      await expectLater(
        comAviso.complete(coordA, 'cor-1', note: 'Dado corrigido.'),
        throwsA(isA<AdminInvalidRequestException>()),
      );
      expect(notificador.chamadas, isEmpty);
    });

    test('decided lançando erro não altera o resultado de complete', () async {
      notificador.lanca = StateError('relé fora do ar');
      await comAviso.complete(coordA, 'cor-1', note: 'Dado corrigido.');
      expect(
        store.pedidos['cor-1']!.detalhe.status,
        DataSubjectRequestStatus.completed,
      );
      await comAviso.reject(coordA, 'del-1', reason: 'Pedido sem fundamento.');
      expect(
        store.pedidos['del-1']!.detalhe.status,
        DataSubjectRequestStatus.rejected,
      );
    });
  });
}
