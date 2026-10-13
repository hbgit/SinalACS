import 'dart:async';
import 'dart:convert';

import 'package:sinalacs_server/src/application/admin/audit_chain_status_service.dart';
import 'package:sinalacs_server/src/application/audit/audit_chain.dart';
import 'package:sinalacs_server/src/application/audit/audit_chain_verifier.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:test/test.dart';

/// `AuditChainStatusService` (#45, Task 6) sem banco: reader, store, trilha e
/// relógio falsos. Prova o mapeamento verificador → estado (D3), a projeção
/// por papel (D9: o coordenador não aprende nada de outra UBS), o
/// single-flight e o cache de 60 s, e que nada além de uma cadeia íntegra e
/// não vazia vira `verified`. Dados sintéticos.
const _segredo = 'segredo-sintetico-da-task-6';
const _ubsA = 'ubs-a';

final _ordem = <String>[];

class _Cadeia {
  _Cadeia() : _chain = AuditChain(secret: _segredo);

  final AuditChain _chain;
  final entries = <AuditChainEntry>[];

  void append({String userId = 'autor-1', String result = 'success'}) {
    final sequence = entries.length + 1;
    final fields = AuditChainFields(
      sequence: sequence,
      previousHash: entries.isEmpty
          ? AuditChain.genesisHash
          : entries.last.entryHash,
      userId: userId,
      actionType: 'read',
      resourceType: 'recurso_sintetico',
      resourceId: null,
      timestamp: DateTime.utc(2026, 10, 13, 12).add(Duration(seconds: sequence)),
      ipHash: 'ip-$sequence',
      result: result,
    );
    entries.add(
      AuditChainEntry(fields: fields, entryHash: _chain.computeEntryHash(fields)),
    );
  }
}

AuditChainFields _copia(
  AuditChainFields f, {
  int? sequence,
  String? previousHash,
  String? result,
}) => AuditChainFields(
  sequence: sequence ?? f.sequence,
  previousHash: previousHash ?? f.previousHash,
  userId: f.userId,
  actionType: f.actionType,
  resourceType: f.resourceType,
  resourceId: f.resourceId,
  timestamp: f.timestamp,
  ipHash: f.ipHash,
  result: result ?? f.result,
);

class _Reader implements AuditChainReader {
  _Reader(List<AuditChainEntry> entries)
    : entries = List.of(entries)
        ..sort((a, b) => a.fields.sequence.compareTo(b.fields.sequence));

  List<AuditChainEntry> entries;
  final lotes = <int>[];

  /// Se não nulo, o primeiro lote espera por ele (single-flight).
  Completer<void>? portao;
  Object? lancar;
  bool travar = false;

  @override
  Future<List<AuditChainEntry>> readBatch({
    required int afterSequence,
    required int limit,
  }) async {
    lotes.add(afterSequence);
    _ordem.add('reader:readBatch');
    final p = portao;
    if (p != null) await p.future;
    if (travar) await Completer<void>().future;
    final erro = lancar;
    if (erro != null) throw erro;
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

class _Store implements AuditChainScopeStore {
  final Map<String, String?> ubs = {
    'coord-a': _ubsA,
    'coord-b': 'ubs-b',
    'coord-sem-ubs': null,
  };

  /// `sequence → UBS do autor`.
  final Map<int, String> donoDa = {};
  bool falharPertencimento = false;
  final consultas = <(int, String)>[];

  @override
  Future<String?> ubsOf(String staffId) async => ubs[staffId];

  @override
  Future<bool> auditRowInUbs(int sequence, String ubsId) async {
    consultas.add((sequence, ubsId));
    if (falharPertencimento) throw StateError('banco fora do ar (sintético)');
    return donoDa[sequence] == ubsId;
  }
}

class _Audit extends AuditTrail {
  final events = <AuditEvent>[];
  bool falhar = false;

  @override
  Future<void> record(AuditEvent event) async {
    if (falhar) throw StateError('auditoria indisponível');
    _ordem.add('audit:${event.actionType}:${event.resourceType}:${event.result}');
    events.add(event);
  }
}

AuthenticatedUser _u(String id, UserRole role, {String? ma}) =>
    AuthenticatedUser(
      id: id,
      role: role,
      microAreaId: ma,
      deviceId: 'sem-aparelho',
    );

void main() {
  late _Cadeia cadeia;
  late _Store store;
  late _Audit audit;
  late AuditChainStatusCache cache;
  late DateTime agora;
  final t0 = DateTime.utc(2026, 10, 13, 15);
  final admin = _u('admin-1', UserRole.admin);
  final coordA = _u('coord-a', UserRole.coordinator);
  final coordB = _u('coord-b', UserRole.coordinator);

  setUp(() {
    _ordem.clear();
    cadeia = _Cadeia();
    for (var i = 0; i < 5; i++) {
      cadeia.append();
    }
    store = _Store();
    audit = _Audit();
    cache = AuditChainStatusCache();
    agora = t0;
  });

  AuditChainStatusService servico(
    _Reader reader, {
    String segredo = _segredo,
    Duration budget = AuditChainStatusService.defaultBudget,
    Duration readTimeout = AuditChainStatusService.defaultReadTimeout,
    DateTime Function()? clock,
  }) => AuditChainStatusService(
    store: store,
    audit: audit,
    reader: reader,
    secret: segredo,
    cache: cache,
    budget: budget,
    readTimeout: readTimeout,
    clock: clock ?? () => agora,
  );

  group('estado (D3)', () {
    test('cadeia íntegra ⇒ verified, com checkedRows e headSequence', () async {
      final s = await servico(_Reader(cadeia.entries)).verify(admin);
      expect(s.state, AuditIntegrityState.verified);
      expect(s.checkedRows, 5);
      expect(s.headSequence, 5);
      expect(s.firstBrokenSequence, isNull);
      expect(s.brokenInScope, isNull);
      expect(s.reasonCode, isNull);
      expect(s.verifiedAt, t0);
    });

    final adulteracoes =
        <
          String,
          (
            List<AuditChainEntry> Function(List<AuditChainEntry>),
            AuditChainReason,
            int,
            String?,
          )
        >{
          'edição do conteúdo da linha 3': (
            (e) => [
              ...e.take(2),
              AuditChainEntry(
                fields: _copia(e[2].fields, result: 'x'),
                entryHash: e[2].entryHash,
              ),
              ...e.skip(3),
            ],
            AuditChainReason.hashMismatch,
            3,
            null,
          ),
          'remoção da linha 3': (
            (e) => [...e.take(2), ...e.skip(3)],
            AuditChainReason.sequenceGap,
            4,
            null,
          ),
          'renumeração da 4 para ocupar a 3 apagada': (
            (e) => [
              ...e.take(2),
              AuditChainEntry(
                fields: _copia(e[3].fields, sequence: 3),
                entryHash: e[3].entryHash,
              ),
              ...e.skip(4),
            ],
            AuditChainReason.linkBroken,
            3,
            null,
          ),
          // Review Focus 3: segredo trocado quebra já na 1 — "falha", nunca
          // "íntegra".
          'segredo trocado no servidor': (
            (e) => e,
            AuditChainReason.hashMismatch,
            1,
            'outro-segredo',
          ),
        };

    for (final MapEntry(key: nome, value: (mutar, motivo, seq, segredo))
        in adulteracoes.entries) {
      test('$nome ⇒ broken/${motivo.name} na sequence $seq', () async {
        final s = await servico(
          _Reader(mutar(cadeia.entries)),
          segredo: segredo ?? _segredo,
        ).verify(admin);
        expect(s.state, AuditIntegrityState.broken);
        expect(s.reasonCode, motivo);
        expect(s.firstBrokenSequence, seq);
        expect(s.brokenInScope, isTrue);
        expect(s.headSequence, isNull);
      });
    }

    test('reader lança Exception ⇒ unavailable/databaseError', () async {
      final r = _Reader(cadeia.entries)..lancar = Exception('fora do ar');
      final s = await servico(r).verify(admin);
      expect(s.state, AuditIntegrityState.unavailable);
      expect(s.reasonCode, AuditChainReason.databaseError);
    });

    test(
      'reader lança Error (não Exception) ⇒ unavailable/databaseError, não 500',
      () async {
        final r = _Reader(cadeia.entries)..lancar = StateError('pool fechado');
        final s = await servico(r).verify(admin);
        expect(s.state, AuditIntegrityState.unavailable);
        expect(s.reasonCode, AuditChainReason.databaseError);
      },
    );

    test('leitura que não responde ⇒ timeout ⇒ unavailable/databaseError',
        () async {
      final r = _Reader(cadeia.entries)..travar = true;
      final s = await servico(
        r,
        readTimeout: const Duration(milliseconds: 20),
      ).verify(admin);
      expect(s.state, AuditIntegrityState.unavailable);
      expect(s.reasonCode, AuditChainReason.databaseError);
    });

    test('segredo vazio ⇒ unavailable/secretUnavailable, sem ler o banco',
        () async {
      for (final vazio in ['', '   ']) {
        cache.reset();
        final r = _Reader(cadeia.entries);
        final s = await servico(r, segredo: vazio).verify(admin);
        expect(s.state, AuditIntegrityState.unavailable, reason: '"$vazio"');
        expect(s.reasonCode, AuditChainReason.secretUnavailable);
        expect(r.lotes, isEmpty);
      }
    });

    test('cadeia vazia ⇒ inconclusive (nada a atestar), nunca verified',
        () async {
      final s = await servico(_Reader(const [])).verify(admin);
      expect(s.state, AuditIntegrityState.inconclusive);
      expect(s.reasonCode, isNull);
      expect(s.checkedRows, 0);
      expect(s.headSequence, isNull);
    });

    test('orçamento esgotado ⇒ inconclusive/timeBudget', () async {
      final grande = _Cadeia();
      for (var i = 0; i < AuditChainVerifier.batchSize + 10; i++) {
        grande.append();
      }
      var tique = t0;
      final s = await servico(
        _Reader(grande.entries),
        budget: Duration.zero,
        clock: () => tique = tique.add(const Duration(milliseconds: 1)),
      ).verify(admin);
      expect(s.state, AuditIntegrityState.inconclusive);
      expect(s.reasonCode, AuditChainReason.timeBudget);
      expect(s.firstBrokenSequence, isNull);
    });
  });

  group('propriedade negativa: não-verified nunca é verified', () {
    for (final motivo in AuditChainReason.values) {
      test('ok:false com ${motivo.name} ⇒ state != verified', () {
        for (final checked in [0, 1, 5, 1000]) {
          final estado = AuditChainStatusService.stateOf(
            AuditChainVerification(
              ok: false,
              checked: checked,
              brokenAtSequence: checked + 1,
              reasonCode: motivo,
            ),
          );
          expect(estado, isNot(AuditIntegrityState.verified));
        }
      });
    }

    test('ok:false sem reasonCode ⇒ unavailable (defensivo)', () {
      expect(
        AuditChainStatusService.stateOf(
          const AuditChainVerification(ok: false, checked: 9),
        ),
        AuditIntegrityState.unavailable,
      );
    });

    test('só ok:true com linhas ⇒ verified', () {
      expect(
        AuditChainStatusService.stateOf(
          const AuditChainVerification(ok: true, checked: 1),
        ),
        AuditIntegrityState.verified,
      );
      expect(
        AuditChainStatusService.stateOf(
          const AuditChainVerification(ok: true, checked: 0),
        ),
        AuditIntegrityState.inconclusive,
      );
    });
  });

  group('papel e escopo (D9, Review Focus 7)', () {
    List<AuditChainEntry> editada3(List<AuditChainEntry> e) => [
      ...e.take(2),
      AuditChainEntry(
        fields: _copia(e[2].fields, result: 'x'),
        entryHash: e[2].entryHash,
      ),
      ...e.skip(3),
    ];

    test(
      'coordenador com quebra de outra UBS ⇒ broken, brokenInScope=false, '
      'sem sequence, sem motivo e sem volume',
      () async {
        store.donoDa[3] = 'ubs-b';
        final s = await servico(_Reader(editada3(cadeia.entries))).verify(coordA);
        expect(s.state, AuditIntegrityState.broken);
        expect(s.brokenInScope, isFalse);
        expect(s.firstBrokenSequence, isNull);
        expect(s.reasonCode, isNull);
        expect(s.checkedRows, isNull);
        expect(s.headSequence, isNull);
        expect(store.consultas, [(3, _ubsA)]);
      },
    );

    test(
      'coordenador com quebra na própria UBS ⇒ broken, brokenInScope=true, '
      'sequence e motivo',
      () async {
        store.donoDa[3] = _ubsA;
        final s = await servico(_Reader(editada3(cadeia.entries))).verify(coordA);
        expect(s.state, AuditIntegrityState.broken);
        expect(s.brokenInScope, isTrue);
        expect(s.firstBrokenSequence, 3);
        expect(s.reasonCode, AuditChainReason.hashMismatch);
        expect(s.checkedRows, isNull);
      },
    );

    test(
      'pertencimento que falha ⇒ broken, brokenInScope nulo, sem sequence',
      () async {
        store.falharPertencimento = true;
        final s = await servico(_Reader(editada3(cadeia.entries))).verify(coordA);
        expect(s.state, AuditIntegrityState.broken);
        expect(s.brokenInScope, isNull);
        expect(s.firstBrokenSequence, isNull);
      },
    );

    test('coordenador com cadeia íntegra ⇒ verified, sem volume', () async {
      final s = await servico(_Reader(cadeia.entries)).verify(coordB);
      expect(s.state, AuditIntegrityState.verified);
      expect(s.checkedRows, isNull);
      expect(s.headSequence, isNull);
      expect(store.consultas, isEmpty);
    });

    test('coordenador vê o motivo de unavailable/inconclusive', () async {
      final s = await servico(
        _Reader(cadeia.entries),
        segredo: '',
      ).verify(coordA);
      expect(s.state, AuditIntegrityState.unavailable);
      expect(s.reasonCode, AuditChainReason.secretUnavailable);
    });

    test(
      'ACS, paciente e coordenador sem UBS ⇒ AlertPermissionException e '
      'denied, sem ler a cadeia',
      () async {
        final r = _Reader(cadeia.entries);
        for (final u in [
          _u('acs-1', UserRole.acs, ma: 'ma-1'),
          _u('pac-1', UserRole.patient, ma: 'ma-1'),
          _u('coord-sem-ubs', UserRole.coordinator),
        ]) {
          await expectLater(
            servico(r).verify(u),
            throwsA(isA<AlertPermissionException>()),
          );
        }
        expect(r.lotes, isEmpty);
        expect(audit.events.map((e) => e.result), ['denied', 'denied', 'denied']);
        expect(
          audit.events.map((e) => e.resourceType).toSet(),
          {'admin_audit_chain'},
        );
      },
    );
  });

  group('auditoria antes de verificar', () {
    test('grava read/admin_audit_chain/success ANTES de ler', () async {
      await servico(_Reader(cadeia.entries)).verify(admin);
      expect(_ordem.first, 'audit:read:admin_audit_chain:success');
      expect(_ordem.skip(1), everyElement('reader:readBatch'));
    });

    test('trilha fora do ar ⇒ a exceção sobe e nada é lido', () async {
      audit.falhar = true;
      final r = _Reader(cadeia.entries);
      await expectLater(servico(r).verify(admin), throwsA(isA<StateError>()));
      expect(r.lotes, isEmpty);
    });

    test('resposta do cache também é auditada', () async {
      final r = _Reader(cadeia.entries);
      await servico(r).verify(admin);
      await servico(r).verify(admin);
      expect(audit.events.where((e) => e.result == 'success'), hasLength(2));
    });
  });

  group('single-flight e cache (60 s)', () {
    test('duas chamadas concorrentes ⇒ um só readBatch inicial', () async {
      final r = _Reader(cadeia.entries)..portao = Completer<void>();
      final a = servico(r).verify(admin);
      final b = servico(r).verify(coordB);
      // Deixa as duas chegarem ao verificador antes de liberar a leitura.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      r.portao!.complete();
      final (sa, sb) = await (a, b).wait;
      expect(r.lotes, [r.lotes.first], reason: 'um único lote: 5 linhas');
      expect(sa.state, AuditIntegrityState.verified);
      expect(sb.state, AuditIntegrityState.verified);
      expect(sa.verifiedAt, sb.verifiedAt);
    });

    test('segunda chamada em 60 s não relê; depois de 60 s, relê', () async {
      final r = _Reader(cadeia.entries);
      final primeira = await servico(r).verify(admin);
      expect(r.lotes, hasLength(1));

      agora = t0.add(const Duration(seconds: 59));
      final segunda = await servico(r).verify(admin);
      expect(r.lotes, hasLength(1));
      expect(segunda.verifiedAt, primeira.verifiedAt);

      agora = t0.add(const Duration(seconds: 61));
      final terceira = await servico(r).verify(admin);
      expect(r.lotes, hasLength(2));
      expect(terceira.verifiedAt, agora);
    });

    test('o cache vale para todos e a projeção continua por papel', () async {
      store.donoDa[3] = 'ubs-b';
      final r = _Reader([
        ...cadeia.entries.take(2),
        AuditChainEntry(
          fields: _copia(cadeia.entries[2].fields, result: 'x'),
          entryHash: cadeia.entries[2].entryHash,
        ),
        ...cadeia.entries.skip(3),
      ]);
      final doAdmin = await servico(r).verify(admin);
      final doCoord = await servico(r).verify(coordA);
      expect(r.lotes, hasLength(1));
      expect(doAdmin.firstBrokenSequence, 3);
      expect(doCoord.firstBrokenSequence, isNull);
      expect(doCoord.brokenInScope, isFalse);
    });

    test('relógio voltando no tempo não estende o cache para sempre', () async {
      final r = _Reader(cadeia.entries);
      await servico(r).verify(admin);
      agora = t0.subtract(const Duration(minutes: 5));
      await servico(r).verify(admin);
      expect(r.lotes, hasLength(2));
    });
  });

  test('a resposta serializada não tem hash nem segredo', () async {
    final s = await servico(_Reader(cadeia.entries)).verify(admin);
    final texto = jsonEncode(s.toJson());
    expect(texto, isNot(contains(_segredo)));
    expect(texto, isNot(contains('Hash')));
    for (final e in cadeia.entries) {
      expect(texto, isNot(contains(e.entryHash)));
    }
  });
}
