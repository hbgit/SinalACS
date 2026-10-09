import 'dart:math';

import 'package:sinalacs_server/src/application/admin/admin_scope.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/institutional_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/password_hasher.dart';
import 'package:sinalacs_server/src/application/auth/refresh_token_service.dart';
import 'package:sinalacs_server/src/application/auth/upload_token_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

// A `AdminScope`/`AdminScopeStore` vêm com o serviço: quem implementa o store
// (ou o falsifica no teste) não precisa de um segundo import para falar a
// língua do escopo — mesmo arranjo de `admin_read_service.dart`.
export 'package:sinalacs_server/src/application/admin/admin_scope.dart';

/// Contas do backoffice sobre o banco (issue #43). Interface à parte do ORM, no
/// espírito de `AdminReadStore`: o serviço e seus testes não conhecem SQL.
///
/// Estende a porta estreita do [AdminScopeResolver] (`ubsOf`) porque é ela que
/// resolve o papel e o escopo de toda operação — a leitura da UBS do
/// coordenador é a mesma consulta para os dois serviços do backoffice.
abstract interface class AdminAccountStore implements AdminScopeStore {
  /// ACS do escopo: o administrador vê os do sistema inteiro, o coordenador só
  /// os da própria UBS. Inclui quem ainda não tem microárea.
  Future<List<AdminAcs>> acsList(AdminScope scope);

  /// Contas de equipe — lista do sistema inteiro, só para o administrador.
  Future<List<AdminStaff>> staffList();

  /// ACS do escopo, ou `null` para "não existe" **e** para "não é do escopo":
  /// a mesma resposta, para não revelar território alheio.
  Future<AdminAcs?> acsById(AdminScope scope, String acsId);

  /// Conta de equipe, ou `null` se não existir.
  Future<AdminStaff?> staffById(String staffId);
}

/// Gestão de contas do backoffice (issue #43): listagem de ACS e da equipe
/// (esta tarefa) e, nas operações seguintes da mesma issue, cadastro, vínculo
/// de microárea, desativação e redefinição de senha/MFA.
///
/// Papel e escopo vêm do [AdminScopeResolver] — a regra única do backoffice
/// (PRD §4.2.2): só `coordinator` e `admin`; o coordenador enxerga e opera
/// **apenas** a própria UBS (`staff_accounts.ubsId`), fail-closed sem UBS; o
/// administrador, o sistema inteiro. Toda recusa é a mesma (`acesso restrito ao
/// backoffice` / `não encontrado`), sem distinguir "não existe" de "não é seu".
///
/// **Auditoria fail-closed**, sempre com `AuditTrail.record` — nunca
/// `recordSafely`: se a linha não grava, a operação não pode seguir em silêncio.
///
/// - **Recusa:** a linha `denied` entra na trilha **antes** de a exceção subir.
///   É o que [AdminScopeResolver] faz para papel e escopo, e o que [_negar] faz
///   para um alvo fora do escopo ou uma entrada inválida.
/// - **Leitura:** audita `read`/`success` **antes** de consultar o store — o
///   dado nunca sai sem a linha.
/// - **Escrita:** recusa audita antes de lançar; sucesso audita **depois** do
///   commit, com o id do alvo em `resourceId`.
class AdminAccountService {
  AdminAccountService({
    required this.store,
    required this.credentials,
    required this.totpStore,
    required this.activationStore,
    required this.refreshStore,
    required this.uploadStore,
    required this.hasher,
    required this.audit,
    Random? random,
    DateTime Function()? clock,
  }) : _random = random ?? Random.secure(),
       _clock = clock ?? DateTime.now;

  final AdminAccountStore store;

  /// Credencial de login do ACS (RF07): senha inicial e redefinição.
  final AcsCredentialStore credentials;

  /// Estado da MFA (`user_credentials.totp*`), do ACS e do staff.
  final TotpStore totpStore;

  /// Código de ativação de uso único da MFA do staff (#48).
  final StaffActivationStore activationStore;

  /// Refresh tokens do ACS: a desativação revoga a família inteira.
  final RefreshTokenStore refreshStore;

  /// Tokens de envio diferido do ACS: a desativação também os derruba.
  final UploadTokenStore uploadStore;

  final PasswordHasher hasher;
  final AuditTrail audit;

  /// Sorteio das credenciais entregues fora de banda (senha inicial, código de
  /// ativação). As operações de escrita da #43 é que o usam.
  // ignore: unused_field
  final Random _random;

  /// Relógio dos carimbos de tempo. As operações de escrita da #43 é que o usam.
  // ignore: unused_field
  final DateTime Function() _clock;

  /// A regra única de papel/escopo, sobre o [store] (que também é a porta da
  /// UBS do coordenador).
  late final AdminScopeResolver _resolver = AdminScopeResolver(
    store: store,
    audit: audit,
  );

  Future<List<AdminAcs>> acsList(AuthenticatedUser user) async {
    const recurso = 'admin_acs';
    final escopo = await _resolver.resolve(user, recurso: recurso);
    await _auditarLeitura(user, recurso);
    return store.acsList(escopo);
  }

  Future<List<AdminStaff>> staffList(AuthenticatedUser user) async {
    const recurso = 'admin_staff';
    await _resolver.requireAdmin(user, recurso: recurso);
    await _auditarLeitura(user, recurso);
    return store.staffList();
  }

  /// Leitura bem-sucedida: a linha entra na trilha **antes** de o store ser
  /// consultado, mesmo arranjo de `AdminReadService`.
  Future<void> _auditarLeitura(AuthenticatedUser user, String recurso) =>
      audit.record(
        AuditEvent(
          userId: user.id,
          actionType: 'read',
          resourceType: recurso,
          result: 'success',
        ),
      );

  // Os dois helpers abaixo são a interface interna das operações de escrita da
  // #43 (tarefas seguintes): ficam declarados desde já para as escritas
  // entrarem sem mudar a forma do arquivo. Nesta tarefa, ainda não há chamador.

  /// Recusa com linha `denied` na trilha ANTES de lançar (fail-closed), a mesma
  /// mensagem para "não existe" e "não é seu". [message] só é sobre a própria
  /// entrada do operador (validação) — nunca revela existência de outro território.
  // ignore: unused_element
  Future<Never> _negar(
    AuthenticatedUser user,
    String recurso, {
    String message = 'Não foi possível concluir a operação com os dados informados.',
  }) async {
    await audit.record(
      AuditEvent(
        userId: user.id,
        actionType: 'write',
        resourceType: recurso,
        result: 'denied',
      ),
    );
    throw AdminInvalidRequestException(message: message);
  }

  /// Sucesso: audita DEPOIS do commit, com `record` (não `recordSafely`).
  // ignore: unused_element
  Future<void> _auditar(
    AuthenticatedUser user,
    String recurso, {
    required String result,
    required String resourceId,
  }) => audit.record(
    AuditEvent(
      userId: user.id,
      actionType: 'write',
      resourceType: recurso,
      resourceId: resourceId,
      result: result,
    ),
  );
}
