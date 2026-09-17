import 'package:sinalacs_acs/core/database/sync_cursor_store.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';
import 'package:sinalacs_client/sinalacs_client.dart';

/// Aplica a sincronização central→dispositivo (`visits.pull`, RF15) sobre o
/// dispositivo do ACS.
///
/// Lê o cursor por instalação (`SyncCursorStore`), chama
/// `AcsBackend.pullVisits`, descarta o que já está na fila offline local
/// (mesmo critério de dedupe por `localId` que `visits.sync` usa do lado
/// servidor) e avança o cursor.
///
/// **Escopo intencional desta task**: [OfflineVisitQueue] hoje não tem um
/// conceito de "visita vinda do servidor, só leitura, não editável
/// localmente" — toda visita que ela guarda é candidata a subir de volta em
/// `sync()`. Escrever as entradas recebidas ali de volta criaria um loop
/// pull → sync → pull, reenviando ao servidor dados que vieram dele mesmo.
/// Por isso este serviço NUNCA escreve no [VisitStore] da fila: ele só lê
/// dali para dedupe e expõe o resultado do pull em [lastPulled], para a UI
/// consumir como referência (ex.: contagem territorial mais precisa). Uma
/// tela consumidora final — e a extensão da fila para diferenciar "visita do
/// servidor" de "visita registrada em campo" — é decisão de uma próxima
/// iteração; a decisão §5 especifica o contrato de sincronização, não a UI.
class VisitPullService {
  VisitPullService({
    required AcsBackend backend,
    required SyncCursorStore cursorStore,
    required VisitStore localVisits,
  })  : _backend = backend,
        _cursorStore = cursorStore,
        _localVisits = localVisits;

  /// Usado como `since` quando o dispositivo nunca sincronizou (cursor
  /// ausente) — "desde o início dos tempos", não um erro.
  static final DateTime epoch = DateTime.utc(2000);

  final AcsBackend _backend;
  final SyncCursorStore _cursorStore;
  final VisitStore _localVisits;

  List<VisitSyncEntry> _lastPulled = const [];

  /// Entradas do último [pullAndMerge] que não duplicam a fila offline local,
  /// na ordem em que o servidor as devolveu. Só para leitura pela UI — ver
  /// nota da classe.
  List<VisitSyncEntry> get lastPulled => List.unmodifiable(_lastPulled);

  /// Lê o cursor, busca as visitas alteradas desde ele, remove as que já
  /// existem localmente por `localId` e avança o cursor para agora.
  Future<void> pullAndMerge() async {
    final since = await _cursorStore.read() ?? epoch;
    final entries = await _backend.pullVisits(since: since);

    final existingLocalIds = {
      for (final visit in await _localVisits.load()) visit.localId,
    };
    _lastPulled = [
      for (final entry in entries)
        if (!existingLocalIds.contains(entry.localId)) entry,
    ];

    await _cursorStore.write(DateTime.now().toUtc());
  }
}
