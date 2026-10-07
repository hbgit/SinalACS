import 'dart:convert';
import 'dart:io';

import 'package:sinalacs_client/sinalacs_client.dart';

import 'backend_config.dart';

/// Sessão do staff (coordenador/administrador). Nunca registre o token em log.
class AdminSession {
  const AdminSession({
    required this.accessToken,
    required this.userId,
    required this.role,
    required this.expiresAt,
  });

  final String accessToken;
  final String userId;

  /// `coordinator` ou `admin`.
  final String role;
  final DateTime expiresAt;

  static const papeisDeStaff = {'coordinator', 'admin'};

  /// Lê o payload do JWT **sem verificar a assinatura** (papel do servidor; o
  /// app não tem o segredo HMAC). Recusa papel que não é de staff mesmo que o
  /// servidor o tenha emitido, e token malformado.
  factory AdminSession.fromToken(String accessToken) {
    const invalido = AdminAuthFailure(
      'O servidor devolveu um token que o aplicativo não entendeu.',
    );
    final partes = accessToken.split('.');
    if (partes.length != 3) throw invalido;
    final Object? payload;
    try {
      payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(partes[1]))),
      );
    } on FormatException {
      throw invalido;
    }
    if (payload is! Map<String, dynamic>) throw invalido;
    final exp = payload['exp'];
    final sub = payload['sub'];
    final role = payload['role'];
    if (exp is! int || sub is! String || role is! String) throw invalido;
    if (!papeisDeStaff.contains(role)) {
      throw const AdminAuthFailure('Esta conta não tem acesso ao backoffice.');
    }
    return AdminSession(
      accessToken: accessToken,
      userId: sub,
      role: role,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true),
    );
  }
}

class AdminAuthFailure implements Exception {
  const AdminAuthFailure(this.message);
  final String message;

  @override
  String toString() => 'AdminAuthFailure: $message';
}

class AdminMfaCodeRequired extends AdminAuthFailure {
  const AdminMfaCodeRequired()
    : super('Informe o código do aplicativo autenticador.');
}

class AdminMfaEnrollmentRequired extends AdminAuthFailure {
  const AdminMfaEnrollmentRequired()
    : super('Ative a verificação em duas etapas antes de entrar.');
}

abstract interface class AdminAuthBackend {
  Future<AdminSession> login({
    required String matricula,
    required String senha,
    String? totpCode,
  });

  Future<({String secret, String otpauthUri})> beginMfaEnrollment({
    required String matricula,
    required String senha,
  });

  Future<void> confirmMfaEnrollment({
    required String matricula,
    required String senha,
    required String code,
  });
}

/// Cria o [Client] para um host. Seam: os testes não constroem o real.
typedef AdminClientFactory = Client Function(String host);

Client _clienteReal(String host) => Client(host)..connectivityMonitor = null;

/// Implementação sobre `auth.loginStaff` e a ativação de MFA do staff.
class BackendAdminAuth implements AdminAuthBackend {
  /// [auth] é o endpoint já resolvido (testes passam um com chamador falso).
  BackendAdminAuth(EndpointAuth auth) : _auth = auth;

  /// Cria o cliente a partir do host (https obrigatório no default de
  /// compilação; um host explícito passa como veio, como no app do ACS).
  factory BackendAdminAuth.forHost({
    String? host,
    AdminClientFactory clientFactory = _clienteReal,
  }) {
    final h =
        host ?? AdminBackendConfig.requireSecureHost(AdminBackendConfig.host);
    return BackendAdminAuth(clientFactory(h).auth);
  }

  final EndpointAuth _auth;

  @override
  Future<AdminSession> login({
    required String matricula,
    required String senha,
    String? totpCode,
  }) async {
    final result = await _guard(
      () => _auth.loginStaff(
        matricula: matricula,
        password: senha,
        totpCode: totpCode,
      ),
    );
    return AdminSession.fromToken(result.accessToken);
  }

  @override
  Future<({String secret, String otpauthUri})> beginMfaEnrollment({
    required String matricula,
    required String senha,
  }) async {
    final r = await _guard(
      () =>
          _auth.beginStaffTotpEnrollment(matricula: matricula, password: senha),
    );
    return (secret: r.secretBase32, otpauthUri: r.otpauthUri);
  }

  @override
  Future<void> confirmMfaEnrollment({
    required String matricula,
    required String senha,
    required String code,
  }) => _guard(
    () => _auth.confirmStaffTotpEnrollment(
      matricula: matricula,
      password: senha,
      code: code,
    ),
  );

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on AdminAuthFailure {
      rethrow;
    } on MfaRequiredException {
      throw const AdminMfaCodeRequired();
    } on MfaEnrollmentRequiredException {
      throw const AdminMfaEnrollmentRequired();
    } on AuthenticationFailedException catch (e) {
      // O texto vem do servidor de propósito: distingue "credencial inválida"
      // de "acesso bloqueado por tentativas", sem revelar matrículas.
      throw AdminAuthFailure(e.message);
    } on SocketException {
      throw const AdminAuthFailure('Não foi possível conectar ao servidor.');
    } on ServerpodClientException {
      throw const AdminAuthFailure('Não foi possível conectar ao servidor.');
    } catch (_) {
      throw const AdminAuthFailure('Não foi possível conectar ao servidor.');
    }
  }
}
