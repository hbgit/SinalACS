import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/onboarding/consent_signature.dart';
import 'package:sinalacs_server/src/application/onboarding/onboarding_service.dart'
    show ConsentLogEntry;
import 'package:sinalacs_server/src/application/patients/data_subject_rights_service.dart';
import 'package:sinalacs_server/src/application/patients/patient_data_overview_service.dart'
    show ConsentRecordSnapshot, DataSubjectRequestSnapshot;
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/encrypted_json.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/health_data_cipher.dart';
import 'package:sinalacs_server/src/infrastructure/database/signed_consent_log.dart';

/// Um pedido lido do banco, com `details` decifrado. Compartilhado com
/// `OrmPatientDataOverviewStore`, que lista os mesmos pedidos em "Meus Dados".
Future<DataSubjectRequestSnapshot> dataSubjectRequestSnapshotOf(
  DataSubjectRequest row,
  HealthDataCipher cipher,
) async =>
    DataSubjectRequestSnapshot(
      id: row.id!.uuid,
      type: row.requestType,
      status: row.status,
      details: await cipher.decryptJson(row.detailsEncrypted, row.detailsKeyVersion) as String?,
      createdAt: row.createdAt,
      dueAt: row.dueAt,
    );

/// Implementação de [DataSubjectRightsStore] sobre o ORM do Serverpod.
///
/// [chainSecret] é o mesmo `AUDIT_CHAIN_SECRET` que assina `consent_logs` no
/// onboarding (`OrmOnboardingStore`) — a linha sai de [signedConsentLog], a
/// mesma função, para as duas origens não divergirem.
class OrmDataSubjectRightsStore implements DataSubjectRightsStore {
  OrmDataSubjectRightsStore({
    required Session Function() session,
    required String chainSecret,
    required HealthDataCipher cipher,
  })  : _session = session,
        _signature = ConsentSignature(secret: chainSecret),
        _cipher = cipher;

  final Session Function() _session;
  final ConsentSignature _signature;
  final HealthDataCipher _cipher;

  @override
  Future<String> recordConsent(ConsentLogEntry entry) async {
    final row = await ConsentLog.db.insertRow(
      _session(),
      signedConsentLog(entry, signature: _signature, origin: 'painel-titular'),
    );
    return row.id!.uuid;
  }

  @override
  Future<ConsentRecordSnapshot?> latestConsent(String userId, ConsentPurpose purpose) async {
    final row = await ConsentLog.db.findFirstRow(
      _session(),
      where: (t) => t.userId.equals(UuidValue.fromString(userId)) & t.purpose.equals(purpose.name),
      orderBy: (t) => t.timestamp,
      orderDescending: true,
    );
    return row == null
        ? null
        : ConsentRecordSnapshot(
            purpose: row.purpose,
            action: row.action,
            version: row.version,
            timestamp: row.timestamp,
          );
  }

  /// Serializa por titular com `pg_advisory_xact_lock`, o mesmo recurso que
  /// `OrmAuditTrail` usa para a cadeia: o Serverpod não declara `WHERE` em
  /// índice, então um índice único parcial ("um pedido aberto por titular")
  /// não é possível. O lock solta sozinho no fim da transação.
  @override
  Future<({DataSubjectRequestSnapshot request, bool created})> createDeletionRequestIfNoneOpen({
    required String userId,
    required DateTime createdAt,
    required DateTime dueAt,
  }) async {
    final session = _session();
    final userUuid = UuidValue.fromString(userId);
    final encrypted = await _cipher.encryptJson(null);
    return session.db.transaction((transaction) async {
      await session.db.unsafeExecute(
        'SELECT pg_advisory_xact_lock(hashtext(@key));',
        parameters: QueryParameters.named({'key': 'exclusao:$userId'}),
        transaction: transaction,
      );
      final open = await DataSubjectRequest.db.findFirstRow(
        session,
        where: (t) =>
            t.userId.equals(userUuid) &
            t.requestType.equals(DataSubjectRequestType.deletion) &
            t.status.equals(DataSubjectRequestStatus.open),
        orderBy: (t) => t.createdAt,
        orderDescending: true,
        transaction: transaction,
      );
      if (open != null) {
        return (request: await dataSubjectRequestSnapshotOf(open, _cipher), created: false);
      }
      final row = await DataSubjectRequest.db.insertRow(
        session,
        DataSubjectRequest(
          userId: userUuid,
          requestType: DataSubjectRequestType.deletion,
          detailsEncrypted: encrypted.ciphertextBase64,
          detailsKeyVersion: encrypted.keyVersion,
          status: DataSubjectRequestStatus.open,
          createdAt: createdAt,
          dueAt: dueAt,
        ),
        transaction: transaction,
      );
      return (request: await dataSubjectRequestSnapshotOf(row, _cipher), created: true);
    });
  }

  @override
  Future<DataSubjectRequestSnapshot> createRequest({
    required String userId,
    required DataSubjectRequestType type,
    required String? details,
    required DateTime createdAt,
    required DateTime dueAt,
  }) async {
    // Cifra sempre, inclusive o `null` da exclusão: a coluna vazia fica
    // reservada para linha escrita fora do caminho Dart (ver `decryptJson`).
    final encrypted = await _cipher.encryptJson(details);
    final row = await DataSubjectRequest.db.insertRow(
      _session(),
      DataSubjectRequest(
        userId: UuidValue.fromString(userId),
        requestType: type,
        detailsEncrypted: encrypted.ciphertextBase64,
        detailsKeyVersion: encrypted.keyVersion,
        status: DataSubjectRequestStatus.open,
        createdAt: createdAt,
        dueAt: dueAt,
      ),
    );
    return dataSubjectRequestSnapshotOf(row, _cipher);
  }
}
