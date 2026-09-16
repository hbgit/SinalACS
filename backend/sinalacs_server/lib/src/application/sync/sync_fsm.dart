enum SyncState {
  idle,
  localWrite,
  queued,
  syncing,
  conflict,
  synced,
  error,

  /// Terminal: o servidor recusou em definitivo (ver `VisitSyncService`,
  /// `SyncStatus.rejected`). Ao contrário de `error`, nenhum evento de rede
  /// tira uma visita deste estado — `networkUp`/`syncStart` não o alcançam,
  /// porque o motivo da recusa não muda com uma próxima tentativa.
  rejected,
}

enum SyncEvent {
  save,
  enqueue,
  networkUp,
  networkDown,
  syncStart,
  syncAck,
  syncConflict,
  syncError,
  syncRejected,
}

class SyncFsm {
  SyncFsm() : state = SyncState.idle;

  SyncState state;

  void trigger(SyncEvent event) {
    switch (event) {
      case SyncEvent.save:
        state = SyncState.localWrite;
        break;
      case SyncEvent.enqueue:
        if (state == SyncState.localWrite || state == SyncState.idle) {
          state = SyncState.queued;
        }
        break;
      case SyncEvent.networkUp:
        if (state == SyncState.queued ||
            state == SyncState.localWrite ||
            state == SyncState.error) {
          state = SyncState.syncing;
        }
        break;
      case SyncEvent.syncStart:
        if (state == SyncState.queued ||
            state == SyncState.localWrite ||
            state == SyncState.idle) {
          state = SyncState.syncing;
        }
        break;
      case SyncEvent.syncAck:
        state = SyncState.synced;
        break;
      case SyncEvent.syncConflict:
        state = SyncState.conflict;
        break;
      case SyncEvent.syncError:
        state = SyncState.error;
        break;
      case SyncEvent.syncRejected:
        state = SyncState.rejected;
        break;
      case SyncEvent.networkDown:
        if (state == SyncState.syncing || state == SyncState.queued) {
          state = SyncState.queued;
        }
        break;
    }
  }
}
