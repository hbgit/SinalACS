import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:test/test.dart';

import 'test_tools/runtime_harness.dart';
import 'test_tools/serverpod_test_tools.dart';

/// Bloqueio progressivo do login institucional contra Postgres real: prova que
/// `lockStreak` sobe uma vez por bloqueio aplicado — inclusive numa rajada
/// concorrente — e zera no login válido. O store falso do teste unitário só
/// espelha o `CASE`; quem prova que o SQL o aplica é este.
///
/// Dados sintéticos; ids próprios, distintos das outras suítes.
const _acsId = '00000000-0000-4000-8000-0000000000a1';
const _microAreaId = '00000000-0000-4000-8000-0000000000a2';
const _ubsId = '00000000-0000-4000-8000-0000000000a3';
const _matricula = 'ACS-LK-001';

Future<void> _seed(Session session) async {
  await Ubs.db.insertRow(
    session,
    Ubs(
      id: UuidValue.fromString(_ubsId),
      name: 'UBS lockStreak',
      address: 'Endereço local',
      city: 'São Paulo',
      state: 'SP',
    ),
  );
  await MicroArea.db.insertRow(
    session,
    MicroArea(
      id: UuidValue.fromString(_microAreaId),
      name: 'Microárea lockStreak',
      ubsId: UuidValue.fromString(_ubsId),
      geoJsonBoundary: '{}',
    ),
  );
  final now = DateTime.now().toUtc();
  await User.db.insertRow(
    session,
    User(
      id: UuidValue.fromString(_acsId),
      cpfHash: 'development-acs-lock-streak',
      name: 'ACS de desenvolvimento (lockStreak)',
      birthDate: DateTime.utc(1980),
      role: UserRole.acs,
      microAreaId: UuidValue.fromString(_microAreaId),
      createdAt: now,
      updatedAt: now,
    ),
  );
  await Acs.db.insertRow(
    session,
    Acs(
      id: UuidValue.fromString(_acsId),
      enrollmentId: _matricula,
      ubsId: UuidValue.fromString(_ubsId),
      active: true,
    ),
  );
  await AlertRuntimeHarness.store(session).saveCredential(
        _acsId,
        await AlertRuntimeHarness.hasher.derive('senha-sintetica-de-teste'),
        now,
      );
}

void main() {
  withServerpod('Dado o bloqueio progressivo do login institucional', (sessionBuilder, endpoints) {
    setUp(() async => _seed(sessionBuilder.build()));

    test('lockStreak sobe uma vez por bloqueio aplicado e zera no login válido', () async {
      final store = AlertRuntimeHarness.store(sessionBuilder.build());
      final at = DateTime.utc(2026, 10, 5, 12);
      final lockUntil = at.add(const Duration(minutes: 15));

      for (var i = 0; i < 5; i++) {
        await store.registerFailedAttempt(_acsId,
            restartCounter: false, maxFailedAttempts: 5, lockUntil: lockUntil, at: at);
      }
      expect((await store.findByEnrollmentId(_matricula))!.lockStreak, 1);

      // Rajada concorrente na linha já bloqueada: o WHERE recusa; a sequência não sobe de novo.
      await Future.wait([
        for (var i = 0; i < 5; i++)
          store.registerFailedAttempt(_acsId,
              restartCounter: false, maxFailedAttempts: 5, lockUntil: lockUntil, at: at),
      ]);
      expect((await store.findByEnrollmentId(_matricula))!.lockStreak, 1);

      // Bloqueio vencido: o contador recomeça em 1, mas a escalada é preservada.
      final depois = at.add(const Duration(minutes: 16));
      await store.registerFailedAttempt(_acsId,
          restartCounter: true, maxFailedAttempts: 5, lockUntil: depois.add(const Duration(minutes: 30)), at: depois);
      expect((await store.findByEnrollmentId(_matricula))!.lockStreak, 1);

      await store.registerSuccessfulLogin(_acsId, depois.add(const Duration(minutes: 1)));
      expect((await store.findByEnrollmentId(_matricula))!.lockStreak, 0);
    });
  });
}
