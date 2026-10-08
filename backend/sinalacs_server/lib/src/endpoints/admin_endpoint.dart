import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/endpoints/authenticated_endpoint.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';

/// Backoffice: leitura (issue #40) de indicadores, microáreas, alertas e
/// auditoria, e o atendimento de pedidos do titular (issue #42). Só para
/// `coordinator` e `admin`.
///
/// O papel, o escopo (sistema para o administrador, UBS para o coordenador), a
/// paginação e a auditoria de cada leitura são do `AdminReadService` (e, nos
/// pedidos do titular, do `DataSubjectCaseService`); o endpoint só verifica o
/// token e delega. Nenhum método devolve nome, CPF ou contato de paciente: o
/// paciente é um rótulo (`#A18F`).
class AdminEndpoint extends AuthenticatedEndpoint {
  Future<AdminIndicators> indicators(
    Session session, {
    required String accessToken,
  }) => AlertRuntime.instance
      .adminReadServiceFor(session)
      .indicators(authenticate(accessToken));

  Future<List<AdminMicroArea>> microAreas(
    Session session, {
    required String accessToken,
  }) => AlertRuntime.instance
      .adminReadServiceFor(session)
      .microAreas(authenticate(accessToken));

  Future<AdminAlertPage> alerts(
    Session session, {
    required String accessToken,
    String? microAreaId,
    AlertStatus? status,
    int limit = 50,
    int offset = 0,
  }) => AlertRuntime.instance
      .adminReadServiceFor(session)
      .alerts(
        authenticate(accessToken),
        microAreaId: microAreaId,
        status: status,
        limit: limit,
        offset: offset,
      );

  Future<AdminAuditPage> auditLogs(
    Session session, {
    required String accessToken,
    int limit = 50,
    int? beforeSequence,
  }) => AlertRuntime.instance
      .adminReadServiceFor(session)
      .auditLogs(
        authenticate(accessToken),
        limit: limit,
        beforeSequence: beforeSequence,
      );

  /// Pedidos do titular no escopo de quem chama, prazo mais próximo primeiro.
  /// Nunca traz o texto do pedido nem a nota.
  Future<AdminDataSubjectRequestPage> dataSubjectRequests(
    Session session, {
    required String accessToken,
    DataSubjectRequestStatus? status,
    int limit = 50,
    int offset = 0,
  }) => AlertRuntime.instance
      .dataSubjectCaseServiceFor(session)
      .list(
        authenticate(accessToken),
        status: status,
        limit: limit,
        offset: offset,
      );

  /// Detalhe de um pedido, com o texto decifrado. A leitura é auditada antes.
  /// Inexistente e fora do escopo dão a mesma recusa.
  Future<AdminDataSubjectRequestDetail> dataSubjectRequest(
    Session session, {
    required String accessToken,
    required String id,
  }) => AlertRuntime.instance
      .dataSubjectCaseServiceFor(session)
      .get(authenticate(accessToken), id);

  /// `open → inReview`.
  Future<void> startDataSubjectReview(
    Session session, {
    required String accessToken,
    required String id,
  }) => AlertRuntime.instance
      .dataSubjectCaseServiceFor(session)
      .startReview(authenticate(accessToken), id);

  /// Atende o pedido. Correção exige [note]; exclusão anonimiza o titular na
  /// mesma transação da mudança de status e da auditoria.
  Future<void> completeDataSubjectRequest(
    Session session, {
    required String accessToken,
    required String id,
    String? note,
  }) => AlertRuntime.instance
      .dataSubjectCaseServiceFor(session)
      .complete(authenticate(accessToken), id, note: note);

  /// Recusa o pedido com um motivo de 3 a 500 caracteres, que o titular vê.
  Future<void> rejectDataSubjectRequest(
    Session session, {
    required String accessToken,
    required String id,
    required String reason,
  }) => AlertRuntime.instance
      .dataSubjectCaseServiceFor(session)
      .reject(authenticate(accessToken), id, reason: reason);
}
