import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinalacs_patient/app/app.dart';
import 'package:sinalacs_patient/app/educational_notice_screens.dart';
import 'package:sinalacs_patient/core/legal/educational_notice.dart';

import 'support/fake_patient_backend.dart';

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

Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('texto canônico', () {
    test('as duas versões são cópia literal de spec/escopo_projeto.md', () {
      // Regra do escopo: "copiada literalmente, sem paráfrase". Qualquer
      // diferença, inclusive de pontuação, reprova aqui.
      final secao = _secaoDoAvisoNoEscopo();
      expect(secao, contains('> $educationalNoticeLong\n'));
      expect(secao, contains('> $educationalNoticeShort\n'));
    });
  });

  group('primeira abertura', () {
    testWidgets('mostra o aviso curto e só segue para o login depois de "Entendi"', (tester) async {
      final store = MemoryEducationalNoticeStore();
      await tester.pumpWidget(SinalAcsApp(backend: FakePatientBackend(), educationalNotice: store));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('first_open_notice')), findsOneWidget);
      expect(find.text(educationalNoticeShort), findsOneWidget);
      // Nada do app por trás do aviso: nem o login.
      expect(find.byType(PatientLoginScreen), findsNothing);

      await _tapKey(tester, 'educational_notice_confirm');

      expect(find.byKey(const Key('first_open_notice')), findsNothing);
      expect(find.byType(PatientLoginScreen), findsOneWidget);
      expect(store.acknowledgeCalls, 1);
      expect(store.acknowledged, isTrue);
    });

    testWidgets('já confirmado, abre direto no login', (tester) async {
      await tester.pumpWidget(SinalAcsApp(
        backend: FakePatientBackend(),
        educationalNotice: MemoryEducationalNoticeStore(acknowledged: true),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('first_open_notice')), findsNothing);
      expect(find.byType(PatientLoginScreen), findsOneWidget);
    });

    testWidgets('leitura da confirmação falhou: o aviso aparece', (tester) async {
      await tester.pumpWidget(SinalAcsApp(backend: FakePatientBackend(), educationalNotice: _FailingStore()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('first_open_notice')), findsOneWidget);
      // Gravar também falha, e mesmo assim a pessoa não fica presa no aviso.
      await _tapKey(tester, 'educational_notice_confirm');
      expect(find.byType(PatientLoginScreen), findsOneWidget);
    });

    testWidgets('"Ler o aviso completo" abre "Sobre" e volta ao aviso', (tester) async {
      await tester.pumpWidget(SinalAcsApp(
        backend: FakePatientBackend(),
        educationalNotice: MemoryEducationalNoticeStore(),
      ));
      await tester.pumpAndSettle();

      await _tapKey(tester, 'educational_notice_about');
      expect(find.byType(AboutScreen), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('first_open_notice')), findsOneWidget);
    });

    testWidgets('a 200% de fonte, o aviso cabe e o botão continua alcançável', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final store = MemoryEducationalNoticeStore();
      await tester.pumpWidget(SinalAcsApp(backend: FakePatientBackend(), educationalNotice: store));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await _tapKey(tester, 'educational_notice_confirm');
      expect(store.acknowledged, isTrue);
    });
  });

  group('tela "Sobre"', () {
    testWidgets('mostra o aviso longo literal e reaproveita o aviso da cifra local', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: AboutScreen()));

      expect(find.text(educationalNoticeLong), findsOneWidget);
      expect(find.byKey(const Key('local_protection_notice')), findsOneWidget);
    });

    testWidgets('abre pelo login, sem sessão', (tester) async {
      await tester.pumpWidget(SinalAcsApp(
        backend: FakePatientBackend(),
        educationalNotice: MemoryEducationalNoticeStore(acknowledged: true),
      ));
      await tester.pumpAndSettle();

      await _tapKey(tester, 'login_about_link');
      expect(find.byType(AboutScreen), findsOneWidget);
      expect(find.text(educationalNoticeLong), findsOneWidget);
    });

    testWidgets('abre pelo menu "Mais"', (tester) async {
      await tester.pumpWidget(SinalAcsApp(
        backend: FakePatientBackend(),
        educationalNotice: MemoryEducationalNoticeStore(acknowledged: true),
      ));
      await tester.pumpAndSettle();
      // Login passwordless contra o duplo (o mesmo de `patient_app_mvp_test`).
      await tester.enterText(find.byKey(const Key('cpf_field')), '123.456.789-09');
      await tester.enterText(find.byKey(const Key('birth_date_field')), '01/01/1990');
      await tester.tap(find.byKey(const Key('enter_button')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('otp_code_field')), '123456');
      await tester.tap(find.byKey(const Key('verify_code_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Mais')));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'more_about');

      expect(find.byType(AboutScreen), findsOneWidget);
      expect(find.text(educationalNoticeLong), findsOneWidget);
    });

    testWidgets('a 200% de fonte, "Sobre" não estoura', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(const MaterialApp(home: AboutScreen()));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
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
