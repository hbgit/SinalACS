import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinalacs_acs/app/app.dart';
import 'package:sinalacs_acs/app/educational_notice_screens.dart';
import 'package:sinalacs_acs/core/legal/educational_notice.dart';

import 'support/fakes.dart';
import 'support/layout_harness.dart';

/// Loja cuja leitura falha: o aviso tem de aparecer mesmo assim.
class _FailingStore implements EducationalNoticeStore {
  @override
  bool? get knownAcknowledged => null;
  @override
  Future<bool> isAcknowledged() async => throw StateError('prefs indisponível');
  @override
  Future<void> acknowledge() async => throw StateError('prefs indisponível');
}

/// Seção "Aviso educativo" do escopo, a fonte do texto canônico (RF21).
String _secaoDoAvisoNoEscopo() {
  // Monorepo: o CI do app faz checkout do repositório inteiro. CRLF de um
  // checkout no Windows não pode reprovar o texto.
  final escopo = File('../../spec/escopo_projeto.md').readAsStringSync().replaceAll('\r\n', '\n');
  final inicio = escopo.indexOf('## Aviso educativo');
  expect(inicio, isNonNegative, reason: 'seção "Aviso educativo" não encontrada no escopo');
  final fim = escopo.indexOf('<a id=', inicio);
  return escopo.substring(inicio, fim < 0 ? escopo.length : fim);
}

Widget _app(EducationalNoticeStore store) => SinalAcsApp(
      backend: FakeAcsBackend(),
      feedBuilder: (queue) => FakeAlertFeed(queue),
      educationalNotice: store,
    );

Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await assentar(tester);
  await tester.tap(finder);
  await assentar(tester);
}

final _login = find.byKey(const Key('matricula_field'));

void main() {
  group('texto canônico', () {
    test('as duas versões são cópia literal de spec/escopo_projeto.md', () {
      // Regra do escopo: "copiada literalmente, sem paráfrase". Qualquer
      // diferença, inclusive de pontuação, reprova aqui.
      final secao = _secaoDoAvisoNoEscopo();
      expect(secao, contains('> $educationalNoticeLong\n'));
      expect(secao, contains('> $educationalNoticeShort\n'));
    });

    test('o texto é o mesmo do app do paciente', () {
      // Não há pacote compartilhado entre os apps: as duas cópias não podem
      // divergir uma da outra.
      String semLog(String path) => File(path)
          .readAsStringSync()
          .replaceAll('\r\n', '\n')
          .replaceAll(RegExp(r"name: 'sinalacs\.\w+\.educational_notice'"), '');
      final acs = semLog('lib/core/legal/educational_notice.dart');
      final paciente = semLog('../patient/lib/core/legal/educational_notice.dart');
      String constante(String fonte, String nome) =>
          RegExp('const $nome =([^;]+);').firstMatch(fonte)!.group(1)!;
      for (final nome in ['educationalNoticeLong', 'educationalNoticeShort', 'educationalNoticeVersion']) {
        expect(constante(acs, nome), constante(paciente, nome), reason: nome);
      }
    });
  });

  group('primeira abertura', () {
    testWidgets('mostra o aviso curto e só segue para o login depois de "Entendi"', (tester) async {
      final store = MemoryEducationalNoticeStore();
      await tester.pumpWidget(_app(store));
      await assentar(tester);

      expect(find.byKey(const Key('first_open_notice')), findsOneWidget);
      expect(find.text(educationalNoticeShort), findsOneWidget);
      // Nada do app por trás do aviso: nem o login, nem o pedido de biometria.
      expect(_login, findsNothing);

      await _tapKey(tester, 'educational_notice_confirm');

      expect(find.byKey(const Key('first_open_notice')), findsNothing);
      expect(_login, findsOneWidget);
      expect(store.acknowledgeCalls, 1);
      expect(store.acknowledged, isTrue);
    });

    testWidgets('já confirmado, abre direto no login', (tester) async {
      await tester.pumpWidget(_app(MemoryEducationalNoticeStore(acknowledged: true)));
      await assentar(tester);

      expect(find.byKey(const Key('first_open_notice')), findsNothing);
      expect(_login, findsOneWidget);
    });

    testWidgets('leitura da confirmação falhou: o aviso aparece', (tester) async {
      await tester.pumpWidget(_app(_FailingStore()));
      await assentar(tester);

      expect(find.byKey(const Key('first_open_notice')), findsOneWidget);
      // Gravar também falha, e mesmo assim o agente não fica preso no aviso.
      await _tapKey(tester, 'educational_notice_confirm');
      expect(_login, findsOneWidget);
    });

    testWidgets('"Ler o aviso completo" abre "Sobre" e volta ao aviso', (tester) async {
      await tester.pumpWidget(_app(MemoryEducationalNoticeStore()));
      await assentar(tester);

      await _tapKey(tester, 'educational_notice_about');
      expect(find.byType(AboutScreen), findsOneWidget);

      await tester.pageBack();
      await assentar(tester);
      expect(find.byKey(const Key('first_open_notice')), findsOneWidget);
    });

    testWidgets('a 200% de fonte, o aviso cabe e o botão continua alcançável', (tester) async {
      redimensionar(tester, const Size(360, 640), escalaDeFonte: 2.0);
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final store = MemoryEducationalNoticeStore();
      await tester.pumpWidget(_app(store));
      await assentar(tester);

      esperarSemEstouro(tester, 'aviso da primeira abertura');
      await _tapKey(tester, 'educational_notice_confirm');
      expect(store.acknowledged, isTrue);
    });
  });

  group('tela "Sobre"', () {
    testWidgets('mostra o aviso longo literal', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: AboutScreen()));

      expect(find.text(educationalNoticeLong), findsOneWidget);
    });

    testWidgets('abre pelo menu "Mais" do painel', (tester) async {
      await abrirPainel(tester, tamanho: const Size(800, 1200));

      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Mais')));
      await assentar(tester);
      await _tapKey(tester, 'more_about');

      expect(find.byType(AboutScreen), findsOneWidget);
      expect(find.text(educationalNoticeLong), findsOneWidget);
    });

    testWidgets('a 200% de fonte, "Sobre" não estoura', (tester) async {
      redimensionar(tester, const Size(360, 640), escalaDeFonte: 2.0);
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(const MaterialApp(home: AboutScreen()));
      await percorrerTelaInteira(tester, 'Sobre');
    });
  });

  group('SharedPreferencesEducationalNoticeStore', () {
    test('sem registro, não confirmado; confirmar grava a versão atual', () async {
      SharedPreferences.setMockInitialValues({});
      final store = SharedPreferencesEducationalNoticeStore();
      expect(store.knownAcknowledged, isNull);
      expect(await store.isAcknowledged(), isFalse);

      await store.acknowledge();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(SharedPreferencesEducationalNoticeStore.prefsKey), educationalNoticeVersion);
      expect(await SharedPreferencesEducationalNoticeStore().isAcknowledged(), isTrue);
    });

    test('confirmação de outra versão do texto não vale: o aviso volta', () async {
      SharedPreferences.setMockInitialValues({
        SharedPreferencesEducationalNoticeStore.prefsKey: '2000-01-01',
      });
      expect(await SharedPreferencesEducationalNoticeStore().isAcknowledged(), isFalse);
    });

    test('em produção, a loja padrão é a de shared_preferences e nada em lib/ a troca', () {
      // O `flutter_test_config.dart` troca o padrão nos testes, então o valor de
      // fábrica (o que vale no aparelho) só pode ser conferido na fonte.
      final declaracao = File('lib/core/legal/educational_notice.dart').readAsStringSync();
      expect(
        declaracao.replaceAll(RegExp(r'\s+'), ' '),
        contains('educationalNoticeStoreFactory = SharedPreferencesEducationalNoticeStore.new;'),
      );
      final atribuicoes = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => RegExp(r'educationalNoticeStoreFactory\s*=[^=]').hasMatch(f.readAsStringSync()))
          .toList();
      expect(atribuicoes, hasLength(1), reason: 'só a declaração pode atribuir: ${atribuicoes.map((f) => f.path)}');
    });
  });
}
