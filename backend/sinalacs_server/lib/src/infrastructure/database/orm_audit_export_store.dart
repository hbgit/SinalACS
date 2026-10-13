import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/admin/admin_read_service.dart';
import 'package:sinalacs_server/src/application/admin/audit_export_service.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_admin_read_store.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_data_subject_case_store.dart'
    show AuditAppender;

/// Exportação da auditoria (#45, Task 10) sobre Postgres.
///
/// A leitura reusa o SQL da página do backoffice ([OrmAdminReadStore]): mesmo
/// filtro, mesmo selo, escopo de sistema, keyset `sequence < head + 1` — "o
/// recorte" é um só texto para a tela e para o arquivo. A gravação é uma
/// transação: `audit_exports` e o apêndice à cadeia ([AuditAppender], em
/// produção `OrmAuditTrail.recordInTransaction`, que toma o lock da cadeia
/// por último).
class OrmAuditExportStore implements AuditExportStore {
  OrmAuditExportStore({
    required Session Function() session,
    required AuditAppender appendAudit,
  }) : _session = session,
       _appendAudit = appendAudit,
       _leitura = OrmAdminReadStore(session: session);

  final Session Function() _session;
  final AuditAppender _appendAudit;
  final OrmAdminReadStore _leitura;

  static const _sistema = AdminScope.system();

  @override
  Future<String?> ubsOf(String staffId) => _leitura.ubsOf(staffId);

  @override
  Future<int> headSequence() async {
    final ultima = await AuditLog.db.findFirstRow(
      _session(),
      orderBy: (t) => t.sequence,
      orderDescending: true,
    );
    return ultima?.sequence ?? 0;
  }

  @override
  Future<int> countUpTo(
    AdminAuditFilter filter, {
    required int headSequence,
    required int cap,
  }) => _leitura.auditLogsCount(
    _sistema,
    filter: filter,
    beforeSequence: headSequence + 1,
    cap: cap,
  );

  @override
  Future<List<AdminAuditRow>> readUpTo(
    AdminAuditFilter filter, {
    required int headSequence,
    required int limit,
  }) async {
    final pagina = await _leitura.auditLogs(
      _sistema,
      filter: filter,
      limit: limit,
      beforeSequence: headSequence + 1,
    );
    // A página vem em `sequence DESC`; o arquivo é cronológico.
    return pagina.items.reversed.toList();
  }

  @override
  Future<void> commitExport(AuditExport registro, AuditEvent evento) {
    final session = _session();
    return session.db.transaction((transaction) async {
      await AuditExport.db.insertRow(
        session,
        registro,
        transaction: transaction,
      );
      await _appendAudit(session, transaction, evento);
    });
  }
}
