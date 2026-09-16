import 'package:sinalacs_admin/core/data/admin_data_source.dart';

/// Duplo de teste que permite forçar falha em qualquer método, uma vez.
///
/// Existe para provar o comportamento de erro/retry das telas (achado da
/// revisão do PR: `FutureBuilder` sem `hasError` deixava erro parecer "vazio"
/// ou spinner infinito). Cada campo `failNext*` é consumido uma única vez, o
/// que permite testar "falha, depois usuário tenta de novo e funciona".
class FailingAdminDataSource implements AdminDataSource {
  FailingAdminDataSource({required this.inner});

  final AdminDataSource inner;

  bool failNextIndicators = false;
  bool failNextMicroAreas = false;
  bool failNextAlerts = false;
  bool failNextAuditLogs = false;
  bool failNextRecordAccess = false;

  int recordAccessCalls = 0;

  @override
  Future<DashboardIndicators> fetchDashboardIndicators() async {
    if (failNextIndicators) {
      failNextIndicators = false;
      throw StateError('falha simulada: indicadores');
    }
    return inner.fetchDashboardIndicators();
  }

  @override
  Future<List<MicroAreaSummary>> fetchMicroAreas() async {
    if (failNextMicroAreas) {
      failNextMicroAreas = false;
      throw StateError('falha simulada: microáreas');
    }
    return inner.fetchMicroAreas();
  }

  @override
  Future<List<AlertSummary>> fetchAlerts({String? microAreaName, AlertStatus? status}) async {
    if (failNextAlerts) {
      failNextAlerts = false;
      throw StateError('falha simulada: alertas');
    }
    return inner.fetchAlerts(microAreaName: microAreaName, status: status);
  }

  @override
  Future<List<AuditLogEntry>> fetchAuditLogs() async {
    if (failNextAuditLogs) {
      failNextAuditLogs = false;
      throw StateError('falha simulada: auditoria');
    }
    return inner.fetchAuditLogs();
  }

  @override
  Future<void> recordAccess({required String actionType, required String resourceType}) async {
    recordAccessCalls++;
    if (failNextRecordAccess) {
      failNextRecordAccess = false;
      throw StateError('falha simulada: recordAccess');
    }
    return inner.recordAccess(actionType: actionType, resourceType: resourceType);
  }
}
