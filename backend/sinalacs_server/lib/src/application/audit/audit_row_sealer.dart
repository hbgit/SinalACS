import 'package:sinalacs_server/src/application/audit/audit_chain.dart';
import 'package:sinalacs_server/src/application/audit/audit_chain_verifier.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// O que o selo de uma linha precisa e que **nunca** sai do servidor: os
/// campos da cadeia da própria linha (com `entryHash`) e o `entryHash` da linha
/// `sequence - 1` lido do banco — nulo quando essa linha não existe. Não é
/// modelo `.spy.yaml` de propósito: não tem serialização.
class AuditSealInput {
  const AuditSealInput({required this.row, required this.previousEntryHash});

  final AuditChainEntry row;
  final String? previousEntryHash;
}

/// Selo por linha de `audit_logs` (#45, D3) para a tela do backoffice.
///
/// Usa a MESMA [AuditChain] que grava a trilha (`OrmAuditTrail`): nenhum
/// segundo cálculo de HMAC. Cada linha é conferida contra o próprio conteúdo
/// e contra o `entryHash` da linha `sequence - 1` **que o banco devolve** —
/// nunca contra a linha vizinha da página: com filtro, as linhas de uma página
/// não têm `sequence` contígua, e compará-las entre si daria "elo quebrado"
/// falso (Review Focus 1).
///
/// Regra, nesta ordem:
/// 1. `sequence < 1` ou HMAC que não confere ⇒ [AuditRowSeal.invalid] — o
///    HMAC já prova a adulteração, com ou sem vizinho;
/// 2. `sequence == 1`: o elo é a gênese ⇒ `verified` se `previousHash` é
///    [AuditChain.genesisHash], senão `invalid`;
/// 3. vizinho ausente (`previousEntryHash` nulo) ⇒ [AuditRowSeal.unverifiable]
///    — **nunca** `verified` por omissão;
/// 4. `previousHash` diferente do `entryHash` do vizinho ⇒ `invalid`;
/// 5. senão ⇒ [AuditRowSeal.verified].
///
/// **Limite (documentado):** o selo olha só para trás. Se a linha N for
/// editada no banco, N fica `invalid`, mas a linha N+1 — cujo `previousHash`
/// aponta para o `entryHash` ORIGINAL de N, que continua gravado — segue
/// `verified`: o `entryHash` de N não foi recalculado, então o elo confere.
/// Quem vê a quebra a jusante, remoção de linhas e truncamento de cauda é a
/// verificação global ([AuditChainVerifier]), não o selo.
class AuditRowSealer {
  AuditRowSealer(this._chain);

  final AuditChain _chain;

  AuditRowSeal seal(AuditChainEntry row, {required String? previousEntryHash}) {
    final fields = row.fields;
    if (fields.sequence < 1 || !_chain.matches(fields, row.entryHash)) {
      return AuditRowSeal.invalid;
    }
    if (fields.sequence == 1) {
      return fields.previousHash == AuditChain.genesisHash
          ? AuditRowSeal.verified
          : AuditRowSeal.invalid;
    }
    if (previousEntryHash == null) return AuditRowSeal.unverifiable;
    return fields.previousHash == previousEntryHash
        ? AuditRowSeal.verified
        : AuditRowSeal.invalid;
  }

  /// Atalho para o par que o store devolve.
  AuditRowSeal sealInput(AuditSealInput input) =>
      seal(input.row, previousEntryHash: input.previousEntryHash);
}
