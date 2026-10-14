import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/app/admin_theme.dart';
import 'package:sinalacs_admin/core/data/admin_data_source.dart';
import 'package:sinalacs_admin/core/data/mock_admin_data_source.dart';

import 'support/contrast.dart';
import 'support/fake_admin_auth.dart';
import 'support/layout_harness.dart';

/// Acessibilidade, contraste e layout em celular das telas Avisos/Termos (#46).
///
/// Dados sintéticos; nenhum texto jurídico real. As quatro frentes seguem os
/// padrões de `touch_targets_test.dart` (alvo E tinta ≥ 48dp),
/// `text_scale_test.dart` (percorrer a tela inteira), `contrast_tokens_test.dart`
/// (4,5:1 medido no widget, contra a superfície onde de fato renderiza) e a
/// regra WCAG 1.4.1 (o selo nunca depende só de cor).
const _texto = '[TEXTO PLACEHOLDER]';
const _alvo = 48.0;

/// Os termos usam datas relativas ao relógio real porque o app do teste roda
/// com `DateTime.now`.
DateTime _emDias(int dias) {
  final h = DateTime.now().add(Duration(days: dias));
  return DateTime(h.year, h.month, h.day);
}

class _Dados extends MockAdminDataSource {
  _Dados({this.vazio = false, this.falhaNoAgendamento, this.falhaNoRascunho});

  final bool vazio;
  final Object? falhaNoAgendamento;
  final Object? falhaNoRascunho;

  @override
  Future<List<NoticeHistoryItem>> fetchNoticeHistory({String? microAreaId, int limit = 50, int offset = 0}) async {
    if (vazio) return const [];
    NoticeHistoryItem item(NoticeStatus s, {int? rec, int? ace, String? motivo}) => NoticeHistoryItem(
          id: 'av-${s.name}',
          microAreaId: 'ma-1',
          microAreaName: 'Microárea 01',
          audience: NoticeAudience.chronic,
          title: 'Aviso de vacinação em ${s.name}',
          status: s,
          scheduledFor: DateTime(2026, 10, 15, 8, 30),
          createdByLabel: 'ADM-001',
          recipients: rec,
          accepted: ace,
          failureReason: motivo,
        );
    return [
      item(NoticeStatus.pending),
      item(NoticeStatus.sending),
      item(NoticeStatus.sent, rec: 120, ace: 118),
      item(NoticeStatus.unknown),
      item(NoticeStatus.failed, motivo: 'Provedor de push indisponível'),
      item(NoticeStatus.cancelled),
    ];
  }

  @override
  Future<List<TermsVersionSummary>> fetchTermsVersions() async {
    if (vazio) return const [];
    TermsVersionSummary termo(String id, int dias, {bool revisada = false, bool publicada = false}) => TermsVersionSummary(
          id: id,
          version: '2026.$id',
          summary: _texto,
          effectiveFrom: _emDias(dias),
          createdAt: _emDias(-1),
          legallyReviewedAt: revisada || publicada ? _emDias(-1) : null,
          publishedAt: publicada ? _emDias(-1) : null,
        );
    return [
      termo('rascunho', 30),
      termo('revisada', 30, revisada: true),
      termo('esgotada', 5, revisada: true),
      termo('publicada', 40, publicada: true),
    ];
  }

  @override
  Future<String> scheduleNotice({
    required String microAreaId,
    required NoticeAudience audience,
    required String title,
    required String message,
    required DateTime scheduledFor,
  }) async {
    if (falhaNoAgendamento != null) throw falhaNoAgendamento!;
    return super.scheduleNotice(
      microAreaId: microAreaId,
      audience: audience,
      title: title,
      message: message,
      scheduledFor: scheduledFor,
    );
  }

  @override
  Future<TermsVersionSummary> draftTermsVersion({
    required String version,
    required String summary,
    required DateTime effectiveFrom,
  }) async {
    if (falhaNoRascunho != null) throw falhaNoRascunho!;
    return super.draftTermsVersion(version: version, summary: summary, effectiveFrom: effectiveFrom);
  }
}

Future<void> _abrirAvisos(
  WidgetTester tester, {
  Size tamanho = const Size(360, 800),
  double escala = 1.0,
  String papel = 'admin',
  AdminDataSource? dados,
}) async {
  await abrirBackoffice(
    tester,
    tamanho: tamanho,
    escalaDeFonte: escala,
    dataSource: dados ?? _Dados(),
    auth: FakeAdminAuth()..role = papel,
  );
  await irPara(tester, 'Avisos');
}

Future<void> _abrirTermos(
  WidgetTester tester, {
  Size tamanho = const Size(360, 800),
  double escala = 1.0,
  AdminDataSource? dados,
}) async {
  await _abrirAvisos(tester, tamanho: tamanho, escala: escala, dados: dados);
  await tester.tap(find.byKey(const Key('notices_tab_terms')));
  await tester.pumpAndSettle();
}

Future<void> _rolarAte(WidgetTester tester, Finder alvo) async {
  if (alvo.evaluate().isEmpty) {
    // A lista é preguiçosa e pode estar além do alvo: tenta descer e, se não
    // houver mais o que descer, sobe.
    try {
      await tester.scrollUntilVisible(alvo, 200, scrollable: find.byType(Scrollable).last, maxScrolls: 60);
    } on StateError {
      await tester.scrollUntilVisible(alvo, -200, scrollable: find.byType(Scrollable).last, maxScrolls: 60);
    }
  }
  await tester.ensureVisible(alvo);
  await tester.pumpAndSettle();
}

Future<void> _tocar(WidgetTester tester, Finder alvo) async {
  await _rolarAte(tester, alvo);
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

/// Altura da TINTA do botão — ver o cabeçalho de `touch_targets_test.dart`.
double _alturaPintada(WidgetTester tester, Finder botao) =>
    tester.getSize(find.descendant(of: botao, matching: find.byType(Material)).first).height;

void _conferirAlvo(WidgetTester tester, Finder botao, String rotulo) {
  expect(botao, findsOneWidget, reason: rotulo);
  final tamanho = tester.getSize(botao);
  expect(tamanho.height, greaterThanOrEqualTo(_alvo), reason: '$rotulo (alvo de toque)');
  expect(tamanho.width, greaterThanOrEqualTo(_alvo), reason: '$rotulo (largura do alvo)');
  expect(_alturaPintada(tester, botao), greaterThanOrEqualTo(_alvo), reason: '$rotulo (altura pintada)');
}

/// Cor efetiva (já resolvida pelo tema) com que [alvo] pinta o texto/ícone.
Color _corPintada(WidgetTester tester, Finder alvo) {
  final rich = find.descendant(of: alvo, matching: find.byType(RichText)).first;
  final cor = tester.renderObject<RenderParagraph>(rich).text.style?.color;
  expect(cor, isNotNull, reason: 'sem cor resolvida em $alvo');
  return cor!;
}

/// Cor da superfície que de fato fica atrás de [alvo]: o `Material` com cor
/// mais próximo (Card ou AlertDialog) — medido, não presumido.
Color _superficie(WidgetTester tester, Finder alvo) {
  final material = find.ancestor(of: alvo, matching: find.byWidgetPredicate((w) => w is Material && w.color != null));
  expect(material, findsWidgets, reason: 'sem superfície atrás de $alvo');
  return tester.widget<Material>(material.first).color!;
}

void _conferirContraste(WidgetTester tester, Finder alvo, String rotulo, {Color? superficieEsperada}) {
  expect(alvo, findsWidgets, reason: rotulo);
  final primeiro = alvo.first;
  final fundo = _superficie(tester, primeiro);
  if (superficieEsperada != null) expect(fundo, superficieEsperada, reason: '$rotulo: superfície inesperada');
  final razao = contrastOn(_corPintada(tester, primeiro), fundo);
  expect(razao, greaterThanOrEqualTo(4.5), reason: '$rotulo: ${razao.toStringAsFixed(2)}:1');
}

const _avisosPorStatus = <NoticeStatus, (String, IconData)>{
  NoticeStatus.pending: ('Agendado', Icons.schedule),
  NoticeStatus.sending: ('Enviando', Icons.send_outlined),
  NoticeStatus.sent: ('Enviado', Icons.check_circle_outline),
  NoticeStatus.unknown: ('Resultado desconhecido — confira antes de reenviar', Icons.help_outline),
  NoticeStatus.failed: ('Falhou', Icons.error_outline),
  NoticeStatus.cancelled: ('Cancelado', Icons.block),
};

const _termosPorEstado = <String, (String, IconData)>{
  'rascunho': ('Rascunho', Icons.edit_note),
  'revisada': ('Revisada', Icons.fact_check_outlined),
  'publicada': ('Publicada', Icons.check_circle_outline),
};

void main() {
  group('alvos de toque >= 48dp (altura pintada e alvo)', () {
    testWidgets('aba Avisos: Novo aviso, Cancelar do cartão e diálogo de cancelamento', (tester) async {
      await _abrirAvisos(tester);

      _conferirAlvo(tester, find.byKey(const Key('notice_new_button')), 'Novo aviso');
      final cancelar = find.byKey(const Key('notice_cancel_av-pending'));
      await _rolarAte(tester, cancelar);
      _conferirAlvo(tester, cancelar, 'Cancelar (cartão pendente)');

      await tester.tap(cancelar);
      await tester.pumpAndSettle();
      _conferirAlvo(tester, find.widgetWithText(TextButton, 'Voltar'), 'Voltar (diálogo de cancelar aviso)');
      _conferirAlvo(tester, find.byKey(const Key('notice_cancel_confirm')), 'Cancelar aviso (confirmar)');
    });

    testWidgets('formulário de aviso: Agendar (habilitado e desabilitado), Cancelar, data e hora', (tester) async {
      await _abrirAvisos(tester);
      await _tocar(tester, find.byKey(const Key('notice_new_button')));

      _conferirAlvo(tester, find.byKey(const Key('notice_form_cancel')), 'Cancelar (formulário de aviso)');
      expect(tester.widget<FilledButton>(find.byKey(const Key('notice_submit'))).onPressed, isNull);
      _conferirAlvo(tester, find.byKey(const Key('notice_submit')), 'Agendar (desabilitado)');
      _conferirAlvo(tester, find.byKey(const Key('notice_date')), 'Data');
      _conferirAlvo(tester, find.byKey(const Key('notice_time')), 'Hora');

      await tester.enterText(find.byKey(const Key('notice_title')), 'Título');
      await tester.enterText(find.byKey(const Key('notice_message')), _texto);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(find.byKey(const Key('notice_submit'))).onPressed, isNotNull);
      _conferirAlvo(tester, find.byKey(const Key('notice_submit')), 'Agendar (habilitado)');
      // O público é um SegmentedButton: cada segmento é alvo de toque.
      for (final rotulo in const ['Todos', 'Só crônicos']) {
        final segmento = find.ancestor(of: find.text(rotulo), matching: find.byType(TextButton)).first;
        _conferirAlvo(tester, segmento, 'segmento "$rotulo"');
      }
    });

    testWidgets('aba Termos: Nova versão, Marcar como revisado, Publicar (ambos os estados)', (tester) async {
      await _abrirTermos(tester);

      _conferirAlvo(tester, find.byKey(const Key('terms_new_button')), 'Nova versão');
      final revisar = find.byKey(const Key('terms_review_rascunho'));
      await _rolarAte(tester, revisar);
      _conferirAlvo(tester, revisar, 'Marcar como revisado');

      final desabilitado = find.byKey(const Key('terms_publish_rascunho'));
      expect(tester.widget<FilledButton>(desabilitado).onPressed, isNull);
      _conferirAlvo(tester, desabilitado, 'Publicar (desabilitado)');

      final habilitado = find.byKey(const Key('terms_publish_revisada'));
      await _rolarAte(tester, habilitado);
      expect(tester.widget<FilledButton>(habilitado).onPressed, isNotNull);
      _conferirAlvo(tester, habilitado, 'Publicar (habilitado)');
    });

    testWidgets('aba Termos: diálogos de revisão e de publicação', (tester) async {
      await _abrirTermos(tester);

      await _tocar(tester, find.byKey(const Key('terms_review_rascunho')));
      _conferirAlvo(tester, find.widgetWithText(TextButton, 'Voltar'), 'Voltar (diálogo de revisão)');
      _conferirAlvo(tester, find.byKey(const Key('terms_review_confirm')), 'Confirmar revisão');
      await tester.tap(find.widgetWithText(TextButton, 'Voltar'));
      await tester.pumpAndSettle();

      await _tocar(tester, find.byKey(const Key('terms_publish_revisada')));
      _conferirAlvo(tester, find.widgetWithText(TextButton, 'Voltar'), 'Voltar (diálogo de publicação)');
      _conferirAlvo(tester, find.byKey(const Key('terms_publish_confirm')), 'Publicar (confirmar)');
    });

    testWidgets('formulário de termos: Criar rascunho (ambos os estados), Cancelar e data', (tester) async {
      await _abrirTermos(tester);
      await _tocar(tester, find.byKey(const Key('terms_new_button')));

      _conferirAlvo(tester, find.byKey(const Key('terms_form_cancel')), 'Cancelar (formulário de termos)');
      expect(tester.widget<FilledButton>(find.byKey(const Key('terms_submit'))).onPressed, isNull);
      _conferirAlvo(tester, find.byKey(const Key('terms_submit')), 'Criar rascunho (desabilitado)');
      _conferirAlvo(tester, find.byKey(const Key('terms_date')), 'Vigência');

      await tester.enterText(find.byKey(const Key('terms_version')), '2026.9');
      await tester.enterText(find.byKey(const Key('terms_summary')), _texto);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(find.byKey(const Key('terms_submit'))).onPressed, isNotNull);
      _conferirAlvo(tester, find.byKey(const Key('terms_submit')), 'Criar rascunho (habilitado)');
    });
  });

  group('sem estouro de layout em celular', () {
    for (final tamanho in const [Size(360, 640), Size(320, 568)]) {
      for (final escala in const [1.0, 2.0]) {
        final cenario = '${tamanho.width.toInt()}x${tamanho.height.toInt()}, fonte a ${(escala * 100).toInt()}%';

        testWidgets('Avisos (admin): histórico com 6 status e vazio, $cenario', (tester) async {
          await _abrirAvisos(tester, tamanho: tamanho, escala: escala);
          expect(find.byKey(const Key('notice_row_av-unknown')), findsNothing, reason: 'lista preguiçosa: ainda não construído');
          await percorrerTelaInteira(tester, 'Avisos cheio ($cenario)');
          for (final status in NoticeStatus.values) {
            await _rolarAte(tester, find.byKey(Key('notice_row_av-${status.name}')));
            esperarCaberNaLargura(tester, find.byKey(Key('notice_row_av-${status.name}')), 'cartão ${status.name} ($cenario)');
          }
        });

        testWidgets('Avisos (admin): vazio, $cenario', (tester) async {
          await _abrirAvisos(tester, tamanho: tamanho, escala: escala, dados: _Dados(vazio: true));
          await _rolarAte(tester, find.text('Nenhum aviso agendado ou enviado ainda.'));
          expect(find.text('Nenhum aviso agendado ou enviado ainda.'), findsOneWidget);
          await percorrerTelaInteira(tester, 'Avisos vazio ($cenario)');
        });

        testWidgets('Avisos (coordenador), $cenario', (tester) async {
          await _abrirAvisos(tester, tamanho: tamanho, escala: escala, papel: 'coordinator');
          expect(find.byKey(const Key('notices_tab_terms')), findsNothing);
          await percorrerTelaInteira(tester, 'Avisos coordenador ($cenario)');
        });

        testWidgets('formulário de aviso (com erro), $cenario', (tester) async {
          await _abrirAvisos(
            tester,
            tamanho: tamanho,
            escala: escala,
            dados: _Dados(falhaNoAgendamento: const AdminValidationFailure('O horário do aviso deve ser pelo menos 1 minuto à frente.')),
          );
          await _tocar(tester, find.byKey(const Key('notice_new_button')));
          final rolagem = find.descendant(of: find.byType(AlertDialog), matching: find.byType(Scrollable)).first;
          await percorrerTelaInteira(tester, 'formulário de aviso ($cenario)', lista: rolagem);

          await tester.enterText(find.byKey(const Key('notice_title')), 'Título');
          await tester.enterText(find.byKey(const Key('notice_message')), _texto);
          await tester.pumpAndSettle();
          final agendar = find.byKey(const Key('notice_submit'));
          await tester.ensureVisible(agendar);
          await tester.tap(agendar);
          await tester.pumpAndSettle();
          expect(find.textContaining('pelo menos 1 minuto'), findsOneWidget);
          esperarSemEstouroDeLayout(tester, 'formulário de aviso com erro ($cenario)');
          await tester.drag(rolagem, const Offset(0, -2000));
          await tester.pumpAndSettle();
          esperarSemEstouroDeLayout(tester, 'formulário de aviso com erro, rodapé ($cenario)');
        });

        testWidgets('Termos (admin): rascunho, revisada, prazo esgotado e publicada, $cenario', (tester) async {
          await _abrirTermos(tester, tamanho: tamanho, escala: escala);
          await percorrerTelaInteira(tester, 'Termos ($cenario)');
          for (final id in const ['rascunho', 'revisada', 'esgotada', 'publicada']) {
            await _rolarAte(tester, find.byKey(Key('terms_row_$id')));
            esperarCaberNaLargura(tester, find.byKey(Key('terms_row_$id')), 'cartão $id ($cenario)');
          }
        });

        testWidgets('Termos (admin): vazio, $cenario', (tester) async {
          await _abrirTermos(tester, tamanho: tamanho, escala: escala, dados: _Dados(vazio: true));
          await _rolarAte(tester, find.text('Nenhuma versão de termos cadastrada.'));
          expect(find.text('Nenhuma versão de termos cadastrada.'), findsOneWidget);
          await percorrerTelaInteira(tester, 'Termos vazio ($cenario)');
        });

        testWidgets('formulário de termos (com erro), $cenario', (tester) async {
          await _abrirTermos(
            tester,
            tamanho: tamanho,
            escala: escala,
            dados: _Dados(falhaNoRascunho: const AdminValidationFailure('Já existe uma versão com este número.')),
          );
          await _tocar(tester, find.byKey(const Key('terms_new_button')));
          final rolagem = find.descendant(of: find.byType(AlertDialog), matching: find.byType(Scrollable)).first;
          await percorrerTelaInteira(tester, 'formulário de termos ($cenario)', lista: rolagem);

          await tester.enterText(find.byKey(const Key('terms_version')), '2026.9');
          await tester.enterText(find.byKey(const Key('terms_summary')), _texto);
          await tester.pumpAndSettle();
          final criar = find.byKey(const Key('terms_submit'));
          await tester.ensureVisible(criar);
          await tester.tap(criar);
          await tester.pumpAndSettle();
          expect(find.textContaining('Já existe uma versão'), findsOneWidget);
          esperarSemEstouroDeLayout(tester, 'formulário de termos com erro ($cenario)');
          await tester.drag(rolagem, const Offset(0, -2000));
          await tester.pumpAndSettle();
          esperarSemEstouroDeLayout(tester, 'formulário de termos com erro, rodapé ($cenario)');
        });
      }
    }
  });

  group('contraste >= 4,5:1 sobre a superfície onde renderiza', () {
    testWidgets('selos de status dos avisos (texto e ícone) sobre o Card', (tester) async {
      await _abrirAvisos(tester);
      for (final entrada in _avisosPorStatus.entries) {
        final (rotulo, icone) = entrada.value;
        final cartao = find.byKey(Key('notice_row_av-${entrada.key.name}'));
        await _rolarAte(tester, cartao);
        _conferirContraste(tester, find.descendant(of: cartao, matching: find.text(rotulo)), 'texto do selo ${entrada.key.name}',
            superficieEsperada: AdminColors.surfaceRaised);
        _conferirContraste(tester, find.descendant(of: cartao, matching: find.byIcon(icone)), 'ícone do selo ${entrada.key.name}',
            superficieEsperada: AdminColors.surfaceRaised);
      }
    });

    testWidgets('selos de estado dos termos, aviso de revisão e prazo esgotado sobre o Card', (tester) async {
      await _abrirTermos(tester);
      for (final entrada in _termosPorEstado.entries) {
        final (rotulo, icone) = entrada.value;
        final cartao = find.byKey(Key('terms_row_${entrada.key}'));
        await _rolarAte(tester, cartao);
        _conferirContraste(tester, find.descendant(of: cartao, matching: find.text(rotulo)), 'texto do selo ${entrada.key}',
            superficieEsperada: AdminColors.surfaceRaised);
        _conferirContraste(tester, find.descendant(of: cartao, matching: find.byIcon(icone)), 'ícone do selo ${entrada.key}',
            superficieEsperada: AdminColors.surfaceRaised);
      }
      final rascunho = find.byKey(const Key('terms_row_rascunho'));
      await _rolarAte(tester, rascunho);
      _conferirContraste(tester, find.descendant(of: rascunho, matching: find.text('Aguardando revisão jurídica')),
          'Aguardando revisão jurídica', superficieEsperada: AdminColors.surfaceRaised);
      final esgotada = find.byKey(const Key('terms_row_esgotada'));
      await _rolarAte(tester, esgotada);
      _conferirContraste(tester, find.descendant(of: esgotada, matching: find.textContaining('Prazo de 15 dias esgotado')),
          'prazo esgotado', superficieEsperada: AdminColors.surfaceRaised);
    });

    testWidgets('erro, ajuda e textos do formulário de aviso sobre o diálogo', (tester) async {
      await _abrirAvisos(
        tester,
        dados: _Dados(falhaNoAgendamento: const AdminValidationFailure('Mensagem de erro sintética.')),
      );
      await _tocar(tester, find.byKey(const Key('notice_new_button')));
      await tester.enterText(find.byKey(const Key('notice_title')), 'Título');
      await tester.enterText(find.byKey(const Key('notice_message')), _texto);
      await tester.pumpAndSettle();
      await _tocar(tester, find.byKey(const Key('notice_submit')));

      final dialogo = find.byType(AlertDialog);
      _conferirContraste(tester, find.descendant(of: dialogo, matching: find.text('Mensagem de erro sintética.')), 'texto de erro');
      _conferirContraste(tester, find.descendant(of: dialogo, matching: find.byIcon(Icons.error_outline)), 'ícone de erro');
      _conferirContraste(
          tester, find.descendant(of: dialogo, matching: find.text('O texto do aviso não é gravado na trilha de auditoria.')), 'texto de ajuda');
      _conferirContraste(tester, find.descendant(of: dialogo, matching: find.textContaining('Envio em ')).last, 'texto de envio');
    });

    testWidgets('erro, ajuda e textos do formulário de termos sobre o diálogo', (tester) async {
      await _abrirTermos(
        tester,
        dados: _Dados(falhaNoRascunho: const AdminValidationFailure('Mensagem de erro sintética.')),
      );
      await _tocar(tester, find.byKey(const Key('terms_new_button')));
      await tester.enterText(find.byKey(const Key('terms_version')), '2026.9');
      await tester.enterText(find.byKey(const Key('terms_summary')), _texto);
      await tester.pumpAndSettle();
      await _tocar(tester, find.byKey(const Key('terms_submit')));

      final dialogo = find.byType(AlertDialog);
      _conferirContraste(tester, find.descendant(of: dialogo, matching: find.text('Mensagem de erro sintética.')), 'texto de erro');
      _conferirContraste(tester, find.descendant(of: dialogo, matching: find.byIcon(Icons.error_outline)), 'ícone de erro');
      _conferirContraste(tester, find.descendant(of: dialogo, matching: find.text('A vigência exige 15 dias de antecedência para publicar.')),
          'texto de ajuda da vigência');
      // helperText do campo Resumo: renderizado no diálogo, fora do preenchimento.
      _conferirContraste(
          tester, find.descendant(of: dialogo, matching: find.text('Resumo público exibido no cartão do paciente.')), 'helperText do Resumo');
    });
  });

  group('semântica', () {
    testWidgets('não há botão só-ícone sem tooltip nas duas abas', (tester) async {
      await _abrirTermos(tester);
      for (final botao in tester.widgetList<IconButton>(find.byType(IconButton))) {
        expect(botao.tooltip, isNotNull, reason: 'IconButton sem tooltip');
      }
      await tester.tap(find.byKey(const Key('notices_tab_history')));
      await tester.pumpAndSettle();
      for (final botao in tester.widgetList<IconButton>(find.byType(IconButton))) {
        expect(botao.tooltip, isNotNull, reason: 'IconButton sem tooltip');
      }
    });

    testWidgets('selos de aviso têm ícone E texto (não dependem só de cor)', (tester) async {
      await _abrirAvisos(tester);
      for (final entrada in _avisosPorStatus.entries) {
        final (rotulo, icone) = entrada.value;
        final cartao = find.byKey(Key('notice_row_av-${entrada.key.name}'));
        await _rolarAte(tester, cartao);
        expect(find.descendant(of: cartao, matching: find.text(rotulo)), findsOneWidget, reason: 'texto ${entrada.key.name}');
        expect(find.descendant(of: cartao, matching: find.byIcon(icone)), findsOneWidget, reason: 'ícone ${entrada.key.name}');
      }
    });

    testWidgets('selos de termos têm ícone E texto (não dependem só de cor)', (tester) async {
      await _abrirTermos(tester);
      for (final entrada in _termosPorEstado.entries) {
        final (rotulo, icone) = entrada.value;
        final cartao = find.byKey(Key('terms_row_${entrada.key}'));
        await _rolarAte(tester, cartao);
        expect(find.descendant(of: cartao, matching: find.text(rotulo)), findsOneWidget, reason: 'texto ${entrada.key}');
        expect(find.descendant(of: cartao, matching: find.byIcon(icone)), findsOneWidget, reason: 'ícone ${entrada.key}');
      }
    });

    testWidgets('campos dos formulários têm labelText', (tester) async {
      await _abrirAvisos(tester);
      await _tocar(tester, find.byKey(const Key('notice_new_button')));
      for (final (chave, rotulo) in const [('notice_title', 'Título'), ('notice_message', 'Mensagem')]) {
        expect(tester.widget<TextField>(find.byKey(Key(chave))).decoration?.labelText, rotulo, reason: chave);
      }
      expect(find.text('Microárea'), findsWidgets);
      await tester.tap(find.byKey(const Key('notice_form_cancel')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('notices_tab_terms')));
      await tester.pumpAndSettle();
      await _tocar(tester, find.byKey(const Key('terms_new_button')));
      for (final (chave, rotulo) in const [('terms_version', 'Versão'), ('terms_summary', 'Resumo')]) {
        expect(tester.widget<TextField>(find.byKey(Key(chave))).decoration?.labelText, rotulo, reason: chave);
      }
    });

    testWidgets('Publicar desabilitado expõe o motivo ao leitor de tela, sem duplicar o anúncio', (tester) async {
      final semantica = tester.ensureSemantics();
      await _abrirTermos(tester);

      for (final (id, motivo) in const [
        ('rascunho', 'Aguardando revisão jurídica'),
        ('esgotada', 'Prazo de 15 dias esgotado'),
      ]) {
        final publicar = find.byKey(Key('terms_publish_$id'));
        await _rolarAte(tester, publicar);
        final no = tester.getSemantics(publicar);
        final dados = no.getSemanticsData();
        expect(dados.label, contains('Publicar'), reason: id);
        expect(dados.label, contains(motivo), reason: '$id: o motivo precisa estar no nó do botão');
        expect(dados.flagsCollection.isEnabled, ui.Tristate.isFalse, reason: id);
        // Sem duplicar: o texto visível do motivo não vira um segundo nó.
        expect(
          find.semantics.byLabel(RegExp(motivo)).evaluate().length,
          1,
          reason: '$id: motivo anunciado mais de uma vez',
        );
      }

      final habilitado = find.byKey(const Key('terms_publish_revisada'));
      await _rolarAte(tester, habilitado);
      expect(tester.getSemantics(habilitado).getSemanticsData().label, 'Publicar');
      semantica.dispose();
    });
  });
}
