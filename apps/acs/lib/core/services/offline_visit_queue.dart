enum SyncOutcomeKind {
  synced,
  conflict,
  empty,
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
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String patientName;
  final String risk;
  final String status;
  final DateTime createdAt;

  OfflineVisitRecord copyWith({
    String? patientName,
    String? risk,
    String? status,
    DateTime? createdAt,
  }) {
    return OfflineVisitRecord(
      patientName: patientName ?? this.patientName,
      risk: risk ?? this.risk,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class OfflineVisitQueue {
  OfflineVisitQueue();

  final List<OfflineVisitRecord> _pending = <OfflineVisitRecord>[];
  final List<OfflineVisitRecord> _synced = <OfflineVisitRecord>[];
  final List<OfflineVisitRecord> _conflicts = <OfflineVisitRecord>[];

  int get pendingCount => _pending.length;
  int get syncedCount => _synced.length;
  int get conflictCount => _conflicts.length;

  List<OfflineVisitRecord> get pendingVisits => List.unmodifiable(_pending);
  List<OfflineVisitRecord> get syncedVisits => List.unmodifiable(_synced);
  List<OfflineVisitRecord> get conflictVisits => List.unmodifiable(_conflicts);

  Future<void> add(OfflineVisitRecord record) async {
    _pending.add(record);
  }

  Future<SyncOutcome> sync({bool forceConflict = false}) async {
    if (_pending.isEmpty) {
      return const SyncOutcome(kind: SyncOutcomeKind.empty, processed: 0);
    }

    final batch = List<OfflineVisitRecord>.from(_pending);
    _pending.clear();

    if (forceConflict && batch.isNotEmpty) {
      final conflicted = batch.first.copyWith(status: 'CONFLITO');
      _conflicts.add(conflicted);
      _pending.add(conflicted);
      return SyncOutcome(kind: SyncOutcomeKind.conflict, processed: 1);
    }

    for (final visit in batch) {
      _synced.add(
        visit.copyWith(
          status: 'SINCRONIZADO',
        ),
      );
    }

    return SyncOutcome(kind: SyncOutcomeKind.synced, processed: batch.length);
  }
}
