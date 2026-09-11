import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/visits/visit_sync_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// Implementação de [VisitStore] sobre o ORM do Serverpod.
///
/// Segue o mesmo arranjo de [OrmAlertStore]: a sessão é obtida por chamada, e
/// não guardada no construtor, porque o Serverpod amarra o ciclo de vida da
/// conexão à `Session` da requisição.
class OrmVisitStore implements VisitStore {
  OrmVisitStore({
    required Session Function() session,
    Transaction? transaction,
  })  : _session = session,
        _transaction = transaction;

  final Session Function() _session;
  final Transaction? _transaction;

  @override
  Future<Visit?> findByLocalId(String localId) async {
    // `visits.localId` tem índice único (visits_local_id_key), então esta busca
    // é o ponto de deduplicação do reenvio de um lote.
    return Visit.db.findFirstRow(
      _session(),
      where: (visit) => visit.localId.equals(UuidValue.fromString(localId)),
      transaction: _transaction,
    );
  }

  @override
  Future<Visit> insert(Visit visit) =>
      Visit.db.insertRow(_session(), visit, transaction: _transaction);

  @override
  Future<Visit> update(Visit visit) =>
      Visit.db.updateRow(_session(), visit, transaction: _transaction);
}
