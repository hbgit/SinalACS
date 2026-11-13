import 'dart:async';

import 'package:sinalacs_patient/core/legal/educational_notice.dart';

/// Os testes que não tratam do aviso educativo da primeira abertura (RF21,
/// C-02) sobem o app como um aparelho que já o confirmou, para abrir direto no
/// login como antes. Os testes do aviso injetam a própria loja em
/// `SinalAcsApp(educationalNotice:)` e não passam por este padrão.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  educationalNoticeStoreFactory = () => MemoryEducationalNoticeStore(acknowledged: true);
  await testMain();
}
