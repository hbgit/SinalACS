import 'package:sinalacs_server/src/application/audit/audit_chain.dart';
import 'package:sinalacs_server/src/application/audit/audit_chain_verifier.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
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

/// Leitor em memória com o contrato de `readBatch`: `sequence >
/// afterSequence`, ordem crescente, no máximo `limit`. Conta as chamadas para
/// provar a leitura em lotes. As entradas são ordenadas por `sequence`, como o
/// `ORDER BY` do banco faria.
class _FakeReader implements AuditChainReader {
  _FakeReader(List<AuditChainEntry> entries, {this.falharNoLote})
      : entries = List.of(entries)
          ..sort((a, b) => a.fields.sequence.compareTo(b.fields.sequence));

  final List<AuditChainEntry> entries;
  final int? falharNoLote;
  final lotes = <({int afterSequence, int limit})>[];

  @override
  Future<List<AuditChainEntry>> readBatch({
    required int afterSequence,
    required int limit,
  }) async {
    lotes.add((afterSequence: afterSequence, limit: limit));
    if (falharNoLote == lotes.length) {
      throw Exception('banco fora do ar (sintético)');
    }
    return entries
        .where((e) => e.fields.sequence > afterSequence)
        .take(limit)
        .toList();
  }

  @override
  Future<AuditChainEntry?> entryAt(int sequence) async {
    for (final e in entries) {
      if (e.fields.sequence == sequence) return e;
    }
    return null;
  }
}

/// A versão antiga do verificador (lia tudo de uma vez), mantida no teste como
/// oráculo: a leitura em lotes tem de dar o MESMO resultado.
Future<({bool ok, int checked, int? brokenAt})> _verificarDeUmaVez(
  List<AuditChainEntry> entries,
  String secret,
) async {
  final chain = AuditChain(secret: secret);
  var expectedSequence = 1;
  var expectedPreviousHash = AuditChain.genesisHash;
  for (final entry in entries) {
    final f = entry.fields;
    if (f.sequence != expectedSequence ||
        f.previousHash != expectedPreviousHash ||
        !chain.matches(f, entry.entryHash)) {
      return (ok: false, checked: expectedSequence - 1, brokenAt: f.sequence);
    }
    expectedPreviousHash = entry.entryHash;
    expectedSequence++;
  }
  return (ok: true, checked: entries.length, brokenAt: null);
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
      expect(result.reasonCode, AuditChainReason.hashMismatch);
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
      expect(result.reasonCode, AuditChainReason.sequenceGap);
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
      expect(result.reasonCode, AuditChainReason.linkBroken);
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
      expect(result.reasonCode, AuditChainReason.hashMismatch);
    });
  });

  group('AuditChainVerifier em lotes (#45, G5)', () {
    List<AuditChainEntry> cadeia(int n) {
      final b = _ChainBuilder(secret: secret);
      for (var i = 0; i < n; i++) {
        b.append(result: i.isEven ? 'granted' : 'denied');
      }
      return b.build();
    }

    test('2500 linhas ⇒ 3 lotes de até 1000, mesmo resultado da versão antiga',
        () async {
      final entries = cadeia(2500);
      final reader = _FakeReader(entries);
      final result =
          await AuditChainVerifier(reader: reader, secret: secret).verify();

      expect(AuditChainVerifier.batchSize, 1000);
      expect(reader.lotes, hasLength(3));
      expect(reader.lotes.map((l) => l.limit).toSet(), {1000});
      expect(reader.lotes[1].afterSequence, 1000);
      expect(reader.lotes[2].afterSequence, 2000);

      final antigo = await _verificarDeUmaVez(entries, secret);
      expect(result.ok, antigo.ok);
      expect(result.ok, isTrue);
      expect(result.checked, antigo.checked);
      expect(result.checked, 2500);
      expect(result.reasonCode, isNull);
      expect(result.brokenAtSequence, isNull);
    });

    test('múltiplo exato do lote ⇒ lê um lote vazio e termina íntegro',
        () async {
      final reader = _FakeReader(cadeia(2000));
      final result =
          await AuditChainVerifier(reader: reader, secret: secret).verify();
      expect(result.ok, isTrue);
      expect(result.checked, 2000);
      expect(reader.lotes, hasLength(3));
    });

    test('remoção DENTRO de um lote é detectada', () async {
      final entries = cadeia(2500)..removeAt(1499); // apaga a sequence 1500
      final result =
          await AuditChainVerifier(reader: _FakeReader(entries), secret: secret)
              .verify();
      final antigo = await _verificarDeUmaVez(entries, secret);

      expect(result.ok, isFalse);
      expect(result.reasonCode, AuditChainReason.sequenceGap);
      expect(result.brokenAtSequence, 1501);
      expect(result.checked, 1499);
      expect(
        (result.ok, result.checked, result.brokenAtSequence),
        (antigo.ok, antigo.checked, antigo.brokenAt),
      );
    });

    test('remoção NA FRONTEIRA entre lotes é detectada', () async {
      // Apaga a sequence 1001: o 1º lote termina íntegro em 1000 e o 2º
      // começa em 1002.
      final entries = cadeia(2500)..removeAt(1000);
      final result =
          await AuditChainVerifier(reader: _FakeReader(entries), secret: secret)
              .verify();

      expect(result.ok, isFalse);
      expect(result.reasonCode, AuditChainReason.sequenceGap);
      expect(result.brokenAtSequence, 1002);
      expect(result.checked, 1000);
    });

    test('remoção da ÚLTIMA linha de um lote é detectada', () async {
      final entries = cadeia(2500)..removeAt(999); // apaga a sequence 1000
      final result =
          await AuditChainVerifier(reader: _FakeReader(entries), secret: secret)
              .verify();

      expect(result.ok, isFalse);
      expect(result.reasonCode, AuditChainReason.sequenceGap);
      expect(result.brokenAtSequence, 1001);
      expect(result.checked, 999);
    });

    test('edição no 3º lote ⇒ hashMismatch na sequence certa', () async {
      final entries = cadeia(2500);
      entries[2100] = AuditChainEntry(
        fields: _withResult(entries[2100].fields, 'adulterado'),
        entryHash: entries[2100].entryHash,
      );
      final result =
          await AuditChainVerifier(reader: _FakeReader(entries), secret: secret)
              .verify();

      expect(result.ok, isFalse);
      expect(result.reasonCode, AuditChainReason.hashMismatch);
      expect(result.brokenAtSequence, 2101);
      expect(result.checked, 2100);
    });

    test('linha com sequence 0 inserida antes da gênese é detectada', () async {
      final entries = cadeia(3);
      final intrusa = AuditChainEntry(
        fields: _withSequence(entries[0].fields, 0),
        entryHash: entries[0].entryHash,
      );
      final result = await AuditChainVerifier(
        reader: _FakeReader([intrusa, ...entries]),
        secret: secret,
      ).verify();

      expect(result.ok, isFalse);
      expect(result.reasonCode, AuditChainReason.sequenceGap);
      expect(result.brokenAtSequence, 0);
    });

    test('orçamento esgotado ⇒ ok:false com timeBudget, NUNCA ok:true',
        () async {
      // Relógio que anda 1 s a cada leitura: o orçamento de 1500 ms acaba
      // depois do 1º lote, com 1500 linhas ainda por ler.
      var agora = DateTime.utc(2026, 10, 13, 12);
      DateTime relogio() {
        final t = agora;
        agora = agora.add(const Duration(seconds: 1));
        return t;
      }

      final reader = _FakeReader(cadeia(2500));
      final result = await AuditChainVerifier(reader: reader, secret: secret)
          .verify(budget: const Duration(milliseconds: 1500), clock: relogio);

      expect(result.ok, isFalse);
      expect(result.reasonCode, AuditChainReason.timeBudget);
      expect(result.brokenAtSequence, isNull);
      expect(result.checked, lessThan(2500));
      expect(result.checked, greaterThan(0));
      expect(reader.lotes.length, lessThan(3));
    });

    test('orçamento folgado ⇒ íntegro normalmente', () async {
      final result = await AuditChainVerifier(
        reader: _FakeReader(cadeia(1500)),
        secret: secret,
      ).verify(budget: const Duration(minutes: 1));
      expect(result.ok, isTrue);
      expect(result.checked, 1500);
    });

    test('quebra achada antes do fim do orçamento vence o timeBudget',
        () async {
      final entries = cadeia(1500)..removeAt(10);
      var agora = DateTime.utc(2026, 10, 13, 12);
      final result = await AuditChainVerifier(
        reader: _FakeReader(entries),
        secret: secret,
      ).verify(
        budget: const Duration(milliseconds: 1500),
        clock: () => agora = agora.add(const Duration(seconds: 1)),
      );
      expect(result.reasonCode, AuditChainReason.sequenceGap);
      expect(result.brokenAtSequence, 12);
    });

    test('falha ao ler o banco ⇒ ok:false com databaseError', () async {
      final reader = _FakeReader(cadeia(2500), falharNoLote: 2);
      final result =
          await AuditChainVerifier(reader: reader, secret: secret).verify();
      expect(result.ok, isFalse);
      expect(result.reasonCode, AuditChainReason.databaseError);
      expect(result.checked, 1000);
      expect(result.brokenAtSequence, isNull);
    });

    test('segredo vazio ⇒ ok:false com secretUnavailable, sem ler o banco',
        () async {
      final reader = _FakeReader(cadeia(3));
      final result =
          await AuditChainVerifier(reader: reader, secret: '').verify();
      expect(result.ok, isFalse);
      expect(result.reasonCode, AuditChainReason.secretUnavailable);
      expect(reader.lotes, isEmpty);
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
