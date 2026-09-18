import 'package:sinalacs_acs/core/database/sync_cursor_store.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/security/database_key_store.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';
import 'package:sinalacs_acs/core/services/visit_pull_service.dart';

/// Monta o serviço de pull central→dispositivo (RF15, decisão §5) como ele
/// roda em produção.
///
/// [localVisits] deve ser o MESMO `VisitStore` que respalda a
/// `OfflineVisitQueue` do app: é o que `VisitPullService` usa para nunca
/// reintroduzir localmente uma visita que já está na fila offline (ver a
/// documentação da própria classe). Passar um store diferente perde essa
/// garantia sem lançar nenhum erro visível.
///
/// [cursorStore] existe só para o teste poder inspecionar o cursor gravado;
/// em produção a chamada não passa nada e usa o padrão, respaldado pelo
/// Keystore/Keychain do aparelho.
VisitPullService buildVisitPullService({
  required AcsBackend backend,
  required VisitStore localVisits,
  SyncCursorStore? cursorStore,
}) =>
    VisitPullService(
      backend: backend,
      cursorStore: cursorStore ??
          SyncCursorStore(keyStore: SecureStorageDatabaseKeyStore()),
      localVisits: localVisits,
    );
