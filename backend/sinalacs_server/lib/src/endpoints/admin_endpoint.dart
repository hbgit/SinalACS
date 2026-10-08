import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/endpoints/authenticated_endpoint.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';

/// Leitura do backoffice (issue #40): indicadores, microáreas, alertas e
/// auditoria. Somente leitura, só para `coordinator` e `admin`.
///
/// O papel, o escopo (sistema para o administrador, UBS para o coordenador), a
/// paginação e a auditoria de cada leitura são do `AdminReadService`; o endpoint
/// só verifica o token e delega. Nenhum método devolve nome, CPF ou contato de
/// paciente: o paciente é um rótulo (`#A18F`).
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
}
