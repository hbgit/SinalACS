import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/devices/device_wipe_service.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_data_subject_case_store.dart'
    show AuditAppender;

/// Pedidos de limpeza remota e aparelhos do ACS sobre Postgres (issue #81).
///
/// SQL direto com parâmetros nomeados, como `OrmAdminAccountStore`: a listagem
/// junta duas tabelas de token e o pedido. Nada aqui concatena valor no texto
/// da consulta.
class OrmDeviceWipeStore implements DeviceWipeStore {
  OrmDeviceWipeStore({
    required Session Function() session,
    required AuditAppender appendAudit,
  }) : _session = session,
       _appendAudit = appendAudit;

  final Session Function() _session;

  /// Onde a linha do aparelho é auditada, dentro da transação do carimbo. Em
  /// produção é `OrmAuditTrail.recordInTransaction`; o teste injeta uma falha.
  final AuditAppender _appendAudit;

  @override
  Future<List<AdminAcsDevice>> devicesOf(String acsId) async {
    if (!_uuidValido(acsId)) return const [];
    final rows = await _session().db.unsafeQuery(
      'SELECT d."deviceId", MAX(d."issuedAt") AS "lastSeenAt", '
      'o."requestedAt", o."deliveredAt", o."confirmedAt" '
      'FROM ('
      'SELECT "deviceId", "issuedAt" FROM acs_refresh_tokens '
      'WHERE "userId" = @acs::uuid '
      'UNION ALL '
      'SELECT "deviceId", "issuedAt" FROM acs_upload_tokens '
      'WHERE "userId" = @acs::uuid'
      ') d '
      'LEFT JOIN device_wipe_orders o ON o."deviceId" = d."deviceId" '
      'GROUP BY d."deviceId", o."requestedAt", o."deliveredAt", o."confirmedAt" '
      'ORDER BY "lastSeenAt" DESC, d."deviceId"',
      parameters: QueryParameters.named({'acs': acsId}),
    );
    return [
      for (final r in rows)
        () {
          final id = r[0]! as String;
          final pedido = (r[2] as DateTime?)?.toUtc();
          final entregue = r[3] as DateTime?;
          final confirmado = (r[4] as DateTime?)?.toUtc();
          return AdminAcsDevice(
            deviceId: id,
            label: 'Aparelho ${id.length > 8 ? id.substring(0, 8) : id}',
            lastSeenAt: (r[1]! as DateTime).toUtc(),
            wipeState: pedido == null
                ? null
                : confirmado != null
                ? DeviceWipeState.confirmed
                : entregue != null
                ? DeviceWipeState.delivered
                : DeviceWipeState.pending,
            wipeRequestedAt: pedido,
            wipeConfirmedAt: confirmado,
          );
        }(),
    ];
  }

  @override
  Future<bool> deviceBelongsTo(String acsId, String deviceId) async {
    if (!_uuidValido(acsId)) return false;
    final rows = await _session().db.unsafeQuery(
      'SELECT 1 FROM acs_refresh_tokens '
      'WHERE "userId" = @acs::uuid AND "deviceId" = @d '
      'UNION ALL '
      'SELECT 1 FROM acs_upload_tokens '
      'WHERE "userId" = @acs::uuid AND "deviceId" = @d LIMIT 1',
      parameters: QueryParameters.named({'acs': acsId, 'd': deviceId}),
    );
    return rows.isNotEmpty;
  }

  @override
  Future<({DeviceWipeOrder order, bool created})> orderWipe({
    required String deviceId,
    required String targetUserId,
    required String requestedBy,
    required DeviceWipeReason reason,
    required DateTime at,
  }) {
    final session = _session();
    return session.db.transaction((transaction) async {
      final inseridas = await session.db.unsafeQuery(
        'INSERT INTO device_wipe_orders '
        '("deviceId", "targetUserId", "requestedBy", reason, "requestedAt") '
        'VALUES (@d, @alvo::uuid, @autor::uuid, @motivo, @at) '
        'ON CONFLICT ("deviceId") DO NOTHING RETURNING id',
        parameters: QueryParameters.named({
          'd': deviceId,
          'alvo': targetUserId,
          'autor': requestedBy,
          'motivo': reason.name,
          'at': at.toUtc(),
        }),
        transaction: transaction,
      );
      final created = inseridas.isNotEmpty;
      final order = await DeviceWipeOrder.db.findFirstRow(
        session,
        where: (t) => t.deviceId.equals(deviceId),
        transaction: transaction,
      );
      if (order == null) {
        throw StateError('pedido de limpeza sumiu dentro da transação');
      }
      if (created) {
        for (final tabela in ['acs_refresh_tokens', 'acs_upload_tokens']) {
          await session.db.unsafeExecute(
            'UPDATE $tabela SET "revokedAt" = @at '
            'WHERE "deviceId" = @d AND "revokedAt" IS NULL',
            parameters: QueryParameters.named({'at': at.toUtc(), 'd': deviceId}),
            transaction: transaction,
          );
        }
      }
      return (order: order, created: created);
    });
  }

  @override
  Future<DeviceWipeOrder?> orderFor(String deviceId) =>
      DeviceWipeOrder.db.findFirstRow(
        _session(),
        where: (t) => t.deviceId.equals(deviceId),
      );

  @override
  Future<bool> markDelivered(
    String orderId,
    DateTime at, {
    required AuditEvent audit,
  }) async {
    if (!_uuidValido(orderId)) return false;
    final sessao = _session();
    return sessao.db.transaction((transaction) async {
      final linhas = await sessao.db.unsafeExecute(
        'UPDATE device_wipe_orders SET "deliveredAt" = @at '
        'WHERE id = @id::uuid AND "deliveredAt" IS NULL',
        parameters: QueryParameters.named({'at': at.toUtc(), 'id': orderId}),
        transaction: transaction,
      );
      if (linhas != 1) return false;
      await _appendAudit(sessao, transaction, audit);
      return true;
    });
  }

  @override
  Future<bool> markConfirmed(
    String deviceId,
    String orderId,
    DateTime at, {
    required AuditEvent audit,
  }) async {
    if (!_uuidValido(orderId)) return false;
    final sessao = _session();
    return sessao.db.transaction((transaction) async {
      final linhas = await sessao.db.unsafeExecute(
        'UPDATE device_wipe_orders SET "confirmedAt" = @at '
        'WHERE id = @id::uuid AND "deviceId" = @d AND "confirmedAt" IS NULL',
        parameters: QueryParameters.named({
          'at': at.toUtc(),
          'id': orderId,
          'd': deviceId,
        }),
        transaction: transaction,
      );
      if (linhas != 1) return false;
      await _appendAudit(sessao, transaction, audit);
      return true;
    });
  }

  static bool _uuidValido(String id) {
    try {
      UuidValue.withFormatValidation(id);
      return true;
    } on FormatException {
      return false;
    }
  }
}
