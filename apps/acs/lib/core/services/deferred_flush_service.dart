import 'dart:async';

import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/security/session_token_store.dart';
import 'package:sinalacs_acs/core/security/upload_token_store.dart';
import 'package:sinalacs_acs/core/services/backend_visit_synchronizer.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';
import 'package:sinalacs_client/sinalacs_client.dart' show SyncStatus, VisitSyncResult;

/// Tamanho de cada lote do envio diferido e do legado. O servidor recusa acima
/// de 200 (`VisitSyncService.maxLegacyBatch`); 100 deixa folga.
const deferredBatchSize = 100;

/// Mensagem do servidor para uma visita legada cujo `localId` já existe com
/// autor, em outra versão (D4). Não é recusa de território: precisa de revisão.
const legacyVersionMismatchMessage = 'visita já registrada com autor — versão diferente';

/// Resultado de [DeferredFlushService.flushAll]. Só contagens e ids de ACS —
/// nenhum conteúdo de visita.
class FlushReport {
  const FlushReport({
    required this.sent,
    required this.remaining,
    this.needsReview = 0,
    this.blockedOwners = const <String>[],
  });

  /// Visitas confirmadas (`synced`) e retiradas do aparelho nesta execução.
  final int sent;

  /// Visitas que continuam no aparelho depois da execução: de TODOS os donos
  /// (inclusive o da sessão atual, cuja fila é do painel) e da quarentena,
  /// pendentes, em conflito ou recusadas.
  final int remaining;

  /// Visitas legadas recusadas com [legacyVersionMismatchMessage]: ficam em
  /// quarentena e pedem revisão (não são erro de território).
  final int needsReview;

  /// Donos (que não são a sessão atual) com visitas no aparelho que este
  /// serviço NÃO consegue subir: sem token de envio, ou com o token recusado
  /// pelo servidor. Só sobem quando o próprio dono entrar de novo.
  final List<String> blockedOwners;
}

/// Sincronizador da fila de UM dono pelo token de envio dele (`syncDeferred`).
///
/// O autor gravado no servidor é o dono do token — por isso cada instância tem
/// um só token e a fila temporária de um só dono. Envia em lotes de
/// [deferredBatchSize]; se um lote do meio falhar, devolve o que já foi
/// confirmado (o resto fica pendente e é reenviado, idempotente pelo `localId`).
class DeferredVisitSynchronizer implements VisitSynchronizer {
  DeferredVisitSynchronizer({required this.backend, required this.uploadToken, required this.deviceId});

  final AcsBackend backend;
  final String uploadToken;
  final String deviceId;

  /// `true` quando o servidor recusou o token (vencido, revogado, outro
  /// aparelho, conta inativa). A fila só enxerga a exceção como texto; o
  /// serviço precisa saber o tipo.
  bool tokenRefused = false;

  @override
  Future<List<VisitSyncOutcome>> push(List<OfflineVisitRecord> visits) async {
    final outcomes = <VisitSyncOutcome>[];
    for (var start = 0; start < visits.length; start += deferredBatchSize) {
      final chunk = visits.sublist(start, (start + deferredBatchSize).clamp(0, visits.length));
      try {
        final results = await backend.syncDeferredVisits(
          uploadToken: uploadToken,
          deviceId: deviceId,
          visits: [for (final visit in chunk) visitSyncEntryFor(visit)],
        );
        outcomes.addAll(results.map(_outcome));
      } on UploadTokenRefused {
        tokenRefused = true;
        if (outcomes.isEmpty) rethrow;
        break;
      } catch (_) {
        if (outcomes.isEmpty) rethrow;
        break;
      }
    }
    return outcomes;
  }
}

VisitSyncOutcome _outcome(VisitSyncResult result) => VisitSyncOutcome(
      localId: result.localId,
      status: result.syncStatus.name,
      serverVersion: result.serverVersion,
      message: result.message,
    );

/// Sobe o que está preso no aparelho e não pertence à sessão atual (D4/D7).
///
/// **A fila do dono da sessão atual NÃO é tocada aqui**: ela é do painel
/// (`OfflineVisitQueue` do escopo dele, que sincroniza pela sessão). Enviá-la
/// também por aqui seria um segundo `sync` concorrente sobre o mesmo dono, e
/// `OfflineVisitQueue.sync` não é single-flight. Quem quiser tudo enviado (o
/// "Sair", Task 8) sincroniza a fila do painel e depois chama [flushAll].
class DeferredFlushService {
  DeferredFlushService({
    required AcsBackend backend,
    required VisitStorage storage,
    required UploadTokenStore tokens,
    required DeviceIdStore deviceIds,
  })  : _backend = backend,
        _storage = storage,
        _tokens = tokens,
        _deviceIds = deviceIds;

  final AcsBackend _backend;
  final VisitStorage _storage;
  final UploadTokenStore _tokens;
  final DeviceIdStore _deviceIds;

  Future<FlushReport>? _inFlight;

  /// `localId`s legados recusados com [legacyVersionMismatchMessage]: não
  /// adianta reenviar por ninguém enquanto o app vive.
  final Set<String> _legacyNeedsReview = <String>{};

  /// `localId`s legados recusados por transportador (`userId|microAreaId`):
  /// não são reenviados pelo MESMO transportador nesta execução do app (cada
  /// reenvio vira linha de auditoria no servidor), mas um ACS de outra
  /// microárea ainda pode subi-los.
  final Map<String, Set<String>> _legacyRejectedBy = <String, Set<String>>{};

  /// Sobe, nesta ordem: (1) legado, via a sessão ATUAL como transporte; (2) a
  /// fila de cada dono que tem token de envio, via `syncDeferred`; (3) revoga
  /// e apaga o token de todo dono cuja fila zerou. Uma chamada por vez
  /// (single-flight). Nunca lança: erros viram `remaining`/`blockedOwners`.
  Future<FlushReport> flushAll() {
    final pending = _inFlight;
    if (pending != null) return pending;
    late final Future<FlushReport> flight;
    flight = _run().whenComplete(() {
      if (identical(_inFlight, flight)) _inFlight = null;
    });
    return _inFlight = flight;
  }

  /// Visitas de OUTROS donos + legado. Só contagem.
  Future<int> pendingElsewhere(String currentOwnerId) async {
    final counts = await _safe(_storage.countsByOwner) ?? const <String, int>{};
    final legacy = await _safe(_storage.legacy.load) ?? const <OfflineVisitRecord>[];
    var total = legacy.length;
    counts.forEach((owner, count) {
      if (owner != currentOwnerId) total += count;
    });
    return total;
  }

  Future<FlushReport> _run() async {
    var sent = 0;
    final blocked = <String>{};
    try {
      final deviceId = await _safe(_deviceIds.readOrCreate);

      // (1) Legado: só com uma sessão para transportar.
      final transporter = _backend.session;
      if (transporter != null && deviceId != null) {
        sent += await _flushLegacy(deviceId, '${transporter.userId}|${transporter.microAreaId ?? ''}');
      }

      // (2) e (3): cada dono com token, menos o da sessão atual.
      for (final owner in await _safe(_tokens.owners) ?? const <String>[]) {
        if (owner == _backend.session?.userId) continue;
        final token = await _safe(() => _tokens.read(owner));
        if (token == null) continue;

        if (deviceId != null) {
          final synchronizer = DeferredVisitSynchronizer(backend: _backend, uploadToken: token, deviceId: deviceId);
          final queue = OfflineVisitQueue(store: _MergingOwnerStore(_storage.forOwner(owner)), synchronizer: synchronizer);
          await queue.restore();
          await queue.sync(); // nunca lança: falha vira SyncOutcome.error
          sent += queue.syncedCount;
          if (synchronizer.tokenRefused) {
            // O servidor diz que este token morreu: apagar só o local. As
            // visitas do dono FICAM, para o próximo login dele.
            blocked.add(owner);
            await _clearIfSame(owner, token);
            continue;
          }
        }

        // (3) Fila do dono vazia (nada pendente, em conflito nem recusado):
        // revoga no servidor e apaga daqui. Se o dono virou a sessão atual no
        // meio, o token fica (ele pode registrar visitas e sair de novo).
        if (owner == _backend.session?.userId) continue;
        final rows = await _safe(() => _storage.forOwner(owner).load());
        if (rows == null || rows.isNotEmpty) continue;
        try {
          await _backend.revokeUploadToken(token);
        } catch (_) {
          continue; // sem rede: tenta de novo no próximo envio
        }
        await _clearIfSame(owner, token);
      }
    } catch (_) {
      // Nunca lança: o que sobrou é contado abaixo.
    }
    return _report(sent, blocked);
  }

  /// Sobe o legado em lotes de [deferredBatchSize]. Só `synced` sai da
  /// quarentena; `rejected` e `error` ficam. Devolve quantas saíram.
  Future<int> _flushLegacy(String deviceId, String transporterKey) async {
    final rows = await _safe(_storage.legacy.load);
    if (rows == null) return 0;
    final rejectedHere = _legacyRejectedBy.putIfAbsent(transporterKey, () => <String>{});
    final toSend = [
      for (final row in rows)
        if (!_legacyNeedsReview.contains(row.localId) && !rejectedHere.contains(row.localId)) row,
    ];
    var removed = 0;
    for (var start = 0; start < toSend.length; start += deferredBatchSize) {
      final chunk = toSend.sublist(start, (start + deferredBatchSize).clamp(0, toSend.length));
      final List<VisitSyncResult> results;
      try {
        results = await _backend.syncLegacyVisits(
          [for (final visit in chunk) visitSyncEntryFor(visit)],
          deviceId: deviceId,
        );
      } catch (_) {
        break; // rede ou sessão: o resto fica para a próxima
      }
      final sentIds = {for (final visit in chunk) visit.localId};
      final synced = <String>[];
      for (final result in results) {
        if (!sentIds.contains(result.localId)) continue;
        switch (result.syncStatus) {
          case SyncStatus.synced:
            synced.add(result.localId);
          case SyncStatus.rejected:
            (result.message == legacyVersionMismatchMessage ? _legacyNeedsReview : rejectedHere).add(result.localId);
          default:
            break; // error/conflict: retenta depois
        }
      }
      try {
        await _storage.legacy.remove(synced);
        removed += synced.length;
      } catch (_) {
        // O servidor já gravou; a linha volta no próximo envio e o reenvio
        // do mesmo `localId` é idempotente (`synced`).
        break;
      }
    }
    return removed;
  }

  Future<FlushReport> _report(int sent, Set<String> blocked) async {
    final current = _backend.session?.userId;
    final counts = await _safe(_storage.countsByOwner) ?? const <String, int>{};
    final legacy = await _safe(_storage.legacy.load) ?? const <OfflineVisitRecord>[];
    final withToken = (await _safe(_tokens.owners) ?? const <String>[]).toSet();
    var remaining = legacy.length;
    counts.forEach((owner, count) {
      remaining += count;
      if (count > 0 && owner != current && !withToken.contains(owner)) blocked.add(owner);
    });
    blocked.remove(current);
    return FlushReport(
      sent: sent,
      remaining: remaining,
      needsReview: legacy.where((row) => _legacyNeedsReview.contains(row.localId)).length,
      blockedOwners: List.unmodifiable(blocked),
    );
  }

  /// Apaga o token local só se ainda é [token]: um login do dono no meio do
  /// envio gravou um token NOVO, que não pode ser apagado por engano.
  Future<void> _clearIfSame(String owner, String token) async {
    try {
      if (await _tokens.read(owner) == token) await _tokens.clear(owner);
    } catch (_) {}
  }

  static Future<T?> _safe<T>(Future<T> Function() op) async {
    try {
      return await op();
    } catch (_) {
      return null;
    }
  }
}

/// Visão do dono para a fila TEMPORÁRIA do envio diferido.
///
/// A `OfflineVisitQueue` grava a lista inteira do dono. Se o dono entrar
/// enquanto o lote dele está no servidor e registrar uma visita nova, uma
/// gravação "cega" apagaria essa visita. Por isso, ao gravar, esta visão:
/// mantém as visitas que apareceram no disco depois da leitura, e não
/// ressuscita as que sumiram do disco nesse meio-tempo (a fila do painel já as
/// enviou ou descartou). Sobra uma janela curta, só de E/S local, entre a
/// releitura e a gravação.
class _MergingOwnerStore implements VisitStore {
  _MergingOwnerStore(this._inner);

  final VisitStore _inner;
  Set<String> _seen = <String>{};

  @override
  Future<List<OfflineVisitRecord>> load() async {
    final rows = await _inner.load();
    _seen = {for (final row in rows) row.localId};
    return rows;
  }

  @override
  Future<void> save(List<OfflineVisitRecord> visits) async {
    final current = await _inner.load();
    final onDisk = {for (final row in current) row.localId};
    final keep = [for (final visit in visits) if (onDisk.contains(visit.localId)) visit];
    final keepIds = {for (final visit in keep) visit.localId};
    final added = [
      for (final row in current)
        if (!_seen.contains(row.localId) && !keepIds.contains(row.localId)) row,
    ];
    await _inner.save([...keep, ...added]);
  }
}
