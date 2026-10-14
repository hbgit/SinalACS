import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/core/data/admin_data_source.dart';
import 'package:sinalacs_admin/core/data/backend_admin_data_source.dart';
import 'package:sinalacs_client/sinalacs_client.dart' as api;

import 'support/fake_admin_auth.dart';

/// `BackendAdminDataSource` (#40) sobre o `EndpointAdmin` do cliente gerado, com
/// um chamador falso: o mapeamento, o token e a tradução de falhas. Dados sintéticos.
BackendAdminDataSource _fonte(
  FakeEndpointCaller caller, {
  String token = 'token-de-teste',
}) => BackendAdminDataSource(api.EndpointAdmin(caller), accessToken: token);

void main() {
  test(
    'indicadores: mapeia contagens e preserva TMRAV nulo (sem amostra não é 0)',
    () async {
      final caller = FakeEndpointCaller(
        result: api.AdminIndicators(
          red: 2,
          yellow: 1,
          green: 3,
          openRedAlerts: 1,
          acknowledgedRedAlerts: 1,
          tmravSeconds: null,
        ),
      );
      final r = await _fonte(caller).fetchDashboardIndicators();
      expect(r.countsByRisk, {
        RiskLevel.red: 2,
        RiskLevel.yellow: 1,
        RiskLevel.green: 3,
      });
      expect(r.openRedAlerts, 1);
      expect(r.acknowledgedRedAlerts, 1);
      expect(r.tmravSeconds, isNull);
      expect(caller.lastArgs, {'accessToken': 'token-de-teste'});
    },
  );

  test('indicadores: TMRAV com valor passa como veio', () async {
    final caller = FakeEndpointCaller(
      result: api.AdminIndicators(
        red: 0,
        yellow: 0,
        green: 0,
        openRedAlerts: 0,
        acknowledgedRedAlerts: 0,
        tmravSeconds: 60,
      ),
    );
    expect((await _fonte(caller).fetchDashboardIndicators()).tmravSeconds, 60);
  });

  test('microáreas: mapeia o vínculo com o ACS', () async {
    final caller = FakeEndpointCaller(
      result: [
        api.AdminMicroArea(
          id: 'ma-1',
          name: 'Microárea A',
          acsName: 'Carla',
          acsEnrollmentId: 'ACS-1',
          acsActive: true,
        ),
      ],
    );
    final r = await _fonte(caller).fetchMicroAreas();
    expect(r.single.name, 'Microárea A');
    expect(r.single.acsEnrollmentId, 'ACS-1');
    expect(r.single.acsActive, isTrue);
  });

  test(
    'alertas: manda token, filtro por id, status e página; traduz os enums',
    () async {
      final em = DateTime.utc(2026, 10, 7, 12);
      final caller = FakeEndpointCaller(
        result: api.AdminAlertPage(
          items: [
            api.AdminAlert(
              id: 'a1',
              patientLabel: '#A18F',
              microAreaName: 'Microárea A',
              riskLevel: api.RiskLevel.red,
              status: api.AlertStatus.acknowledged,
              triggeredAt: em,
              escalatedAt: DateTime.utc(2026, 10, 7, 12, 20),
              overdue: true,
            ),
          ],
        ),
      );
      final r = await _fonte(caller).fetchAlerts(
        microAreaId: 'ma-1',
        status: AlertStatus.acknowledged,
        limit: 20,
        offset: 40,
      );
      expect(caller.lastArgs, {
        'accessToken': 'token-de-teste',
        'microAreaId': 'ma-1',
        'status': api.AlertStatus.acknowledged,
        'limit': 20,
        'offset': 40,
      });
      expect(r.single.patientLabel, 'Paciente #A18F', reason: 'a tela mostra o rótulo cru; o servidor manda só o #A18F');
      expect(r.single.riskLevel, RiskLevel.red);
      expect(r.single.status, AlertStatus.acknowledged);
      expect(r.single.triggeredAt, em);
      expect(r.single.overdue, isTrue, reason: 'vem do servidor, não do relógio do aparelho');
      expect(r.single.escalatedAt, DateTime.utc(2026, 10, 7, 12, 20));
    },
  );

  test('alertas: escalatedAt nulo e overdue falso passam como vieram', () async {
    final caller = FakeEndpointCaller(
      result: api.AdminAlertPage(
        items: [
          api.AdminAlert(
            id: 'a2',
            patientLabel: '#7C2E',
            microAreaName: 'Microárea A',
            riskLevel: api.RiskLevel.red,
            status: api.AlertStatus.pending,
            triggeredAt: DateTime.utc(2026, 10, 7, 12),
            overdue: false,
          ),
        ],
      ),
    );
    final r = await _fonte(caller).fetchAlerts();
    expect(r.single.escalatedAt, isNull);
    expect(r.single.overdue, isFalse);
  });

  group('escalonamento, pulso e fim de sessão (#44)', () {
    test('escalateAlert manda token, id e motivo; mapeia o resultado', () async {
      final em = DateTime.utc(2026, 10, 7, 12, 30);
      final caller = FakeEndpointCaller(
        result: api.AdminEscalationResult(alertId: 'a1', escalatedAt: em, alreadyEscalated: false),
      );
      final r = await _fonte(caller).escalateAlert('a1', EscalationReasonCode.acsUnreachable);
      expect(caller.lastArgs, {
        'accessToken': 'token-de-teste',
        'alertId': 'a1',
        'reason': api.EscalationReason.acsUnreachable,
      });
      expect(r.escalatedAt, em);
      expect(r.alreadyEscalated, isFalse);
    });

    test('escalateAlert: reaplicação devolve alreadyEscalated', () async {
      final em = DateTime.utc(2026, 10, 7, 12, 30);
      final caller = FakeEndpointCaller(
        result: api.AdminEscalationResult(alertId: 'a1', escalatedAt: em, alreadyEscalated: true),
      );
      final r = await _fonte(caller).escalateAlert('a1', EscalationReasonCode.noAckTimeout);
      expect(r.alreadyEscalated, isTrue);
      expect(r.escalatedAt, em);
    });

    test('escalateAlert: cada motivo do app vira o motivo do cliente de mesmo nome', () async {
      for (final m in EscalationReasonCode.values) {
        final caller = FakeEndpointCaller(
          result: api.AdminEscalationResult(
            alertId: 'a1',
            escalatedAt: DateTime.utc(2026),
            alreadyEscalated: false,
          ),
        );
        await _fonte(caller).escalateAlert('a1', m);
        expect(caller.lastArgs!['reason'], api.EscalationReason.values.byName(m.name));
      }
    });

    test('escalateAlert: textos de recusa do servidor chegam em português', () async {
      for (final texto in [
        'Alerta não encontrado.',
        'O prazo para escalonar este alerta ainda não venceu.',
        'Alerta já confirmado.',
        'Só alertas vermelhos podem ser escalonados.',
        'Identificador de alerta inválido.',
      ]) {
        await expectLater(
          _fonte(
            FakeEndpointCaller(error: api.AdminInvalidRequestException(message: texto)),
          ).escalateAlert('a1', EscalationReasonCode.noAckTimeout),
          throwsA(isA<AdminValidationFailure>().having((e) => e.message, 'message', texto)),
        );
      }
    });

    test('escalateAlert: permissão, sessão vencida e rede reaproveitam a tradução existente', () async {
      await expectLater(
        _fonte(
          FakeEndpointCaller(error: api.AlertPermissionException(message: 'acesso restrito ao backoffice')),
        ).escalateAlert('a1', EscalationReasonCode.noAckTimeout),
        throwsA(isA<AdminDataFailure>().having((e) => e.message, 'message', 'Acesso restrito ao backoffice.')),
      );
      await expectLater(
        _fonte(
          FakeEndpointCaller(error: api.ServerpodClientUnauthorized()),
        ).escalateAlert('a1', EscalationReasonCode.noAckTimeout),
        throwsA(isA<AdminSessionExpired>()),
      );
      await expectLater(
        _fonte(
          FakeEndpointCaller(error: const SocketException('x')),
        ).escalateAlert('a1', EscalationReasonCode.noAckTimeout),
        throwsA(isA<AdminDataFailure>().having((e) => e.message, 'message', 'Não foi possível conectar ao servidor.')),
      );
    });

    test('alertsPulse mapeia indicadores, vermelhos vencidos, marca e relógio do servidor', () async {
      final agora = DateTime.utc(2026, 10, 7, 13);
      final marca = DateTime.utc(2026, 10, 7, 12, 59);
      final caller = FakeEndpointCaller(
        result: api.AdminAlertsPulse(
          indicators: api.AdminIndicators(
            red: 2,
            yellow: 1,
            green: 0,
            openRedAlerts: 2,
            acknowledgedRedAlerts: 0,
            tmravSeconds: null,
          ),
          overdueRed: 1,
          maxChangedAt: marca,
          serverNow: agora,
        ),
      );
      final r = await _fonte(caller).alertsPulse();
      expect(caller.lastArgs, {'accessToken': 'token-de-teste'});
      expect(r.indicators.countsByRisk[RiskLevel.red], 2);
      expect(r.indicators.openRedAlerts, 2);
      expect(r.indicators.tmravSeconds, isNull);
      expect(r.overdueRed, 1);
      expect(r.maxChangedAt, marca);
      expect(r.serverNow, agora);
    });

    test('alertsPulse: maxChangedAt nulo passa como veio; falhas usam a guarda das leituras', () async {
      final caller = FakeEndpointCaller(
        result: api.AdminAlertsPulse(
          indicators: api.AdminIndicators(
            red: 0,
            yellow: 0,
            green: 0,
            openRedAlerts: 0,
            acknowledgedRedAlerts: 0,
          ),
          overdueRed: 0,
          serverNow: DateTime.utc(2026, 10, 7),
        ),
      );
      expect((await _fonte(caller).alertsPulse()).maxChangedAt, isNull);
      await expectLater(
        _fonte(FakeEndpointCaller(error: api.ServerpodClientUnauthorized())).alertsPulse(),
        throwsA(isA<AdminSessionExpired>()),
      );
    });

    test('endMonitoringSession chama o servidor com o token', () async {
      final caller = FakeEndpointCaller();
      await _fonte(caller).endMonitoringSession();
      expect(caller.lastArgs, {'accessToken': 'token-de-teste'});
    });

    test('endMonitoringSession nunca lança, qualquer que seja a falha', () async {
      for (final erro in <Object>[
        api.AlertPermissionException(message: 'x'),
        api.ServerpodClientUnauthorized(),
        const SocketException('sem rede'),
        TimeoutException('x'),
        StateError('qualquer coisa'),
      ]) {
        await _fonte(FakeEndpointCaller(error: erro)).endMonitoringSession();
      }
    });
  });

  test('auditoria: mapeia o rótulo do usuário, o instante, a sequence e o selo', () async {
    final em = DateTime.utc(2026, 10, 7, 12, 30);
    final caller = FakeEndpointCaller(
      result: api.AdminAuditPage(
        items: [
          api.AdminAuditEntry(
            id: 'l1',
            sequence: 9,
            userLabel: 'ADM-1 (Administrador)',
            actionType: 'read',
            resourceType: 'admin_alerts',
            timestamp: em,
            result: 'success',
            integrity: api.AuditRowSeal.invalid,
          ),
        ],
        nextBeforeSequence: 9,
      ),
    );
    final r = await _fonte(caller).fetchAuditLogs(limit: 10);
    // Sem filtro e sem cursor, o cliente gerado manda `filter: null` e
    // `beforeSequence: null` junto com o resto.
    expect(caller.lastArgs, {
      'accessToken': 'token-de-teste',
      'filter': null,
      'limit': 10,
      'beforeSequence': null,
    });
    expect(r.items.single.userLabel, 'ADM-1 (Administrador)');
    expect(r.items.single.timestamp, em);
    expect(r.items.single.sequence, 9);
    expect(r.items.single.seal, AuditRowSeal.invalid);
    expect(r.nextBeforeSequence, 9);
  });

  test('auditoria: selo ausente na resposta vira "não verificável", nunca íntegro', () async {
    final caller = FakeEndpointCaller(
      result: api.AdminAuditPage(
        items: [
          api.AdminAuditEntry(
            id: 'l1',
            sequence: 1,
            userLabel: 'ADM-1 (Administrador)',
            actionType: 'read',
            resourceType: 'admin_alerts',
            timestamp: DateTime.utc(2026, 10, 7),
            result: 'success',
          ),
        ],
      ),
    );
    final r = await _fonte(caller).fetchAuditLogs();
    expect(r.items.single.seal, AuditRowSeal.unverifiable);
    expect(r.nextBeforeSequence, isNull);
  });

  test('auditoria: traduz o filtro por nome e passa o cursor', () async {
    final de = DateTime.utc(2026, 10, 1);
    final ate = DateTime.utc(2026, 10, 8);
    final caller = FakeEndpointCaller(result: api.AdminAuditPage(items: []));
    await _fonte(caller).fetchAuditLogs(
      filter: AuditLogFilter(
        actorEnrollmentId: 'ACS-12',
        actorRole: AuditActorRole.coordinator,
        actionType: 'write',
        resourceType: 'admin_acs',
        result: 'created',
        from: de,
        to: ate,
        search: 'adm',
      ),
      limit: 20,
      beforeSequence: 300,
    );
    final f = caller.lastArgs!['filter'] as api.AdminAuditFilter;
    expect(f.actorEnrollmentId, 'ACS-12');
    expect(f.actorRole, api.UserRole.coordinator);
    expect(f.actionType, 'write');
    expect(f.resourceType, 'admin_acs');
    expect(f.result, 'created');
    expect(f.from, de);
    expect(f.to, ate);
    expect(f.search, 'adm');
    expect(caller.lastArgs!['limit'], 20);
    expect(caller.lastArgs!['beforeSequence'], 300);
  });

  test('auditoria: filtro recusado pelo servidor vira texto fixo sobre o filtro', () async {
    final caller = FakeEndpointCaller(
      error: api.AdminInvalidRequestException(message: 'detalhe interno do servidor'),
    );
    await expectLater(
      _fonte(caller).fetchAuditLogs(filter: const AuditLogFilter(search: 'xx')),
      throwsA(
        isA<AdminDataFailure>()
            .having((f) => f.message, 'message', 'Filtro de auditoria inválido. Revise os campos.')
            .having((f) => f.message, 'message', isNot(contains('interno'))),
      ),
    );
  });

  test('cadeia: mapeia estado, contagens, motivo e brokenInScope nulo como nulo', () async {
    final em = DateTime.utc(2026, 10, 13, 9);
    final caller = FakeEndpointCaller(
      result: api.AdminAuditChainStatus(
        state: api.AuditIntegrityState.broken,
        checkedRows: 120,
        headSequence: 130,
        firstBrokenSequence: 77,
        reasonCode: api.AuditChainReason.checkpointInvalid,
        verifiedAt: em,
      ),
    );
    final s = await _fonte(caller).verifyAuditChain();
    expect(caller.lastArgs, {'accessToken': 'token-de-teste'});
    expect(s.state, AuditIntegrityState.broken);
    expect(s.checkedRows, 120);
    expect(s.headSequence, 130);
    expect(s.firstBrokenSequence, 77);
    expect(s.brokenInScope, isNull, reason: 'nulo é "não informado", não false');
    expect(s.reasonCode, AuditChainReason.checkpointInvalid);
    expect(s.verifiedAt, em);
  });

  test('cadeia: todo estado e todo motivo do cliente têm par no app, por nome', () async {
    for (final e in api.AuditIntegrityState.values) {
      final caller = FakeEndpointCaller(
        result: api.AdminAuditChainStatus(state: e, verifiedAt: DateTime.utc(2026), brokenInScope: false),
      );
      final s = await _fonte(caller).verifyAuditChain();
      expect(s.state.name, e.name);
      expect(s.brokenInScope, isFalse);
    }
    for (final r in api.AuditChainReason.values) {
      final caller = FakeEndpointCaller(
        result: api.AdminAuditChainStatus(
          state: api.AuditIntegrityState.unavailable,
          reasonCode: r,
          verifiedAt: DateTime.utc(2026),
        ),
      );
      expect((await _fonte(caller).verifyAuditChain()).reasonCode!.name, r.name);
    }
    expect(AuditRowSeal.values.map((s) => s.name), api.AuditRowSeal.values.map((s) => s.name));
  });

  test('cadeia: recusa de papel vira falha genérica', () async {
    final caller = FakeEndpointCaller(
      error: api.AlertPermissionException(message: 'detalhe interno do servidor'),
    );
    await expectLater(
      _fonte(caller).verifyAuditChain(),
      throwsA(isA<AdminDataFailure>().having((f) => f.message, 'message', 'Acesso restrito ao backoffice.')),
    );
  });

  test(
    'recusa de papel vira falha genérica, sem o texto do servidor',
    () async {
      final caller = FakeEndpointCaller(
        error: api.AlertPermissionException(
          message: 'detalhe interno do servidor',
        ),
      );
      await expectLater(
        _fonte(caller).fetchMicroAreas(),
        throwsA(
          isA<AdminDataFailure>().having(
            (e) => e.message,
            'message',
            'Acesso restrito ao backoffice.',
          ),
        ),
      );
    },
  );

  test('parâmetro inválido e falha de rede viram mensagens próprias', () async {
    await expectLater(
      _fonte(
        FakeEndpointCaller(
          error: api.AdminInvalidRequestException(message: 'x'),
        ),
      ).fetchAlerts(),
      throwsA(
        isA<AdminDataFailure>().having(
          (e) => e.message,
          'message',
          'Parâmetro de paginação inválido.',
        ),
      ),
    );
    await expectLater(
      _fonte(
        FakeEndpointCaller(error: const SocketException('sem rede')),
      ).fetchDashboardIndicators(),
      throwsA(
        isA<AdminDataFailure>().having(
          (e) => e.message,
          'message',
          'Não foi possível conectar ao servidor.',
        ),
      ),
    );
  });

  test('401 do servidor (token vencido na chamada) vira AdminSessionExpired', () async {
    await expectLater(
      _fonte(
        FakeEndpointCaller(error: api.ServerpodClientUnauthorized()),
      ).fetchDashboardIndicators(),
      throwsA(isA<AdminSessionExpired>()),
    );
  });

  test('o cliente embrulha a falha de rede em ServerpodClientException(-1): texto de conexão', () async {
    await expectLater(
      _fonte(
        FakeEndpointCaller(error: const api.ServerpodClientException('Connection refused', -1)),
      ).fetchDashboardIndicators(),
      throwsA(
        isA<AdminDataFailure>().having((e) => e.message, 'message', 'Não foi possível conectar ao servidor.'),
      ),
    );
  });

  test('tempo esgotado e falha de TLS também viram o texto de conexão', () async {
    for (final erro in <Object>[TimeoutException('x'), const HandshakeException('x')]) {
      await expectLater(
        _fonte(FakeEndpointCaller(error: erro)).fetchDashboardIndicators(),
        throwsA(isA<AdminDataFailure>().having((e) => e.message, 'message', 'Não foi possível conectar ao servidor.')),
      );
    }
  });

  // O servidor NÃO responde 401: recusa o token com AlertPermissionException
  // ('token inválido ou expirado'). Com a sessão já vencida pelo relógio, isso é
  // sessão vencida; antes do vencimento continua sendo recusa de acesso.
  test('recusa depois do vencimento da sessão vira AdminSessionExpired', () async {
    final fonte = BackendAdminDataSource(
      api.EndpointAdmin(FakeEndpointCaller(error: api.AlertPermissionException(message: 'token inválido ou expirado'))),
      accessToken: 't',
      expiresAt: DateTime.utc(2026, 1, 1, 12),
      now: () => DateTime.utc(2026, 1, 1, 12, 0, 1),
    );
    await expectLater(fonte.fetchDashboardIndicators(), throwsA(isA<AdminSessionExpired>()));
  });

  test('recusa antes do vencimento segue sendo acesso restrito', () async {
    final fonte = BackendAdminDataSource(
      api.EndpointAdmin(FakeEndpointCaller(error: api.AlertPermissionException(message: 'x'))),
      accessToken: 't',
      expiresAt: DateTime.utc(2026, 1, 1, 12),
      now: () => DateTime.utc(2026, 1, 1, 11),
    );
    await expectLater(
      fonte.fetchDashboardIndicators(),
      throwsA(isA<AdminDataFailure>().having((e) => e.message, 'message', 'Acesso restrito ao backoffice.')),
    );
  });

  test(
    'recordAccess não chama o servidor: ele já audita cada leitura',
    () async {
      final caller = FakeEndpointCaller();
      await _fonte(
        caller,
      ).recordAccess(actionType: 'view', resourceType: 'micro_areas');
      expect(caller.lastArgs, isNull);
    },
  );
  group('pedidos do titular (#42)', () {
    final prazo = DateTime.utc(2026, 10, 3, 12);
    final criado = DateTime.utc(2026, 9, 18, 12);

    test('lista: manda token, status e página; traduz os enums por nome e mantém a ordem', () async {
      final caller = FakeEndpointCaller(
        result: api.AdminDataSubjectRequestPage(
          items: [
            api.AdminDataSubjectRequest(
              id: 'r1',
              type: api.DataSubjectRequestType.correction,
              status: api.DataSubjectRequestStatus.inReview,
              createdAt: criado,
              dueAt: prazo,
              overdue: true,
              patientLabel: '#A18F',
            ),
            api.AdminDataSubjectRequest(
              id: 'r2',
              type: api.DataSubjectRequestType.deletion,
              status: api.DataSubjectRequestStatus.open,
              createdAt: criado,
              dueAt: prazo.add(const Duration(days: 1)),
              overdue: false,
              patientLabel: '#7C2E',
            ),
          ],
        ),
      );
      final r = await _fonte(caller).fetchDataRequests(status: DataRequestStatus.inReview, limit: 20, offset: 40);
      expect(caller.lastArgs, {
        'accessToken': 'token-de-teste',
        'status': api.DataSubjectRequestStatus.inReview,
        'limit': 20,
        'offset': 40,
      });
      expect(r.map((e) => e.id), ['r1', 'r2']);
      expect(r.first.type, DataRequestType.correction);
      expect(r.first.status, DataRequestStatus.inReview);
      expect(r.first.overdue, isTrue);
      expect(r.first.dueAt, prazo);
      expect(r.first.createdAt, criado);
      expect(r.first.patientLabel, 'Paciente #A18F');
      expect(r.last.type, DataRequestType.deletion);
    });

    test('detalhe: traz o texto decifrado, a resposta e a data da decisão', () async {
      final decidido = DateTime.utc(2026, 10, 1, 9);
      final caller = FakeEndpointCaller(
        result: api.AdminDataSubjectRequestDetail(
          id: 'r1',
          type: api.DataSubjectRequestType.correction,
          status: api.DataSubjectRequestStatus.rejected,
          createdAt: criado,
          dueAt: prazo,
          overdue: false,
          patientLabel: '#A18F',
          details: 'texto fictício',
          resolution: 'motivo fictício',
          decidedAt: decidido,
        ),
      );
      final r = await _fonte(caller).fetchDataRequest('r1');
      expect(caller.lastArgs, {'accessToken': 'token-de-teste', 'id': 'r1'});
      expect(r.details, 'texto fictício');
      expect(r.resolution, 'motivo fictício');
      expect(r.decidedAt, decidido);
      expect(r.status, DataRequestStatus.rejected);
      expect(r.patientLabel, 'Paciente #A18F');
    });

    test('decisões mandam token, id e o texto já sem espaços nas pontas', () async {
      final caller = FakeEndpointCaller();
      final fonte = _fonte(caller);

      await fonte.startDataRequestReview('r1');
      expect(caller.lastArgs, {'accessToken': 'token-de-teste', 'id': 'r1'});

      await fonte.completeDataRequest('r1', note: '  nota fictícia  ');
      expect(caller.lastArgs, {'accessToken': 'token-de-teste', 'id': 'r1', 'note': 'nota fictícia'});

      await fonte.completeDataRequest('r2');
      expect(caller.lastArgs, {'accessToken': 'token-de-teste', 'id': 'r2', 'note': null});

      await fonte.rejectDataRequest('r3', reason: ' motivo fictício ');
      expect(caller.lastArgs, {'accessToken': 'token-de-teste', 'id': 'r3', 'reason': 'motivo fictício'});
    });

    test('recusa de decisão pelo servidor vira o texto neutro, nunca o de paginação nem o cru', () async {
      const neutro = 'Pedido não encontrado ou já decidido. Atualize a lista.';
      final caller = FakeEndpointCaller(
        error: api.AdminInvalidRequestException(message: 'detalhe interno do servidor'),
      );
      final fonte = _fonte(caller);
      for (final chamada in <Future<void> Function()>[
        () => fonte.startDataRequestReview('r1'),
        () => fonte.completeDataRequest('r1', note: 'nota fictícia'),
        () => fonte.rejectDataRequest('r1', reason: 'motivo fictício'),
        () => fonte.fetchDataRequest('r1'),
      ]) {
        await expectLater(
          chamada(),
          throwsA(isA<AdminDataFailure>().having((e) => e.message, 'message', neutro)),
        );
      }
      // A lista continua com o texto de paginação.
      await expectLater(
        fonte.fetchDataRequests(),
        throwsA(isA<AdminDataFailure>().having((e) => e.message, 'message', 'Parâmetro de paginação inválido.')),
      );
    });

    test('nota ou motivo fora de 3 a 500 caracteres é recusado sem chamar o servidor', () async {
      const textoInvalido = 'A resposta deve ter de 3 a 500 caracteres.';
      for (final texto in ['', '  ', 'ab', '   ab   ', 'x' * 501]) {
        final caller = FakeEndpointCaller();
        final fonte = _fonte(caller);
        await expectLater(
          fonte.rejectDataRequest('r1', reason: texto),
          throwsA(isA<AdminDataFailure>().having((e) => e.message, 'message', textoInvalido)),
        );
        await expectLater(
          fonte.completeDataRequest('r1', note: texto),
          throwsA(isA<AdminDataFailure>().having((e) => e.message, 'message', textoInvalido)),
        );
        expect(caller.lastArgs, isNull, reason: 'nada foi enviado para "$texto"');
      }
      // Exatamente 500 depois do trim passa.
      final caller = FakeEndpointCaller();
      await _fonte(caller).rejectDataRequest('r1', reason: ' ${'x' * 500} ');
      expect(caller.lastArgs?['reason'], 'x' * 500);
    });

    test('sessão vencida numa decisão vira AdminSessionExpired', () async {
      final fonte = BackendAdminDataSource(
        api.EndpointAdmin(FakeEndpointCaller(error: api.AlertPermissionException(message: 'x'))),
        accessToken: 't',
        expiresAt: DateTime.utc(2026, 1, 1, 12),
        now: () => DateTime.utc(2026, 1, 1, 12, 0, 1),
      );
      await expectLater(fonte.completeDataRequest('r1', note: 'nota fictícia'), throwsA(isA<AdminSessionExpired>()));
      await expectLater(
        _fonte(FakeEndpointCaller(error: api.ServerpodClientUnauthorized())).rejectDataRequest('r1', reason: 'motivo'),
        throwsA(isA<AdminSessionExpired>()),
      );
    });
  });

  group('exportação da trilha (#45, Task 11)', () {
    final em = DateTime.utc(2026, 10, 13, 12);
    final filtro = AuditLogFilter(
      from: DateTime.utc(2026, 10, 1, 12),
      to: DateTime.utc(2026, 10, 5, 21),
      actorRole: AuditActorRole.acs,
      search: 'ACS',
    );

    test('manda token e filtro (papel por nome, período em UTC) e mapeia o resultado', () async {
      final caller = FakeEndpointCaller(
        result: api.AdminAuditExport(
          fileName: 'auditoria_x.csv',
          csv: 'sequence\r\n3\r\n',
          rowCount: 1,
          firstSequence: 3,
          lastSequence: 3,
          contentSha256: 'ab' * 32,
          chainState: api.AuditIntegrityState.inconclusive,
          generatedAt: em,
        ),
      );
      final r = await _fonte(caller).exportAuditLogs(filtro);

      expect(caller.lastArgs!['accessToken'], 'token-de-teste');
      final enviado = caller.lastArgs!['filter'] as api.AdminAuditFilter;
      expect(enviado.from, filtro.from);
      expect(enviado.to, filtro.to);
      expect(enviado.actorRole, api.UserRole.acs);
      expect(enviado.search, 'ACS');

      expect(r.fileName, 'auditoria_x.csv');
      expect(r.csv, 'sequence\r\n3\r\n');
      expect(r.rowCount, 1);
      expect(r.firstSequence, 3);
      expect(r.lastSequence, 3);
      expect(r.contentSha256, 'ab' * 32);
      expect(r.chainState, AuditIntegrityState.inconclusive, reason: 'o estado vem como está, nunca promovido');
      expect(r.generatedAt, em);
    });

    test('recorte vazio: sequences nulas continuam nulas', () async {
      final caller = FakeEndpointCaller(
        result: api.AdminAuditExport(
          fileName: 'f.csv',
          csv: 'h\r\n',
          rowCount: 0,
          contentSha256: 'cd' * 32,
          chainState: api.AuditIntegrityState.verified,
          generatedAt: em,
        ),
      );
      final r = await _fonte(caller).exportAuditLogs(filtro);
      expect(r.firstSequence, isNull);
      expect(r.lastSequence, isNull);
    });

    test('teto de linhas (AdminInvalidRequestException) vira tooManyRows, sem o texto do servidor', () async {
      final caller = FakeEndpointCaller(
        error: api.AdminInvalidRequestException(message: 'O recorte passa de 5000 linhas. detalhe do servidor'),
      );
      await expectLater(
        _fonte(caller).exportAuditLogs(filtro),
        throwsA(
          isA<AuditExportFailure>()
              .having((f) => f.kind, 'kind', AuditExportFailureKind.tooManyRows)
              .having((f) => f.message, 'message', 'Há registros demais; estreite o período.'),
        ),
      );
    });

    test('recusa de permissão vira forbidden com texto fixo, sem o motivo', () async {
      final caller = FakeEndpointCaller(
        error: api.AlertPermissionException(message: 'coordenador não exporta: motivo interno'),
      );
      await expectLater(
        _fonte(caller).exportAuditLogs(filtro),
        throwsA(
          isA<AuditExportFailure>()
              .having((f) => f.kind, 'kind', AuditExportFailureKind.forbidden)
              .having((f) => f.message, 'message', 'Você não tem permissão para exportar a trilha de auditoria.')
              .having((f) => f.message, 'message', isNot(contains('motivo'))),
        ),
      );
    });

    test('recusa depois do vencimento da sessão vira AdminSessionExpired; 401 também', () async {
      final vencida = BackendAdminDataSource(
        api.EndpointAdmin(FakeEndpointCaller(error: api.AlertPermissionException(message: 'x'))),
        accessToken: 't',
        expiresAt: em,
        now: () => em.add(const Duration(seconds: 1)),
      );
      await expectLater(vencida.exportAuditLogs(filtro), throwsA(isA<AdminSessionExpired>()));
      await expectLater(
        _fonte(FakeEndpointCaller(error: api.ServerpodClientUnauthorized())).exportAuditLogs(filtro),
        throwsA(isA<AdminSessionExpired>()),
      );
    });

    test('500 genérico, rede, tempo esgotado e TLS viram failed com texto fixo', () async {
      for (final erro in <Object>[
        const api.ServerpodClientException('Internal server error', 500),
        const api.ServerpodClientException('Connection refused', -1),
        const SocketException('sem rede'),
        TimeoutException('x'),
        const HandshakeException('x'),
      ]) {
        await expectLater(
          _fonte(FakeEndpointCaller(error: erro)).exportAuditLogs(filtro),
          throwsA(
            isA<AuditExportFailure>()
                .having((f) => f.kind, 'kind', AuditExportFailureKind.failed)
                .having((f) => f.message, 'message', 'Não foi possível gerar a exportação. Tente novamente.'),
          ),
          reason: '$erro',
        );
      }
    });
  });
}
