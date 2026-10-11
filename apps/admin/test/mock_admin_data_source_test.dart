import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/core/data/admin_data_source.dart';
import 'package:sinalacs_admin/core/data/mock_admin_data_source.dart';

void main() {
  test('deve calcular contadores por risco e métricas de alerta vermelho a partir dos alertas mockados', () async {
    final dataSource = MockAdminDataSource();

    final indicators = await dataSource.fetchDashboardIndicators();

    expect(indicators.countsByRisk[RiskLevel.red], 2);
    expect(indicators.countsByRisk[RiskLevel.yellow], 2);
    expect(indicators.countsByRisk[RiskLevel.green], 2);
    expect(indicators.openRedAlerts, 1);
    expect(indicators.acknowledgedRedAlerts, 1);
  });

  test('deve filtrar alertas por microárea e status combinados', () async {
    final dataSource = MockAdminDataSource();

    final filtered = await dataSource.fetchAlerts(
      microAreaId: 'ma-07',
      status: AlertStatus.acknowledged,
    );

    expect(filtered, hasLength(1));
    expect(filtered.single.id, 'alert-3');
  });

  test('deve registrar acessos em ordem cronológica reversa (mais recente primeiro)', () async {
    final dataSource = MockAdminDataSource();

    await dataSource.recordAccess(actionType: 'view', resourceType: 'micro_areas');
    await dataSource.recordAccess(actionType: 'view', resourceType: 'alerts');

    final log = await dataSource.fetchAuditLogs();

    expect(log, hasLength(2));
    expect(log.first.resourceType, 'alerts');
    expect(log.last.resourceType, 'micro_areas');
  });

  test('pedidos do titular: fixtures sintéticas ordenadas por prazo, com um vencido', () async {
    final dataSource = MockAdminDataSource();

    final pedidos = await dataSource.fetchDataRequests();

    expect(pedidos, isNotEmpty);
    for (var i = 1; i < pedidos.length; i++) {
      expect(pedidos[i - 1].dueAt.isAfter(pedidos[i].dueAt), isFalse);
    }
    expect(pedidos.where((p) => p.overdue), isNotEmpty);
  });

  test('pedidos do titular: atender correção muda o status e grava a resposta', () async {
    final dataSource = MockAdminDataSource();

    await dataSource.completeDataRequest('req-a18f', note: 'Resposta fictícia.');
    final pedido = await dataSource.fetchDataRequest('req-a18f');

    expect(pedido.status, DataRequestStatus.completed);
    expect(pedido.resolution, 'Resposta fictícia.');
    expect(pedido.overdue, isFalse, reason: 'decidido não é mais vencido');
    await expectLater(
      dataSource.rejectDataRequest('req-a18f', reason: 'tarde demais'),
      throwsA(isA<AdminDataFailure>()),
    );
  });

  group('gestão de contas (#43)', () {
    test('semeia o ACS acs-1 e a conta de equipe staff-1, por chave', () async {
      final dataSource = MockAdminDataSource();

      final acs = await dataSource.fetchAcs();
      final carla = acs.firstWhere((a) => a.id == 'acs-1');
      expect(carla.name, 'Carla Nogueira');
      expect(carla.enrollmentId, 'ACS-001');
      expect(carla.microAreaId, 'ma-12');
      expect(carla.active, isTrue);
      expect(carla.mfaActive, isFalse);

      final staff = await dataSource.fetchStaff();
      final coordenadora = staff.firstWhere((s) => s.id == 'staff-1');
      expect(coordenadora.enrollmentId, 'COO-001');
      expect(coordenadora.role, 'coordinator');
      expect(coordenadora.ubsName, isNotNull);
    });

    test('createAcs acrescenta o ACS com a senha inicial determinística, uma vez', () async {
      final dataSource = MockAdminDataSource();

      final criado = await dataSource.createAcs(
        name: 'Nova Agente',
        enrollmentId: 'ACS-999',
        microAreaId: 'ma-07',
      );

      expect(criado.initialPassword, 'SENHA-INICIAL-DE-TESTE');
      expect(criado.acs.name, 'Nova Agente');
      expect(criado.acs.enrollmentId, 'ACS-999');
      expect(criado.acs.microAreaId, 'ma-07');
      expect(criado.acs.microAreaName, 'Microárea 07 — Centro');
      expect(criado.acs.active, isTrue, reason: 'o servidor cadastra já ativo');
      expect(criado.acs.mfaActive, isFalse, reason: 'MFA nasce pendente de ativação');

      final acs = await dataSource.fetchAcs();
      expect(acs.map((a) => a.id), contains(criado.acs.id));
    });

    test('setAcsActive desativa e anota a chamada; reativar não entra na lista', () async {
      final dataSource = MockAdminDataSource();

      final desativado = await dataSource.setAcsActive(acsId: 'acs-1', active: false);
      expect(desativado.active, isFalse);
      expect(dataSource.desativados, ['acs-1']);

      await dataSource.setAcsActive(acsId: 'acs-1', active: true);
      expect(dataSource.desativados, ['acs-1'], reason: 'reativar não é uma desativação');

      final carla = (await dataSource.fetchAcs()).firstWhere((a) => a.id == 'acs-1');
      expect(carla.active, isTrue);
    });

    test('setAcsMicroArea vincula e resolve o nome da microárea na lista da tela', () async {
      final dataSource = MockAdminDataSource();

      final vinculado = await dataSource.setAcsMicroArea(acsId: 'acs-1', microAreaId: 'ma-03');

      expect(vinculado.microAreaId, 'ma-03');
      expect(vinculado.microAreaName, 'Microárea 03 — Vila Esperança');
      expect(dataSource.vinculados, ['acs-1']);

      final carla = (await dataSource.fetchAcs()).firstWhere((a) => a.id == 'acs-1');
      expect(carla.microAreaId, 'ma-03');
    });

    test('resetAcsPassword devolve a senha determinística e anota o alvo', () async {
      final dataSource = MockAdminDataSource();

      final senha = await dataSource.resetAcsPassword(acsId: 'acs-1');

      expect(senha, 'SENHA-INICIAL-DE-TESTE');
      expect(dataSource.senhasRedefinidas, ['acs-1']);
    });

    test('resetAcsMfa limpa o estado de MFA do ACS e anota o alvo', () async {
      final dataSource = MockAdminDataSource();
      final antes = (await dataSource.fetchAcs()).firstWhere((a) => a.id == 'acs-2');
      expect(antes.mfaActive, isTrue);

      await dataSource.resetAcsMfa(acsId: 'acs-2');

      expect(dataSource.mfasRedefinidas, ['acs-2']);
      final depois = (await dataSource.fetchAcs()).firstWhere((a) => a.id == 'acs-2');
      expect(depois.mfaActive, isFalse);
    });

    test('resetStaffMfa devolve o código de ativação determinístico e limpa a MFA da conta', () async {
      final dataSource = MockAdminDataSource();

      final ativacao = await dataSource.resetStaffMfa(staffId: 'staff-1');

      expect(ativacao.code, 'ABCD-EFGH-JKLM-NPQR-STUV');
      expect(ativacao.expiresAt.isAfter(DateTime(2026, 1, 1)), isTrue);
      expect(dataSource.mfasRedefinidas, ['staff-1']);
      final conta = (await dataSource.fetchStaff()).firstWhere((s) => s.id == 'staff-1');
      expect(conta.mfaActive, isFalse);
    });
  });
}
