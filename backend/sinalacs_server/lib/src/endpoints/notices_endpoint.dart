import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/endpoints/authenticated_endpoint.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';

/// Avisos comunitários do ACS (RF14, decisão §3.2).
class NoticesEndpoint extends AuthenticatedEndpoint {
  /// Envia um aviso segmentado aos pacientes da microárea do ACS que
  /// consentiram com `segmentedPush`. A microárea vem do token, nunca de
  /// parâmetro. Auditoria: uma linha `community_notice` com quem enviou e a
  /// microárea; o texto do aviso nunca entra na trilha.
  Future<NoticeSendResult> sendSegmented(
    Session session, {
    required String accessToken,
    required String title,
    required String message,
    required String audience,
  }) async {
    final user = authenticate(accessToken);

    try {
      final r = await AlertRuntime.instance
          .noticeServiceFor(session)
          .sendSegmented(user, title: title, message: message, audience: audience);
      return NoticeSendResult(recipients: r.recipients, accepted: r.accepted);
    } on StateError catch (error) {
      throw AlertPermissionException(message: error.message);
    }
  }
}
