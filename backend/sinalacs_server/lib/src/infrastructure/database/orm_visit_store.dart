import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/visits/visit_sync_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/encrypted_json.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/health_data_cipher.dart';

/// Implementação de [VisitStore] sobre o ORM do Serverpod.
///
/// Segue o mesmo arranjo de [OrmAlertStore]: a sessão é obtida por chamada, e
/// não guardada no construtor, porque o Serverpod amarra o ciclo de vida da
/// conexão à `Session` da requisição.
///
/// É também a única fronteira que conhece a cifragem de `visits.notes`
/// (RNF03, INV-04): [VisitSyncService] trafega [VisitRecord] com `notes` em
/// claro nos dois sentidos — inclusive no `pull`, porque o ACS do território é
/// justamente quem tem legitimidade para lê-las — e este store converte de e
/// para o par `notesEncrypted`/`notesKeyVersion`.
class OrmVisitStore implements VisitStore {
  OrmVisitStore({
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
  Future<VisitRecord?> findByLocalId(String localId) async {
    // `visits.localId` tem índice único (visits_local_id_key), então esta busca
    // é o ponto de deduplicação do reenvio de um lote.
    final visit = await Visit.db.findFirstRow(
      _session(),
      where: (visit) => visit.localId.equals(UuidValue.fromString(localId)),
      transaction: _transaction,
    );
    if (visit == null) return null;
    return _toRecord(visit);
  }

  @override
  Future<VisitRecord> insert(VisitRecord visit) async {
    final row = await Visit.db.insertRow(
      _session(),
      await _toRow(visit),
      transaction: _transaction,
    );
    // Reaproveita as notas em claro que o chamador já tem: decifrar de volta o
    // que acabamos de cifrar seria trabalho puro de ida e volta.
    return _toRecord(row, notes: visit.notes);
  }

  @override
  Future<VisitRecord> update(VisitRecord visit) async {
    final row = await Visit.db.updateRow(
      _session(),
      await _toRow(visit),
      transaction: _transaction,
    );
    return _toRecord(row, notes: visit.notes);
  }

  @override
  Future<UuidValue?> microAreaOfPatient(UuidValue patientId) async {
    // `Patient.id` É o UUID do usuário (mesma decisão de `patient.spy.yaml`),
    // então a microárea vem de `users`, não de `patients`.
    final user = await User.db.findFirstRow(
      _session(),
      where: (t) => t.id.equals(patientId),
      transaction: _transaction,
    );
    return user?.microAreaId;
  }

  @override
  Future<List<VisitRecord>> listChangedInMicroArea(
    UuidValue microAreaId,
    DateTime since,
  ) async {
    final session = _session();

    // Mesmo arranjo em duas etapas de `OrmPatientDirectoryStore`: `visits` só
    // guarda `patientId`, e a microárea do paciente vive em `users`, não em
    // `patients` — não há relação declarada entre as tabelas para um JOIN
    // automático do ORM.
    final users = await User.db.find(
      session,
      where: (t) => t.microAreaId.equals(microAreaId) & t.role.equals(UserRole.patient),
      transaction: _transaction,
    );
    if (users.isEmpty) return const [];

    final patientIds = {for (final user in users) user.id!}.cast<UuidValue>();

    final visits = await Visit.db.find(
      session,
      where: (t) => t.patientId.inSet(patientIds) & (t.syncAt > since),
      orderBy: (t) => t.syncAt,
      transaction: _transaction,
    );

    // Laço, e não list literal: decifrar é assíncrono.
    final records = <VisitRecord>[];
    for (final visit in visits) {
      records.add(await _toRecord(visit));
    }
    return records;
  }

  Future<Visit> _toRow(VisitRecord record) async {
    final encrypted = await _cipher.encryptJson(record.notes);
    return Visit(
      id: record.id,
      patientId: record.patientId,
      acsId: record.acsId,
      scheduledAt: record.scheduledAt,
      startedAt: record.startedAt,
      completedAt: record.completedAt,
      status: record.status,
      riskLevelBefore: record.riskLevelBefore,
      riskLevelAfter: record.riskLevelAfter,
      notesEncrypted: encrypted.ciphertextBase64,
      notesKeyVersion: encrypted.keyVersion,
      syncStatus: record.syncStatus,
      arrivalMethod: record.arrivalMethod,
      localId: record.localId,
      syncAt: record.syncAt,
      version: record.version,
    );
  }

  Future<VisitRecord> _toRecord(Visit row, {Map<String, String>? notes}) async {
    final decoded = notes ??
        ((await _cipher.decryptJson(row.notesEncrypted, row.notesKeyVersion))
                as Map<String, dynamic>?)
            ?.cast<String, String>();
    return VisitRecord(
      id: row.id,
      patientId: row.patientId,
      acsId: row.acsId,
      scheduledAt: row.scheduledAt,
      startedAt: row.startedAt,
      completedAt: row.completedAt,
      status: row.status,
      riskLevelBefore: row.riskLevelBefore,
      riskLevelAfter: row.riskLevelAfter,
      notes: decoded ?? const {},
      syncStatus: row.syncStatus,
      arrivalMethod: row.arrivalMethod,
      localId: row.localId,
      syncAt: row.syncAt,
      version: row.version,
    );
  }
}
