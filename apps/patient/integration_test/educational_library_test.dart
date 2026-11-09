/// Biblioteca de saúde no aparelho (C-03, RF20, RF22).
///
/// Hermético: não precisa de stack, seed nem `--dart-define`. Prova o que o
/// `flutter test` não prova — que `assets/conteudo_educativo/` está dentro do
/// APK e é lido do bundle do aparelho — e que nada da biblioteca chama o
/// backend: o duplo abaixo recusa e registra qualquer chamada.
///
///     flutter test integration_test/educational_library_test.dart -d emulator-5554
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sinalacs_patient/app/app.dart';
import 'package:sinalacs_patient/app/educational_library_screens.dart';
import 'package:sinalacs_patient/app/educational_notice_screens.dart';
import 'package:sinalacs_patient/core/education/educational_library.dart';
import 'package:sinalacs_patient/core/legal/educational_notice.dart';
import 'package:sinalacs_patient/core/network/backend_client.dart';

class _NoNetworkBackend implements PatientBackend {
  final calls = <String>[];
  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName.toString());
    throw StateError('a biblioteca não pode chamar o backend');
  }
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('biblioteca abre do login, sem sessão, com fontes e licença', (tester) async {
    final backend = _NoNetworkBackend();
    await tester.pumpWidget(SinalAcsApp(
      backend: backend,
      educationalNotice: MemoryEducationalNoticeStore(acknowledged: true),
    ));
    await tester.pumpAndSettle();
    final callsBefore = List.of(backend.calls);

    await _tapKey(tester, 'login_library_button');
    expect(find.byType(EducationalLibraryScreen), findsOneWidget);
    expect(find.byKey(const Key('library_error')), findsNothing, reason: 'asset fora do APK');

    // Todos os temas do asset do aparelho aparecem e citam fonte.
    final library = await const AssetEducationalLibrarySource().load();
    for (final topic in library.topics) {
      await _tapKey(tester, 'library_topic_${topic.id}');
      expect(find.byType(EducationalTopicScreen), findsOneWidget);
      final scroll = find.descendant(of: find.byType(EducationalTopicScreen), matching: find.byType(Scrollable)).first;
      final lastSource = find.byKey(Key('topic_source_${topic.sources.length - 1}'));
      await tester.scrollUntilVisible(lastSource, 300, scrollable: scroll);
      for (final source in topic.sources) {
        expect(find.text(source.url.toString()), findsOneWidget, reason: topic.id);
      }
      await tester.pageBack();
      await tester.pumpAndSettle();
    }

    await tester.pageBack();
    await tester.pumpAndSettle();
    await _tapKey(tester, 'login_about_link');
    final aboutScroll = find.descendant(of: find.byType(AboutScreen), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.byKey(const Key('about_content_license')), 300, scrollable: aboutScroll);
    expect(find.text(codeLicenseLabel), findsOneWidget);
    expect(find.text(contentLicenseLabel), findsOneWidget);

    expect(backend.calls, callsBefore, reason: 'a biblioteca chamou o backend');
  });
}
