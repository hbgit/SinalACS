import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/patients/patient_data_overview_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/encrypted_json.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/health_data_cipher.dart';

/// Implementação de [PatientDataOverviewStore] sobre o ORM do Serverpod.
///
/// Agrega quatro consultas independentes — `patients`, `users`,
/// `consent_logs` e o histórico de risco de `triage_sessions`/`alerts` — num
/// único snapshot. Só decifra `chronicConditionsEncrypted`; o conteúdo bruto
/// de uma triagem (`answersEncrypted`) e a localização de um alerta nunca
/// entram no snapshot, por minimização (spec/lgpd_design.md).
class OrmPatientDataOverviewStore implements PatientDataOverviewStore {
  OrmPatientDataOverviewStore({
    required Session Function() session,
    required HealthDataCipher cipher,
  })  : _session = session,
        _cipher = cipher;

  final Session Function() _session;
  final HealthDataCipher _cipher;

  @override
  Future<PatientDataSnapshot?> loadFor(String patientId) async {
    final id = UuidValue.fromString(patientId);
    final session = _session();

    final patient = await Patient.db.findById(session, id);
    if (patient == null) return null;
    final user = await User.db.findById(session, id);

    final decoded = await _cipher.decryptJson(
      patient.chronicConditionsEncrypted,
      patient.chronicConditionsKeyVersion,
    );
    final chronicConditions =
        decoded == null ? const <String>[] : (decoded as List).cast<String>();

    final consentRows = await ConsentLog.db.find(
      session,
      where: (t) => t.userId.equals(id),
      orderBy: (t) => t.timestamp,
    );
    final triageRows = await TriageSession.db.find(
      session,
      where: (t) => t.patientId.equals(id),
      orderBy: (t) => t.createdAt,
    );
    final alertRows = await Alert.db.find(
      session,
      where: (t) => t.patientId.equals(id),
      orderBy: (t) => t.triggeredAt,
    );

    final riskHistory = <RiskEventSnapshot>[
      for (final row in triageRows)
        RiskEventSnapshot(source: 'triage', riskLevel: row.resultRisk, recordedAt: row.createdAt),
      for (final row in alertRows)
        RiskEventSnapshot(source: 'alert', riskLevel: row.riskLevel, recordedAt: row.triggeredAt),
    ]..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));

    return PatientDataSnapshot(
      // `patients.id` É `users.id` (mesma chave, ver `patient.spy.yaml`), então
      // `user` só vem `null` se o schema estiver inconsistente — não deveria
      // acontecer; `??` é defesa, não o caminho esperado. `Patient` não tem
      // `createdAt`, por isso o epoch como sentinela óbvio de dado ausente.
      name: user?.name ?? '',
      birthDate: user?.birthDate ?? DateTime.utc(1970),
      emergencyContact: patient.emergencyContact,
      isChronic: patient.isChronic,
      chronicConditions: chronicConditions,
      consents: [
        for (final row in consentRows)
          ConsentRecordSnapshot(
            purpose: row.purpose,
            action: row.action,
            version: row.version,
            timestamp: row.timestamp,
          ),
      ],
      riskHistory: riskHistory,
    );
  }
}
