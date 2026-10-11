import 'package:serverpod/serverpod.dart';

/// Prefixo que a exclusão atendida (#42, `OrmDataSubjectCaseStore`) grava em
/// `users.cpfHash` no lugar do HMAC do CPF: `removed:` + UUID aleatório, que
/// nunca casa com o hash de um CPF de verdade.
const removedCpfHashPrefix = 'removed:';

/// `true` se a conta [userId] foi anonimizada por uma exclusão atendida.
///
/// Existe para o JWT do paciente que ainda vive depois da anonimização (a
/// sessão dura 1 hora): sem esta consulta, ele continuaria abrindo pedidos e
/// gravando consentimentos de uma conta que não tem mais titular. É lida dentro
/// da transação de quem chama, depois do lock por titular, para não correr com
/// a anonimização, que segura os mesmos locks até o commit.
Future<bool> isRemovedAccount(
  Session session,
  UuidValue userId, {
  Transaction? transaction,
}) async {
  final rows = await session.db.unsafeQuery(
    'SELECT 1 FROM users WHERE id = @id::uuid AND starts_with("cpfHash", @prefixo)',
    parameters: QueryParameters.named({
      'id': userId.uuid,
      'prefixo': removedCpfHashPrefix,
    }),
    transaction: transaction,
  );
  return rows.isNotEmpty;
}
