import 'dart:math';

import 'package:sinalacs_server/src/application/admin/admin_scope.dart';
import 'package:sinalacs_server/src/application/admin/initial_password.dart';
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

  /// A microárea [microAreaId] com a UBS dona dela, ou `null` se não existir.
  ///
  /// A UBS vem junto porque o escopo do coordenador é decidido comparando-a
  /// com `staff_accounts.ubsId`: devolvesse só a microárea e o serviço faria
  /// uma segunda consulta pela UBS — e uma decisão de território feita sobre
  /// duas leituras é uma decisão sobre dois alvos diferentes.
  Future<({String? ubsId, String? name})?> microAreaFor(String microAreaId);

  /// `true` se já existe um ACS com a matrícula [enrollmentId].
  ///
  /// É a pré-checagem do cadastro, para a resposta limpa do caso comum. Quem
  /// fecha a corrida é o índice único de `acs."enrollmentId"`, tratado em
  /// [insertAcs] — entre esta consulta e o INSERT cabe outro cadastro.
  Future<bool> enrollmentIdTaken(String enrollmentId);

  /// Cria `users` (papel `acs`), `acs` e `user_credentials` numa **única
  /// transação**, com [digest] já derivado do lado de fora (o serviço é quem
  /// sorteia a senha e nunca a guarda).
  ///
  /// Devolve o ACS criado — já no formato da listagem — ou `null` quando o
  /// índice único da matrícula dispara, ou seja, quando outro cadastro passou
  /// entre a pré-checagem e este INSERT. Nada fica gravado nesse caso: as três
  /// linhas são da mesma transação.
  Future<AdminAcs?> insertAcs({
    required String name,
    required String enrollmentId,
    required String microAreaId,
    required String ubsId,
    required PasswordDigest digest,
    required DateTime at,
  });

  /// Move o ACS [acsId] para a microárea [microAreaId], gravando
  /// `users."microAreaId"` e `acs."ubsId"` (o de [ubsId], derivado da
  /// microárea-alvo pelo serviço) numa **única transação**.
  ///
  /// O predicado de [scope] vai **dentro** do `WHERE` do `UPDATE`: um ACS que
  /// saia do escopo entre a pré-checagem do serviço e esta escrita não é movido
  /// — a checagem e a escrita não podem ser duas decisões sobre estados
  /// diferentes (TOCTOU). `null` significa exatamente isso: nada foi movido,
  /// seja porque o ACS não existe, seja porque não é do escopo.
  Future<AdminAcs?> setAcsMicroArea({
    required String acsId,
    required String microAreaId,
    required String ubsId,
    required AdminScope scope,
    required DateTime at,
  });

  /// Liga/desliga o acesso do ACS [acsId] numa **única transação**, com o
  /// predicado de [scope] dentro do `WHERE` (mesma defesa de [setAcsMicroArea]).
  ///
  /// Desativar revoga, **na mesma transação**, todas as famílias de refresh
  /// token e todos os tokens de envio diferido da conta, com [at] como carimbo
  /// da revogação: a flag e as revogações são um só estado, e não existe
  /// instante observável em que o ACS esteja inativo e ainda com sessão viva
  /// (o `findAccount` do refresh só recusaria na próxima renovação). Reativar
  /// não toca em token nenhum — revogado é revogado, e o acesso novo se obtém
  /// com um login novo.
  ///
  /// Devolve `true` quando o ACS existe no escopo e a flag foi gravada — o
  /// valor anterior não importa (desativar um já inativo também grava). `false`
  /// significa que nada foi escrito: o ACS não existe, está fora do escopo ou
  /// o id não é UUID.
  Future<bool> setAcsActive({
    required String acsId,
    required AdminScope scope,
    required bool active,
    required DateTime at,
  });
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

  /// Refresh tokens do ACS.
  ///
  /// A desativação revoga todas as famílias **dentro da transação do
  /// [store]** (ver [setAcsActive]): um serviço que revogasse por aqui faria
  /// da flag e da revogação duas gravações independentes, e uma sessão viva
  /// sobreviveria à desativação até a próxima renovação. A porta continua no
  /// construtor para as operações do serviço que não precisam de atomicidade
  /// com [store].
  final RefreshTokenStore refreshStore;

  /// Tokens de envio diferido do ACS, pela mesma regra de [refreshStore].
  final UploadTokenStore uploadStore;

  final PasswordHasher hasher;
  final AuditTrail audit;

  /// Sorteio das credenciais entregues fora de banda (senha inicial, código de
  /// ativação).
  final Random _random;

  /// Relógio dos carimbos de tempo.
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

  /// Cadastra um ACS na UBS da microárea escolhida e devolve a senha inicial
  /// gerada — que existe **só** nesta resposta (ver `AcsInitialPassword`).
  ///
  /// A UBS **nunca** vem do pedido: sai da microárea, que é o único dado que o
  /// escopo do coordenador pode comparar. Microárea inexistente e microárea de
  /// outra UBS recebem a **mesma** mensagem; separá-las diria ao coordenador,
  /// por tentativa, quais microáreas existem fora da UBS dele.
  ///
  /// A ordem é deliberada: papel/escopo (recusa auditada), entrada, alvo e
  /// matrícula — e só então o sorteio da senha, porque derivar o Argon2id é
  /// caro e não deve acontecer para um pedido que já vai ser recusado. A
  /// corrida que passa pela pré-checagem da matrícula é fechada pelo índice
  /// único do banco e chega aqui como `insertAcs` devolvendo `null`: mesmo
  /// desfecho, mesma mensagem, nunca um erro de servidor.
  Future<AdminAcsCreationResult> createAcs(
    AuthenticatedUser user, {
    required String name,
    required String enrollmentId,
    required String microAreaId,
  }) async {
    const recurso = 'admin_acs';
    final escopo = await _resolver.resolve(
      user,
      recurso: recurso,
      actionType: 'write',
    );

    final nome = name.trim();
    final matricula = enrollmentId.trim();
    final ma = await store.microAreaFor(microAreaId);
    final ubsDaMicroarea = ma?.ubsId;

    if (nome.isEmpty ||
        nome.length > 120 ||
        matricula.isEmpty ||
        matricula.length > 32) {
      await _negar(user, recurso, message: 'Informe nome e matrícula do ACS.');
    }
    if (ubsDaMicroarea == null ||
        (escopo.ubsId != null && ubsDaMicroarea != escopo.ubsId)) {
      await _negar(user, recurso, message: 'Microárea não encontrada.');
    }
    if (await store.enrollmentIdTaken(matricula)) {
      await _negar(
        user,
        recurso,
        message: 'Já existe um ACS com esta matrícula.',
      );
    }

    final senha = AcsInitialPassword.generate(_random);
    final digest = await hasher.derive(senha);
    final acs = await store.insertAcs(
      name: nome,
      enrollmentId: matricula,
      microAreaId: microAreaId,
      ubsId: ubsDaMicroarea,
      digest: digest,
      at: _clock().toUtc(),
    );
    if (acs == null) {
      await _negar(
        user,
        recurso,
        message: 'Já existe um ACS com esta matrícula.',
      );
    }
    await _auditar(user, recurso, result: 'created', resourceId: acs.id);
    return AdminAcsCreationResult(acs: acs, initialPassword: senha);
  }

  /// Move um ACS para outra microárea e devolve a linha já com o território
  /// novo.
  ///
  /// As validações são as da criação, pela mesma razão: microárea inexistente e
  /// microárea de outra UBS recebem a **mesma** mensagem (senão o coordenador
  /// descobre, por tentativa, quais microáreas existem fora da UBS dele), e o
  /// ACS inexistente e o ACS de outra UBS recebem a **mesma** recusa — um ACS
  /// fora do escopo não existe para quem perguntou.
  ///
  /// A ordem é: papel/escopo (recusa auditada) → microárea-alvo → ACS-alvo →
  /// escrita. A UBS do vínculo sai da microárea-alvo, nunca do chamador: para o
  /// administrador o escopo é nulo, e um `acs."ubsId"` nulo seria um ACS sem
  /// UBS nenhuma.
  ///
  /// As duas pré-checagens são para a resposta limpa do caso comum; quem fecha
  /// a corrida é o `WHERE` do store, que repete o escopo dentro da própria
  /// escrita e devolve `null` se o ACS saiu do escopo nesse meio-tempo — mesmo
  /// desfecho, mesma mensagem, nada movido. A releitura com [AdminAccountStore.acsById]
  /// depois do commit é o que garante que a linha devolvida é a do banco, e não
  /// a que o `UPDATE` achou que gravou.
  Future<AdminAcs> setAcsMicroArea(
    AuthenticatedUser user, {
    required String acsId,
    required String microAreaId,
  }) async {
    const recurso = 'admin_acs';
    final escopo = await _resolver.resolve(
      user,
      recurso: recurso,
      actionType: 'write',
    );

    final ma = await store.microAreaFor(microAreaId);
    final ubsDaMicroarea = ma?.ubsId;
    if (ubsDaMicroarea == null ||
        (escopo.ubsId != null && ubsDaMicroarea != escopo.ubsId)) {
      await _negar(user, recurso, message: 'Microárea não encontrada.');
    }
    if (await store.acsById(escopo, acsId) == null) {
      await _negar(user, recurso, message: 'ACS não encontrado.');
    }

    final movido = await store.setAcsMicroArea(
      acsId: acsId,
      microAreaId: microAreaId,
      ubsId: ubsDaMicroarea,
      scope: escopo,
      at: _clock().toUtc(),
    );
    if (movido == null) {
      await _negar(user, recurso, message: 'ACS não encontrado.');
    }
    // A leitura é preferida à devolvida pelo `UPDATE`; o `??` só cobre o caso
    // extremo de o ACS ter saído do escopo entre o commit e esta releitura —
    // aí a linha do `UPDATE` ainda descreve o vínculo que de fato aconteceu.
    final acs = await store.acsById(escopo, acsId) ?? movido;
    await _auditar(
      user,
      recurso,
      result: 'micro_area_changed',
      resourceId: acs.id,
    );
    return acs;
  }

  /// Ativa ou desativa o ACS, com a revogação das sessões na desativação.
  ///
  /// A flag e as revogações são da **mesma** transação, do lado do store: o
  /// ACS desativado perde a sessão na hora, e não na próxima renovação — o
  /// `findAccount` do refresh só recusaria lá, e a desativação precisa valer
  /// agora. A reativação **não** ressuscita token nenhum: o acesso novo se
  /// obtém com um login novo (senha + TOTP).
  ///
  /// Desativar um ACS já inativo (e reativar um já ativo) é idempotente: a
  /// operação conclui e audita uma linha nova — o que a trilha registra é o
  /// pedido do operador, e um pedido repetido é um fato novo.
  ///
  /// As recusas são as do vínculo, pela mesma razão: ACS inexistente e ACS de
  /// outra UBS recebem a **mesma** mensagem — um ACS fora do escopo não existe
  /// para quem perguntou.
  Future<AdminAcs> setAcsActive(
    AuthenticatedUser user, {
    required String acsId,
    required bool active,
  }) async {
    const recurso = 'admin_acs';
    final escopo = await _resolver.resolve(
      user,
      recurso: recurso,
      actionType: 'write',
    );

    final antes = await store.acsById(escopo, acsId);
    if (antes == null) {
      await _negar(user, recurso, message: 'ACS não encontrado.');
    }

    final mudou = await store.setAcsActive(
      acsId: acsId,
      scope: escopo,
      active: active,
      at: _clock().toUtc(),
    );
    if (!mudou) {
      await _negar(user, recurso, message: 'ACS não encontrado.');
    }

    // A releitura é a do banco; o `??` só cobre o caso extremo de o ACS ter
    // saído do escopo entre o commit e esta leitura — aí a linha da
    // pré-checagem, com a flag que a transação gravou, ainda descreve o estado.
    final acs = await store.acsById(escopo, acsId) ?? antes.copyWith(active: active);
    await _auditar(
      user,
      recurso,
      result: active ? 'activated' : 'deactivated',
      resourceId: acs.id,
    );
    return acs;
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
  // #43.

  /// Recusa com linha `denied` na trilha ANTES de lançar (fail-closed), a mesma
  /// mensagem para "não existe" e "não é seu". [message] só é sobre a própria
  /// entrada do operador (validação) — nunca revela existência de outro território.
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
