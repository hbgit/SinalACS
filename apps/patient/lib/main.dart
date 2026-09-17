import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sinalacs_patient/app/app.dart';

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

  runApp(const SinalAcsApp());
}
