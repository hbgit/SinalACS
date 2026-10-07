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
}
