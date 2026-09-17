import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/core/reminders/reminder.dart';
import 'package:sinalacs_patient/core/reminders/reminder_scheduler.dart';
import 'package:timezone/timezone.dart' as tz;

/// Chamada de agendamento capturada por [FakeNotificationChannel], para
/// asserção nos testes.
class _RecordedZonedSchedule {
  _RecordedZonedSchedule(
    this.id,
    this.title,
    this.body,
    this.scheduledDate,
    this.matchDateTimeComponents,
  );

  final int id;
  final String title;
  final String body;
  final tz.TZDateTime scheduledDate;
  final DateTimeComponents matchDateTimeComponents;
}

/// Duplo de [NotificationChannel]: `flutter_local_notifications` fala com
/// código nativo por `MethodChannel`, que não responde em `flutter test`
/// (não é hermético). Os testes abaixo cobrem só a tradução
/// Reminder -> parâmetros feita por [LocalNotificationsReminderScheduler],
/// nunca o plugin third-party em si.
class FakeNotificationChannel implements NotificationChannel {
  final scheduled = <_RecordedZonedSchedule>[];
  final cancelled = <int>[];

  @override
  Future<void> zonedSchedule(
    int id,
    String title,
    String body,
    tz.TZDateTime scheduledDate, {
    required DateTimeComponents matchDateTimeComponents,
  }) async {
    scheduled.add(
      _RecordedZonedSchedule(id, title, body, scheduledDate, matchDateTimeComponents),
    );
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
  }
}

void main() {
  group('nextOccurrence (tradução pura Reminder -> horário)', () {
    test('lembrete inativo não tem próxima ocorrência', () {
      const reminder = Reminder(id: 1, label: 'x', hour: 8, minute: 0, active: false);
      expect(nextOccurrence(reminder, now: DateTime(2026, 9, 17, 7)), isNull);
    });

    test('horário ainda não passado hoje agenda para hoje', () {
      const reminder = Reminder(id: 1, label: 'x', hour: 8, minute: 0, active: true);
      final now = DateTime(2026, 9, 17, 7, 30);
      expect(nextOccurrence(reminder, now: now), DateTime(2026, 9, 17, 8, 0));
    });

    test('horário exatamente agora conta como ainda não passado (>= agora)', () {
      const reminder = Reminder(id: 1, label: 'x', hour: 8, minute: 0, active: true);
      final now = DateTime(2026, 9, 17, 8, 0);
      expect(nextOccurrence(reminder, now: now), DateTime(2026, 9, 17, 8, 0));
    });

    test('horário já passado hoje agenda para amanhã', () {
      const reminder = Reminder(id: 1, label: 'x', hour: 8, minute: 0, active: true);
      final now = DateTime(2026, 9, 17, 9, 0);
      expect(nextOccurrence(reminder, now: now), DateTime(2026, 9, 18, 8, 0));
    });
  });

  group('LocalNotificationsReminderScheduler', () {
    late FakeNotificationChannel channel;
    late LocalNotificationsReminderScheduler scheduler;

    setUp(() {
      channel = FakeNotificationChannel();
      scheduler = LocalNotificationsReminderScheduler.withChannel(channel);
    });

    test('schedule com active:false não agenda nada e cancela se já existia', () async {
      const reminder = Reminder(id: 42, label: 'Pausado', hour: 8, minute: 0, active: false);

      await scheduler.schedule(reminder);

      expect(channel.scheduled, isEmpty);
      expect(channel.cancelled, [42]);
    });

    test('schedule com active:true calcula o próximo horário >= agora', () async {
      const reminder = Reminder(id: 7, label: 'Losartana 50 mg', hour: 8, minute: 0, active: true);
      final now = DateTime.now();

      await scheduler.schedule(reminder);

      expect(channel.scheduled, hasLength(1));
      final recorded = channel.scheduled.single;
      expect(recorded.id, 7);
      expect(recorded.body, 'Losartana 50 mg');
      expect(recorded.matchDateTimeComponents, DateTimeComponents.time);
      expect(recorded.scheduledDate.hour, 8);
      expect(recorded.scheduledDate.minute, 0);

      final deltaMs = recorded.scheduledDate.millisecondsSinceEpoch - now.millisecondsSinceEpoch;
      // Sempre no futuro (ou agora) e nunca mais que 24h à frente, já que a
      // próxima ocorrência só pode ser hoje ou amanhã no mesmo horário.
      expect(deltaMs, greaterThanOrEqualTo(0));
      expect(deltaMs, lessThan(const Duration(hours: 24, minutes: 1).inMilliseconds));
    });

    test('cancel chama o cancelamento pelo id correto', () async {
      await scheduler.cancel(99);
      expect(channel.cancelled, [99]);
      expect(channel.scheduled, isEmpty);
    });
  });
}
