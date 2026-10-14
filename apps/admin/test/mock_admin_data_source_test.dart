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

    final log = (await dataSource.fetchAuditLogs()).items;

    expect(log, hasLength(2));
    expect(log.first.resourceType, 'alerts');
    expect(log.last.resourceType, 'micro_areas');
    expect(log.first.sequence, greaterThan(log.last.sequence));
    expect(log.map((e) => e.seal), everyElement(AuditRowSeal.verified));
  });

  group('auditoria (#45): filtro, cursor e estado da cadeia configuráveis', () {
    AuditLogEntry linha(int seq, String label, String acao) => AuditLogEntry(
          id: 'e$seq',
          sequence: seq,
          userLabel: label,
          actionType: acao,
          resourceType: 'session',
          timestamp: DateTime.utc(2026, 10, 1).add(Duration(hours: seq)),
          result: 'success',
          seal: seq.isEven ? AuditRowSeal.verified : AuditRowSeal.invalid,
        );

    test('keyset por sequence decrescente: a página seguinte começa abaixo do cursor', () async {
      final ds = MockAdminDataSource(auditSeed: [for (var s = 5; s >= 1; s--) linha(s, 'ADM-1 (Administrador)', 'read')]);
      final p1 = await ds.fetchAuditLogs(limit: 2);
      expect(p1.items.map((e) => e.sequence), [5, 4]);
      expect(p1.nextBeforeSequence, 4);
      final p2 = await ds.fetchAuditLogs(limit: 2, beforeSequence: p1.nextBeforeSequence);
      expect(p2.items.map((e) => e.sequence), [3, 2]);
      final p3 = await ds.fetchAuditLogs(limit: 2, beforeSequence: p2.nextBeforeSequence);
      expect(p3.items.map((e) => e.sequence), [1]);
      expect(p3.nextBeforeSequence, isNull);
      expect(ds.auditQueries.map((q) => q.beforeSequence), [null, 4, 2]);
    });

    test('filtros combinam em E e o selo vem da semente, sem recalcular', () async {
      final ds = MockAdminDataSource(auditSeed: [
        linha(4, 'ACS-12 (ACS)', 'read'),
        linha(3, 'ACS-12 (ACS)', 'write'),
        linha(2, 'COORD-1 (Coordenador)', 'read'),
        linha(1, 'Paciente #A18F', 'login'),
      ]);
      final acsLeitura = await ds.fetchAuditLogs(
        filter: const AuditLogFilter(actorRole: AuditActorRole.acs, actionType: 'read'),
      );
      expect(acsLeitura.items.map((e) => e.id), ['e4']);
      final paciente = await ds.fetchAuditLogs(filter: const AuditLogFilter(actorRole: AuditActorRole.patient));
      expect(paciente.items.map((e) => e.id), ['e1']);
      expect(paciente.items.single.seal, AuditRowSeal.invalid);
      final busca = await ds.fetchAuditLogs(filter: const AuditLogFilter(search: 'coord'));
      expect(busca.items.map((e) => e.id), ['e2']);
    });

    test('estado da cadeia é o configurado; sem configuração, verified', () async {
      final ds = MockAdminDataSource();
      expect((await ds.verifyAuditChain()).state, AuditIntegrityState.verified);
      ds.chainStatus = ChainStatus(state: AuditIntegrityState.unavailable, verifiedAt: DateTime.utc(2026));
      expect((await ds.verifyAuditChain()).state, AuditIntegrityState.unavailable);
      expect(ds.verifyChainCalls, 2);
    });
  });

  test('AuditLogFilter: isEmpty, copyWith que limpa campo e igualdade por valor', () {
    const vazio = AuditLogFilter();
    expect(vazio.isEmpty, isTrue);
    final f = vazio.copyWith(search: 'ab', actorRole: AuditActorRole.acs);
    expect(f.isEmpty, isFalse);
    expect(f, const AuditLogFilter(search: 'ab', actorRole: AuditActorRole.acs));
    expect(f.copyWith(search: null).search, isNull);
    expect(f.copyWith(search: null).actorRole, AuditActorRole.acs);
    expect(f.copyWith(search: null, actorRole: null).isEmpty, isTrue);
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

  group('escalonamento, pulso e fim de sessão (#44)', () {
    final t0 = DateTime(2026, 10, 7, 12);

    // alert-1 é vermelho e pendente, disparado às 8h12 de 11/09 (já vencido
    // para qualquer relógio posterior); o relógio injetado controla o prazo.
    MockAdminDataSource fonte(DateTime agora) => MockAdminDataSource(now: () => agora);

    test('vermelho pendente vencido: escalona, segue pendente e listado, com escalatedAt', () async {
      final ds = fonte(t0);
      final antes = await ds.fetchAlerts();
      expect(antes.firstWhere((a) => a.id == 'alert-1').overdue, isTrue);

      final r = await ds.escalateAlert('alert-1', EscalationReasonCode.noAckTimeout);
      expect(r.alreadyEscalated, isFalse);
      expect(r.escalatedAt, t0);

      final depois = await ds.fetchAlerts();
      expect(depois, hasLength(antes.length), reason: 'escalonar não tira o alerta da lista');
      final a = depois.firstWhere((a) => a.id == 'alert-1');
      expect(a.status, AlertStatus.pending, reason: 'o escalonamento não confirma nem muda o status');
      expect(a.escalatedAt, t0);
    });

    test('segunda chamada devolve alreadyEscalated com o horário original', () async {
      var agora = t0;
      final ds = MockAdminDataSource(now: () => agora);
      final primeira = await ds.escalateAlert('alert-1', EscalationReasonCode.acsUnreachable);
      agora = t0.add(const Duration(minutes: 5));
      final segunda = await ds.escalateAlert('alert-1', EscalationReasonCode.patientRecontact);
      expect(segunda.alreadyEscalated, isTrue);
      expect(segunda.escalatedAt, primeira.escalatedAt);
    });

    test('alerta ainda no prazo: mesma recusa do servidor', () async {
      // Um minuto depois do disparo de alert-1, o prazo não venceu.
      final ds = fonte(DateTime(2026, 9, 11, 8, 13));
      await expectLater(
        ds.escalateAlert('alert-1', EscalationReasonCode.noAckTimeout),
        throwsA(isA<AdminValidationFailure>().having(
          (e) => e.message,
          'message',
          'O prazo para escalonar este alerta ainda não venceu.',
        )),
      );
    });

    test('recusas: confirmado, não vermelho e inexistente', () async {
      final ds = fonte(t0);
      Matcher falha(String m) => throwsA(isA<AdminValidationFailure>().having((e) => e.message, 'message', m));
      await expectLater(ds.escalateAlert('alert-2', EscalationReasonCode.noAckTimeout), falha('Alerta já confirmado.'));
      await expectLater(
        ds.escalateAlert('alert-3', EscalationReasonCode.noAckTimeout),
        falha('Só alertas vermelhos podem ser escalonados.'),
      );
      await expectLater(
        ds.escalateAlert('nao-existe', EscalationReasonCode.noAckTimeout),
        falha('Alerta não encontrado.'),
      );
    });

    test('alertsPulse reflete indicadores, vencidos, marca e relógio', () async {
      final ds = fonte(t0);
      final p = await ds.alertsPulse();
      expect(p.serverNow, t0);
      expect(p.overdueRed, 1);
      expect(p.indicators.openRedAlerts, 1);
      final antes = p.maxChangedAt;
      await ds.escalateAlert('alert-1', EscalationReasonCode.noAckTimeout);
      final depois = await ds.alertsPulse();
      expect(depois.maxChangedAt, isNotNull);
      expect(antes == null || !depois.maxChangedAt!.isBefore(antes), isTrue);
      expect(depois.maxChangedAt, t0, reason: 'o escalonamento é uma mudança observável');
    });

    test('endMonitoringSession é registrado', () async {
      final ds = MockAdminDataSource();
      expect(ds.monitoringSessionEnds, 0);
      await ds.endMonitoringSession();
      await ds.endMonitoringSession();
      expect(ds.monitoringSessionEnds, 2);
    });
  });

  group('exportação da trilha (#45, Task 11)', () {
    AuditLogEntry linha(int seq, DateTime em) => AuditLogEntry(
          id: 'e$seq',
          sequence: seq,
          userLabel: 'ADM-001 (Administrador)',
          actionType: 'read',
          resourceType: 'admin_alerts',
          timestamp: em,
          result: 'success',
          seal: AuditRowSeal.verified,
        );

    test('sem resultado configurado, exporta o recorte semeado do período e conta a chamada', () async {
      final ds = MockAdminDataSource(auditSeed: [
        linha(1, DateTime.utc(2026, 9, 30)),
        linha(2, DateTime.utc(2026, 10, 2)),
        linha(3, DateTime.utc(2026, 10, 3)),
        linha(4, DateTime.utc(2026, 10, 9)),
      ]);
      final filtro = AuditLogFilter(from: DateTime.utc(2026, 10, 1), to: DateTime.utc(2026, 10, 5));

      final r = await ds.exportAuditLogs(filtro);

      expect(ds.exportCalls, 1);
      expect(ds.lastExportFilter, filtro);
      expect(r.rowCount, 2);
      expect(r.firstSequence, 2);
      expect(r.lastSequence, 3);
      expect(r.csv, startsWith('sequence,timestamp_utc,autor,papel_autor,acao,recurso,rotulo_recurso,resultado,selo\r\n'));
      expect(r.contentSha256, hasLength(64));
      expect(r.chainState, AuditIntegrityState.verified);
    });

    test('erro configurado é lançado e a chamada ainda é contada', () async {
      final ds = MockAdminDataSource()..exportError = const AuditExportFailure(AuditExportFailureKind.tooManyRows);
      final filtro = AuditLogFilter(from: DateTime.utc(2026, 10, 1), to: DateTime.utc(2026, 10, 5));
      await expectLater(ds.exportAuditLogs(filtro), throwsA(isA<AuditExportFailure>()));
      expect(ds.exportCalls, 1);
    });

    test('sem início e fim é erro de programação: a tela nunca pede assim', () async {
      final ds = MockAdminDataSource();
      await expectLater(ds.exportAuditLogs(const AuditLogFilter()), throwsArgumentError);
    });
  });
}
