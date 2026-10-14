import 'package:sinalacs_server/src/application/audit/audit_chain.dart';
import 'package:sinalacs_server/src/application/audit/audit_chain_verifier.dart';
import 'package:sinalacs_server/src/application/audit/audit_row_sealer.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:test/test.dart';

/// Selo por linha (#45, D3): cada linha confere o próprio HMAC e o elo com o
/// `entryHash` da linha `sequence - 1` que o BANCO devolve — nunca com a linha
/// vizinha da página. Dados sintéticos.
const _segredo = 'segredo-sintetico-do-selo';

AuditChainFields _campos({
  required int sequence,
  required String previousHash,
  String result = 'success',
}) => AuditChainFields(
  sequence: sequence,
  previousHash: previousHash,
  userId: '00000000-0000-4000-8000-00000000a001',
  actionType: 'read',
  resourceType: 'admin_audit_logs',
  resourceId: null,
  timestamp: DateTime.utc(2026, 10, 13, 12, sequence),
  ipHash: 'ip-sintetico-$sequence',
  result: result,
);

/// Cadeia íntegra de [n] linhas, encadeada como `OrmAuditTrail` encadeia.
List<AuditChainEntry> _cadeia(int n) {
  final chain = AuditChain(secret: _segredo);
  final linhas = <AuditChainEntry>[];
  for (var s = 1; s <= n; s++) {
    final campos = _campos(
      sequence: s,
      previousHash: linhas.isEmpty
          ? AuditChain.genesisHash
          : linhas.last.entryHash,
    );
    linhas.add(
      AuditChainEntry(
        fields: campos,
        entryHash: chain.computeEntryHash(campos),
      ),
    );
  }
  return linhas;
}

AuditChainEntry _comCampos(AuditChainEntry e, AuditChainFields f) =>
    AuditChainEntry(fields: f, entryHash: e.entryHash);

void main() {
  final selador = AuditRowSealer(AuditChain(secret: _segredo));
  final linhas = _cadeia(3);

  test('linha íntegra com o vizinho certo ⇒ verified', () {
    expect(
      selador.seal(linhas[1], previousEntryHash: linhas[0].entryHash),
      AuditRowSeal.verified,
    );
  });

  test('sequence 1 com previousHash de gênese ⇒ verified', () {
    expect(
      selador.seal(linhas[0], previousEntryHash: null),
      AuditRowSeal.verified,
    );
  });

  test('sequence 1 com previousHash diferente da gênese ⇒ invalid', () {
    final chain = AuditChain(secret: _segredo);
    final campos = _campos(sequence: 1, previousHash: 'f' * 64);
    final linha = AuditChainEntry(
      fields: campos,
      entryHash: chain.computeEntryHash(campos),
    );
    expect(selador.seal(linha, previousEntryHash: null), AuditRowSeal.invalid);
  });

  test('conteúdo editado (sem recalcular o hash) ⇒ invalid', () {
    final editada = _comCampos(
      linhas[1],
      _campos(
        sequence: 2,
        previousHash: linhas[1].fields.previousHash,
        result: 'denied',
      ),
    );
    expect(
      selador.seal(editada, previousEntryHash: linhas[0].entryHash),
      AuditRowSeal.invalid,
    );
  });

  test('previousHash editado ⇒ invalid', () {
    final editada = _comCampos(
      linhas[1],
      _campos(sequence: 2, previousHash: 'a' * 64),
    );
    expect(
      selador.seal(editada, previousEntryHash: linhas[0].entryHash),
      AuditRowSeal.invalid,
    );
  });

  test('elo com outro vizinho (hash não confere com sequence-1) ⇒ invalid', () {
    // A linha está íntegra, mas o banco diz que a `sequence - 1` tem outro
    // `entryHash`: a anterior foi trocada.
    expect(
      selador.seal(linhas[1], previousEntryHash: linhas[2].entryHash),
      AuditRowSeal.invalid,
    );
  });

  test(
    'vizinho ausente (sequence > 1, previousEntryHash nulo) ⇒ unverifiable, '
    'NUNCA verified',
    () {
      final selo = selador.seal(linhas[2], previousEntryHash: null);
      expect(selo, AuditRowSeal.unverifiable);
      expect(selo, isNot(AuditRowSeal.verified));
    },
  );

  test('vizinho ausente e conteúdo editado ⇒ invalid (o HMAC já prova)', () {
    final editada = _comCampos(
      linhas[2],
      _campos(
        sequence: 3,
        previousHash: linhas[2].fields.previousHash,
        result: 'denied',
      ),
    );
    expect(
      selador.seal(editada, previousEntryHash: null),
      AuditRowSeal.invalid,
    );
  });

  test('segredo errado ⇒ invalid em todas as linhas', () {
    final outro = AuditRowSealer(AuditChain(secret: 'outro-segredo'));
    expect(
      outro.seal(linhas[0], previousEntryHash: null),
      AuditRowSeal.invalid,
    );
    expect(
      outro.seal(linhas[1], previousEntryHash: linhas[0].entryHash),
      AuditRowSeal.invalid,
    );
  });

  test('sequence menor que 1 ⇒ invalid', () {
    final chain = AuditChain(secret: _segredo);
    final campos = _campos(sequence: 0, previousHash: AuditChain.genesisHash);
    final linha = AuditChainEntry(
      fields: campos,
      entryHash: chain.computeEntryHash(campos),
    );
    expect(selador.seal(linha, previousEntryHash: null), AuditRowSeal.invalid);
  });
}
