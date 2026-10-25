import 'package:serverpod/serverpod.dart';

/// Adulteração da trilha como o adversário privilegiado da §458 de
/// `spec/lgpd_design.md`: um superusuário do Postgres, que desliga os
/// triggers da sessão com `session_replication_role = replica`. O trigger
/// append-only da #82 não para esse adversário — é ele que a cadeia HMAC
/// existe para detectar, e é o que os testes de detecção precisam simular.
///
/// O `SET LOCAL` dura até o fim da transação EXTERNA (o harness com rollback
/// transforma esta transação num savepoint, e o `RELEASE` não o desfaz), então
/// o `finally` volta a `origin`: sem isso o resto do teste rodaria sem trigger
/// e esconderia uma regressão.
Future<T> comoSuperusuario<T>(
  Session session,
  Future<T> Function(Transaction transaction) corpo,
) {
  return session.db.transaction((transaction) async {
    await session.db.unsafeExecute(
      'SET LOCAL session_replication_role = replica',
      transaction: transaction,
    );
    try {
      return await corpo(transaction);
    } finally {
      await session.db.unsafeExecute(
        'SET LOCAL session_replication_role = origin',
        transaction: transaction,
      );
    }
  });
}

/// Um comando só, pelo mesmo caminho de [comoSuperusuario].
Future<void> adulterarComoSuperusuario(
  Session session,
  String sql, {
  QueryParameters? parameters,
}) {
  return comoSuperusuario(
    session,
    (transaction) => session.db.unsafeExecute(
      sql,
      parameters: parameters,
      transaction: transaction,
    ),
  );
}
