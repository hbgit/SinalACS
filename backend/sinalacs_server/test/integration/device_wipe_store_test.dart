import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_device_wipe_store.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

/// Pedido de limpeza remota (#81) contra Postgres real: revogação por aparelho
/// na mesma transação, idempotência pelo índice único e o estado derivado dos
/// carimbos. Dados sintéticos.
const _u1 = '00000000-0000-4000-8000-00000000d001';
const _u2 = '00000000-0000-4000-8000-00000000d002';
const _u3 = '00000000-0000-4000-8000-00000000d003';
const _admin = '00000000-0000-4000-8000-00000000d004';

const _aparelhoD = 'dddddddd-aparelho-d';
const _aparelhoE = 'eeeeeeee-aparelho-e';

final _t = DateTime.utc(2026, 10, 17, 9);

final _ev = AuditEvent(
  userId: _u1,
  actionType: 'write',
  resourceType: 'acs_device',
  result: 'teste',
);

var _seq = 0;
UuidValue _id() => UuidValue.fromString(
  '00000000-0000-4000-8000-${(0xd100 + (++_seq)).toRadixString(16).padLeft(12, '0')}',
);

Future<void> _usuario(Session s, String id, UserRole role) => User.db
    .insertRow(
      s,
      User(
        id: UuidValue.fromString(id),
        cpfHash: 'wipe-$id',
        name: 'Usuário sintético',
        birthDate: DateTime.utc(1980),
        role: role,
        createdAt: _t,
        updatedAt: _t,
      ),
    )
    .then((_) {});

Future<void> _refresh(Session s, String user, String device, DateTime issued) =>
    AcsRefreshToken.db
        .insertRow(
          s,
          AcsRefreshToken(
            id: _id(),
            userId: UuidValue.fromString(user),
            familyId: _id(),
            tokenHash: 'r-${_id()}',
            deviceId: device,
            issuedAt: issued,
            idleExpiresAt: issued.add(const Duration(hours: 2)),
            absoluteExpiresAt: issued.add(const Duration(hours: 8)),
          ),
        )
        .then((_) {});

Future<void> _envio(Session s, String user, String device, DateTime issued) =>
    AcsUploadToken.db
        .insertRow(
          s,
          AcsUploadToken(
            id: _id(),
            userId: UuidValue.fromString(user),
            tokenHash: 'u-${_id()}',
            deviceId: device,
            issuedAt: issued,
            expiresAt: issued.add(const Duration(days: 7)),
          ),
        )
        .then((_) {});

Future<int> _vivos(Session s, String tabela, String device) async {
  final r = await s.db.unsafeQuery(
    'SELECT count(*) FROM $tabela WHERE "deviceId" = @d AND "revokedAt" IS NULL',
    parameters: QueryParameters.named({'d': device}),
  );
  return r.single[0]! as int;
}

void main() {
  withServerpod('Dado o pedido de limpeza remota do aparelho (#81)', (
    sessionBuilder,
    endpoints,
  ) {
    late Session session;
    late OrmDeviceWipeStore store;
    late List<AuditEvent> auditados;
    var falhaNaTrilha = false;
    setUp(() async {
      session = sessionBuilder.build();
      auditados = [];
      falhaNaTrilha = false;
      store = OrmDeviceWipeStore(
        session: () => session,
        appendAudit: (s, transaction, event) async {
          if (falhaNaTrilha) throw StateError('trilha fora do ar');
          auditados.add(event);
        },
      );
      await _usuario(session, _u1, UserRole.acs);
      await _usuario(session, _u2, UserRole.acs);
      await _usuario(session, _u3, UserRole.acs);
      await _usuario(session, _admin, UserRole.admin);
      // Aparelho D: dois donos (refresh + envio); aparelho E: outro usuário.
      await _refresh(session, _u1, _aparelhoD, _t);
      await _envio(session, _u1, _aparelhoD, _t.add(const Duration(hours: 1)));
      await _refresh(session, _u2, _aparelhoD, _t);
      await _envio(session, _u2, _aparelhoD, _t);
      await _refresh(session, _u3, _aparelhoE, _t);
      await _envio(session, _u3, _aparelhoE, _t);
    });

    Future<({DeviceWipeOrder order, bool created})> pedir({
      DateTime? at,
    }) => store.orderWipe(
      deviceId: _aparelhoD,
      targetUserId: _u1,
      requestedBy: _admin,
      reason: DeviceWipeReason.lost,
      at: at ?? _t.add(const Duration(days: 1)),
    );

    test(
      'orderWipe revoga refresh e envio de todos os donos do deviceId e só dele',
      () async {
        expect(await _vivos(session, 'acs_refresh_tokens', _aparelhoD), 2);
        expect(await _vivos(session, 'acs_upload_tokens', _aparelhoD), 2);

        final r = await pedir();
        expect(r.created, isTrue);
        expect(r.order.deviceId, _aparelhoD);
        expect(r.order.reason, DeviceWipeReason.lost);

        expect(await _vivos(session, 'acs_refresh_tokens', _aparelhoD), 0);
        expect(await _vivos(session, 'acs_upload_tokens', _aparelhoD), 0);
        expect(await _vivos(session, 'acs_refresh_tokens', _aparelhoE), 1);
        expect(await _vivos(session, 'acs_upload_tokens', _aparelhoE), 1);
      },
    );

    test('segundo orderWipe não cria linha nem revoga de novo', () async {
      final primeiro = await pedir();
      // Token novo no mesmo aparelho depois do pedido: o segundo pedido não
      // pode revogá-lo.
      await _refresh(session, _u1, _aparelhoD, _t.add(const Duration(days: 2)));
      final segundo = await pedir(at: _t.add(const Duration(days: 3)));
      expect(segundo.created, isFalse);
      expect(segundo.order.id, primeiro.order.id);
      expect(segundo.order.requestedAt, primeiro.order.requestedAt);
      expect(await _vivos(session, 'acs_refresh_tokens', _aparelhoD), 1);
      final n = await DeviceWipeOrder.db.count(
        session,
        where: (t) => t.deviceId.equals(_aparelhoD),
      );
      expect(n, 1);
    });

    test(
      'devicesOf agrupa por deviceId, lastSeenAt = maior issuedAt, junta estado do pedido',
      () async {
        var lista = await store.devicesOf(_u1);
        expect(lista, hasLength(1));
        expect(lista.single.deviceId, _aparelhoD);
        expect(lista.single.label, 'Aparelho dddddddd');
        expect(lista.single.lastSeenAt, _t.add(const Duration(hours: 1)));
        expect(lista.single.wipeState, isNull);

        final pedido = await pedir();
        final id = pedido.order.id.toString();
        lista = await store.devicesOf(_u1);
        expect(lista.single.wipeState, DeviceWipeState.pending);
        expect(lista.single.wipeRequestedAt, pedido.order.requestedAt);

        expect(await store.markDelivered(id, _t.add(const Duration(days: 2)), audit: _ev), isTrue);
        expect(await store.markDelivered(id, _t.add(const Duration(days: 3)), audit: _ev), isFalse);
        lista = await store.devicesOf(_u1);
        expect(lista.single.wipeState, DeviceWipeState.delivered);

        expect(await store.markConfirmed(_aparelhoE, id, _t, audit: _ev), isFalse);
        expect(await store.markConfirmed(_aparelhoD, id, _t.add(const Duration(days: 4)), audit: _ev), isTrue);
        expect(await store.markConfirmed(_aparelhoD, id, _t.add(const Duration(days: 5)), audit: _ev), isFalse);
        lista = await store.devicesOf(_u1);
        expect(lista.single.wipeState, DeviceWipeState.confirmed);
        expect(lista.single.wipeConfirmedAt, _t.add(const Duration(days: 4)));
        expect((await store.orderFor(_aparelhoD))!.id.toString(), id);
        expect(await store.orderFor(_aparelhoE), isNull);
        // Só as duas primeiras gravações auditam; repetição e par errado não.
        expect(auditados, hasLength(2));
      },
    );

    test(
      'se a trilha falha, o carimbo é desfeito e a repetição ainda audita',
      () async {
        final id = (await pedir()).order.id.toString();

        falhaNaTrilha = true;
        await expectLater(
          store.markDelivered(id, _t.add(const Duration(days: 2)), audit: _ev),
          throwsA(isA<StateError>()),
        );
        expect((await store.orderFor(_aparelhoD))!.deliveredAt, isNull);
        falhaNaTrilha = false;
        expect(
          await store.markDelivered(
            id,
            _t.add(const Duration(days: 2)),
            audit: _ev,
          ),
          isTrue,
        );

        falhaNaTrilha = true;
        await expectLater(
          store.markConfirmed(
            _aparelhoD,
            id,
            _t.add(const Duration(days: 3)),
            audit: _ev,
          ),
          throwsA(isA<StateError>()),
        );
        expect((await store.orderFor(_aparelhoD))!.confirmedAt, isNull);
        falhaNaTrilha = false;
        expect(
          await store.markConfirmed(
            _aparelhoD,
            id,
            _t.add(const Duration(days: 3)),
            audit: _ev,
          ),
          isTrue,
        );
        expect(auditados, hasLength(2));
      },
    );

    test('deviceBelongsTo só para quem tem token no aparelho', () async {
      expect(await store.deviceBelongsTo(_u1, _aparelhoD), isTrue);
      expect(await store.deviceBelongsTo(_u1, _aparelhoE), isFalse);
      expect(await store.deviceBelongsTo('nao-uuid', _aparelhoD), isFalse);
    });
  });
}
