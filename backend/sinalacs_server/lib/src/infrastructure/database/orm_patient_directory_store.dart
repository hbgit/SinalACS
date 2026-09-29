import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/patients/patient_directory_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/encrypted_json.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/health_data_cipher.dart';

/// Implementação de [PatientDirectoryStore] sobre o ORM do Serverpod.
///
/// `Patient` não guarda `microAreaId` — ela vive em `users`, e `Patient.id` É
/// o UUID do usuário (mesma decisão de chave documentada em
/// `models/patient.spy.yaml`). Por isso a consulta é em duas etapas: primeiro
/// os `users` da microárea com papel `patient`, depois os `patients` cujo
/// `id` está nesse conjunto — não há relação declarada entre as duas tabelas
/// para um join automático do ORM.
///
/// É aqui — e só aqui — que `chronicConditions` deixa de ser ciphertext e
/// volta a ser `List<String>`: [PatientDirectoryStore] e
/// [PatientDirectoryService] continuam ignorando que a coluna é cifrada
/// (RNF03, INV-04).
///
/// [updateChronicConditions] é a escrita que esta nota costumava dizer que
/// não existia: `cipher.encryptJson(conditions)` gravando o par
/// `chronicConditionsEncrypted`/`chronicConditionsKeyVersion`, mesma simetria
/// que `bin/seed_health_data.dart` já usava para o seed.
class OrmPatientDirectoryStore implements PatientDirectoryStore {
  OrmPatientDirectoryStore({
    required Session Function() session,
    required HealthDataCipher cipher,
  })  : _session = session,
        _cipher = cipher;

  final Session Function() _session;
  final HealthDataCipher _cipher;

  @override
  Future<List<PatientDirectoryEntry>> listByMicroArea(String microAreaId) async {
    final areaId = UuidValue.fromString(microAreaId);

    final users = await User.db.find(
      _session(),
      where: (t) => t.microAreaId.equals(areaId) & t.role.equals(UserRole.patient),
    );
    if (users.isEmpty) return const [];

    final userIds = {for (final user in users) user.id!}.cast<UuidValue>();
    final patients = await Patient.db.find(
      _session(),
      where: (t) => t.id.inSet(userIds),
    );

    final namesById = {for (final user in users) user.id!: user.name};

    // Laço, e não list literal: decifrar é assíncrono.
    final entries = <PatientDirectoryEntry>[];
    for (final patient in patients) {
      entries.add(PatientDirectoryEntry(
        patientId: patient.id!.uuid,
        // O nome vive em `users`; `patients` não o duplica.
        name: namesById[patient.id] ?? '',
        isChronic: patient.isChronic,
        chronicConditions: await _decryptConditions(patient),
      ));
    }
    return entries;
  }

  Future<List<String>> _decryptConditions(Patient patient) async {
    final decoded = await _cipher.decryptJson(
      patient.chronicConditionsEncrypted,
      patient.chronicConditionsKeyVersion,
    );
    if (decoded == null) return const [];
    return (decoded as List).cast<String>();
  }

  @override
  Future<PatientDirectoryEntry?> findById(String patientId) async {
    final patient = await Patient.db.findById(
      _session(),
      UuidValue.fromString(patientId),
    );
    if (patient == null) return null;

    final user = await User.db.findById(_session(), patient.id!);

    return PatientDirectoryEntry(
      patientId: patient.id!.uuid,
      name: user?.name ?? '',
      isChronic: patient.isChronic,
      chronicConditions: await _decryptConditions(patient),
    );
  }

  // A ESCRITA que a nota da classe (acima) previa: simétrica à leitura —
  // `cipher.encryptJson` no lugar de `_decryptConditions`, gravando o par
  // `chronicConditionsEncrypted`/`chronicConditionsKeyVersion` — e nada mais
  // do `Patient` muda, porque só isso é o que esta escrita representa.
  @override
  Future<void> updateChronicConditions({
    required String patientId,
    required List<String> conditions,
  }) async {
    final session = _session();
    final id = UuidValue.fromString(patientId);
    final patient = await Patient.db.findById(session, id);
    if (patient == null) {
      throw StateError('Paciente $patientId não encontrado.');
    }

    final encrypted = await _cipher.encryptJson(conditions);
    patient
      ..chronicConditionsEncrypted = encrypted.ciphertextBase64
      ..chronicConditionsKeyVersion = encrypted.keyVersion;
    await Patient.db.updateRow(session, patient);
  }
}
