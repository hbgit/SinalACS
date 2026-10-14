import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/notices/notice_scheduling_service.dart';
import 'package:sinalacs_server/src/application/notices/notice_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:test/test.dart';

const _ma1 = '00000000-0000-4000-8000-000000000003';

AuthenticatedUser _user(UserRole role, {String id = 'u-1', String? microAreaId}) =>
    AuthenticatedUser(id: id, role: role, microAreaId: microAreaId, deviceId: 'dev-1');

class _RecordingAudit extends AuditTrail {
  final events = <AuditEvent>[];

  @override
  Future<void> record(AuditEvent event) async => events.add(event);
}

class _FakeStore implements ScheduledNoticeStore {
  final ubsOfStaffMap = <String, String?>{};
  final ubsOfMicroAreaMap = <String, String?>{};
  final rows = <String, ScheduledNoticeSnapshot>{};
  var _seq = 0;

  @override
  Future<String?> ubsOfStaff(String userId) async => ubsOfStaffMap[userId];

  @override
  Future<String?> ubsOfMicroArea(String microAreaId) async => ubsOfMicroAreaMap[microAreaId];

  @override
  Future<String> insert({
    required String createdBy,
    required String microAreaId,
    required String audience,
    required String title,
    required String message,
    required DateTime scheduledFor,
    required DateTime createdAt,
  }) async {
    final id = 'notice-${++_seq}';
    rows[id] = ScheduledNoticeSnapshot(
      id: id,
      createdBy: createdBy,
      microAreaId: microAreaId,
      audience: audience,
      title: title,
      message: message,
      scheduledFor: scheduledFor,
      status: ScheduledNoticeStatus.pending,
      createdAt: createdAt,
    );
    return id;
  }

  @override
  Future<bool> cancelIfPending(String id) async => false;

  @override
  Future<List<ScheduledNoticeSnapshot>> claimDue(DateTime now, {int limit = 20}) async => [];

  @override
  Future<void> finish(
    String id, {
    required ScheduledNoticeStatus status,
    int? recipients,
    int? accepted,
    String? failureReason,
    required DateTime at,
  }) async {}

  @override
  Future<List<ScheduledNoticeSnapshot>> history({
    String? microAreaId,
    String? ubsId,
    required int limit,
    required int offset,
  }) async => [];
}

void main() {
  final now = DateTime.utc(2026, 10, 14, 12);
  late _FakeStore store;
  late _RecordingAudit audit;
  late NoticeSchedulingService service;
  var sends = 0;

  Future<void> schedule(
    AuthenticatedUser user, {
    String microAreaId = _ma1,
    String audience = 'everyone',
    String title = 'Título',
    String message = 'Mensagem secreta',
    DateTime? scheduledFor,
  }) =>
      service.schedule(
        user,
        microAreaId: microAreaId,
        audience: audience,
        title: title,
        message: message,
        scheduledFor: scheduledFor ?? now.add(const Duration(hours: 2)),
      );

  setUp(() {
    store = _FakeStore();
    store.ubsOfMicroAreaMap[_ma1] = 'ubs-1';
    audit = _RecordingAudit();
    sends = 0;
    service = NoticeSchedulingService(
      store: store,
      audit: audit,
      clock: () => now,
      sendNow: ({
        required microAreaId,
        required audience,
        required title,
        required message,
        required actorId,
      }) async {
        sends++;
        return const NoticeSendSnapshot(recipients: 0, accepted: 0);
      },
    );
  });

  test('paciente e ACS não agendam: erro e linha denied_role', () async {
    for (final role in [UserRole.patient, UserRole.acs]) {
      await expectLater(
        schedule(_user(role, microAreaId: _ma1)),
        throwsA(isA<StateError>()),
      );
      expect(audit.events.last.result, 'denied_role');
      expect(audit.events.last.resourceType, 'community_notice');
    }
    expect(store.rows, isEmpty);
    expect(sends, 0);
  });

  test('coordenador não agenda para microárea de outra UBS: denied_territory', () async {
    store.ubsOfStaffMap['c-1'] = 'ubs-1';
    store.ubsOfMicroAreaMap['ma-x'] = 'ubs-2';
    await expectLater(
      schedule(_user(UserRole.coordinator, id: 'c-1'), microAreaId: 'ma-x'),
      throwsA(isA<StateError>()),
    );
    expect(audit.events.last.result, 'denied_territory');
    expect(audit.events.last.resourceType, 'community_notice');
    expect(store.rows, isEmpty);
  });

  test('coordenador sem UBS é recusado (fail-closed)', () async {
    await expectLater(
      schedule(_user(UserRole.coordinator, id: 'c-sem-ubs')),
      throwsA(isA<StateError>()),
    );
    expect(audit.events.last.result, 'denied_territory');
    // Ambos nulos: só a checagem `own == null` não basta para passar.
    store.ubsOfMicroAreaMap[_ma1] = null;
    await expectLater(
      schedule(_user(UserRole.coordinator, id: 'c-sem-ubs')),
      throwsA(isA<StateError>()),
    );
    expect(audit.events.last.result, 'denied_territory');
  });

  test('admin com microárea inexistente: entrada inválida, sem auditoria', () async {
    await expectLater(
      schedule(_user(UserRole.admin), microAreaId: 'ma-inexistente'),
      throwsA(isA<AdminInvalidRequestException>()),
    );
    expect(audit.events, isEmpty);
    expect(store.rows, isEmpty);
  });

  test('datas gravadas no store em UTC', () async {
    final local = DateTime(2026, 10, 14, 15);
    final id = await service.schedule(
      _user(UserRole.admin),
      microAreaId: _ma1,
      audience: 'everyone',
      title: 'T',
      message: 'M',
      scheduledFor: local.add(const Duration(days: 1)),
    );
    expect(store.rows[id]!.scheduledFor.isUtc, isTrue);
    expect(store.rows[id]!.createdAt.isUtc, isTrue);
  });

  test('coordenador agenda na própria UBS', () async {
    store.ubsOfStaffMap['c-1'] = 'ubs-1';
    store.ubsOfMicroAreaMap[_ma1] = 'ubs-1';
    final id = await service.schedule(
      _user(UserRole.coordinator, id: 'c-1'),
      microAreaId: _ma1,
      audience: 'everyone',
      title: 'T',
      message: 'M',
      scheduledFor: now.add(const Duration(hours: 1)),
    );
    expect(store.rows[id]!.status, ScheduledNoticeStatus.pending);
    expect(store.rows[id]!.createdBy, 'c-1');
    expect(audit.events.last.result, 'scheduled');
  });

  test('agendar no passado ou a menos de 1 minuto recusa', () async {
    final admin = _user(UserRole.admin);
    for (final delta in [
      Duration.zero,
      const Duration(hours: -1),
      const Duration(seconds: 59),
    ]) {
      await expectLater(
        schedule(admin, scheduledFor: now.add(delta)),
        throwsA(isA<AdminInvalidRequestException>()),
      );
    }
    expect(store.rows, isEmpty);
  });

  test('exatamente 1 minuto à frente é aceito', () async {
    final id = await service.schedule(
      _user(UserRole.admin),
      microAreaId: _ma1,
      audience: 'everyone',
      title: 'T',
      message: 'M',
      scheduledFor: now.add(const Duration(minutes: 1)),
    );
    expect(store.rows.containsKey(id), isTrue);
  });

  test('título, mensagem e público inválidos recusam', () async {
    final admin = _user(UserRole.admin);
    final casos = <Future<void>>[
      schedule(admin, title: '   '),
      schedule(admin, message: ''),
      schedule(admin, title: 'x' * (noticeTitleMaxLength + 1)),
      schedule(admin, message: 'x' * (noticeMessageMaxLength + 1)),
      schedule(admin, audience: 'todos'),
    ];
    for (final caso in casos) {
      await expectLater(caso, throwsA(isA<AdminInvalidRequestException>()));
    }
    expect(store.rows, isEmpty);
  });

  test('admin agenda: grava pending e audita scheduled com resourceId = id, sem o texto', () async {
    final id = await service.schedule(
      _user(UserRole.admin),
      microAreaId: _ma1,
      audience: 'chronic',
      title: 'TituloUnico',
      message: 'MensagemUnica',
      scheduledFor: now.add(const Duration(hours: 2)),
    );
    expect(store.rows[id]!.status, ScheduledNoticeStatus.pending);
    expect(store.rows[id]!.microAreaId, _ma1);
    final event = audit.events.last;
    expect(event.result, 'scheduled');
    expect(event.actionType, 'write');
    expect(event.resourceType, 'community_notice');
    expect(event.resourceId, id);
    final dump = audit.events.map((e) => e.toString()).join();
    expect(dump, isNot(contains('TituloUnico')));
    expect(dump, isNot(contains('MensagemUnica')));
    expect(sends, 0);
  });
}
