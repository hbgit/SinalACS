import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_admin/app/app.dart';
import 'package:sinalacs_admin/core/auth/admin_auth_backend.dart';

import 'support/fake_admin_auth.dart';

Future<void> _preencher(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('matricula_field')), 'ADM-001');
  await tester.enterText(
    find.byKey(const Key('senha_field')),
    'segredo-de-teste',
  );
}

Future<void> _entrar(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('login_button')));
  await tester.pumpAndSettle();
}

const _codigo = 'ABCD-EFGH-JKLM-NPQR-STUV-WXYZ-23';

/// Etapa 1 da ativação (#48): o código de uso único vem antes do QR.
Future<void> _informarCodigoDeAtivacao(
  WidgetTester tester, [
  String codigo = _codigo,
]) async {
  await tester.enterText(
    find.byKey(const Key('activation_code_field')),
    codigo,
  );
  await tester.tap(find.byKey(const Key('activation_continue')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'credencial recusada mostra o erro em região viva e não abre o painel',
    (tester) async {
      final auth = FakeAdminAuth()
        ..failWith = const AdminAuthFailure('Matrícula ou senha inválidos.');
      await tester.pumpWidget(SinalAdminApp(auth: auth));
      await _preencher(tester);
      await _entrar(tester);

      expect(find.byKey(const Key('login_error')), findsOneWidget);
      expect(find.text('Matrícula ou senha inválidos.'), findsOneWidget);
      expect(find.text('Painel de Indicadores'), findsNothing);
      final regiaoViva = find.ancestor(
        of: find.byKey(const Key('login_error')),
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.liveRegion == true,
        ),
      );
      expect(regiaoViva, findsOneWidget);
      expect(auth.loginCalls, 1);
    },
  );

  testWidgets('MfaCodeRequired mostra totp_field e reenvia com o código', (
    tester,
  ) async {
    final auth = FakeAdminAuth()..requiresTotp = true;
    await tester.pumpWidget(SinalAdminApp(auth: auth));
    expect(find.byKey(const Key('totp_field')), findsNothing);

    await _preencher(tester);
    await _entrar(tester);
    expect(find.byKey(const Key('totp_field')), findsOneWidget);
    expect(find.text('Painel de Indicadores'), findsNothing);
    expect(
      auth.lastTotpCode,
      isNull,
      reason: 'a primeira chamada vai sem código',
    );

    await tester.enterText(find.byKey(const Key('totp_field')), '123456');
    await _entrar(tester);

    expect(auth.lastTotpCode, '123456');
    expect(auth.loginCalls, 2);
    expect(find.text('Painel de Indicadores'), findsOneWidget);
  });

  testWidgets('o campo do código só aceita dígitos e no máximo 6', (
    tester,
  ) async {
    final auth = FakeAdminAuth()..requiresTotp = true;
    await tester.pumpWidget(SinalAdminApp(auth: auth));
    await _preencher(tester);
    await _entrar(tester);

    await tester.enterText(find.byKey(const Key('totp_field')), '12ab34567890');
    final campo = tester.widget<TextField>(find.byKey(const Key('totp_field')));
    expect(campo.controller!.text, '123456');
    expect(campo.keyboardType, TextInputType.number);
  });

  testWidgets('mudar matrícula ou senha descarta o campo do código', (
    tester,
  ) async {
    final auth = FakeAdminAuth()..requiresTotp = true;
    await tester.pumpWidget(SinalAdminApp(auth: auth));
    await _preencher(tester);
    await _entrar(tester);
    await tester.enterText(find.byKey(const Key('totp_field')), '123456');
    expect(find.byKey(const Key('totp_field')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('matricula_field')), 'ADM-002');
    await tester.pump();
    expect(find.byKey(const Key('totp_field')), findsNothing);

    // Mesmo vale para a senha, e o código antigo não vaza para o reenvio.
    await _entrar(tester);
    expect(find.byKey(const Key('totp_field')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('totp_field')))
          .controller!
          .text,
      isEmpty,
    );
    await tester.enterText(find.byKey(const Key('senha_field')), 'outra-senha');
    await tester.pump();
    expect(find.byKey(const Key('totp_field')), findsNothing);
  });

  testWidgets(
    'MfaEnrollmentRequired abre a etapa do código de ativação, sem QR e sem chamar begin',
    (tester) async {
      final auth = FakeAdminAuth()
        ..failWith = const AdminMfaEnrollmentRequired();
      await tester.pumpWidget(SinalAdminApp(auth: auth));
      await _preencher(tester);
      await _entrar(tester);

      expect(find.byKey(const Key('activation_code_field')), findsOneWidget);
      expect(find.byKey(const Key('mfa_secret')), findsNothing);
      expect(find.byKey(const Key('mfa_code_field')), findsNothing);
      expect(find.text('Painel de Indicadores'), findsNothing);
      expect(
        auth.enrollmentBegins,
        0,
        reason: 'sem o código, o app nem pede o segredo',
      );
    },
  );

  testWidgets('código de ativação vazio não chama o servidor e pede o código', (
    tester,
  ) async {
    final auth = FakeAdminAuth()..failWith = const AdminMfaEnrollmentRequired();
    await tester.pumpWidget(SinalAdminApp(auth: auth));
    await _preencher(tester);
    await _entrar(tester);

    await tester.tap(find.byKey(const Key('activation_continue')));
    await tester.pumpAndSettle();

    expect(find.text('Informe o código de ativação.'), findsOneWidget);
    expect(auth.enrollmentBegins, 0);
  });

  testWidgets(
    'com o código, begin recebe exatamente o que foi digitado e o QR aparece',
    (tester) async {
      final auth = FakeAdminAuth()
        ..failWith = const AdminMfaEnrollmentRequired();
      await tester.pumpWidget(SinalAdminApp(auth: auth));
      await _preencher(tester);
      await _entrar(tester);
      await _informarCodigoDeAtivacao(tester);

      expect(auth.enrollmentBegins, 1);
      expect(auth.lastActivationCode, _codigo);
      expect(find.byKey(const Key('mfa_secret')), findsOneWidget);
      expect(find.text('JBSWY3DPEHPK3PXP'), findsOneWidget);
      expect(find.byKey(const Key('mfa_code_field')), findsOneWidget);
    },
  );

  testWidgets('código de ativação recusado mostra o erro e o QR não aparece', (
    tester,
  ) async {
    final auth = FakeAdminAuth()
      ..failWith = const AdminMfaEnrollmentRequired()
      ..beginFailWith = const AdminAuthFailure(
        'Código de ativação inválido ou expirado.',
      );
    await tester.pumpWidget(SinalAdminApp(auth: auth));
    await _preencher(tester);
    await _entrar(tester);
    await _informarCodigoDeAtivacao(tester, 'ERRADO');

    expect(find.byKey(const Key('activation_error')), findsOneWidget);
    expect(
      find.text('Código de ativação inválido ou expirado.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('mfa_secret')), findsNothing);
    expect(
      find.byKey(const Key('activation_code_field')),
      findsOneWidget,
      reason: 'dá para tentar de novo',
    );
  });

  testWidgets(
    'confirmar a ativação envia o mesmo código, volta ao login com o aviso e pede o código',
    (tester) async {
      final auth = FakeAdminAuth()
        ..failWith = const AdminMfaEnrollmentRequired();
      await tester.pumpWidget(SinalAdminApp(auth: auth));
      await _preencher(tester);
      await _entrar(tester);
      await _informarCodigoDeAtivacao(tester);

      await tester.enterText(find.byKey(const Key('mfa_code_field')), '654321');
      await tester.tap(find.byKey(const Key('mfa_confirm_button')));
      await tester.pumpAndSettle();

      expect(auth.lastEnrollmentCode, '654321');
      expect(auth.lastActivationCode, _codigo);
      expect(find.byKey(const Key('mfa_secret')), findsNothing);
      expect(
        find.text('Verificação ativada. Entre com o código do aplicativo.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('totp_field')), findsOneWidget);
    },
  );

  testWidgets('falha ao confirmar a ativação mostra o erro e fica na tela', (
    tester,
  ) async {
    final auth = FakeAdminAuth()
      ..failWith = const AdminMfaEnrollmentRequired()
      ..confirmFailWith = const AdminAuthFailure('Código inválido.');
    await tester.pumpWidget(SinalAdminApp(auth: auth));
    await _preencher(tester);
    await _entrar(tester);
    await _informarCodigoDeAtivacao(tester);

    await tester.enterText(find.byKey(const Key('mfa_code_field')), '000000');
    await tester.tap(find.byKey(const Key('mfa_confirm_button')));
    await tester.pumpAndSettle();

    expect(find.text('Código inválido.'), findsOneWidget);
    expect(find.byKey(const Key('mfa_secret')), findsOneWidget);
  });

  testWidgets(
    'não existe caminho de entrada sem chamar o backend (sem bypass)',
    (tester) async {
      final auth = FakeAdminAuth();
      await tester.pumpWidget(SinalAdminApp(auth: auth));
      await _entrar(tester); // campos vazios não autenticam

      expect(find.text('Painel de Indicadores'), findsNothing);
      expect(auth.loginCalls, 0, reason: 'campo vazio nem chega ao backend');
      expect(find.byKey(const Key('login_error')), findsOneWidget);
      expect(find.byKey(const Key('dev_banner')), findsNothing);
      expect(find.byKey(const Key('dev_login_disabled_notice')), findsNothing);
    },
  );

  testWidgets('sessão vencida volta ao login com a mensagem', (tester) async {
    final auth = FakeAdminAuth(
      session: AdminSession(
        accessToken: 't',
        userId: 'ADM-001',
        role: 'admin',
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      ),
    );
    await tester.pumpWidget(SinalAdminApp(auth: auth));
    await _preencher(tester);
    await _entrar(tester);

    expect(find.byKey(const Key('login_button')), findsOneWidget);
    expect(find.text('Sessão encerrada. Entre novamente.'), findsOneWidget);
    expect(find.text('Painel de Indicadores'), findsNothing);
  });

  testWidgets('sessão que vence com o painel aberto volta ao login', (
    tester,
  ) async {
    final auth = FakeAdminAuth(
      session: AdminSession(
        accessToken: 't',
        userId: 'ADM-001',
        role: 'admin',
        expiresAt: DateTime.now().add(const Duration(seconds: 5)),
      ),
    );
    await tester.pumpWidget(SinalAdminApp(auth: auth));
    await _preencher(tester);
    await _entrar(tester);
    expect(find.text('Painel de Indicadores'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login_button')), findsOneWidget);
    expect(find.text('Sessão encerrada. Entre novamente.'), findsOneWidget);
  });
}
