import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/auth/cpf.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';

/// Autenticação. `developmentLogin` é acesso de desenvolvimento e **não** é
/// autenticação institucional; `loginInstitutional` é o caminho real (RF07);
/// `requestOtp`/`verifyOtp` são o login passwordless do paciente (RF01).
///
/// `developmentLogin` substitui `POST /v1/auth/development/login`, preservando
/// o gate do `ENABLE_DEV_LOGIN`: quando desligado, a chamada falha como se o
/// endpoint não existisse, e não como "proibido" — o servidor `dart:io`
/// respondia 404 e não 403, para não revelar a existência da rota.
class AuthEndpoint extends Endpoint {
  @override
  bool get requireLogin => false;

  /// TTL da sessão do paciente (LGPD-RT06). O ACS continua nos 15 minutos
  /// padrão — a renovação dele é silenciosa, por credencial em memória.
  static const patientSessionLifetime = Duration(hours: 1);

  /// UUIDs fixos do seed de desenvolvimento. Dados sintéticos.
  static const _patient = AuthenticatedUser(
    id: '00000000-0000-4000-8000-000000000001',
    role: UserRole.patient,
    microAreaId: '00000000-0000-4000-8000-000000000003',
    deviceId: 'patient-device-001',
  );

  static const _acs = AuthenticatedUser(
    id: '00000000-0000-4000-8000-000000000002',
    role: UserRole.acs,
    microAreaId: '00000000-0000-4000-8000-000000000003',
    deviceId: 'acs-device-001',
  );

  Future<DevelopmentLoginResult> developmentLogin(
    Session session, {
    required String role,
  }) async {
    final runtime = AlertRuntime.instance;
    if (!runtime.config.enableDevLogin) {
      throw EndpointDisabledException(message: 'not found');
    }

    final user = switch (role) {
      'patient' => _patient,
      'acs' => _acs,
      _ => null,
    };
    if (user == null) {
      throw AlertValidationException(
        message: 'role deve ser patient ou acs',
      );
    }

    return DevelopmentLoginResult(
      accessToken: runtime.auth.issueToken(user),
      tokenType: 'Bearer',
    );
  }

  /// Login institucional do ACS (RF07): matrícula + senha.
  ///
  /// Não é gated por `ENABLE_DEV_LOGIN` — é o caminho real, e o gate existe
  /// para o *outro* método. As recusas chegam ao app como
  /// `AuthenticationFailedException`, com a mensagem que o serviço escolheu:
  /// mensagem idêntica para matrícula inexistente e senha errada (ver
  /// `InstitutionalAuthService`).
  Future<DevelopmentLoginResult> loginInstitutional(
    Session session, {
    required String matricula,
    required String password,
    String? deviceId,
  }) async {
    final runtime = AlertRuntime.instance;

    final user = await runtime.institutionalAuthServiceFor(session).login(
          matricula: matricula,
          password: password,
          deviceId: deviceId,
        );

    return DevelopmentLoginResult(
      accessToken: runtime.auth.issueToken(user),
      tokenType: 'Bearer',
    );
  }

  /// Pedido do código de acesso (RF01). Público por definição: quem chama
  /// ainda não tem sessão. A resposta é sempre a mesma — não revela se o CPF
  /// está cadastrado (ver `PasswordlessAuthService.requestOtp`).
  ///
  /// O CPF é validado aqui, **antes** de virar hash: um número com dígito
  /// verificador errado é erro de digitação, e tratá-lo como "não encontrado"
  /// mandaria o paciente para a tela do código com um CPF que nunca vai casar.
  /// A recusa não distingue esse caso de nenhum outro para quem sonda, porque
  /// `Cpf.tryParse` devolve `null` sem dizer o motivo.
  ///
  /// Data de nascimento no futuro não é validada aqui de propósito: quem decide
  /// se a data confere com o cadastro é o serviço, e uma checagem de faixa
  /// étaria no endpoint seria mais um sinal distinguível.
  Future<void> requestOtp(
    Session session, {
    required String cpf,
    required DateTime birthDate,
  }) async {
    final parsed = Cpf.tryParse(cpf);
    if (parsed == null) {
      throw OtpRequestException(message: 'Confira os dados informados.');
    }

    await AlertRuntime.instance
        .passwordlessAuthServiceFor(session)
        .requestOtp(cpf: parsed, birthDate: birthDate);
  }

  /// Verificação do código, que emite a sessão do paciente (RF01).
  ///
  /// Público pelo mesmo motivo de [requestOtp] — é esta chamada que **emite** a
  /// sessão —, e o token sai com o papel `patient` e a microárea lida do
  /// cadastro pelo serviço, nunca de parâmetro.
  ///
  /// Toda recusa chega ao app como `OtpRequestException`, com a mensagem que o
  /// serviço escolheu: uma só, para não dizer se aquele CPF existe.
  Future<DevelopmentLoginResult> verifyOtp(
    Session session, {
    required String cpf,
    required String code,
    String? deviceId,
  }) async {
    final parsed = Cpf.tryParse(cpf);
    if (parsed == null) {
      throw OtpRequestException(
        message: 'Código inválido ou expirado. Peça um novo.',
      );
    }

    final runtime = AlertRuntime.instance;
    final user = await runtime
        .passwordlessAuthServiceFor(session)
        .verifyOtp(cpf: parsed, code: code, deviceId: deviceId);

    return DevelopmentLoginResult(
      // 1 hora **neste caminho**, o de login com OTP verificado — que é o que
      // `spec/lgpd_design.md` LGPD-RT06 exige para o paciente. Não é o TTL de
      // toda sessão de paciente: há dois caminhos de emissão, e o de onboarding
      // (`onboarding_endpoint.dart`) ainda emite o padrão de 15 minutos, lacuna
      // do RF02 registrada no plano.
      // Com o padrão de 15 minutos, e sem refresh token, o paciente teria de
      // receber um SMS novo a cada 15 minutos: o código OTP não pode ser
      // reapresentado como a senha do ACS pode, então não existe renovação
      // silenciosa para o paciente. Ver as Global Constraints do plano.
      accessToken: runtime.auth.issueToken(
        user,
        lifetime: patientSessionLifetime,
      ),
      tokenType: 'Bearer',
    );
  }
}
