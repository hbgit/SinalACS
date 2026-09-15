import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// Um paciente da microárea, do jeito que a store enxerga — sem o formato de
/// transporte do endpoint.
class PatientDirectoryEntry {
  const PatientDirectoryEntry({
    required this.patientId,
    required this.name,
    required this.isChronic,
    required this.chronicConditions,
  });

  final String patientId;
  final String name;
  final bool isChronic;
  final List<String> chronicConditions;
}

/// Consulta aos pacientes de uma microárea.
///
/// Mesmo padrão de `AlertStore`/`VisitStore`: interface aqui, implementação
/// ORM em `infrastructure/`, para o serviço ser testável sem Postgres.
abstract interface class PatientDirectoryStore {
  Future<List<PatientDirectoryEntry>> listByMicroArea(String microAreaId);
}

/// Lista os pacientes da microárea de um ACS, para a rotina de visitas.
///
/// Existe porque o único produtor de alertas é `RedAlertService` — e ele só
/// publica `riskLevel: 'red'` (emergência, com SAMU). O PRD mede visita como
/// trabalho territorial de rotina (≥ 8/dia por ACS): sem uma lista de
/// pacientes, a "Visita" nunca teria de onde partir fora do caminho reativo.
class PatientDirectoryService {
  PatientDirectoryService({
    required PatientDirectoryStore store,
    required AuditTrail audit,
  }) : _store = store,
       _audit = audit;

  final PatientDirectoryStore _store;
  final AuditTrail _audit;

  /// A microárea vem SEMPRE do token, nunca de um parâmetro do método — aceitar
  /// um `microAreaId` do cliente seria oferecer ao dispositivo a chance de
  /// pedir outro território (INV-01).
  Future<List<MicroAreaPatient>> listForAcs(AuthenticatedUser user) async {
    if (user.role != UserRole.acs || user.microAreaId == null) {
      throw StateError('Somente ACS territorializados podem listar pacientes.');
    }

    final entries = await _store.listByMicroArea(user.microAreaId!);

    // Best-effort: uma trilha de auditoria que falha não pode impedir o ACS de
    // trabalhar. A leitura audita o EVENTO, não os pacientes retornados — listar
    // os UUIDs aqui recriaria o prontuário dentro do próprio log de auditoria.
    await _audit.recordSafely(AuditEvent(
      userId: user.id,
      actionType: 'read',
      resourceType: 'patient_directory',
      result: 'granted',
    ));

    return [
      for (final entry in entries)
        MicroAreaPatient(
          patientId: entry.patientId,
          name: entry.name,
          isChronic: entry.isChronic,
          chronicConditions: entry.chronicConditions,
        ),
    ];
  }
}
