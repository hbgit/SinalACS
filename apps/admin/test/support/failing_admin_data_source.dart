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

  /// Exceção específica lançada (uma vez) pela próxima leitura de dados, no
  /// lugar do `StateError` genérico: prova o tratamento de `AdminDataFailure` e
  /// `AdminSessionExpired` nas telas.
  Object? nextError;

  /// Falha depois do próximo frame (o pump avança o relógio antes de montar), como uma chamada de rede de
  /// verdade: um erro síncrono antes de o `FutureBuilder` assinar o `Future` é
  /// reportado como não tratado.
  Future<void> _lancaSeProgramado() async {
    final erro = nextError;
    if (erro == null) return;
    nextError = null;
    await Future<void>.delayed(const Duration(milliseconds: 150));
    throw erro;
  }

  @override
  Future<DashboardIndicators> fetchDashboardIndicators() async {
    await _lancaSeProgramado();
    if (failNextIndicators) {
      failNextIndicators = false;
      throw StateError('falha simulada: indicadores');
    }
    return inner.fetchDashboardIndicators();
  }

  @override
  Future<List<MicroAreaSummary>> fetchMicroAreas() async {
    await _lancaSeProgramado();
    if (failNextMicroAreas) {
      failNextMicroAreas = false;
      throw StateError('falha simulada: microáreas');
    }
    return inner.fetchMicroAreas();
  }

  @override
  Future<List<AlertSummary>> fetchAlerts({String? microAreaId, AlertStatus? status, int limit = 50, int offset = 0}) async {
    await _lancaSeProgramado();
    if (failNextAlerts) {
      failNextAlerts = false;
      throw StateError('falha simulada: alertas');
    }
    return inner.fetchAlerts(microAreaId: microAreaId, status: status, limit: limit, offset: offset);
  }

  @override
  Future<List<AuditLogEntry>> fetchAuditLogs({int limit = 50}) async {
    await _lancaSeProgramado();
    if (failNextAuditLogs) {
      failNextAuditLogs = false;
      throw StateError('falha simulada: auditoria');
    }
    return inner.fetchAuditLogs(limit: limit);
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
