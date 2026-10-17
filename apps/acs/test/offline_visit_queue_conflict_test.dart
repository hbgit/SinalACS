import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';

import 'support/fakes.dart';

/// Conflito de visita (#79, D3): sai da retentativa, fica no aparelho com a
/// cópia do servidor até o ACS decidir, e a decisão fala com o servidor só em
/// "Manter a minha". Ids e pacientes sintéticos.
void main() {
  const copiaDoServidor = VisitConflictSnapshot(
    version: 3,
    status: 'Paciente ausente',
    notes: 'Sem resposta',
  );

  OfflineVisitRecord visita(String localId, {int n = 1}) => OfflineVisitRecord(
        localId: localId,
        patientId: syntheticPatientId(n),
        risk: 'red',
        status: 'PENDENTE',
        outcome: 'Realizada com sucesso',
        notes: 'obs do aparelho',
      );

  OfflineVisitRecord emConflito(String localId, {int versao = 3}) => visita(localId).copyWith(
        conflictServerVersion: versao,
        conflictServer: VisitConflictSnapshot(version: versao, status: 'Paciente ausente', notes: 'Sem resposta'),
      );

  test('conflito sai da retentativa e guarda a cópia do servidor', () async {
    final envio = _Sincronizador((v) => VisitSyncOutcome(
          localId: v.localId,
          status: 'conflict',
          serverVersion: 3,
          serverSnapshot: copiaDoServidor,
        ));
    final store = InMemoryVisitStore();
    final fila = OfflineVisitQueue(store: store, synchronizer: envio);
    await fila.add(visita('local-1'));

    final resultado = await fila.sync();

    expect(resultado.kind, SyncOutcomeKind.conflict);
    expect(fila.pendingCount, 0);
    expect(fila.conflictCount, 1);
    final c = fila.conflictVisits.single;
    expect(c.conflictServerVersion, 3);
    expect(c.conflictServer, same(copiaDoServidor));
    expect(c.outcome, 'Realizada com sucesso', reason: 'o conteúdo do aparelho não muda');

    final disco = await store.load();
    expect(disco.single.conflictServerVersion, 3, reason: 'o conflito é persistido');
  });

  test('conflito repetido não duplica', () async {
    final envio = _Sincronizador((v) => VisitSyncOutcome(
          localId: v.localId,
          status: 'conflict',
          serverVersion: 3,
          serverSnapshot: copiaDoServidor,
        ));
    final fila = OfflineVisitQueue(synchronizer: envio);
    await fila.add(visita('local-1'));
    await fila.add(visita('local-2', n: 2));

    await fila.sync();
    await fila.sync();
    await fila.sync();

    expect(fila.conflictCount, 2);
    expect(envio.lotes, hasLength(1), reason: 'a visita em conflito não volta a ser enviada');
    expect(envio.lotes.single.map((v) => v.localId), ['local-1', 'local-2']);
  });

  test('restore separa pendente, conflito e recusada', () async {
    final store = InMemoryVisitStore();
    await store.save([
      visita('pendente'),
      emConflito('conflito'),
      visita('recusada').copyWith(rejectionReason: 'paciente fora da sua microárea'),
    ]);

    final fila = OfflineVisitQueue(store: store);
    await fila.restore();

    expect(fila.pendingCount, 1);
    expect(fila.conflictCount, 1);
    expect(fila.rejectedCount, 1);
    expect(fila.conflictVisits.single.localId, 'conflito');
  });

  test('conflito sem versão é erro retentável', () async {
    final envio = _Sincronizador((v) => VisitSyncOutcome(localId: v.localId, status: 'conflict'));
    final fila = OfflineVisitQueue(synchronizer: envio);
    await fila.add(visita('local-1'));

    final resultado = await fila.sync();

    expect(resultado.kind, SyncOutcomeKind.error);
    expect(resultado.message, 'O servidor indicou conflito sem informar a versão.');
    expect(fila.pendingCount, 1);
    expect(fila.conflictCount, 0);
  });

  test('resolveKeepServer remove só aquela visita e persiste', () async {
    final store = InMemoryVisitStore();
    await store.save([emConflito('c-1'), emConflito('c-2'), visita('pendente')]);
    final fila = OfflineVisitQueue(store: store);
    await fila.restore();

    await fila.resolveKeepServer('c-1');
    await fila.resolveKeepServer('desconhecida'); // no-op

    expect(fila.conflictVisits.map((v) => v.localId), ['c-2']);
    expect(fila.pendingCount, 1);
    expect((await store.load()).map((v) => v.localId).toSet(), {'c-2', 'pendente'});
  });

  test('resolveKeepLocal sincronizado sai do aparelho', () async {
    final store = InMemoryVisitStore();
    await store.save([emConflito('c-1')]);
    final resolvedor = _Resolvedor((v, _) async => VisitSyncOutcome(localId: v.localId, status: 'synced', serverVersion: 4));
    final fila = OfflineVisitQueue(store: store, conflictResolver: resolvedor);
    await fila.restore();

    final resultado = await fila.resolveKeepLocal('c-1', outcome: 'Paciente ausente', notes: 'editada');

    expect(resultado.kind, SyncOutcomeKind.synced);
    expect(resultado.processed, 1);
    expect(fila.conflictCount, 0);
    expect(await store.load(), isEmpty);
    final chamada = resolvedor.chamadas.single;
    expect(chamada.versao, 3);
    expect(chamada.visita.outcome, 'Paciente ausente');
    expect(chamada.visita.notes, 'editada');
  });

  test('resolveKeepLocal com conflito novo atualiza a cópia', () async {
    final store = InMemoryVisitStore();
    await store.save([emConflito('c-1')]);
    const novaCopia = VisitConflictSnapshot(version: 4, status: 'Realizada com sucesso', notes: 'outra');
    final resolvedor = _Resolvedor((v, _) async => VisitSyncOutcome(
          localId: v.localId,
          status: 'conflict',
          serverVersion: 4,
          serverSnapshot: novaCopia,
        ));
    final fila = OfflineVisitQueue(store: store, conflictResolver: resolvedor);
    await fila.restore();

    final resultado = await fila.resolveKeepLocal('c-1', notes: 'editada');

    expect(resultado.kind, SyncOutcomeKind.conflict);
    final c = fila.conflictVisits.single;
    expect(c.conflictServerVersion, 4);
    expect(c.conflictServer, same(novaCopia));
    expect(c.notes, 'editada', reason: 'a edição do ACS não se perde');
    expect(c.outcome, 'Realizada com sucesso');
    final disco = (await store.load()).single;
    expect(disco.conflictServerVersion, 4);
    expect(disco.notes, 'editada');
  });

  test('resolveKeepLocal recusado vai para recusadas', () async {
    final store = InMemoryVisitStore();
    await store.save([emConflito('c-1')]);
    final resolvedor = _Resolvedor((v, _) async => VisitSyncOutcome(
          localId: v.localId,
          status: 'rejected',
          message: 'paciente fora da sua microárea',
        ));
    final fila = OfflineVisitQueue(store: store, conflictResolver: resolvedor);
    await fila.restore();

    final resultado = await fila.resolveKeepLocal('c-1');

    expect(resultado.kind, SyncOutcomeKind.rejected);
    expect(resultado.message, 'paciente fora da sua microárea');
    expect(fila.conflictCount, 0);
    expect(fila.rejectedVisits.single.rejectionReason, 'paciente fora da sua microárea');
    expect((await store.load()).single.rejectionReason, 'paciente fora da sua microárea');
  });

  test('resolveKeepLocal recusado não ressuscita visita descartada durante a chamada', () async {
    final store = InMemoryVisitStore();
    await store.save([emConflito('c-1')]);
    late final OfflineVisitQueue fila;
    final resolvedor = _Resolvedor((v, _) async {
      // "Manter a do servidor" correu enquanto a chamada estava em voo.
      await fila.resolveKeepServer('c-1');
      return VisitSyncOutcome(localId: v.localId, status: 'rejected', message: 'paciente fora da sua microárea');
    });
    fila = OfflineVisitQueue(store: store, conflictResolver: resolvedor);
    await fila.restore();

    final resultado = await fila.resolveKeepLocal('c-1');

    expect(resultado.kind, SyncOutcomeKind.rejected);
    expect(fila.conflictCount, 0);
    expect(fila.rejectedCount, 0, reason: 'o ACS já descartou a cópia do aparelho');
    expect(await store.load(), isEmpty);
  });

  test('resolveKeepLocal sincronizado não conta visita descartada durante a chamada', () async {
    final store = InMemoryVisitStore();
    await store.save([emConflito('c-1')]);
    late final OfflineVisitQueue fila;
    final resolvedor = _Resolvedor((v, _) async {
      // "Manter a do servidor" correu enquanto a chamada estava em voo.
      await fila.resolveKeepServer('c-1');
      return VisitSyncOutcome(localId: v.localId, status: 'synced', serverVersion: 4);
    });
    fila = OfflineVisitQueue(store: store, conflictResolver: resolvedor);
    await fila.restore();

    final resultado = await fila.resolveKeepLocal('c-1');

    expect(resultado.kind, SyncOutcomeKind.synced);
    expect(fila.conflictCount, 0);
    expect(fila.syncedCount, 0, reason: 'o ACS já descartou a cópia do aparelho');
    expect(await store.load(), isEmpty);
  });

  test('resolveKeepLocal sem rede mantém o conflito', () async {
    final store = InMemoryVisitStore();
    await store.save([emConflito('c-1')]);
    final resolvedor = _Resolvedor((_, __) async => throw const BackendFailure('Sem conexão com o servidor.'));
    final fila = OfflineVisitQueue(store: store, conflictResolver: resolvedor);
    await fila.restore();

    final resultado = await fila.resolveKeepLocal('c-1', notes: 'editada');

    expect(resultado.kind, SyncOutcomeKind.error);
    expect(resultado.message, 'Sem conexão com o servidor.');
    expect(fila.conflictCount, 1);
    expect(fila.conflictVisits.single.conflictServerVersion, 3);
    expect(fila.conflictVisits.single.notes, 'editada', reason: 'a edição fica gravada');
    final disco = (await store.load()).single;
    expect(disco.inConflict, isTrue);
    expect(disco.notes, 'editada');
  });

  test('resolveKeepLocal sem resolvedor configurado é erro', () async {
    final store = InMemoryVisitStore();
    await store.save([emConflito('c-1')]);
    final fila = OfflineVisitQueue(store: store);
    await fila.restore();

    final resultado = await fila.resolveKeepLocal('c-1');

    expect(resultado.kind, SyncOutcomeKind.error);
    expect(resultado.message, 'A resolução de conflitos não está configurada neste aplicativo.');
    expect(fila.conflictCount, 1);
  });

  test('resolve aguarda sync em voo', () async {
    final portao = Completer<void>();
    final eventos = <String>[];
    final envio = _Sincronizador(
      (v) => VisitSyncOutcome(localId: v.localId, status: 'synced', serverVersion: 2),
      antes: () async {
        eventos.add('sync começou');
        await portao.future;
        eventos.add('sync terminou');
      },
    );
    final resolvedor = _Resolvedor((v, _) async {
      eventos.add('resolve');
      return VisitSyncOutcome(localId: v.localId, status: 'synced', serverVersion: 4);
    });
    final store = InMemoryVisitStore();
    await store.save([emConflito('c-1'), visita('pendente')]);
    final fila = OfflineVisitQueue(store: store, synchronizer: envio, conflictResolver: resolvedor);
    await fila.restore();

    final sincronizando = fila.sync();
    await pumpEventQueue();
    final resolvendo = fila.resolveKeepLocal('c-1');
    await pumpEventQueue();
    expect(resolvedor.chamadas, isEmpty, reason: 'o resolvedor espera o sync em voo');

    portao.complete();
    await sincronizando;
    final resultado = await resolvendo;

    expect(resultado.kind, SyncOutcomeKind.synced);
    expect(eventos, ['sync começou', 'sync terminou', 'resolve']);
    expect(fila.conflictCount, 0);
    expect(fila.pendingCount, 0);
    expect(await store.load(), isEmpty);
  });
}

class _Sincronizador implements VisitSynchronizer {
  _Sincronizador(this.resposta, {this.antes});

  final VisitSyncOutcome Function(OfflineVisitRecord visit) resposta;
  final Future<void> Function()? antes;
  final List<List<OfflineVisitRecord>> lotes = [];

  @override
  Future<List<VisitSyncOutcome>> push(List<OfflineVisitRecord> visits) async {
    lotes.add(List.of(visits));
    await antes?.call();
    return [for (final visit in visits) resposta(visit)];
  }
}

class _Resolvedor implements VisitConflictResolver {
  _Resolvedor(this.resposta);

  final Future<VisitSyncOutcome> Function(OfflineVisitRecord visit, int versao) resposta;
  final List<({OfflineVisitRecord visita, int versao})> chamadas = [];

  @override
  Future<VisitSyncOutcome> resolve(OfflineVisitRecord visit, {required int expectedServerVersion}) {
    chamadas.add((visita: visit, versao: expectedServerVersion));
    return resposta(visit, expectedServerVersion);
  }
}
