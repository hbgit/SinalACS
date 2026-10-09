import 'package:meta/meta.dart';
import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/admin/admin_account_service.dart';
import 'package:sinalacs_server/src/application/auth/password_hasher.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_refresh_token_store.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_upload_token_store.dart';

/// Mesmo `Uuid` de `RedAlertService`: o sorteio da chave é o mesmo em todo o
/// servidor.
const _uuid = Uuid();

/// Contas do backoffice sobre Postgres (issue #43).
///
/// SQL direto (`unsafeQuery` com parâmetros nomeados), como `OrmAdminReadStore`:
/// o ORM do Serverpod não expressa a junção `users`/`acs`/`ubs`/`micro_areas`/
/// `user_credentials` que as listagens precisam. Nada aqui concatena **valor**
/// no texto da consulta; só a presença do filtro de escopo e do filtro por id
/// muda a forma.
///
/// O escopo do coordenador é `acs."ubsId"` — o mesmo campo que o login usa —, e
/// a listagem inclui quem não tem microárea (`LEFT JOIN`): um ACS recém-cadastrado,
/// ainda sem território, precisa aparecer para poder ser vinculado.
///
/// `mfaActive` vem da própria consulta (`totpEnabledAt IS NOT NULL`), nunca de
/// coluna calculada: MFA iniciada e não confirmada não é MFA ativa.
class OrmAdminAccountStore implements AdminAccountStore {
  OrmAdminAccountStore({
    required Session Function() session,
    @visibleForTesting bool debugFailAfterUsersInsert = false,
    @visibleForTesting bool debugFailAfterRevocations = false,
  }) : _session = session,
       _debugFailAfterUsersInsert = debugFailAfterUsersInsert,
       _debugFailAfterRevocations = debugFailAfterRevocations;

  final Session Function() _session;

  /// Derruba a transação do cadastro **depois** de `users` e antes de `acs`,
  /// para o teste provar que a atomicidade não é teórica: se as três linhas não
  /// fossem da mesma transação, sobraria um usuário sem credencial e sem
  /// matrícula — um órfão que ninguém consegue nem logar nem apagar pela
  /// interface. Mesmo arranjo de
  /// `OrmDataSubjectRightsStore._debugFailAfterTokenDelete`.
  final bool _debugFailAfterUsersInsert;

  /// Derruba a transação da desativação **depois** das duas revogações: sem a
  /// transação única, a flag ficaria gravada e os tokens vigentes — o teste
  /// prova que o rollback leva os três `UPDATE` juntos. Mesmo arranjo de
  /// [_debugFailAfterUsersInsert].
  final bool _debugFailAfterRevocations;

  /// `@ubs` nulo = sistema inteiro (administrador).
  static const _escopoAcs = '(@ubs::uuid IS NULL OR acs."ubsId" = @ubs::uuid)';

  /// Colunas e junções das duas listagens; o `WHERE`/`ORDER BY` de cada método
  /// é o que varia.
  static const _selecaoAcs = '''
      SELECT u.id, u.name, acs."enrollmentId", acs."ubsId", ub.name,
             m.id, m.name, acs.active, (uc."totpEnabledAt" IS NOT NULL)
      FROM acs
      JOIN users u ON u.id = acs.id
      JOIN ubs ub ON ub.id = acs."ubsId"
      LEFT JOIN micro_areas m ON m.id = u."microAreaId"
      LEFT JOIN user_credentials uc ON uc."userId" = acs.id''';

  static const _selecaoStaff = '''
      SELECT u.id, u.name, s."enrollmentId", u.role, ub.name, s.active,
             (uc."totpEnabledAt" IS NOT NULL)
      FROM staff_accounts s
      JOIN users u ON u.id = s.id
      LEFT JOIN ubs ub ON ub.id = s."ubsId"
      LEFT JOIN user_credentials uc ON uc."userId" = s.id''';

  @override
  Future<List<AdminAcs>> acsList(AdminScope scope) async {
    final rows = await _session().db.unsafeQuery(
      '$_selecaoAcs WHERE $_escopoAcs ORDER BY u.name, u.id',
      parameters: QueryParameters.named({'ubs': scope.ubsId}),
    );
    return [for (final r in rows) _acs(r)];
  }

  @override
  Future<AdminAcs?> acsById(AdminScope scope, String acsId) async {
    // Um id que não é UUID nem chega ao banco: o Postgres lançaria erro de
    // sintaxe no `::uuid`, e um erro de servidor diria ao chamador que o id é
    // inválido — em vez da mesma resposta de "não existe ou não é seu".
    if (!_uuidValido(acsId)) return null;
    final rows = await _session().db.unsafeQuery(
      '$_selecaoAcs WHERE u.id = @id::uuid AND $_escopoAcs',
      parameters: QueryParameters.named({'id': acsId, 'ubs': scope.ubsId}),
    );
    return rows.isEmpty ? null : _acs(rows.single);
  }

  @override
  Future<List<AdminStaff>> staffList() async {
    final rows = await _session().db.unsafeQuery(
      '$_selecaoStaff ORDER BY u.name, u.id',
    );
    return [for (final r in rows) _staff(r)];
  }

  @override
  Future<AdminStaff?> staffById(String staffId) async {
    if (!_uuidValido(staffId)) return null;
    final rows = await _session().db.unsafeQuery(
      '$_selecaoStaff WHERE s.id = @id::uuid',
      parameters: QueryParameters.named({'id': staffId}),
    );
    return rows.isEmpty ? null : _staff(rows.single);
  }

  /// A microárea e a UBS dona dela. Um id que não é UUID devolve `null` pela
  /// mesma guarda de [acsById]: a alternativa é o erro de sintaxe do Postgres
  /// no `::uuid`, que diria ao chamador que o id é inválido em vez de
  /// "microárea não encontrada".
  @override
  Future<({String? ubsId, String? name})?> microAreaFor(
    String microAreaId,
  ) async {
    if (!_uuidValido(microAreaId)) return null;
    final rows = await _session().db.unsafeQuery(
      'SELECT m.name, m."ubsId" FROM micro_areas m WHERE m.id = @id::uuid',
      parameters: QueryParameters.named({'id': microAreaId}),
    );
    if (rows.isEmpty) return null;
    return (name: rows.single[0] as String, ubsId: rows.single[1].toString());
  }

  /// Índice único `acs_enrollment_id_key`. Só a existência interessa: a linha
  /// não é lida aqui, e um `SELECT 1` não devolve PII nenhuma.
  @override
  Future<bool> enrollmentIdTaken(String enrollmentId) async {
    final rows = await _session().db.unsafeQuery(
      'SELECT 1 FROM acs WHERE "enrollmentId" = @matricula LIMIT 1',
      parameters: QueryParameters.named({'matricula': enrollmentId}),
    );
    return rows.isNotEmpty;
  }

  /// As três linhas do cadastro numa transação — ou todas, ou nenhuma.
  ///
  /// O id é sorteado aqui e serve às três tabelas: `acs.id` e
  /// `user_credentials.userId` são o mesmo UUID de `users.id`, a chave
  /// compartilhada que o login do RF07 já atravessa. Sorteado em Dart (e não
  /// pelo `DEFAULT gen_random_uuid()` da coluna) porque ele entra também no
  /// placeholder do CPF, que é gravado na **mesma** linha — e o índice único
  /// de `users.cpfHash` não pode disparar por dois ACS cadastrados no mesmo
  /// instante. Mesmo `Uuid` de `RedAlertService`.
  ///
  /// `cpfHash` recebe um placeholder aleatório único, **nunca** o HMAC de um
  /// CPF: `verifyOtp` emite papel de PACIENTE a partir da linha que encontra
  /// por `users.cpfHash`, então um CPF na linha do ACS deixaria o login
  /// passwordless abrir sessão de paciente com o id e a microárea dele (o
  /// mesmo motivo que deixou o ACS semeado fora de `seed_cpf_hashes.dart` —
  /// `spec/lgpd_data_audit.md`, nota de seed). O placeholder não é um HMAC
  /// (não é hex de 64 caracteres), então nenhum CPF chega até ele.
  ///
  /// `birthDate` recebe a sentinela 1900-01-01 UTC — a coluna é NOT NULL e não
  /// existe data de nascimento de ACS a guardar: nada além do login
  /// passwordless lê este campo, e esse login não alcança esta linha.
  ///
  /// Um 23505 (`unique_violation`) devolve `null` em vez de subir: significa
  /// que outra requisição cadastrou a mesma matrícula entre a pré-checagem do
  /// serviço e este INSERT, e o resultado para quem chamou é a mesma validação
  /// do caso comum. Qualquer outro erro de banco sobe — engolir um erro
  /// inesperado aqui viraria "matrícula duplicada" para um defeito de verdade.
  @override
  Future<AdminAcs?> insertAcs({
    required String name,
    required String enrollmentId,
    required String microAreaId,
    required String ubsId,
    required PasswordDigest digest,
    required DateTime at,
  }) async {
    final session = _session();
    final id = UuidValue.fromString(_uuid.v4());
    try {
      await session.db.transaction((transaction) async {
        await User.db.insertRow(
          session,
          User(
            id: id,
            cpfHash: 'acs-sem-cpf-${id.uuid}',
            name: name,
            birthDate: DateTime.utc(1900, 1, 1),
            role: UserRole.acs,
            microAreaId: UuidValue.fromString(microAreaId),
            createdAt: at,
            updatedAt: at,
          ),
          transaction: transaction,
        );
        if (_debugFailAfterUsersInsert) {
          throw StateError('falha injetada depois de users (só em teste)');
        }
        await Acs.db.insertRow(
          session,
          Acs(
            id: id,
            enrollmentId: enrollmentId,
            ubsId: UuidValue.fromString(ubsId),
            active: true,
          ),
          transaction: transaction,
        );
        await UserCredential.db.insertRow(
          session,
          UserCredential(
            userId: id,
            passwordHash: digest.hashBase64,
            passwordSalt: digest.saltBase64,
            memoryKb: digest.memoryKb,
            iterations: digest.iterations,
            parallelism: digest.parallelism,
            failedAttempts: 0,
            lockStreak: 0,
            createdAt: at,
            updatedAt: at,
          ),
          transaction: transaction,
        );
      });
    } on DatabaseQueryException catch (e) {
      // 23505 = unique_violation: a matrícula já existe (corrida).
      if (e.code == '23505') return null;
      rethrow;
    }
    return acsById(const AdminScope.system(), id.uuid);
  }

  /// O vínculo novo: `acs."ubsId"` (a UBS da microárea-alvo) e
  /// `users."microAreaId"` na **mesma transação**.
  ///
  /// O predicado de escopo vai **dentro** do `WHERE` do `UPDATE`, e não só na
  /// pré-checagem do serviço: entre a checagem e a escrita cabe uma outra
  /// requisição movendo o mesmo ACS para fora do escopo, e quem decide é a
  /// escrita — a única leitura e a única decisão são a da mesma instrução
  /// (fecha o TOCTOU). A CTE `alvo` é o alvo `id` já filtrado pelo escopo, e o
  /// `RETURNING id` é o que diz se o `UPDATE` alcançou alguma linha: sem linha,
  /// nada é movido e nada é escrito em `users`.
  ///
  /// A UBS gravada é a [ubsId] recebida — derivada da microárea-alvo pelo
  /// serviço —, **nunca** `scope.ubsId`: o escopo do administrador é nulo, e
  /// `acs."ubsId"` é NOT NULL.
  ///
  /// A segunda escrita é conferida: o Serverpod não declara a chave
  /// estrangeira de `acs.id` para `users.id`, então um `acs` órfão é gravável,
  /// e sem esta checagem o vínculo ficaria pela metade (UBS nova no `acs`,
  /// microárea velha no `users`). Sem a linha de `users` a transação inteira
  /// volta atrás.
  @override
  Future<AdminAcs?> setAcsMicroArea({
    required String acsId,
    required String microAreaId,
    required String ubsId,
    required AdminScope scope,
    required DateTime at,
  }) async {
    // A mesma guarda de [acsById]: um id fora do formato não pode virar erro de
    // sintaxe do Postgres no `::uuid` — o desfecho dele é "não movido".
    if (!_uuidValido(acsId) ||
        !_uuidValido(microAreaId) ||
        !_uuidValido(ubsId)) {
      return null;
    }
    final session = _session();
    final vinculado = await session.db.transaction((transaction) async {
      final alvo = await session.db.unsafeQuery(
        '''
        WITH alvo AS (
          SELECT a.id FROM acs a
           WHERE a.id = @acs::uuid
             AND (@escopo::uuid IS NULL OR a."ubsId" = @escopo::uuid)
        )
        UPDATE acs SET "ubsId" = @ubs::uuid
         WHERE id IN (SELECT id FROM alvo)
        RETURNING id;
        ''',
        parameters: QueryParameters.named({
          'acs': acsId,
          'ubs': ubsId,
          'escopo': scope.ubsId,
        }),
        transaction: transaction,
      );
      if (alvo.isEmpty) return false;

      final usuarios = await session.db.unsafeExecute(
        'UPDATE users SET "microAreaId" = @ma::uuid, "updatedAt" = @at '
        'WHERE id = @acs::uuid;',
        parameters: QueryParameters.named({
          'ma': microAreaId,
          'at': at,
          'acs': acsId,
        }),
        transaction: transaction,
      );
      if (usuarios != 1) {
        // Inalcançável com dado íntegro (toda linha de `acs` nasce com a de
        // `users`); desfaz os dois UPDATEs em vez de confirmar meio vínculo.
        throw StateError(
          'acs sem linha em users: vínculo desfeito (dado inconsistente)',
        );
      }
      return true;
    });
    if (!vinculado) return null;
    return acsById(scope, acsId);
  }

  /// A flag de acesso e as revogações numa **única** transação.
  ///
  /// Desativar sem revogar deixaria a sessão do ACS viva até a próxima
  /// renovação (o `findAccount` do refresh só recusa lá) — a desativação tem de
  /// valer agora, e não no próximo `refreshSession`. Como o `UPDATE` da flag e
  /// as duas revogações são da mesma transação, não existe estado observável
  /// intermediário: ou o ACS está inativo e sem token vigente, ou nada mudou
  /// (é o que a falha injetada de [_debugFailAfterRevocations] prova).
  ///
  /// As revogações são dos stores de token, amarrados a ESTA transação pelo
  /// construtor — o SQL de cada tabela continua sendo de quem é dono dela, e
  /// nem `refresh_token_service`/`upload_token_service` nem este arquivo
  /// conhecem o `package:serverpod` do outro lado da porta.
  ///
  /// Reativar não toca em token nenhum: revogado é revogado, e o acesso novo
  /// se obtém com um login novo. O predicado de escopo vai **dentro** do
  /// `WHERE` (mesma defesa de [setAcsMicroArea]), e um id fora do formato de
  /// UUID devolve `false` sem chegar ao `::uuid` do Postgres.
  @override
  Future<bool> setAcsActive({
    required String acsId,
    required AdminScope scope,
    required bool active,
    required DateTime at,
  }) async {
    if (!_uuidValido(acsId)) return false;
    final session = _session();
    return session.db.transaction((transaction) async {
      // Sem `RETURNING`: a contagem de linhas já diz se o ACS existe no
      // escopo, e um `UPDATE` que regrava o mesmo valor conta igual — é o que
      // torna a operação idempotente sem um `SELECT` a mais.
      final linhas = await session.db.unsafeExecute(
        'UPDATE acs SET active = @ativo '
        'WHERE id = @acs::uuid '
        'AND (@escopo::uuid IS NULL OR "ubsId" = @escopo::uuid);',
        parameters: QueryParameters.named({
          'ativo': active,
          'acs': acsId,
          'escopo': scope.ubsId,
        }),
        transaction: transaction,
      );
      if (linhas != 1) return false;
      if (active) return true;

      await OrmRefreshTokenStore(
        session: _session,
        transaction: transaction,
      ).revokeAllForUser(acsId, at);
      await OrmUploadTokenStore(
        session: _session,
        transaction: transaction,
      ).revokeAllForUser(acsId, at);
      if (_debugFailAfterRevocations) {
        throw StateError('falha injetada depois das revogações (só em teste)');
      }
      return true;
    });
  }

  /// Mesma leitura de `OrmAdminReadStore.ubsOf`: `staff_accounts.ubsId` é a
  /// única fonte do escopo do coordenador.
  @override
  Future<String?> ubsOf(String staffId) async {
    if (!_uuidValido(staffId)) return null;
    final conta = await StaffAccount.db.findById(
      _session(),
      UuidValue.fromString(staffId),
    );
    return conta?.ubsId?.toString();
  }

  /// `UuidValue.fromString` **não** valida nada (só embrulha a string); quem
  /// valida o formato é `withFormatValidation`. Sem esta guarda, um id fora do
  /// formato chega ao `::uuid` e vira erro de sintaxe do Postgres — um 500 no
  /// lugar da resposta de "não existe".
  static bool _uuidValido(String id) {
    try {
      UuidValue.withFormatValidation(id);
      return true;
    } on FormatException {
      return false;
    }
  }

  static AdminAcs _acs(List<dynamic> r) => AdminAcs(
    id: r[0].toString(),
    name: r[1] as String,
    enrollmentId: r[2] as String,
    ubsId: r[3].toString(),
    ubsName: r[4] as String,
    // Nulos enquanto o ACS não tem território (`users.microAreaId`).
    microAreaId: r[5]?.toString(),
    microAreaName: r[6] as String?,
    active: r[7] as bool,
    mfaActive: r[8] as bool,
  );

  static AdminStaff _staff(List<dynamic> r) => AdminStaff(
    id: r[0].toString(),
    name: r[1] as String,
    enrollmentId: r[2] as String,
    role: UserRole.fromJson(r[3] as String),
    // Nulo para o administrador (sistema inteiro) e para o coordenador sem UBS.
    ubsName: r[4] as String?,
    active: r[5] as bool,
    mfaActive: r[6] as bool,
  );
}
