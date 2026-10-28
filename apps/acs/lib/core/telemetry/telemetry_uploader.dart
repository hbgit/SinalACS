import 'dart:async';

import 'package:sinalacs_acs/core/services/owner_id.dart';
import 'package:sinalacs_acs/core/telemetry/telemetry_event.dart';
import 'package:sinalacs_acs/core/telemetry/telemetry_store.dart';

// Dart puro de propósito: o `backend_client.dart` importa este arquivo e roda
// também na VM (`tool/live_check.dart`). Nada aqui pode chegar a `dart:ui`,
// nem pelo gravador (`telemetry_recorder.dart` → `connectivity_plus`) —
// `test/session_store_wiring_test.dart` guarda o caminho.

/// Resposta de `telemetry.ingest`: os ids que o servidor gravou (ou já tinha)
/// e os que recusou pelo esquema. Os dois saem do aparelho.
class TelemetryIngestAck {
  const TelemetryIngestAck({required this.accepted, required this.rejected});

  final Set<String> accepted;
  final Set<String> rejected;
}

/// Quem leva o lote ao servidor. [expectedUserId] é o dono dos eventos: sessão
/// de outro dono tem de falhar sem chamada de rede (RNF06).
abstract interface class TelemetryTransport {
  Future<TelemetryIngestAck> ingestTelemetry(
    List<TelemetryEventRecord> events, {
    required String expectedUserId,
  });
}

/// Resultado de um [TelemetryUploader.flush].
class TelemetryFlushResult {
  const TelemetryFlushResult({required this.sent, required this.rejected, required this.stoppedByFailure});

  /// Eventos aceitos pelo servidor e apagados do aparelho.
  final int sent;

  /// Eventos recusados pelo esquema e apagados do aparelho.
  final int rejected;

  /// `true` quando o transporte ou o store falhou e o flush parou com lote
  /// ainda no aparelho.
  final bool stoppedByFailure;
}

/// Sobe a fila local de telemetria do [owner] em lotes.
///
/// Idempotente: o servidor ignora `eventId` repetido, então um lote cuja
/// resposta se perdeu é reenviado inteiro na próxima vez, sem duplicar linha.
/// Sai do aparelho só o que voltou em `accepted` ou `rejected`; id que o
/// servidor não respondeu fica. Nunca lança: telemetria não derruba nada.
class TelemetryUploader {
  TelemetryUploader({
    required TelemetryStore store,
    required TelemetryTransport transport,
    required String owner,
    this.batchSize = 100,
    this.maxBatchesPerFlush = 10,
  })  : _store = store,
        _transport = transport,
        _owner = requireOwnerId(owner);

  final TelemetryStore _store;
  final TelemetryTransport _transport;
  final String _owner;
  final int batchSize;
  final int maxBatchesPerFlush;

  Future<TelemetryFlushResult>? _inFlight;

  /// Single-flight: uma chamada durante um voo devolve o mesmo `Future`.
  Future<TelemetryFlushResult> flush() {
    final emVoo = _inFlight;
    if (emVoo != null) return emVoo;
    final voo = _run();
    _inFlight = voo;
    // `whenComplete` sobre um future que nunca falha (`_run` não lança).
    voo.whenComplete(() {
      if (identical(_inFlight, voo)) _inFlight = null;
    });
    return voo;
  }

  Future<TelemetryFlushResult> _run() async {
    var sent = 0;
    var rejected = 0;
    TelemetryFlushResult parar() => TelemetryFlushResult(sent: sent, rejected: rejected, stoppedByFailure: true);

    for (var i = 0; i < maxBatchesPerFlush; i++) {
      final List<TelemetryEventRecord> lote;
      final TelemetryIngestAck ack;
      try {
        lote = await _store.oldestForOwner(_owner, limit: batchSize);
        if (lote.isEmpty) break;
        ack = await _transport.ingestTelemetry(lote, expectedUserId: _owner);
      } catch (_) {
        // Rede, sessão vencida, outro dono, servidor antigo sem o método: o
        // lote fica para a próxima vez.
        return parar();
      }

      // O servidor devolve os ids em minúsculas; o casamento ignora a caixa.
      final aceitos = {for (final id in ack.accepted) id.toLowerCase()};
      final recusados = {for (final id in ack.rejected) id.toLowerCase()};
      // Só ids lidos do próprio dono: `deleteByIds` não filtra por dono, e um
      // ACK com id de outro dono nunca pode apagar o evento dele.
      final apagar = <String>[];
      var aceitosNoLote = 0;
      var recusadosNoLote = 0;
      for (final e in lote) {
        final id = e.eventId.toLowerCase();
        if (aceitos.contains(id)) {
          aceitosNoLote++;
          apagar.add(e.eventId);
        } else if (recusados.contains(id)) {
          recusadosNoLote++;
          apagar.add(e.eventId);
        }
      }
      try {
        if (apagar.isNotEmpty) await _store.deleteByIds(apagar);
      } catch (_) {
        // O servidor já tem os eventos; o reenvio é idempotente.
        return parar();
      }
      sent += aceitosNoLote;
      rejected += recusadosNoLote;
      // Lote incompleto: a fila acabou. Id sem resposta: parar evita reenviar
      // o mesmo resto a cada volta deste flush.
      if (lote.length < batchSize || apagar.length < lote.length) break;
    }
    return TelemetryFlushResult(sent: sent, rejected: rejected, stoppedByFailure: false);
  }
}
