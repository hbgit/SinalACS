import 'package:sinalacs_backend/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_backend/src/domain/enums/user_role.dart';
import 'package:test/test.dart';

void main() {
  final service = DevelopmentAuthService(secret: 'test-secret');
  final user = AuthenticatedUser(
    id: 'acs-001',
    role: UserRole.acs,
    microAreaId: 'area-12',
    deviceId: 'device-001',
  );

  test('emite e valida claims de papel e microárea', () {
    final token = service.issueToken(user, now: DateTime.utc(2026, 9, 1, 12));
    final authenticated = service.verifyToken(token, now: DateTime.utc(2026, 9, 1, 12, 1));

    expect(authenticated?.id, 'acs-001');
    expect(authenticated?.role, UserRole.acs);
    expect(authenticated?.microAreaId, 'area-12');
  });

  test('rejeita token expirado e assinatura alterada', () {
    final token = service.issueToken(user, lifetime: const Duration(seconds: 1), now: DateTime.utc(2026, 9, 1, 12));

    expect(service.verifyToken(token, now: DateTime.utc(2026, 9, 1, 12, 1)), isNull);
    expect(service.verifyToken('$token-x', now: DateTime.utc(2026, 9, 1, 12)), isNull);
  });
}