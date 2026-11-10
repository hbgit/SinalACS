/// Trilha local de eventos do aparelho (C-04, #127).
///
/// Guarda só o que `spec/requisitos_piloto.md` §INV-03 no piloto pede: o tipo
/// do evento, a data e hora e a versão do motor. **Nunca** as respostas da
/// autoavaliação, em claro ou não. Mesmo assim o evento é dado de saúde (revela
/// que a pessoa recebeu a orientação de maior gravidade), por isso mora no banco
/// cifrado do app (`PatientLocalDatabase`, #136) e nunca sai do aparelho.
///
/// A expiração em 30 dias e o "Apagar meus dados" são da C-10 (#131); o
/// `deleteEverything()` do banco já leva a trilha junto.
library;

/// Tipos de evento da trilha. Conjunto fechado: um tipo novo é uma decisão de
/// privacidade, não um detalhe de implementação.
enum LocalEventKind {
  /// A orientação "Ligar 192" da autoavaliação foi exibida. Nenhum pedido de
  /// contato foi gerado por ela (P-09).
  call192OrientationShown('orientacao_192_exibida');

  const LocalEventKind(this.code);

  /// Valor gravado no banco; estável entre versões do app.
  final String code;

  static LocalEventKind? fromCode(String code) {
    for (final kind in values) {
      if (kind.code == code) return kind;
    }
    return null;
  }
}

class LocalEvent {
  const LocalEvent({
    required this.kind,
    required this.occurredAt,
    required this.engineVersion,
  });

  final LocalEventKind kind;

  /// Instante do evento, em UTC.
  final DateTime occurredAt;

  /// Versão da árvore de decisão que produziu a saída.
  final String engineVersion;

  @override
  bool operator ==(Object other) =>
      other is LocalEvent &&
      other.kind == kind &&
      other.occurredAt == occurredAt &&
      other.engineVersion == engineVersion;

  @override
  int get hashCode => Object.hash(kind, occurredAt, engineVersion);

  @override
  String toString() => 'LocalEvent(${kind.code}, $occurredAt, $engineVersion)';
}

abstract interface class LocalEventLog {
  /// Grava [event]. Lança `LocalDatabaseUnavailableException` se o banco não
  /// abre; quem chama decide (a tela da orientação nunca espera por isto).
  Future<void> record(LocalEvent event);

  /// Os eventos gravados, do mais antigo para o mais novo.
  Future<List<LocalEvent>> list();
}

/// Trilha em memória, para testes.
class InMemoryLocalEventLog implements LocalEventLog {
  final List<LocalEvent> _events = [];

  @override
  Future<void> record(LocalEvent event) async => _events.add(event);

  @override
  Future<List<LocalEvent>> list() async => List.unmodifiable(_events);
}
