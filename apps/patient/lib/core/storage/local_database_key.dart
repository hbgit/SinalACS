import 'dart:math';

/// Estado da chave do banco local, como a custódia a informa.
///
/// **Nunca registre a chave em log**, nem em mensagem de erro (LGPD-RF09).
sealed class LocalKeyState {}

/// A chave está disponível. [rawKey] vem no formato do SQLCipher,
/// `x'<64 hex>'`.
final class KeyAvailable extends LocalKeyState {
  KeyAvailable(this.rawKey);

  final String rawKey;

  @override
  String toString() => 'KeyAvailable(<oculta>)';
}

/// Fase 2: a chave exige o PIN. Nunca é produzido na Fase 1.
final class KeyLocked extends LocalKeyState {}

/// A custódia respondeu "não há chave" para um banco que existe.
final class KeyLost extends LocalKeyState {}

/// A leitura lançou: transitório até prova em contrário.
final class KeyUnavailable extends LocalKeyState {}

/// O banco local não pôde ser aberto ou a chave não pôde ser gravada.
///
/// Sem mensagem de origem de propósito: a causa pode carregar material da
/// custódia.
class LocalDatabaseUnavailableException implements Exception {
  const LocalDatabaseUnavailableException();

  @override
  String toString() => 'LocalDatabaseUnavailableException';
}

abstract interface class LocalDatabaseKeyProvider {
  /// Sem banco e sem chave: cria, grava e devolve [KeyAvailable].
  /// Com banco e sem chave: [KeyLost] (não cria). Leitura que lança:
  /// [KeyUnavailable] (não cria, não apaga).
  Future<LocalKeyState> obtain({required bool databaseExists});

  /// Apaga a chave e qualquer envelope.
  Future<void> destroy();
}

/// Gera a chave raw do SQLCipher: `x'` + 64 hex de [Random.secure] + `'`.
String generateRawDatabaseKey() {
  final random = Random.secure();
  final hex = List<int>.generate(32, (_) => random.nextInt(256))
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return "x'$hex'";
}

/// Duplo de teste: mantém a chave só em memória.
///
/// Controle para testes: [obtainCalls] conta as chamadas a [obtain];
/// [forceNext] enfileira estados devolvidos, um por chamada e na ordem, antes
/// de a lógica normal voltar a valer (ex.: `forceNext([KeyUnavailable()])` faz
/// a 1ª chamada falhar e a 2ª seguir normal). Um estado forçado não cria nem
/// apaga a chave. Sem chave e com `databaseExists: true`, devolve [KeyLost].
class InMemoryDatabaseKeyProvider implements LocalDatabaseKeyProvider {
  InMemoryDatabaseKeyProvider({String? initialKey}) : _key = initialKey;

  String? _key;
  final List<LocalKeyState> _forced = [];

  int obtainCalls = 0;

  /// Enfileira [states] para as próximas chamadas de [obtain].
  void forceNext(Iterable<LocalKeyState> states) => _forced.addAll(states);

  @override
  Future<LocalKeyState> obtain({required bool databaseExists}) async {
    obtainCalls++;
    if (_forced.isNotEmpty) return _forced.removeAt(0);
    final existing = _key;
    if (existing != null) return KeyAvailable(existing);
    if (databaseExists) return KeyLost();
    return KeyAvailable(_key = generateRawDatabaseKey());
  }

  @override
  Future<void> destroy() async => _key = null;
}
