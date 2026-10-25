import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';
import 'package:sinalacs_acs/core/telemetry/network_probe.dart';
import 'package:sinalacs_acs/core/telemetry/telemetry_event.dart';
import 'package:sinalacs_acs/core/telemetry/telemetry_recorder.dart';
import 'package:sinalacs_acs/core/telemetry/telemetry_store.dart';

import 'support/fakes.dart';

const _owner = 'acs-001';
const _alert = '22222222-2222-4222-8222-222222222222';

/// Sincronizador que, dentro do `push`, olha o que já está na fila de
/// telemetria: prova que o `sync_attempt` chegou ao "disco" antes do envio.
/// Com [portao], segura o envio até o teste liberar (envio em voo).
class _EspiaoDeTelemetria implements VisitSynchronizer {
  _EspiaoDeTelemetria(this.telemetria);

  final TelemetryStore telemetria;
  final List<int> attemptsNoPush = <int>[];
  Completer<void>? portao;
  int chamadas = 0;

  @override
  Future<List<VisitSyncOutcome>> push(List<OfflineVisitRecord> visits) async {
    chamadas++;
    final eventos = await telemetria.oldestForOwner(_owner, limit: 1000);
    attemptsNoPush.add(eventos.where((e) => e.name == 'sync_attempt').length);
    await portao?.future;
    return [
      for (final v in visits)
        VisitSyncOutcome(localId: v.localId, status: 'synced', serverVersion: v.version + 1),
    ];
  }
}

/// Store de telemetria cujo `append` espera [portao] (ou nunca completa, se
/// [portao] nunca for completado). [falha] faz o `append` lançar.
class _StoreTravado implements TelemetryStore {
  final Completer<void> portao = Completer<void>();
  final InMemoryTelemetryStore _interno = InMemoryTelemetryStore();
  int appends = 0;

  @override
  Future<void> append(TelemetryEventRecord e) async {
    appends++;
    await portao.future;
    await _interno.append(e);
  }

  @override
  Future<List<TelemetryEventRecord>> oldestForOwner(String owner, {required int limit}) =>
      _interno.oldestForOwner(owner, limit: limit);
  @override
  Future<void> deleteByIds(Iterable<String> ids) => _interno.deleteByIds(ids);
  @override
  Future<int> countForOwner(String owner) => _interno.countForOwner(owner);
}

/// Gravador que lança em `visitRegistered` — o contrato diz que não lança,
/// mas a fila não pode depender disso para não pedir o registro de novo.
class _GravadorQueLanca extends TelemetryRecorder {
  _GravadorQueLanca() : super(store: InMemoryTelemetryStore(), owner: _owner, probe: () async => NetworkKind.wifi);

  @override
  Future<void> visitRegistered({required OfflineVisitRecord visit, String? alertId}) async =>
      throw StateError('telemetria quebrada');
}

/// Envio que espera o portão e falha na rede.
class _EnvioQueFalha implements VisitSynchronizer {
  _EnvioQueFalha(this.portao);

  final Completer<void> portao;

  @override
  Future<List<VisitSyncOutcome>> push(List<OfflineVisitRecord> visits) async {
    await portao.future;
    throw StateError('sem rede');
  }
}

/// Disco de visitas cujo `save` espera [portao].
class _DiscoTravado extends InMemoryVisitStore {
  final Completer<void> portao = Completer<void>();

  @override
  Future<void> save(List<OfflineVisitRecord> visits) async {
    await portao.future;
    await super.save(visits);
  }
}

OfflineVisitRecord _visita(int n) => OfflineVisitRecord(
      patientId: syntheticPatientId(n),
      risk: 'yellow',
      status: 'PENDENTE',
      localId: 'tel-$n',
      createdAt: DateTime.utc(2026, 10, 25, 8).add(Duration(minutes: n)),
    );

TelemetryRecorder _recorder(TelemetryStore store) => TelemetryRecorder(
      store: store,
      owner: _owner,
      probe: () async => NetworkKind.wifi,
      clock: () => DateTime.utc(2026, 10, 25, 12),
    );

Future<List<TelemetryEventRecord>> _eventos(TelemetryStore s, [String? nome]) async {
  final todos = await s.oldestForOwner(_owner, limit: 1000);
  return nome == null ? todos : todos.where((e) => e.name == nome).toList();
}

void main() {
  test('attempt persiste antes do push', () async {
    final telemetria = InMemoryTelemetryStore();
    final envio = _EspiaoDeTelemetria(telemetria);
    final fila = OfflineVisitQueue(synchronizer: envio, telemetry: _recorder(telemetria));
    await fila.add(_visita(1));
    await fila.add(_visita(2));

    await fila.sync();

    expect(envio.attemptsNoPush, [1], reason: 'o sync_attempt já estava gravado dentro do push');
    final attempt = (await _eventos(telemetria, 'sync_attempt')).single;
    expect(attempt.payload['records_count'], 2);
    final result = (await _eventos(telemetria, 'sync_result')).single;
    expect(result.payload['attempt_event_id'], attempt.eventId);
    expect(result.payload['outcome'], 'synced');
    expect(result.payload['success_count'], 2);
    expect(result.payload['transport_error'], isFalse);
  });

  test('resultado com contagens synced/erro/conflito/recusa', () async {
    final telemetria = InMemoryTelemetryStore();
    final envio = FakeVisitSynchronizer(
      statusFor: (v) => switch (v.localId) {
        'tel-1' => 'error',
        'tel-2' => 'conflict',
        'tel-3' => 'rejected',
        _ => 'synced',
      },
    );
    final fila = OfflineVisitQueue(synchronizer: envio, telemetry: _recorder(telemetria));
    for (var n = 0; n < 6; n++) {
      await fila.add(_visita(n));
    }

    final resultado = await fila.sync();

    expect(resultado.kind, SyncOutcomeKind.rejected, reason: 'a precedência pública não muda');
    final result = (await _eventos(telemetria, 'sync_result')).single;
    expect(result.payload['success_count'], 3);
    expect(result.payload['failure_count'], 1);
    expect(result.payload['conflict_count'], 1);
    expect(result.payload['rejected_count'], 1);
    expect(result.payload['outcome'], 'rejected');
    expect(result.payload['transport_error'], isFalse);
    expect(result.payload['duration_ms'], isA<int>());
    expect(fila.pendingCount, 1);
    expect(fila.conflictCount, 1);
    expect(fila.rejectedCount, 1);
  });

  test('falha de rede emite transport_error e mantém o lote', () async {
    final telemetria = InMemoryTelemetryStore();
    final envio = FakeVisitSynchronizer(throwOnPush: true);
    final fila = OfflineVisitQueue(synchronizer: envio, telemetry: _recorder(telemetria));
    for (var n = 0; n < 3; n++) {
      await fila.add(_visita(n));
    }

    final resultado = await fila.sync();

    expect(resultado.kind, SyncOutcomeKind.error);
    expect(fila.pendingCount, 3, reason: 'falha de rede não perde o lote');
    final attempt = (await _eventos(telemetria, 'sync_attempt')).single;
    final result = (await _eventos(telemetria, 'sync_result')).single;
    expect(result.payload, {
      'attempt_event_id': attempt.eventId,
      'success_count': 0,
      'failure_count': 3,
      'conflict_count': 0,
      'rejected_count': 0,
      'outcome': 'error',
      'transport_error': true,
      'duration_ms': result.payload['duration_ms'],
    });
  });

  test('sync em voo chamado duas vezes emite um attempt', () async {
    final telemetria = InMemoryTelemetryStore();
    final envio = _EspiaoDeTelemetria(telemetria)..portao = Completer<void>();
    final fila = OfflineVisitQueue(synchronizer: envio, telemetry: _recorder(telemetria));
    await fila.add(_visita(1));

    final primeiro = fila.sync();
    final segundo = fila.sync();
    await pumpEventQueue();
    envio.portao!.complete();
    await Future.wait([primeiro, segundo]);

    expect(envio.chamadas, 1);
    expect(await _eventos(telemetria, 'sync_attempt'), hasLength(1));
    expect(await _eventos(telemetria, 'sync_result'), hasLength(1));
  });

  test('lote vazio não emite', () async {
    final telemetria = InMemoryTelemetryStore();
    final fila = OfflineVisitQueue(
      synchronizer: FakeVisitSynchronizer(),
      telemetry: _recorder(telemetria),
    );

    final resultado = await fila.sync();

    expect(resultado.kind, SyncOutcomeKind.empty);
    expect(await _eventos(telemetria), isEmpty);
  });

  test('sem sincronizador não emite attempt nem result', () async {
    final telemetria = InMemoryTelemetryStore();
    final fila = OfflineVisitQueue(telemetry: _recorder(telemetria));
    await fila.add(_visita(1));

    await fila.sync();

    expect(await _eventos(telemetria, 'sync_attempt'), isEmpty);
    expect(await _eventos(telemetria, 'sync_result'), isEmpty);
  });

  test('add com alertId emite visit_registered de alerta', () async {
    final telemetria = InMemoryTelemetryStore();
    final disco = InMemoryVisitStore();
    final fila = OfflineVisitQueue(store: disco, telemetry: _recorder(telemetria));

    await fila.add(_visita(1), alertId: _alert);
    await fila.add(_visita(2));

    final registros = await _eventos(telemetria, 'visit_registered');
    expect(registros, hasLength(2));
    expect(registros[0].payload['visit_type'], 'alert');
    expect(registros[0].payload['alert_id'], _alert);
    expect(registros[0].payload['local_id'], 'tel-1');
    expect(registros[1].payload['visit_type'], 'routine');
    expect(registros[1].payload.containsKey('alert_id'), isFalse);
    expect(await disco.load(), hasLength(2), reason: 'a visita foi gravada');
  });

  test('fila selada: add lança e não emite', () async {
    final telemetria = InMemoryTelemetryStore();
    final fila = OfflineVisitQueue(telemetry: _recorder(telemetria))..seal();

    await expectLater(fila.add(_visita(1)), throwsStateError);
    expect(await _eventos(telemetria), isEmpty);
  });

  test('resolveKeepServer e resolveKeepLocal não emitem', () async {
    final telemetria = InMemoryTelemetryStore();
    final fila = OfflineVisitQueue(
      synchronizer: FakeVisitSynchronizer(statusFor: (_) => 'conflict'),
      conflictResolver: FakeVisitConflictResolver(),
      telemetry: _recorder(telemetria),
    );
    await fila.add(_visita(1));
    await fila.add(_visita(2));
    await fila.sync();
    final antes = (await _eventos(telemetria)).length;

    await fila.resolveKeepLocal('tel-1');
    await fila.resolveKeepServer('tel-2');

    expect(await _eventos(telemetria), hasLength(antes));
  });

  test('selo no meio do envio: nada volta ao disco das visitas', () async {
    final telemetria = InMemoryTelemetryStore();
    final disco = InMemoryVisitStore();
    final envio = _EspiaoDeTelemetria(telemetria)..portao = Completer<void>();
    final fila = OfflineVisitQueue(store: disco, synchronizer: envio, telemetry: _recorder(telemetria));
    await fila.add(_visita(1));
    final gravadoAntes = await disco.load();

    final envioEmVoo = fila.sync();
    await pumpEventQueue();
    fila.seal();
    envio.portao!.complete();
    await envioEmVoo;

    expect((await disco.load()).map((v) => v.localId), gravadoAntes.map((v) => v.localId),
        reason: 'a fila selada não grava o fim do envio');
    // Decisão do controlador (Task 14): selada, a fila não grava mais nem a
    // telemetria — o banco pode já ter sido destruído (#81). A tentativa fica
    // órfã, contada como interrompida.
    expect(await _eventos(telemetria, 'sync_result'), isEmpty);
  });

  test('selo no meio de um envio que falha na rede: não há result', () async {
    final telemetria = InMemoryTelemetryStore();
    final portao = Completer<void>();
    final envio = _EnvioQueFalha(portao);
    final fila = OfflineVisitQueue(synchronizer: envio, telemetry: _recorder(telemetria));
    await fila.add(_visita(1));

    final envioEmVoo = fila.sync();
    await pumpEventQueue();
    fila.seal();
    portao.complete();
    await envioEmVoo;

    expect(await _eventos(telemetria, 'sync_attempt'), hasLength(1));
    expect(await _eventos(telemetria, 'sync_result'), isEmpty);
  });

  test('selo durante a gravação da visita: não emite visit_registered', () async {
    final telemetria = InMemoryTelemetryStore();
    final disco = _DiscoTravado();
    final fila = OfflineVisitQueue(store: disco, telemetry: _recorder(telemetria));

    final registro = fila.add(_visita(1));
    await pumpEventQueue();
    fila.seal();
    disco.portao.complete();
    await registro;

    expect(await _eventos(telemetria, 'visit_registered'), isEmpty);
  });

  test('selo durante a gravação do attempt: o lote não sai e não há result', () async {
    final telemetria = _StoreTravado();
    final envio = FakeVisitSynchronizer();
    final fila = OfflineVisitQueue(synchronizer: envio, telemetry: _recorder(telemetria));
    fila.add(_visita(1)).ignore(); // `visit_registered` também espera o portão
    await pumpEventQueue();

    final envioEmVoo = fila.sync();
    await pumpEventQueue();
    fila.seal();
    telemetria.portao.complete();
    final resultado = await envioEmVoo;

    expect(envio.batches, isEmpty, reason: 'fila selada não envia (#81)');
    expect(resultado.kind, SyncOutcomeKind.error);
    expect(await _eventos(telemetria, 'sync_attempt'), hasLength(1));
    expect(await _eventos(telemetria, 'sync_result'), isEmpty);
  });

  test('sonda de rede que nunca responde não prende add nem sync', () async {
    final telemetria = InMemoryTelemetryStore();
    final envio = FakeVisitSynchronizer();
    final fila = OfflineVisitQueue(
      synchronizer: envio,
      telemetry: TelemetryRecorder(
        store: telemetria,
        owner: _owner,
        probe: () => Completer<NetworkKind>().future,
        stepTimeout: const Duration(milliseconds: 20),
      ),
    );

    await fila.add(_visita(1));
    final resultado = await fila.sync();

    expect(resultado.kind, SyncOutcomeKind.synced);
    expect(fila.syncedCount, 1);
    final eventos = await _eventos(telemetria);
    expect(eventos.map((e) => e.name), ['visit_registered', 'sync_attempt', 'sync_result']);
    expect(eventos.first.payload['network_type'], 'unknown');
  });

  test('gravação de telemetria que nunca completa não prende add nem sync', () async {
    final telemetria = _StoreTravado(); // portão nunca liberado
    final disco = InMemoryVisitStore();
    final envio = FakeVisitSynchronizer();
    final fila = OfflineVisitQueue(
      store: disco,
      synchronizer: envio,
      telemetry: TelemetryRecorder(
        store: telemetria,
        owner: _owner,
        probe: () async => NetworkKind.wifi,
        stepTimeout: const Duration(milliseconds: 20),
      ),
    );

    await fila.add(_visita(1));
    final resultado = await fila.sync();

    expect(resultado.kind, SyncOutcomeKind.synced);
    expect(envio.batches, hasLength(1), reason: 'o lote segue o fluxo normal');
    expect(fila.pendingCount, 0);
    expect(await disco.load(), isEmpty);
    expect(fila.isSyncing, isFalse);
    expect(telemetria.appends, 2, reason: 'visit_registered e sync_attempt; sem id, nenhum result');
  });

  test('erro da telemetria no add não sobe: a visita já está gravada', () async {
    final disco = InMemoryVisitStore();
    final fila = OfflineVisitQueue(store: disco, telemetry: _GravadorQueLanca());

    await fila.add(_visita(1));

    expect(fila.pendingCount, 1);
    expect(await disco.load(), hasLength(1));
  });
}
