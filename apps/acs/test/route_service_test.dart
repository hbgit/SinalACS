import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:sinalacs_acs/core/services/route_service.dart';

void main() {
  const service = RouteService(arrivalThresholdKm: 0.15);
  const destination = LatLng(-15.7942, -47.8828);

  test('sem origem ou destino informa que o geofence está indisponível', () {
    expect(
      service.arrivalStatus(origin: null, destination: destination),
      ArrivalStatus.unavailable,
    );
    expect(
      service.arrivalStatus(origin: destination, destination: null),
      ArrivalStatus.unavailable,
    );
  });

  test('fora do raio mantém o ACS a caminho', () {
    const origin = LatLng(-15.79, -47.88);

    expect(
      service.arrivalStatus(origin: origin, destination: destination),
      ArrivalStatus.approaching,
    );
    expect(
      service.distanceToDestination(origin: origin, destination: destination),
      greaterThan(service.arrivalThresholdKm),
    );
  });

  test('dentro do raio marca o ACS como chegado', () {
    expect(
      service.arrivalStatus(origin: destination, destination: destination),
      ArrivalStatus.arrived,
    );
    expect(
      service.distanceToDestination(origin: destination, destination: destination),
      0,
    );
  });
}
