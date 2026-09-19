import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sinalacs_patient/app/app.dart';
import 'package:sinalacs_patient/core/network/backend_client.dart';
import 'package:sinalacs_patient/core/network/backend_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializa o plugin de notificações locais antes de `runApp`: é preciso
  // para que `LocalNotificationsReminderScheduler` (RF06 §3.1, lembretes de
  // saúde locais ao aparelho) consiga chamar `zonedSchedule`/`cancel` mais
  // tarde. `@mipmap/ic_launcher` é o ícone padrão já usado pelo app — ver
  // `android/app/src/main/res/mipmap-*/ic_launcher.png`.
  final notifications = FlutterLocalNotificationsPlugin();
  await notifications.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );
  // A partir do Android 13 (API 33) mostrar notificação exige permissão
  // concedida em tempo de execução; sem pedir, os lembretes agendados nunca
  // apareceriam nesses aparelhos. `resolvePlatformSpecificImplementation`
  // retorna `null` fora do Android (ex.: `flutter test`), daí o `?.`.
  await notifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();

  // O RPC responde por HTTPS e o certificado é assinado por uma CA de
  // desenvolvimento que o armazenamento do sistema não conhece (RNF04/L-08).
  // Sem estes bytes o cliente cai no armazenamento do sistema e a conexão falha
  // — explicitamente, com `HandshakeException`, e não aceitando qualquer
  // certificado.
  //
  // A ausência do asset não é fatal de propósito: o cliente é construído
  // assim mesmo e a falha aparece na tela como erro de conexão, com a causa
  // real no log abaixo — melhor que derrubar o app no boot por um arquivo que
  // só existe depois de `scripts/dev/sync_dev_ca.sh`.
  List<int>? trustedCaBytes;
  try {
    final data = await rootBundle.load(BackendConfig.rpcCaAsset);
    trustedCaBytes = data.buffer.asUint8List();
  } catch (error) {
    debugPrint(
      'CA do RPC não encontrada em ${BackendConfig.rpcCaAsset}: $error. '
      'Rode ./scripts/dev/sync_dev_ca.sh depois de subir a stack.',
    );
  }

  // O cliente é construído aqui, e não dentro de `SinalAcsApp`, porque só aqui
  // a CA já foi lida: `BackendConfig` não importa `rootBundle` de propósito —
  // `tool/live_check.dart` o importa fora do Flutter, onde `dart:ui` não existe.
  runApp(SinalAcsApp(backend: BackendClient(trustedCaBytes: trustedCaBytes)));
}
