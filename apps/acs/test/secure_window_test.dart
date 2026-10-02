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

  test('a janela do ACS é FLAG_SECURE (sem captura, gravação nem miniatura)', () {
    expect(fonte, contains('override fun onCreate'));
    expect(fonte, contains('WindowManager.LayoutParams.FLAG_SECURE'));
    expect(fonte, contains('window.setFlags('));
  });
}
