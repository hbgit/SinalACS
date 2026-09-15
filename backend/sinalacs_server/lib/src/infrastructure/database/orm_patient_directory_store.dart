import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/patients/patient_directory_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// Implementação de [PatientDirectoryStore] sobre o ORM do Serverpod.
///
/// `Patient` não guarda `microAreaId` — ela vive em `users`, e `Patient.id` É
/// o UUID do usuário (mesma decisão de chave documentada em
/// `models/patient.spy.yaml`). Por isso a consulta é em duas etapas: primeiro
/// os `users` da microárea com papel `patient`, depois os `patients` cujo
/// `id` está nesse conjunto — não há relação declarada entre as duas tabelas
/// para um join automático do ORM.
class OrmPatientDirectoryStore implements PatientDirectoryStore {
  OrmPatientDirectoryStore({required Session Function() session}) : _session = session;

  final Session Function() _session;

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

    return [
      for (final patient in patients)
        PatientDirectoryEntry(
          patientId: patient.id!.uuid,
          // O nome vive em `users`; `patients` não o duplica.
          name: namesById[patient.id] ?? '',
          isChronic: patient.isChronic,
          chronicConditions: patient.chronicConditions,
        ),
    ];
  }
}
