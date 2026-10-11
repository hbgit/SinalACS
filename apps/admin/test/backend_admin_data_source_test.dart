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
    },
  );

  test('auditoria: mapeia o rótulo do usuário e o instante', () async {
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
          ),
        ],
      ),
    );
    final r = await _fonte(caller).fetchAuditLogs(limit: 10);
    // O cliente gerado manda `beforeSequence: null` (sem cursor) junto com o resto.
    expect(caller.lastArgs, {
      'accessToken': 'token-de-teste',
      'limit': 10,
      'beforeSequence': null,
    });
    expect(r.single.userLabel, 'ADM-1 (Administrador)');
    expect(r.single.timestamp, em);
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
}
