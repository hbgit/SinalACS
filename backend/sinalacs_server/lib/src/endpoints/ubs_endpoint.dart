import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/endpoints/authenticated_endpoint.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';

/// Contato da UBS do ACS (RF13).
class UbsEndpoint extends AuthenticatedEndpoint {
  Future<UbsContact> myContact(
    Session session, {
    required String accessToken,
  }) async {
    final user = authenticate(accessToken);
    try {
      return await AlertRuntime.instance.ubsContactServiceFor(session).contactFor(user);
    } on StateError catch (error) {
      throw AlertPermissionException(message: error.message);
    }
  }
}
