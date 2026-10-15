import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/app/admin_theme.dart';
import 'package:sinalacs_admin/app/app.dart';
import 'package:sinalacs_admin/core/data/admin_data_source.dart';
import 'package:sinalacs_admin/core/data/mock_admin_data_source.dart';

import 'support/failing_admin_data_source.dart';
import 'support/fake_admin_auth.dart';
import 'support/layout_harness.dart';

/// Tela de auditoria (#45, Task 8): selo por linha, estado da cadeia, filtros e
/// cursor. Dados sintéticos; a integridade vem **sempre** da fonte de dados —
/// a tela só mostra o que o servidor devolveu.
final _agora = DateTime.utc(2026, 10, 13, 12);

AuditLogEntry _linha(
  int seq, {
  AuditRowSeal seal = AuditRowSeal.verified,
  String userLabel = 'ADM-001 (Administrador)',
  String actionType = 'read',
  String resourceType = 'admin_alerts',
  String result = 'success',
}) =>
    AuditLogEntry(
      id: 'e$seq',
      sequence: seq,
      userLabel: userLabel,
      actionType: actionType,
      resourceType: resourceType,
      timestamp: _agora.subtract(Duration(minutes: 100 - seq)),
      result: result,
      seal: seal,
    );

ChainStatus _cadeia(
  AuditIntegrityState state, {
  int? checkedRows = 42,
  int? firstBrokenSequence,
  bool? brokenInScope,
  AuditChainReason? reasonCode,
}) =>
    ChainStatus(
      state: state,
      checkedRows: checkedRows,
      firstBrokenSequence: firstBrokenSequence,
      brokenInScope: brokenInScope,
      reasonCode: reasonCode,
      verifiedAt: _agora,
    );

Future<void> _abrir(WidgetTester tester, AdminDataSource dataSource, {Size tamanho = const Size(1024, 900)}) async {
  await abrirBackoffice(tester, tamanho: tamanho, dataSource: dataSource);
  await irPara(tester, 'Auditoria');
}

/// Traz [alvo] para a janela (a lista é preguiçosa) antes de tocar ou ler.
/// Rola a PÁGINA da auditoria, nunca um campo do filtro.
Future<void> _rolarAte(WidgetTester tester, Finder alvo) async {
  if (alvo.evaluate().isEmpty) {
    // `scrollUntilVisible` só desce: o alvo pode ter ficado acima da janela.
    await _topo(tester);
  }
  if (alvo.evaluate().isEmpty) {
    await tester.scrollUntilVisible(alvo, 300, scrollable: rolagemDaAuditoria());
  }
  await tester.ensureVisible(alvo);
  await tester.pumpAndSettle();
}

/// Volta ao topo da página da auditoria.
Future<void> _topo(WidgetTester tester) async {
  await tester.drag(rolagemDaAuditoria(), const Offset(0, 20000));
  await tester.pumpAndSettle();
}

Future<void> _tocar(WidgetTester tester, Finder alvo) async {
  await _rolarAte(tester, alvo);
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

/// Os filtros nascem recolhidos: abre a seção se os campos não estão na tela.
Future<void> _abrirFiltros(WidgetTester tester) async {
  if (find.byKey(const Key('audit_filter_apply')).evaluate().isNotEmpty) return;
  await _tocar(tester, find.text('Filtros'));
}

Future<void> _escolher(WidgetTester tester, String chave, String opcao) async {
  await _abrirFiltros(tester);
  await _tocar(tester, find.byKey(Key(chave)));
  await tester.tap(find.text(opcao).last);
  await tester.pumpAndSettle();
}

Future<void> _digitar(WidgetTester tester, String chave, String texto) async {
  await _abrirFiltros(tester);
  await _rolarAte(tester, find.byKey(Key(chave)));
  await tester.enterText(find.byKey(Key(chave)), texto);
  // Tira o foco do campo: um campo focado se traz de volta à janela a cada
  // quadro e desfaria a rolagem até o botão que o teste vai tocar.
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('deve registrar e exibir o próprio acesso do admin às telas sensíveis', (tester) async {
    await tester.pumpWidget(SinalAdminApp(auth: FakeAdminAuth()));
    await entrarComCredenciais(tester);

    // Visitar Microáreas e Alertas antes da Auditoria — cada visita deve gerar
    // uma entrada própria via AdminDataSource.recordAccess (PRD §4.2.2).
    await tester.tap(find.text('Microáreas').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alertas').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Auditoria').last);
    await tester.pumpAndSettle();

    expect(find.text('Logs de auditoria'), findsOneWidget);
    // Desde a #45 o painel da cadeia e os filtros ficam acima da lista, que é
    // preguiçosa: a 800x600 as linhas mais antigas nascem abaixo da dobra, então
    // cada uma é trazida à janela antes de ser procurada (como na #44).
    for (final linha in ['view • audit_logs', 'view • alerts', 'view • micro_areas']) {
      await _rolarAte(tester, find.text(linha));
      expect(find.text(linha), findsOneWidget);
    }
    expect(find.textContaining('admin.dev (Administrador)'), findsWidgets);
  });

  group('selo por linha (D3): ícone + rótulo + Semantics, nunca só cor', () {
    testWidgets('verified, invalid e unverifiable têm rótulo, ícone e cor próprios', (tester) async {
      final mock = MockAdminDataSource(auditSeed: [
        _linha(3, seal: AuditRowSeal.verified),
        _linha(2, seal: AuditRowSeal.invalid),
        _linha(1, seal: AuditRowSeal.unverifiable),
      ]);
      await _abrir(tester, mock);

      Finder selo(String id) => find.byKey(Key('audit_seal_$id'));
      for (final id in ['e3', 'e2', 'e1']) {
        await _rolarAte(tester, selo(id));
      }

      expect(find.descendant(of: selo('e3'), matching: find.text('Íntegro')), findsOneWidget);
      expect(find.descendant(of: selo('e2'), matching: find.text('Adulterado?')), findsOneWidget);
      expect(find.descendant(of: selo('e1'), matching: find.text('Não verificável')), findsOneWidget);

      // Ícones distintos: a cor nunca é o único canal (WCAG 1.4.1).
      final icones = {
        for (final id in ['e3', 'e2', 'e1'])
          tester.widget<Icon>(find.descendant(of: selo(id), matching: find.byType(Icon))).icon,
      };
      expect(icones, hasLength(3));

      // Cores de TEXTO (tokens *OnSurface medidos contra o Card).
      Color? cor(String id, String texto) =>
          tester.widget<Text>(find.descendant(of: selo(id), matching: find.text(texto))).style?.color;
      expect(cor('e2', 'Adulterado?'), AdminColors.redOnSurface);
      expect(cor('e3', 'Íntegro'), AdminColors.green);
      expect(cor('e1', 'Não verificável'), isNot(AdminColors.green));
      expect(cor('e1', 'Não verificável'), isNot(AdminColors.redOnSurface));

      // Leitor de tela: o selo é anunciado por extenso.
      expect(tester.getSemantics(selo('e2')).label, startsWith('Selo do registro: possível adulteração'));
      expect(tester.getSemantics(selo('e3')).label, 'Selo do registro: íntegro');
      expect(tester.getSemantics(selo('e1')).label, startsWith('Selo do registro: não verificável'));
    });

    testWidgets('a tela não recalcula: linha "estranha" com selo verified do servidor aparece Íntegro', (tester) async {
      final mock = MockAdminDataSource(
        auditSeed: [
          _linha(7, seal: AuditRowSeal.verified, result: 'tampered_by_hand', resourceType: 'zz_desconhecido'),
          _linha(6, seal: AuditRowSeal.invalid),
        ],
        // Cadeia íntegra mesmo com uma linha inválida: a tela não deriva o
        // estado global das linhas, só mostra o que o servidor disse.
        chainStatus: _cadeia(AuditIntegrityState.verified),
      );
      await _abrir(tester, mock);
      await _rolarAte(tester, find.byKey(const Key('audit_seal_e7')));

      expect(find.descendant(of: find.byKey(const Key('audit_seal_e7')), matching: find.text('Íntegro')), findsOneWidget);
      expect(find.text('Cadeia íntegra'), findsOneWidget);
    });
  });

  group('estado da cadeia (D3/D9): só verified é sucesso', () {
    Future<void> abrirCom(WidgetTester tester, ChainStatus status) =>
        _abrir(tester, MockAdminDataSource(chainStatus: status));

    Finder painel() => find.byKey(const Key('audit_chain_status'));

    testWidgets('verified: "Cadeia íntegra", verde, com ícone', (tester) async {
      await abrirCom(tester, _cadeia(AuditIntegrityState.verified, checkedRows: 42));

      expect(find.descendant(of: painel(), matching: find.text('Cadeia íntegra')), findsOneWidget);
      expect(find.descendant(of: painel(), matching: find.textContaining('42 registros conferidos')), findsOneWidget);
      final titulo = tester.widget<Text>(find.text('Cadeia íntegra'));
      expect(titulo.style?.color, AdminColors.green);
      expect(find.descendant(of: painel(), matching: find.byType(Icon)), findsWidgets);
    });

    testWidgets('broken: falha de integridade, motivo em português, sem "Cadeia íntegra" nem verde', (tester) async {
      await abrirCom(
        tester,
        _cadeia(
          AuditIntegrityState.broken,
          firstBrokenSequence: 17,
          brokenInScope: true,
          reasonCode: AuditChainReason.hashMismatch,
        ),
      );

      expect(find.text('Cadeia íntegra'), findsNothing);
      expect(find.descendant(of: painel(), matching: find.text('Falha de integridade na cadeia')), findsOneWidget);
      expect(find.descendant(of: painel(), matching: find.textContaining('não confere com o selo')), findsOneWidget);
      expect(find.descendant(of: painel(), matching: find.textContaining('nº 17')), findsOneWidget);
      expect(find.descendant(of: painel(), matching: find.textContaining('atinge registros que você vê')), findsOneWidget);
      // Não afirma ataque/adulteração categórica (segredo trocado parece adulteração em massa).
      expect(find.descendant(of: painel(), matching: find.textContaining(RegExp('ataque|foi adulterad', caseSensitive: false))), findsNothing);
      final titulo = tester.widget<Text>(find.text('Falha de integridade na cadeia'));
      expect(titulo.style?.color, isNot(AdminColors.green));
      expect(titulo.style?.color, AdminColors.redOnSurface);
    });

    testWidgets('broken com brokenInScope nulo: texto neutro, nunca "fora da sua UBS"', (tester) async {
      await abrirCom(
        tester,
        _cadeia(AuditIntegrityState.broken, checkedRows: null, brokenInScope: null, reasonCode: AuditChainReason.linkBroken),
      );

      expect(find.descendant(of: painel(), matching: find.text('Falha de integridade na cadeia')), findsOneWidget);
      expect(find.textContaining('fora da sua UBS'), findsNothing);
      expect(find.descendant(of: painel(), matching: find.textContaining('Não foi informado')), findsOneWidget);
    });

    testWidgets('broken com brokenInScope false: texto neutro, nunca "fora da sua UBS"', (tester) async {
      await abrirCom(tester, _cadeia(AuditIntegrityState.broken, brokenInScope: false, reasonCode: AuditChainReason.sequenceGap));

      expect(find.textContaining('fora da sua UBS'), findsNothing);
      expect(find.descendant(of: painel(), matching: find.textContaining('Nenhum registro que você vê')), findsOneWidget);
    });

    testWidgets('unavailable: texto próprio que nega o sucesso', (tester) async {
      await abrirCom(tester, _cadeia(AuditIntegrityState.unavailable, checkedRows: null, reasonCode: AuditChainReason.databaseError));

      expect(find.text('Cadeia íntegra'), findsNothing);
      expect(find.descendant(of: painel(), matching: find.text('Verificação indisponível')), findsOneWidget);
      expect(find.descendant(of: painel(), matching: find.textContaining('não significa que a cadeia está íntegra')), findsOneWidget);
      expect(find.descendant(of: painel(), matching: find.textContaining('banco de dados')), findsOneWidget);
      expect(tester.widget<Text>(find.text('Verificação indisponível')).style?.color, isNot(AdminColors.green));
    });

    testWidgets('inconclusive: texto próprio, distinto de unavailable e de sucesso', (tester) async {
      await abrirCom(tester, _cadeia(AuditIntegrityState.inconclusive, reasonCode: AuditChainReason.timeBudget));

      expect(find.text('Cadeia íntegra'), findsNothing);
      expect(find.text('Verificação indisponível'), findsNothing);
      expect(find.descendant(of: painel(), matching: find.text('Verificação inconclusiva')), findsOneWidget);
      expect(find.descendant(of: painel(), matching: find.textContaining('não significa que a cadeia está íntegra')), findsOneWidget);
      expect(find.descendant(of: painel(), matching: find.textContaining('tempo limite')), findsOneWidget);
      expect(tester.widget<Text>(find.text('Verificação inconclusiva')).style?.color, isNot(AdminColors.green));
    });

    test('todo motivo tem texto em português, e nenhum repete outro', () {
      final textos = {for (final r in AuditChainReason.values) r: auditChainReasonText(r)};
      expect(textos.values.toSet(), hasLength(AuditChainReason.values.length));
      for (final t in textos.values) {
        expect(t.trim(), isNotEmpty);
        expect(t, isNot(contains('Mismatch')));
      }
      expect(textos[AuditChainReason.checkpointInvalid], contains('ponto de conferência'));
    });

    testWidgets('"Verificar novamente" mostra "Verificando…" e nunca o resultado antigo como atual', (tester) async {
      final fonte = _VerificacaoPendurada();
      await _abrir(tester, fonte);
      expect(find.text('Cadeia íntegra'), findsOneWidget);

      // Sem `pumpAndSettle`: o indicador gira enquanto a verificação não volta.
      await _rolarAte(tester, find.byKey(const Key('audit_chain_retry')));
      await tester.tap(find.byKey(const Key('audit_chain_retry')));
      await tester.pump();

      expect(find.descendant(of: painel(), matching: find.text('Verificando a integridade da trilha…')), findsOneWidget);
      expect(find.text('Cadeia íntegra'), findsNothing, reason: 'o resultado anterior não aparece como atual');
      expect(find.descendant(of: painel(), matching: find.textContaining('Resultado anterior: Cadeia íntegra')), findsOneWidget);
      expect(find.byKey(const Key('audit_chain_verifying')), findsOneWidget);

      fonte.segunda.complete(_cadeia(AuditIntegrityState.inconclusive, reasonCode: AuditChainReason.timeBudget));
      await tester.pumpAndSettle();
      expect(find.text('Verificação inconclusiva'), findsOneWidget);
      expect(find.textContaining('Resultado anterior'), findsNothing);
      expect(find.byKey(const Key('audit_chain_verifying')), findsNothing);
    });

    testWidgets('falha ao consultar o estado não vira sucesso e oferece verificar de novo', (tester) async {
      final mock = MockAdminDataSource()..chainStatusError = const AdminDataFailure('Não foi possível conectar ao servidor.');
      await _abrir(tester, mock);

      expect(find.text('Cadeia íntegra'), findsNothing);
      expect(find.descendant(of: painel(), matching: find.textContaining('Não foi possível verificar a integridade')), findsOneWidget);
      // A lista continua utilizável: a falha da verificação não esconde os registros.
      expect(find.text('view • audit_logs'), findsOneWidget);

      mock.chainStatusError = null;
      await _tocar(tester, find.byKey(const Key('audit_chain_retry')));
      expect(find.text('Cadeia íntegra'), findsOneWidget);
      expect(mock.verifyChainCalls, 2);
    });
  });

  group('filtros (D1) e cursor', () {
    List<AuditLogEntry> variados() => [
          _linha(6, userLabel: 'ACS-12 (ACS)', actionType: 'write', resourceType: 'visit'),
          _linha(5, userLabel: 'COORD-7 (Coordenador)', actionType: 'read', resourceType: 'admin_alerts'),
          _linha(4, userLabel: 'ACS-12 (ACS)', actionType: 'read', resourceType: 'patient_directory'),
          _linha(3, userLabel: 'Paciente #A18F', actionType: 'login', resourceType: 'session'),
          _linha(2, userLabel: 'ACS-30 (ACS)', actionType: 'login', resourceType: 'session'),
        ];

    testWidgets('aplicar um filtro manda o filtro e mostra só o que bate', (tester) async {
      final mock = MockAdminDataSource(auditSeed: variados());
      await _abrir(tester, mock);

      await _escolher(tester, 'audit_filter_role', 'ACS');
      await _tocar(tester, find.byKey(const Key('audit_filter_apply')));

      expect(mock.auditQueries.last.filter.actorRole, AuditActorRole.acs);
      expect(mock.auditQueries.last.beforeSequence, isNull);
      expect(find.byKey(const Key('audit_e6')), findsOneWidget);
      expect(find.byKey(const Key('audit_e4')), findsOneWidget);
      expect(find.byKey(const Key('audit_e2')), findsOneWidget);
      expect(find.byKey(const Key('audit_e5')), findsNothing);
      expect(find.byKey(const Key('audit_e3')), findsNothing);
    });

    testWidgets('combinar filtros é E lógico (papel + ação + matrícula)', (tester) async {
      final mock = MockAdminDataSource(auditSeed: variados());
      await _abrir(tester, mock);

      await _escolher(tester, 'audit_filter_role', 'ACS');
      await _escolher(tester, 'audit_filter_action', 'Leitura');
      await _digitar(tester, 'audit_filter_enrollment', 'ACS-12');
      await _tocar(tester, find.byKey(const Key('audit_filter_apply')));

      final filtro = mock.auditQueries.last.filter;
      expect(filtro.actorRole, AuditActorRole.acs);
      expect(filtro.actionType, 'read');
      expect(filtro.actorEnrollmentId, 'ACS-12');
      expect(find.byKey(const Key('audit_e4')), findsOneWidget);
      expect(find.byKey(const Key('audit_e6')), findsNothing);
      expect(find.byKey(const Key('audit_e2')), findsNothing);
    });

    testWidgets('"Limpar" volta ao filtro vazio e à lista inteira', (tester) async {
      final mock = MockAdminDataSource(auditSeed: variados());
      await _abrir(tester, mock);
      await _escolher(tester, 'audit_filter_role', 'Paciente');
      await _tocar(tester, find.byKey(const Key('audit_filter_apply')));
      expect(find.byKey(const Key('audit_e6')), findsNothing);

      await _tocar(tester, find.byKey(const Key('audit_filter_clear')));

      expect(mock.auditQueries.last.filter.isEmpty, isTrue);
      expect(mock.auditQueries.last.beforeSequence, isNull);
      await _rolarAte(tester, find.byKey(const Key('audit_e6')));
      expect(find.byKey(const Key('audit_e6')), findsOneWidget);
    });

    testWidgets('busca curta demais é recusada na tela, sem ir ao servidor', (tester) async {
      final mock = MockAdminDataSource(auditSeed: variados());
      await _abrir(tester, mock);
      final consultas = mock.auditQueries.length;

      await _digitar(tester, 'audit_filter_search', 'a');
      await _tocar(tester, find.byKey(const Key('audit_filter_apply')));

      expect(mock.auditQueries.length, consultas);
      expect(find.textContaining('de 2 a 64 caracteres'), findsOneWidget);
    });

    testWidgets('"Carregar mais" usa nextBeforeSequence e não duplica; mudar o filtro zera o cursor', (tester) async {
      final mock = MockAdminDataSource(auditSeed: [for (var s = 60; s >= 1; s--) _linha(s)]);
      await _abrir(tester, mock);

      // Primeira página: 50 linhas semeadas + o próprio acesso (sequence 61).
      expect(find.text('50 registros carregados'), findsOneWidget);
      final cursor = mock.auditQueries.last.nextBeforeSequence;
      expect(cursor, isNotNull);

      await _tocar(tester, find.byKey(const Key('audit_load_more')));

      expect(mock.auditQueries.last.beforeSequence, cursor);
      await _topo(tester);
      expect(find.text('61 registros carregados'), findsOneWidget);
      // Fim da trilha: sem cursor, sem botão.
      expect(find.byKey(const Key('audit_load_more')), findsNothing);

      await _escolher(tester, 'audit_filter_action', 'Leitura');
      await _tocar(tester, find.byKey(const Key('audit_filter_apply')));
      expect(mock.auditQueries.last.beforeSequence, isNull, reason: 'filtro novo começa do topo');
      expect(mock.auditQueries.last.filter.actionType, 'read');
    });

    testWidgets('página seguinte que repete um registro já mostrado não o duplica', (tester) async {
      final fonte = _PaginaSobreposta();
      await _abrir(tester, fonte);
      expect(find.text('2 registros carregados'), findsOneWidget);

      await _tocar(tester, find.byKey(const Key('audit_load_more')));

      expect(find.text('3 registros carregados'), findsOneWidget);
      expect(find.byKey(const Key('audit_e2')), findsOneWidget);
    });
  });

  group('período com início e fim (RF1)', () {
    /// Escolhe data e hora pelos seletores do Material (pt-BR), digitando.
    Future<void> instante(WidgetTester tester, String chave, String data, String hora, String minuto) async {
      await _abrirFiltros(tester);
      await _tocar(tester, find.byKey(Key(chave)));
      final campoDeData = find.descendant(of: find.byType(Dialog), matching: find.byType(TextField));
      await tester.enterText(campoDeData.first, data);
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      // A hora abre no relógio; o ícone de teclado troca para a digitação.
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();
      final camposDeHora = find.descendant(of: find.byType(Dialog), matching: find.byType(TextField));
      await tester.enterText(camposDeHora.at(0), hora);
      await tester.enterText(camposDeHora.at(1), minuto);
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
    }

    testWidgets('início e fim escolhidos vão ao filtro em UTC, e o rótulo mostra o instante', (tester) async {
      final mock = MockAdminDataSource();
      await _abrir(tester, mock);

      await instante(tester, 'audit_filter_from', '01/10/2026', '09', '30');
      await instante(tester, 'audit_filter_to', '05/10/2026', '18', '05');
      expect(find.text('Início: 01/10/2026 09:30'), findsOneWidget);
      expect(find.text('Fim: 05/10/2026 18:05'), findsOneWidget);
      await _tocar(tester, find.byKey(const Key('audit_filter_apply')));

      final filtro = mock.auditQueries.last.filter;
      expect(filtro.from, DateTime(2026, 10, 1, 9, 30).toUtc());
      expect(filtro.to, DateTime(2026, 10, 5, 18, 5).toUtc());
      expect(filtro.from!.isUtc && filtro.to!.isUtc, isTrue);
      expect(mock.auditQueries.last.beforeSequence, isNull);
    });

    testWidgets('só o início (ou só o fim) é uma consulta válida', (tester) async {
      final mock = MockAdminDataSource();
      await _abrir(tester, mock);

      await instante(tester, 'audit_filter_to', '05/10/2026', '18', '00');
      await _tocar(tester, find.byKey(const Key('audit_filter_apply')));
      expect(mock.auditQueries.last.filter.from, isNull);
      expect(mock.auditQueries.last.filter.to, DateTime(2026, 10, 5, 18).toUtc());

      await _tocar(tester, find.byKey(const Key('audit_filter_to_clear')));
      await instante(tester, 'audit_filter_from', '01/10/2026', '08', '00');
      await _tocar(tester, find.byKey(const Key('audit_filter_apply')));
      expect(mock.auditQueries.last.filter.from, DateTime(2026, 10, 1, 8).toUtc());
      expect(mock.auditQueries.last.filter.to, isNull);
    });

    testWidgets('fim igual ou anterior ao início: erro em português e nenhuma consulta', (tester) async {
      final mock = MockAdminDataSource();
      await _abrir(tester, mock);
      await instante(tester, 'audit_filter_from', '05/10/2026', '10', '00');
      await instante(tester, 'audit_filter_to', '05/10/2026', '10', '00');
      final consultas = mock.auditQueries.length;

      await _tocar(tester, find.byKey(const Key('audit_filter_apply')));

      expect(mock.auditQueries.length, consultas);
      expect(find.text('O início do período deve ser anterior ao fim.'), findsOneWidget);
    });

    testWidgets('janela maior que 366 dias: erro em português e nenhuma consulta', (tester) async {
      final mock = MockAdminDataSource();
      await _abrir(tester, mock);
      await instante(tester, 'audit_filter_from', '01/01/2025', '00', '00');
      await instante(tester, 'audit_filter_to', '03/01/2026', '00', '00');
      final consultas = mock.auditQueries.length;

      await _tocar(tester, find.byKey(const Key('audit_filter_apply')));

      expect(mock.auditQueries.length, consultas);
      expect(find.text('O período é de no máximo 366 dias.'), findsOneWidget);
    });

    testWidgets('"Limpar" zera início e fim', (tester) async {
      final mock = MockAdminDataSource();
      await _abrir(tester, mock);
      await instante(tester, 'audit_filter_from', '01/10/2026', '09', '30');
      await instante(tester, 'audit_filter_to', '05/10/2026', '18', '05');
      await _tocar(tester, find.byKey(const Key('audit_filter_apply')));

      await _tocar(tester, find.byKey(const Key('audit_filter_clear')));

      expect(mock.auditQueries.last.filter.from, isNull);
      expect(mock.auditQueries.last.filter.to, isNull);
      expect(find.text('Início: não definido'), findsOneWidget);
      expect(find.text('Fim: não definido'), findsOneWidget);
    });

    testWidgets('mudar o período zera o cursor', (tester) async {
      final mock = MockAdminDataSource(auditSeed: [for (var s = 60; s >= 1; s--) _linha(s)]);
      await _abrir(tester, mock);
      await _tocar(tester, find.byKey(const Key('audit_load_more')));
      expect(mock.auditQueries.last.beforeSequence, isNotNull);

      await instante(tester, 'audit_filter_from', '01/10/2026', '00', '00');
      await _tocar(tester, find.byKey(const Key('audit_filter_apply')));

      expect(mock.auditQueries.last.beforeSequence, isNull);
      expect(mock.auditQueries.last.filter.from, DateTime(2026, 10, 1).toUtc());
    });

    testWidgets('atalho "Últimos 7 dias" preenche só o início, a partir do relógio', (tester) async {
      final mock = MockAdminDataSource();
      await _abrir(tester, mock);
      await _abrirFiltros(tester);
      final antes = DateTime.now();
      await _tocar(tester, find.byKey(const Key('audit_filter_preset_7d')));
      await _tocar(tester, find.byKey(const Key('audit_filter_apply')));

      final de = mock.auditQueries.last.filter.from!;
      expect(de.isUtc, isTrue);
      expect(antes.subtract(const Duration(days: 7)).difference(de).inMinutes.abs(), lessThanOrEqualTo(1));
      expect(mock.auditQueries.last.filter.to, isNull);
    });
  });

  group('estados da lista', () {
    testWidgets('carregando mostra o indicador da lista', (tester) async {
      final fonte = _ListaPendurada();
      await abrirBackoffice(tester, tamanho: const Size(1024, 900), dataSource: fonte);
      await tester.tap(find.text('Auditoria').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const Key('audit_loading')), findsOneWidget);
      fonte.pagina.complete(const AuditLogPage(items: []));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('audit_loading')), findsNothing);
    });

    testWidgets('vazio com filtro diz que nada bate, sem fingir erro', (tester) async {
      final mock = MockAdminDataSource();
      await _abrir(tester, mock);
      await _digitar(tester, 'audit_filter_search', 'nada-bate');
      await _tocar(tester, find.byKey(const Key('audit_filter_apply')));

      expect(find.text('Nenhum registro encontrado para estes filtros.'), findsOneWidget);
      expect(find.text('Tentar novamente'), findsNothing);
    });

    testWidgets('erro na lista mostra a falha e "Tentar novamente" recupera', (tester) async {
      final fonte = FailingAdminDataSource(inner: MockAdminDataSource())..failNextAuditLogs = true;
      await _abrir(tester, fonte);

      expect(find.text('Não foi possível carregar os logs de auditoria.'), findsOneWidget);
      await _tocar(tester, find.text('Tentar novamente'));
      expect(find.text('view • audit_logs'), findsOneWidget);
    });

    testWidgets('registro do próprio acesso falhando: nada da trilha aparece, e o retry recupera', (tester) async {
      final fonte = FailingAdminDataSource(inner: MockAdminDataSource())..failNextRecordAccess = true;
      await _abrir(tester, fonte);

      expect(find.text('Não foi possível registrar o acesso a esta tela.'), findsOneWidget);
      expect(find.byKey(const Key('audit_chain_status')), findsNothing);
      expect(find.text('Logs de auditoria'), findsNothing);
      expect(find.byKey(const Key('audit_count')), findsNothing);

      await tester.tap(find.text('Tentar novamente'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('audit_chain_status')), findsOneWidget);
      expect(find.text('view • audit_logs'), findsOneWidget);
    });

    testWidgets('AdminSessionExpired na verificação da cadeia volta ao login', (tester) async {
      final fonte = FailingAdminDataSource(inner: MockAdminDataSource())..failNextChainStatusWith = const AdminSessionExpired();
      await _abrir(tester, fonte);

      expect(find.text('Sessão encerrada. Entre novamente.'), findsOneWidget);
    });
  });

  group('layout (WCAG 1.4.4/1.4.10/2.5.5)', () {
    ChainStatus quebrada() => _cadeia(
          AuditIntegrityState.broken,
          firstBrokenSequence: 123456,
          brokenInScope: null,
          reasonCode: AuditChainReason.checkpointInvalid,
        );

    List<AuditLogEntry> tresSelos() => [
          _linha(3, seal: AuditRowSeal.invalid, userLabel: 'COORD-0000000000007 (Coordenador)'),
          _linha(2, seal: AuditRowSeal.unverifiable),
          _linha(1),
        ];

    for (final largura in const [320.0, 360.0]) {
      for (final escala in const [1.0, 2.0]) {
        testWidgets('sem estouro em ${largura.toInt()}dp com fonte a ${(escala * 100).toInt()}%', (tester) async {
          final mock = MockAdminDataSource(auditSeed: tresSelos(), chainStatus: quebrada());
          await abrirBackoffice(tester, tamanho: Size(largura, 800), escalaDeFonte: escala, dataSource: mock);
          await irPara(tester, 'Auditoria');
          final rotulo = 'auditoria ${largura.toInt()}dp ${(escala * 100).toInt()}%';
          await percorrerTelaInteira(tester, rotulo, lista: rolagemDaAuditoria());

          // Filtros abertos, com a mensagem de erro do filtro na tela.
          await _topo(tester);
          await _digitar(tester, 'audit_filter_search', 'a');
          await _tocar(tester, find.byKey(const Key('audit_filter_apply')));
          expect(find.byKey(const Key('audit_filter_error')), findsOneWidget);
          await _topo(tester);
          await percorrerTelaInteira(tester, '$rotulo, filtros abertos', lista: rolagemDaAuditoria());
        });
      }
    }

    for (final largura in const [320.0, 360.0]) {
      testWidgets('seletores de data e hora e o período preenchido não estouram em ${largura.toInt()}dp a 200%', (tester) async {
        final mock = MockAdminDataSource();
        await abrirBackoffice(tester, tamanho: Size(largura, 800), escalaDeFonte: 2.0, dataSource: mock);
        await irPara(tester, 'Auditoria');
        await _abrirFiltros(tester);

        await _tocar(tester, find.byKey(const Key('audit_filter_from')));
        esperarSemEstouroDeLayout(tester, 'seletor de data ${largura.toInt()}dp');
        await tester.enterText(find.descendant(of: find.byType(Dialog), matching: find.byType(TextField)).first, '01/10/2026');
        await tester.tap(find.text('Confirmar'));
        await tester.pumpAndSettle();
        esperarSemEstouroDeLayout(tester, 'seletor de hora ${largura.toInt()}dp');
        expect(find.text('Hora do início'), findsOneWidget);
        await tester.tap(find.text('Confirmar'));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('audit_filter_from_clear')), findsOneWidget);
        await _topo(tester);
        await percorrerTelaInteira(tester, 'período preenchido ${largura.toInt()}dp', lista: rolagemDaAuditoria());
      });
    }

    testWidgets('botões novos e o cabeçalho dos filtros têm alvo de pelo menos 48dp', (tester) async {
      final mock = MockAdminDataSource(auditSeed: [for (var s = 60; s >= 1; s--) _linha(s)]);
      await _abrir(tester, mock, tamanho: const Size(360, 800));
      await _abrirFiltros(tester);

      for (final chave in [
        'audit_chain_retry',
        'audit_filter_from',
        'audit_filter_to',
        'audit_filter_preset_24h',
        'audit_filter_preset_7d',
        'audit_filter_preset_30d',
        'audit_filter_apply',
        'audit_filter_clear',
        'audit_load_more',
      ]) {
        final alvo = find.byKey(Key(chave));
        await _rolarAte(tester, alvo);
        expect(tester.getSize(alvo).height, greaterThanOrEqualTo(48), reason: chave);
        final tinta = find.descendant(of: alvo, matching: find.byType(Material)).first;
        expect(tester.getSize(tinta).height, greaterThanOrEqualTo(48), reason: '$chave (altura pintada)');
      }
      // O botão que limpa um extremo do período só existe preenchido.
      await _topo(tester);
      await _tocar(tester, find.byKey(const Key('audit_filter_preset_24h')));
      final limparInicio = find.byKey(const Key('audit_filter_from_clear'));
      await _rolarAte(tester, limparInicio);
      expect(tester.getSize(limparInicio).height, greaterThanOrEqualTo(48), reason: 'limpar início');
      expect(tester.getSize(limparInicio).width, greaterThanOrEqualTo(48), reason: 'limpar início');
      final cabecalho = find.descendant(of: find.byKey(const Key('audit_filters_toggle')), matching: find.byType(ListTile));
      await _rolarAte(tester, cabecalho);
      expect(tester.getSize(cabecalho).height, greaterThanOrEqualTo(48), reason: 'cabeçalho dos filtros');
    });
  });
}

/// Duas páginas que se sobrepõem em um registro (sequence 2): a tela não pode
/// mostrar o mesmo registro duas vezes.
class _PaginaSobreposta extends MockAdminDataSource {
  @override
  Future<AuditLogPage> fetchAuditLogs({
    AuditLogFilter filter = const AuditLogFilter(),
    int limit = 50,
    int? beforeSequence,
  }) async {
    if (beforeSequence == null) {
      return AuditLogPage(items: [_linha(3), _linha(2)], nextBeforeSequence: 2);
    }
    return AuditLogPage(items: [_linha(2), _linha(1)]);
  }
}

/// Lista que só responde quando o teste completa [pagina].
class _ListaPendurada extends MockAdminDataSource {
  final pagina = Completer<AuditLogPage>();

  @override
  Future<AuditLogPage> fetchAuditLogs({
    AuditLogFilter filter = const AuditLogFilter(),
    int limit = 50,
    int? beforeSequence,
  }) =>
      pagina.future;
}

/// Primeira verificação íntegra; a segunda só responde quando o teste completa [segunda].
class _VerificacaoPendurada extends MockAdminDataSource {
  final segunda = Completer<ChainStatus>();
  var _chamadas = 0;

  @override
  Future<ChainStatus> verifyAuditChain() {
    _chamadas++;
    if (_chamadas == 1) return Future.value(_cadeia(AuditIntegrityState.verified));
    return segunda.future;
  }
}
