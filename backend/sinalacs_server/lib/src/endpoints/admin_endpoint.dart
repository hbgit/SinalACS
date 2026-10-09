import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/endpoints/authenticated_endpoint.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';

/// Backoffice, só para `coordinator` e `admin`: leitura (issue #40) e gestão de
/// contas (issue #43).
///
/// A leitura — indicadores, microáreas, alertas e auditoria — é do
/// `AdminReadService`; a listagem de ACS e de equipe é do `AdminAccountService`,
/// que nas operações seguintes da mesma issue ganha o cadastro, o vínculo de
/// microárea, a desativação e as redefinições de senha/MFA. Hoje todos os
/// métodos daqui são de leitura: os de escrita entram na mesma dupla
/// serviço/store, sem endpoint novo.
///
/// O papel, o escopo (sistema para o administrador, UBS para o coordenador),
/// a paginação e a auditoria de cada operação são dos serviços; o endpoint só
/// verifica o token e delega. Nenhum método devolve nome, CPF ou contato de
/// paciente: o paciente é um rótulo (`#A18F`), e o que sai dos cadastros é a
/// identificação **profissional** (nome, matrícula, UBS, microárea).
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

  /// ACS visíveis para o chamador: o administrador vê o sistema, o coordenador
  /// só os da própria UBS.
  Future<List<AdminAcs>> acs(
    Session session, {
    required String accessToken,
  }) => AlertRuntime.instance
      .adminAccountServiceFor(session)
      .acsList(authenticate(accessToken));

  /// Contas de equipe do backoffice — só o administrador.
  Future<List<AdminStaff>> staff(
    Session session, {
    required String accessToken,
  }) => AlertRuntime.instance
      .adminAccountServiceFor(session)
      .staffList(authenticate(accessToken));
}
