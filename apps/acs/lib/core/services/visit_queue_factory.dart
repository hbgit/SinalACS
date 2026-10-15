import 'package:sinalacs_acs/core/database/sqlcipher_visit_store.dart';
import 'package:sinalacs_acs/core/network/auth_session.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/services/backend_visit_synchronizer.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';
import 'package:sinalacs_acs/core/services/visit_pull_service.dart';
import 'package:sinalacs_acs/core/services/visit_pull_service_factory.dart';

/// Fila + pull de UM dono, prontos para o painel dele.
class OwnerVisitScope {
  const OwnerVisitScope({required this.queue, required this.pullService});

  final OfflineVisitQueue queue;
  final VisitPullService pullService;
}

/// Resolve a fila e o pull do dono de uma sessão.
typedef VisitScopeResolver = OwnerVisitScope Function(AuthSession session);

/// Dono do cursor de `visits.pull`: usuário E microárea. O mesmo ACS movido de
/// microárea não herda o `since` do território anterior.
String visitCursorOwner(AuthSession session) =>
    '${session.userId}|${session.microAreaId ?? ''}';

/// Monta a fila de visitas de [ownerId] como ela roda em produção.
///
/// Existe como função pública, e não como método privado da `State` do app,
/// porque a ausência do sincronizador foi um defeito que nenhum teste podia
/// enxergar: a UI só é testável com a fila injetada, então a montagem real
/// nunca era exercitada. `sync()` caía no ramo sem remetente e devolvia erro —
/// as visitas nunca subiam e o disco nunca era liberado.
///
/// [store] é obrigatório: é a visão do dono (`VisitStorage.forOwner`). Não há
/// mais padrão que abra o banco sem dono.
OfflineVisitQueue buildVisitQueue({
  required AcsBackend backend,
  required VisitStore store,
  required String ownerId,
}) =>
    OfflineVisitQueue(
      store: store,
      synchronizer: BackendVisitSynchronizer(backend: backend, ownerId: ownerId),
    );

/// Fila e pull do dono de [session] sobre UM [storage].
///
/// O dono da fila é o `userId`; o do cursor, `userId|microAreaId`. Com um
/// [SqlCipherVisitStorage], o cursor é gravado no MESMO [VisitDatabase] da fila
/// (uma conexão por arquivo). [queue], se passada, é reaproveitada — o app
/// mantém uma fila por `userId` e nunca duas sobre o mesmo dono.
OwnerVisitScope buildOwnerVisitScope({
  required AcsBackend backend,
  required VisitStorage storage,
  required AuthSession session,
  OfflineVisitQueue? queue,
}) {
  final store = storage.forOwner(session.userId);
  return OwnerVisitScope(
    queue: queue ?? buildVisitQueue(backend: backend, store: store, ownerId: session.userId),
    pullService: buildVisitPullService(
      backend: backend,
      localVisits: store,
      cursorOwner: visitCursorOwner(session),
      cursorDatabase: storage is SqlCipherVisitStorage ? storage.database : null,
    ),
  );
}
