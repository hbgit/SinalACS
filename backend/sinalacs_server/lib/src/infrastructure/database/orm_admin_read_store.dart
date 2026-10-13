import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/admin/admin_labels.dart';
import 'package:sinalacs_server/src/application/admin/admin_read_service.dart';
import 'package:sinalacs_server/src/application/audit/audit_chain.dart';
import 'package:sinalacs_server/src/application/audit/audit_chain_verifier.dart';
import 'package:sinalacs_server/src/application/audit/audit_row_sealer.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/alert_overdue_sql.dart';

/// Escapa `\`, `%` e `_` para que o texto do usuário seja literal num `LIKE`/
/// `ILIKE ... ESCAPE '\'` (#45, D2): `'%'` busca o caractere `%`, não "tudo".
/// O `\` vem primeiro, senão os escapes acrescentados seriam escapados de novo.
String escaparLike(String texto) =>
    texto.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');

/// Leitura do backoffice sobre Postgres.
///
/// SQL direto (`unsafeQuery` com parâmetros nomeados, como `orm_alert_outbox`):
/// o ORM não expressa agregação com `FILTER` nem junções. Nada aqui concatena
/// valor no texto da consulta; só a presença do filtro de escopo muda a forma.
///
/// O escopo de UBS passa por `micro_areas.ubsId`. `alerts.microAreaId` é
/// anulável, então a junção é `LEFT`: o administrador conta também o alerta sem
/// microárea; o coordenador, filtrado por `ubsId`, não o enxerga. Na auditoria
/// não há microárea na linha — ela pertence ao **autor** (`users."microAreaId"`,
/// subconsulta de [auditLogs]), e staff não tem microárea: as linhas de staff só
/// o escopo de sistema enxerga.
class OrmAdminReadStore implements AdminReadStore {
  OrmAdminReadStore({
    required Session Function() session,
    this.escalationThreshold = const Duration(seconds: 300),
  }) : _session = session;

  final Session Function() _session;

  /// Prazo do alerta vermelho (`AppConfig.redAlertEscalationSeconds`) a partir
  /// do qual `AdminAlert.overdue` vale.
  final Duration escalationThreshold;

  static const _janelaDoTmrav = Duration(days: 30);

  /// `@ubs` nulo = sistema inteiro.
  static const _escopo = '(@ubs::uuid IS NULL OR m."ubsId" = @ubs::uuid)';

  @override
  Future<AdminIndicators> indicators(
    AdminScope scope, {
    required DateTime now,
  }) async {
    final rows = await _session().db.unsafeQuery(
      '''
      SELECT
        count(*) FILTER (WHERE a."riskLevel" = 'red'),
        count(*) FILTER (WHERE a."riskLevel" = 'yellow'),
        count(*) FILTER (WHERE a."riskLevel" = 'green'),
        count(*) FILTER (WHERE a."riskLevel" = 'red' AND a."status" = 'pending'),
        count(*) FILTER (WHERE a."riskLevel" = 'red' AND a."status" = 'acknowledged'),
        round(avg(extract(epoch FROM (a."acknowledgedAt" - a."triggeredAt")))
          FILTER (WHERE a."riskLevel" = 'red'
                    AND a."acknowledgedAt" IS NOT NULL
                    AND a."triggeredAt" >= @since))::int
      FROM alerts a
      LEFT JOIN micro_areas m ON m.id = a."microAreaId"
      WHERE $_escopo
      ''',
      parameters: QueryParameters.named({
        'ubs': scope.ubsId,
        'since': now.toUtc().subtract(_janelaDoTmrav),
      }),
    );
    final r = rows.single;
    return AdminIndicators(
      red: r[0] as int,
      yellow: r[1] as int,
      green: r[2] as int,
      openRedAlerts: r[3] as int,
      acknowledgedRedAlerts: r[4] as int,
      tmravSeconds: r[5] as int?,
    );
  }

  /// Um `SELECT` só de agregados: nenhuma coluna de alerta sai daqui. A
  /// contagem usa o fragmento de `alert_overdue_sql.dart`, o mesmo de
  /// [alerts] e do escalonamento.
  @override
  Future<AlertsPulseCounts> pulse(
    AdminScope scope, {
    required DateTime now,
    required Duration threshold,
  }) async {
    final rows = await _session().db.unsafeQuery(
      '''
      SELECT
        count(*) FILTER (WHERE $alertOverdueSql),
        max(GREATEST(a."triggeredAt",
                     COALESCE(a."acknowledgedAt", a."triggeredAt"),
                     COALESCE(a."escalatedAt", a."triggeredAt")))
      FROM alerts a
      LEFT JOIN micro_areas m ON m.id = a."microAreaId"
      WHERE $_escopo
      ''',
      parameters: QueryParameters.named({
        'ubs': scope.ubsId,
        'now': now.toUtc(),
        'limite': threshold.inMicroseconds,
      }),
    );
    final r = rows.single;
    return (
      overdueRed: r[0] as int,
      maxChangedAt: (r[1] as DateTime?)?.toUtc(),
    );
  }

  /// Uma linha por microárea: o `id` é a chave do filtro de alertas no app (dois
  /// itens com o mesmo valor quebrariam o `DropdownButton`). Com mais de um ACS na
  /// área, nomes e matrículas vêm juntos, na ordem da matrícula, e `acsActive` vale
  /// se **algum** deles está ativo.
  @override
  Future<List<AdminMicroArea>> microAreas(AdminScope scope) async {
    final rows = await _session().db.unsafeQuery(
      '''
      SELECT m.id, m.name,
             string_agg(u.name, ', ' ORDER BY acs."enrollmentId"),
             string_agg(acs."enrollmentId", ', ' ORDER BY acs."enrollmentId"),
             bool_or(acs.active)
      FROM micro_areas m
      LEFT JOIN users u ON u."microAreaId" = m.id AND u.role = 'acs'
      LEFT JOIN acs ON acs.id = u.id
      WHERE (@ubs::uuid IS NULL OR m."ubsId" = @ubs::uuid)
      GROUP BY m.id, m.name
      ORDER BY m.name, m.id
      ''',
      parameters: QueryParameters.named({'ubs': scope.ubsId}),
    );
    return [
      for (final r in rows)
        AdminMicroArea(
          id: r[0].toString(),
          name: r[1] as String,
          acsName: (r[2] as String?) ?? 'Sem ACS vinculado',
          acsEnrollmentId: (r[3] as String?) ?? '—',
          acsActive: (r[4] as bool?) ?? false,
        ),
    ];
  }

  @override
  Future<AdminAlertPage> alerts(
    AdminScope scope, {
    String? microAreaId,
    AlertStatus? status,
    required int limit,
    required int offset,
    required DateTime now,
  }) async {
    final rows = await _session().db.unsafeQuery(
      '''
      SELECT a.id, a."patientId", m.name, a."riskLevel", a."status", a."triggeredAt",
             a."escalatedAt",
             -- Regra única de "vencido" (`alert_overdue_sql.dart`), a mesma de
             -- `OrmAlertEscalationStore` e de [pulse]; o acordo é pinado por
             -- test/integration/admin_read_store_test.dart ('acordo: overdue…').
             $alertOverdueSql AS vencido
      FROM alerts a
      LEFT JOIN micro_areas m ON m.id = a."microAreaId"
      WHERE $_escopo
        AND (@ma::uuid IS NULL OR a."microAreaId" = @ma::uuid)
        AND (@status::text IS NULL OR a."status" = @status::text)
      -- Vencidos primeiro (#44): um vencido além das primeiras linhas não
      -- teria botão "Escalar" em tela nenhuma. Ordena pelo próprio `vencido`
      -- (o mesmo fragmento, sem segunda cópia da regra); o desempate
      -- `triggeredAt`/`id` mantém a ordem total, estável entre páginas.
      ORDER BY vencido DESC, a."triggeredAt" DESC, a.id DESC
      LIMIT @limit OFFSET @offset
      ''',
      parameters: QueryParameters.named({
        'ubs': scope.ubsId,
        'ma': microAreaId,
        'status': status?.name,
        'now': now.toUtc(),
        'limite': escalationThreshold.inMicroseconds,
        // Uma linha a mais só para saber se há próxima página.
        'limit': limit + 1,
        'offset': offset,
      }),
    );
    final haMais = rows.length > limit;
    final pagina = haMais ? rows.sublist(0, limit) : rows;
    return AdminAlertPage(
      items: [
        for (final r in pagina)
          AdminAlert(
            id: r[0].toString(),
            patientLabel: AdminLabels.patient(r[1].toString()),
            microAreaName: (r[2] as String?) ?? 'Sem microárea',
            riskLevel: RiskLevel.fromJson(r[3] as String),
            status: AlertStatus.fromJson(r[4] as String),
            triggeredAt: (r[5] as DateTime).toUtc(),
            escalatedAt: (r[6] as DateTime?)?.toUtc(),
            overdue: r[7] as bool,
          ),
      ],
      nextOffset: haMais ? offset + limit : null,
    );
  }

  /// O escopo filtra o autor da linha, não o recurso auditado: o `IN` junta
  /// `users` a `micro_areas` (#43 — o que a #40 havia adiado). `@ubs` nulo
  /// (administrador) não filtra nada; ninguém de staff tem microárea, então
  /// só o administrador lê as linhas de staff.
  ///
  /// O [filter] (#45, D1/D2) só acrescenta condições ao `WHERE`, todas por
  /// parâmetro nomeado no formato `@p IS NULL OR …`: o texto da consulta é
  /// fixo, e o escopo e o `ORDER BY sequence DESC` não mudam com ele. A busca
  /// chega escapada por [escaparLike] e casa só o início da matrícula do
  /// autor, `resourceType` e `result` — nunca hash, IP nem UUID.
  ///
  /// Os campos da cadeia (`ipHash`, `previousHash`, `entryHash`,
  /// `resourceId`) e o `entryHash` da linha `sequence - 1` (`LEFT JOIN
  /// audit_logs p`, pelo índice único de `sequence`) vão só para o
  /// [AuditSealInput] interno de cada linha (#45, Task 5): o selo confere o
  /// vizinho da CADEIA, não o da página filtrada. A busca não os enxerga.
  @override
  Future<AdminAuditRowPage> auditLogs(
    AdminScope scope, {
    AdminAuditFilter? filter,
    required int limit,
    int? beforeSequence,
  }) async {
    final busca = filter?.search;
    // Colunas 0–8: o que a tela pode ver. 9–13: só para o selo interno
    // (nunca vão para o AdminAuditEntry).
    final rows = await _session().db.unsafeQuery(
      '''
      SELECT l.id, l.sequence, l."userId", u.role, COALESCE(acs."enrollmentId", s."enrollmentId"),
             l."actionType", l."resourceType", l."timestamp", l.result,
             l."resourceId", l."ipHash", l."previousHash", l."entryHash",
             p."entryHash"
      FROM audit_logs l
      LEFT JOIN audit_logs p ON p.sequence = l.sequence - 1
      LEFT JOIN users u ON u.id = l."userId"
      LEFT JOIN acs ON acs.id = l."userId"
      LEFT JOIN staff_accounts s ON s.id = l."userId"
      WHERE (@before::bigint IS NULL OR l.sequence < @before::bigint)
        AND (@ubs::uuid IS NULL OR l."userId" IN (
              SELECT u.id FROM users u
              JOIN micro_areas m ON m.id = u."microAreaId"
              WHERE m."ubsId" = @ubs::uuid))
        AND (@action::text IS NULL OR l."actionType" = @action::text)
        AND (@rtype::text IS NULL OR l."resourceType" = @rtype::text)
        AND (@result::text IS NULL OR l.result = @result::text)
        AND (@from::timestamp IS NULL OR l."timestamp" >= @from::timestamp)
        AND (@to::timestamp IS NULL OR l."timestamp" < @to::timestamp)
        AND (@role::text IS NULL OR u.role = @role::text)
        AND (@enroll::text IS NULL
             OR lower(COALESCE(acs."enrollmentId", s."enrollmentId"))
                = lower(@enroll::text))
        AND (@q::text IS NULL OR (
                COALESCE(acs."enrollmentId", s."enrollmentId", '')
                  ILIKE @q::text || '%' ESCAPE '\\'
             OR l."resourceType" ILIKE '%' || @q::text || '%' ESCAPE '\\'
             OR l.result ILIKE '%' || @q::text || '%' ESCAPE '\\'))
      ORDER BY l.sequence DESC
      LIMIT @limit
      ''',
      parameters: QueryParameters.named({
        'before': beforeSequence,
        'ubs': scope.ubsId,
        'action': filter?.actionType,
        'rtype': filter?.resourceType,
        'result': filter?.result,
        'from': filter?.from?.toUtc(),
        'to': filter?.to?.toUtc(),
        'role': filter?.actorRole?.name,
        'enroll': filter?.actorEnrollmentId,
        'q': busca == null ? null : escaparLike(busca),
        'limit': limit + 1,
      }),
    );
    final haMais = rows.length > limit;
    final pagina = haMais ? rows.sublist(0, limit) : rows;
    final items = [
      for (final r in pagina)
        AdminAuditRow(
          entry: AdminAuditEntry(
            id: r[0].toString(),
            sequence: r[1] as int,
            userLabel: AdminLabels.user(
              role: (r[3] as String?) ?? 'desconhecido',
              id: r[2].toString(),
              enrollmentId: r[4] as String?,
            ),
            actionType: r[5] as String,
            resourceType: r[6] as String,
            timestamp: (r[7] as DateTime).toUtc(),
            result: r[8] as String,
          ),
          seal: AuditSealInput(
            row: AuditChainEntry(
              fields: AuditChainFields(
                sequence: r[1] as int,
                previousHash: r[11] as String,
                userId: r[2].toString(),
                actionType: r[5] as String,
                resourceType: r[6] as String,
                resourceId: r[9]?.toString(),
                timestamp: r[7] as DateTime,
                ipHash: r[10] as String,
                result: r[8] as String,
              ),
              entryHash: r[12] as String,
            ),
            previousEntryHash: r[13] as String?,
          ),
        ),
    ];
    return AdminAuditRowPage(
      items: items,
      nextBeforeSequence: haMais ? items.last.entry.sequence : null,
    );
  }

  @override
  Future<String?> ubsOf(String staffId) async {
    final UuidValue id;
    try {
      id = UuidValue.fromString(staffId);
    } on FormatException {
      return null;
    }
    final conta = await StaffAccount.db.findById(_session(), id);
    return conta?.ubsId?.toString();
  }
}
