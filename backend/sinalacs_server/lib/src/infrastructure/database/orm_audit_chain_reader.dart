import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/audit/audit_chain.dart';
import 'package:sinalacs_server/src/application/audit/audit_chain_verifier.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// Implementação de [AuditChainReader] sobre o ORM do Serverpod.
///
/// Toda leitura é limitada (#45, G5): `readBatch` por keyset sobre o índice
/// único `audit_logs_sequence_idx`, `entryAt` por igualdade nele.
class OrmAuditChainReader implements AuditChainReader {
  OrmAuditChainReader({required Session Function() session})
    : _session = session;

  final Session Function() _session;

  @override
  Future<List<AuditChainEntry>> readBatch({
    required int afterSequence,
    required int limit,
  }) async {
    if (limit < 1) throw ArgumentError.value(limit, 'limit');
    final rows = await AuditLog.db.find(
      _session(),
      where: (t) => t.sequence > afterSequence,
      orderBy: (t) => t.sequence,
      limit: limit,
    );
    return [for (final row in rows) entryOf(row)];
  }

  @override
  Future<AuditChainEntry?> entryAt(int sequence) async {
    final row = await AuditLog.db.findFirstRow(
      _session(),
      where: (t) => t.sequence.equals(sequence),
    );
    return row == null ? null : entryOf(row);
  }

  /// A linha do ORM na forma que a cadeia conhece.
  static AuditChainEntry entryOf(AuditLog row) => AuditChainEntry(
    fields: AuditChainFields(
      sequence: row.sequence,
      previousHash: row.previousHash,
      userId: row.userId.uuid,
      actionType: row.actionType,
      resourceType: row.resourceType,
      resourceId: row.resourceId?.uuid,
      timestamp: row.timestamp,
      ipHash: row.ipHash,
      result: row.result,
    ),
    entryHash: row.entryHash,
  );
}
