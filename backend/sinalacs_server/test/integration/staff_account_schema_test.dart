import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

/// Esquema de `staff_accounts` contra Postgres real: a matrícula de staff é
/// única, e é o índice único (não outro erro) que barra a segunda linha.
Future<UuidValue> _insertStaffUser(
  Session session, {
  required UserRole role,
  required String cpfHash,
}) async {
  final now = DateTime.now().toUtc();
  final user = await User.db.insertRow(
    session,
    User(
      cpfHash: cpfHash,
      name: 'Staff sintético',
      birthDate: DateTime.utc(1980),
      role: role,
      createdAt: now,
      updatedAt: now,
    ),
  );
  return user.id!;
}

void main() {
  withServerpod('Dado o esquema de staff_accounts', (sessionBuilder, endpoints) {
    test('matrícula de staff é única', () async {
      final session = sessionBuilder.build();
      final primeiro = await _insertStaffUser(
        session,
        role: UserRole.admin,
        cpfHash: 'staff-schema-1',
      );
      final segundo = await _insertStaffUser(
        session,
        role: UserRole.admin,
        cpfHash: 'staff-schema-2',
      );
      await StaffAccount.db.insertRow(
        session,
        StaffAccount(id: primeiro, enrollmentId: 'ADM-T1', active: true),
      );

      await expectLater(
        StaffAccount.db.insertRow(
          session,
          StaffAccount(id: segundo, enrollmentId: 'ADM-T1', active: true),
        ),
        throwsA(
          // 23505 = unique_violation, e a mensagem nomeia o índice: prova que
          // foi a unicidade da matrícula, e não outro erro, que barrou.
          isA<DatabaseQueryException>().having(
            (e) => e.toString(),
            'mensagem',
            allOf(contains('23505'), contains('staff_accounts_enrollment_id_key')),
          ),
        ),
      );
    });
  });
}
