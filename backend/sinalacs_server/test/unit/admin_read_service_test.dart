import 'package:sinalacs_server/src/application/admin/admin_read_service.dart';
import 'package:sinalacs_server/src/application/audit/audit_chain.dart';
import 'package:sinalacs_server/src/application/audit/audit_chain_verifier.dart';
import 'package:sinalacs_server/src/application/audit/audit_row_sealer.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_admin_read_store.dart'
    show escaparLike;
import 'package:test/test.dart';

/// Regras do backoffice (#40) sem banco: papel, escopo, auditoria que vem ANTES
/// do dado e validação de paginação. Dados sintéticos.
const _ubsDoCoordenador = 'ubs-a';
const _segredoDaCadeia = 'segredo-sintetico-do-servico';

/// Linha de auditoria como o store a devolve: [integridadeDoStore] é o que o
/// store pôs no `entry` (o serviço tem de ignorar), e a cadeia é montada com
/// [segredo].
AdminAuditRow _linha(
  int sequence, {
  required String previousHash,
  String? previousEntryHash,
  String segredo = _segredoDaCadeia,
  AuditRowSeal integridadeDoStore = AuditRowSeal.unverifiable,
}) {
  final campos = AuditChainFields(
    sequence: sequence,
    previousHash: previousHash,
    userId: 'u-$sequence',
    actionType: 'read',
    resourceType: 'admin_audit_logs',
    resourceId: null,
    timestamp: DateTime.utc(2026, 10, 13, 12, sequence),
    ipHash: 'ip-$sequence',
    result: 'success',
  );
  return AdminAuditRow(
    entry: AdminAuditEntry(
      id: 'id-$sequence',
      sequence: sequence,
      userLabel: 'X (Administrador)',
      actionType: 'read',
      resourceType: 'admin_audit_logs',
      timestamp: campos.timestamp,
      result: 'success',
      integrity: integridadeDoStore,
    ),
    seal: AuditSealInput(
      row: AuditChainEntry(
        fields: campos,
        entryHash: AuditChain(secret: segredo).computeEntryHash(campos),
      ),
      previousEntryHash: previousEntryHash,
    ),
  );
}

/// Registra cada chamada com a ordem global, para provar "auditoria antes do dado".
final _ordem = <String>[];

class _Store implements AdminReadStore {
  AdminScope? ultimoEscopo;
  int chamadas = 0;
  int? ultimoLimit;
  AdminAuditFilter? ultimoFiltro;
  List<AdminAuditRow> proximaPagina = [];
  int? proximoCursor;
  DateTime? ultimoAgoraDosAlertas;
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
      resolvedRedAlerts: 0,
      tmravSeconds: null,
    );
  }

  /// O pulso (D5) é do `AdminMonitoringService`; o serviço de leitura não o usa.
  @override
  Future<AlertsPulseCounts> pulse(
    AdminScope scope, {
    required DateTime now,
    required Duration threshold,
  }) => throw UnimplementedError();

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
    required DateTime now,
  }) async {
    _marca('alerts', scope);
    ultimoAgoraDosAlertas = now;
    ultimoLimit = limit;
    return AdminAlertPage(items: []);
  }

  @override
  Future<AdminAuditRowPage> auditLogs(
    AdminScope scope, {
    AdminAuditFilter? filter,
    required int limit,
    int? beforeSequence,
  }) async {
    _marca('auditLogs', scope);
    ultimoLimit = limit;
    ultimoFiltro = filter;
    return AdminAuditRowPage(
      items: proximaPagina,
      nextBeforeSequence: proximoCursor,
    );
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
      auditChain: AuditChain(secret: _segredoDaCadeia),
      clock: () => DateTime.utc(2026, 10, 7, 12),
    );
  });

  test(
    'alertas: o serviço passa ao store o relógio DO SERVIDOR, em UTC (vencido nunca vem do aparelho)',
    () async {
      await servico.alerts(admin);
      expect(store.ultimoAgoraDosAlertas, DateTime.utc(2026, 10, 7, 12));
      expect(store.ultimoAgoraDosAlertas!.isUtc, isTrue);
    },
  );

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

  group('selo por linha (#45, D3)', () {
    test('o serviço sela cada linha e ignora o integrity que o store pôs',
        () async {
      final l1 = _linha(1, previousHash: AuditChain.genesisHash);
      final l2 = _linha(
        2,
        previousHash: l1.seal.row.entryHash,
        previousEntryHash: l1.seal.row.entryHash,
      );
      // Store "mente" verified numa linha forjada com outro segredo.
      final forjada = _linha(
        3,
        previousHash: l2.seal.row.entryHash,
        previousEntryHash: l2.seal.row.entryHash,
        segredo: 'segredo-do-atacante',
        integridadeDoStore: AuditRowSeal.verified,
      );
      // Vizinho 9 ausente no banco.
      final orfa = _linha(10, previousHash: 'f' * 64);
      store.proximaPagina = [orfa, forjada, l2, l1];

      final pagina = await servico.auditLogs(admin);

      expect(
        {for (final e in pagina.items) e.sequence: e.integrity},
        {
          10: AuditRowSeal.unverifiable,
          3: AuditRowSeal.invalid,
          2: AuditRowSeal.verified,
          1: AuditRowSeal.verified,
        },
      );
      expect(pagina.items.map((e) => e.sequence), [10, 3, 2, 1],
          reason: 'a ordem do store (sequence desc) é preservada');
    });

    test('o cursor do store passa adiante sem mudar', () async {
      store.proximaPagina = [_linha(1, previousHash: AuditChain.genesisHash)];
      store.proximoCursor = 1;
      final pagina = await servico.auditLogs(admin, limit: 1);
      expect(pagina.nextBeforeSequence, 1);
    });
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

  group('filtro da auditoria (#45, D1/D2)', () {
    final de = DateTime.utc(2026, 10, 1);
    final invalidos = <String, AdminAuditFilter>{
      'resourceType com maiúscula': AdminAuditFilter(resourceType: 'Session'),
      'resourceType com curinga': AdminAuditFilter(resourceType: 'sess%'),
      'resourceType vazio': AdminAuditFilter(resourceType: ''),
      'resourceType com 65': AdminAuditFilter(resourceType: 'a' * 65),
      'result com espaço': AdminAuditFilter(result: 'denied x'),
      'result com %': AdminAuditFilter(result: 'escalated:%'),
      'result com ;': AdminAuditFilter(result: 'denied;drop'),
      'result com maiúscula': AdminAuditFilter(result: 'Escalated:no_ack'),
      'resourceType com espaço': AdminAuditFilter(resourceType: 'admin alert'),
      'resourceType com ;': AdminAuditFilter(resourceType: 'alert;'),
      'result com aspas': AdminAuditFilter(result: "x' OR '1'='1"),
      'actionType desconhecida': AdminAuditFilter(actionType: 'delete'),
      'from == to': AdminAuditFilter(from: de, to: de),
      'from > to': AdminAuditFilter(
        from: de,
        to: de.subtract(const Duration(seconds: 1)),
      ),
      'janela de 366 d + 1 µs': AdminAuditFilter(
        from: de,
        to: de.add(const Duration(days: 366, microseconds: 1)),
      ),
      'busca com 1': AdminAuditFilter(search: 'a'),
      'busca vazia': AdminAuditFilter(search: ''),
      'busca com 65': AdminAuditFilter(search: 'a' * 65),
      'matrícula com 33': AdminAuditFilter(actorEnrollmentId: 'A' * 33),
      'matrícula vazia': AdminAuditFilter(actorEnrollmentId: ''),
    };

    for (final MapEntry(key: caso, value: filtro) in invalidos.entries) {
      test(
        'inválido ($caso) ⇒ AdminInvalidRequestException, sem auditoria e sem store',
        () async {
          await expectLater(
            servico.auditLogs(admin, filter: filtro),
            throwsA(
              isA<AdminInvalidRequestException>().having(
                (e) => e.message,
                'message',
                startsWith('Filtro de auditoria inválido.'),
              ),
            ),
          );
          expect(
            audit.events,
            isEmpty,
            reason: 'entrada inválida não é acesso',
          );
          expect(store.chamadas, 0);
        },
      );
    }

    test('a mensagem de recusa nunca ecoa o valor recebido', () async {
      const valor = "zz' OR 1=1 --";
      await expectLater(
        servico.auditLogs(admin, filter: AdminAuditFilter(result: valor)),
        throwsA(
          isA<AdminInvalidRequestException>().having(
            (e) => e.message,
            'message',
            isNot(contains(valor)),
          ),
        ),
      );
    });

    test(
      'acs com filtro inválido continua recusado por papel (denied auditado)',
      () async {
        await expectLater(
          servico.auditLogs(
            _u('acs-1', UserRole.acs),
            filter: AdminAuditFilter(search: 'a'),
          ),
          throwsA(isA<AlertPermissionException>()),
        );
        expect(audit.events.single.result, 'denied');
      },
    );

    test(
      'válido ⇒ audita success ANTES do store e repassa o filtro intacto',
      () async {
        final filtro = AdminAuditFilter(
          actorEnrollmentId: 'ACS-0001',
          actorRole: UserRole.acs,
          actionType: 'export',
          resourceType: 'admin_audit_logs',
          result: 'denied_territory',
          from: de,
          to: de.add(const Duration(days: 366)),
          search: '%_',
        );
        await servico.auditLogs(coordA, filter: filtro, limit: 20);
        expect(_ordem, ['audit:admin_audit_logs:success', 'store:auditLogs']);
        expect(store.ultimoFiltro, same(filtro));
        expect(store.ultimoLimit, 20);
        expect(store.ultimoEscopo!.ubsId, _ubsDoCoordenador);
      },
    );

    test(
      'resourceType/result aceitam dígito e ":" (ex.: escalated:no_ack_timeout)',
      () async {
        final f = AdminAuditFilter(
          resourceType: 'admin_alert',
          result: 'escalated:no_ack_timeout',
        );
        await servico.auditLogs(admin, filter: f);
        expect(store.ultimoFiltro, same(f));
        await servico.auditLogs(
          admin,
          filter: AdminAuditFilter(result: 'already_escalated:x1'),
        );
        expect(store.chamadas, 2);
      },
    );

    test('só from, só to e busca com 2 e 64 passam', () async {
      for (final f in [
        AdminAuditFilter(from: de),
        AdminAuditFilter(to: de),
        AdminAuditFilter(search: 'ab'),
        AdminAuditFilter(search: 'a' * 64),
        AdminAuditFilter(actorEnrollmentId: 'A' * 32),
        AdminAuditFilter(resourceType: 'a' * 64),
      ]) {
        await servico.auditLogs(admin, filter: f);
      }
      expect(store.chamadas, 6);
    });
  });

  group('escaparLike', () {
    test('escapa \\, % e _ (a barra primeiro)', () {
      expect(escaparLike('%'), r'\%');
      expect(escaparLike('_'), r'\_');
      expect(escaparLike(r'\'), r'\\');
      expect(escaparLike(r'a\%_b'), r'a\\\%\_b');
      expect(escaparLike('admin'), 'admin');
      expect(escaparLike(''), '');
    });
  });
}
