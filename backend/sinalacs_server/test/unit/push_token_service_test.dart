import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
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
  final rows = <String, ({String userId, String platform})>{};

  @override
  Future<PushRegistrationResult> registerIfConsented({
    required String userId,
    required String? microAreaId,
    required String token,
    required String platform,
    required DateTime now,
  }) async {
    if (!consent) return const PushRegistrationResult(PushRegistration.refused);
    final previous = rows[token];
    rows[token] = (userId: userId, platform: platform);
    return previous != null && previous.userId != userId
        ? PushRegistrationResult(PushRegistration.ownerChanged, previousOwnerId: previous.userId)
        : const PushRegistrationResult(PushRegistration.registered);
  }
}

class _FakeAudit extends AuditTrail {
  final events = <AuditEvent>[];

  @override
  Future<void> record(AuditEvent event) async => events.add(event);
}

void main() {
  late _FakePushTokenStore store;
  late _FakeAudit audit;
  late PushTokenService service;

  setUp(() {
    store = _FakePushTokenStore();
    audit = _FakeAudit();
    service = PushTokenService(store: store, audit: audit, clock: () => DateTime.utc(2026, 9, 29));
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

  test('troca de dono audita o novo dono E o anterior, sem o token', () async {
    await service.register(_patient, token: 'tok-1', platform: 'android');
    await service.register(_patient, token: 'tok-1', platform: 'android');
    expect(audit.events, isEmpty);

    await service.register(_otherPatient, token: 'tok-1', platform: 'android');

    expect(audit.events.map((e) => e.userId).toSet(), {_otherPatient.id, _patient.id});
    for (final e in audit.events) {
      expect(e.resourceType, 'push_token');
      expect('${e.resourceId} ${e.result}'.contains('tok-1'), isFalse);
    }
    expect(audit.events.map((e) => e.result), containsAll(['granted', 'lost']));
  });

  test('recusa por falta de consentimento lança e não audita', () async {
    store.consent = false;
    await expectLater(
      service.register(_patient, token: 'tok-1', platform: 'android'),
      throwsA(isA<DataRightsException>()),
    );
    expect(audit.events, isEmpty);
  });
}
