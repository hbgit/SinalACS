import 'package:serverpod/serverpod.dart';

/// Namespaces dos advisory locks por titular. A forma de duas chaves de
/// `pg_advisory_xact_lock(int, int)` não compartilha espaço com a de uma chave
/// (`OrmAuditTrail`), então um `hashtext` nunca colide com a cadeia de auditoria.
const int lockNamespaceDeletion = 1;
const int lockNamespaceTerms = 2;
/// Push: 3 serializa por titular (consentimento × token), 4 por token.
const int lockNamespacePushToken = 3;
const int lockNamespacePushTokenRow = 4;
/// Token de envio diferido: serializa a troca por (usuário, aparelho).
const int lockNamespaceUploadToken = 5;

/// Serializa, dentro de [transaction], quem disputa a mesma [key] no mesmo
/// [namespace]. Solta sozinho no fim da transação.
Future<void> lockPerSubject(
  Session session,
  Transaction transaction, {
  required int namespace,
  required String key,
}) async {
  await session.db.unsafeExecute(
    'SELECT pg_advisory_xact_lock(@ns::int, hashtext(@key));',
    parameters: QueryParameters.named({'ns': namespace, 'key': key}),
    transaction: transaction,
  );
}
