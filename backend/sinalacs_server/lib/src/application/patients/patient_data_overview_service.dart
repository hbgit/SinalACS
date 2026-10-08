import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/authorization.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// Um consentimento do próprio titular, do jeito que a store enxerga — sem o
/// formato de transporte do endpoint.
class ConsentRecordSnapshot {
  const ConsentRecordSnapshot({
    required this.purpose,
    required this.action,
    required this.version,
    required this.timestamp,
  });

  final String purpose;
  final String action;
  final String version;
  final DateTime timestamp;
}

/// Um evento de classificação de risco do próprio titular, de triagem ou de
/// alerta.
class RiskEventSnapshot {
  const RiskEventSnapshot({
    required this.source,
    required this.riskLevel,
    required this.recordedAt,
  });

  /// 'triage' ou 'alert'.
  final String source;
  final RiskLevel riskLevel;
  final DateTime recordedAt;
}

/// Um pedido do próprio titular (LGPD-RF08: exclusão ou correção), do jeito
/// que a store enxerga — `details` já decifrado.
class DataSubjectRequestSnapshot {
  const DataSubjectRequestSnapshot({
    required this.id,
    required this.type,
    required this.status,
    required this.details,
    required this.createdAt,
    required this.dueAt,
    this.resolution,
  });

  final String id;
  final DataSubjectRequestType type;
  final DataSubjectRequestStatus status;

  /// Texto do pedido de correção; `null` num pedido de exclusão.
  final String? details;
  final DateTime createdAt;
  final DateTime dueAt;

  /// Nota de resposta ou motivo da recusa do backoffice (#42), já decifrada;
  /// `null` enquanto o pedido não foi decidido (ou foi atendido sem nota). Só
  /// chega ao próprio titular.
  final String? resolution;
}

/// Tudo que o painel "Meus Dados" mostra sobre o próprio paciente.
class PatientDataSnapshot {
  const PatientDataSnapshot({
    required this.name,
    required this.birthDate,
    required this.emergencyContact,
    required this.isChronic,
    required this.chronicConditions,
    required this.consents,
    required this.riskHistory,
    this.requests = const [],
  });

  final String name;
  final DateTime birthDate;
  final String emergencyContact;
  final bool isChronic;
  final List<String> chronicConditions;
  final List<ConsentRecordSnapshot> consents;
  final List<RiskEventSnapshot> riskHistory;

  /// Mais recente primeiro.
  final List<DataSubjectRequestSnapshot> requests;
}

/// Consulta a tudo que compõe o painel "Meus Dados" de um único paciente.
///
/// Mesmo padrão de `PatientDirectoryStore`: interface aqui, implementação ORM
/// em `infrastructure/`, para o serviço ser testável sem Postgres.
abstract interface class PatientDataOverviewStore {
  /// `null` só é alcançável se o token carregar um id sem linha
  /// correspondente em `patients` — não deveria acontecer com um token
  /// válido.
  Future<PatientDataSnapshot?> loadFor(String patientId);
}

/// Painel "Meus Dados" (LGPD, spec/lgpd_design.md linhas 417/581-595):
/// confirmação de existência de tratamento e acesso aos próprios dados.
class PatientDataOverviewService {
  PatientDataOverviewService({
    required PatientDataOverviewStore store,
    required AuditTrail audit,
  })  : _store = store,
        _audit = audit;

  final PatientDataOverviewStore _store;
  final AuditTrail _audit;

  /// `patientId` vem SEMPRE de `user.id` — nunca de parâmetro — pelo mesmo
  /// motivo de INV-05 em `triage.evaluate`: aceitar um id do cliente deixaria
  /// um paciente ler o prontuário de outro.
  ///
  /// `requireMicroArea: false`, mesmo motivo de `RedAlertService.statusFor`:
  /// o escopo é o próprio titular pelo `user.id` do token, não o território.
  Future<PatientDataSnapshot> myData(AuthenticatedUser user) async {
    Authorization.require(
      user,
      roles: {UserRole.patient},
      onDenied: () =>
          StateError('Somente pacientes podem consultar os próprios dados.'),
      requireMicroArea: false,
    );

    final snapshot = await _store.loadFor(user.id);

    await _audit.recordSafely(AuditEvent(
      userId: user.id,
      actionType: 'read',
      resourceType: 'patient_data_overview',
      result: 'granted',
    ));

    if (snapshot == null) {
      throw StateError('Paciente não encontrado.');
    }
    return snapshot;
  }
}
