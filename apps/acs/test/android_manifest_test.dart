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

  // #152: com targetSdk 31+, `allowBackup="false"` não desliga a transferência
  // entre aparelhos (Android 12+). Sem as regras abaixo, o banco SQLCipher da
  // fila e as SharedPreferences (WipeJournal da #81, EncryptedSharedPreferences
  // do flutter_secure_storage) iriam para o aparelho novo, sem a chave do
  // Keystore. Mesma regra do paciente (#136, `android_backup_manifest_test`).
  final application = RegExp(r'<application\b[^>]*>').firstMatch(manifest)?.group(0) ?? '';

  test('fullBackupContent="false" no <application> (API < 31)', () {
    expect(application.contains('android:fullBackupContent="false"'), isTrue);
  });

  test('dataExtractionRules aponta para @xml/data_extraction_rules (API 31+)', () {
    expect(
      application.contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
      isTrue,
    );
  });

  test('regras excluem root, file, database, sharedpref e external em cloud-backup e device-transfer', () {
    final rulesFile = File('android/app/src/main/res/xml/data_extraction_rules.xml');
    expect(rulesFile.existsSync(), isTrue, reason: 'o recurso referenciado precisa existir');
    final rules = rulesFile.readAsStringSync();
    for (final section in ['cloud-backup', 'device-transfer']) {
      final block = RegExp('<$section[^>]*>([\\s\\S]*?)</$section>').firstMatch(rules);
      expect(block, isNotNull, reason: 'falta <$section>');
      for (final domain in ['root', 'file', 'database', 'sharedpref', 'external']) {
        final exclude = RegExp('<exclude\\s+domain="$domain"\\s+path="\\."\\s*/>');
        expect(exclude.hasMatch(block!.group(1)!), isTrue,
            reason: '$section deve excluir o domínio $domain');
      }
      expect(RegExp(r'<include\b').hasMatch(block!.group(1)!), isFalse,
          reason: '$section não deve incluir nada');
    }
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

  test('MainActivity registra o cofre do Keystore no canal do Dart', () {
    final activity =
        File('android/app/src/main/kotlin/br/com/prismrr/sinalacs/acs/MainActivity.kt').readAsStringSync();
    expect(activity, contains('override fun configureFlutterEngine'));
    expect(activity, contains('KeystoreVault.CHANNEL'));
    expect(activity, contains('KeystoreVault(this)'));
  });

  test('KeystoreVault exige autenticação a cada uso e não registra nada', () {
    // flutter test não tem Keystore: a prova real fica no emulador. Aqui se
    // guarda o que não pode regredir no código-fonte do cofre.
    final vault =
        File('android/app/src/main/kotlin/br/com/prismrr/sinalacs/acs/KeystoreVault.kt').readAsStringSync();
    expect(vault, contains('const val CHANNEL = "br.com.prismrr.sinalacs.acs/keystore_vault"'));
    expect(vault, contains('.setUserAuthenticationRequired(true)'));
    expect(vault, contains('.setInvalidatedByBiometricEnrollment(true)'));
    expect(vault, contains('BiometricPrompt.CryptoObject(cipher)'));
    expect(vault, contains('MGF1ParameterSpec.SHA1'));
    // A biometric 1.1.0 descarta o authenticate em silêncio com o estado já
    // salvo: sem esta checagem o canal nunca responderia.
    expect(vault, contains('supportFragmentManager.isStateSaved'));
    // Blob adulterado (tag GCM) é apagado e vira `invalidated`.
    expect(vault, contains('catch (e: AEADBadTagException)'));
    for (final code in ['"cancelled"', '"lockedOut"', '"invalidated"', '"unavailable"']) {
      expect(vault, contains(code));
    }
    // Nada de log nem de mensagem de exceção atravessando o canal.
    expect(vault, isNot(contains('android.util.Log')));
    expect(vault, isNot(contains('Log.')));
    expect(vault, isNot(contains('.message')));
    expect(vault, isNot(contains('printStackTrace')));
    expect(vault, isNot(contains('localizedMessage')));
  });

  test('a dependência do BiometricPrompt está fixada na 1.1.0', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('implementation("androidx.biometric:biometric:1.1.0")'));
  });
}
