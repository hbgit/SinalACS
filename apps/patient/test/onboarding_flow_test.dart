import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/app/app.dart';
import 'package:sinalacs_patient/app/legal_screens.dart';
import 'package:sinalacs_patient/core/consent/consent_preferences.dart';
import 'package:sinalacs_patient/core/network/backend_client.dart';
import 'package:sinalacs_patient/core/push/push_token_source.dart';

import 'support/fake_device_credential_store.dart';
import 'support/fake_patient_backend.dart';
import 'support/semantics_scan.dart';

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

/// Custódia do consentimento cuja gravação nunca termina (Keystore/SQLCipher
/// travados): o cadastro não pode esperar por ela.
class _NeverCompletingConsentPreferences implements ConsentPreferences {
  @override
  Future<bool?> localRemindersGranted() => Completer<bool?>().future;

  @override
  Future<void> saveLocalRemindersConsent(bool granted) => Completer<void>().future;
}

const _pinDeTeste = '284637';

FakeDeviceCredentialStore _storeVazio() => FakeDeviceCredentialStore();

/// Abre a tela de onboarding a partir da tela de acesso (C-05: o convite é o
/// caminho de quem ainda não tem credencial neste aparelho).
Future<void> openOnboarding(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tapKey(tester, 'start_onboarding_button');
}

/// Cria o PIN e conclui o cadastro (o passo novo da C-05).
Future<void> criarPin(WidgetTester tester, {String pin = _pinDeTeste}) async {
  await pumpUntil(tester, find.byKey(const Key('pin_setup_field')));
  await tester.enterText(find.byKey(const Key('pin_setup_field')), pin);
  await tester.enterText(find.byKey(const Key('pin_setup_confirm_field')), pin);
  await tapKey(tester, 'pin_setup_confirm_button');
}

Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
  final limit = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(limit)) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('não apareceu: $finder');
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

class _FonteDeToken implements PushTokenSource {
  int calls = 0;

  @override
  Future<PushDevice?> currentDevice() async {
    calls++;
    return const PushDevice(token: 'tok-onb', platform: 'android');
  }
}

Future<void> concluirCadastro(WidgetTester tester, {required bool avisos}) async {
  await openOnboarding(tester);
  await tester.enterText(find.byKey(const Key('onboarding_token_field')), 'convite-123');
  await tapKey(tester, 'onboarding_consent_health');
  await tapKey(tester, 'onboarding_terms_accept');
  if (avisos) await tapKey(tester, 'onboarding_consent_push');
  await tapKey(tester, 'complete_enrollment_button');
  await criarPin(tester);
}

/// Token sintético no formato real (43 caracteres base64url).
const _conviteSintetico = 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789-_AbCde';

void main() {
  testWidgets('deve abrir com campo de token e os 3 consentimentos desmarcados', (tester) async {
    await tester.pumpWidget(SinalAcsApp(
      backend: FakePatientBackend(),
      deviceCredentials: _storeVazio(),
    ));
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
    await tester.ensureVisible(find.byKey(const Key('onboarding_terms_accept')));
    final termsAccept = tester.widget<CheckboxListTile>(
      find.byKey(const Key('onboarding_terms_accept')),
    );
    expect(termsAccept.value, isFalse);
  });

  testWidgets('botão de concluir cadastro fica desabilitado enquanto o token estiver vazio', (tester) async {
    await tester.pumpWidget(SinalAcsApp(
      backend: FakePatientBackend(),
      deviceCredentials: _storeVazio(),
    ));
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
    await tester.pumpWidget(SinalAcsApp(backend: backend, deviceCredentials: _storeVazio()));
    await openOnboarding(tester);

    await tester.enterText(find.byKey(const Key('onboarding_token_field')), 'convite-123');
    await tester.pump();
    await tapKey(tester, 'complete_enrollment_button');

    expect(find.byKey(const Key('onboarding_error')), findsOneWidget);
    expect(backend.enrollmentCalls, isEmpty);
  });

  testWidgets('marcar o obrigatório e concluir cria o PIN, chama completeEnrollment e navega para a tela principal', (tester) async {
    final backend = FakePatientBackend();
    await tester.pumpWidget(SinalAcsApp(backend: backend, deviceCredentials: _storeVazio()));
    await openOnboarding(tester);

    await tester.enterText(find.byKey(const Key('onboarding_token_field')), 'convite-123');
    await tapKey(tester, 'onboarding_consent_health');
    await tapKey(tester, 'onboarding_terms_accept');
    await tapKey(tester, 'onboarding_consent_reminders');
    await tapKey(tester, 'complete_enrollment_button');
    await criarPin(tester);

    expect(backend.enrollmentCalls, hasLength(1));
    expect(backend.enrollmentCalls.single, {
      'token': 'convite-123',
      'healthDataConsent': true,
      'remindersConsent': true,
      'pushConsent': false,
      'termsAccepted': true,
      'deviceId': isA<String>(),
      'deviceSecret': isA<String>(),
    });
    expect(find.text('Triagem rápida'), findsOneWidget);
  });

  testWidgets('PIN fora da política é recusado LOCALMENTE e o convite não é consumido', (tester) async {
    final backend = FakePatientBackend();
    await tester.pumpWidget(SinalAcsApp(backend: backend, deviceCredentials: _storeVazio()));
    await openOnboarding(tester);

    await tester.enterText(find.byKey(const Key('onboarding_token_field')), 'convite-123');
    await tapKey(tester, 'onboarding_consent_health');
    await tapKey(tester, 'onboarding_terms_accept');
    await tapKey(tester, 'complete_enrollment_button');

    // Curto demais, sequência proibida, dígito repetido: nada chega ao servidor.
    for (final fraco in ['12345', '123456', '000000']) {
      await tester.enterText(find.byKey(const Key('pin_setup_field')), fraco);
      await tester.enterText(find.byKey(const Key('pin_setup_confirm_field')), fraco);
      await tapKey(tester, 'pin_setup_confirm_button');
      expect(find.byKey(const Key('pin_setup_error')), findsOneWidget);
    }
    expect(backend.enrollmentCalls, isEmpty);

    // O MESMO convite segue servindo: a recusa foi antes do consumo.
    await criarPin(tester);
    expect(backend.enrollmentCalls, hasLength(1));
    expect(find.text('Triagem rápida'), findsOneWidget);
  });

  testWidgets('cadastro com "Avisos da equipe" marcado registra o token sem consultar o servidor',
      (tester) async {
    final backend = FakePatientBackend();
    final fonte = _FonteDeToken();
    await tester.pumpWidget(SinalAcsApp(
      backend: backend,
      deviceCredentials: _storeVazio(),
      pushTokens: fonte,
    ));
    await concluirCadastro(tester, avisos: true);

    expect(backend.pushRegistrations, [('tok-onb', 'android')]);
    expect(backend.hasGrantedConsentCalls, 0);
    expect(backend.myDataCallCount, 0);
  });

  testWidgets('cadastro sem "Avisos da equipe": o aparelho nem é consultado', (tester) async {
    final backend = FakePatientBackend();
    final fonte = _FonteDeToken();
    await tester.pumpWidget(SinalAcsApp(
      backend: backend,
      deviceCredentials: _storeVazio(),
      pushTokens: fonte,
    ));
    await concluirCadastro(tester, avisos: false);

    expect(fonte.calls, 0);
    expect(backend.pushRegistrations, isEmpty);
    expect(backend.hasGrantedConsentCalls, 0);
    expect(find.text('Triagem rápida'), findsOneWidget);
  });

  testWidgets('falha do backend mostra a mensagem, apaga a credencial local e deixa o convite utilizável', (tester) async {
    final backend = FakePatientBackend(
      enrollmentFailure: const BackendFailure('Convite inválido, expirado ou já utilizado.'),
    );
    final store = _storeVazio();
    await tester.pumpWidget(SinalAcsApp(backend: backend, deviceCredentials: store));
    await openOnboarding(tester);

    await tester.enterText(find.byKey(const Key('onboarding_token_field')), 'convite-123');
    await tapKey(tester, 'onboarding_consent_health');
    await tapKey(tester, 'onboarding_terms_accept');
    await tapKey(tester, 'complete_enrollment_button');
    await criarPin(tester);

    expect(find.text('Convite inválido, expirado ou já utilizado.'), findsOneWidget);
    expect(find.text('Triagem rápida'), findsNothing);
    expect(find.byKey(const Key('pin_setup_field')), findsOneWidget);

    // Falha-segura: o envelope local foi desfeito junto com a falha — não
    // fica credencial órfã para um convite que não foi consumido.
    expect(store.hasCredential(), completion(isFalse));
  });

  testWidgets('falha local do enroll mostra mensagem, destrava a tela e NÃO chama o servidor', (tester) async {
    final backend = FakePatientBackend();
    final store = _storeVazio()..failEnroll = true;
    await tester.pumpWidget(SinalAcsApp(backend: backend, deviceCredentials: store));
    await openOnboarding(tester);

    await tester.enterText(find.byKey(const Key('onboarding_token_field')), 'convite-123');
    await tapKey(tester, 'onboarding_consent_health');
    await tapKey(tester, 'onboarding_terms_accept');
    await tapKey(tester, 'complete_enrollment_button');
    await criarPin(tester);

    // Sem o catch-all, `_busy` ficava true: botão desabilitado com indicador,
    // nenhuma mensagem, e a exceção do Keystore ia para o logcat.
    expect(find.text('Não foi possível concluir o cadastro agora. Tente de novo.'), findsOneWidget);
    final botao = tester.widget<FilledButton>(find.byKey(const Key('pin_setup_confirm_button')));
    expect(botao.onPressed, isNotNull);
    // O convite continua utilizável: a falha foi local, antes do servidor.
    expect(backend.enrollmentCalls, isEmpty);
  });

  testWidgets('concluir o cadastro com o consentimento de lembretes marcado grava isso localmente', (tester) async {
    final backend = FakePatientBackend();
    final consentPreferences = _RecordingConsentPreferences();
    await tester.pumpWidget(SinalAcsApp(
      backend: backend,
      deviceCredentials: _storeVazio(),
      consentPreferences: consentPreferences,
    ));
    await openOnboarding(tester);

    await tester.enterText(find.byKey(const Key('onboarding_token_field')), 'convite-123');
    await tapKey(tester, 'onboarding_consent_health');
    await tapKey(tester, 'onboarding_terms_accept');
    await tapKey(tester, 'onboarding_consent_reminders');
    await tapKey(tester, 'complete_enrollment_button');
    await criarPin(tester);

    expect(consentPreferences.saved, isTrue);
  });

  testWidgets('gravação local que nunca termina não segura a tela principal (limite de 3 s)', (tester) async {
    final backend = FakePatientBackend();
    await tester.pumpWidget(SinalAcsApp(
      backend: backend,
      deviceCredentials: _storeVazio(),
      consentPreferences: _NeverCompletingConsentPreferences(),
    ));
    await openOnboarding(tester);

    await tester.enterText(find.byKey(const Key('onboarding_token_field')), 'convite-123');
    await tapKey(tester, 'onboarding_consent_health');
    await tapKey(tester, 'onboarding_terms_accept');
    await tapKey(tester, 'onboarding_consent_reminders');
    await tapKey(tester, 'complete_enrollment_button');
    await pumpUntil(tester, find.byKey(const Key('pin_setup_field')));
    await tester.enterText(find.byKey(const Key('pin_setup_field')), _pinDeTeste);
    await tester.enterText(find.byKey(const Key('pin_setup_confirm_field')), _pinDeTeste);
    final finder = find.byKey(const Key('pin_setup_confirm_button'));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pump();
    expect(find.text('Triagem rápida'), findsNothing);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(backend.enrollmentCalls, hasLength(1));
    expect(find.text('Triagem rápida'), findsOneWidget);
  });

  testWidgets('concluir o cadastro com o consentimento de lembretes desmarcado grava a recusa localmente', (tester) async {
    final backend = FakePatientBackend();
    final consentPreferences = _RecordingConsentPreferences();
    await tester.pumpWidget(SinalAcsApp(
      backend: backend,
      deviceCredentials: _storeVazio(),
      consentPreferences: consentPreferences,
    ));
    await openOnboarding(tester);

    await tester.enterText(find.byKey(const Key('onboarding_token_field')), 'convite-123');
    await tapKey(tester, 'onboarding_consent_health');
    await tapKey(tester, 'onboarding_terms_accept');
    // onboarding_consent_reminders permanece desmarcado.
    await tapKey(tester, 'complete_enrollment_button');
    await criarPin(tester);

    expect(consentPreferences.saved, isFalse);
  });

  testWidgets("'Concluir cadastro' é UM nó, com o texto visível e a ação de toque", (tester) async {
    // WCAG 4.1.2, medido pela primeira vez aqui: `spec/ux_accessibility_assessment.md`
    // linha 242 declarava este botão "não medido" — fora da primeira dobra do
    // viewport padrão de teste (o `ListView` é mais alto que os 600dp). O
    // `ensureVisible` de `tapKey`/`openOnboarding` acima já rola até ele; esta
    // varredura precisa do mesmo antes de olhar a árvore.
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(SinalAcsApp(
      backend: FakePatientBackend(),
      deviceCredentials: _storeVazio(),
    ));
    await openOnboarding(tester);
    await tester.ensureVisible(find.byKey(const Key('complete_enrollment_button')));
    await tester.pumpAndSettle();

    expectNenhumBotaoInerte(tester);

    final node = tester.getSemantics(find.byKey(const Key('complete_enrollment_button')));
    final data = node.getSemanticsData();
    expect(data.label, contains('Concluir cadastro'));
    handle.dispose();
  });

  testWidgets('sem aceitar o termo, concluir mostra o motivo e não chama o backend', (tester) async {
    final backend = FakePatientBackend();
    await tester.pumpWidget(SinalAcsApp(backend: backend, deviceCredentials: _storeVazio()));
    await openOnboarding(tester);

    await tester.enterText(find.byKey(const Key('onboarding_token_field')), 'convite-123');
    await tapKey(tester, 'onboarding_consent_health');
    await tapKey(tester, 'complete_enrollment_button');

    expect(find.text('É preciso aceitar o Termo de Uso e a Política de Privacidade.'), findsOneWidget);
    expect(backend.enrollmentCalls, isEmpty);
  });

  testWidgets('o onboarding abre o termo e a política antes do aceite', (tester) async {
    await tester.pumpWidget(SinalAcsApp(
      backend: FakePatientBackend(),
      deviceCredentials: _storeVazio(),
    ));
    await openOnboarding(tester);

    await tapKey(tester, 'onboarding_open_terms');
    expect(find.byType(LegalDocumentScreen), findsOneWidget);
    expect(find.text('Termo de Uso'), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tapKey(tester, 'onboarding_open_privacy');
    expect(find.text('Política de Privacidade'), findsWidgets);
  });

  testWidgets('ler o QR do convite preenche o campo e libera concluir', (tester) async {
    final backend = FakePatientBackend();
    await tester.pumpWidget(SinalAcsApp(
      backend: backend,
      deviceCredentials: _storeVazio(),
      qrScanner: (_) async => _conviteSintetico,
    ));
    await openOnboarding(tester);

    await tapKey(tester, 'scan_qr_button');
    final field = tester.widget<TextField>(find.byKey(const Key('onboarding_token_field')));
    expect(field.controller!.text, _conviteSintetico);

    await tapKey(tester, 'onboarding_consent_health');
    await tapKey(tester, 'onboarding_terms_accept');
    await tapKey(tester, 'complete_enrollment_button');
    await criarPin(tester);
    expect(backend.enrollmentCalls.single['token'], _conviteSintetico);
  });

  testWidgets('cancelar a leitura não muda o que já foi digitado', (tester) async {
    await tester.pumpWidget(SinalAcsApp(
      backend: FakePatientBackend(),
      deviceCredentials: _storeVazio(),
      qrScanner: (_) async => null,
    ));
    await openOnboarding(tester);
    await tester.enterText(find.byKey(const Key('onboarding_token_field')), 'convite-123');

    await tapKey(tester, 'scan_qr_button');

    final field = tester.widget<TextField>(find.byKey(const Key('onboarding_token_field')));
    expect(field.controller!.text, 'convite-123');
    expect(find.byKey(const Key('onboarding_error')), findsNothing);
  });

  testWidgets('QR que não é convite mostra aviso e não preenche o campo', (tester) async {
    await tester.pumpWidget(SinalAcsApp(
      backend: FakePatientBackend(),
      deviceCredentials: _storeVazio(),
      qrScanner: (_) async => 'https://exemplo.invalid/pagina',
    ));
    await openOnboarding(tester);
    await tester.enterText(find.byKey(const Key('onboarding_token_field')), 'convite-123');

    await tapKey(tester, 'scan_qr_button');

    expect(find.textContaining('não é um convite do SinalACS'), findsOneWidget);
    final field = tester.widget<TextField>(find.byKey(const Key('onboarding_token_field')));
    expect(field.controller!.text, 'convite-123');
  });

  testWidgets('falha da câmera mostra aviso e o campo manual continua utilizável', (tester) async {
    final backend = FakePatientBackend();
    await tester.pumpWidget(SinalAcsApp(
      backend: backend,
      deviceCredentials: _storeVazio(),
      qrScanner: (_) async => throw StateError('câmera indisponível'),
    ));
    await openOnboarding(tester);

    await tapKey(tester, 'scan_qr_button');
    expect(find.textContaining('Não foi possível usar a câmera'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('onboarding_token_field')), 'convite-123');
    await tapKey(tester, 'onboarding_consent_health');
    await tapKey(tester, 'onboarding_terms_accept');
    await tapKey(tester, 'complete_enrollment_button');
    await criarPin(tester);
    expect(backend.enrollmentCalls, hasLength(1));
  });

  testWidgets('toque duplo em "Ler QR Code" abre uma leitura só', (tester) async {
    final gate = Completer<String?>();
    var calls = 0;
    await tester.pumpWidget(SinalAcsApp(
      backend: FakePatientBackend(),
      deviceCredentials: _storeVazio(),
      qrScanner: (_) {
        calls++;
        return gate.future;
      },
    ));
    await openOnboarding(tester);

    await tester.tap(find.byKey(const Key('scan_qr_button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('scan_qr_button')), warnIfMissed: false);
    await tester.pump();
    expect(calls, 1);

    gate.complete(null);
    await tester.pumpAndSettle();
    await tapKey(tester, 'scan_qr_button');
    expect(calls, 2, reason: 'depois de voltar, dá para ler de novo');
  });

  testWidgets('o botão de ler QR volta a funcionar depois que o leitor lança', (tester) async {
    var calls = 0;
    await tester.pumpWidget(SinalAcsApp(
      backend: FakePatientBackend(),
      deviceCredentials: _storeVazio(),
      qrScanner: (_) async {
        calls++;
        if (calls == 1) throw StateError('câmera indisponível');
        return null;
      },
    ));
    await openOnboarding(tester);

    await tapKey(tester, 'scan_qr_button');
    expect(find.textContaining('Não foi possível usar a câmera'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.byKey(const Key('scan_qr_button'))).onPressed, isNotNull);

    await tapKey(tester, 'scan_qr_button');
    expect(calls, 2);
  });

  testWidgets('o aviso do QR some quando a pessoa volta a digitar', (tester) async {
    await tester.pumpWidget(SinalAcsApp(
      backend: FakePatientBackend(),
      deviceCredentials: _storeVazio(),
      qrScanner: (_) async => 'https://exemplo.invalid/pagina',
    ));
    await openOnboarding(tester);
    await tapKey(tester, 'scan_qr_button');
    expect(find.textContaining('não é um convite do SinalACS'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('onboarding_token_field')), 'convite-123');
    await tester.pump();

    expect(find.textContaining('não é um convite do SinalACS'), findsNothing);
  });
}
