import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/audit/audit_chain.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/rotating_ip_hasher.dart';

/// Implementação de [AuditTrail] sobre o ORM do Serverpod.
///
/// `ipHash` nunca é o IP em claro — a §51 de spec/lgpd_design.md pede
/// "IP (anonimizado)", e o próprio nome do campo promete isso. Usa
/// `session.request.remoteInfo`, que o Serverpod já resolve corretamente atrás
/// de proxy (prefere `Forwarded`/`X-Forwarded-For` antes do endereço da
/// conexão) — decisivo aqui porque a stack tem Traefik na frente, e o endereço
/// da conexão seria sempre o do proxy, não o do ACS. O valor gravado é um
/// HMAC-SHA-256 com chave rotativa diária derivada de `AUDIT_CHAIN_SECRET`
/// ([RotatingIpHasher]) — SHA-256 puro sobre um IPv4 (2^32 combinações) seria
/// reversível por rainbow table (spec/lgpd_data_audit.md §2.1).
///
/// Cada gravação também estende a cadeia de hash de `audit_logs` (LGPD-RT03):
/// lê a última linha e insere a próxima dentro da MESMA transação, sob um
/// advisory lock do Postgres — sem isso, duas gravações concorrentes leriam a
/// mesma última linha e encadeariam nela ao mesmo tempo, bifurcando a cadeia.
/// `pg_advisory_xact_lock` solta sozinho no fim da transação (commit ou
/// rollback), então não existe caminho que deixe o lock preso.
class OrmAuditTrail extends AuditTrail {
  OrmAuditTrail({
    required Session Function() session,
    required String chainSecret,
  })  : _session = session,
        _chain = AuditChain(secret: chainSecret),
        _ipHasher = RotatingIpHasher(secret: chainSecret);

  final Session Function() _session;
  final AuditChain _chain;
  final RotatingIpHasher _ipHasher;

  /// Chave arbitrária e fixa do advisory lock que serializa o apêndice à
  /// cadeia. Só precisa ser estável entre chamadas — não é derivada de nada.
  static const _chainLockKey = 725100823;

  @override
  Future<void> record(AuditEvent event) async {
    final session = _session();
    await session.db.transaction(
      (transaction) => recordInTransaction(session, transaction, event),
    );
  }

  /// O apêndice à cadeia dentro de uma transação que já existe, para quem
  /// precisa que a linha de auditoria e a mudança que ela descreve vivam ou
  /// morram juntas (o atendimento de pedidos do titular, #42): se esta
  /// gravação falhar, a transação de quem chamou é desfeita inteira.
  ///
  /// Toma o lock da cadeia por último: quem chama pode já segurar locks
  /// próprios (por pedido, por titular), mas nunca deve pedir outro depois
  /// deste — é essa ordem fixa que impede o deadlock.
  Future<void> recordInTransaction(
    Session session,
    Transaction transaction,
    AuditEvent event,
  ) async {
    // Nulo em sessões sem requisição HTTP (ex.: tarefas internas). Nunca cai
    // para string vazia, que se confundiria com "IP resolvido, mas vazio" —
    // um marcador explícito deixa a ausência de request auditável também.
    final remoteInfo = session.request?.remoteInfo ?? 'sem-requisicao-http';
    final ipHash = _ipHasher.hash(remoteInfo);
    final resourceId = event.resourceId;
    final timestamp = DateTime.now().toUtc();

    await session.db.unsafeExecute(
      'SELECT pg_advisory_xact_lock(@key);',
      parameters: QueryParameters.named({'key': _chainLockKey}),
      transaction: transaction,
    );

    final last = await AuditLog.db.findFirstRow(
      session,
      orderBy: (t) => t.sequence,
      orderDescending: true,
      transaction: transaction,
    );

    final sequence = (last?.sequence ?? 0) + 1;
    final previousHash = last?.entryHash ?? AuditChain.genesisHash;
    final entryHash = _chain.computeEntryHash(AuditChainFields(
      sequence: sequence,
      previousHash: previousHash,
      userId: event.userId,
      actionType: event.actionType,
      resourceType: event.resourceType,
      resourceId: resourceId,
      timestamp: timestamp,
      ipHash: ipHash,
      result: event.result,
    ));

    await AuditLog.db.insertRow(
      session,
      AuditLog(
        userId: UuidValue.fromString(event.userId),
        actionType: event.actionType,
        resourceType: event.resourceType,
        resourceId: resourceId == null ? null : UuidValue.fromString(resourceId),
        timestamp: timestamp,
        ipHash: ipHash,
        result: event.result,
        sequence: sequence,
        previousHash: previousHash,
        entryHash: entryHash,
      ),
      transaction: transaction,
    );
  }
}
