import 'dart:math';

enum SyncOutcomeKind {
  synced,
  conflict,
  empty,
  error,
}

class SyncOutcome {
  const SyncOutcome({
    required this.kind,
    required this.processed,
  });

  final SyncOutcomeKind kind;
  final int processed;
}

class OfflineVisitRecord {
  OfflineVisitRecord({
    required this.patientName,
    required this.risk,
    required this.status,
    this.outcome = '',
    String? localId,
    DateTime? createdAt,
    this.version = 1,
  })  : localId = localId ?? _newLocalId(),
        createdAt = createdAt ?? DateTime.now();

  final String patientName;
  final String risk;
  final String status;
  final String outcome;

  /// Identificador gerado no dispositivo.
  ///
  /// É a chave de deduplicação da sincronização: a tabela `visits` do servidor
  /// tem índice único em `localId`, então reenviar a mesma visita depois de uma
  /// falha de rede atualiza a linha em vez de criar uma segunda.
  final String localId;

  final DateTime createdAt;

  /// Versão conhecida no servidor, para detecção de conflito.
  final int version;

  OfflineVisitRecord copyWith({
    String? patientName,
    String? risk,
    String? status,
    String? outcome,
    String? localId,
    DateTime? createdAt,
    int? version,
  }) {
    return OfflineVisitRecord(
      patientName: patientName ?? this.patientName,
      risk: risk ?? this.risk,
      status: status ?? this.status,
      outcome: outcome ?? this.outcome,
      localId: localId ?? this.localId,
      createdAt: createdAt ?? this.createdAt,
      version: version ?? this.version,
    );
  }

  static String _newLocalId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

/// Resultado da sincronização de uma visita, do ponto de vista do servidor.
class VisitSyncOutcome {
  const VisitSyncOutcome({
    required this.localId,
    required this.status,
    this.serverVersion,
  });

  final String localId;

  /// `synced`, `conflict` ou `error`, como devolvido por `visits.sync`.
  final String status;

  final int? serverVersion;
}

/// Quem leva as visitas pendentes ao servidor.
///
/// Abstração no mesmo espírito de `AlertPublisher`/`AlertStore` no backend:
/// mantém a fila testável sem rede.
abstract class VisitSynchronizer {
  Future<List<VisitSyncOutcome>> push(List<OfflineVisitRecord> visits);
}

/// Onde as visitas ficam enquanto não sincronizam.
abstract class VisitStore {
  Future<List<OfflineVisitRecord>> load();

  Future<void> save(List<OfflineVisitRecord> visits);
}

/// Armazenamento em memória. Padrão quando nenhum é fornecido.
class InMemoryVisitStore implements VisitStore {
  List<OfflineVisitRecord> _visits = <OfflineVisitRecord>[];

  @override
  Future<List<OfflineVisitRecord>> load() async => List.of(_visits);

  @override
  Future<void> save(List<OfflineVisitRecord> visits) async {
    _visits = List.of(visits);
  }
}

/// Fila offline-first de visitas domiciliares.
///
/// Preserva a semântica da `SyncFsm` do backend
/// (`idle → localWrite → queued → syncing → {synced|conflict|error}`): uma
/// visita em conflito **volta para a fila** em vez de ser descartada, e uma
/// falha de rede não perde o lote.
class OfflineVisitQueue {
  OfflineVisitQueue({VisitStore? store, this.synchronizer})
      : _store = store ?? InMemoryVisitStore();

  final VisitStore _store;

  /// `null` mantém o comportamento local: a fila enfileira, mas não envia.
  final VisitSynchronizer? synchronizer;

  final List<OfflineVisitRecord> _pending = <OfflineVisitRecord>[];
  final List<OfflineVisitRecord> _synced = <OfflineVisitRecord>[];
  final List<OfflineVisitRecord> _conflicts = <OfflineVisitRecord>[];

  bool _restored = false;

  int get pendingCount => _pending.length;
  int get syncedCount => _synced.length;
  int get conflictCount => _conflicts.length;

  List<OfflineVisitRecord> get pendingVisits => List.unmodifiable(_pending);
  List<OfflineVisitRecord> get syncedVisits => List.unmodifiable(_synced);
  List<OfflineVisitRecord> get conflictVisits => List.unmodifiable(_conflicts);

  /// Recarrega o que ficou gravado de execuções anteriores.
  ///
  /// Sem isso, fechar o app perde a fila — o oposto de offline-first.
  Future<void> restore() async {
    if (_restored) return;
    _restored = true;
    final stored = await _store.load();
    _pending
      ..clear()
      ..addAll(stored);
  }

  Future<void> add(OfflineVisitRecord record) async {
    _pending.add(record);
    await _store.save(_pending);
  }

  Future<SyncOutcome> sync({bool forceConflict = false}) async {
    if (_pending.isEmpty) {
      return const SyncOutcome(kind: SyncOutcomeKind.empty, processed: 0);
    }

    final batch = List<OfflineVisitRecord>.from(_pending);

    // Gancho de teste preservado do comportamento anterior.
    if (forceConflict) {
      return _applyOutcomes(batch, [
        VisitSyncOutcome(localId: batch.first.localId, status: 'conflict'),
        for (final visit in batch.skip(1))
          VisitSyncOutcome(localId: visit.localId, status: 'synced'),
      ]);
    }

    final sender = synchronizer;
    if (sender == null) {
      // Sem sincronizador configurado a fila permanece local; nada é
      // declarado sincronizado, porque nada saiu do dispositivo.
      return SyncOutcome(kind: SyncOutcomeKind.error, processed: batch.length);
    }

    final List<VisitSyncOutcome> outcomes;
    try {
      outcomes = await sender.push(batch);
    } catch (_) {
      // O lote continua pendente: perder a visita por falha de rede seria
      // exatamente o que a fila existe para evitar.
      return SyncOutcome(kind: SyncOutcomeKind.error, processed: batch.length);
    }

    return _applyOutcomes(batch, outcomes);
  }

  Future<SyncOutcome> _applyOutcomes(
    List<OfflineVisitRecord> batch,
    List<VisitSyncOutcome> outcomes,
  ) async {
    final byLocalId = {for (final outcome in outcomes) outcome.localId: outcome};

    var conflicts = 0;
    var synced = 0;
    final stillPending = <OfflineVisitRecord>[];

    for (final visit in batch) {
      final outcome = byLocalId[visit.localId];
      switch (outcome?.status) {
        case 'synced':
          _synced.add(visit.copyWith(
            status: 'SINCRONIZADO',
            version: outcome?.serverVersion ?? visit.version,
          ));
          synced++;
        case 'conflict':
          final conflicted = visit.copyWith(status: 'CONFLITO');
          _conflicts.add(conflicted);
          // Volta para a fila: conflito precisa de resolução, não de descarte.
          stillPending.add(conflicted);
          conflicts++;
        default:
          // Sem resposta para esta visita — mantém pendente e tenta de novo.
          stillPending.add(visit);
      }
    }

    _pending
      ..clear()
      ..addAll(stillPending);
    await _store.save(_pending);

    if (conflicts > 0) {
      return SyncOutcome(kind: SyncOutcomeKind.conflict, processed: conflicts);
    }
    return SyncOutcome(kind: SyncOutcomeKind.synced, processed: synced);
  }
}
