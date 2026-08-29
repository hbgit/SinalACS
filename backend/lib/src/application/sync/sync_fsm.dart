enum SyncState {
  idle,
  localWrite,
  queued,
  syncing,
  conflict,
  synced,
  error,
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
        state = SyncState.queued;
        break;
      case SyncEvent.networkUp:
        if (state == SyncState.queued || state == SyncState.localWrite) {
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
      case SyncEvent.networkDown:
      case SyncEvent.syncStart:
        break;
    }
  }
}
