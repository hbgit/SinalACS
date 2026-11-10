import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/app/app.dart';
import 'package:sinalacs_patient/core/network/backend_client.dart';

import 'support/fake_device_credential_store.dart';
import 'support/fake_patient_backend.dart';

/// Acesso do participante (RF24, C-05): convite QR + PIN local, sem CPF,
/// telefone ou e-mail — o critério de aceite da issue #128.
void main() {
  const deviceId = '00000000-0000-4000-8000-0000000000d1';
  const secret = 'segredo-sintetico';
  const pin = '284637';

  Widget app(FakePatientBackend backend, FakeDeviceCredentialStore store) =>
      SinalAcsApp(backend: backend, deviceCredentials: store);

  Future<void> entrarComPin(
    WidgetTester tester, {
    String pinDigitado = pin,
  }) async {
    await tester.enterText(find.byKey(const Key('pin_field')), pinDigitado);
    await tester.tap(find.byKey(const Key('pin_unlock_button')));
    await tester.pumpAndSettle();
  }

  testWidgets('sem credencial, a tela oferece o convite e NÃO tem campo de CPF, telefone nem e-mail',
      (tester) async {
    final backend = FakePatientBackend();
    await tester.pumpWidget(app(backend, FakeDeviceCredentialStore()));
    await tester.pumpAndSettle();

    // Critério de aceite: o fluxo de login não usa e-mail, CPF nem telefone.
    expect(find.byKey(const Key('cpf_field')), findsNothing);
    expect(find.byKey(const Key('birth_date_field')), findsNothing);
    expect(find.byKey(const Key('otp_code_field')), findsNothing);
    expect(find.textContaining('CPF'), findsNothing);
    expect(find.textContaining('e-mail'), findsNothing);
    expect(find.textContaining('telefone'), findsNothing);

    // O caminho é o convite QR do agente.
    expect(find.byKey(const Key('start_onboarding_button')), findsOneWidget);
    expect(find.byKey(const Key('login_legal_link')), findsOneWidget);
  });

  testWidgets('PIN correto libera o segredo e abre o painel por auth.loginDevice',
      (tester) async {
    final backend = FakePatientBackend();
    final store = FakeDeviceCredentialStore()
      ..enrollForTest(deviceId: deviceId, secret: secret, pin: pin);
    await tester.pumpWidget(app(backend, store));
    await tester.pumpAndSettle();

    // A tela não mostra convite: já há acesso neste aparelho.
    expect(find.byKey(const Key('pin_field')), findsOneWidget);
    expect(find.byKey(const Key('start_onboarding_button')), findsNothing);

    await entrarComPin(tester);

    // O par guardado no envelope foi reapresentado ao servidor.
    expect(backend.deviceLogins.single.deviceId, deviceId);
    expect(backend.deviceLogins.single.deviceSecret, secret);
    expect(find.text('Triagem rápida'), findsOneWidget);
    expect(find.byKey(const Key('pin_field')), findsNothing);
  });

  testWidgets('PIN errado mostra a mensagem local e não chama o servidor',
      (tester) async {
    final backend = FakePatientBackend();
    final store = FakeDeviceCredentialStore()
      ..enrollForTest(deviceId: deviceId, secret: secret, pin: pin);
    await tester.pumpWidget(app(backend, store));
    await tester.pumpAndSettle();

    await entrarComPin(tester, pinDigitado: '000000');

    // O PIN nunca sai do aparelho: PIN errado morre no envelope, e o servidor
    // não é consultado.
    expect(backend.deviceLogins, isEmpty);
    expect(store.unlockCalls, 1);
    expect(find.text('PIN incorreto. Tente de novo.'), findsOneWidget);
    expect(find.text('Triagem rápida'), findsNothing);
    expect(find.byKey(const Key('pin_field')), findsOneWidget);
  });

  testWidgets('tentativas demais bloqueiam com aviso ao vivo e voltam a liberar',
      (tester) async {
    final backend = FakePatientBackend();
    final store = FakeDeviceCredentialStore()
      ..enrollForTest(deviceId: deviceId, secret: secret, pin: pin);
    await tester.pumpWidget(app(backend, store));
    await tester.pumpAndSettle();

    for (var tentativa = 0; tentativa < 5; tentativa++) {
      await entrarComPin(tester, pinDigitado: '000000');
    }

    expect(find.byKey(const Key('pin_lockout_message')), findsOneWidget);
    final botao = tester.widget<FilledButton>(find.byKey(const Key('pin_unlock_button')));
    expect(botao.onPressed, isNull);

    // O relógio do fake avança além do bloqueio: a tela libera de novo.
    store.now = store.now.add(const Duration(seconds: 31));
    await tester.tap(find.byKey(const Key('pin_unlock_button')), warnIfMissed: false);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pin_lockout_message')), findsNothing);
  });

  testWidgets('recusa do servidor à credencial descarta a cópia local e volta ao convite',
      (tester) async {
    final backend = FakePatientBackend(
      loginDeviceFailure: const BackendFailure(
        'Credencial inválida ou revogada.',
        isRecoverable: false,
        credentialRefused: true,
      ),
    );
    final store = FakeDeviceCredentialStore()
      ..enrollForTest(deviceId: deviceId, secret: secret, pin: pin);
    await tester.pumpWidget(app(backend, store));
    await tester.pumpAndSettle();

    await entrarComPin(tester);

    // O aparelho nunca mais vai entrar com esta credencial: a cópia local
    // some e a tela oferece o convite de novo.
    expect(store.destroyCalls, 1);
    expect(store.hasCredential(), completion(isFalse));
    expect(find.byKey(const Key('start_onboarding_button')), findsOneWidget);
    expect(find.text('Credencial inválida ou revogada.'), findsOneWidget);
  });

  testWidgets('falha de rede no login NÃO descarta a credencial local',
      (tester) async {
    final backend = FakePatientBackend(
      loginDeviceFailure: const BackendFailure('Sem conexão com o servidor.'),
    );
    final store = FakeDeviceCredentialStore()
      ..enrollForTest(deviceId: deviceId, secret: secret, pin: pin);
    await tester.pumpWidget(app(backend, store));
    await tester.pumpAndSettle();

    await entrarComPin(tester);

    expect(store.destroyCalls, 0);
    expect(store.hasCredential(), completion(isTrue));
    expect(find.byKey(const Key('pin_field')), findsOneWidget);
    expect(find.text('Sem conexão com o servidor.'), findsOneWidget);
  });

  testWidgets('"Esqueceu o PIN" confirma e remove o acesso do aparelho',
      (tester) async {
    final backend = FakePatientBackend();
    final store = FakeDeviceCredentialStore()
      ..enrollForTest(deviceId: deviceId, secret: secret, pin: pin);
    await tester.pumpWidget(app(backend, store));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('forgot_pin_button')));
    await tester.pumpAndSettle();
    expect(find.text('Esqueceu o PIN?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('forgot_pin_confirm_button')));
    await tester.pumpAndSettle();

    expect(store.destroyCalls, 1);
    expect(find.byKey(const Key('start_onboarding_button')), findsOneWidget);
  });

  group('sessão expirada em uso', () {
    /// O fake não reimplementa a validação de token do `BackendClient` real —
    /// ele só devolve o que o teste mandar. Por isso a falha entra aqui do
    /// jeito que `_requireToken` a produz quando a sessão expirou.
    const sessaoExpirada = BackendFailure(
      'Sua sessão expirou. Entre novamente com o PIN.',
      isRecoverable: false,
    );

    testWidgets('oferece "Entrar novamente" e volta para a tela do PIN',
        (tester) async {
      final backend = FakePatientBackend();
      final store = FakeDeviceCredentialStore()
        ..enrollForTest(deviceId: deviceId, secret: secret, pin: pin);
      await tester.pumpWidget(app(backend, store));
      await tester.pumpAndSettle();
      await entrarComPin(tester);

      // A sessão de 1 hora acabou com o app aberto.
      backend
        ..expireSession()
        ..statusFailure = sessaoExpirada;
      await tester.tap(find.text('Status'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('session_expired_notice')), findsOneWidget);
      expect(find.byKey(const Key('reenter_button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('reenter_button')));
      await tester.pumpAndSettle();

      // De volta ao PIN: a credencial de dispositivo é reapresentável, sem
      // convite novo.
      expect(find.byKey(const Key('pin_field')), findsOneWidget);
    });

    testWidgets('não oferece quando a sessão continua válida', (tester) async {
      final backend = FakePatientBackend()
        ..statusFailure = const BackendFailure(
          'Este acesso não tem permissão para esta ação.',
          isRecoverable: false,
        );
      final store = FakeDeviceCredentialStore()
        ..enrollForTest(deviceId: deviceId, secret: secret, pin: pin);
      await tester.pumpWidget(app(backend, store));
      await tester.pumpAndSettle();
      await entrarComPin(tester);

      await tester.tap(find.text('Status'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('session_expired_notice')), findsNothing);
      expect(find.byKey(const Key('reenter_button')), findsNothing);
    });
  });
}
