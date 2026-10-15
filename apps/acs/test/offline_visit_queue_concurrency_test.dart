import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';

import 'support/fakes.dart' show seedPatientId;

/// Visita registrada enquanto um `sync()` está em voo, e `sync()` concorrentes.
/// Ids e paciente sintéticos.
void main() {
  OfflineVisitRecord visita(String localId) =>
      OfflineVisitRecord(localId: localId, patientId: seedPatientId, risk: 'red', status: 'PENDENTE');

  for (final (nome, criarStore) in <(String, VisitStore Function())>[
    ('InMemoryVisitStore', InMemoryVisitStore.new),
    ('visão de um dono (InMemoryVisitStorage)', () => InMemoryVisitStorage().forOwner('acs-a')),
    ('store com E/S assíncrona', _StoreLento.new),
  ]) {
    test('visita adicionada DURANTE o envio continua pendente e no disco ($nome)', () async {
      final store = criarStore();
      final envio = _SincronizadorPreso();
      final fila = OfflineVisitQueue(store: store, synchronizer: envio);
      await fila.restore();
      await fila.add(visita('x'));

      final emVoo = fila.sync();
      await envio.chegou.future;
      expect(fila.isSyncing, isTrue);
      await fila.add(visita('y')); // registrada em campo com o lote no servidor
      envio.solta.complete();
      await emVoo;

      expect(fila.isSyncing, isFalse);
      expect(fila.pendingVisits.map((v) => v.localId), ['y'], reason: 'x subiu; y não pode sumir da memória');
      expect((await store.load()).map((v) => v.localId), ['y'], reason: 'nem do disco');

      // E a próxima sincronização a envia.
      final segunda = _SincronizadorPreso()..solta.complete();
      final outra = OfflineVisitQueue(store: store, synchronizer: segunda);
      await outra.restore();
      await outra.sync();
      expect(segunda.lotes.single.map((v) => v.localId), ['y']);
    });
  }

  test('dois sync() concorrentes enviam o lote UMA vez e devolvem o mesmo resultado', () async {
    final envio = _SincronizadorPreso();
    final fila = OfflineVisitQueue(store: InMemoryVisitStore(), synchronizer: envio);
    await fila.add(visita('x'));

    final primeiro = fila.sync();
    final segundo = fila.sync();
    await envio.chegou.future;
    envio.solta.complete();
    final resultados = await Future.wait([primeiro, segundo]);

    expect(envio.lotes, hasLength(1));
    expect(resultados.map((r) => r.kind), everyElement(SyncOutcomeKind.synced));
    expect(fila.pendingCount, 0);
    expect(fila.syncedCount, 1, reason: 'sem contar duas vezes');
  });
}

/// Sincronizador que avisa quando o lote chegou e só responde quando liberado.
class _SincronizadorPreso implements VisitSynchronizer {
  final Completer<void> chegou = Completer<void>();
  final Completer<void> solta = Completer<void>();
  final List<List<OfflineVisitRecord>> lotes = <List<OfflineVisitRecord>>[];

  @override
  Future<List<VisitSyncOutcome>> push(List<OfflineVisitRecord> visits) async {
    lotes.add(List.of(visits));
    if (!chegou.isCompleted) chegou.complete();
    await solta.future;
    return [for (final v in visits) VisitSyncOutcome(localId: v.localId, status: 'synced', serverVersion: v.version + 1)];
  }
}

/// Store cujas leituras e gravações levam um tempo (como o SQLCipher).
class _StoreLento implements VisitStore {
  List<OfflineVisitRecord> _linhas = <OfflineVisitRecord>[];

  @override
  Future<List<OfflineVisitRecord>> load() async {
    await Future<void>.delayed(const Duration(milliseconds: 2));
    return List.of(_linhas);
  }

  @override
  Future<void> save(List<OfflineVisitRecord> visits) async {
    final copia = List.of(visits);
    await Future<void>.delayed(const Duration(milliseconds: 2));
    _linhas = copia;
  }
}
