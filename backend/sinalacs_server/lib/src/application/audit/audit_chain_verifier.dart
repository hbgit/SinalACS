import 'package:sinalacs_server/src/application/audit/audit_chain.dart';

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
abstract interface class AuditChainReader {
  Future<List<AuditChainEntry>> readInOrder();
}

/// Resultado de uma verificação da cadeia.
///
/// `checked` conta quantas linhas confirmaram elo e hash antes de uma quebra
/// (ou o total, quando `ok` é `true`) — útil para dizer "as primeiras N linhas
/// estão intactas" mesmo quando a N+1 não está.
class AuditChainVerification {
  const AuditChainVerification({
    required this.ok,
    required this.checked,
    this.brokenAtSequence,
    this.reason,
  });

  final bool ok;
  final int checked;
  final int? brokenAtSequence;
  final String? reason;
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
class AuditChainVerifier {
  AuditChainVerifier({
    required AuditChainReader reader,
    required String secret,
  })  : _reader = reader,
        _chain = AuditChain(secret: secret);

  final AuditChainReader _reader;
  final AuditChain _chain;

  Future<AuditChainVerification> verify() async {
    final entries = await _reader.readInOrder();

    var expectedSequence = 1;
    var expectedPreviousHash = AuditChain.genesisHash;

    for (final entry in entries) {
      final fields = entry.fields;

      if (fields.sequence != expectedSequence) {
        return AuditChainVerification(
          ok: false,
          checked: expectedSequence - 1,
          brokenAtSequence: fields.sequence,
          reason: 'sequência descontínua: esperava $expectedSequence, '
              'encontrou ${fields.sequence} (linha apagada ou fora de ordem)',
        );
      }

      if (fields.previousHash != expectedPreviousHash) {
        return AuditChainVerification(
          ok: false,
          checked: expectedSequence - 1,
          brokenAtSequence: fields.sequence,
          reason: 'elo quebrado: previousHash não confere com a linha '
              'anterior (possível reordenação ou inserção)',
        );
      }

      if (!_chain.matches(fields, entry.entryHash)) {
        return AuditChainVerification(
          ok: false,
          checked: expectedSequence - 1,
          brokenAtSequence: fields.sequence,
          reason: 'hash não confere com o conteúdo da linha '
              '(possível adulteração)',
        );
      }

      expectedPreviousHash = entry.entryHash;
      expectedSequence++;
    }

    return AuditChainVerification(ok: true, checked: entries.length);
  }
}
