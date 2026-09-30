import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// O FCM, por padrão, gera o token e fala com os servidores do Google **em toda
/// abertura do app** (auto-init): antes do login e sem nenhum consentimento
/// `segmentedPush` (LGPD: recusa por omissão). O token só pode ser pedido quando o
/// código o pedir (`MainActivity`, canal `sinalacs/push_token`), então o auto-init
/// precisa estar desligado no manifesto. Este teste lê o texto-fonte, o mesmo idioma
/// de `legal_documents_test.dart`: o manifesto não existe no `flutter test`.
void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  test('o auto-init do FCM está desligado no manifesto', () {
    final meta = RegExp(
      r'<meta-data\s+android:name="firebase_messaging_auto_init_enabled"\s+android:value="false"\s*/>',
    );
    expect(meta.hasMatch(manifest), isTrue,
        reason: 'sem isto o aparelho contata o Google em toda abertura, sem consentimento');
  });

  test('o manifesto continua pedindo POST_NOTIFICATIONS', () {
    expect(manifest.contains('android.permission.POST_NOTIFICATIONS'), isTrue);
  });
}
