import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/app/app.dart';
import 'package:sinalacs_patient/core/consent/consent_preferences.dart';
import 'package:sinalacs_patient/core/network/backend_client.dart';

import 'support/fake_patient_backend.dart';

/// Fake local para os testes deste arquivo — mesma forma de
/// `_FixedConsentPreferences` (Task 2, em `patient_app_mvp_test.dart`), mas
/// duplicada aqui porque essa classe privada não é importável entre arquivos
/// de teste.
class _RecordingConsentPreferences implements ConsentPreferences {
  bool? saved;

  @override
  Future<bool> localRemindersGranted() async => saved ?? false;

  @override
  Future<void> saveLocalRemindersConsent(bool granted) async => saved = granted;
}

/// Abre a tela de onboarding a partir da tela de login, mesmo ponto de
/// entrada que hoje mostra o snackbar placeholder do QR Code.
Future<void> openOnboarding(WidgetTester tester) async {
  await tapKey(tester, 'start_onboarding_button');
}

/// Rola o widget para dentro da viewport antes de tocar — o `ListView` da
/// tela é mais alto que os 600dp do viewport de teste padrão.
Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('deve abrir com campo de token e os 3 consentimentos desmarcados', (tester) async {
    await tester.pumpWidget(SinalAcsApp(backend: FakePatientBackend()));
    await openOnboarding(tester);

    expect(find.byKey(const Key('onboarding_token_field')), findsOneWidget);

    final healthConsent = tester.widget<CheckboxListTile>(
      find.byKey(const Key('onboarding_consent_health')),
    );
    final remindersConsent = tester.widget<CheckboxListTile>(
      find.byKey(const Key('onboarding_consent_reminders')),
    );
    final pushConsent = tester.widget<CheckboxListTile>(
      find.byKey(const Key('onboarding_consent_push')),
    );

    // A decisão exige aceite/recusa explícitos — nenhum checkbox pode vir
    // pré-marcado, nem mesmo o obrigatório.
    expect(healthConsent.value, isFalse);
    expect(remindersConsent.value, isFalse);
    expect(pushConsent.value, isFalse);
  });

  testWidgets('botão de concluir cadastro fica desabilitado enquanto o token estiver vazio', (tester) async {
    await tester.pumpWidget(SinalAcsApp(backend: FakePatientBackend()));
    await openOnboarding(tester);

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('complete_enrollment_button')),
    );
    expect(button.onPressed, isNull);

    await tester.enterText(find.byKey(const Key('onboarding_token_field')), 'convite-123');
    await tester.pump();

    final buttonAfter = tester.widget<FilledButton>(
      find.byKey(const Key('complete_enrollment_button')),
    );
    expect(buttonAfter.onPressed, isNotNull);
  });

  testWidgets('tentar concluir sem marcar o consentimento obrigatório mostra erro inline e não chama o backend', (tester) async {
    final backend = FakePatientBackend();
    await tester.pumpWidget(SinalAcsApp(backend: backend));
    await openOnboarding(tester);

    await tester.enterText(find.byKey(const Key('onboarding_token_field')), 'convite-123');
    await tester.pump();
    await tapKey(tester, 'complete_enrollment_button');

    expect(find.byKey(const Key('onboarding_error')), findsOneWidget);
    expect(backend.enrollmentCalls, isEmpty);
  });

  testWidgets('marcar o obrigatório e concluir chama completeEnrollment e navega para a tela principal', (tester) async {
    final backend = FakePatientBackend();
    await tester.pumpWidget(SinalAcsApp(backend: backend));
    await openOnboarding(tester);

    await tester.enterText(find.byKey(const Key('onboarding_token_field')), 'convite-123');
    await tapKey(tester, 'onboarding_consent_health');
    await tapKey(tester, 'onboarding_consent_reminders');
    await tapKey(tester, 'complete_enrollment_button');

    expect(backend.enrollmentCalls, hasLength(1));
    expect(backend.enrollmentCalls.single, {
      'token': 'convite-123',
      'healthDataConsent': true,
      'remindersConsent': true,
      'pushConsent': false,
    });
    expect(find.text('Triagem rápida'), findsOneWidget);
  });

  testWidgets('falha do backend mostra a mensagem e mantém a tela de onboarding', (tester) async {
    final backend = FakePatientBackend(
      enrollmentFailure: const BackendFailure('Convite inválido, expirado ou já utilizado.'),
    );
    await tester.pumpWidget(SinalAcsApp(backend: backend));
    await openOnboarding(tester);

    await tester.enterText(find.byKey(const Key('onboarding_token_field')), 'convite-123');
    await tapKey(tester, 'onboarding_consent_health');
    await tapKey(tester, 'complete_enrollment_button');

    expect(find.text('Convite inválido, expirado ou já utilizado.'), findsOneWidget);
    expect(find.text('Triagem rápida'), findsNothing);
    expect(find.byKey(const Key('onboarding_token_field')), findsOneWidget);
  });

  testWidgets('concluir o cadastro com o consentimento de lembretes marcado grava isso localmente', (tester) async {
    final backend = FakePatientBackend();
    final consentPreferences = _RecordingConsentPreferences();
    await tester.pumpWidget(SinalAcsApp(backend: backend, consentPreferences: consentPreferences));
    await openOnboarding(tester);

    await tester.enterText(find.byKey(const Key('onboarding_token_field')), 'convite-123');
    await tapKey(tester, 'onboarding_consent_health');
    await tapKey(tester, 'onboarding_consent_reminders');
    await tapKey(tester, 'complete_enrollment_button');

    expect(consentPreferences.saved, isTrue);
  });

  testWidgets('concluir o cadastro com o consentimento de lembretes desmarcado grava a recusa localmente', (tester) async {
    final backend = FakePatientBackend();
    final consentPreferences = _RecordingConsentPreferences();
    await tester.pumpWidget(SinalAcsApp(backend: backend, consentPreferences: consentPreferences));
    await openOnboarding(tester);

    await tester.enterText(find.byKey(const Key('onboarding_token_field')), 'convite-123');
    await tapKey(tester, 'onboarding_consent_health');
    // onboarding_consent_reminders permanece desmarcado.
    await tapKey(tester, 'complete_enrollment_button');

    expect(consentPreferences.saved, isFalse);
  });
}
