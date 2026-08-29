import 'package:sinalacs_backend/src/application/sync/sync_fsm.dart';
import 'package:test/test.dart';

void main() {
  group('SyncFsm', () {
    test('save marca a operação como escrita local e syncStart inicia sincronização quando há fila', () {
      final fsm = SyncFsm();

      fsm.trigger(SyncEvent.save);
      expect(fsm.state, SyncState.localWrite);

      fsm.trigger(SyncEvent.enqueue);
      expect(fsm.state, SyncState.queued);

      fsm.trigger(SyncEvent.syncStart);
      expect(fsm.state, SyncState.syncing);
    });

    test('networkUp move a fila para sincronização', () {
      final fsm = SyncFsm();

      fsm.trigger(SyncEvent.save);
      fsm.trigger(SyncEvent.enqueue);
      fsm.trigger(SyncEvent.networkUp);

      expect(fsm.state, SyncState.syncing);
    });

    test('syncConflict registra conflito de versão', () {
      final fsm = SyncFsm();

      fsm.trigger(SyncEvent.save);
      fsm.trigger(SyncEvent.syncConflict);

      expect(fsm.state, SyncState.conflict);
    });
  });
}
