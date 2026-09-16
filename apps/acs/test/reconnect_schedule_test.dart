import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/services/reconnect_schedule.dart';

void main() {
  group('ReconnectSchedule', () {
    test('dobra a cada tentativa até o teto de 60s', () {
      final schedule = ReconnectSchedule();

      expect(schedule.next(), const Duration(seconds: 2));
      expect(schedule.next(), const Duration(seconds: 4));
      expect(schedule.next(), const Duration(seconds: 8));
      expect(schedule.next(), const Duration(seconds: 16));
      expect(schedule.next(), const Duration(seconds: 32));
      expect(schedule.next(), const Duration(seconds: 60));
      // Fica no teto, não ultrapassa.
      expect(schedule.next(), const Duration(seconds: 60));
    });

    test('reset volta ao atraso inicial depois de já ter subido', () {
      final schedule = ReconnectSchedule();
      schedule.next();
      schedule.next();
      schedule.next();

      schedule.reset();

      expect(schedule.next(), const Duration(seconds: 2));
    });
  });
}
