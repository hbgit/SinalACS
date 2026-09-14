import 'package:sinalacs_server/src/application/audit/audit_chain.dart';
import 'package:sinalacs_server/src/application/audit/audit_chain_verifier.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:test/test.dart';

class _ThrowingAuditTrail extends AuditTrail {
  @override
  Future<void> record(AuditEvent event) async {
    throw StateError('trilha de auditoria fora do ar');
  }
}

/// Simula o que `OrmAuditTrail` faz linha a linha, sem Postgres: monta uma
/// cadeia válida a partir de uma lista de eventos, encadeando cada um ao
/// `entryHash` do anterior. É o que permite montar cenários de adulteração
/// (editar, apagar, reordenar) sobre uma cadeia que nasceu íntegra.
class _ChainBuilder {
  _ChainBuilder({required String secret}) : _chain = AuditChain(secret: secret);

  final AuditChain _chain;
  final List<AuditChainEntry> _entries = [];

  void append({
    String userId = 'user-1',
    String actionType = 'read',
    String resourceType = 'patient_directory',
    String? resourceId,
    String result = 'granted',
  }) {
    final sequence = _entries.length + 1;
    final previousHash =
        _entries.isEmpty ? AuditChain.genesisHash : _entries.last.entryHash;
    final fields = AuditChainFields(
      sequence: sequence,
      previousHash: previousHash,
      userId: userId,
      actionType: actionType,
      resourceType: resourceType,
      resourceId: resourceId,
      timestamp: DateTime.utc(2026, 1, sequence),
      ipHash: 'hash-de-ip-$sequence',
      result: result,
    );
    _entries.add(AuditChainEntry(
      fields: fields,
      entryHash: _chain.computeEntryHash(fields),
    ));
  }

  List<AuditChainEntry> build() => List.of(_entries);
}

class _FakeReader implements AuditChainReader {
  _FakeReader(this.entries);

  final List<AuditChainEntry> entries;

  @override
  Future<List<AuditChainEntry>> readInOrder() async => entries;
}

AuditChainFields _withResult(AuditChainFields fields, String result) =>
    AuditChainFields(
      sequence: fields.sequence,
      previousHash: fields.previousHash,
      userId: fields.userId,
      actionType: fields.actionType,
      resourceType: fields.resourceType,
      resourceId: fields.resourceId,
      timestamp: fields.timestamp,
      ipHash: fields.ipHash,
      result: result,
    );

AuditChainFields _withSequence(AuditChainFields fields, int sequence) =>
    AuditChainFields(
      sequence: sequence,
      previousHash: fields.previousHash,
      userId: fields.userId,
      actionType: fields.actionType,
      resourceType: fields.resourceType,
      resourceId: fields.resourceId,
      timestamp: fields.timestamp,
      ipHash: fields.ipHash,
      result: fields.result,
    );

void main() {
  const secret = 'segredo-de-teste';

  group('AuditChain', () {
    test('a mesma entrada produz sempre o mesmo hash', () {
      final chain = AuditChain(secret: secret);
      final fields = AuditChainFields(
        sequence: 1,
        previousHash: AuditChain.genesisHash,
        userId: 'user-1',
        actionType: 'read',
        resourceType: 'patient_directory',
        resourceId: null,
        timestamp: DateTime.utc(2026, 1, 1),
        ipHash: 'hash-de-ip',
        result: 'granted',
      );

      expect(chain.computeEntryHash(fields), chain.computeEntryHash(fields));
    });

    test('trocar qualquer campo muda o hash', () {
      final chain = AuditChain(secret: secret);
      final base = AuditChainFields(
        sequence: 1,
        previousHash: AuditChain.genesisHash,
        userId: 'user-1',
        actionType: 'read',
        resourceType: 'patient_directory',
        resourceId: null,
        timestamp: DateTime.utc(2026, 1, 1),
        ipHash: 'hash-de-ip',
        result: 'granted',
      );

      expect(
        chain.computeEntryHash(_withResult(base, 'denied_territory')),
        isNot(chain.computeEntryHash(base)),
      );
    });

    test('secrets diferentes produzem hashes diferentes para o mesmo conteúdo',
        () {
      final fields = AuditChainFields(
        sequence: 1,
        previousHash: AuditChain.genesisHash,
        userId: 'user-1',
        actionType: 'read',
        resourceType: 'patient_directory',
        resourceId: null,
        timestamp: DateTime.utc(2026, 1, 1),
        ipHash: 'hash-de-ip',
        result: 'granted',
      );

      expect(
        AuditChain(secret: 'a').computeEntryHash(fields),
        isNot(AuditChain(secret: 'b').computeEntryHash(fields)),
      );
    });
  });

  group('AuditChainVerifier', () {
    test('uma cadeia vazia é íntegra por vacuidade', () async {
      final verifier =
          AuditChainVerifier(reader: _FakeReader([]), secret: secret);

      final result = await verifier.verify();

      expect(result.ok, isTrue);
      expect(result.checked, 0);
    });

    test('a gênese usa genesisHash e sequence 1', () async {
      final builder = _ChainBuilder(secret: secret)..append();
      final verifier =
          AuditChainVerifier(reader: _FakeReader(builder.build()), secret: secret);

      final result = await verifier.verify();

      expect(result.ok, isTrue);
      expect(result.checked, 1);
    });

    test('uma cadeia com várias linhas encadeadas corretamente é íntegra',
        () async {
      final builder = _ChainBuilder(secret: secret)
        ..append(result: 'granted')
        ..append(actionType: 'write', resourceType: 'visit', result: 'denied_territory')
        ..append();
      final verifier =
          AuditChainVerifier(reader: _FakeReader(builder.build()), secret: secret);

      final result = await verifier.verify();

      expect(result.ok, isTrue);
      expect(result.checked, 3);
    });

    test('editar o conteúdo de uma linha é detectado', () async {
      final builder = _ChainBuilder(secret: secret)
        ..append()
        ..append(actionType: 'write', resourceType: 'visit', result: 'denied_territory')
        ..append();
      final entries = builder.build();

      // Adultera a linha do meio SEM recalcular o hash — exatamente o que um
      // UPDATE direto no Postgres faria.
      final tampered = List.of(entries);
      tampered[1] = AuditChainEntry(
        fields: _withResult(entries[1].fields, 'granted'),
        entryHash: entries[1].entryHash,
      );

      final verifier =
          AuditChainVerifier(reader: _FakeReader(tampered), secret: secret);
      final result = await verifier.verify();

      expect(result.ok, isFalse);
      expect(result.brokenAtSequence, 2);
      expect(result.checked, 1);
      expect(result.reason, contains('adulteração'));
    });

    test('apagar uma linha do meio quebra a contiguidade', () async {
      final builder = _ChainBuilder(secret: secret)
        ..append()
        ..append()
        ..append();
      final entries = builder.build();

      final withGap = [entries[0], entries[2]]; // remove a sequence 2

      final verifier =
          AuditChainVerifier(reader: _FakeReader(withGap), secret: secret);
      final result = await verifier.verify();

      expect(result.ok, isFalse);
      expect(result.brokenAtSequence, 3);
      expect(result.checked, 1);
      expect(result.reason, contains('descontínua'));
    });

    test('renumerar uma linha para ocupar o lugar de outra apagada quebra o elo',
        () async {
      final builder = _ChainBuilder(secret: secret)
        ..append()
        ..append()
        ..append();
      final entries = builder.build();

      // Apaga a linha 2 e renumera a linha 3 para ocupar o lugar dela, sem
      // recalcular previousHash/entryHash — exatamente o que um UPDATE direto
      // no Postgres faria sem conhecer o segredo. A sequência fica contígua
      // (1, 2), então só o elo denuncia a fraude.
      final renumbered = [
        entries[0],
        AuditChainEntry(
          fields: _withSequence(entries[2].fields, 2),
          entryHash: entries[2].entryHash,
        ),
      ];

      final verifier =
          AuditChainVerifier(reader: _FakeReader(renumbered), secret: secret);
      final result = await verifier.verify();

      expect(result.ok, isFalse);
      expect(result.checked, 1);
      expect(result.reason, contains('elo quebrado'));
    });

    test('verificar com o segredo errado rejeita uma cadeia legítima',
        () async {
      final builder = _ChainBuilder(secret: secret)..append()..append();
      final verifier = AuditChainVerifier(
        reader: _FakeReader(builder.build()),
        secret: 'segredo-errado',
      );

      final result = await verifier.verify();

      expect(result.ok, isFalse);
      expect(result.brokenAtSequence, 1);
      expect(result.reason, contains('adulteração'));
    });
  });

  group('AuditTrail.recordSafely', () {
    // Regressão: a cadeia de hash não muda o contrato de recordSafely, testado
    // a fundo em patient_directory_service_test.dart e
    // visit_sync_service_test.dart — uma trilha fora do ar não pode derrubar a
    // operação clínica que está tentando auditar.
    test('não propaga falha de record', () async {
      final trail = _ThrowingAuditTrail();

      await trail.recordSafely(const AuditEvent(
        userId: 'user-1',
        actionType: 'read',
        resourceType: 'patient_directory',
        result: 'granted',
      ));
    });
  });
}
