import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/notices/notice_scheduling_service.dart';
import 'package:sinalacs_server/src/application/notices/notice_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/push/gorush_client.dart';
import 'package:test/test.dart';

const _ma1 = '00000000-0000-4000-8000-000000000003';
const _ma2 = '00000000-0000-4000-8000-000000000004';
const _maX = '00000000-0000-4000-8000-000000000005';
const _maInexistente = '00000000-0000-4000-8000-000000000006';

AuthenticatedUser _user(UserRole role, {String id = 'u-1', String? microAreaId}) =>
    AuthenticatedUser(id: id, role: role, microAreaId: microAreaId, deviceId: 'dev-1');

class _RecordingAudit extends AuditTrail {
  final events = <AuditEvent>[];

  @override
  Future<void> record(AuditEvent event) async => events.add(event);
}

class _ThrowingAudit extends AuditTrail {
  var calls = 0;

  @override
  Future<void> record(AuditEvent event) async {
    calls++;
    throw StateError('auditoria fora do ar');
  }
}

class _OrderAudit extends AuditTrail {
  _OrderAudit(this.order);
  final List<String> order;

  @override
  Future<void> record(AuditEvent event) async => order.add('audit');
}

/// Embrulha o fake e conta chamadas a `history`.
class _CountingStore implements ScheduledNoticeStore {
  _CountingStore(this._inner, this._onHistory);
  final _FakeStore _inner;
  final void Function() _onHistory;

  @override
  Future<List<ScheduledNoticeSnapshot>> history({
    String? microAreaId,
    String? ubsId,
    required int limit,
    required int offset,
  }) {
    _onHistory();
    return _inner.history(
      microAreaId: microAreaId,
      ubsId: ubsId,
      limit: limit,
      offset: offset,
    );
  }

  @override
  Future<String?> ubsOfStaff(String userId) => _inner.ubsOfStaff(userId);
  @override
  Future<String?> ubsOfMicroArea(String id) => _inner.ubsOfMicroArea(id);
  @override
  Future<String> insert({
    required String createdBy,
    required String microAreaId,
    required String audience,
    required String title,
    required String message,
    required DateTime scheduledFor,
    required DateTime createdAt,
  }) => _inner.insert(
    createdBy: createdBy,
    microAreaId: microAreaId,
    audience: audience,
    title: title,
    message: message,
    scheduledFor: scheduledFor,
    createdAt: createdAt,
  );
  @override
  Future<ScheduledNoticeSnapshot?> findById(String id) => _inner.findById(id);
  @override
  Future<bool> cancelIfPending(String id) => _inner.cancelIfPending(id);
  @override
  Future<List<ScheduledNoticeSnapshot>> claimDue(
    DateTime now, {
    int limit = 20,
  }) => _inner.claimDue(now, limit: limit);
  @override
  Future<void> finish(
    String id, {
    required ScheduledNoticeStatus status,
    int? recipients,
    int? accepted,
    String? failureReason,
    required DateTime at,
  }) => _inner.finish(
    id,
    status: status,
    recipients: recipients,
    accepted: accepted,
    failureReason: failureReason,
    at: at,
  );
  @override
  Future<List<StuckNotice>> markStaleSendingUnknown({
    required DateTime before,
    required String reason,
    required DateTime at,
  }) => _inner.markStaleSendingUnknown(before: before, reason: reason, at: at);
}

Future<String> _insertNotice(_FakeStore s) => s.insert(
  createdBy: 'u',
  microAreaId: _ma1,
  audience: 'everyone',
  title: 'T',
  message: 'M',
  scheduledFor: DateTime.utc(2030),
  createdAt: DateTime.utc(2026),
);

class _RecipientStore implements NoticeRecipientStore {
  List<PushTarget> targets = const [PushTarget(token: 'tok', platform: 'android')];

  @override
  Future<List<PushTarget>> consentedTargets({
    required String microAreaId,
    required bool chronicOnly,
  }) async =>
      targets;

  @override
  Future<int> deleteTokens(List<String> tokens) async => tokens.length;
}

class _Sender implements PushSender {
  PushSendReport report = const PushSendReport(accepted: 1, invalidTokens: []);
  PushGatewayException? failure;

  @override
  Future<PushSendReport> send(PushMessage message, List<PushTarget> targets) async {
    final f = failure;
    if (f != null) throw f;
    return report;
  }
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
    final id = '00000000-0000-4000-8000-${(++_seq).toString().padLeft(12, '0')}';
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
  Future<List<StuckNotice>> markStaleSendingUnknown({
    required DateTime before,
    required String reason,
    required DateTime at,
  }) async {
    final moved = <StuckNotice>[];
    for (final r in rows.values.toList()) {
      if (r.status == ScheduledNoticeStatus.sending && r.scheduledFor.isBefore(before)) {
        await finish(r.id, status: ScheduledNoticeStatus.unknown, failureReason: reason, at: at);
        moved.add(StuckNotice(id: r.id, createdBy: r.createdBy));
      }
    }
    return moved;
  }

  @override
  Future<ScheduledNoticeSnapshot?> findById(String id) async => rows[id];

  @override
  Future<bool> cancelIfPending(String id) async {
    final row = rows[id];
    if (row == null || row.status != ScheduledNoticeStatus.pending) return false;
    rows[id] = _copy(row, status: ScheduledNoticeStatus.cancelled);
    return true;
  }

  @override
  Future<List<ScheduledNoticeSnapshot>> claimDue(DateTime now, {int limit = 20}) async {
    final due = rows.values
        .where((r) => r.status == ScheduledNoticeStatus.pending && !r.scheduledFor.isAfter(now))
        .take(limit)
        .toList();
    for (final r in due) {
      rows[r.id] = _copy(r, status: ScheduledNoticeStatus.sending);
    }
    return due;
  }

  @override
  Future<void> finish(
    String id, {
    required ScheduledNoticeStatus status,
    int? recipients,
    int? accepted,
    String? failureReason,
    required DateTime at,
  }) async {
    final r = rows[id]!;
    rows[id] = ScheduledNoticeSnapshot(
      id: r.id,
      createdBy: r.createdBy,
      microAreaId: r.microAreaId,
      audience: r.audience,
      title: r.title,
      message: r.message,
      scheduledFor: r.scheduledFor,
      status: status,
      createdAt: r.createdAt,
      recipients: recipients,
      accepted: accepted,
      failureReason: failureReason,
      sentAt: status == ScheduledNoticeStatus.sent ? at : null,
    );
  }

  @override
  Future<List<ScheduledNoticeSnapshot>> history({
    String? microAreaId,
    String? ubsId,
    required int limit,
    required int offset,
  }) async {
    lastHistoryUbsId = ubsId;
    lastHistoryLimit = limit;
    lastHistoryOffset = offset;
    return rows.values
        .where((r) => microAreaId == null || r.microAreaId == microAreaId)
        .where((r) => ubsId == null || ubsOfMicroAreaMap[r.microAreaId] == ubsId)
        .toList();
  }

  String? lastHistoryUbsId;
  int? lastHistoryLimit;
  int? lastHistoryOffset;

  static ScheduledNoticeSnapshot _copy(ScheduledNoticeSnapshot r, {required ScheduledNoticeStatus status}) =>
      ScheduledNoticeSnapshot(
        id: r.id,
        createdBy: r.createdBy,
        microAreaId: r.microAreaId,
        audience: r.audience,
        title: r.title,
        message: r.message,
        scheduledFor: r.scheduledFor,
        status: status,
        createdAt: r.createdAt,
      );
}

void main() {
  final now = DateTime.utc(2026, 10, 14, 12);
  late _FakeStore store;
  late _RecordingAudit audit;
  late NoticeSchedulingService service;
  var sends = 0;
  late Future<NoticeSendSnapshot> Function(String microAreaId) onSend;

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
    onSend = (_) async => const NoticeSendSnapshot(recipients: 0, accepted: 0);
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
        auditResourceId,
      }) async {
        sends++;
        return onSend(microAreaId);
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
    store.ubsOfMicroAreaMap[_maX] = 'ubs-2';
    await expectLater(
      schedule(_user(UserRole.coordinator, id: 'c-1'), microAreaId: _maX),
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
      schedule(_user(UserRole.admin), microAreaId: _maInexistente),
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
    // AuditEvent não sobrescreve toString: monta-se o dump pelos campos.
    final dump = audit.events
        .map((e) => '${e.userId}|${e.actionType}|${e.resourceType}|${e.resourceId}|${e.result}')
        .join('\n');
    expect(dump, isNot(contains('TituloUnico')));
    expect(dump, isNot(contains('MensagemUnica')));
    expect(sends, 0);
  });

  group('cancel', () {
    Future<String> pendente() => service.schedule(
          _user(UserRole.admin),
          microAreaId: _ma1,
          audience: 'everyone',
          title: 'T',
          message: 'MensagemSecreta',
          scheduledFor: now.add(const Duration(hours: 2)),
        );

    test('admin cancela aviso pending e audita cancelled com resourceId = id', () async {
      final id = await pendente();
      await service.cancel(_user(UserRole.admin), id);
      expect(store.rows[id]!.status, ScheduledNoticeStatus.cancelled);
      final e = audit.events.last;
      expect(e.result, 'cancelled');
      expect(e.resourceType, 'community_notice');
      expect(e.resourceId, id);
    });

    test('coordenador cancela aviso da própria UBS', () async {
      final id = await pendente();
      store.ubsOfStaffMap['c-1'] = 'ubs-1';
      await service.cancel(_user(UserRole.coordinator, id: 'c-1'), id);
      expect(store.rows[id]!.status, ScheduledNoticeStatus.cancelled);
    });

    test('aviso que não está pending recusa', () async {
      final id = await pendente();
      store.rows[id] = _FakeStore._copy(store.rows[id]!, status: ScheduledNoticeStatus.sent);
      await expectLater(
        service.cancel(_user(UserRole.admin), id),
        throwsA(isA<AdminInvalidRequestException>()),
      );
      expect(store.rows[id]!.status, ScheduledNoticeStatus.sent);
    });

    test('aviso inexistente recusa', () async {
      await expectLater(
        service.cancel(_user(UserRole.admin), '00000000-0000-4000-8000-0000000000ff'),
        throwsA(isA<AdminInvalidRequestException>()),
      );
    });

    test('paciente e ACS: denied_role auditado', () async {
      final id = await pendente();
      for (final role in [UserRole.patient, UserRole.acs]) {
        await expectLater(
          service.cancel(_user(role, microAreaId: _ma1), id),
          throwsA(isA<StateError>()),
        );
        expect(audit.events.last.result, 'denied_role');
        expect(audit.events.last.resourceType, 'community_notice');
      }
      expect(store.rows[id]!.status, ScheduledNoticeStatus.pending);
    });

    test('coordenador de outra UBS e sem UBS: denied_territory, nada cancelado', () async {
      final id = await pendente();
      store.ubsOfStaffMap['c-2'] = 'ubs-2';
      for (final uid in ['c-2', 'c-sem-ubs']) {
        await expectLater(
          service.cancel(_user(UserRole.coordinator, id: uid), id),
          throwsA(isA<StateError>()),
        );
        expect(audit.events.last.result, 'denied_territory');
      }
      expect(store.rows[id]!.status, ScheduledNoticeStatus.pending);
    });
  });

  group('history', () {
    setUp(() {
      store.ubsOfMicroAreaMap[_ma2] = 'ubs-2';
    });

    Future<void> seed() async {
      for (final ma in [_ma1, _ma2]) {
        await service.schedule(
          _user(UserRole.admin),
          microAreaId: ma,
          audience: 'everyone',
          title: 'Titulo-$ma',
          message: 'MensagemSecreta-$ma',
          scheduledFor: now.add(const Duration(hours: 2)),
        );
      }
    }

    test('coordenador só vê a própria UBS; admin vê todas', () async {
      await seed();
      store.ubsOfStaffMap['c-1'] = 'ubs-1';
      final doCoord = await service.history(_user(UserRole.coordinator, id: 'c-1'));
      expect(doCoord.map((i) => i.microAreaId), [_ma1]);
      expect(store.lastHistoryUbsId, 'ubs-1');
      final doAdmin = await service.history(_user(UserRole.admin));
      expect(doAdmin, hasLength(2));
      expect(store.lastHistoryUbsId, isNull);
    });

    test('paciente e ACS: denied_role auditado', () async {
      for (final role in [UserRole.patient, UserRole.acs]) {
        await expectLater(
          service.history(_user(role, microAreaId: _ma1)),
          throwsA(isA<StateError>()),
        );
        expect(audit.events.last.result, 'denied_role');
      }
    });

    test('coordenador sem UBS ou filtrando microárea de outra UBS: denied_territory', () async {
      await seed();
      await expectLater(
        service.history(_user(UserRole.coordinator, id: 'c-sem-ubs')),
        throwsA(isA<StateError>()),
      );
      expect(audit.events.last.result, 'denied_territory');
      store.ubsOfStaffMap['c-1'] = 'ubs-1';
      await expectLater(
        service.history(_user(UserRole.coordinator, id: 'c-1'), microAreaId: _ma2),
        throwsA(isA<StateError>()),
      );
      expect(audit.events.last.result, 'denied_territory');
    });

    test('filtro por microárea própria funciona', () async {
      await seed();
      final r = await service.history(_user(UserRole.admin), microAreaId: _ma2);
      expect(r.map((i) => i.microAreaId), [_ma2]);
    });

    test('o item não carrega a mensagem e a leitura é auditada sem texto', () async {
      await seed();
      final r = await service.history(_user(UserRole.admin));
      final item = r.first;
      expect(item.title, startsWith('Titulo-'));
      expect(item.status, ScheduledNoticeStatus.pending);
      expect(item.createdBy, 'u-1');
      expect(item.toString(), isNot(contains('MensagemSecreta')));
      final e = audit.events.last;
      expect(e.actionType, 'read');
      expect(e.resourceType, 'community_notice');
      expect(e.result, 'granted');
      final dump = audit.events
          .map((e) => '${e.userId}|${e.actionType}|${e.resourceType}|${e.resourceId}|${e.result}')
          .join('\n');
      expect(dump, isNot(contains('MensagemSecreta')));
    });

    test('limit é limitado a 1..100 (padrão 50) e offset a >= 0', () async {
      final admin = _user(UserRole.admin);
      await service.history(admin);
      expect(store.lastHistoryLimit, 50);
      await service.history(admin, limit: 0);
      expect(store.lastHistoryLimit, 1);
      await service.history(admin, limit: 1000);
      expect(store.lastHistoryLimit, 100);
      await service.history(admin, limit: 20, offset: -5);
      expect(store.lastHistoryLimit, 20);
      expect(store.lastHistoryOffset, 0);
    });
  });

  group('dispatchDue', () {
    final admin = _user(UserRole.admin, id: 'adm-1');
    Future<String> due({String title = 'Titulo', String message = 'TextoSecretoDoAviso'}) async {
      final id = await store.insert(
        createdBy: 'adm-1',
        microAreaId: _ma1,
        audience: 'everyone',
        title: title,
        message: message,
        scheduledFor: now.subtract(const Duration(minutes: 5)),
        createdAt: now.subtract(const Duration(hours: 1)),
      );
      return id;
    }

    String dump() => audit.events
        .map((e) => '${e.userId}|${e.actionType}|${e.resourceType}|${e.resourceId}|${e.result}')
        .join('\n');

    test('2 vencidos enviam 2 e viram sent com contagens', () async {
      final a = await due();
      final b = await due();
      onSend = (_) async => const NoticeSendSnapshot(recipients: 5, accepted: 4);
      expect(await service.dispatchDue(), 2);
      expect(sends, 2);
      for (final id in [a, b]) {
        final r = store.rows[id]!;
        expect(r.status, ScheduledNoticeStatus.sent);
        expect(r.recipients, 5);
        expect(r.accepted, 4);
        expect(r.sentAt, now);
      }
    });

    test('segunda chamada não reenvia', () async {
      await due();
      expect(await service.dispatchDue(), 1);
      expect(await service.dispatchDue(), 0);
      expect(sends, 1);
    });

    test('futuro não é disparado', () async {
      await service.schedule(admin,
          microAreaId: _ma1,
          audience: 'everyone',
          title: 'T',
          message: 'M',
          scheduledFor: now.add(const Duration(hours: 1)));
      expect(await service.dispatchDue(), 0);
      expect(sends, 0);
    });

    test('NoticeDeliveryException simples vira failed e não repete', () async {
      final id = await due();
      onSend = (_) async => throw NoticeDeliveryException(message: 'Gorush fora');
      expect(await service.dispatchDue(), 1);
      expect(store.rows[id]!.status, ScheduledNoticeStatus.failed);
      expect(store.rows[id]!.failureReason, 'Gorush fora');
      await service.dispatchDue();
      expect(sends, 1);
      final e = audit.events.last;
      expect(e.result, 'failed');
      expect(e.resourceType, 'community_notice');
      expect(e.resourceId, id);
      expect(e.userId, 'adm-1');
    });

    test('resultado desconhecido vira unknown e não repete', () async {
      final id = await due();
      onSend = (_) async => throw NoticeDeliveryException(message: noticeOutcomeUnknownMessage);
      await service.dispatchDue();
      expect(store.rows[id]!.status, ScheduledNoticeStatus.unknown);
      await service.dispatchDue();
      expect(sends, 1);
    });

    test('erro inesperado de um aviso não impede o seguinte', () async {
      final a = await due();
      final b = await due();
      var n = 0;
      onSend = (_) async {
        if (++n == 1) throw StateError('boom TextoSecretoDoAviso');
        return const NoticeSendSnapshot(recipients: 1, accepted: 1);
      };
      expect(await service.dispatchDue(), 2);
      expect(store.rows[a]!.status, ScheduledNoticeStatus.failed);
      expect(store.rows[a]!.failureReason, isNot(contains('boom')));
      expect(store.rows[b]!.status, ScheduledNoticeStatus.sent);
    });

    test('auditoria de failed usa createdBy e o id do aviso, sem texto', () async {
      final id = await due();
      onSend = (_) async => throw StateError('x');
      await service.dispatchDue();
      expect(audit.events, hasLength(1));
      expect(audit.events.single.resourceId, id);
      expect(audit.events.single.userId, 'adm-1');
      expect(dump(), isNot(contains('TextoSecretoDoAviso')));
    });
  });

  group('recoverStuckSending (varredura de partida)', () {
    Future<String> row(Duration age, ScheduledNoticeStatus status) async {
      final id = await store.insert(
        createdBy: 'adm-1',
        microAreaId: _ma1,
        audience: 'everyone',
        title: 't',
        message: 'm',
        scheduledFor: now.subtract(age),
        createdAt: now.subtract(const Duration(days: 1)),
      );
      if (status == ScheduledNoticeStatus.sending) {
        await store.claimDue(now);
      }
      return id;
    }

    test('sending há mais de 10 min vira unknown com motivo fixo, nunca pending', () async {
      final old = await row(const Duration(minutes: 11), ScheduledNoticeStatus.sending);
      final recent = await row(const Duration(minutes: 9), ScheduledNoticeStatus.sending);
      final pending = await store.insert(
        createdBy: 'adm-1',
        microAreaId: _ma1,
        audience: 'everyone',
        title: 't',
        message: 'm',
        scheduledFor: now.add(const Duration(hours: 1)),
        createdAt: now,
      );
      expect(await service.recoverStuckSending(), 1);
      expect(store.rows[old]!.status, ScheduledNoticeStatus.unknown);
      expect(store.rows[old]!.failureReason, noticeStuckSendingReason);
      expect(store.rows[recent]!.status, ScheduledNoticeStatus.sending);
      expect(store.rows[pending]!.status, ScheduledNoticeStatus.pending);
      expect(sends, 0, reason: 'a varredura nunca reenvia');
    });

    test('grava uma linha de auditoria por aviso movido, sem o texto', () async {
      final a = await row(const Duration(minutes: 11), ScheduledNoticeStatus.sending);
      final b = await row(const Duration(minutes: 30), ScheduledNoticeStatus.sending);
      await row(const Duration(minutes: 2), ScheduledNoticeStatus.sending);
      expect(await service.recoverStuckSending(), 2);
      expect(audit.events.map((e) => e.resourceId), unorderedEquals([a, b]));
      for (final e in audit.events) {
        expect(e.result, 'unknown_after_restart');
        expect(e.resourceType, 'community_notice');
        expect(e.actionType, 'write');
        expect(e.userId, 'adm-1');
      }
      expect(audit.events.map((e) => '${e.userId}${e.resourceId}${e.result}').join(),
          isNot(contains('Mensagem secreta')));
      audit.events.clear();
      expect(await service.recoverStuckSending(), 0);
      expect(audit.events, isEmpty);
    });

    test('auditoria fora do ar não impede a varredura (recordSafely)', () async {
      await row(const Duration(minutes: 11), ScheduledNoticeStatus.sending);
      final svc = NoticeSchedulingService(
        store: store,
        audit: _ThrowingAudit(),
        clock: () => now,
        sendNow: ({
          required microAreaId,
          required audience,
          required title,
          required message,
          required actorId,
          auditResourceId,
        }) async => const NoticeSendSnapshot(recipients: 0, accepted: 0),
      );
      expect(await svc.recoverStuckSending(), 1);
    });
  });

  group('negação com resourceId do cliente', () {
    test('microAreaId vazio ou malformado grava evento com resourceId nulo', () async {
      for (final bad in ['', 'nao-e-uuid']) {
        audit.events.clear();
        await expectLater(
          service.schedule(_user(UserRole.acs, microAreaId: _ma1),
              microAreaId: bad,
              audience: 'everyone',
              title: 'T',
              message: 'M',
              scheduledFor: now.add(const Duration(hours: 2))),
          throwsA(isA<StateError>()),
        );
        expect(audit.events, hasLength(1));
        expect(audit.events.single.resourceId, isNull);
        expect(audit.events.single.result, 'denied_role');
      }
    });

    test('UUID válido é preservado e a negação de history é read', () async {
      await expectLater(service.history(_user(UserRole.acs), microAreaId: _ma1), throwsA(isA<StateError>()));
      expect(audit.events.single.resourceId, _ma1);
      expect(audit.events.single.actionType, 'read');
      audit.events.clear();
      await expectLater(service.history(_user(UserRole.patient)), throwsA(isA<StateError>()));
      expect(audit.events.single.resourceId, isNull);
      expect(audit.events.single.actionType, 'read');
    });
  });

  group('auditoria do disparo com o NoticeService real', () {
    late _RecipientStore recipients;
    late _Sender sender;
    late NoticeSchedulingService real;

    setUp(() {
      recipients = _RecipientStore();
      sender = _Sender();
      final notices = NoticeService(store: recipients, sender: sender, audit: audit);
      real = NoticeSchedulingService(
        store: store,
        audit: audit,
        clock: () => now,
        sendNow: notices.sendToMicroArea,
      );
    });

    Future<String> due() => store.insert(
          createdBy: 'adm-1',
          microAreaId: _ma1,
          audience: 'everyone',
          title: 'T',
          message: 'M',
          scheduledFor: now.subtract(const Duration(minutes: 1)),
          createdAt: now.subtract(const Duration(hours: 1)),
        );

    Future<void> expectResult(String audit0, ScheduledNoticeStatus status) async {
      final id = await due();
      await real.dispatchDue();
      final e = audit.events.single;
      expect(e.result, audit0);
      expect(e.resourceType, 'community_notice');
      expect(e.resourceId, id);
      expect(e.userId, 'adm-1');
      expect(store.rows[id]!.status, status);
    }

    test('granted', () => expectResult('granted', ScheduledNoticeStatus.sent));

    test('no_recipients', () {
      recipients.targets = const [];
      return expectResult('no_recipients', ScheduledNoticeStatus.sent);
    });

    test('not_delivered', () {
      sender.report = const PushSendReport(accepted: 0, invalidTokens: []);
      return expectResult('not_delivered', ScheduledNoticeStatus.sent);
    });

    test('unknown', () {
      sender.failure = const PushGatewayException('demorou', outcomeUnknown: true);
      return expectResult('unknown', ScheduledNoticeStatus.unknown);
    });
  });

  group('auditoria fail-closed (record, nunca recordSafely)', () {
    late _ThrowingAudit broken;
    late _FakeStore s2;
    late NoticeSchedulingService svc;
    var storeReads = 0;

    setUp(() {
      broken = _ThrowingAudit();
      s2 = _FakeStore()..ubsOfMicroAreaMap[_ma1] = 'ubs-1';
      storeReads = 0;
      svc = NoticeSchedulingService(
        store: _CountingStore(s2, () => storeReads++),
        audit: broken,
        clock: () => now,
        sendNow:
            ({
              required microAreaId,
              required audience,
              required title,
              required message,
              required actorId,
              auditResourceId,
            }) async => const NoticeSendSnapshot(recipients: 0, accepted: 0),
      );
    });

    test(
      'negação por papel: se a auditoria falha, a exceção da trilha sobe (não vira sucesso)',
      () async {
        await expectLater(
          svc.schedule(
            _user(UserRole.acs, microAreaId: _ma1),
            microAreaId: _ma1,
            audience: 'everyone',
            title: 'T',
            message: 'M',
            scheduledFor: now.add(const Duration(hours: 2)),
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'auditoria fora do ar',
            ),
          ),
        );
        expect(broken.calls, 1);
        expect(s2.rows, isEmpty);
      },
    );

    test('schedule: escrita ok mas auditoria falha propaga o erro', () async {
      await expectLater(
        svc.schedule(
          _user(UserRole.admin),
          microAreaId: _ma1,
          audience: 'everyone',
          title: 'T',
          message: 'M',
          scheduledFor: now.add(const Duration(hours: 2)),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'auditoria fora do ar',
          ),
        ),
      );
      expect(broken.calls, 1);
    });

    test(
      'cancel: auditoria falha propaga o erro (e negação continua negando)',
      () async {
        final id = await _insertNotice(s2);
        await expectLater(
          svc.cancel(_user(UserRole.admin), id),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'auditoria fora do ar',
            ),
          ),
        );
        await expectLater(
          svc.cancel(_user(UserRole.patient), id),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'auditoria fora do ar',
            ),
          ),
        );
      },
    );

    test('history: se a leitura não grava, o store NÃO é chamado', () async {
      await expectLater(
        svc.history(_user(UserRole.admin)),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'auditoria fora do ar',
          ),
        ),
      );
      expect(storeReads, 0);
      expect(s2.lastHistoryLimit, isNull);
    });

    test(
      'history: negação com auditoria fora do ar propaga o erro da trilha',
      () async {
        await expectLater(
          svc.history(_user(UserRole.patient)),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'auditoria fora do ar',
            ),
          ),
        );
        expect(s2.lastHistoryLimit, isNull);
      },
    );
  });

  test('history audita ANTES de consultar o store', () async {
    final order = <String>[];
    final svc = NoticeSchedulingService(
      store: _CountingStore(store, () => order.add('store')),
      audit: _OrderAudit(order),
      clock: () => now,
      sendNow:
          ({
            required microAreaId,
            required audience,
            required title,
            required message,
            required actorId,
            auditResourceId,
          }) async => const NoticeSendSnapshot(recipients: 0, accepted: 0),
    );
    await svc.history(_user(UserRole.admin));
    expect(order, ['audit', 'store']);
  });

  group('identificador que não é UUID (entrada inválida, antes do store)', () {
    const ruins = ['', 'abc', 'notice-1', '00000000-0000-4000-8000-00000000000g', "x'; drop"];

    Matcher invalido() => throwsA(isA<AdminInvalidRequestException>()
        .having((e) => e.message, 'message', 'Identificador inválido.'));

    test('schedule, cancel e history recusam sem chamar o store nem auditar', () async {
      final admin = _user(UserRole.admin);
      for (final ruim in ruins) {
        await expectLater(schedule(admin, microAreaId: ruim), invalido());
        await expectLater(service.cancel(admin, ruim), invalido());
        await expectLater(service.history(admin, microAreaId: ruim), invalido());
      }
      expect(store.rows, isEmpty);
      expect(store.lastHistoryLimit, isNull);
      expect(audit.events, isEmpty);
    });

    test('coordenador também recebe entrada inválida (não vira denied_territory)', () async {
      store.ubsOfStaffMap['c-1'] = 'ubs-1';
      final c = _user(UserRole.coordinator, id: 'c-1');
      await expectLater(schedule(c, microAreaId: 'abc'), invalido());
      await expectLater(service.cancel(c, 'abc'), invalido());
      await expectLater(service.history(c, microAreaId: 'abc'), invalido());
      expect(audit.events, isEmpty);
    });

    test('a autorização de papel vem ANTES: paciente e ACS recebem denied_role auditado', () async {
      for (final role in [UserRole.patient, UserRole.acs]) {
        await expectLater(
            schedule(_user(role, microAreaId: _ma1), microAreaId: 'abc'), throwsA(isA<StateError>()));
        expect(audit.events.last.result, 'denied_role');
        await expectLater(service.cancel(_user(role), 'abc'), throwsA(isA<StateError>()));
        expect(audit.events.last.result, 'denied_role');
        await expectLater(
            service.history(_user(role), microAreaId: 'abc'), throwsA(isA<StateError>()));
        expect(audit.events.last.result, 'denied_role');
        expect(audit.events.last.actionType, 'read');
      }
    });
  });
}
