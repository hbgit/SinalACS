/// O que a tela de lembretes precisa saber e fazer sobre o banco local (#136).
///
/// Interface estreita de propósito (R12): a interface do usuário nunca depende
/// do `PatientLocalDatabase` concreto, e o teste de widget injeta um duplo,
/// como faz com `PatientBackend`. Implementada por `PatientLocalDatabase`.
abstract interface class LocalDataControl {
  /// `true` se esta execução recomeçou o banco porque a chave se perdeu.
  bool get recoveredFromLostKey;

  /// Devolve `true` uma única vez por execução depois de uma recuperação por
  /// chave perdida, e `false` dali em diante. É o que faz o aviso aparecer uma
  /// vez só, mesmo que a tela de lembretes seja aberta de novo.
  bool consumeRecoveryNotice();

  /// Tenta abrir o banco de novo. Lança `LocalDatabaseUnavailableException`
  /// se ainda não abrir.
  Future<void> retryOpen();

  /// "Apagar e recomeçar": apaga o banco, os laterais, a chave e os arquivos
  /// antigos em claro. Lança `LocalDatabaseUnavailableException` se falhar.
  Future<void> deleteEverything();
}
