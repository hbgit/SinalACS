import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/core/privacy/location_cell.dart';

void main() {
  group('locationCellFrom', () {
    test('agrupa coordenadas próximas na mesma célula', () {
      final a = locationCellFrom(-23.550520, -46.633308);
      final b = locationCellFrom(-23.550999, -46.633999);
      expect(a, b);
    });

    test('separa coordenadas em células diferentes', () {
      final a = locationCellFrom(-23.550520, -46.633308);
      final b = locationCellFrom(-23.560520, -46.633308);
      expect(a, isNot(b));
    });

    test('formato é "latCell:lngCell", nunca contém a coordenada em claro', () {
      final cell = locationCellFrom(-23.550520, -46.633308);
      expect(cell, matches(RegExp(r'^-?\d+:-?\d+$')));
      expect(cell, isNot(contains('23.55')));
      expect(cell, isNot(contains('46.63')));
    });

    test('é determinístico', () {
      expect(
        locationCellFrom(-23.550520, -46.633308),
        locationCellFrom(-23.550520, -46.633308),
      );
    });
  });
}
