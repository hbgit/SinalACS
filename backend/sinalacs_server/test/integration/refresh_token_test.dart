import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/auth/refresh_token_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_refresh_token_store.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

/// Store do refresh token (LGPD-RT06) contra Postgres real: prova a rotação
/// atômica e o fechamento da corrida entre `insert` e `revokeFamily`, que um
/// store falso não alcança. Dados sintéticos; ids próprios (`...0a1`).
const _ubsId = '00000000-0000-4000-8000-0000000000a1';
const _microAreaId = '00000000-0000-4000-8000-0000000000a2';
const _acsId = '00000000-0000-4000-8000-0000000000a3';
const _outroAcsId = '00000000-0000-4000-8000-0000000000a4';
const _pacienteId = '00000000-0000-4000-8000-0000000000a5';
const _familiaA = '00000000-0000-4000-8000-0000000000b1';
const _familiaB = '00000000-0000-4000-8000-0000000000b2';

String _sha(String t) => sha256.convert(utf8.encode(t)).toString();

String _id(int n) =>
    '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';

Future<void> _seed(Session session) async {
  await Ubs.db.insertRow(
    session,
    Ubs(
      id: UuidValue.fromString(_ubsId),
      name: 'UBS Refresh',
      address: 'Endereço local',
      city: 'São Paulo',
      state: 'SP',
    ),
  );
  await MicroArea.db.insertRow(
    session,
    MicroArea(
      id: UuidValue.fromString(_microAreaId),
      name: 'Microárea Refresh',
      ubsId: UuidValue.fromString(_ubsId),
      geoJsonBoundary: '{}',
    ),
  );
  final now = DateTime.now().toUtc();
  Future<void> user(String id, UserRole role, String cpf) => User.db.insertRow(
    session,
    User(
      id: UuidValue.fromString(id),
      cpfHash: cpf,
      name: 'Usuário sintético',
      birthDate: DateTime.utc(1980),
      role: role,
      microAreaId: UuidValue.fromString(_microAreaId),
      createdAt: now,
      updatedAt: now,
    ),
  );
  await user(_acsId, UserRole.acs, 'development-acs-refresh');
  await user(_outroAcsId, UserRole.acs, 'development-acs-refresh-2');
  await user(_pacienteId, UserRole.patient, 'development-patient-refresh');
  await Acs.db.insertRow(
    session,
    Acs(
      id: UuidValue.fromString(_acsId),
      enrollmentId: 'ACS-REFRESH-001',
      ubsId: UuidValue.fromString(_ubsId),
      active: true,
    ),
  );
  await Acs.db.insertRow(
    session,
    Acs(
      id: UuidValue.fromString(_outroAcsId),
      enrollmentId: 'ACS-REFRESH-002',
      ubsId: UuidValue.fromString(_ubsId),
      active: false,
    ),
  );
}

RefreshTokenRecord _record(
  String id, {
  String userId = _acsId,
  String familyId = _familiaA,
  DateTime? absolute,
}) {
  final at = DateTime.utc(2026, 10, 3, 12);
  return RefreshTokenRecord(
    id: id,
    userId: userId,
    familyId: familyId,
    deviceId: 'device-1',
    issuedAt: at,
    idleExpiresAt: at.add(const Duration(hours: 2)),
    absoluteExpiresAt: absolute ?? at.add(const Duration(hours: 8)),
  );
}

OrmRefreshTokenStore _store(Session s) =>
    OrmRefreshTokenStore(session: () => s);

void main() {
  withServerpod('Dado o store do refresh token do ACS', (
    sessionBuilder,
    endpoints,
  ) {
    late Session session;
    late OrmRefreshTokenStore store;

    setUp(() async {
      session = sessionBuilder.build();
      await _seed(session);
      store = _store(session);
    });

    test(
      'insert + findByHash devolvem os mesmos campos e a linha guarda só o hash',
      () async {
        final r = _record(_id(1));
        expect(await store.insert(r, _sha('token-em-claro')), isTrue);

        final lido = await store.findByHash(_sha('token-em-claro'));
        expect(lido, isNotNull);
        expect(lido!.id, r.id);
        expect(lido.userId, r.userId);
        expect(lido.familyId, r.familyId);
        expect(lido.deviceId, r.deviceId);
        expect(lido.issuedAt, r.issuedAt);
        expect(lido.idleExpiresAt, r.idleExpiresAt);
        expect(lido.absoluteExpiresAt, r.absoluteExpiresAt);
        expect(lido.rotatedAt, isNull);
        expect(lido.revokedAt, isNull);

        final linhas = await AcsRefreshToken.db.find(session);
        expect(linhas, hasLength(1));
        expect(linhas.single.tokenHash, _sha('token-em-claro'));
        expect(linhas.single.tokenHash, isNot('token-em-claro'));
        expect(await store.findByHash(_sha('outro')), isNull);
      },
    );

    test(
      'markRotated em linha vigente devolve true, e a segunda vez false',
      () async {
        await store.insert(_record(_id(1)), _sha('t1'));
        expect(
          await store.markRotated(_id(1), DateTime.utc(2026, 10, 3, 13)),
          isTrue,
        );
        expect(
          await store.markRotated(_id(1), DateTime.utc(2026, 10, 3, 13)),
          isFalse,
        );
        expect(
          (await store.findByHash(_sha('t1')))!.rotatedAt,
          DateTime.utc(2026, 10, 3, 13),
        );
      },
    );

    test('markRotated em linha revogada devolve false', () async {
      await store.insert(_record(_id(1)), _sha('t1'));
      await store.revokeFamily(_familiaA, DateTime.utc(2026, 10, 3, 13));
      expect(
        await store.markRotated(_id(1), DateTime.utc(2026, 10, 3, 14)),
        isFalse,
      );
    });

    test('revokeFamily revoga a família inteira e só ela', () async {
      await store.insert(_record(_id(1)), _sha('a1'));
      await store.insert(_record(_id(2)), _sha('a2'));
      await store.insert(_record(_id(3), familyId: _familiaB), _sha('b1'));
      final at = DateTime.utc(2026, 10, 3, 13);
      await store.revokeFamily(_familiaA, at);

      expect((await store.findByHash(_sha('a1')))!.revokedAt, at);
      expect((await store.findByHash(_sha('a2')))!.revokedAt, at);
      expect((await store.findByHash(_sha('b1')))!.revokedAt, isNull);
    });

    test(
      'insert em família com token revogado devolve false e não grava nada',
      () async {
        await store.insert(_record(_id(1)), _sha('a1'));
        await store.revokeFamily(_familiaA, DateTime.utc(2026, 10, 3, 13));

        expect(await store.insert(_record(_id(2)), _sha('a2')), isFalse);
        expect(await store.findByHash(_sha('a2')), isNull);
        expect(await AcsRefreshToken.db.find(session), hasLength(1));
      },
    );

    test('insert em família vigente (ou nova) devolve true', () async {
      expect(await store.insert(_record(_id(1)), _sha('a1')), isTrue);
      expect(await store.insert(_record(_id(2)), _sha('a2')), isTrue);
      // Revogar outra família não impede esta.
      await store.insert(_record(_id(3), familyId: _familiaB), _sha('b1'));
      await store.revokeFamily(_familiaB, DateTime.utc(2026, 10, 3, 13));
      expect(await store.insert(_record(_id(4)), _sha('a3')), isTrue);
      expect(await AcsRefreshToken.db.find(session), hasLength(4));
    });

    test('findAccount devolve active e microAreaId reais', () async {
      final ativo = await store.findAccount(_acsId);
      expect(ativo!.active, isTrue);
      expect(ativo.microAreaId, _microAreaId);

      final inativo = await store.findAccount(_outroAcsId);
      expect(inativo!.active, isFalse);
      expect(inativo.microAreaId, _microAreaId);
    });

    test(
      'findAccount devolve null para quem não é ACS ou não existe',
      () async {
        expect(await store.findAccount(_pacienteId), isNull);
        expect(await store.findAccount(_id(999)), isNull);
      },
    );

    test(
      'deleteExpiredFor só apaga linhas do próprio usuário vencidas',
      () async {
        final base = DateTime.utc(2026, 10, 3, 12);
        await store.insert(
          _record(_id(1), absolute: base.subtract(const Duration(hours: 1))),
          _sha('vencido'),
        );
        await store.insert(
          _record(_id(2), absolute: base.add(const Duration(hours: 1))),
          _sha('vigente'),
        );
        await store.insert(
          _record(
            _id(3),
            userId: _outroAcsId,
            familyId: _familiaB,
            absolute: base.subtract(const Duration(hours: 1)),
          ),
          _sha('vencido-de-outro'),
        );

        await store.deleteExpiredFor(_acsId, base);

        expect(await store.findByHash(_sha('vencido')), isNull);
        expect(await store.findByHash(_sha('vigente')), isNotNull);
        expect(await store.findByHash(_sha('vencido-de-outro')), isNotNull);
      },
    );
  });

  // Corridas precisam de conexões independentes: sem rollback automático cada
  // `Session` usa a sua. A limpeza é manual, no `finally`.
  withServerpod(
    'Dado o store do refresh token, sem rollback (corridas)',
    (
      sessionBuilder,
      endpoints,
    ) {
      Future<void> limpar() async {
        final s = sessionBuilder.build();
        final a = UuidValue.fromString(_acsId);
        final b = UuidValue.fromString(_outroAcsId);
        final p = UuidValue.fromString(_pacienteId);
        await AcsRefreshToken.db.deleteWhere(
          s,
          where: (t) => t.userId.equals(a) | t.userId.equals(b),
        );
        await Acs.db.deleteWhere(
          s,
          where: (t) => t.id.equals(a) | t.id.equals(b),
        );
        await User.db.deleteWhere(
          s,
          where: (t) => t.id.equals(a) | t.id.equals(b) | t.id.equals(p),
        );
        await MicroArea.db.deleteWhere(
          s,
          where: (t) => t.id.equals(UuidValue.fromString(_microAreaId)),
        );
        await Ubs.db.deleteWhere(
          s,
          where: (t) => t.id.equals(UuidValue.fromString(_ubsId)),
        );
      }

      test('markRotated em paralelo: exatamente um true', () async {
        await limpar();
        try {
          await _seed(sessionBuilder.build());
          await _store(
            sessionBuilder.build(),
          ).insert(_record(_id(1)), _sha('t1'));
          final resultados = await Future.wait([
            for (var i = 0; i < 6; i++)
              _store(
                sessionBuilder.build(),
              ).markRotated(_id(1), DateTime.utc(2026, 10, 3, 13)),
          ]);
          expect(resultados.where((r) => r), hasLength(1));
        } finally {
          await limpar();
        }
      });

      test(
        'insert concorrente com revokeFamily nunca deixa filho vigente após a revogação',
        () async {
          await limpar();
          try {
            await _seed(sessionBuilder.build());
            for (var i = 0; i < 8; i++) {
              final familia = _id(0x100 + i);
              await _store(sessionBuilder.build()).insert(
                _record(_id(0x200 + i * 10), familyId: familia),
                _sha('pai$i'),
              );
              await Future.wait([
                for (var k = 1; k <= 3; k++)
                  _store(sessionBuilder.build()).insert(
                    _record(_id(0x200 + i * 10 + k), familyId: familia),
                    _sha('f$i-$k'),
                  ),
                _store(
                  sessionBuilder.build(),
                ).revokeFamily(familia, DateTime.utc(2026, 10, 3, 13)),
              ]);
              // A revogação já terminou: nenhuma linha da família pode estar vigente,
              // e nenhum insert posterior pode passar.
              final vigentes = await AcsRefreshToken.db.find(
                sessionBuilder.build(),
                where: (t) =>
                    t.familyId.equals(UuidValue.fromString(familia)) &
                    t.revokedAt.equals(null),
              );
              expect(vigentes, isEmpty, reason: 'iteração $i');
              expect(
                await _store(sessionBuilder.build()).insert(
                  _record(_id(0x200 + i * 10 + 9), familyId: familia),
                  _sha('tarde$i'),
                ),
                isFalse,
              );
            }
          } finally {
            await limpar();
          }
        },
      );
    },
    rollbackDatabase: RollbackDatabase.disabled,
  );
}
