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

/// A única coisa que o resolvedor precisa saber sobre o mundo: a UBS do
/// coordenador. Porta estreita, cumprida tanto pela leitura (`OrmAdminReadStore`)
/// quanto pela gestão de contas (issue #43).
abstract interface class AdminScopeStore {
  /// UBS do coordenador (`staff_accounts.ubsId`), ou `null` se não houver.
  Future<String?> ubsOf(String staffId);
}

/// A regra única de papel e escopo do backoffice (PRD §4.2.2), extraída do
/// `AdminReadService` para servir também à gestão de contas (issue #43).
///
/// 1. **Papel:** só `coordinator` e `admin` ([Authorization.staffRoles]); `acs` e
///    `patient` são recusados mesmo com token válido.
/// 2. **Escopo:** o administrador vê o sistema; o coordenador, a UBS de
///    `staff_accounts.ubsId`. Coordenador sem UBS é recusado (fail-closed).
/// 3. **Recusa auditada, fail-closed:** toda recusa grava uma linha `read` com
///    `result: denied` **antes** de lançar, e com `record` (não `recordSafely`):
///    se a linha não grava, a exceção da trilha sobe no lugar da recusa.
class AdminScopeResolver {
  AdminScopeResolver({required this.store, required this.audit});

  final AdminScopeStore store;
  final AuditTrail audit;

  /// A mesma recusa para todos os papéis e todos os recursos, para não revelar
  /// por que o acesso foi barrado.
  static const negado = 'acesso restrito ao backoffice';

  /// O escopo de [user] para [recurso] (usado nas linhas de auditoria), ou a
  /// recusa auditada.
  Future<AdminScope> resolve(
    AuthenticatedUser user, {
    required String recurso,
  }) async {
    if (!Authorization.staffRoles.contains(user.role)) {
      return _negar(user, recurso);
    }
    if (user.role == UserRole.admin) return const AdminScope.system();
    final ubs = await store.ubsOf(user.id);
    if (ubs == null) return _negar(user, recurso);
    return AdminScope.ubs(ubs);
  }

  /// Exige o papel `admin`: usado pelo que o coordenador não pode ver nem fazer,
  /// mesmo dentro da própria UBS.
  Future<void> requireAdmin(
    AuthenticatedUser user, {
    required String recurso,
  }) async {
    if (user.role != UserRole.admin) {
      await _negar(user, recurso);
    }
  }

  Future<Never> _negar(AuthenticatedUser user, String recurso) async {
    await audit.record(
      AuditEvent(
        userId: user.id,
        actionType: 'read',
        resourceType: recurso,
        result: 'denied',
      ),
    );
    throw AlertPermissionException(message: negado);
  }
}
