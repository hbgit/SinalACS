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
  FakeAdminAuth({this.session, this.failure});
  AdminSession? session;
  AdminAuthFailure? failure;

  @override
  Future<AdminSession> login({
    required String matricula,
    required String senha,
    String? totpCode,
  }) async {
    if (failure != null) throw failure!;
    return session!;
  }

  @override
  Future<({String secret, String otpauthUri})> beginMfaEnrollment({
    required String matricula,
    required String senha,
  }) async => (
    secret: 'JBSWY3DPEHPK3PXP',
    otpauthUri: 'otpauth://totp/x?secret=JBSWY3DPEHPK3PXP',
  );

  @override
  Future<void> confirmMfaEnrollment({
    required String matricula,
    required String senha,
    required String code,
  }) async {}
}
