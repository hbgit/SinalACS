import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';
import 'package:sinalacs_acs/core/telemetry/network_probe.dart';
import 'package:sinalacs_acs/core/telemetry/telemetry_recorder.dart';
import 'package:sinalacs_acs/core/telemetry/telemetry_store.dart';

import 'support/fakes.dart';

/// M2.4 / RNF02: "100 registros offline sincronizam em < 5s após rede" e
/// sincronização > 99,5%. Aqui a parte determinística: nada se perde, nada
/// duplica, e a fila sobrevive a um reinício. O tempo contra o servidor de
/// verdade é medido no dispositivo (`integration_test/full_journey_e2e.dart`).
void main() {
  OfflineVisitRecord visita(int n) => OfflineVisitRecord(
        patientId: syntheticPatientId(n),
        risk: 'yellow',
        status: 'PENDENTE',
        localId: 'burst-$n',
        createdAt: DateTime.utc(2026, 10, 2, 8).add(Duration(minutes: n)),
      );

  test('100 visitas enfileiradas, reiniciadas e sincronizadas: nenhuma se perde', () async {
    final disco = InMemoryVisitStore();
    final antes = OfflineVisitQueue(store: disco);
    for (var n = 0; n < 100; n++) {
      await antes.add(visita(n));
    }
    expect(antes.pendingCount, 100);

    // Reinício do app: outra fila sobre o mesmo "disco".
    final envio = FakeVisitSynchronizer();
    final depois = OfflineVisitQueue(store: disco, synchronizer: envio);
    await depois.restore();
    expect(depois.pendingCount, 100, reason: 'o que estava no disco volta inteiro');

    final resultado = await depois.sync();

    expect(resultado.kind, SyncOutcomeKind.synced);
    expect(depois.pendingCount, 0);
    expect(depois.syncedCount, 100);
    expect(envio.batches, hasLength(1), reason: 'um lote só: uma ida e volta ao servidor');
    final enviados = envio.batches.single.map((v) => v.localId).toSet();
    expect(enviados, hasLength(100), reason: 'nenhum localId repetido (dedupe do servidor)');
  });

  test('uma recusada e um conflito no meio não seguram as demais', () async {
    final envio = FakeVisitSynchronizer(
      statusFor: (v) => switch (v.localId) {
        'burst-40' => 'rejected',
        'burst-70' => 'conflict',
        _ => 'synced',
      },
      messageFor: (v) => v.localId == 'burst-40' ? 'paciente de outra microárea' : null,
    );
    final fila = OfflineVisitQueue(synchronizer: envio);
    for (var n = 0; n < 100; n++) {
      await fila.add(visita(n));
    }

    await fila.sync();

    expect(fila.syncedCount, 98);
    expect(fila.rejectedCount, 1, reason: 'a recusada fica visível no aparelho até o ACS descartar');
    expect(fila.rejectedVisits.single.localId, 'burst-40');
    expect(fila.rejectedVisits.single.rejectionReason, 'paciente de outra microárea');
    expect(fila.conflictCount, 1, reason: 'o conflito fica registrado');
    // Conflito sai da retentativa e espera a decisão do ACS (#79, D3); a
    // recusada também sai e fica só visível. Nenhuma das duas se perde.
    expect(fila.pendingCount, 0);
    expect(fila.conflictVisits.single.localId, 'burst-70');
    expect(fila.conflictVisits.single.inConflict, isTrue);
  });

  test('sem rede, as 100 continuam pendentes e a próxima tentativa as leva', () async {
    final envio = FakeVisitSynchronizer(throwOnPush: true);
    final fila = OfflineVisitQueue(synchronizer: envio);
    for (var n = 0; n < 100; n++) {
      await fila.add(visita(n));
    }

    final falha = await fila.sync();
    expect(falha.kind, SyncOutcomeKind.error);
    expect(fila.pendingCount, 100, reason: 'falha de rede não perde o lote');

    envio.throwOnPush = false;
    await fila.sync();
    expect(fila.pendingCount, 0);
    expect(fila.syncedCount, 100);
  });

  test('100 visitas com telemetria ligada: nenhuma se perde e 100 visit_registered + 1 attempt + 1 result',
      () async {
    // A fila de telemetria também é "disco": sobrevive ao reinício, como a
    // das visitas.
    final telemetria = InMemoryTelemetryStore();
    TelemetryRecorder gravador() => TelemetryRecorder(
          store: telemetria,
          owner: 'acs-burst',
          probe: () async => NetworkKind.none,
        );
    final disco = InMemoryVisitStore();
    final antes = OfflineVisitQueue(store: disco, telemetry: gravador());
    for (var n = 0; n < 100; n++) {
      await antes.add(visita(n));
    }

    final envio = FakeVisitSynchronizer();
    final depois = OfflineVisitQueue(store: disco, synchronizer: envio, telemetry: gravador());
    await depois.restore();
    final resultado = await depois.sync();

    expect(resultado.kind, SyncOutcomeKind.synced);
    expect(depois.pendingCount, 0);
    expect(depois.syncedCount, 100);
    expect(envio.batches.single.map((v) => v.localId).toSet(), hasLength(100));

    final eventos = await telemetria.oldestForOwner('acs-burst', limit: 1000);
    int contar(String nome) => eventos.where((e) => e.name == nome).length;
    expect(contar('visit_registered'), 100);
    expect(contar('sync_attempt'), 1);
    expect(contar('sync_result'), 1);
    final result = eventos.singleWhere((e) => e.name == 'sync_result');
    expect(result.payload['success_count'], 100);
    expect(result.payload['failure_count'], 0);
  });
}
