import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/app/app.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';

import 'support/fakes.dart';
import 'support/layout_harness.dart' show assentar;

Future<void> entrar(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('matricula_field')), 'ACS-001');
  await tester.enterText(find.byKey(const Key('senha_field')), 'senha-sintetica');
  await tester.tap(find.byKey(const Key('login_button')));
}

void main() {
  // 1. MFA exigida: depois de matrícula+senha, aparece o campo de código e o painel NÃO abre.
  testWidgets('pede o código do autenticador depois de matrícula e senha', (tester) async {
    final backend = FakeAcsBackend()..expectedTotpCode = '123456';
    await tester.pumpWidget(SinalAcsApp(backend: backend, feedBuilder: (q) => FakeAlertFeed(q)));
    await entrar(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('totp_field')), findsOneWidget);
    expect(find.byKey(const Key('login_button')), findsOneWidget, reason: 'o painel não abriu');
  });

  // 2. Código certo: entra, e o app reenviou matrícula+senha COM o código.
  testWidgets('com o código certo, entra', (tester) async {
    final backend = FakeAcsBackend()..expectedTotpCode = '123456';
    await tester.pumpWidget(SinalAcsApp(backend: backend, feedBuilder: (q) => FakeAlertFeed(q)));
    await entrar(tester);
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('totp_field')), '123456');
    await tester.tap(find.byKey(const Key('login_button')));
    await tester.pumpAndSettle();

    expect(backend.lastTotpCode, '123456');
    expect(find.byKey(const Key('login_button')), findsNothing, reason: 'o painel abriu');
  });

  // 3. Código errado: erro visível, painel fechado, campo continua.
  testWidgets('com o código errado, mostra o erro e fica no login', (tester) async {
    final backend = FakeAcsBackend()..expectedTotpCode = '123456';
    await tester.pumpWidget(SinalAcsApp(backend: backend, feedBuilder: (q) => FakeAlertFeed(q)));
    await entrar(tester);
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('totp_field')), '000000');
    await tester.tap(find.byKey(const Key('login_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login_error')), findsOneWidget);
    expect(find.byKey(const Key('totp_field')), findsOneWidget);
  });

  // 4. Servidor exige MFA e o ACS não a tem: vai para a tela de ativação, com segredo e campo de código.
  testWidgets('sem MFA ativada, leva à ativação e confirma com o código', (tester) async {
    final backend = FakeAcsBackend()..mfaEnrollmentRequired = true;
    await tester.pumpWidget(SinalAcsApp(backend: backend, feedBuilder: (q) => FakeAlertFeed(q)));
    await entrar(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mfa_secret')), findsOneWidget);
    expect(find.textContaining('GEZDGNBVGY3TQOJQ'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('mfa_code_field')), '654321');
    await tester.tap(find.byKey(const Key('mfa_confirm_button')));
    await tester.pumpAndSettle();

    expect(backend.confirmedCode, '654321');
    expect(find.text('Aguarde o próximo código do autenticador.'), findsOneWidget);
    // Voltou ao login, pronto para entrar de novo (agora com MFA).
    expect(find.byKey(const Key('login_button')), findsOneWidget);
  });

  // 5. O código é só dígitos: o campo recusa letras e passa de 6.
  testWidgets('o campo de código aceita só 6 dígitos', (tester) async {
    final backend = FakeAcsBackend()..expectedTotpCode = '123456';
    await tester.pumpWidget(SinalAcsApp(backend: backend, feedBuilder: (q) => FakeAlertFeed(q)));
    await entrar(tester);
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('totp_field')), '12ab34567');

    final campo = tester.widget<TextField>(find.byKey(const Key('totp_field')));
    expect(campo.controller!.text, '123456', reason: 'letras caem fora e o 7º dígito não entra');
    expect(campo.keyboardType, TextInputType.number);
  });

  testWidgets('falha ao iniciar a ativação mostra o erro e deixa tentar de novo', (tester) async {
    final backend = FakeAcsBackend()
      ..mfaEnrollmentRequired = true
      ..enrollmentFailuresLeft = 1;
    await tester.pumpWidget(SinalAcsApp(backend: backend, feedBuilder: (q) => FakeAlertFeed(q)));
    await entrar(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mfa_error')), findsOneWidget);
    expect(find.byKey(const Key('mfa_secret')), findsNothing);

    await tester.tap(find.byKey(const Key('mfa_retry_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mfa_secret')), findsOneWidget);
    expect(find.byKey(const Key('mfa_error')), findsNothing);
  });

  testWidgets('o painel volta ao login com o aviso, sem perder a fila', (tester) async {
    final fake = FakeAcsBackend();
    final fila = OfflineVisitQueue();
    await fila.add(OfflineVisitRecord(patientId: seedPatientId, risk: 'red', status: 'PENDENTE'));
    await tester.pumpWidget(SinalAcsApp(backend: fake, visitQueue: fila, feedBuilder: (q) => FakeAlertFeed(q)));
    await tester.enterText(find.byKey(const Key('matricula_field')), 'ACS-001');
    await tester.enterText(find.byKey(const Key('senha_field')), 'senha-sintetica');
    await tester.tap(find.byKey(const Key('login_button')));
    await assentar(tester);
    expect(find.byKey(const Key('login_button')), findsNothing, reason: 'o painel abriu');

    fake.onSessionExpired!();
    await assentar(tester);

    expect(find.byKey(const Key('login_button')), findsOneWidget);
    expect(find.text('Sua sessão expirou. Entre novamente com o código do autenticador.'), findsOneWidget);
    expect(fila.pendingCount, 1);
  });
}
