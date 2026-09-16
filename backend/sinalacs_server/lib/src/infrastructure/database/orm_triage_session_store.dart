import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/triage/triage_session_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// Implementação de [TriageSessionStore] sobre o ORM do Serverpod.
///
/// `TriageSession.patientId` tem chave estrangeira para `patients`, então a
/// gravação falha se o paciente do token não existir no banco — é o que
/// garante que uma triagem nunca fique órfã de prontuário.
class OrmTriageSessionStore implements TriageSessionStore {
  OrmTriageSessionStore({
    required Session Function() session,
    Transaction? transaction,
  })  : _session = session,
        _transaction = transaction;

  final Session Function() _session;
  final Transaction? _transaction;

  @override
  Future<TriageSession> insert(TriageSession session) => TriageSession.db.insertRow(
        _session(),
        session,
        transaction: _transaction,
      );
}
