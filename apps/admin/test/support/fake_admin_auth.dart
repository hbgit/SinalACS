import 'package:serverpod_client/serverpod_client.dart';
import 'package:sinalacs_admin/core/auth/admin_auth_backend.dart';

/// Chamador de endpoint falso: a próxima chamada lança [error] ou devolve
/// [result]. Permite exercitar o `EndpointAuth` real sem rede.
class FakeEndpointCaller implements EndpointCaller {
  FakeEndpointCaller({this.error, this.result});
  Object? error;
  Object? result;
  Map<String, dynamic>? lastArgs;

  @override
  Future<T> callServerEndpoint<T>(
    String endpoint,
    String method,
    Map<String, dynamic> args, {
    bool authenticated = true,
  }) async {
    lastArgs = args;
    if (error != null) throw error!;
    return result as T;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// [AdminAuthBackend] em memória para testes de tela.
class FakeAdminAuth implements AdminAuthBackend {
  FakeAdminAuth({this.session});

  /// Sessão devolvida no sucesso; `null` gera uma de papel `admin` válida por 1 h.
  AdminSession? session;

  /// Lançada por `login` (e só por ele) quando não for `null`.
  Object? failWith;

  /// Quando `true`, `login` sem código lança [AdminMfaCodeRequired].
  bool requiresTotp = false;

  /// Último código TOTP recebido por `login`.
  String? lastTotpCode;

  /// Última matrícula/senha recebidas por `login`.
  String? lastMatricula;
  String? lastSenha;

  int loginCalls = 0;

  /// Lançada por `confirmMfaEnrollment` quando não for `null`.
  Object? confirmFailWith;
  String? lastEnrollmentCode;
  int enrollmentBegins = 0;

  @override
  Future<AdminSession> login({
    required String matricula,
    required String senha,
    String? totpCode,
  }) async {
    loginCalls++;
    lastMatricula = matricula;
    lastSenha = senha;
    lastTotpCode = totpCode;
    if (failWith != null) throw failWith!;
    if (requiresTotp && (totpCode == null || totpCode.isEmpty)) {
      throw const AdminMfaCodeRequired();
    }
    return session ??
        AdminSession(
          accessToken: 'token-de-teste',
          userId: 'ADM-001',
          role: 'admin',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        );
  }

  @override
  Future<({String secret, String otpauthUri})> beginMfaEnrollment({
    required String matricula,
    required String senha,
  }) async {
    enrollmentBegins++;
    return (
      secret: 'JBSWY3DPEHPK3PXP',
      otpauthUri: 'otpauth://totp/x?secret=JBSWY3DPEHPK3PXP',
    );
  }

  @override
  Future<void> confirmMfaEnrollment({
    required String matricula,
    required String senha,
    required String code,
  }) async {
    lastEnrollmentCode = code;
    if (confirmFailWith != null) throw confirmFailWith!;
  }
}
