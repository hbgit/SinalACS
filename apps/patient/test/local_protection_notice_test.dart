import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/app/local_protection_notice.dart';
import 'package:sinalacs_patient/app/patient_theme.dart';
import 'package:sinalacs_patient/core/consent/consent_preferences.dart';
import 'package:sinalacs_patient/core/reminders/reminder.dart';
import 'package:sinalacs_patient/core/reminders/reminder_scheduler.dart';
import 'package:sinalacs_patient/core/reminders/reminder_store.dart';
import 'package:sinalacs_patient/app/app.dart';
import 'package:sinalacs_patient/core/services/theme_controller.dart';

import 'support/contrast.dart';

class _Store implements ReminderStore {
  @override
  Future<List<Reminder>> list() async => const [];
  @override
  Future<Reminder> save(Reminder reminder) async => reminder;
  @override
  Future<void> delete(int id) async {}
}

class _Scheduler implements ReminderScheduler {
  @override
  Future<void> schedule(Reminder reminder) async {}
  @override
  Future<void> cancel(int reminderId) async {}
  @override
  Future<void> cancelAll() async {}
  @override
  Future<void> rescheduleAll(List<Reminder> active) async {}
}

class _Prefs implements ConsentPreferences {
  @override
  Future<bool?> localRemindersGranted() async => true;
  @override
  Future<void> saveLocalRemindersConsent(bool value) async {}
}

Widget _reminders({double scale = 1.0}) => MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: RemindersScope(
        store: _Store(),
        scheduler: _Scheduler(),
        consentPreferences: _Prefs(),
        child: PatientHomeShell(
          themeController: ThemeController(),
          initialDestination: PatientDestination.reminders,
        ),
      ),
    );

void main() {
  testWidgets('RemindersScreen mostra o aviso de proteção local', (tester) async {
    await tester.pumpWidget(_reminders());
    await tester.pumpAndSettle();
    expect(find.byType(LocalProtectionNotice), findsOneWidget);
    expect(find.text('Proteção dos dados neste aparelho.'), findsOneWidget);
    expect(find.textContaining('Não empreste o celular desbloqueado.'), findsOneWidget);
  });

  testWidgets('o aviso não promete expiração nem apagar', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: LocalProtectionNotice())));
    final texto = tester
        .widgetList<Text>(find.descendant(of: find.byType(LocalProtectionNotice), matching: find.byType(Text)))
        .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
        .join(' ');
    expect(texto, isNotEmpty);
    expect(texto, isNot(contains('30 dias')));
    expect(texto, isNot(contains('Apagar meus dados')));
  });

  testWidgets('semântica: título é cabeçalho e o texto é exposto', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: LocalProtectionNotice())));
    final titulo = tester.getSemantics(find.text('Proteção dos dados neste aparelho.'));
    expect(titulo.getSemanticsData().flagsCollection.isHeader, isTrue);
    expect(find.bySemanticsLabel(RegExp('não protege de quem usa o seu celular desbloqueado')), findsOneWidget);
    // O aviso não tem controle: `botoesInertes` exige ao menos um botão na
    // árvore e não se aplica; aqui basta provar que nenhum nó se anuncia como botão.
    expect(titulo.getSemanticsData().flagsCollection.isButton, isFalse);
    handle.dispose();
  });

  test('contraste: texto comum do tema sobre o fundo do aviso (dark e claro)', () {
    final dark = buildPatientDarkTheme().colorScheme;
    final light = buildPatientLightTheme().colorScheme;
    expect(contrastOn(dark.onSurface, PatientDarkColors.surfaceRaised), greaterThanOrEqualTo(4.5));
    expect(contrastOn(dark.onSurface, PatientDarkColors.background), greaterThanOrEqualTo(4.5));
    expect(contrastOn(light.onSurface, PatientLightColors.background), greaterThanOrEqualTo(4.5));
    expect(contrastOn(light.onSurface, PatientLightColors.surfaceRaised), greaterThanOrEqualTo(4.5));
  });

  testWidgets('o aviso não estoura a 200% de fonte na RemindersScreen', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_reminders(scale: 2.0));
    await tester.pumpAndSettle();
    expect(find.byType(LocalProtectionNotice), findsOneWidget);
    final ex = tester.takeException();
    expect(ex is FlutterError ? ex.toStringDeep() : ex, isNull);
  });
}
