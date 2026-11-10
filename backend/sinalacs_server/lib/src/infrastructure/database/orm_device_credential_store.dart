import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/auth/device_credential_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// Implementação de [DeviceCredentialStore] sobre o ORM do Serverpod (C-05).
///
/// A fronteira entre o login por credencial de dispositivo (`application/`)
/// e a tabela `patient_device_credentials`. Uma [Transaction] opcional faz a
/// criação participar da MESMA transação que consome o convite
/// (`OnboardingEndpoint.completeEnrollment`), como `OrmOnboardingStore`.
/// As semânticas presas contra o Postgres em
/// `test/integration/device_credential_login_test.dart`:
///
/// 1. [findByDeviceId] devolve a linha **com a microárea do titular relida
///    do banco** (join com `users`), para o JWT sair com o território do
///    cadastro — nunca de parâmetro do chamador (INV-01).
/// 2. [create] grava a linha nova com `lastUsedAt`/`revokedAt` nulos por
///    construção: uma credencial recém-emitida não pode nascer usada nem
///    revogada.
/// 3. [touchLastUsed] não ressuscita credencial revogada (o filtro mantém
///    `revokedAt IS NULL`: um aparelho revogado que loga não pode
///    "des-revogar" a própria marca).
class OrmDeviceCredentialStore implements DeviceCredentialStore {
  OrmDeviceCredentialStore({
    required Session Function() session,
    Transaction? transaction,
  })  : _session = session,
        _transaction = transaction;

  final Session Function() _session;
  final Transaction? _transaction;

  @override
  Future<StoredPatientDeviceCredential?> findByDeviceId(String deviceId) async {
    final session = _session();
    final rows = await session.db.unsafeQuery(
      '''
      SELECT
        c."id",
        c."patientId",
        c."deviceId",
        c."credentialHash",
        c."createdAt",
        c."lastUsedAt",
        c."revokedAt",
        u."microAreaId"
      FROM "patient_device_credentials" c
      JOIN "users" u ON u."id" = c."patientId"
      WHERE c."deviceId" = @deviceId
      LIMIT 2
      ''',
      parameters: QueryParameters.named({'deviceId': deviceId}),
      transaction: _transaction,
    );
    if (rows.isEmpty) return null;

    // O índice único de `deviceId` garante no máximo uma linha; `LIMIT 2` é a
    // asserção barata de que ele existe (semântica presa no teste de
    // integração: um índice perdido devolveria 2 e cairia aqui em vez de
    // logar com uma linha arbitrária).
    if (rows.length != 1) {
      throw StateError(
        'patient_device_credentials.deviceId não está único: $deviceId.',
      );
    }
    final row = rows.single;
    return StoredPatientDeviceCredential(
      id: UuidValue.fromString(row[0] as String).uuid,
      patientId: UuidValue.fromString(row[1] as String).uuid,
      deviceId: row[2] as String,
      credentialHash: row[3] as String,
      createdAt: row[4] as DateTime,
      lastUsedAt: row[5] as DateTime?,
      revokedAt: row[6] as DateTime?,
      microAreaId: row[7] == null ? null : UuidValue.fromString(row[7] as String).uuid,
    );
  }

  @override
  Future<void> create(StoredPatientDeviceCredential credential) async {
    final session = _session();
    await PatientDeviceCredential.db.insertRow(
      session,
      PatientDeviceCredential(
        patientId: UuidValue.fromString(credential.patientId),
        deviceId: credential.deviceId,
        credentialHash: credential.credentialHash,
        createdAt: credential.createdAt,
        lastUsedAt: null,
        revokedAt: null,
      ),
      transaction: _transaction,
    );
  }

  @override
  Future<void> touchLastUsed(String deviceId, DateTime at) async {
    final session = _session();
    final row = await PatientDeviceCredential.db.findFirstRow(
      session,
      where: (table) =>
          table.deviceId.equals(deviceId) & table.revokedAt.equals(null),
      transaction: _transaction,
    );
    if (row == null) return;
    row.lastUsedAt = at;
    await PatientDeviceCredential.db.updateRow(
      session,
      row,
      transaction: _transaction,
    );
  }
}
