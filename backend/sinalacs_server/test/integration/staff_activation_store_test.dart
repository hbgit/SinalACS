import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_acs_credential_store.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

/// Código de ativação do staff (#48) contra Postgres real: o store grava,
/// lê, substitui e apaga o código sem tocar nas outras colunas da conta.
///
/// Dados sintéticos; ids próprios, distintos das outras suítes.
const _staffId = '00000000-0000-4000-8000-0000000000b1';

Future<void> _seed(Session session) async {
  final now = DateTime.now().toUtc();
  await User.db.insertRow(
    session,
    User(
      id: UuidValue.fromString(_staffId),
      cpfHash: 'development-staff-activation',
      name: 'Administrador sintético',
      birthDate: DateTime.utc(1980),
      role: UserRole.admin,
      microAreaId: null,
      createdAt: now,
      updatedAt: now,
    ),
  );
  await StaffAccount.db.insertRow(
    session,
    StaffAccount(
      id: UuidValue.fromString(_staffId),
      enrollmentId: 'ADM-ACT-001',
      active: true,
    ),
  );
}

void main() {
  withServerpod('Dado o código de ativação do staff (#48)', (sessionBuilder, endpoints) {
    setUp(() async => _seed(sessionBuilder.build()));

    test('issue grava; find devolve; issue de novo substitui; clear apaga', () async {
      final session = sessionBuilder.build();
      final store = OrmAcsCredentialStore(session: () => session, staff: true);
      final t0 = DateTime.utc(2026, 10, 7, 12);

      expect(await store.find(_staffId), isNull);

      await store.issue(
        _staffId,
        codeHash: 'h1',
        expiresAt: t0.add(const Duration(hours: 1)),
        issuedBy: 'operador',
        at: t0,
      );
      expect((await store.find(_staffId))?.codeHash, 'h1');

      await store.issue(
        _staffId,
        codeHash: 'h2',
        expiresAt: t0.add(const Duration(hours: 2)),
        issuedBy: 'operador-2',
        at: t0,
      );
      final vigente = await store.find(_staffId);
      expect(vigente?.codeHash, 'h2');
      expect(vigente?.expiresAt, t0.add(const Duration(hours: 2)));

      await store.clear(_staffId);
      expect(await store.find(_staffId), isNull);

      // `clear` apaga hash e validade, mas mantém o último registro de emissão.
      final conta = await StaffAccount.db.findById(session, UuidValue.fromString(_staffId));
      expect(conta?.activationCodeIssuedBy, 'operador-2');
      expect(conta?.active, isTrue);
    });
  });
}
