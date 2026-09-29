import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/endpoints/authenticated_endpoint.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';

/// Aparelhos do paciente para avisos segmentados (RF14, decisão §3.2).
class DevicesEndpoint extends AuthenticatedEndpoint {
  /// Registra o token de push do aparelho do paciente autenticado. Só grava com
  /// o consentimento `segmentedPush` vigente; sem ele, [DataRightsException].
  Future<void> registerPushToken(
    Session session, {
    required String accessToken,
    required String token,
    required String platform,
  }) async {
    final user = authenticate(accessToken);

    try {
      await AlertRuntime.instance
          .pushTokenServiceFor(session)
          .register(user, token: token, platform: platform);
    } on StateError catch (error) {
      throw AlertPermissionException(message: error.message);
    }
  }
}
