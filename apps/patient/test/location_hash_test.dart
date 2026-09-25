import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sinalacs_patient/core/privacy/location_hash.dart';

/// Duplo de [GeolocatorPlatform] para testar [GeolocatorLocationReader] sem
/// canal de plataforma — não há emulador nem GPS real no CI hermético.
class _FakeGeolocatorPlatform extends GeolocatorPlatform {
  _FakeGeolocatorPlatform({
    this.serviceEnabled = true,
    this.permission = LocationPermission.whileInUse,
    this.permissionAfterRequest,
    this.position,
    this.positionError,
  });

  bool serviceEnabled;
  LocationPermission permission;
  LocationPermission? permissionAfterRequest;
  Position? position;
  Object? positionError;

  int requestPermissionCalls = 0;
  LocationSettings? lastLocationSettings;

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async {
    requestPermissionCalls++;
    return permissionAfterRequest ?? permission;
  }

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) async {
    lastLocationSettings = locationSettings;
    final error = positionError;
    if (error != null) throw error;
    final result = position;
    if (result == null) {
      throw StateError('Nenhuma posição configurada no duplo de teste.');
    }
    return result;
  }
}

Position _positionAt(double latitude, double longitude) => Position(
      latitude: latitude,
      longitude: longitude,
      timestamp: DateTime.utc(2026, 1, 1),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

void main() {
  group('locationHashFrom', () {
    test('é determinístico para a mesma coordenada', () {
      final a = locationHashFrom(-23.55052, -46.633308);
      final b = locationHashFrom(-23.55052, -46.633308);
      expect(a, b);
    });

    test('trunca a precisão em 3 casas decimais', () {
      // Diferença na 4ª casa decimal (~11m) não deve mudar o hash.
      final a = locationHashFrom(-23.550, -46.633);
      final b = locationHashFrom(-23.5504, -46.6334);
      expect(a, b);
    });

    test('muda o hash para coordenadas realmente diferentes', () {
      final a = locationHashFrom(-23.550520, -46.633308);
      final b = locationHashFrom(-22.906847, -43.172897);
      expect(a, isNot(b));
    });

    test('nunca inclui latitude/longitude em texto simples', () {
      final hash = locationHashFrom(-23.550520, -46.633308);
      expect(hash, isNot(contains('23.55')));
      expect(hash, isNot(contains('46.63')));
    });
  });

  group('GeolocatorLocationReader', () {
    const reader = GeolocatorLocationReader();

    test('retorna o hash da posição quando a permissão já foi concedida', () async {
      final position = _positionAt(-23.550520, -46.633308);
      GeolocatorPlatform.instance = _FakeGeolocatorPlatform(position: position);

      final reading = await reader.read();

      expect(reading, isA<LocationAvailable>());
      expect(
        (reading as LocationAvailable).hash,
        locationHashFrom(position.latitude, position.longitude),
      );
    });

    test('solicita permissão quando ainda não concedida e usa o resultado', () async {
      final position = _positionAt(-23.550520, -46.633308);
      final fake = _FakeGeolocatorPlatform(
        permission: LocationPermission.denied,
        permissionAfterRequest: LocationPermission.whileInUse,
        position: position,
      );
      GeolocatorPlatform.instance = fake;

      final reading = await reader.read();

      expect(fake.requestPermissionCalls, 1);
      expect(reading, isA<LocationAvailable>());
    });

    test('sinaliza indisponível quando a permissão é negada', () async {
      GeolocatorPlatform.instance = _FakeGeolocatorPlatform(
        permission: LocationPermission.denied,
        permissionAfterRequest: LocationPermission.denied,
      );

      final reading = await reader.read();

      expect(reading, isA<LocationUnavailable>());
      expect(
        (reading as LocationUnavailable).reason,
        LocationUnavailableReason.permissionDenied,
      );
    });

    test('sinaliza indisponível quando a permissão foi negada permanentemente', () async {
      GeolocatorPlatform.instance = _FakeGeolocatorPlatform(
        permission: LocationPermission.deniedForever,
      );

      final reading = await reader.read();

      expect(reading, isA<LocationUnavailable>());
      expect(
        (reading as LocationUnavailable).reason,
        LocationUnavailableReason.permissionDenied,
      );
    });

    test('sinaliza indisponível quando o serviço de GPS está desligado', () async {
      GeolocatorPlatform.instance = _FakeGeolocatorPlatform(serviceEnabled: false);

      final reading = await reader.read();

      expect(reading, isA<LocationUnavailable>());
      expect(
        (reading as LocationUnavailable).reason,
        LocationUnavailableReason.serviceDisabled,
      );
    });

    test('sinaliza indisponível quando a leitura estoura o tempo limite', () async {
      GeolocatorPlatform.instance = _FakeGeolocatorPlatform(
        positionError: TimeoutException('sem resposta do GPS'),
      );

      final reading = await reader.read(timeout: const Duration(milliseconds: 1));

      expect(reading, isA<LocationUnavailable>());
      expect(
        (reading as LocationUnavailable).reason,
        LocationUnavailableReason.timeout,
      );
    });

    test('nunca deixa uma leitura sem localização passar como coordenada válida', () async {
      // Regressão central do L-02: falha de qualquer tipo deve virar
      // LocationUnavailable, nunca um LocationAvailable com dado inventado.
      GeolocatorPlatform.instance = _FakeGeolocatorPlatform(
        positionError: const LocationServiceDisabledException(),
      );

      final reading = await reader.read();

      expect(reading, isA<LocationUnavailable>());
    });
  });
}
