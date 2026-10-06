import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/visits/visit_sync_service.dart';
import 'package:sinalacs_server/src/endpoints/authenticated_endpoint.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';

/// Sincronização das visitas domiciliares registradas offline.
///
/// É a contraparte da fila offline do app do ACS: o dispositivo grava a visita
/// localmente durante a visita (onde normalmente não há rede) e envia o lote
/// quando a conexão volta.
///
/// O lote inteiro roda em uma transação: ou todas as visitas são aplicadas, ou
/// nenhuma. Um resultado parcial deixaria o dispositivo sem saber o que
/// reenviar.
class VisitsEndpoint extends AuthenticatedEndpoint {
  Future<List<VisitSyncResult>> sync(
    Session session, {
    required String accessToken,
    required List<VisitSyncEntry> visits,
  }) async {
    final user = authenticate(accessToken);

    if (visits.isEmpty) return <VisitSyncResult>[];

    try {
      return await session.db.transaction((transaction) async {
        final service =
            AlertRuntime.instance.visitSyncServiceFor(session, transaction: transaction);
        return service.sync(user: user, entries: visits);
      });
    } on ArgumentError catch (error) {
      throw AlertValidationException(message: '${error.message}');
    } on StateError catch (error) {
      throw AlertPermissionException(message: error.message);
    }
  }

  /// Envio das visitas LEGADAS do aparelho (autoria desconhecida, D4 do plano
  /// 2026-10-03): gravadas antes de existir dono por visita no banco local.
  ///
  /// A sessão do ACS é só o transporte — ver `VisitSyncService.syncLegacy`.
  /// Mesma transação por lote e mesma tradução de erros de [sync].
  Future<List<VisitSyncResult>> syncLegacy(
    Session session, {
    required String accessToken,
    required String deviceId,
    required List<VisitSyncEntry> visits,
  }) async {
    final user = authenticate(accessToken);

    if (visits.isEmpty) return <VisitSyncResult>[];

    try {
      // Teto do lote ANTES de abrir a transação: nada toca o banco.
      VisitSyncService.checkLegacyBatchSize(visits.length);
      return await session.db.transaction((transaction) async {
        final service =
            AlertRuntime.instance.visitSyncServiceFor(session, transaction: transaction);
        return service.syncLegacy(
          transporter: user,
          deviceId: deviceId,
          entries: visits,
        );
      });
    } on ArgumentError catch (error) {
      throw AlertValidationException(message: '${error.message}');
    } on StateError catch (error) {
      throw AlertPermissionException(message: error.message);
    }
  }

  /// Envio DIFERIDO (D7 do plano 2026-10-03): sobe as visitas pendentes de um
  /// ACS que pode já ter saído, autenticado pelo token de envio que o
  /// `auth.loginInstitutional` emitiu para ele neste aparelho — não pelo JWT.
  ///
  /// Público por desenho para o `authenticate(...)`: o token opaco É a
  /// credencial, e o único poder dele é este envio. O usuário resolvido é o
  /// DONO do token, com a microárea relida do banco agora, e o lote passa
  /// pelo MESMO `VisitSyncService.sync` do envio comum: autoria do dono,
  /// território atual do dono, `localId` de outro agente recusado. Toda recusa
  /// do token é a mesma `SessionExpiredException`, sem motivo e sem o token.
  ///
  /// No máximo `VisitSyncService.maxLegacyBatch` visitas por chamada, checado
  /// antes de qualquer acesso ao banco. Um evento `visit_deferred_sync` por
  /// lote gravado vai para `audit_logs`, com o dono e nada clínico.
  Future<List<VisitSyncResult>> syncDeferred(
    Session session, {
    required String uploadToken,
    required String deviceId,
    required List<VisitSyncEntry> visits,
  }) async {
    final runtime = AlertRuntime.instance;
    try {
      // Teto do lote ANTES de resolver o token e de abrir a transação.
      VisitSyncService.checkLegacyBatchSize(visits.length);
    } on ArgumentError catch (error) {
      throw AlertValidationException(message: '${error.message}');
    }

    // Fora da transação do lote: uma recusa que revoga o token precisa
    // persistir mesmo quando a chamada termina em exceção.
    final owner = await runtime
        .uploadTokenServiceFor(session)
        .resolve(uploadToken: uploadToken, deviceId: deviceId);

    if (visits.isEmpty) return <VisitSyncResult>[];

    final List<VisitSyncResult> results;
    try {
      results = await session.db.transaction((transaction) async {
        final service =
            runtime.visitSyncServiceFor(session, transaction: transaction);
        return service.sync(user: owner, entries: visits);
      });
    } on ArgumentError catch (error) {
      throw AlertValidationException(message: '${error.message}');
    } on StateError catch (error) {
      throw AlertPermissionException(message: error.message);
    }

    // Depois do commit: só lote que de fato persistiu vira linha na trilha.
    await runtime.auditTrailFor(session).recordSafely(AuditEvent(
          userId: owner.id,
          actionType: 'write',
          resourceType: 'visit_deferred',
          result: 'visit_deferred_sync',
        ));
    return results;
  }

  /// Revoga o token de envio diferido (o app chama quando a fila do dono
  /// zera). Público pelo mesmo motivo de [syncDeferred]; idempotente, e um
  /// token desconhecido é ignorado em silêncio.
  Future<void> revokeUploadToken(
    Session session, {
    required String uploadToken,
  }) =>
      AlertRuntime.instance.uploadTokenServiceFor(session).revoke(uploadToken);

  /// Sincronização central→dispositivo: visitas da microárea do ACS
  /// autenticado alteradas após `since`, para reconciliar um device que
  /// ficou offline ou foi reinstalado.
  Future<List<VisitSyncEntry>> pull(
    Session session, {
    required String accessToken,
    required DateTime since,
  }) async {
    final user = authenticate(accessToken);
    try {
      return await AlertRuntime.instance
          .visitSyncServiceFor(session)
          .pull(user: user, since: since);
    } on StateError catch (error) {
      throw AlertPermissionException(message: error.message);
    }
  }
}
