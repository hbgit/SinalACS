import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';

/// Acesso de desenvolvimento. **Não** é autenticação institucional.
///
/// Substitui `POST /v1/auth/development/login`, preservando o gate do
/// `ENABLE_DEV_LOGIN`: quando desligado, a chamada falha como se o endpoint não
/// existisse, e não como "proibido" — o servidor `dart:io` respondia 404 e não
/// 403, para não revelar a existência da rota.
class AuthEndpoint extends Endpoint {
  @override
  bool get requireLogin => false;

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
}
