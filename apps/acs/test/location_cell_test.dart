import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/geo/location_cell.dart';

void main() {
  group('parseLocationCell', () {
    test('converte "latCell:lngCell" no centro da célula', () {
      final center = parseLocationCell('-1580:-4783');
      expect(center, isNotNull);
      expect(center!.latitude, closeTo(-15.795, 0.001));
      expect(center.longitude, closeTo(-47.825, 0.001));
    });

    test('devolve null para célula ausente', () {
      expect(parseLocationCell(null), isNull);
    });

    test('devolve null para formato inválido, sem lançar', () {
      expect(parseLocationCell('não-é-uma-célula'), isNull);
      expect(parseLocationCell(''), isNull);
    });
  });

  test('cellRadiusMeters é positivo e cobre a diagonal da célula', () {
    expect(cellRadiusMeters, greaterThan(0));
  });
}
