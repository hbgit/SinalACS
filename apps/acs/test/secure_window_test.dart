import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A lista da microárea mostra nome e condições crônicas (LGPD §5.6). Sem
/// `FLAG_SECURE`, o sistema deixa a tela ser capturada, gravada e reduzida a
/// miniatura nos "apps recentes" — dado de saúde fora do controle do app.
/// Este teste lê a `MainActivity` porque `flutter test` não tem janela
/// Android; a prova na janela de verdade é `scripts/qa/acs_secure_window.sh`.
void main() {
  final fonte = File(
    'android/app/src/main/kotlin/br/com/prismrr/sinalacs/acs/MainActivity.kt',
  ).readAsStringSync();

  final gradle = File('android/app/build.gradle.kts').readAsStringSync();

  test('FLAG_SECURE só é dispensada pela constante de compilação ALLOW_SCREEN_CAPTURE', () {
    final inicio = fonte.indexOf('override fun onCreate');
    final fim = fonte.indexOf('override fun configureFlutterEngine');
    final corpo = fonte.substring(inicio, fim);
    // A aplicação da flag está condicionada à constante, e a constante não é
    // lida de nenhum outro lugar (nada de SharedPreferences, intent, menu).
    expect(corpo, matches(RegExp(r'if\s*\(\s*!BuildConfig\.ALLOW_SCREEN_CAPTURE\s*\)')));
    expect(fonte, isNot(contains('getSharedPreferences')));
    expect(fonte, isNot(contains('getIntent')));
    expect(fonte, isNot(contains('getBooleanExtra')));
  });

  test('o Gradle liga ALLOW_SCREEN_CAPTURE só no debug e barra a propriedade em release', () {
    expect(gradle, contains('buildConfig = true'));
    // Padrão false para todo build.
    expect(gradle, matches(RegExp(r'defaultConfig\s*\{[\s\S]*?ALLOW_SCREEN_CAPTURE",\s*"false"')));
    // Só o buildType debug lê a propriedade.
    expect(gradle, matches(RegExp(r'debug\s*\{[\s\S]*?licenca\("sinalacs\.allowScreenCapture"\)')));
    // E o release que a recebe falha.
    expect(gradle, contains('captura de tela'));
  });

  test('a janela do ACS é FLAG_SECURE (sem captura, gravação nem miniatura)', () {
    expect(fonte, contains('override fun onCreate'));
    expect(fonte, contains('WindowManager.LayoutParams.FLAG_SECURE'));
    expect(fonte, contains('window.setFlags('));
  });

  test('a flag é aplicada DENTRO de onCreate, não só mencionada no arquivo', () {
    // Corpo de `onCreate`: da assinatura até o `}` que fecha o método (a classe
    // é pequena e o método não tem blocos aninhados fora do `window.setFlags(`).
    final inicio = fonte.indexOf('override fun onCreate');
    final fim = fonte.indexOf('override fun configureFlutterEngine');
    expect(inicio, isNonNegative);
    expect(fim, greaterThan(inicio));
    final corpo = fonte.substring(inicio, fim);
    expect(corpo, contains('window.setFlags('));
    expect(corpo, contains('WindowManager.LayoutParams.FLAG_SECURE'));
    // E não está comentada: nenhuma linha com a chamada começa por `//`.
    expect(
      corpo.split('\n').where((l) => l.contains('window.setFlags(')).any((l) => l.trimLeft().startsWith('//')),
      isFalse,
    );
  });
}
