import 'dart:async';
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
/// As falhas viram [AdminDataFailure] com texto próprio: o motivo de uma recusa
/// de acesso não vai para a tela. A exceção é a recusa de **validação** de uma
/// escrita, que fala da entrada do operador: essa vira [AdminValidationFailure]
/// carregando a mensagem do servidor (ver [_guardEscrita]).
class BackendAdminDataSource implements AdminDataSource {
  BackendAdminDataSource(
    this._admin, {
    required String accessToken,
    DateTime? expiresAt,
    DateTime Function()? now,
  }) : _accessToken = accessToken,
       _expiresAt = expiresAt,
       _now = now ?? DateTime.now;

  final api.EndpointAdmin _admin;
  final String _accessToken;

  /// Vencimento da sessão. O servidor não responde 401: recusa o token com
  /// `AlertPermissionException`, a mesma exceção da recusa por papel ou escopo.
  /// Só o relógio separa as duas: recusa depois do vencimento é sessão vencida.
  final DateTime? _expiresAt;
  final DateTime Function() _now;

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
  Future<List<AcsSummary>> fetchAcs() => _guard(() async {
    final lista = await _admin.acs(accessToken: _accessToken);
    return [for (final a in lista) _acsDoCliente(a)];
  });

  @override
  Future<List<StaffSummary>> fetchStaff() => _guard(() async {
    final lista = await _admin.staff(accessToken: _accessToken);
    return [
      for (final s in lista)
        StaffSummary(
          id: s.id,
          name: s.name,
          enrollmentId: s.enrollmentId,
          role: s.role.name,
          ubsName: s.ubsName,
          active: s.active,
          mfaActive: s.mfaActive,
        ),
    ];
  });

  @override
  Future<NewAcsCredential> createAcs({
    required String name,
    required String enrollmentId,
    required String microAreaId,
  }) => _guardEscrita(() async {
    final r = await _admin.createAcs(
      accessToken: _accessToken,
      name: name,
      enrollmentId: enrollmentId,
      microAreaId: microAreaId,
    );
    return NewAcsCredential(
      acs: _acsDoCliente(r.acs),
      initialPassword: r.initialPassword,
    );
  });

  @override
  Future<AcsSummary> setAcsMicroArea({
    required String acsId,
    required String microAreaId,
  }) => _guardEscrita(() async {
    final a = await _admin.setAcsMicroArea(
      accessToken: _accessToken,
      acsId: acsId,
      microAreaId: microAreaId,
    );
    return _acsDoCliente(a);
  });

  @override
  Future<AcsSummary> setAcsActive({
    required String acsId,
    required bool active,
  }) => _guardEscrita(() async {
    final a = await _admin.setAcsActive(
      accessToken: _accessToken,
      acsId: acsId,
      active: active,
    );
    return _acsDoCliente(a);
  });

  @override
  Future<String> resetAcsPassword({required String acsId}) =>
      _guardEscrita(() async {
        final r = await _admin.resetAcsPassword(
          accessToken: _accessToken,
          acsId: acsId,
        );
        return r.newPassword;
      });

  @override
  Future<void> resetAcsMfa({required String acsId}) => _guardEscrita(
    () => _admin.resetAcsMfa(accessToken: _accessToken, acsId: acsId),
  );

  @override
  Future<NewStaffActivation> resetStaffMfa({required String staffId}) =>
      _guardEscrita(() async {
        final r = await _admin.resetStaffMfa(
          accessToken: _accessToken,
          staffId: staffId,
        );
        return NewStaffActivation(
          code: r.activationCode,
          expiresAt: r.activationCodeExpiresAt,
        );
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
  Future<List<DataRequestSummary>> fetchDataRequests({
    DataRequestStatus? status,
    int limit = 50,
    int offset = 0,
  }) => _guard(() async {
    final pagina = await _admin.dataSubjectRequests(
      accessToken: _accessToken,
      status: status == null
          ? null
          : api.DataSubjectRequestStatus.values.byName(status.name),
      limit: limit,
      offset: offset,
    );
    // A ordem é a do servidor (prazo crescente): não reordena.
    return [
      for (final r in pagina.items)
        DataRequestSummary(
          id: r.id,
          type: DataRequestType.values.byName(r.type.name),
          status: DataRequestStatus.values.byName(r.status.name),
          createdAt: r.createdAt,
          dueAt: r.dueAt,
          overdue: r.overdue,
          patientLabel: 'Paciente ${r.patientLabel}',
        ),
    ];
  });

  @override
  Future<DataRequestDetail> fetchDataRequest(String id) => _guard(() async {
    final r = await _admin.dataSubjectRequest(accessToken: _accessToken, id: id);
    return DataRequestDetail(
      id: r.id,
      type: DataRequestType.values.byName(r.type.name),
      status: DataRequestStatus.values.byName(r.status.name),
      createdAt: r.createdAt,
      dueAt: r.dueAt,
      overdue: r.overdue,
      patientLabel: 'Paciente ${r.patientLabel}',
      details: r.details,
      resolution: r.resolution,
      decidedAt: r.decidedAt,
    );
  }, invalido: dataRequestUnavailable);

  @override
  Future<void> startDataRequestReview(String id) => _guard(
    () => _admin.startDataSubjectReview(accessToken: _accessToken, id: id),
    invalido: dataRequestUnavailable,
  );

  @override
  Future<void> completeDataRequest(String id, {String? note}) async {
    final nota = note == null ? null : _textoValidado(note);
    return _guard(
      () => _admin.completeDataSubjectRequest(
        accessToken: _accessToken,
        id: id,
        note: nota,
      ),
      invalido: dataRequestUnavailable,
    );
  }

  @override
  Future<void> rejectDataRequest(String id, {required String reason}) async {
    final motivo = _textoValidado(reason);
    return _guard(
      () => _admin.rejectDataSubjectRequest(
        accessToken: _accessToken,
        id: id,
        reason: motivo,
      ),
      invalido: dataRequestUnavailable,
    );
  }

  /// Valida a nota/motivo aqui, com o mesmo critério do servidor, para que a
  /// recusa por tamanho tenha texto próprio sem depender da mensagem do
  /// servidor. Assim toda `AdminInvalidRequestException` de uma decisão é o
  /// caso neutro (corrida perdida, fora do escopo, já decidido).
  static String _textoValidado(String texto) {
    if (!dataRequestTextIsValid(texto)) {
      throw const AdminDataFailure(dataRequestTextInvalid);
    }
    return texto.trim();
  }

  @override
  Future<void> recordAccess({
    required String actionType,
    required String resourceType,
  }) async {}

  /// [invalido] é o texto da tela para `AdminInvalidRequestException`, que o
  /// servidor usa tanto para paginação inválida (listas) quanto para decisão
  /// sobre pedido indisponível: cada chamada diz qual dos dois ela é.
  Future<T> _guard<T>(
    Future<T> Function() chamada, {
    String invalido = 'Parâmetro de paginação inválido.',
  }) async {
    try {
      return await chamada();
    } on api.ServerpodClientUnauthorized {
      throw const AdminSessionExpired();
    } on api.AlertPermissionException {
      final venceu = _expiresAt != null && !_now().isBefore(_expiresAt);
      if (venceu) throw const AdminSessionExpired();
      throw const AdminDataFailure('Acesso restrito ao backoffice.');
    } on api.AdminInvalidRequestException {
      throw AdminDataFailure(invalido);
    } on SocketException {
      throw const AdminDataFailure('Não foi possível conectar ao servidor.');
    } on TimeoutException {
      throw const AdminDataFailure('Não foi possível conectar ao servidor.');
    } on HandshakeException {
      throw const AdminDataFailure('Não foi possível conectar ao servidor.');
    } on api.ServerpodClientException catch (e) {
      // O cliente embrulha a SocketException em ServerpodClientException(-1).
      // Vem depois do Unauthorized, que é subtipo deste. Os outros status (500
      // etc.) seguem para o texto genérico da tela: não são falta de conexão.
      if (e.statusCode == -1) {
        throw const AdminDataFailure('Não foi possível conectar ao servidor.');
      }
      rethrow;
    }
  }

  /// Guarda das **escritas** (issue #43). É a das leituras com uma diferença que
  /// é o ponto todo: a mensagem de [api.AdminInvalidRequestException] descreve a
  /// entrada do próprio operador ('Já existe um ACS com esta matrícula.'), então
  /// ela vai à tela em [AdminValidationFailure]; nas leituras ela continua sendo
  /// só `'Parâmetro de paginação inválido.'`, porque ali o único parâmetro que o
  /// operador digita é a página.
  Future<T> _guardEscrita<T>(Future<T> Function() chamada) async {
    try {
      return await chamada();
    } on api.ServerpodClientUnauthorized {
      throw const AdminSessionExpired();
    } on api.AlertPermissionException {
      final venceu = _expiresAt != null && !_now().isBefore(_expiresAt);
      if (venceu) throw const AdminSessionExpired();
      throw const AdminDataFailure('Acesso restrito ao backoffice.');
    } on api.AdminInvalidRequestException catch (e) {
      throw AdminValidationFailure(e.message);
    } on SocketException {
      throw const AdminDataFailure('Não foi possível conectar ao servidor.');
    } on TimeoutException {
      throw const AdminDataFailure('Não foi possível conectar ao servidor.');
    } on HandshakeException {
      throw const AdminDataFailure('Não foi possível conectar ao servidor.');
    } on api.ServerpodClientException catch (e) {
      if (e.statusCode == -1) {
        throw const AdminDataFailure('Não foi possível conectar ao servidor.');
      }
      rethrow;
    }
  }
}

/// `AdminAcs` do cliente para o modelo do app. Só campos simples: os enums do
/// backoffice que exigem tradução por nome (`UserRole`) entram onde aparecem.
AcsSummary _acsDoCliente(api.AdminAcs a) => AcsSummary(
  id: a.id,
  name: a.name,
  enrollmentId: a.enrollmentId,
  ubsName: a.ubsName,
  microAreaId: a.microAreaId,
  microAreaName: a.microAreaName,
  active: a.active,
  mfaActive: a.mfaActive,
);
