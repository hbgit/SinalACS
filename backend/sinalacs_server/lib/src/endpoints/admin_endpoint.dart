import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/endpoints/authenticated_endpoint.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';

/// Backoffice, só para `coordinator` e `admin`: leitura (issue #40) e gestão de
/// contas (issue #43).
///
/// A leitura — indicadores, microáreas, alertas e auditoria — é do
/// `AdminReadService`; a listagem de ACS e de equipe, o cadastro, o vínculo de
/// microárea, a (des)ativação e as redefinições de senha/MFA do ACS são do
/// `AdminAccountService` — sempre na mesma dupla serviço/store, sem endpoint
/// novo. A redefinição da MFA do staff é a última operação da issue.
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

  /// Cadastra um ACS e devolve a senha inicial gerada, que **só** existe nesta
  /// resposta: o servidor guarda apenas o hash (ver `AcsInitialPassword`).
  /// A UBS vem da microárea, nunca do pedido.
  Future<AdminAcsCreationResult> createAcs(
    Session session, {
    required String accessToken,
    required String name,
    required String enrollmentId,
    required String microAreaId,
  }) => AlertRuntime.instance
      .adminAccountServiceFor(session)
      .createAcs(
        authenticate(accessToken),
        name: name,
        enrollmentId: enrollmentId,
        microAreaId: microAreaId,
      );

  /// Move um ACS existente para outra microárea — da própria UBS, para o
  /// coordenador; de qualquer UBS, para o administrador. A UBS do vínculo sai
  /// da microárea-alvo, nunca do pedido, e devolve a linha já no território
  /// novo. O ACS renovará a sessão (refresh token) já no território novo; o JWT
  /// em curso continua com o antigo até o refresh.
  Future<AdminAcs> setAcsMicroArea(
    Session session, {
    required String accessToken,
    required String acsId,
    required String microAreaId,
  }) => AlertRuntime.instance
      .adminAccountServiceFor(session)
      .setAcsMicroArea(
        authenticate(accessToken),
        acsId: acsId,
        microAreaId: microAreaId,
      );

  /// Liga/desliga o acesso de um ACS — da própria UBS, para o coordenador; de
  /// qualquer UBS, para o administrador.
  ///
  /// Desativar revoga, na mesma transação da flag, todas as sessões (refresh
  /// token) e todos os tokens de envio diferido da conta: o aparelho perde o
  /// acesso na hora, inclusive o envio offline das visitas pendentes, e o login
  /// por senha passa a recusar com `'Este acesso está inativo.'`. Reativar
  /// devolve o acesso pelo login — os tokens revogados não voltam.
  Future<AdminAcs> setAcsActive(
    Session session, {
    required String accessToken,
    required String acsId,
    required bool active,
  }) => AlertRuntime.instance
      .adminAccountServiceFor(session)
      .setAcsActive(authenticate(accessToken), acsId: acsId, active: active);

  /// Redefine a senha do ACS — da própria UBS, para o coordenador; de qualquer
  /// UBS, para o administrador — e devolve a nova, que **só** existe nesta
  /// resposta.
  ///
  /// A senha é sorteada pelo servidor (nunca escolhida pelo operador) e o
  /// bloqueio da conta é zerado: a credencial nova não herda as tentativas da
  /// antiga. As sessões em curso **não** são revogadas; cortá-las na hora é a
  /// desativação.
  Future<AdminPasswordResetResult> resetAcsPassword(
    Session session, {
    required String accessToken,
    required String acsId,
  }) => AlertRuntime.instance
      .adminAccountServiceFor(session)
      .resetAcsPassword(authenticate(accessToken), acsId: acsId);

  /// Redefine a MFA do ACS: apaga o segredo TOTP gravado, para ele ativar de
  /// novo na próxima entrada (é o caminho que a recusa "Peça a redefinição à
  /// coordenação" não tinha). A senha e o bloqueio não são tocados.
  Future<void> resetAcsMfa(
    Session session, {
    required String accessToken,
    required String acsId,
  }) => AlertRuntime.instance
      .adminAccountServiceFor(session)
      .resetAcsMfa(authenticate(accessToken), acsId: acsId);
}
