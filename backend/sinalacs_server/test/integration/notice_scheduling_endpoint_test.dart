import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/notices/notice_scheduling_service.dart';
import 'package:sinalacs_server/src/application/notices/notice_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_scheduled_notice_store.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

/// Serviço e store ORM reais de avisos agendados (#46) sobre o Postgres de
/// teste. O envio é um duplo: sem Gorush não há como falar com FCM aqui.
const _ubsA = '00000000-0000-4000-8000-0000000000a1';
const _ubsB = '00000000-0000-4000-8000-0000000000b1';
const _maA = '00000000-0000-4000-8000-0000000000a2';
const _maB = '00000000-0000-4000-8000-0000000000b2';
const _admin = '00000000-0000-4000-8000-0000000000c1';
const _coordA = '00000000-0000-4000-8000-0000000000c2';

class _SilentAudit extends AuditTrail {
  final events = <AuditEvent>[];
  @override
  Future<void> record(AuditEvent event) async => events.add(event);
}

AuthenticatedUser _user(String id, UserRole role) =>
    AuthenticatedUser(id: id, role: role, microAreaId: null, deviceId: 'dev');

Future<void> _seed(Session s) async {
  for (final (ubs, ma, nome) in [(_ubsA, _maA, 'Microárea A'), (_ubsB, _maB, 'Microárea B')]) {
    await Ubs.db.insertRow(
      s,
      Ubs(
        id: UuidValue.fromString(ubs),
        name: 'UBS sintética $nome',
        address: 'Endereço sintético',
        city: 'Cidade',
        state: 'SP',
      ),
    );
    await MicroArea.db.insertRow(
      s,
      MicroArea(
        id: UuidValue.fromString(ma),
        name: nome,
        ubsId: UuidValue.fromString(ubs),
        geoJsonBoundary: '{}',
      ),
    );
  }
  final now = DateTime.utc(2026, 1, 1);
  await User.db.insert(s, [
    for (final (id, role) in [(_admin, UserRole.admin), (_coordA, UserRole.coordinator)])
      User(
        id: UuidValue.fromString(id),
        cpfHash: 'sintetico-$id',
        name: 'Staff sintético',
        birthDate: DateTime.utc(1980, 1, 1),
        role: role,
        createdAt: now,
        updatedAt: now,
      ),
  ]);
  await StaffAccount.db.insertRow(
    s,
    StaffAccount(
      id: UuidValue.fromString(_coordA),
      enrollmentId: 'COO-AVISO-1',
      active: true,
      ubsId: UuidValue.fromString(_ubsA),
    ),
  );
}

void main() {
  withServerpod('Dado o agendamento de avisos sobre o Postgres (#46)', (
    sessionBuilder,
    endpoints,
  ) {
    final now = DateTime.utc(2026, 10, 14, 12);
    late Session session;
    late OrmScheduledNoticeStore store;
    late _SilentAudit audit;
    late List<String> sent;
    late NoticeSchedulingService service;
    var clock = now;

    Future<Map<String, Object?>> row(String id) async {
      final r = await session.db.unsafeQuery(
        'SELECT * FROM scheduled_notices WHERE "id" = @id::uuid',
        parameters: QueryParameters.named({'id': id}),
      );
      return r.single.toColumnMap();
    }

    Future<String> insertDue(String ma, {Duration ago = const Duration(minutes: 1)}) =>
        store.insert(
          createdBy: _admin,
          microAreaId: ma,
          audience: 'everyone',
          title: 'Título sintético',
          message: 'Mensagem sintética',
          scheduledFor: now.subtract(ago),
          createdAt: now.subtract(const Duration(hours: 1)),
        );

    setUp(() async {
      session = sessionBuilder.build();
      await _seed(session);
      store = OrmScheduledNoticeStore(session: () => session);
      audit = _SilentAudit();
      sent = [];
      clock = now;
      service = NoticeSchedulingService(
        store: store,
        audit: audit,
        clock: () => clock,
        sendNow: ({
          required microAreaId,
          required audience,
          required title,
          required message,
          required actorId,
          auditResourceId,
        }) async {
          sent.add(microAreaId);
          return const NoticeSendSnapshot(recipients: 7, accepted: 6);
        },
      );
    });

    test('agendar como admin grava uma linha pending com o texto', () async {
      final id = await service.schedule(
        _user(_admin, UserRole.admin),
        microAreaId: _maA,
        audience: 'everyone',
        title: 'Vacinação',
        message: 'Campanha na UBS',
        scheduledFor: now.add(const Duration(hours: 2)),
      );
      final r = await row(id);
      expect(r['status'], 'pending');
      expect(r['title'], 'Vacinação');
      expect(r['recipients'], isNull);
      expect(audit.events.single.result, 'scheduled');
    });

    test('dispatchDue com o relógio avançado envia e grava sent com contagens', () async {
      final id = await service.schedule(
        _user(_admin, UserRole.admin),
        microAreaId: _maA,
        audience: 'everyone',
        title: 'T',
        message: 'M',
        scheduledFor: now.add(const Duration(hours: 2)),
      );
      expect(await service.dispatchDue(), 0, reason: 'ainda não venceu');
      expect((await row(id))['status'], 'pending');

      clock = now.add(const Duration(hours: 3));
      expect(await service.dispatchDue(), 1);
      final r = await row(id);
      expect(r['status'], 'sent');
      expect(r['recipients'], 7);
      expect(r['accepted'], 6);
      expect(r['sentAt'], isNotNull);
      expect(sent, [_maA]);
      expect(await service.dispatchDue(), 0, reason: 'não reenvia o que já foi enviado');
    });

    test('claimDue concorrente reserva cada linha uma única vez', () async {
      final ids = [for (var i = 0; i < 6; i++) await insertDue(_maA)];
      final results = await Future.wait([
        store.claimDue(now, limit: 4),
        store.claimDue(now, limit: 4),
        store.claimDue(now, limit: 4),
      ]);
      final claimed = results.expand((l) => l.map((s) => s.id)).toList();
      expect(claimed, hasLength(ids.length));
      expect(claimed.toSet(), ids.toSet());
      for (final id in ids) {
        expect((await row(id))['status'], 'sending');
      }
      expect(await store.claimDue(now), isEmpty);
    });

    test('claimDue não reserva o que ainda não venceu', () async {
      final futuro = await store.insert(
        createdBy: _admin,
        microAreaId: _maA,
        audience: 'everyone',
        title: 'T',
        message: 'M',
        scheduledFor: now.add(const Duration(hours: 1)),
        createdAt: now,
      );
      expect(await store.claimDue(now), isEmpty);
      expect((await row(futuro))['status'], 'pending');
    });

    test('cancelIfPending só cancela pending', () async {
      final pendente = await insertDue(_maA);
      expect(await store.cancelIfPending(pendente), isTrue);
      expect((await row(pendente))['status'], 'cancelled');
      expect(await store.cancelIfPending(pendente), isFalse);

      final enviando = await insertDue(_maA);
      await store.claimDue(now);
      expect(await store.cancelIfPending(enviando), isFalse);
      expect((await row(enviando))['status'], 'sending');

      await store.finish(enviando, status: ScheduledNoticeStatus.sent, recipients: 1, accepted: 1, at: now);
      expect(await store.cancelIfPending(enviando), isFalse);
      expect((await row(enviando))['status'], 'sent');
    });

    test('history do coordenador só traz a própria UBS, em ordem decrescente', () async {
      final a1 = await insertDue(_maA, ago: const Duration(hours: 3));
      final a2 = await insertDue(_maA, ago: const Duration(hours: 1));
      final b1 = await insertDue(_maB);
      final coord = await service.history(_user(_coordA, UserRole.coordinator));
      expect(coord.map((i) => i.id), [a2, a1]);
      expect(coord.map((i) => i.id), isNot(contains(b1)));
      final admin = await service.history(_user(_admin, UserRole.admin));
      expect(admin.map((i) => i.id).toSet(), {a1, a2, b1});
      final soB = await store.history(microAreaId: _maB, limit: 10, offset: 0);
      expect(soB.map((s) => s.id), [b1]);
      final pagina = await store.history(ubsId: _ubsA, limit: 1, offset: 1);
      expect(pagina.map((s) => s.id), [a1]);
    });

    test('findById devolve a linha ou null; ubsOf* leem staff e microárea', () async {
      final id = await insertDue(_maA);
      final s = (await store.findById(id))!;
      expect(s.status, ScheduledNoticeStatus.pending);
      expect(s.createdBy, _admin);
      expect(s.microAreaId, _maA);
      expect(s.message, 'Mensagem sintética');
      expect(s.scheduledFor.isUtc, isTrue);
      expect(await store.findById('00000000-0000-4000-8000-0000000000ff'), isNull);
      expect(await store.ubsOfStaff(_coordA), _ubsA);
      expect(await store.ubsOfStaff(_admin), isNull);
      expect(await store.ubsOfMicroArea(_maB), _ubsB);
      expect(await store.ubsOfMicroArea('00000000-0000-4000-8000-0000000000ff'), isNull);
    });

    test('a varredura leva sending antigo a unknown, sem tocar o recente nem o pending', () async {
      final velho = await insertDue(_maA, ago: const Duration(minutes: 30));
      final recente = await insertDue(_maA, ago: const Duration(minutes: 2));
      await store.claimDue(now);
      final pendente = await store.insert(
        createdBy: _admin,
        microAreaId: _maA,
        audience: 'everyone',
        title: 'T',
        message: 'M',
        scheduledFor: now.add(const Duration(hours: 1)),
        createdAt: now,
      );
      audit.events.clear();
      expect(await service.recoverStuckSending(), 1);
      expect(audit.events, hasLength(1));
      expect(audit.events.single.result, 'unknown_after_restart');
      expect(audit.events.single.resourceId, velho);
      expect(audit.events.single.userId, _admin);
      expect(audit.events.single.resourceType, 'community_notice');
      final r = await row(velho);
      expect(r['status'], 'unknown');
      expect(r['failureReason'], noticeStuckSendingReason);
      expect((await row(recente))['status'], 'sending');
      expect((await row(pendente))['status'], 'pending');
      expect(await service.recoverStuckSending(), 0);
      expect(audit.events, hasLength(1), reason: 'sem avisos presos, nada novo na trilha');
      expect(sent, isEmpty, reason: 'a varredura nunca reenvia');
    });
  });
}
