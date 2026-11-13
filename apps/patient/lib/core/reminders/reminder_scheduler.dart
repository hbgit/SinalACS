import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'reminder.dart';

/// Agendamento de notificações locais para lembretes ativos. Interface
/// testável sem canal de plataforma — mesma razão de `LocationReader`.
abstract interface class ReminderScheduler {
  Future<void> schedule(Reminder reminder);
  Future<void> cancel(int reminderId);

  /// Cancela toda notificação agendada pelo app. Usado quando os lembretes
  /// deixam de existir sem que se saibam os ids (chave perdida, "Apagar e
  /// recomeçar").
  Future<void> cancelAll();

  /// [cancelAll] e depois [schedule] de cada um de [active].
  Future<void> rescheduleAll(List<Reminder> active);

  /// Pede a permissão de notificações ao sistema (Android 13+, API 33) e
  /// nunca lança: recusa, adiamento ou falha do plugin só fazem a notificação
  /// não aparecer.
  ///
  /// Só é chamada por um ato da pessoa na tela de lembretes (criar, editar ou
  /// ativar um lembrete), nunca na partida (#153): o diálogo do sistema cobre
  /// o app inteiro enquanto não é respondido, e na partida isso escondia a
  /// tela de urgência e o "Ligar 192" (INV-03). [rescheduleAll], que roda no
  /// aquecimento do banco depois do primeiro quadro, também não a chama.
  Future<void> requestPermission();
}

/// Corpo de toda notificação de lembrete (D7, #136). O rótulo é texto livre e
/// pode citar medicamento; a notificação aparece na tela bloqueada, então
/// nunca o carrega.
const reminderNotificationBody = 'Você tem um lembrete. Abra o SinalACS para ver.';

/// Calcula, em hora local do aparelho, o próximo instante >= [now] em que
/// [reminder] deve disparar — ou `null` quando [reminder] está inativo (não
/// deve haver notificação agendada).
///
/// Camada pura de tradução Reminder -> agendamento: sem `flutter_local_notifications`
/// nem canal de plataforma, portanto testável diretamente — ver
/// `test/reminders/reminder_scheduler_test.dart`.
DateTime? nextOccurrence(Reminder reminder, {required DateTime now}) {
  if (!reminder.active) return null;

  var candidate = DateTime(now.year, now.month, now.day, reminder.hour, reminder.minute);
  if (candidate.isBefore(now)) {
    candidate = candidate.add(const Duration(days: 1));
  }
  return candidate;
}

/// [Location] do `timezone` que representa o offset UTC atual do aparelho,
/// sem tabela de fuso IANA nem conversão.
///
/// Decisão de fuso horário (checada contra a API real de
/// `flutter_local_notifications ^17.2.4`, instalada neste projeto):
/// `zonedSchedule` exige um `tz.TZDateTime`, associado a um
/// `timezone.Location` nomeado. Esse nome é repassado ao lado nativo via
/// `ZoneId.of(timeZoneName)`
/// (`FlutterLocalNotificationsPlugin.java`, método `zonedSchedule`), que
/// aceita tanto um id IANA (`America/Sao_Paulo`) quanto um offset fixo no
/// formato `[+-]HH:MM` (`ZoneOffset.of`). Este app roda só em Android (não
/// existe diretório `ios/` em `apps/patient/`) e não depende de um pacote
/// extra (`flutter_timezone`) só para descobrir o id IANA do aparelho — em
/// vez disso, construímos aqui um [Location] cujo nome já é o offset UTC
/// atual do aparelho nesse formato aceito nativamente. Isso reproduz a hora
/// de parede correta no momento em que o agendamento é feito — consistente
/// com o restante do app, que já opera em hora local (o horário do lembrete
/// é digitado e exibido em hora local, nunca em UTC).
///
/// Limitação aceita: um lembrete agendado antes de uma mudança de horário de
/// verão não acompanha a mudança (o offset fica fixo no valor de quando foi
/// agendado). Não é um risco real para este app: o Brasil não usa mais
/// horário de verão desde 2019.
tz.Location deviceLocation(DateTime at) {
  final offset = at.timeZoneOffset;
  final totalMinutes = offset.inMinutes.abs();
  final hours = (totalMinutes ~/ 60).toString().padLeft(2, '0');
  final minutes = (totalMinutes % 60).toString().padLeft(2, '0');
  final name = '${offset.isNegative ? '-' : '+'}$hours:$minutes';
  return tz.Location(name, const [], const [], [
    tz.TimeZone(offset.inMilliseconds, isDst: false, abbreviation: name),
  ]);
}

/// Abstração fina sobre a chamada de agendamento nativa. Existe só para que
/// [LocalNotificationsReminderScheduler] seja testável sem canal de
/// plataforma: `flutter_local_notifications` fala com código nativo por
/// `MethodChannel`, que não responde em `flutter test` (plugin third-party,
/// não hermético em teste). Os testes cobrem a tradução Reminder ->
/// parâmetros, delegando a chamada real a um fake que implementa esta
/// interface — nunca o plugin em si.
@visibleForTesting
abstract interface class NotificationChannel {
  Future<void> zonedSchedule(
    int id,
    String title,
    String body,
    tz.TZDateTime scheduledDate, {
    required DateTimeComponents matchDateTimeComponents,
  });

  Future<void> cancel(int id);

  Future<void> cancelAll();

  /// Pede a permissão de notificações; ver [ReminderScheduler.requestPermission].
  Future<void> requestPermission();
}

/// [NotificationChannel] real sobre `flutter_local_notifications`.
class _PluginNotificationChannel implements NotificationChannel {
  _PluginNotificationChannel(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'reminders',
      'Lembretes',
      channelDescription: 'Lembretes de saúde configurados pela pessoa usuária.',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
  );

  @override
  Future<void> zonedSchedule(
    int id,
    String title,
    String body,
    tz.TZDateTime scheduledDate, {
    required DateTimeComponents matchDateTimeComponents,
  }) {
    return _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduledDate,
      _details,
      // `inexactAllowWhileIdle` dispensa a permissão SCHEDULE_EXACT_ALARM/
      // USE_EXACT_ALARM (obrigatória a partir do Android 12/14 para alarmes
      // exatos) e o fluxo de solicitação dela à pessoa usuária — fora de
      // escopo desta task. Um lembrete de medicamento não precisa de
      // precisão ao segundo; alguns minutos de atraso não comprometem RF06,
      // diferente do alerta vermelho via MQTT, que é tempo-crítico.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      // Só usado no ramo iOS de `zonedSchedule` (este app não tem projeto
      // iOS), mas o parâmetro é obrigatório na assinatura compartilhada.
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: matchDateTimeComponents,
    );
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id);

  @override
  Future<void> cancelAll() => _plugin.cancelAll();

  // A partir do Android 13 (API 33) mostrar notificação exige permissão
  // concedida em tempo de execução. `resolvePlatformSpecificImplementation`
  // devolve `null` fora do Android (ex.: `flutter test`), daí o `?.`.
  @override
  Future<void> requestPermission() async {
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }
}

/// Implementação de [ReminderScheduler] sobre `flutter_local_notifications`.
/// Cada [Reminder.id] é reaproveitado como id da notificação nativa — mesmo
/// id ao reagendar (edição) substitui o agendamento anterior, sem duplicar.
class LocalNotificationsReminderScheduler implements ReminderScheduler {
  LocalNotificationsReminderScheduler(FlutterLocalNotificationsPlugin plugin)
      : _channel = _PluginNotificationChannel(plugin);

  @visibleForTesting
  LocalNotificationsReminderScheduler.withChannel(this._channel);

  final NotificationChannel _channel;

  @override
  Future<void> schedule(Reminder reminder) async {
    final now = DateTime.now();
    final occurrence = nextOccurrence(reminder, now: now);
    if (occurrence == null) {
      // Inativo: garante que não sobra notificação de uma ativação anterior.
      await cancel(reminder.id);
      return;
    }

    await _channel.zonedSchedule(
      reminder.id,
      'Lembrete SinalACS',
      reminderNotificationBody,
      tz.TZDateTime.from(occurrence, deviceLocation(now)),
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  @override
  Future<void> cancel(int reminderId) => _channel.cancel(reminderId);

  @override
  Future<void> cancelAll() => _channel.cancelAll();

  @override
  Future<void> rescheduleAll(List<Reminder> active) async {
    await cancelAll();
    for (final reminder in active) {
      await schedule(reminder);
    }
  }

  @override
  Future<void> requestPermission() async {
    try {
      await _channel.requestPermission();
    } catch (_) {
      // Sem permissão o lembrete continua salvo e agendado; só a notificação
      // não aparece. Nenhuma tela espera por isto.
    }
  }
}
