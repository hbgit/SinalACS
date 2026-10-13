import 'package:sinalacs_server/src/application/audit/audit_chain.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// Uma linha de `audit_logs` como a cadeia a vê: os campos que entram no
/// cálculo, mais o `entryHash` gravado — para o verificador comparar contra o
/// que `AuditChain.computeEntryHash` recalcula.
class AuditChainEntry {
  const AuditChainEntry({required this.fields, required this.entryHash});

  final AuditChainFields fields;
  final String entryHash;
}

/// Fonte das linhas de `audit_logs`, em ordem de `sequence` — implementada
/// sobre o ORM em `infrastructure/database/`, no mesmo molde de `AlertStore`/
/// `VisitStore`: a interface fica em `application/` para o verificador ser
/// testável sem Postgres.
///
/// Leitura sempre limitada (#45, G5): nada aqui carrega a tabela inteira.
abstract interface class AuditChainReader {
  /// Até [limit] linhas com `sequence > afterSequence`, em ordem crescente de
  /// `sequence`. Lista menor que [limit] (ou vazia) = fim da tabela.
  Future<List<AuditChainEntry>> readBatch({
    required int afterSequence,
    required int limit,
  });

  /// A linha de [sequence], ou nulo se não existe.
  Future<AuditChainEntry?> entryAt(int sequence);
}

/// Resultado de uma verificação da cadeia.
///
/// `checked` conta quantas linhas confirmaram elo e hash antes de uma quebra
/// (ou o total, quando `ok` é `true`) — útil para dizer "as primeiras N linhas
/// estão intactas" mesmo quando a N+1 não está.
///
/// `reasonCode` é o motivo fechado (#45, D9) que pode ir ao cliente; `reason`
/// é o texto livre para o operador (CLI, log) e **não** vai ao cliente.
/// `ok == false` nem sempre é adulteração: [AuditChainReason.timeBudget],
/// [AuditChainReason.databaseError] e [AuditChainReason.secretUnavailable]
/// dizem que a verificação **não terminou** — nunca que a cadeia é íntegra.
class AuditChainVerification {
  const AuditChainVerification({
    required this.ok,
    required this.checked,
    this.brokenAtSequence,
    this.reason,
    this.reasonCode,
  });

  final bool ok;
  final int checked;
  final int? brokenAtSequence;
  final String? reason;
  final AuditChainReason? reasonCode;
}

/// Verifica a integridade da cadeia de hash de `audit_logs` (LGPD-RT03).
///
/// Usa a MESMA [AuditChain] que grava as linhas: uma segunda implementação do
/// cálculo de hash aqui seria a forma mais provável de a verificação mentir.
///
/// Três checagens, nesta ordem — cada uma cobre um jeito diferente de
/// adulterar a trilha:
/// 1. `sequence` contígua a partir de 1 — detecta linha **apagada**;
/// 2. `previousHash` da linha bate com o `entryHash` da anterior (e a
///    primeira usa [AuditChain.genesisHash]) — detecta **reordenação** e
///    **inserção**;
/// 3. `entryHash` recalculado bate com o gravado — detecta **edição de
///    conteúdo**, e forjar um hash que bata exige o segredo.
///
/// Lê em lotes de [batchSize] por keyset de `sequence` (#45, G5): o estado
/// (`sequence` e `entryHash` esperados) atravessa a fronteira entre lotes,
/// então uma linha removida na fronteira quebra a contiguidade igual a uma
/// removida no meio. O primeiro lote começa abaixo de qualquer `sequence`
/// possível, para que uma linha com `sequence <= 0` também seja vista.
///
/// Com [verify]`(budget:)`, o orçamento é conferido entre lotes; esgotado com
/// linhas ainda por ler, o resultado é `ok: false` com
/// [AuditChainReason.timeBudget] — verificação parcial nunca vira íntegra.
class AuditChainVerifier {
  AuditChainVerifier({
    required AuditChainReader reader,
    required String secret,
  }) : _reader = reader,
       _secretAvailable = secret.trim().isNotEmpty,
       _chain = AuditChain(secret: secret);

  final AuditChainReader _reader;
  final bool _secretAvailable;
  final AuditChain _chain;

  static const batchSize = 1000;

  /// Menor `int` de 64 bits: o `afterSequence` do primeiro lote.
  static const _antesDeTudo = -0x8000000000000000;

  Future<AuditChainVerification> verify({
    Duration? budget,
    DateTime Function()? clock,
  }) async {
    if (!_secretAvailable) {
      return const AuditChainVerification(
        ok: false,
        checked: 0,
        reason: 'segredo da cadeia ausente',
        reasonCode: AuditChainReason.secretUnavailable,
      );
    }
    final agora = clock ?? DateTime.now;
    final inicio = agora();

    var expectedSequence = 1;
    var expectedPreviousHash = AuditChain.genesisHash;
    var afterSequence = _antesDeTudo;

    while (true) {
      final List<AuditChainEntry> entries;
      try {
        entries = await _reader.readBatch(
          afterSequence: afterSequence,
          limit: batchSize,
        );
      } on Exception {
        return AuditChainVerification(
          ok: false,
          checked: expectedSequence - 1,
          reason: 'falha ao ler audit_logs',
          reasonCode: AuditChainReason.databaseError,
        );
      }

      for (final entry in entries) {
        final fields = entry.fields;

        if (fields.sequence != expectedSequence) {
          return AuditChainVerification(
            ok: false,
            checked: expectedSequence - 1,
            brokenAtSequence: fields.sequence,
            reason:
                'sequência descontínua: esperava $expectedSequence, '
                'encontrou ${fields.sequence} (linha apagada ou fora de ordem)',
            reasonCode: AuditChainReason.sequenceGap,
          );
        }

        if (fields.previousHash != expectedPreviousHash) {
          return AuditChainVerification(
            ok: false,
            checked: expectedSequence - 1,
            brokenAtSequence: fields.sequence,
            reason:
                'elo quebrado: previousHash não confere com a linha '
                'anterior (possível reordenação ou inserção)',
            reasonCode: AuditChainReason.linkBroken,
          );
        }

        if (!_chain.matches(fields, entry.entryHash)) {
          return AuditChainVerification(
            ok: false,
            checked: expectedSequence - 1,
            brokenAtSequence: fields.sequence,
            reason:
                'hash não confere com o conteúdo da linha '
                '(possível adulteração)',
            reasonCode: AuditChainReason.hashMismatch,
          );
        }

        expectedPreviousHash = entry.entryHash;
        expectedSequence++;
      }

      if (entries.length < batchSize) break;
      afterSequence = entries.last.fields.sequence;

      if (budget != null && agora().difference(inicio) > budget) {
        return AuditChainVerification(
          ok: false,
          checked: expectedSequence - 1,
          reason:
              'orçamento de tempo esgotado antes do fim da cadeia '
              '(verificação parcial)',
          reasonCode: AuditChainReason.timeBudget,
        );
      }
    }

    return AuditChainVerification(ok: true, checked: expectedSequence - 1);
  }
}
