import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Mesmo tamanho de célula usado em `apps/patient/lib/core/privacy/location_cell.dart`.
/// Os dois PRECISAM concordar: é o dispositivo do paciente que calcula a
/// célula, o ACS só a desenha.
const double cellSizeDegrees = 0.01;

/// Raio (metros) do círculo de incerteza desenhado no mapa — aproximação
/// fixa para a diagonal de uma célula de 0.01°, suficiente para o desenho,
/// não para cálculo geodésico exato.
const double cellRadiusMeters = 800;

/// Reconstrói o centro de uma célula `"latCell:lngCell"` publicada pelo
/// backend. Devolve `null` para célula ausente ou malformada — o mapa deve
/// tratar isso como "sem localização", nunca inventar um ponto.
LatLng? parseLocationCell(String? cell) {
  if (cell == null || cell.isEmpty) return null;
  final parts = cell.split(':');
  if (parts.length != 2) return null;

  final latCell = int.tryParse(parts[0]);
  final lngCell = int.tryParse(parts[1]);
  if (latCell == null || lngCell == null) return null;

  final centerLat = (latCell + 0.5) * cellSizeDegrees;
  final centerLng = (lngCell + 0.5) * cellSizeDegrees;
  return LatLng(centerLat, centerLng);
}
