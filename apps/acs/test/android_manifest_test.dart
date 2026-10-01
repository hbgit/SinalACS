import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// O check-in passivo (RF12) e o mapa dependem de `Geolocator`, que só pede
/// permissão em runtime se ela estiver DECLARADA no manifesto. Sem a
/// declaração o `requestPermission()` não mostra diálogo nenhum e
/// `_loadCurrentPosition` engole o erro: o GPS some em silêncio. Os testes de
/// widget injetam a posição e nunca viram isso — por isso este teste lê o
/// manifesto de release (`main`), o que o APK de produção realmente leva.
void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  bool declares(String permission) => RegExp(
        '<uses-permission\\s+android:name="android\\.permission\\.$permission"\\s*/>',
      ).hasMatch(manifest);

  test('declara localização precisa e aproximada (RF12)', () {
    expect(declares('ACCESS_FINE_LOCATION'), isTrue);
    expect(declares('ACCESS_COARSE_LOCATION'), isTrue);
  });

  test('declara INTERNET no manifesto de release, sem depender de plugin', () {
    expect(declares('INTERNET'), isTrue);
  });

  test('NÃO pede localização em segundo plano (decisão §4 de 2026-09-16)', () {
    expect(declares('ACCESS_BACKGROUND_LOCATION'), isFalse,
        reason: 'o geofence é só em primeiro plano; background exigiria revisão da loja e LGPD');
  });
}
