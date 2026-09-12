import 'dart:math';

import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Estado do percurso calculado para o ACS.
enum RouteStatus { unavailable, active, complete }

/// Estado de proximidade do ACS em relação ao destino da visita.
enum ArrivalStatus { unavailable, approaching, arrived }

class RoutePlan {
  const RoutePlan({
    required this.points,
    required this.distanceKm,
    required this.etaMinutes,
    this.status = RouteStatus.active,
  });

  final List<LatLng> points;
  final double distanceKm;
  final int etaMinutes;
  final RouteStatus status;
}

class RouteService {
  const RouteService({this.speedKmh = 20, this.arrivalThresholdKm = 0.15});

  final double speedKmh;
  final double arrivalThresholdKm;

    double distanceToDestination({required LatLng origin, required LatLng destination}) =>
      _distanceBetween(origin, destination);

    ArrivalStatus arrivalStatus({required LatLng? origin, required LatLng? destination}) {
    if (origin == null || destination == null) return ArrivalStatus.unavailable;
    return isAtDestination(origin: origin, destination: destination)
      ? ArrivalStatus.arrived
      : ArrivalStatus.approaching;
    }

    bool isAtDestination({required LatLng origin, required LatLng destination}) =>
      distanceToDestination(origin: origin, destination: destination) <= arrivalThresholdKm;

  RoutePlan plan({required LatLng origin, required LatLng destination}) {
    final points = <LatLng>[];
    const segments = 6;
    for (var i = 0; i <= segments; i++) {
      final progress = i / segments;
      final lat = origin.latitude + (destination.latitude - origin.latitude) * progress;
      final lng = origin.longitude + (destination.longitude - origin.longitude) * progress;
      points.add(LatLng(lat, lng));
    }

    final distanceKm = distanceToDestination(origin: origin, destination: destination);
    final etaMinutes = distanceKm <= 0 ? 0 : (distanceKm / speedKmh * 60).round();
    final status = distanceKm <= arrivalThresholdKm ? RouteStatus.complete : RouteStatus.active;

    return RoutePlan(
      points: points,
      distanceKm: distanceKm,
      etaMinutes: etaMinutes,
      status: status,
    );
  }

  double _distanceBetween(LatLng origin, LatLng destination) {
    const earthRadiusKm = 6371.0;
    final lat1 = origin.latitude * pi / 180;
    final lat2 = destination.latitude * pi / 180;
    final deltaLat = (destination.latitude - origin.latitude) * pi / 180;
    final deltaLng = (destination.longitude - origin.longitude) * pi / 180;

    final a = (sin(deltaLat / 2) * sin(deltaLat / 2)) +
        (cos(lat1) * cos(lat2) * sin(deltaLng / 2) * sin(deltaLng / 2));
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }
}
