import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/patients/push_token_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:test/test.dart';

const _microAreaId = '00000000-0000-4000-8000-000000000003';

const _patient = AuthenticatedUser(
  id: '00000000-0000-4000-8000-000000000001',
  role: UserRole.patient,
  microAreaId: _microAreaId,
  deviceId: 'patient-device-001',
);

const _otherPatient = AuthenticatedUser(
  id: '00000000-0000-4000-8000-000000000009',
  role: UserRole.patient,
  microAreaId: _microAreaId,
  deviceId: 'patient-device-009',
);

const _acs = AuthenticatedUser(
  id: '00000000-0000-4000-8000-000000000002',
  role: UserRole.acs,
  microAreaId: _microAreaId,
  deviceId: 'acs-device-001',
);

class _FakePushTokenStore implements PushTokenStore {
  var consent = true;
  var deleted = 0;
  final rows = <String, ({String userId, String platform})>{};

  @override
  Future<bool> hasGrantedConsent(String userId) async => consent;

  @override
  Future<void> upsert({
    required String userId,
    required String? microAreaId,
    required String token,
    required String platform,
    required DateTime now,
  }) async {
    rows[token] = (userId: userId, platform: platform);
  }

  @override
  Future<int> deleteAllFor(String userId) async {
    deleted++;
    rows.removeWhere((_, r) => r.userId == userId);
    return 1;
  }
}

void main() {
  late _FakePushTokenStore store;
  late PushTokenService service;

  setUp(() {
    store = _FakePushTokenStore();
    service = PushTokenService(store: store, clock: () => DateTime.utc(2026, 9, 29));
  });

  test('sem consentimento vigente, recusa e não grava', () async {
    store.consent = false;
    await expectLater(
      service.register(_patient, token: 'tok-1', platform: 'android'),
      throwsA(isA<DataRightsException>()),
    );
    expect(store.rows, isEmpty);
  });

  test('registra e repete sem duplicar', () async {
    await service.register(_patient, token: 'tok-1', platform: 'android');
    await service.register(_patient, token: 'tok-1', platform: 'android');
    expect(store.rows.keys, ['tok-1']);
  });

  test('o mesmo token de outro titular troca de dono', () async {
    await service.register(_patient, token: 'tok-1', platform: 'android');
    await service.register(_otherPatient, token: 'tok-1', platform: 'android');
    expect(store.rows['tok-1']!.userId, _otherPatient.id);
  });

  test('recusa token vazio, longo demais e plataforma desconhecida', () async {
    for (final args in [('', 'android'), ('x' * 4097, 'android'), ('tok', 'web')]) {
      await expectLater(
        service.register(_patient, token: args.$1, platform: args.$2),
        throwsA(isA<DataRightsException>()),
      );
    }
    expect(store.rows, isEmpty);
  });

  test('ACS não registra token', () async {
    await expectLater(
      service.register(_acs, token: 'tok-1', platform: 'android'),
      throwsA(isA<StateError>()),
    );
  });
}
