import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/onboarding/consent_signature.dart';
import 'package:sinalacs_server/src/application/onboarding/onboarding_service.dart'
    show ConsentLogEntry;
import 'package:sinalacs_server/src/application/patients/data_subject_rights_service.dart';
import 'package:sinalacs_server/src/application/patients/patient_data_overview_service.dart'
    show DataSubjectRequestSnapshot;
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
  Future<void> recordConsent(ConsentLogEntry entry) async {
    await ConsentLog.db.insertRow(
      _session(),
      signedConsentLog(entry, signature: _signature, origin: 'painel-titular'),
    );
  }

  @override
  Future<DataSubjectRequestSnapshot?> findOpenRequest(
    String userId,
    DataSubjectRequestType type,
  ) async {
    final row = await DataSubjectRequest.db.findFirstRow(
      _session(),
      where: (t) =>
          t.userId.equals(UuidValue.fromString(userId)) &
          t.requestType.equals(type) &
          t.status.equals(DataSubjectRequestStatus.open),
      orderBy: (t) => t.createdAt,
      orderDescending: true,
    );
    return row == null ? null : dataSubjectRequestSnapshotOf(row, _cipher);
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
