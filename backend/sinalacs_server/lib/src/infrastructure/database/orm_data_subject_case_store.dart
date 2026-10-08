import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/admin/admin_labels.dart';
import 'package:sinalacs_server/src/application/admin/admin_read_service.dart';
import 'package:sinalacs_server/src/application/admin/data_subject_case_service.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/onboarding/consent_signature.dart';
import 'package:sinalacs_server/src/application/onboarding/onboarding_service.dart'
    show ConsentLogEntry, consentPolicyVersion;
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/encrypted_json.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/health_data_cipher.dart';
import 'package:sinalacs_server/src/infrastructure/database/removed_account.dart';
import 'package:sinalacs_server/src/infrastructure/database/signed_consent_log.dart';
import 'package:sinalacs_server/src/infrastructure/database/subject_lock.dart';

/// Grava um evento de auditoria DENTRO de [transaction]. Em produção é
/// `OrmAuditTrail.recordInTransaction`; o teste injeta uma falha por aqui.
typedef AuditAppender =
    Future<void> Function(
      Session session,
      Transaction transaction,
      AuditEvent event,
    );

/// Atendimento de pedidos do titular (#42) sobre Postgres.
///
/// Leitura em SQL direto (`unsafeQuery` com parâmetros nomeados, como
/// `OrmAdminReadStore`): o escopo de UBS é uma junção
/// `data_subject_requests → users → micro_areas.ubsId`. A microárea mora em
/// `users`, não em `patients`, e por isso o titular sem linha em `patients`
/// continua no escopo. Titular sem microárea só aparece para o administrador.
///
/// `details` e a nota de resposta são cifrados com o mesmo [HealthDataCipher]
/// de `visits.notes`; a lista nunca os decifra, só o detalhe ([find]).
class OrmDataSubjectCaseStore implements DataSubjectCaseStore {
  OrmDataSubjectCaseStore(
    this._session,
    this._cipher, {
    required String chainSecret,
    required this.appendAudit,
  }) : _signature = ConsentSignature(secret: chainSecret);

  final Session _session;
  final HealthDataCipher _cipher;

  /// Assina o `denied` de push da anonimização com o MESMO `AUDIT_CHAIN_SECRET`
  /// do painel do titular (`OrmDataSubjectRightsStore`).
  final ConsentSignature _signature;
  /// Onde a decisão é auditada, dentro da transação dela.
  final AuditAppender appendAudit;

  static const rotuloRemovido = 'Titular removido';

  /// `users.birthDate` é NOT NULL: a data real dá lugar a este marcador fixo.
  static final nascimentoRemovido = DateTime.utc(1900, 1, 1);

  /// `@ubs` nulo = sistema inteiro.
  static const _base = '''
      FROM data_subject_requests r
      JOIN users u ON u.id = r."userId"
      LEFT JOIN micro_areas m ON m.id = u."microAreaId"
      WHERE (@ubs::uuid IS NULL OR m."ubsId" = @ubs::uuid)''';

  static const _abertos = {
    DataSubjectRequestStatus.open,
    DataSubjectRequestStatus.inReview,
  };

  static bool _vencido(DataSubjectRequestStatus s, DateTime dueAt, DateTime now) =>
      _abertos.contains(s) && now.isAfter(dueAt);

  /// `UuidValue.fromString` não valida: a string inválida só estoura no
  /// Postgres (22P02). Id malformado = pedido inexistente.
  static UuidValue? _uuid(String id) =>
      Uuid.isValidUUID(fromString: id) ? UuidValue.fromString(id) : null;

  @override
  Future<String?> ubsOf(String staffId) async {
    final id = _uuid(staffId);
    if (id == null) return null;
    final conta = await StaffAccount.db.findById(_session, id);
    return conta?.ubsId?.toString();
  }

  @override
  Future<AdminDataSubjectRequestPage> list(
    AdminScope scope, {
    DataSubjectRequestStatus? status,
    required int limit,
    required int offset,
    required DateTime now,
  }) async {
    // Prazo mais próximo primeiro: os vencidos sobem ao topo da fila.
    final rows = await _session.db.unsafeQuery(
      '''
      SELECT r.id, r."userId", r."requestType", r.status, r."createdAt", r."dueAt"
      $_base
        AND (@status::text IS NULL OR r.status = @status::text)
      ORDER BY r."dueAt" ASC, r.id ASC
      LIMIT @limit OFFSET @offset
      ''',
      parameters: QueryParameters.named({
        'ubs': scope.ubsId,
        'status': status?.name,
        // Uma linha a mais só para saber se há próxima página.
        'limit': limit + 1,
        'offset': offset,
      }),
    );
    final haMais = rows.length > limit;
    final pagina = haMais ? rows.sublist(0, limit) : rows;
    return AdminDataSubjectRequestPage(
      items: [
        for (final r in pagina)
          () {
            final st = DataSubjectRequestStatus.fromJson(r[3] as String);
            final due = (r[5] as DateTime).toUtc();
            return AdminDataSubjectRequest(
              id: r[0].toString(),
              type: DataSubjectRequestType.fromJson(r[2] as String),
              status: st,
              createdAt: (r[4] as DateTime).toUtc(),
              dueAt: due,
              overdue: _vencido(st, due, now),
              patientLabel: AdminLabels.patient(r[1].toString()),
            );
          }(),
      ],
      nextOffset: haMais ? offset + limit : null,
    );
  }

  @override
  Future<AdminDataSubjectRequestDetail?> find(
    AdminScope scope,
    String id, {
    required DateTime now,
  }) async {
    final uuid = _uuid(id);
    if (uuid == null) return null;
    final rows = await _session.db.unsafeQuery(
      '''
      SELECT r.id, r."userId", r."requestType", r.status, r."createdAt", r."dueAt",
             r."detailsEncrypted", r."detailsKeyVersion",
             r."resolutionEncrypted", r."resolutionKeyVersion", r."decidedAt"
      $_base
        AND r.id = @id::uuid
      ''',
      parameters: QueryParameters.named({'ubs': scope.ubsId, 'id': uuid.uuid}),
    );
    if (rows.isEmpty) return null;
    final r = rows.single;
    final st = DataSubjectRequestStatus.fromJson(r[3] as String);
    final due = (r[5] as DateTime).toUtc();
    final resolucaoCifrada = r[8] as String?;
    return AdminDataSubjectRequestDetail(
      id: r[0].toString(),
      type: DataSubjectRequestType.fromJson(r[2] as String),
      status: st,
      createdAt: (r[4] as DateTime).toUtc(),
      dueAt: due,
      overdue: _vencido(st, due, now),
      patientLabel: AdminLabels.patient(r[1].toString()),
      details: await _cipher.decryptJson(r[6] as String, r[7] as int) as String?,
      resolution: resolucaoCifrada == null
          ? null
          : await _cipher.decryptJson(resolucaoCifrada, r[9] as int) as String?,
      decidedAt: (r[10] as DateTime?)?.toUtc(),
    );
  }

  /// Ordem dos locks, sempre a mesma, para não haver deadlock:
  /// 1. pedido (`lockNamespaceDataSubjectCase`) — dois analistas no mesmo pedido;
  /// 2. titular (`lockNamespaceDeletion`, o MESMO de
  ///    `OrmDataSubjectRightsStore.createDeletionRequestIfNoneOpen`) — duas
  ///    exclusões do mesmo titular decididas ao mesmo tempo, ou o titular
  ///    abrindo um pedido novo durante a anonimização;
  /// 3. push do titular (`lockNamespacePushToken`, o MESMO de
  ///    `OrmPushTokenStore.registerIfConsented`), só na anonimização — um
  ///    registro de token em voo termina antes do `DELETE` ou espera e lê o
  ///    `denied`;
  /// 4. cadeia de auditoria, tomado dentro de [appendAudit], por último.
  /// O status é relido só depois dos dois primeiros locks. Nenhum outro
  /// escritor pega estes locks na ordem inversa: o registro de push pega 3 e o
  /// lock por token (4 em `subject_lock.dart`), nunca 1 nem 6.
  @override
  Future<bool> decide(
    AdminScope scope,
    String id, {
    required Set<DataSubjectRequestStatus> from,
    required DataSubjectRequestStatus to,
    required String? resolution,
    required String decidedBy,
    required bool anonymize,
    required AuditEvent audit,
    required DateTime now,
  }) async {
    final uuid = _uuid(id);
    if (uuid == null) return false;
    final decisor = UuidValue.fromString(decidedBy);
    final nota = resolution == null ? null : await _cipher.encryptJson(resolution);
    final session = _session;

    return session.db.transaction((transaction) async {
      await lockPerSubject(
        session,
        transaction,
        namespace: lockNamespaceDataSubjectCase,
        key: uuid.uuid,
      );
      // Só o dono e o escopo; `userId` não muda, então pode ser lido antes do
      // lock do titular.
      final dono = await session.db.unsafeQuery(
        'SELECT r."userId" $_base AND r.id = @id::uuid',
        parameters: QueryParameters.named({'ubs': scope.ubsId, 'id': uuid.uuid}),
        transaction: transaction,
      );
      // Inexistente ou fora do escopo: o serviço trata como corrida perdida.
      if (dono.isEmpty) return false;
      final titular = dono.single[0].toString();
      await lockPerSubject(
        session,
        transaction,
        namespace: lockNamespaceDeletion,
        key: titular,
      );

      final pedido = await DataSubjectRequest.db.findById(
        session,
        uuid,
        transaction: transaction,
      );
      if (pedido == null || !from.contains(pedido.status)) return false;

      await DataSubjectRequest.db.updateRow(
        session,
        pedido.copyWith(
          status: to,
          decidedAt: now,
          decidedBy: decisor,
          resolutionEncrypted: nota?.ciphertextBase64,
          resolutionKeyVersion: nota?.keyVersion,
        ),
        transaction: transaction,
      );

      var irmaos = const <UuidValue>[];
      if (anonymize) {
        if (pedido.requestType != DataSubjectRequestType.deletion) {
          throw StateError('anonimização só atende pedido de exclusão');
        }
        irmaos = await _anonimizar(
          session,
          transaction,
          titular: pedido.userId,
          pedido: uuid,
          decisor: decisor,
          now: now,
        );
      }

      // Por último e na mesma transação: se a auditoria falhar, nada fica.
      await appendAudit(session, transaction, audit);
      // Cada pedido irmão fechado junto ganha a própria linha, com a mesma
      // forma da decisão principal e o id dele.
      for (final irmao in irmaos) {
        await appendAudit(
          session,
          transaction,
          AuditEvent(
            userId: audit.userId,
            actionType: audit.actionType,
            resourceType: audit.resourceType,
            resourceId: irmao.uuid,
            result: 'completed',
          ),
        );
      }
      return true;
    });
  }

  /// Exclusão atendida = anonimização (decisão 2 da #42): some a identidade do
  /// titular e o que liga aparelho/login a ele; ficam `alerts`, `visits`,
  /// `audit_logs` e `consent_logs` (trilha e estatística pseudonimizada,
  /// `spec/lgpd_design.md` 5.7). A microárea do usuário fica, para o pedido
  /// continuar no escopo do coordenador que o atendeu.
  ///
  /// Devolve os ids dos outros pedidos de exclusão fechados junto, para a
  /// auditoria de cada um.
  Future<List<UuidValue>> _anonimizar(
    Session session,
    Transaction transaction, {
    required UuidValue titular,
    required UuidValue pedido,
    required UuidValue decisor,
    required DateTime now,
  }) async {
    final usuario = await User.db.findById(
      session,
      titular,
      transaction: transaction,
    );
    // Pedido de exclusão só nasce do próprio paciente; qualquer outro papel aqui
    // é dado inconsistente, e apagar a credencial de um ACS ou do staff seria
    // grave. Lançar desfaz a transação inteira.
    if (usuario == null || usuario.role != UserRole.patient) {
      throw StateError('titular do pedido de exclusão não é paciente');
    }
    await User.db.updateRow(
      session,
      usuario.copyWith(
        name: rotuloRemovido,
        // Aleatório e nunca derivado do CPF: o mesmo CPF não volta a achar
        // esta linha no login, e o índice único segue satisfeito.
        cpfHash: '$removedCpfHashPrefix${const Uuid().v4()}',
        birthDate: nascimentoRemovido,
        updatedAt: now,
      ),
      transaction: transaction,
    );
    // `copyWith` não zera campo anulável; o UPDATE vai em SQL. Titular sem
    // linha em `patients` atualiza zero linhas e segue.
    await session.db.unsafeExecute(
      '''
      UPDATE patients
      SET "chronicConditionsEncrypted" = '', "lastLocationHash" = NULL,
          "emergencyContact" = ''
      WHERE id = @id::uuid
      ''',
      parameters: QueryParameters.named({'id': titular.uuid}),
      transaction: transaction,
    );
    // Respostas da triagem viram a coluna vazia, que `decryptJson` lê como
    // "sem respostas"; a sessão (risco e data) fica para a estatística, como
    // os alertas. Apagar a linha perderia esse histórico pseudonimizado.
    await session.db.unsafeExecute(
      '''
      UPDATE triage_sessions SET "answersEncrypted" = ''
      WHERE "patientId" = @id::uuid
      ''',
      parameters: QueryParameters.named({'id': titular.uuid}),
      transaction: transaction,
    );
    // Push: a sessão do titular pode seguir viva até o JWT vencer, e
    // `registerIfConsented` só olha o consentimento mais recente. Sob o lock
    // de push do titular, apaga os tokens e acrescenta um `denied` assinado
    // (append-only: as linhas anteriores ficam como estão). Só `segmentedPush`.
    await lockPerSubject(
      session,
      transaction,
      namespace: lockNamespacePushToken,
      key: titular.uuid,
    );
    await PushToken.db.deleteWhere(
      session,
      where: (t) => t.userId.equals(titular),
      transaction: transaction,
    );
    final ultimo = await ConsentLog.db.findFirstRow(
      session,
      where: (t) =>
          t.userId.equals(titular) &
          t.purpose.equals(ConsentPurpose.segmentedPush.name),
      orderBy: (t) => t.timestamp,
      orderDescending: true,
      transaction: transaction,
    );
    // Estritamente depois do último: no empate de instante a leitura desempata
    // por id aleatório, e o `denied` poderia perder para um `granted`.
    final instante = ultimo == null || ultimo.timestamp.isBefore(now)
        ? now
        : ultimo.timestamp.add(const Duration(microseconds: 1));
    await ConsentLog.db.insertRow(
      session,
      signedConsentLog(
        ConsentLogEntry(
          userId: titular.uuid,
          purpose: ConsentPurpose.segmentedPush,
          action: 'denied',
          version: consentPolicyVersion,
          timestamp: instante,
        ),
        signature: _signature,
        origin: 'atendimento-exclusao',
      ),
      transaction: transaction,
    );
    await OtpChallenge.db.deleteWhere(
      session,
      where: (t) => t.userId.equals(titular),
      transaction: transaction,
    );
    await UserCredential.db.deleteWhere(
      session,
      where: (t) => t.userId.equals(titular),
      transaction: transaction,
    );
    // Outros pedidos de exclusão ainda abertos do mesmo titular perderam o
    // objeto: fecham juntos, com a mesma decisão. Correções ficam como estão.
    // Pelo ORM, e não em SQL, para `decidedAt` ser gravado como o resto da
    // tabela. Sob o lock do titular, nenhum outro decide estes pedidos agora.
    final outros = await DataSubjectRequest.db.find(
      session,
      where: (t) =>
          t.userId.equals(titular) &
          t.requestType.equals(DataSubjectRequestType.deletion) &
          t.status.inSet(_abertos) &
          t.id.notEquals(pedido),
      transaction: transaction,
    );
    for (final outro in outros) {
      await DataSubjectRequest.db.updateRow(
        session,
        outro.copyWith(
          status: DataSubjectRequestStatus.completed,
          decidedAt: now,
          decidedBy: decisor,
        ),
        transaction: transaction,
      );
    }
    return [for (final outro in outros) outro.id!];
  }
}
