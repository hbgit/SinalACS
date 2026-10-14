import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/core/data/admin_data_source.dart';
import 'package:sinalacs_admin/core/data/mock_admin_data_source.dart';

import 'support/fake_admin_auth.dart';
import 'support/layout_harness.dart';

/// Exportação da trilha de auditoria pela tela (#45, Task 11 — RF4). Dados
/// sintéticos. O servidor é a autoridade (só admin exporta, período
/// obrigatório, teto de linhas); a tela só não oferece o que vai ser recusado
/// e mostra cada recusa com texto fixo.
final _agora = DateTime.utc(2026, 10, 13, 12);

const _csvSintetico =
    'sequence,timestamp_utc,autor,papel_autor,acao,recurso,rotulo_recurso,resultado,selo\r\n'
    '3,2026-10-02T10:00:00Z,ADM-001,admin,read,admin_alerts,,success,verified\r\n';

const _sha = '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08';

AuditExportResult _resultado({AuditIntegrityState chainState = AuditIntegrityState.verified}) => AuditExportResult(
      fileName: 'auditoria_20261001T0930Z_20261005T1805Z.csv',
      csv: _csvSintetico,
      rowCount: 5,
      firstSequence: 3,
      lastSequence: 7,
      contentSha256: _sha,
      chainState: chainState,
      generatedAt: _agora,
    );

Future<void> _abrir(
  WidgetTester tester,
  AdminDataSource dataSource, {
  String role = 'admin',
  Size tamanho = const Size(1024, 900),
  double escalaDeFonte = 1.0,
}) async {
  await abrirBackoffice(
    tester,
    tamanho: tamanho,
    escalaDeFonte: escalaDeFonte,
    dataSource: dataSource,
    auth: FakeAdminAuth()..role = role,
  );
  await irPara(tester, 'Auditoria');
}

Future<void> _topo(WidgetTester tester) async {
  await tester.drag(rolagemDaAuditoria(), const Offset(0, 20000));
  await tester.pumpAndSettle();
}

Future<void> _rolarAte(WidgetTester tester, Finder alvo) async {
  if (alvo.evaluate().isEmpty) await _topo(tester);
  if (alvo.evaluate().isEmpty) {
    await tester.scrollUntilVisible(alvo, 300, scrollable: rolagemDaAuditoria());
  }
  await tester.ensureVisible(alvo);
  await tester.pumpAndSettle();
}

Future<void> _tocar(WidgetTester tester, Finder alvo) async {
  await _rolarAte(tester, alvo);
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

Future<void> _abrirFiltros(WidgetTester tester) async {
  if (find.byKey(const Key('audit_filter_apply')).evaluate().isNotEmpty) return;
  await _tocar(tester, find.text('Filtros'));
}

/// Escolhe data e hora pelos seletores do Material (pt-BR), digitando.
Future<void> _instante(WidgetTester tester, String chave, String data, String hora, String minuto) async {
  await _abrirFiltros(tester);
  await _tocar(tester, find.byKey(Key(chave)));
  final campoDeData = find.descendant(of: find.byType(Dialog), matching: find.byType(TextField));
  await tester.enterText(campoDeData.first, data);
  await tester.tap(find.text('Confirmar'));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.keyboard_outlined));
  await tester.pumpAndSettle();
  final camposDeHora = find.descendant(of: find.byType(Dialog), matching: find.byType(TextField));
  await tester.enterText(camposDeHora.at(0), hora);
  await tester.enterText(camposDeHora.at(1), minuto);
  await tester.tap(find.text('Confirmar'));
  await tester.pumpAndSettle();
}

/// Aplica o período de 01/10/2026 09:30 a 05/10/2026 18:05 (hora local).
Future<void> _aplicarPeriodo(WidgetTester tester) async {
  await _instante(tester, 'audit_filter_from', '01/10/2026', '09', '30');
  await _instante(tester, 'audit_filter_to', '05/10/2026', '18', '05');
  await _tocar(tester, find.byKey(const Key('audit_filter_apply')));
}

final _botao = find.byKey(const Key('audit_export_button'));
final _confirmar = find.byKey(const Key('audit_export_confirm'));
final _cancelar = find.byKey(const Key('audit_export_cancel'));
final _cartao = find.byKey(const Key('audit_export_result'));

bool _habilitado(WidgetTester tester) => tester.widget<ButtonStyleButton>(_botao).onPressed != null;

/// Abre a confirmação e confirma.
Future<void> _exportar(WidgetTester tester) async {
  await _tocar(tester, _botao);
  await tester.tap(_confirmar);
  await tester.pumpAndSettle();
}

/// Rola até o cartão de resultado e devolve os textos de dentro dele.
Future<String> _textoDoCartao(WidgetTester tester) async {
  await _rolarAte(tester, _cartao);
  final textos = tester
      .widgetList<Text>(find.descendant(of: _cartao, matching: find.byType(Text)))
      .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '');
  final selecionaveis = tester
      .widgetList<SelectableText>(find.descendant(of: _cartao, matching: find.byType(SelectableText)))
      .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '');
  return [...textos, ...selecionaveis].join('\n');
}

void main() {
  group('quem vê o botão', () {
    testWidgets('coordenador não vê "Exportar" em lugar nenhum da tela', (tester) async {
      final mock = MockAdminDataSource();
      await _abrir(tester, mock, role: 'coordinator');
      await _abrirFiltros(tester);
      await _topo(tester);

      // Percorre a tela inteira: o botão não pode estar só abaixo da dobra.
      var visto = _botao.evaluate().isNotEmpty;
      final lista = rolagemDaAuditoria();
      for (var i = 0; i < 40 && !visto; i++) {
        final pos = tester.state<ScrollableState>(lista).position;
        if (pos.pixels >= pos.maxScrollExtent) break;
        await tester.drag(lista, const Offset(0, -300));
        await tester.pumpAndSettle();
        visto = _botao.evaluate().isNotEmpty;
      }
      expect(visto, isFalse);
      expect(find.text('Exportar CSV', skipOffstage: false), findsNothing);
      expect(mock.exportCalls, 0);
    });

    testWidgets('administrador vê "Exportar CSV"', (tester) async {
      await _abrir(tester, MockAdminDataSource());
      await _rolarAte(tester, _botao);
      expect(find.text('Exportar CSV'), findsOneWidget);
    });
  });

  group('período obrigatório', () {
    testWidgets('sem período aplicado o botão fica desabilitado e diz por quê', (tester) async {
      await _abrir(tester, MockAdminDataSource());
      await _rolarAte(tester, _botao);

      expect(_habilitado(tester), isFalse);
      expect(find.byKey(const Key('audit_export_hint')), findsOneWidget);
      expect(find.text('Para exportar, aplique um período com início e fim.'), findsOneWidget);
    });

    testWidgets('só o início aplicado não basta; início e fim habilitam', (tester) async {
      await _abrir(tester, MockAdminDataSource());
      await _instante(tester, 'audit_filter_from', '01/10/2026', '09', '30');
      await _tocar(tester, find.byKey(const Key('audit_filter_apply')));
      await _rolarAte(tester, _botao);
      expect(_habilitado(tester), isFalse);

      await _instante(tester, 'audit_filter_to', '05/10/2026', '18', '05');
      // Escolhido mas não aplicado: a exportação segue o filtro APLICADO.
      await _rolarAte(tester, _botao);
      expect(_habilitado(tester), isFalse);

      await _tocar(tester, find.byKey(const Key('audit_filter_apply')));
      await _rolarAte(tester, _botao);
      expect(_habilitado(tester), isTrue);
      expect(find.byKey(const Key('audit_export_hint')), findsNothing);
    });
  });

  group('confirmação', () {
    testWidgets('pede confirmação dizendo que fica registrado; cancelar não chama o servidor', (tester) async {
      final mock = MockAdminDataSource();
      await _abrir(tester, mock);
      await _aplicarPeriodo(tester);

      await _tocar(tester, _botao);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('Será registrado na trilha de auditoria'), findsOneWidget);

      await tester.tap(_cancelar);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(mock.exportCalls, 0);
    });

    testWidgets('confirmar exporta exatamente o filtro aplicado', (tester) async {
      final mock = MockAdminDataSource()..exportResult = _resultado();
      await _abrir(tester, mock);
      await _aplicarPeriodo(tester);
      final aplicado = mock.auditQueries.last.filter;

      await _exportar(tester);

      expect(mock.exportCalls, 1);
      expect(mock.lastExportFilter, aplicado);
      expect(mock.lastExportFilter!.from, DateTime(2026, 10, 1, 9, 30).toUtc());
      expect(mock.lastExportFilter!.to, DateTime(2026, 10, 5, 18, 5).toUtc());
    });
  });

  group('sucesso', () {
    late List<MethodCall> chamadasDaPlataforma;

    setUp(() {
      chamadasDaPlataforma = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          chamadasDaPlataforma.add(call);
          return null;
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    testWidgets('mostra contagem, intervalo de sequence, SHA-256, e "Copiar CSV" copia o conteúdo', (tester) async {
      final mock = MockAdminDataSource()..exportResult = _resultado();
      await _abrir(tester, mock);
      await _aplicarPeriodo(tester);
      await _exportar(tester);

      final texto = await _textoDoCartao(tester);
      expect(texto, contains('5 registros exportados'));
      expect(texto, contains('nº 3 a nº 7'));
      expect(texto, contains(_sha));
      expect(texto, contains('auditoria_20261001T0930Z_20261005T1805Z.csv'));
      // O conteúdo do CSV nunca é desenhado na tela.
      expect(texto, isNot(contains('ADM-001,admin')));

      await _tocar(tester, find.byKey(const Key('audit_export_copy')));
      final copias = chamadasDaPlataforma.where((c) => c.method == 'Clipboard.setData').toList();
      expect(copias, hasLength(1));
      expect((copias.single.arguments as Map)['text'], _csvSintetico);
      expect(find.text('CSV copiado para a área de transferência.'), findsOneWidget);
    });

    testWidgets('cadeia verified: "íntegra" no momento da exportação', (tester) async {
      final mock = MockAdminDataSource()..exportResult = _resultado();
      await _abrir(tester, mock);
      await _aplicarPeriodo(tester);
      await _exportar(tester);

      expect(await _textoDoCartao(tester), contains('Cadeia íntegra no momento da exportação.'));
    });

    for (final (estado, esperado) in const [
      (AuditIntegrityState.broken, 'Atenção: a cadeia apresentou falha de integridade no momento da exportação.'),
      (AuditIntegrityState.unavailable, 'Atenção: a verificação da cadeia estava indisponível no momento da exportação.'),
      (AuditIntegrityState.inconclusive, 'Atenção: a verificação da cadeia foi inconclusiva no momento da exportação.'),
    ]) {
      testWidgets('cadeia ${estado.name}: texto de atenção próprio, nunca "íntegra"', (tester) async {
        final mock = MockAdminDataSource()..exportResult = _resultado(chainState: estado);
        await _abrir(tester, mock);
        await _aplicarPeriodo(tester);
        await _exportar(tester);

        final texto = await _textoDoCartao(tester);
        expect(texto, contains(esperado));
        expect(texto.toLowerCase(), isNot(contains('íntegra')));
        expect(find.descendant(of: _cartao, matching: find.byIcon(Icons.verified_outlined)), findsNothing);
      });
    }

    testWidgets('recorte vazio: zero registros, sem intervalo inventado', (tester) async {
      final mock = MockAdminDataSource()
        ..exportResult = AuditExportResult(
          fileName: 'auditoria_vazia.csv',
          csv: 'sequence,timestamp_utc\r\n',
          rowCount: 0,
          contentSha256: _sha,
          chainState: AuditIntegrityState.verified,
          generatedAt: _agora,
        );
      await _abrir(tester, mock);
      await _aplicarPeriodo(tester);
      await _exportar(tester);

      final texto = await _textoDoCartao(tester);
      expect(texto, contains('Nenhum registro no período'));
      expect(texto, isNot(contains('nº null')));
    });

    testWidgets('"Fechar" limpa o resultado; trocar de tela também não deixa o CSV para trás', (tester) async {
      final mock = MockAdminDataSource()..exportResult = _resultado();
      await _abrir(tester, mock);
      await _aplicarPeriodo(tester);
      await _exportar(tester);
      await _rolarAte(tester, _cartao);

      await _tocar(tester, find.byKey(const Key('audit_export_close')));
      expect(find.byKey(const Key('audit_export_result'), skipOffstage: false), findsNothing);

      // De novo, e sai da tela sem fechar: voltando, nada da exportação.
      await _exportar(tester);
      await _rolarAte(tester, _cartao);
      await irPara(tester, 'Indicadores');
      await irPara(tester, 'Auditoria');
      expect(find.byKey(const Key('audit_export_result'), skipOffstage: false), findsNothing);
      expect(find.textContaining(_sha, skipOffstage: false), findsNothing);
    });

    testWidgets('mudar o filtro aplicado descarta o resultado anterior', (tester) async {
      final mock = MockAdminDataSource()..exportResult = _resultado();
      await _abrir(tester, mock);
      await _aplicarPeriodo(tester);
      await _exportar(tester);
      await _rolarAte(tester, _cartao);

      await _tocar(tester, find.byKey(const Key('audit_filter_clear')));
      expect(find.byKey(const Key('audit_export_result'), skipOffstage: false), findsNothing);
    });
  });

  group('falhas com texto fixo', () {
    testWidgets('teto de linhas: "Há registros demais; estreite o período." sem "Tentar novamente"', (tester) async {
      final mock = MockAdminDataSource()
        ..exportError = const AuditExportFailure(AuditExportFailureKind.tooManyRows);
      await _abrir(tester, mock);
      await _aplicarPeriodo(tester);
      await _exportar(tester);

      await _rolarAte(tester, find.byKey(const Key('audit_export_error')));
      expect(find.text('Há registros demais; estreite o período.'), findsOneWidget);
      expect(find.byKey(const Key('audit_export_retry')), findsNothing);
      expect(_cartao, findsNothing);
    });

    testWidgets('recusa de permissão: texto fixo, sem motivo e sem "Tentar novamente"', (tester) async {
      final mock = MockAdminDataSource()
        ..exportError = const AuditExportFailure(AuditExportFailureKind.forbidden);
      await _abrir(tester, mock);
      await _aplicarPeriodo(tester);
      await _exportar(tester);

      await _rolarAte(tester, find.byKey(const Key('audit_export_error')));
      expect(find.text('Você não tem permissão para exportar a trilha de auditoria.'), findsOneWidget);
      expect(find.byKey(const Key('audit_export_retry')), findsNothing);
    });

    testWidgets('falha do servidor ou de rede: texto fixo e "Tentar novamente" (com nova confirmação)', (tester) async {
      final mock = MockAdminDataSource()
        ..exportError = const AuditExportFailure(AuditExportFailureKind.failed)
        ..exportResult = _resultado();
      await _abrir(tester, mock);
      await _aplicarPeriodo(tester);
      await _exportar(tester);

      await _rolarAte(tester, find.byKey(const Key('audit_export_error')));
      expect(find.text('Não foi possível gerar a exportação. Tente novamente.'), findsOneWidget);
      expect(mock.exportCalls, 1);

      mock.exportError = null;
      await _tocar(tester, find.byKey(const Key('audit_export_retry')));
      expect(find.byType(AlertDialog), findsOneWidget, reason: 'tentar de novo pede confirmação de novo');
      expect(mock.exportCalls, 1);
      await tester.tap(_confirmar);
      await tester.pumpAndSettle();

      expect(mock.exportCalls, 2);
      expect(find.byKey(const Key('audit_export_error'), skipOffstage: false), findsNothing);
      expect(await _textoDoCartao(tester), contains('5 registros exportados'));
    });

    testWidgets('sessão vencida volta ao login', (tester) async {
      final mock = MockAdminDataSource()..exportError = const AdminSessionExpired();
      await _abrir(tester, mock);
      await _aplicarPeriodo(tester);
      await _exportar(tester);

      expect(find.text('Sessão encerrada. Entre novamente.'), findsOneWidget);
    });
  });

  group('em curso', () {
    testWidgets('toque duplo não gera duas exportações: o botão desabilita enquanto em curso', (tester) async {
      final portao = Completer<void>();
      final mock = MockAdminDataSource()
        ..exportResult = _resultado()
        ..exportGate = portao;
      await _abrir(tester, mock);
      await _aplicarPeriodo(tester);
      await _rolarAte(tester, _botao);

      // Dois toques seguidos no botão: um diálogo só.
      await tester.tap(_botao);
      await tester.tap(_botao, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      // Dois toques no confirmar: o segundo cai no vazio (diálogo já fechando).
      await tester.tap(_confirmar);
      await tester.tap(_confirmar, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // O indicador gira sem parar: nada de `pumpAndSettle` enquanto em curso.
      expect(_habilitado(tester), isFalse);
      expect(find.byKey(const Key('audit_export_progress')), findsOneWidget);
      await tester.tap(_botao, warnIfMissed: false);
      await tester.pump();
      expect(find.byType(AlertDialog), findsNothing);

      portao.complete();
      await tester.pumpAndSettle();
      expect(mock.exportCalls, 1);
      await _rolarAte(tester, _botao);
      expect(_habilitado(tester), isTrue);
    });
  });

  group('layout (WCAG 1.4.4/1.4.10/2.5.5)', () {
    for (final largura in const [320.0, 360.0]) {
      testWidgets('cartão de exportação e resultado sem estouro em ${largura.toInt()}dp a 200%', (tester) async {
        final mock = MockAdminDataSource()..exportResult = _resultado(chainState: AuditIntegrityState.unavailable);
        await _abrir(tester, mock, tamanho: Size(largura, 800), escalaDeFonte: 2.0);
        await _topo(tester);
        await percorrerTelaInteira(tester, 'exportação sem período ${largura.toInt()}dp', lista: rolagemDaAuditoria());

        // O período é escolhido numa janela mais larga a 100%: o modo de
        // digitação do seletor de hora do Material não cabe em 320dp nem a 200%
        // (defeito do Material já medido na Task 8, fora desta tela). 600dp fica
        // abaixo do `AdminBreakpoints.rail` de propósito: cruzar o breakpoint
        // remonta a tela e descartaria o estado. A confirmação, a seção e o
        // resultado são medidos de volta na janela estreita a 200%.
        redimensionar(tester, const Size(600, 900));
        await tester.pumpAndSettle();
        await _topo(tester);
        await _aplicarPeriodo(tester);
        await _tocar(tester, _botao);
        redimensionar(tester, Size(largura, 800), escalaDeFonte: 2.0);
        await tester.pumpAndSettle();
        esperarSemEstouroDeLayout(tester, 'confirmação ${largura.toInt()}dp');
        await tester.ensureVisible(_confirmar);
        await tester.pumpAndSettle();
        await tester.tap(_confirmar);
        await tester.pumpAndSettle();
        await _rolarAte(tester, _cartao);
        esperarCaberNaLargura(tester, _cartao, 'cartão de resultado ${largura.toInt()}dp');
        await _topo(tester);
        await percorrerTelaInteira(tester, 'exportação concluída ${largura.toInt()}dp', lista: rolagemDaAuditoria());
      });
    }

    testWidgets('botões da exportação têm alvo de pelo menos 48dp, inclusive no diálogo', (tester) async {
      final mock = MockAdminDataSource()
        ..exportError = const AuditExportFailure(AuditExportFailureKind.failed)
        ..exportResult = _resultado();
      await _abrir(tester, mock, tamanho: const Size(360, 800));
      await _aplicarPeriodo(tester);

      void medir(Finder alvo, String nome) {
        expect(tester.getSize(alvo).height, greaterThanOrEqualTo(48), reason: nome);
        final tinta = find.descendant(of: alvo, matching: find.byType(Material)).first;
        expect(tester.getSize(tinta).height, greaterThanOrEqualTo(48), reason: '$nome (altura pintada)');
      }

      await _rolarAte(tester, _botao);
      medir(_botao, 'exportar');
      await tester.tap(_botao);
      await tester.pumpAndSettle();
      medir(_confirmar, 'confirmar');
      medir(_cancelar, 'cancelar');
      await tester.tap(_confirmar);
      await tester.pumpAndSettle();

      final retry = find.byKey(const Key('audit_export_retry'));
      await _rolarAte(tester, retry);
      medir(retry, 'tentar novamente');
      mock.exportError = null;
      await tester.tap(retry);
      await tester.pumpAndSettle();
      await tester.tap(_confirmar);
      await tester.pumpAndSettle();

      for (final chave in ['audit_export_copy', 'audit_export_close']) {
        final alvo = find.byKey(Key(chave));
        await _rolarAte(tester, alvo);
        medir(alvo, chave);
      }
    });

    testWidgets('estado da cadeia e erro chegam ao leitor de tela (liveRegion)', (tester) async {
      final handle = tester.ensureSemantics();
      final mock = MockAdminDataSource()..exportResult = _resultado(chainState: AuditIntegrityState.broken);
      await _abrir(tester, mock);
      await _aplicarPeriodo(tester);
      await _exportar(tester);
      await _rolarAte(tester, _cartao);

      final resumo = find.byKey(const Key('audit_export_summary'));
      expect(
        tester.getSemantics(resumo),
        isSemantics(isLiveRegion: true, label: '5 registros exportados'),
      );
      handle.dispose();
    });
  });
}
