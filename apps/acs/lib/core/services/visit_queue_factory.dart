import 'package:sinalacs_acs/core/database/sqlcipher_visit_store.dart';
import 'package:sinalacs_acs/core/network/auth_session.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/services/backend_visit_synchronizer.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';
import 'package:sinalacs_acs/core/services/visit_pull_service.dart';
import 'package:sinalacs_acs/core/services/visit_pull_service_factory.dart';
import 'package:sinalacs_acs/core/telemetry/network_probe.dart';
import 'package:sinalacs_acs/core/telemetry/telemetry_event.dart';
import 'package:sinalacs_acs/core/telemetry/telemetry_recorder.dart';
import 'package:sinalacs_acs/core/telemetry/telemetry_store.dart';
import 'package:sinalacs_acs/core/telemetry/telemetry_uploader.dart';

/// Fila + pull de UM dono, prontos para o painel dele.
class OwnerVisitScope {
  const OwnerVisitScope({required this.queue, required this.pullService, this.telemetryUploader});

  final OfflineVisitQueue queue;
  final VisitPullService pullService;

  /// Envio da telemetria do MESMO dono da fila (#83). `null`: sem telemetria
  /// (os testes que injetam a fila).
  final TelemetryUploader? telemetryUploader;
}

/// Gravador e envio da telemetria de UM dono (#83). Uma instância por dono,
/// montada junto com a fila: o single-flight do [uploader] vale por
/// instância, então um uploader novo por gatilho mandaria o mesmo lote duas
/// vezes em paralelo.
class OwnerTelemetry {
  const OwnerTelemetry({required this.recorder, required this.uploader});

  final TelemetryRecorder recorder;
  final TelemetryUploader uploader;
}

/// Monta o gravador e o envio da telemetria de [ownerId] sobre [store].
///
/// [probe] é a sonda de rede; sem ela, `network_type` é `unknown`. A real
/// (`connectivityProbe`, Flutter) vem do `main.dart`. Com [backend], o envio
/// só chama [transport] enquanto a sessão do app é do próprio dono
/// ([SessionBoundTelemetryTransport]).
OwnerTelemetry buildOwnerTelemetry({
  required TelemetryStore store,
  required TelemetryTransport transport,
  required String ownerId,
  AcsBackend? backend,
  NetworkProbe? probe,
}) {
  return OwnerTelemetry(
    recorder: TelemetryRecorder(store: store, owner: ownerId, probe: probe),
    uploader: TelemetryUploader(
      store: store,
      transport: backend == null ? transport : SessionBoundTelemetryTransport(backend: backend, inner: transport),
      owner: ownerId,
    ),
  );
}

/// Recusa, sem tocar em rede nem em sessão, o lote cujo dono não é o da sessão
/// aberta no app — inclusive sem sessão nenhuma.
///
/// O `BackendClient` já recusa outro dono, mas sem sessão ele tenta renovar e,
/// sem refresh token, chama `onSessionExpired`: um flush disparado pelo "Sair"
/// que chegasse ao transporte depois do logout levaria a pessoa à tela de
/// sessão expirada. Telemetria nunca pode fazer isso.
class SessionBoundTelemetryTransport implements TelemetryTransport {
  SessionBoundTelemetryTransport({required AcsBackend backend, required TelemetryTransport inner})
      : _backend = backend,
        _inner = inner;

  final AcsBackend _backend;
  final TelemetryTransport _inner;

  @override
  Future<TelemetryIngestAck> ingestTelemetry(
    List<TelemetryEventRecord> events, {
    required String expectedUserId,
  }) async {
    if (_backend.session?.userId != expectedUserId) {
      throw StateError('Sessão aberta não é do dono da telemetria.');
    }
    return _inner.ingestTelemetry(events, expectedUserId: expectedUserId);
  }
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
///
/// [telemetry] é o gravador do MESMO dono ([buildOwnerTelemetry]); `null`
/// desliga a telemetria.
OfflineVisitQueue buildVisitQueue({
  required AcsBackend backend,
  required VisitStore store,
  required String ownerId,
  TelemetryRecorder? telemetry,
}) {
  // O mesmo objeto envia e resolve conflitos (#79): uma só checagem de dono.
  final sender = BackendVisitSynchronizer(backend: backend, ownerId: ownerId);
  return OfflineVisitQueue(store: store, synchronizer: sender, conflictResolver: sender, telemetry: telemetry);
}

/// Fila e pull do dono de [session] sobre UM [storage].
///
/// O dono da fila é o `userId`; o do cursor, `userId|microAreaId`. Com um
/// [SqlCipherVisitStorage], o cursor é gravado no MESMO [VisitDatabase] da fila
/// (uma conexão por arquivo). [queue], se passada, é reaproveitada — o app
/// mantém uma fila por `userId` e nunca duas sobre o mesmo dono.
/// [telemetryUploader] é o envio do mesmo dono, reaproveitado junto com a fila.
OwnerVisitScope buildOwnerVisitScope({
  required AcsBackend backend,
  required VisitStorage storage,
  required AuthSession session,
  OfflineVisitQueue? queue,
  TelemetryUploader? telemetryUploader,
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
    telemetryUploader: telemetryUploader,
  );
}
