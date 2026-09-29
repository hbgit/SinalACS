import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/triage/triage_session_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/encrypted_json.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/health_data_cipher.dart';

/// Implementação de [TriageSessionStore] sobre o ORM do Serverpod.
///
/// `TriageSession.patientId` tem chave estrangeira para `patients`, então a
/// gravação falha se o paciente do token não existir no banco — é o que
/// garante que uma triagem nunca fique órfã de prontuário.
///
/// É aqui que as respostas da triagem viram ciphertext: o serviço entrega um
/// [TriageSessionRecord] em claro e este store serializa para JSON, cifra e
/// monta a linha persistida (RNF03, INV-04). `application/` não constrói mais
/// o `TriageSession` gerado justamente para não precisar conhecer o par
/// `answersEncrypted`/`answersKeyVersion`.
class OrmTriageSessionStore implements TriageSessionStore {
  OrmTriageSessionStore({
    required Session Function() session,
    required HealthDataCipher cipher,
    Transaction? transaction,
  })  : _session = session,
        _cipher = cipher,
        _transaction = transaction;

  final Session Function() _session;
  final HealthDataCipher _cipher;
  final Transaction? _transaction;

  @override
  Future<UuidValue?> insert(TriageSessionRecord session) async {
    final encrypted = await _cipher.encryptJson(
      [for (final answer in session.answers) answer.toJson()],
    );

    final stored = await TriageSession.db.insertRow(
      _session(),
      TriageSession(
        patientId: session.patientId,
        answersEncrypted: encrypted.ciphertextBase64,
        answersKeyVersion: encrypted.keyVersion,
        resultRisk: session.resultRisk,
        resultDisplay: session.resultDisplay,
        createdAt: session.createdAt,
        deviceId: session.deviceId,
      ),
      transaction: _transaction,
    );
    return stored.id;
  }
}
