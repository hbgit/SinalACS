/// Modelos e contrato de dados do backoffice.
///
/// Os campos espelham os modelos reais do backend (`backend/sinalacs_server/lib/src/models/*.spy.yaml`)
/// para que trocar [MockAdminDataSource] por uma implementação sobre o `sinalacs_client`
/// não exija remodelar as telas.
library;

/// Espelha `RiskLevel` de `models/enums/risk_level.spy.yaml`.
enum RiskLevel { red, yellow, green }

/// Espelha `AlertStatus` de `models/enums/alert_status.spy.yaml`.
enum AlertStatus { pending, acknowledged, resolved, escalated }

class DashboardIndicators {
  const DashboardIndicators({
    required this.countsByRisk,
    required this.openRedAlerts,
    required this.acknowledgedRedAlerts,
    required this.tmravSeconds,
  });

  final Map<RiskLevel, int> countsByRisk;
  final int openRedAlerts;
  final int acknowledgedRedAlerts;

  /// Tempo Médio de Resposta a Alerta Vermelho (métrica North Star do PRD §1.3).
  final int tmravSeconds;
}

/// Vínculo ACS ↔ microárea, para a listagem somente leitura da issue.
/// Espelha `MicroArea` (`micro_area.spy.yaml`) e `Acs` (`acs.spy.yaml`).
class MicroAreaSummary {
  const MicroAreaSummary({
    required this.id,
    required this.name,
    required this.acsName,
    required this.acsEnrollmentId,
    required this.acsActive,
  });

  final String id;
  final String name;
  final String acsName;
  final String acsEnrollmentId;
  final bool acsActive;
}

/// Espelha `Alert` (`alert.spy.yaml`). `patientLabel` é um identificador
/// minimizado (não o nome do paciente) — o backoffice é o cliente que mais
/// toca dado sensível (spec/lgpd_design.md), então a listagem evita PII
/// desnecessária para o que a issue pede (consulta, não atendimento).
class AlertSummary {
  const AlertSummary({
    required this.id,
    required this.patientLabel,
    required this.microAreaName,
    required this.riskLevel,
    required this.status,
    required this.triggeredAt,
  });

  final String id;
  final String patientLabel;
  final String microAreaName;
  final RiskLevel riskLevel;
  final AlertStatus status;
  final DateTime triggeredAt;
}

/// Espelha `AuditLog` (`audit_log.spy.yaml`).
class AuditLogEntry {
  const AuditLogEntry({
    required this.id,
    required this.userLabel,
    required this.actionType,
    required this.resourceType,
    required this.timestamp,
    required this.result,
  });

  final String id;
  final String userLabel;
  final String actionType;
  final String resourceType;
  final DateTime timestamp;
  final String result;
}

/// Camada de dados isolada atrás de interface (no espírito de `AlertPublisher`/
/// `AlertStore` do backend), para permitir mock enquanto os endpoints reais
/// não existem no `sinalacs_client`.
abstract interface class AdminDataSource {
  Future<DashboardIndicators> fetchDashboardIndicators();

  Future<List<MicroAreaSummary>> fetchMicroAreas();

  Future<List<AlertSummary>> fetchAlerts({String? microAreaName, AlertStatus? status});

  Future<List<AuditLogEntry>> fetchAuditLogs();

  /// Registra o próprio acesso do admin a uma tela sensível (PRD §4.2.2:
  /// "Administrador (Sistema): R (auditado)").
  Future<void> recordAccess({required String actionType, required String resourceType});
}
