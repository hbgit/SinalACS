import 'package:crypto/crypto.dart';
import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// Implementação de [AuditTrail] sobre o ORM do Serverpod.
///
/// `ipHash` nunca é o IP em claro — a §51 de spec/lgpd_design.md pede
/// "IP (anonimizado)", e o próprio nome do campo promete isso. Usa
/// `session.request.remoteInfo`, que o Serverpod já resolve corretamente atrás
/// de proxy (prefere `Forwarded`/`X-Forwarded-For` antes do endereço da
/// conexão) — decisivo aqui porque a stack tem Traefik na frente, e o endereço
/// da conexão seria sempre o do proxy, não o do ACS.
class OrmAuditTrail extends AuditTrail {
  OrmAuditTrail({required Session Function() session}) : _session = session;

  final Session Function() _session;

  @override
  Future<void> record(AuditEvent event) async {
    final session = _session();
    // Nulo em sessões sem requisição HTTP (ex.: tarefas internas). Nunca cai
    // para string vazia, que se confundiria com "IP resolvido, mas vazio" —
    // um marcador explícito deixa a ausência de request auditável também.
    final remoteInfo = session.request?.remoteInfo ?? 'sem-requisicao-http';

    await AuditLog.db.insertRow(
      session,
      AuditLog(
        userId: UuidValue.fromString(event.userId),
        actionType: event.actionType,
        resourceType: event.resourceType,
        resourceId: event.resourceId == null ? null : UuidValue.fromString(event.resourceId!),
        timestamp: DateTime.now().toUtc(),
        ipHash: sha256.convert(remoteInfo.codeUnits).toString(),
        result: event.result,
      ),
    );
  }
}
