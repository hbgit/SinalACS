import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/admin/admin_labels.dart';
import 'package:sinalacs_server/src/application/admin/admin_read_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// Leitura do backoffice sobre Postgres.
///
/// SQL direto (`unsafeQuery` com parâmetros nomeados, como `orm_alert_outbox`):
/// o ORM não expressa agregação com `FILTER` nem junções. Nada aqui concatena
/// valor no texto da consulta; só a presença do filtro de escopo muda a forma.
///
/// O escopo de UBS passa por `micro_areas.ubsId`. `alerts.microAreaId` é
/// anulável, então a junção é `LEFT`: o administrador conta também o alerta sem
/// microárea; o coordenador, filtrado por `ubsId`, não o enxerga.
class OrmAdminReadStore implements AdminReadStore {
  OrmAdminReadStore({required Session Function() session}) : _session = session;

  final Session Function() _session;

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

  @override
  Future<List<AdminMicroArea>> microAreas(AdminScope scope) async {
    final rows = await _session().db.unsafeQuery(
      '''
      SELECT m.id, m.name, u.name, acs."enrollmentId", acs.active
      FROM micro_areas m
      LEFT JOIN users u ON u."microAreaId" = m.id AND u.role = 'acs'
      LEFT JOIN acs ON acs.id = u.id
      WHERE (@ubs::uuid IS NULL OR m."ubsId" = @ubs::uuid)
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
  }) async {
    final rows = await _session().db.unsafeQuery(
      '''
      SELECT a.id, a."patientId", m.name, a."riskLevel", a."status", a."triggeredAt"
      FROM alerts a
      LEFT JOIN micro_areas m ON m.id = a."microAreaId"
      WHERE $_escopo
        AND (@ma::uuid IS NULL OR a."microAreaId" = @ma::uuid)
        AND (@status::text IS NULL OR a."status" = @status::text)
      ORDER BY a."triggeredAt" DESC, a.id DESC
      LIMIT @limit OFFSET @offset
      ''',
      parameters: QueryParameters.named({
        'ubs': scope.ubsId,
        'ma': microAreaId,
        'status': status?.name,
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
          ),
      ],
      nextOffset: haMais ? offset + limit : null,
    );
  }

  @override
  Future<AdminAuditPage> auditLogs({
    required int limit,
    int? beforeSequence,
  }) async {
    // Só as colunas que a tela pode ver: nunca ipHash, previousHash nem entryHash.
    final rows = await _session().db.unsafeQuery(
      '''
      SELECT l.id, l.sequence, l."userId", u.role, COALESCE(acs."enrollmentId", s."enrollmentId"),
             l."actionType", l."resourceType", l."timestamp", l.result
      FROM audit_logs l
      LEFT JOIN users u ON u.id = l."userId"
      LEFT JOIN acs ON acs.id = l."userId"
      LEFT JOIN staff_accounts s ON s.id = l."userId"
      WHERE (@before::bigint IS NULL OR l.sequence < @before::bigint)
      ORDER BY l.sequence DESC
      LIMIT @limit
      ''',
      parameters: QueryParameters.named({
        'before': beforeSequence,
        'limit': limit + 1,
      }),
    );
    final haMais = rows.length > limit;
    final pagina = haMais ? rows.sublist(0, limit) : rows;
    final items = [
      for (final r in pagina)
        AdminAuditEntry(
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
    ];
    return AdminAuditPage(
      items: items,
      nextBeforeSequence: haMais ? items.last.sequence : null,
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
