/// Tamanho da célula em graus (~1,1 km na latitude). Constante de produto
/// para o MVP — a decisão registra que o tamanho por UBS/microárea é
/// parâmetro de configuração futuro, fora do escopo desta tarefa.
/// Ver docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md §1.2.
const double cellSizeDegrees = 0.01;

/// Deriva uma célula geográfica de baixa resolução a partir de uma
/// coordenada, para o mapa do ACS desenhar uma área de incerteza — nunca um
/// ponto exato.
///
/// **LGPD:** ao contrário de `locationHashFrom`, isto não é um hash — é uma
/// coordenada arredondada, legível pelo servidor. É por isso que a célula é
/// deliberadamente maior (~1,1 km) do que a resolução usada para o hash de
/// idempotência: o hash serve para deduplicar o MESMO ponto, a célula serve
/// só para desenhar uma região no mapa.
String locationCellFrom(double latitude, double longitude) {
  final latCell = (latitude / cellSizeDegrees).floor();
  final lngCell = (longitude / cellSizeDegrees).floor();
  return '$latCell:$lngCell';
}
