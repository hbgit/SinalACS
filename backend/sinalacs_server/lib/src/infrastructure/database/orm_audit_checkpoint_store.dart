import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/audit/audit_chain_checkpoint_store.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// [AuditChainCheckpointStore] sobre `audit_chain_checkpoints` (#45, Task 7,
/// D4). Leitura limitada pelo índice único de `sequence`; escrita só para
/// frente.
///
/// **Limite conhecido:** esta tabela vive no mesmo banco que `audit_logs`.
/// Quem apaga a cauda da cadeia com escrita direta também pode apagar os
/// checkpoints (não forjar um novo: a assinatura exige `AUDIT_CHAIN_SECRET`),
/// e restaurar um backup inteiro antigo traz cadeia e checkpoints coerentes
/// entre si. O checkpoint reduz o risco do truncamento, não o elimina.
class OrmAuditCheckpointStore implements AuditChainCheckpointStore {
  OrmAuditCheckpointStore({required Session Function() session})
    : _session = session;

  final Session Function() _session;

  /// Serializa as gravações de checkpoint entre transações: sem ele, duas
  /// verificações concorrentes com cabeças diferentes poderiam ambas passar
  /// pelo `NOT EXISTS` e a menor entrar depois da maior. Chave fixa, distinta
  /// da chave da cadeia (`OrmAuditTrail._chainLockKey`) e da forma de duas
  /// chaves de `lockPerSubject`.
  static const _checkpointLockKey = 725100824;

  @override
  Future<List<AuditChainCheckpointRecord>> latest({required int limit}) async {
    if (limit < 1) throw ArgumentError.value(limit, 'limit');
    final rows = await AuditChainCheckpoint.db.find(
      _session(),
      orderBy: (t) => t.sequence,
      orderDescending: true,
      limit: limit,
    );
    return [
      for (final r in rows)
        AuditChainCheckpointRecord(
          sequence: r.sequence,
          entryHash: r.entryHash,
          signature: r.signature,
        ),
    ];
  }

  @override
  Future<void> advanceTo(AuditChainCheckpointRecord checkpoint) async {
    final session = _session();
    await session.db.transaction((transaction) async {
      await session.db.unsafeExecute(
        'SELECT pg_advisory_xact_lock(@key);',
        parameters: QueryParameters.named({'key': _checkpointLockKey}),
        transaction: transaction,
      );
      // Só avança: nenhuma linha com `sequence` >= pode existir. O
      // `ON CONFLICT` cobre o que o lock não cobre (ex.: outra escrita fora
      // deste store) sem transformar a corrida em erro.
      await session.db.unsafeExecute(
        'INSERT INTO audit_chain_checkpoints '
        '("sequence", "entryHash", "signature", "createdAt") '
        'SELECT @sequence, @entryHash, @signature, @createdAt '
        'WHERE NOT EXISTS ('
        '  SELECT 1 FROM audit_chain_checkpoints WHERE "sequence" >= @sequence'
        ') '
        'ON CONFLICT ("sequence") DO NOTHING;',
        parameters: QueryParameters.named({
          'sequence': checkpoint.sequence,
          'entryHash': checkpoint.entryHash,
          'signature': checkpoint.signature,
          'createdAt': DateTime.now().toUtc(),
        }),
        transaction: transaction,
      );
    });
  }
}
