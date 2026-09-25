import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/audit/audit_chain.dart';
import 'package:sinalacs_server/src/application/audit/audit_chain_verifier.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// Implementação de [AuditChainReader] sobre o ORM do Serverpod.
class OrmAuditChainReader implements AuditChainReader {
  OrmAuditChainReader({required Session Function() session}) : _session = session;

  final Session Function() _session;

  @override
  Future<List<AuditChainEntry>> readInOrder() async {
    final rows = await AuditLog.db.find(
      _session(),
      orderBy: (t) => t.sequence,
    );

    return [
      for (final row in rows)
        AuditChainEntry(
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
        ),
    ];
  }
}
