import 'dart:io';

import 'package:sinalacs_client/sinalacs_client.dart' as api;

import 'admin_data_source.dart';

/// [AdminDataSource] sobre o `admin.*` do backend (issue #40).
///
/// Os enums do cliente têm os mesmos nomes dos do app (`RiskLevel`,
/// `AlertStatus`) e por isso entram com o prefixo `api.`; a tradução é por
/// **nome**, nunca por índice.
///
/// O servidor audita cada leitura em `audit_logs` antes de devolver o dado, então
/// [recordAccess] não faz nada: chamar o servidor de novo gravaria a mesma
/// leitura duas vezes.
///
/// As falhas viram [AdminDataFailure] com texto próprio: a mensagem do servidor
/// (que descreve o motivo da recusa) não vai para a tela.
class BackendAdminDataSource implements AdminDataSource {
  BackendAdminDataSource(this._admin, {required String accessToken})
    : _accessToken = accessToken;

  final api.EndpointAdmin _admin;
  final String _accessToken;

  @override
  Future<DashboardIndicators> fetchDashboardIndicators() => _guard(() async {
    final r = await _admin.indicators(accessToken: _accessToken);
    return DashboardIndicators(
      countsByRisk: {
        RiskLevel.red: r.red,
        RiskLevel.yellow: r.yellow,
        RiskLevel.green: r.green,
      },
      openRedAlerts: r.openRedAlerts,
      acknowledgedRedAlerts: r.acknowledgedRedAlerts,
      tmravSeconds: r.tmravSeconds,
    );
  });

  @override
  Future<List<MicroAreaSummary>> fetchMicroAreas() => _guard(() async {
    final lista = await _admin.microAreas(accessToken: _accessToken);
    return [
      for (final m in lista)
        MicroAreaSummary(
          id: m.id,
          name: m.name,
          acsName: m.acsName,
          acsEnrollmentId: m.acsEnrollmentId,
          acsActive: m.acsActive,
        ),
    ];
  });

  @override
  Future<List<AlertSummary>> fetchAlerts({
    String? microAreaId,
    AlertStatus? status,
    int limit = 50,
    int offset = 0,
  }) => _guard(() async {
    final pagina = await _admin.alerts(
      accessToken: _accessToken,
      microAreaId: microAreaId,
      status: status == null
          ? null
          : api.AlertStatus.values.byName(status.name),
      limit: limit,
      offset: offset,
    );
    return [
      for (final a in pagina.items)
        AlertSummary(
          id: a.id,
          patientLabel: 'Paciente ${a.patientLabel}',
          microAreaName: a.microAreaName,
          riskLevel: RiskLevel.values.byName(a.riskLevel.name),
          status: AlertStatus.values.byName(a.status.name),
          triggeredAt: a.triggeredAt,
        ),
    ];
  });

  @override
  Future<List<AuditLogEntry>> fetchAuditLogs({int limit = 50}) =>
      _guard(() async {
        final pagina = await _admin.auditLogs(
          accessToken: _accessToken,
          limit: limit,
        );
        return [
          for (final e in pagina.items)
            AuditLogEntry(
              id: e.id,
              userLabel: e.userLabel,
              actionType: e.actionType,
              resourceType: e.resourceType,
              timestamp: e.timestamp,
              result: e.result,
            ),
        ];
      });

  @override
  Future<void> recordAccess({
    required String actionType,
    required String resourceType,
  }) async {}

  Future<T> _guard<T>(Future<T> Function() chamada) async {
    try {
      return await chamada();
    } on api.ServerpodClientUnauthorized {
      throw const AdminSessionExpired();
    } on api.AlertPermissionException {
      throw const AdminDataFailure('Acesso restrito ao backoffice.');
    } on api.AdminInvalidRequestException {
      throw const AdminDataFailure('Parâmetro de paginação inválido.');
    } on SocketException {
      throw const AdminDataFailure('Não foi possível conectar ao servidor.');
    }
  }
}
