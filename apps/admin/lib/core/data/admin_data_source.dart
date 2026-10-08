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
  /// `null` = nenhum alerta vermelho reconhecido na janela: sem amostra não há
  /// média, e `0` seria uma resposta instantânea que nunca aconteceu.
  final int? tmravSeconds;
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

/// Espelha `DataSubjectRequestType` (`enums/data_subject_request_type.spy.yaml`).
enum DataRequestType { deletion, correction }

/// Espelha `DataSubjectRequestStatus`. `completed` e `rejected` são finais.
enum DataRequestStatus { open, inReview, completed, rejected }

/// Limites da nota de resposta e do motivo de recusa, os mesmos do servidor
/// (`DataSubjectCaseService.notaMin/notaMax`), contados depois do `trim`.
const dataRequestTextMin = 3;
const dataRequestTextMax = 500;

/// Texto da falha de validação da nota/motivo. Fixo do app: a mensagem do
/// servidor não chega à tela.
const dataRequestTextInvalid = 'A resposta deve ter de $dataRequestTextMin a $dataRequestTextMax caracteres.';

/// Texto neutro para decisão recusada pelo servidor: corrida perdida, pedido
/// fora do escopo ou já decidido. Não diz se o pedido existe.
const dataRequestUnavailable = 'Pedido não encontrado ou já decidido. Atualize a lista.';

/// `true` quando [texto], sem espaços nas pontas, cabe em 3–500 caracteres.
bool dataRequestTextIsValid(String texto) {
  final t = texto.trim();
  return t.length >= dataRequestTextMin && t.length <= dataRequestTextMax;
}

/// Pedido do titular na fila do backoffice (#42). Espelha `AdminDataSubjectRequest`.
/// A lista **nunca** traz o texto do pedido: ele só é decifrado no detalhe.
/// [overdue] vem do servidor (aberto ou em análise e com o prazo passado).
class DataRequestSummary {
  const DataRequestSummary({
    required this.id,
    required this.type,
    required this.status,
    required this.createdAt,
    required this.dueAt,
    required this.overdue,
    required this.patientLabel,
  });

  final String id;
  final DataRequestType type;
  final DataRequestStatus status;
  final DateTime createdAt;
  final DateTime dueAt;
  final bool overdue;

  /// Rótulo minimizado (`Paciente #A18F`), nunca o nome.
  final String patientLabel;
}

/// Detalhe de um pedido, com o texto decifrado. Espelha
/// `AdminDataSubjectRequestDetail`; a leitura é auditada pelo servidor antes.
class DataRequestDetail extends DataRequestSummary {
  const DataRequestDetail({
    required super.id,
    required super.type,
    required super.status,
    required super.createdAt,
    required super.dueAt,
    required super.overdue,
    required super.patientLabel,
    this.details,
    this.resolution,
    this.decidedAt,
  });

  /// Texto livre do pedido de correção (exclusão não tem).
  final String? details;

  /// Nota de atendimento ou motivo da recusa, que o titular vê.
  final String? resolution;
  final DateTime? decidedAt;
}

/// Falha ao ler dados do backoffice. A mensagem já vem pronta para a tela e
/// nunca carrega o texto cru do servidor.
class AdminDataFailure implements Exception {
  const AdminDataFailure(this.message);
  final String message;

  @override
  String toString() => 'AdminDataFailure: $message';
}

/// O servidor recusou o token (401): a sessão venceu no meio da chamada. As telas
/// levam ao login em vez de oferecer "Tentar novamente", que falharia de novo.
class AdminSessionExpired implements Exception {
  const AdminSessionExpired();

  @override
  String toString() => 'AdminSessionExpired';
}

/// Camada de dados isolada atrás de interface (no espírito de `AlertPublisher`/
/// `AlertStore` do backend), para permitir mock enquanto os endpoints reais
/// não existem no `sinalacs_client`.
abstract interface class AdminDataSource {
  Future<DashboardIndicators> fetchDashboardIndicators();

  Future<List<MicroAreaSummary>> fetchMicroAreas();

  /// [microAreaId] é o `MicroAreaSummary.id` (o servidor filtra por id, não por
  /// nome). Mais recentes primeiro; [limit] de 1 a 100.
  Future<List<AlertSummary>> fetchAlerts({
    String? microAreaId,
    AlertStatus? status,
    int limit = 50,
    int offset = 0,
  });

  Future<List<AuditLogEntry>> fetchAuditLogs({int limit = 50});

  /// Registra o próprio acesso do admin a uma tela sensível (PRD §4.2.2:
  /// "Administrador (Sistema): R (auditado)").
  Future<void> recordAccess({required String actionType, required String resourceType});

  /// Pedidos do titular, na ordem do servidor (prazo crescente). [status]
  /// `null` = todos.
  Future<List<DataRequestSummary>> fetchDataRequests({DataRequestStatus? status, int limit = 50, int offset = 0});

  /// Detalhe com o texto decifrado.
  Future<DataRequestDetail> fetchDataRequest(String id);

  /// `open → inReview`.
  Future<void> startDataRequestReview(String id);

  /// Atende o pedido. Correção exige [note]; exclusão anonimiza o titular.
  Future<void> completeDataRequest(String id, {String? note});

  /// Recusa com motivo de 3 a 500 caracteres, que o titular vê.
  Future<void> rejectDataRequest(String id, {required String reason});
}
