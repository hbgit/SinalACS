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

  /// O `orderId` do pedido de limpeza remota do aparelho, ou `null` (#81).
  /// Público: o aparelho cujo token foi revogado precisa perguntar. Não devolve
  /// identidade; só o id do pedido, que é um UUID aleatório.
  Future<String?> pendingWipe(Session session, String deviceId) => AlertRuntime
      .instance
      .deviceWipeServiceFor(session)
      .pendingOrderId(deviceId);

  /// O aparelho confirma que apagou tudo (#81). Sem token e sem retorno: um par
  /// errado ou repetido se comporta igual (no-op), então não vira oráculo.
  Future<void> confirmWipe(
    Session session,
    String deviceId,
    String orderId,
  ) => AlertRuntime.instance
      .deviceWipeServiceFor(session)
      .confirm(deviceId, orderId);
}
