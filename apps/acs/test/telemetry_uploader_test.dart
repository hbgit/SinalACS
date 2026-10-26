import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/telemetry/telemetry_event.dart';
import 'package:sinalacs_acs/core/telemetry/telemetry_store.dart';
import 'package:sinalacs_acs/core/telemetry/telemetry_uploader.dart';

/// Eventos sintéticos, sem PII: ids opacos e um payload de contagem.
TelemetryEventRecord _evento(String id, {String dono = 'acs-a', int ordem = 0}) => TelemetryEventRecord(
      eventId: id,
      owner: dono,
      name: 'sync_attempt',
      occurredAt: DateTime.utc(2026, 10, 25, 12).add(Duration(milliseconds: ordem)),
      payload: const {'records_count': 1, 'network_type': 'wifi', 'channel': 'sync'},
    );

/// Transporte programável: cada chamada passa por [responder], que decide o ACK
/// ou lança. Guarda os lotes e os donos pedidos.
class _Transporte implements TelemetryTransport {
  _Transporte(this.responder);

  final Future<TelemetryIngestAck> Function(int chamada, List<TelemetryEventRecord> lote) responder;
  final lotes = <List<TelemetryEventRecord>>[];
  final donos = <String>[];

  @override
  Future<TelemetryIngestAck> ingestTelemetry(List<TelemetryEventRecord> events, {required String expectedUserId}) {
    lotes.add(List.of(events));
    donos.add(expectedUserId);
    return responder(lotes.length, events);
  }
}

TelemetryIngestAck _aceitaTudo(List<TelemetryEventRecord> lote) =>
    TelemetryIngestAck(accepted: {for (final e in lote) e.eventId}, rejected: const {});

void main() {
  late InMemoryTelemetryStore store;

  setUp(() => store = InMemoryTelemetryStore());

  test('falha de rede mantém; aceito some', () async {
    await store.append(_evento('e1'));
    await store.append(_evento('e2', ordem: 1));
    var foraDoAr = true;
    final transporte = _Transporte((_, lote) async {
      if (foraDoAr) throw Exception('sem rede');
      return _aceitaTudo(lote);
    });
    final uploader = TelemetryUploader(store: store, transport: transporte, owner: 'acs-a');

    final falhou = await uploader.flush();
    expect(falhou.stoppedByFailure, isTrue);
    expect(falhou.sent, 0);
    expect(await store.countForOwner('acs-a'), 2, reason: 'o lote fica no aparelho');

    foraDoAr = false;
    final ok = await uploader.flush();
    expect(ok.stoppedByFailure, isFalse);
    expect(ok.sent, 2);
    expect(await store.countForOwner('acs-a'), 0);
    expect(transporte.donos.toSet(), {'acs-a'});
  });

  test('rejeitado também sai do aparelho', () async {
    await store.append(_evento('bom'));
    await store.append(_evento('ruim', ordem: 1));
    await store.append(_evento('sem-resposta', ordem: 2));
    final transporte = _Transporte(
      (_, __) async => const TelemetryIngestAck(accepted: {'bom'}, rejected: {'ruim'}),
    );

    final r = await TelemetryUploader(store: store, transport: transporte, owner: 'acs-a').flush();

    expect(r.sent, 1);
    expect(r.rejected, 1);
    expect(r.stoppedByFailure, isFalse);
    // Recusado pelo esquema não melhora com reenvio; o que o servidor não
    // respondeu fica para a próxima vez.
    expect((await store.oldestForOwner('acs-a', limit: 10)).map((e) => e.eventId), ['sem-resposta']);
  });

  test('ids do servidor em minúsculas casam com o id gravado sem diferenciar caixa', () async {
    await store.append(_evento('AB-CD'));
    final transporte = _Transporte(
      (_, __) async => const TelemetryIngestAck(accepted: {'ab-cd'}, rejected: {}),
    );

    final r = await TelemetryUploader(store: store, transport: transporte, owner: 'acs-a').flush();

    expect(r.sent, 1);
    expect(await store.countForOwner('acs-a'), 0);
  });

  test('reenvio após resposta perdida não deixa resto', () async {
    for (var i = 0; i < 3; i++) {
      await store.append(_evento('e$i', ordem: i));
    }
    // O "servidor" grava na 1ª chamada e a resposta se perde; na 2ª, o mesmo
    // lote volta todo aceito (idempotência por eventId).
    final gravados = <String>{};
    final transporte = _Transporte((chamada, lote) async {
      gravados.addAll(lote.map((e) => e.eventId));
      if (chamada == 1) throw const SocketExceptionFalsa();
      return _aceitaTudo(lote);
    });
    final uploader = TelemetryUploader(store: store, transport: transporte, owner: 'acs-a');

    expect((await uploader.flush()).stoppedByFailure, isTrue);
    expect(await store.countForOwner('acs-a'), 3);

    final r = await uploader.flush();
    expect(r.sent, 3);
    expect(await store.countForOwner('acs-a'), 0, reason: 'nada fica para trás');
    expect(transporte.lotes[1].map((e) => e.eventId), transporte.lotes[0].map((e) => e.eventId));
    expect(gravados, {'e0', 'e1', 'e2'});
  });

  test('flush concorrente envia uma vez', () async {
    await store.append(_evento('e1'));
    final porta = Completer<void>();
    final transporte = _Transporte((_, lote) async {
      await porta.future;
      return _aceitaTudo(lote);
    });
    final uploader = TelemetryUploader(store: store, transport: transporte, owner: 'acs-a');

    final primeiro = uploader.flush();
    final segundo = uploader.flush();
    expect(identical(primeiro, segundo), isTrue);

    porta.complete();
    final r = await primeiro;
    expect(r.sent, 1);
    expect(transporte.lotes, hasLength(1));

    // Depois do voo, um novo flush roda de novo (e não acha nada).
    final terceiro = uploader.flush();
    expect(identical(terceiro, primeiro), isFalse);
    expect((await terceiro).sent, 0);
    expect(transporte.lotes, hasLength(1), reason: 'fila vazia não chama a rede');
  });

  test('lotes de 100 até esvaziar, no máximo 10 por flush', () async {
    for (var i = 0; i < 1050; i++) {
      await store.append(_evento('e$i', ordem: i));
    }
    final transporte = _Transporte((_, lote) async => _aceitaTudo(lote));
    final uploader = TelemetryUploader(store: store, transport: transporte, owner: 'acs-a');

    final primeiro = await uploader.flush();
    expect(primeiro.sent, 1000);
    expect(transporte.lotes.map((l) => l.length), List.filled(10, 100));
    expect(await store.countForOwner('acs-a'), 50);

    final segundo = await uploader.flush();
    expect(segundo.sent, 50);
    expect(transporte.lotes.last, hasLength(50));
    expect(transporte.lotes, hasLength(11));
    expect(await store.countForOwner('acs-a'), 0);
  });

  test('só apaga ids lidos do próprio dono, mesmo que o ACK traga ids de outro', () async {
    // `deleteByIds` não filtra por dono (pendência da Task 10): a guarda é o
    // uploader só passar ids que leu de `oldestForOwner(owner, …)`.
    await store.append(_evento('a1'));
    await store.append(_evento('b1', dono: 'acs-b'));
    final transporte = _Transporte(
      (_, __) async => const TelemetryIngestAck(accepted: {'a1', 'b1'}, rejected: {'b1'}),
    );

    final r = await TelemetryUploader(store: store, transport: transporte, owner: 'acs-a').flush();

    expect(transporte.lotes.single.map((e) => e.eventId), ['a1'], reason: 'eventos de B nunca sobem por A');
    expect(r.sent, 1);
    expect(r.rejected, 0);
    expect(await store.countForOwner('acs-a'), 0);
    expect((await store.oldestForOwner('acs-b', limit: 10)).map((e) => e.eventId), ['b1']);
  });

  test('falha do store não lança e para o flush', () async {
    final transporte = _Transporte((_, lote) async => _aceitaTudo(lote));
    final r = await TelemetryUploader(store: _StoreQuebrado(), transport: transporte, owner: 'acs-a').flush();

    expect(r.stoppedByFailure, isTrue);
    expect(transporte.lotes, isEmpty);
  });
}

class SocketExceptionFalsa implements Exception {
  const SocketExceptionFalsa();
}

class _StoreQuebrado implements TelemetryStore {
  @override
  Future<void> append(TelemetryEventRecord e) async {}

  @override
  Future<int> countForOwner(String owner) async => 0;

  @override
  Future<void> deleteByIds(Iterable<String> ids) async {}

  @override
  Future<List<TelemetryEventRecord>> oldestForOwner(String owner, {required int limit}) =>
      Future.error(StateError('banco travado'));
}
