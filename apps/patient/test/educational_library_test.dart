import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/app/app.dart';
import 'package:sinalacs_patient/app/educational_library_screens.dart';
import 'package:sinalacs_patient/app/educational_notice_screens.dart';
import 'package:sinalacs_patient/core/education/educational_library.dart';
import 'package:sinalacs_patient/core/legal/educational_notice.dart';
import 'package:sinalacs_patient/core/network/backend_client.dart';

import 'support/fake_patient_backend.dart';

/// Biblioteca de saúde (C-03, RF20, RF22). Critérios de aceite da #126:
/// sem conta e sem rede; cada tema cita fonte do MS ou da BVS; a pasta do
/// conteúdo traz a licença CC BY 4.0 com atribuição; "Sobre" mostra MIT e
/// CC BY 4.0.

/// Backend que registra e recusa **qualquer** chamada: a biblioteca não pode
/// usar nenhuma.
class _NoNetworkBackend implements PatientBackend {
  final calls = <String>[];
  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName.toString());
    throw StateError('a biblioteca não pode chamar o backend');
  }
}

class _FailingSource implements EducationalLibrarySource {
  int loads = 0;
  @override
  Future<EducationalLibrary> load() async {
    loads++;
    throw StateError('asset ausente');
  }
}

class _FixedSource implements EducationalLibrarySource {
  _FixedSource(this.library);
  final EducationalLibrary library;
  @override
  Future<EducationalLibrary> load() async => library;
}

String _assetText(String name) =>
    File('assets/conteudo_educativo/$name').readAsStringSync().replaceAll('\r\n', '\n');

/// JSON mínimo válido; [topic] substitui campos do tema único.
String _library({Map<String, Object?> topic = const {}, Map<String, Object?>? source}) => jsonEncode({
      'versao': 'teste',
      'temas': [
        {
          'id': 'tema-teste',
          'titulo': 'Tema de teste',
          'resumo': 'Resumo de teste.',
          'secoes': [
            {
              'titulo': 'Seção',
              'paragrafos': ['Parágrafo.'],
            },
          ],
          'fontes': [
            source ??
                {
                  'orgao': 'Ministério da Saúde',
                  'titulo': 'Página do MS',
                  'url': 'https://www.gov.br/saude/pt-br/assuntos/saude-de-a-a-z/d/dengue',
                  'consultadoEm': '2026-11-08',
                },
          ],
          'revisao': {'situacao': 'rascunho', 'revisores': <String>[], 'data': null},
          ...topic,
        },
      ],
    });

Matcher _refusedWith(String fragment) => throwsA(
      isA<EducationalLibraryFormatException>().having((e) => e.message, 'message', contains(fragment)),
    );

Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('conteúdo empacotado (assets/conteudo_educativo)', () {
    test('temas.json é válido e todo tema cita fonte do Ministério da Saúde ou da BVS', () {
      final library = parseEducationalLibrary(_assetText('temas.json'));
      expect(library.topics, isNotEmpty);
      for (final topic in library.topics) {
        expect(topic.sources, isNotEmpty, reason: topic.id);
        for (final source in topic.sources) {
          expect(educationalSourceHosts.keys, contains(source.organization), reason: topic.id);
          expect(source.url.scheme, 'https', reason: topic.id);
        }
      }
    });

    test('nenhum tema se declara revisado enquanto a P-07 não define revisores', () {
      // Quando a P-07 sair, este teste muda junto com o conteúdo revisado: um
      // "revisado" sem a lista da P-07 seria afirmação sem lastro.
      final library = parseEducationalLibrary(_assetText('temas.json'));
      expect(library.topics.where((t) => !t.isDraft), isEmpty);
    });

    test('o conteúdo não cita "UBS" (D4, C-06) nem marca de protocolo clínico (M-05)', () {
      final text = _assetText('temas.json');
      expect(text, isNot(contains('UBS')));
      expect(text.toLowerCase(), isNot(contains('manchester')));
    });

    test('a pasta traz a licença CC BY 4.0 com a atribuição', () {
      // Junta as linhas da citação em Markdown (`> `) num texto corrido.
      final licenca = _assetText('LICENCA.md').replaceAll(RegExp(r'\n>[ ]?'), ' ').replaceAll(RegExp(r'\s+'), ' ');
      expect(licenca, contains('CC BY 4.0'));
      expect(licenca, contains('https://creativecommons.org/licenses/by/4.0/'));
      expect(licenca, contains('licença MIT'));
      // A mesma atribuição que o app mostra, para os dois não divergirem.
      expect(licenca, contains(contentAttribution));
    });
  });

  group('parser recusa conteúdo fora da P-07', () {
    test('aceita o mínimo válido', () {
      final library = parseEducationalLibrary(_library());
      expect(library.topics.single.isDraft, isTrue);
    });

    test('tema sem fonte', () {
      expect(() => parseEducationalLibrary(_library(topic: {'fontes': <Object>[]})), _refusedWith('não cita nenhuma fonte'));
    });

    test('fonte de outro órgão', () {
      expect(
        () => parseEducationalLibrary(_library(source: {
          'orgao': 'Blog de saúde',
          'titulo': 'Post',
          'url': 'https://exemplo.com/post',
          'consultadoEm': '2026-11-08',
        })),
        _refusedWith('P-07 aceita só'),
      );
    });

    test('órgão certo com endereço fora dos domínios dele', () {
      expect(
        () => parseEducationalLibrary(_library(source: {
          'orgao': 'Ministério da Saúde',
          'titulo': 'Cópia',
          'url': 'https://gov.br.exemplo.com/dengue',
          'consultadoEm': '2026-11-08',
        })),
        _refusedWith('fora dos domínios'),
      );
    });

    test('endereço sem https', () {
      expect(
        () => parseEducationalLibrary(_library(source: {
          'orgao': 'Biblioteca Virtual em Saúde (BVS)',
          'titulo': 'BVS',
          'url': 'http://bvsms.saude.gov.br/dengue-16/',
          'consultadoEm': '2026-11-08',
        })),
        _refusedWith('fora dos domínios'),
      );
    });

    test('"revisado" sem revisores ou sem data', () {
      expect(
        () => parseEducationalLibrary(_library(topic: {
          'revisao': {'situacao': 'revisado', 'revisores': <String>[], 'data': '2026-11-08'},
        })),
        _refusedWith('sem revisores ou sem data'),
      );
      expect(
        () => parseEducationalLibrary(_library(topic: {
          'revisao': {
            'situacao': 'revisado',
            'revisores': ['Preceptora A'],
            'data': null,
          },
        })),
        _refusedWith('sem revisores ou sem data'),
      );
    });

    test('situação de revisão desconhecida', () {
      expect(
        () => parseEducationalLibrary(_library(topic: {
          'revisao': {'situacao': 'aprovado', 'revisores': <String>[], 'data': null},
        })),
        _refusedWith('"rascunho" ou "revisado"'),
      );
    });

    test('id repetido e JSON malformado', () {
      final dois = jsonDecode(_library()) as Map<String, Object?>;
      final temas = dois['temas']! as List<Object?>;
      temas.add(temas.first);
      expect(() => parseEducationalLibrary(jsonEncode(dois)), _refusedWith('repetido'));
      expect(() => parseEducationalLibrary('{'), _refusedWith('malformado'));
    });
  });

  group('telas', () {
    // O rootBundle guarda o Future do asset; criado na zona de outro teste,
    // ele não completa neste.
    setUp(rootBundle.clear);

    testWidgets('abre pelo login, sem sessão e sem nenhuma chamada ao backend', (tester) async {
      final backend = _NoNetworkBackend();
      await tester.pumpWidget(SinalAcsApp(
        backend: backend,
        educationalNotice: MemoryEducationalNoticeStore(acknowledged: true),
      ));
      await tester.pumpAndSettle();
      final callsBefore = List.of(backend.calls);

      // Conteúdo real do asset (rootBundle), não um duplo.
      await _tapKey(tester, 'login_library_button');
      expect(find.byType(EducationalLibraryScreen), findsOneWidget);
      expect(find.text('Dengue'), findsOneWidget);
      expect(find.text('Pressão alta (hipertensão)'), findsOneWidget);
      expect(find.byKey(const Key('library_short_notice')), findsOneWidget);
      expect(find.byKey(const Key('topic_draft_badge')), findsNWidgets(2));

      await _tapKey(tester, 'library_topic_dengue');
      expect(find.byType(EducationalTopicScreen), findsOneWidget);
      expect(find.text('Sinais de alarme'), findsOneWidget);
      final topicScroll = find.descendant(of: find.byType(EducationalTopicScreen), matching: find.byType(Scrollable)).first;
      await tester.scrollUntilVisible(find.byKey(const Key('topic_source_1')), 300, scrollable: topicScroll);
      expect(find.text('Ministério da Saúde'), findsOneWidget);
      expect(find.text('Biblioteca Virtual em Saúde (BVS)'), findsOneWidget);
      expect(find.text('https://www.gov.br/saude/pt-br/assuntos/saude-de-a-a-z/d/dengue'), findsOneWidget);
      expect(find.text('Consultado em 08/11/2026.'), findsNWidgets(2));
      await tester.scrollUntilVisible(find.byKey(const Key('library_license')), 300, scrollable: topicScroll);
      expect(find.textContaining('CC BY 4.0'), findsOneWidget);

      expect(backend.calls, callsBefore, reason: 'a biblioteca chamou o backend');
    });

    testWidgets('tema revisado mostra revisores e data, sem o selo de rascunho', (tester) async {
      final library = parseEducationalLibrary(_library(topic: {
        'revisao': {
          'situacao': 'revisado',
          'revisores': ['Preceptora A', 'Preceptor B'],
          'data': '2026-12-01',
        },
      }));
      await tester.pumpWidget(MaterialApp(home: EducationalLibraryScreen(source: _FixedSource(library))));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('topic_draft_badge')), findsNothing);

      await _tapKey(tester, 'library_topic_tema-teste');
      expect(find.text('Revisado por Preceptora A, Preceptor B em 2026-12-01.'), findsOneWidget);
      expect(find.byKey(const Key('topic_draft_badge')), findsNothing);
    });

    testWidgets('falha ao ler o conteúdo mostra erro e tenta de novo', (tester) async {
      final source = _FailingSource();
      await tester.pumpWidget(MaterialApp(home: EducationalLibraryScreen(source: source)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('library_error')), findsOneWidget);

      await tester.tap(find.text('Tentar de novo'));
      await tester.pumpAndSettle();
      expect(source.loads, 2);
    });

    testWidgets('abre pelo menu "Mais" com sessão', (tester) async {
      await tester.pumpWidget(SinalAcsApp(
        backend: FakePatientBackend(),
        educationalNotice: MemoryEducationalNoticeStore(acknowledged: true),
      ));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('cpf_field')), '123.456.789-09');
      await tester.enterText(find.byKey(const Key('birth_date_field')), '01/01/1990');
      await tester.tap(find.byKey(const Key('enter_button')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('otp_code_field')), '123456');
      await tester.tap(find.byKey(const Key('verify_code_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Mais')));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'more_library');
      expect(find.byType(EducationalLibraryScreen), findsOneWidget);
    });

    testWidgets('"Sobre" indica código MIT e conteúdo CC BY 4.0', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: AboutScreen()));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('about_content_license')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(codeLicenseLabel), findsOneWidget);
      expect(find.text(contentLicenseLabel), findsOneWidget);
      expect(codeLicenseLabel, contains('MIT'));
      expect(contentLicenseLabel, contains('CC BY 4.0'));
      expect(find.text('Atribuição: $contentAttribution'), findsOneWidget);
    });
  });
}
