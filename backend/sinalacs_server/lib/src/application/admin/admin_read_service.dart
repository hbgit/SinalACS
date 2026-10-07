import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/authorization.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// Até onde o chamador enxerga no backoffice (PRD §4.2.2): o administrador vê o
/// sistema inteiro; o coordenador, só a sua UBS.
class AdminScope {
  const AdminScope.system() : ubsId = null;
  const AdminScope.ubs(String this.ubsId);

  /// `null` = sistema inteiro.
  final String? ubsId;
}

/// Leitura do backoffice. Interface à parte do ORM, no espírito de
/// `AlertStore`: o serviço e seus testes não conhecem SQL.
abstract interface class AdminReadStore {
  /// Contagens por risco e TMRAV no escopo. O TMRAV olha os 30 dias anteriores
  /// a [now]; sem alerta vermelho reconhecido na janela, `tmravSeconds` é nulo.
  Future<AdminIndicators> indicators(AdminScope scope, {required DateTime now});

  Future<List<AdminMicroArea>> microAreas(AdminScope scope);

  /// Mais recentes primeiro (`triggeredAt` desc, `id` desc: ordem estável).
  /// `nextOffset` nulo = fim da lista.
  Future<AdminAlertPage> alerts(
    AdminScope scope, {
    String? microAreaId,
    AlertStatus? status,
    required int limit,
    required int offset,
  });

  /// Mais recentes primeiro, por keyset (`sequence` menor que [beforeSequence]).
  Future<AdminAuditPage> auditLogs({required int limit, int? beforeSequence});

  /// UBS do coordenador (`staff_accounts.ubsId`), ou `null` se não houver.
  Future<String?> ubsOf(String staffId);
}

/// Regras de leitura do backoffice (issue #40).
///
/// 1. **Papel:** só `coordinator` e `admin` ([Authorization.staffRoles]); `acs` e
///    `patient` são recusados mesmo com token válido, e a recusa é auditada.
/// 2. **Escopo:** o administrador vê o sistema; o coordenador, a UBS de
///    `staff_accounts.ubsId`. Coordenador sem UBS é recusado (fail-closed), em
///    **todos** os métodos.
/// 3. **Auditoria antes do dado:** cada leitura grava uma linha `read` e só então
///    consulta o store. `record` (não `recordSafely`): se a linha não grava, a
///    exceção sobe e nenhum dado sai.
/// 4. **Paginação:** `limit` de 1 a 100, `offset` não negativo; fora disso,
///    [AdminInvalidRequestException] (não é erro de permissão).
///
/// A auditoria de logs é só do administrador: filtrar logs por UBS exige juntar
/// `users` a `micro_areas` e fica para a issue #43.
class AdminReadService {
  AdminReadService({
    required this.store,
    required this.audit,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AdminReadStore store;
  final AuditTrail audit;
  final DateTime Function() _clock;

  static const maxLimit = 100;
  static const _negado = 'acesso restrito ao backoffice';
  static const _paginacaoInvalida = 'Parâmetro de paginação inválido.';

  Future<AdminIndicators> indicators(AuthenticatedUser user) async {
    final escopo = await _escopo(user, 'admin_indicators');
    await _auditar(user, 'admin_indicators', 'success');
    return store.indicators(escopo, now: _clock().toUtc());
  }

  Future<List<AdminMicroArea>> microAreas(AuthenticatedUser user) async {
    final escopo = await _escopo(user, 'admin_micro_areas');
    await _auditar(user, 'admin_micro_areas', 'success');
    return store.microAreas(escopo);
  }

  Future<AdminAlertPage> alerts(
    AuthenticatedUser user, {
    String? microAreaId,
    AlertStatus? status,
    int limit = 50,
    int offset = 0,
  }) async {
    final escopo = await _escopo(user, 'admin_alerts');
    _validarPagina(limit, offset);
    await _auditar(user, 'admin_alerts', 'success');
    return store.alerts(
      escopo,
      microAreaId: microAreaId,
      status: status,
      limit: limit,
      offset: offset,
    );
  }

  Future<AdminAuditPage> auditLogs(
    AuthenticatedUser user, {
    int limit = 50,
    int? beforeSequence,
  }) async {
    const recurso = 'admin_audit_logs';
    if (user.role != UserRole.admin) {
      await _auditar(user, recurso, 'denied');
      throw AlertPermissionException(message: _negado);
    }
    _validarPagina(limit, 0);
    await _auditar(user, recurso, 'success');
    return store.auditLogs(limit: limit, beforeSequence: beforeSequence);
  }

  Future<AdminScope> _escopo(AuthenticatedUser user, String recurso) async {
    if (!Authorization.staffRoles.contains(user.role)) {
      await _auditar(user, recurso, 'denied');
      throw AlertPermissionException(message: _negado);
    }
    if (user.role == UserRole.admin) return const AdminScope.system();
    final ubs = await store.ubsOf(user.id);
    if (ubs == null) {
      await _auditar(user, recurso, 'denied');
      throw AlertPermissionException(message: _negado);
    }
    return AdminScope.ubs(ubs);
  }

  void _validarPagina(int limit, int offset) {
    if (limit < 1 || limit > maxLimit || offset < 0) {
      throw AdminInvalidRequestException(message: _paginacaoInvalida);
    }
  }

  Future<void> _auditar(
    AuthenticatedUser user,
    String recurso,
    String result,
  ) => audit.record(
    AuditEvent(
      userId: user.id,
      actionType: 'read',
      resourceType: recurso,
      result: result,
    ),
  );
}
