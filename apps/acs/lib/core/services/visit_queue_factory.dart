import 'package:sinalacs_acs/core/database/sqlcipher_visit_store.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/security/database_key_store.dart';
import 'package:sinalacs_acs/core/services/backend_visit_synchronizer.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';

/// Monta a fila de visitas como ela roda em produção.
///
/// Existe como função pública, e não como método privado da `State` do app,
/// porque a ausência do sincronizador foi um defeito que nenhum teste podia
/// enxergar: a UI só é testável com a fila injetada, então a montagem real
/// nunca era exercitada. `sync()` caía no ramo sem remetente e devolvia erro —
/// as visitas nunca subiam e o disco nunca era liberado.
///
/// [store] existe para o teste trocar o banco criptografado por memória; o
/// `SqlCipherVisitStore` depende de canal de plataforma e não abre na VM.
OfflineVisitQueue buildVisitQueue({
  required AcsBackend backend,
  VisitStore? store,
}) =>
    OfflineVisitQueue(
      store: store ?? SqlCipherVisitStore(keyStore: SecureStorageDatabaseKeyStore()),
      synchronizer: BackendVisitSynchronizer(backend: backend),
    );
