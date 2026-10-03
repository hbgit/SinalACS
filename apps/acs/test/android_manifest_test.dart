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

  test('declara a consulta ao discador (tel:) para o botão do SAMU (RF13)', () {
    // Android 11+: sem <queries>, `canLaunchUrl(tel:)` devolve false mesmo com discador.
    expect(
      RegExp(r'<action\s+android:name="android\.intent\.action\.DIAL"\s*/>\s*<data\s+android:scheme="tel"\s*/>')
          .hasMatch(manifest),
      isTrue,
    );
  });

  test('NÃO pede localização em segundo plano (decisão §4 de 2026-09-16)', () {
    expect(declares('ACCESS_BACKGROUND_LOCATION'), isFalse,
        reason: 'o geofence é só em primeiro plano; background exigiria revisão da loja e LGPD');
  });

  test('NÃO deixa o Android copiar o app para a nuvem (INV-04 / LGPD)', () {
    // allowBackup é `true` por padrão. Sem `false` explícito, o backup
    // automático leva para a conta Google da pessoa o `shared_preferences` e o
    // banco local da fila de visitas — dado de saúde fora do controle do
    // sistema. A chave do SQLCipher vive no Keystore e não migra, então o
    // backup também não restauraria nada que prestasse: só vazaria.
    expect(
      RegExp(r'<application[^>]*android:allowBackup="false"', dotAll: true).hasMatch(manifest),
      isTrue,
    );
  });

  test('o nome na gaveta do aparelho é legível, não o identificador do pacote', () {
    expect(manifest, isNot(contains('android:label="sinalacs_acs"')));
    expect(manifest, contains('android:label="SinalACS ACS"'));
  });

  test('declara USE_BIOMETRIC para o desbloqueio por digital', () {
    expect(declares('USE_BIOMETRIC'), isTrue);
  });

  test('MainActivity usa FlutterFragmentActivity e mantém FLAG_SECURE', () {
    // local_auth falha em tempo de execução com FlutterActivity; e o
    // FLAG_SECURE (captura/miniatura) não pode regredir.
    final activity =
        File('android/app/src/main/kotlin/br/com/prismrr/sinalacs/acs/MainActivity.kt').readAsStringSync();
    expect(activity, contains('class MainActivity : FlutterFragmentActivity()'));
    expect(activity, contains('FLAG_SECURE'));
  });
}
