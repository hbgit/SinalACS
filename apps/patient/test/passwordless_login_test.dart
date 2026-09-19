import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/app/app.dart';
import 'package:sinalacs_patient/core/network/backend_client.dart';

import 'support/fake_patient_backend.dart';

/// Fluxo de login do paciente (RF01): CPF + data de nascimento → código OTP →
/// sessão. Nenhum CPF real: `123.456.789-09` é o exemplo da documentação do
/// algoritmo, o mesmo que o backend usa nos testes dele.
void main() {
  Future<void> pedirCodigo(
    WidgetTester tester, {
    String cpf = '123.456.789-09',
    String nascimento = '01/01/1990',
  }) async {
    await tester.enterText(find.byKey(const Key('cpf_field')), cpf);
    await tester.enterText(find.byKey(const Key('birth_date_field')), nascimento);
    await tester.tap(find.byKey(const Key('enter_button')));
    await tester.pumpAndSettle();
  }

  testWidgets('pede o código e avança para o passo do código', (tester) async {
    final backend = FakePatientBackend();
    await tester.pumpWidget(SinalAcsApp(backend: backend));

    await pedirCodigo(tester, cpf: '12345678909');

    // A máscara importa: o backend normaliza de qualquer forma, mas o app tem
    // um formato de exibição próprio, e é ele que sai daqui — a pessoa vê
    // `123.456.789-09` e é `123.456.789-09` que vai para o servidor.
    expect(backend.lastOtpRequest?.cpf, '123.456.789-09');
    expect(backend.lastOtpRequest?.birthDate, DateTime.utc(1990, 1, 1));
    expect(find.byKey(const Key('otp_code_field')), findsOneWidget);
    // O passo das credenciais sai de cena, para não haver dois formulários
    // concorrentes na mesma tela.
    expect(find.byKey(const Key('cpf_field')), findsNothing);
  });

  testWidgets('data de nascimento inválida não chama o backend', (tester) async {
    final handle = tester.ensureSemantics();
    final backend = FakePatientBackend();
    await tester.pumpWidget(SinalAcsApp(backend: backend));

    await pedirCodigo(tester, nascimento: '99/99/9999');

    // O servidor responde igual para "não existe" e "data errada": uma data que
    // não converte tem de morrer no app, senão o pedido some em silêncio.
    expect(backend.lastOtpRequest, isNull);
    expect(find.textContaining('Confira a data'), findsOneWidget);
    expect(find.byKey(const Key('otp_code_field')), findsNothing);
    // SC 4.1.3: o erro aparece sem mover o foco.
    final semantics = tester.getSemantics(find.byKey(const Key('login_error')));
    expect(semantics.flagsCollection.isLiveRegion, isTrue);
    handle.dispose();
  });

  testWidgets('dia que não existe no mês também é recusado', (tester) async {
    final backend = FakePatientBackend();
    await tester.pumpWidget(SinalAcsApp(backend: backend));

    // `DateTime.utc(1990, 2, 31)` viraria 03/03 sem reclamar — e o app mandaria
    // para o servidor uma data que não é a que a pessoa digitou.
    await pedirCodigo(tester, nascimento: '31/02/1990');

    expect(backend.lastOtpRequest, isNull);
    expect(find.textContaining('Confira a data'), findsOneWidget);
  });

  testWidgets('código correto abre o painel', (tester) async {
    final backend = FakePatientBackend();
    await tester.pumpWidget(SinalAcsApp(backend: backend));

    await pedirCodigo(tester);
    await tester.enterText(find.byKey(const Key('otp_code_field')), '123456');
    await tester.tap(find.byKey(const Key('verify_code_button')));
    await tester.pumpAndSettle();

    expect(backend.otpVerifications.single.cpf, '123.456.789-09');
    expect(backend.otpVerifications.single.code, '123456');
    expect(find.text('Triagem rápida'), findsOneWidget);
    expect(find.byKey(const Key('cpf_field')), findsNothing);
  });

  testWidgets('código errado mostra a mensagem do servidor e não abre o painel', (tester) async {
    final backend = FakePatientBackend();
    await tester.pumpWidget(SinalAcsApp(backend: backend));

    await pedirCodigo(tester);
    await tester.enterText(find.byKey(const Key('otp_code_field')), '000000');
    await tester.tap(find.byKey(const Key('verify_code_button')));
    await tester.pumpAndSettle();

    expect(find.text('Triagem rápida'), findsNothing);
    expect(find.text('Código inválido ou expirado. Peça um novo.'), findsOneWidget);
    // Continua no passo do código: quem errou um dígito não deve ter de
    // redigitar CPF e nascimento.
    expect(find.byKey(const Key('otp_code_field')), findsOneWidget);
  });

  testWidgets('"Pedir outro código" volta ao passo anterior sem repetir o pedido', (tester) async {
    final backend = FakePatientBackend();
    await tester.pumpWidget(SinalAcsApp(backend: backend));

    await pedirCodigo(tester);
    await tester.tap(find.byKey(const Key('request_new_code_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cpf_field')), findsOneWidget);
    expect(find.byKey(const Key('otp_code_field')), findsNothing);
    // O pedido não se repete sozinho: dentro do intervalo mínimo o servidor
    // não manda um código novo — e, desde 2026-09-19, também não diz que
    // esperou (uma recusa aqui seria o oráculo de "este par existe").
    expect(backend.otpRequests, hasLength(1));
  });

  testWidgets('recusa ao pedir o código aparece na tela, sem avançar', (tester) async {
    // A recusa que o servidor ainda emite neste passo é o dígito verificador
    // inválido (`Cpf.tryParse` devolve null no endpoint, e o app não valida o
    // DV por conta própria — ele só mascara o que a pessoa digitou). Era aqui
    // que este teste usava "Aguarde um minuto": essa mensagem deixou de existir
    // no servidor em 2026-09-19, porque só era alcançável por quem já acertou
    // CPF e nascimento — o próprio oráculo do par. O aviso de espera passou a
    // ser responsabilidade DESTE lado (o app sabe quando pediu por último) e
    // ainda não foi implementado; ver `PROGRESS.md`.
    final backend = FakePatientBackend(
      requestOtpFailure: const BackendFailure(
        'Confira os dados informados.',
        isRecoverable: false,
      ),
    );
    await tester.pumpWidget(SinalAcsApp(backend: backend));

    await pedirCodigo(tester);

    expect(find.text('Confira os dados informados.'), findsOneWidget);
    expect(find.byKey(const Key('otp_code_field')), findsNothing);
  });

  group('sessão expirada em uso', () {
    /// O fake não reimplementa a validação de token do `BackendClient` real —
    /// ele só devolve o que o teste mandar. Por isso a falha entra aqui do
    /// jeito que `_requireToken` a produz quando a sessão expirou, com a mesma
    /// sessão expirada no backend.
    const sessaoExpirada = BackendFailure(
      'Sua sessão expirou. Entre novamente com o código de acesso.',
      isRecoverable: false,
    );

    Future<void> abrirStatus(WidgetTester tester) async {
      await tester.tap(find.text('Status'));
      await tester.pumpAndSettle();
    }

    testWidgets('oferece "Entrar novamente" e volta para a tela de login', (tester) async {
      final backend = FakePatientBackend();
      await tester.pumpWidget(SinalAcsApp(backend: backend));

      await pedirCodigo(tester);
      await tester.enterText(find.byKey(const Key('otp_code_field')), '123456');
      await tester.tap(find.byKey(const Key('verify_code_button')));
      await tester.pumpAndSettle();

      // A sessão de 1 hora acabou com o app aberto.
      backend
        ..expireSession()
        ..statusFailure = sessaoExpirada;
      await abrirStatus(tester);

      expect(find.byKey(const Key('session_expired_notice')), findsOneWidget);
      expect(find.byKey(const Key('reenter_button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('reenter_button')));
      await tester.pumpAndSettle();

      // De volta ao começo: o paciente não tem renovação silenciosa, então o
      // único caminho é pedir um código novo.
      expect(find.byKey(const Key('cpf_field')), findsOneWidget);
      expect(find.text('Acesso sem senha'), findsOneWidget);
    });

    testWidgets('não oferece quando a sessão continua válida', (tester) async {
      final backend = FakePatientBackend()
        // Falha não recuperável, mas nada a ver com sessão: repetir o login não
        // resolveria nada.
        ..statusFailure = const BackendFailure(
          'Este acesso não tem permissão para esta ação.',
          isRecoverable: false,
        );
      await tester.pumpWidget(SinalAcsApp(backend: backend));

      await pedirCodigo(tester);
      await tester.enterText(find.byKey(const Key('otp_code_field')), '123456');
      await tester.tap(find.byKey(const Key('verify_code_button')));
      await tester.pumpAndSettle();

      await abrirStatus(tester);

      expect(find.byKey(const Key('session_expired_notice')), findsNothing);
      expect(find.byKey(const Key('reenter_button')), findsNothing);
    });
  });
}
