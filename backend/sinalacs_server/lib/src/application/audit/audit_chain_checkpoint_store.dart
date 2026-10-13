/// Um checkpoint de cauda da cadeia de `audit_logs` (#45, Task 7, D4): o
/// `entryHash` da linha de [sequence] no momento de uma verificação global
/// `verified`, com [signature] = `AuditChain.computeCheckpointSignature`.
/// Interno: nenhum destes campos vai ao cliente.
class AuditChainCheckpointRecord {
  const AuditChainCheckpointRecord({
    required this.sequence,
    required this.entryHash,
    required this.signature,
  });

  final int sequence;
  final String entryHash;
  final String signature;
}

/// Onde os checkpoints de cauda vivem (`audit_chain_checkpoints`). Interface
/// em `application/`, implementação ORM em
/// `infrastructure/database/orm_audit_checkpoint_store.dart` — o serviço é
/// testável sem Postgres.
abstract interface class AuditChainCheckpointStore {
  /// Os [limit] checkpoints de maior `sequence`, em ordem **decrescente** de
  /// `sequence`. Devolve as linhas como estão no banco, sem conferir
  /// assinatura: quem confere é o serviço, com a `AuditChain`.
  Future<List<AuditChainCheckpointRecord>> latest({required int limit});

  /// Grava [checkpoint] só se ele **avança**: nenhuma linha com `sequence`
  /// maior ou igual pode existir. Uma corrida que perde (outra verificação já
  /// gravou a mesma `sequence` ou uma maior) termina sem erro e sem linha —
  /// é o índice único `audit_chain_checkpoints_sequence_idx` mais um lock
  /// que tornam isso atômico. Falha de banco lança.
  Future<void> advanceTo(AuditChainCheckpointRecord checkpoint);
}
