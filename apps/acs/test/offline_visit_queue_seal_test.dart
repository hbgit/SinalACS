import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';

import 'support/fakes.dart';

/// Envio que só responde quando o teste solta o portão (rede lenta).
class _SlowSynchronizer implements VisitSynchronizer {
  final Completer<void> gate = Completer<void>();
  String status = 'synced';

  @override
  Future<List<VisitSyncOutcome>> push(List<OfflineVisitRecord> visits) async {
    await gate.future;
    return [
      for (final visit in visits)
        VisitSyncOutcome(localId: visit.localId, status: status, serverVersion: visit.version + 1, message: 'recusada'),
    ];
  }
}

/// Fila selada pela limpeza remota (#81): nada do que ela tem em RAM volta ao
/// disco, nem pelo fim de um envio que já estava em voo. Ids sintéticos.
void main() {
  OfflineVisitRecord visita(String localId) =>
      OfflineVisitRecord(localId: localId, patientId: seedPatientId, risk: 'green', status: 'PENDENTE');

  for (final status in ['error', 'rejected', 'synced']) {
    test('envio em voo que termina ($status) depois do seal não grava nada', () async {
      final store = InMemoryVisitStore();
      final sender = _SlowSynchronizer()..status = status;
      final queue = OfflineVisitQueue(store: store, synchronizer: sender);
      await queue.add(visita('v-1'));
      await queue.add(visita('v-2'));
      final emVoo = queue.sync();

      queue.seal();
      // A limpeza apaga o banco enquanto o envio está em voo.
      await store.save(const []);
      sender.gate.complete();
      await emVoo;

      expect(await store.load(), isEmpty);
      expect(queue.isSealed, isTrue);
    });
  }

  test('fila selada recusa registrar, resolver e enviar', () async {
    final store = InMemoryVisitStore();
    final sender = FakeVisitSynchronizer();
    final queue = OfflineVisitQueue(store: store, synchronizer: sender);
    await queue.add(visita('v-1'));
    queue.seal();
    await store.save(const []);

    await expectLater(queue.add(visita('v-2')), throwsStateError);
    await queue.discardRejected();
    await queue.resolveKeepServer('v-1');
    final keepLocal = await queue.resolveKeepLocal('v-1');
    final envio = await queue.sync();

    expect(keepLocal.kind, SyncOutcomeKind.error);
    expect(envio.processed, 0);
    expect(sender.batches, isEmpty, reason: 'nada sai de uma fila selada');
    expect(await store.load(), isEmpty);
  });
}
