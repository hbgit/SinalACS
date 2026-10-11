import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/auth/refresh_token_service.dart';
import 'package:sinalacs_server/src/application/auth/totp.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/database/orm_refresh_token_store.dart';
import 'package:test/test.dart';

import 'test_tools/runtime_harness.dart';
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
  endpointTests();
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

const _matricula = 'ACS-REFRESH-001';
const _senha = 'senha-sintetica-de-teste';
const _aparelho = 'aparelho-refresh-1';
const _outraMicroArea = '00000000-0000-4000-8000-0000000000a6';

Uint8List _deBase32(String texto) {
  const alfabeto = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  var bits = 0;
  var valor = 0;
  final saida = <int>[];
  for (final c in texto.split('')) {
    valor = (valor << 5) | alfabeto.indexOf(c);
    bits += 5;
    if (bits >= 8) {
      saida.add((valor >> (bits - 8)) & 0xff);
      bits -= 8;
    }
  }
  return Uint8List.fromList(saida);
}

/// Endpoints `auth.loginInstitutional`, `refreshSession` e `logout` contra
/// Postgres real. O relógio do endpoint não é injetável: o envelhecimento do
/// token é feito reescrevendo `rotatedAt` pelo ORM.
void endpointTests() {
  withServerpod('Dado o refresh token do ACS nos endpoints de auth', (
    sessionBuilder,
    endpoints,
  ) {
    late Session session;
    late Uint8List segredo;
    var passo = 0;

    setUp(() async {
      session = sessionBuilder.build();
      await _seed(session);
      await AlertRuntimeHarness.store(session).saveCredential(
        _acsId,
        await AlertRuntimeHarness.hasher.derive(_senha),
        DateTime.now().toUtc(),
      );
      final inicio = await endpoints.auth.beginTotpEnrollment(
        sessionBuilder,
        matricula: _matricula,
        password: _senha,
      );
      segredo = _deBase32(inicio.secretBase32);
      final agora = DateTime.now().toUtc();
      await endpoints.auth.confirmTotpEnrollment(
        sessionBuilder,
        matricula: _matricula,
        password: _senha,
        code: Totp.code(segredo, agora),
      );
      passo = 1;
    });

    Future<DevelopmentLoginResult> entrar() {
      final codigo = Totp.code(
        segredo,
        DateTime.now().toUtc().add(Duration(seconds: Totp.period * passo++)),
      );
      return endpoints.auth.loginInstitutional(
        sessionBuilder,
        matricula: _matricula,
        password: _senha,
        deviceId: _aparelho,
        totpCode: codigo,
      );
    }

    test('o login com MFA devolve refresh token e o device_id do JWT', () async {
      final login = await entrar();
      expect(login.refreshToken, isNotEmpty);
      final user = AlertRuntimeHarness.verify(login.accessToken);
      expect(user?.deviceId, _aparelho);
    });

    test('refreshSession troca o token sem senha nem TOTP', () async {
      final login = await entrar();
      final renovado = await endpoints.auth.refreshSession(
        sessionBuilder,
        refreshToken: login.refreshToken!,
        deviceId: _aparelho,
      );
      final user = AlertRuntimeHarness.verify(renovado.accessToken);
      expect(user, isNotNull);
      expect(user!.id, _acsId);
      expect(user.microAreaId, _microAreaId);
      expect(renovado.refreshToken, isNotEmpty);
      expect(renovado.refreshToken, isNot(login.refreshToken));
    });

    test('reuso do token antigo além da tolerância revoga a família', () async {
      final login = await entrar();
      final filho = await endpoints.auth.refreshSession(
        sessionBuilder,
        refreshToken: login.refreshToken!,
        deviceId: _aparelho,
      );
      // Envelhece a rotação do pai: o relógio do endpoint não é injetável.
      final hash = sha256.convert(utf8.encode(login.refreshToken!)).toString();
      final pai = (await AcsRefreshToken.db.findFirstRow(
        session,
        where: (t) => t.tokenHash.equals(hash),
      ))!;
      pai.rotatedAt = DateTime.now().toUtc().subtract(
            const Duration(minutes: 5),
          );
      await AcsRefreshToken.db.updateRow(session, pai);

      await expectLater(
        endpoints.auth.refreshSession(
          sessionBuilder,
          refreshToken: login.refreshToken!,
          deviceId: _aparelho,
        ),
        throwsA(isA<SessionExpiredException>()),
      );
      await expectLater(
        endpoints.auth.refreshSession(
          sessionBuilder,
          refreshToken: filho.refreshToken!,
          deviceId: _aparelho,
        ),
        throwsA(isA<SessionExpiredException>()),
      );
    });

    test('a microárea nova do banco chega ao JWT seguinte', () async {
      final login = await entrar();
      await MicroArea.db.insertRow(
        session,
        MicroArea(
          id: UuidValue.fromString(_outraMicroArea),
          name: 'Outra microárea',
          ubsId: UuidValue.fromString(_ubsId),
          geoJsonBoundary: '{}',
        ),
      );
      final u = (await User.db.findById(session, UuidValue.fromString(_acsId)))!;
      u.microAreaId = UuidValue.fromString(_outraMicroArea);
      await User.db.updateRow(session, u);

      final renovado = await endpoints.auth.refreshSession(
        sessionBuilder,
        refreshToken: login.refreshToken!,
        deviceId: _aparelho,
      );
      expect(
        AlertRuntimeHarness.verify(renovado.accessToken)?.microAreaId,
        _outraMicroArea,
      );
    });

    test('ACS desativado recebe SessionExpiredException', () async {
      final login = await entrar();
      final acs = (await Acs.db.findById(session, UuidValue.fromString(_acsId)))!;
      acs.active = false;
      await Acs.db.updateRow(session, acs);
      await expectLater(
        endpoints.auth.refreshSession(
          sessionBuilder,
          refreshToken: login.refreshToken!,
          deviceId: _aparelho,
        ),
        throwsA(isA<SessionExpiredException>()),
      );
      // A recusa revogou a família: reativar o ACS não reabre o token.
      acs.active = true;
      await Acs.db.updateRow(session, acs);
      await expectLater(
        endpoints.auth.refreshSession(
          sessionBuilder,
          refreshToken: login.refreshToken!,
          deviceId: _aparelho,
        ),
        throwsA(isA<SessionExpiredException>()),
      );
    });

    test('login sem deviceId (ausente ou em branco) não emite refresh token',
        () async {
      for (final id in <String?>[null, '', '   ']) {
        // O passo do TOTP só avança: zera o último usado para repetir o login.
        final cred = (await UserCredential.db.findFirstRow(
          session,
          where: (t) => t.userId.equals(UuidValue.fromString(_acsId)),
        ))!;
        cred.totpLastStep = null;
        await UserCredential.db.updateRow(session, cred);
        final codigo = Totp.code(segredo, DateTime.now().toUtc());
        final login = await endpoints.auth.loginInstitutional(
          sessionBuilder,
          matricula: _matricula,
          password: _senha,
          deviceId: id,
          totpCode: codigo,
        );
        expect(login.accessToken, isNotEmpty, reason: 'deviceId=$id');
        expect(login.refreshToken, isNull, reason: 'deviceId=$id');
      }
    });

    test('refreshSession de outro aparelho é recusado e revoga a família',
        () async {
      final login = await entrar();
      final filho = await endpoints.auth.refreshSession(
        sessionBuilder,
        refreshToken: login.refreshToken!,
        deviceId: _aparelho,
      );
      await expectLater(
        endpoints.auth.refreshSession(
          sessionBuilder,
          refreshToken: filho.refreshToken!,
          deviceId: 'aparelho-do-ladrao',
        ),
        throwsA(isA<SessionExpiredException>()),
      );
      await expectLater(
        endpoints.auth.refreshSession(
          sessionBuilder,
          refreshToken: filho.refreshToken!,
          deviceId: _aparelho,
        ),
        throwsA(isA<SessionExpiredException>()),
      );
    });

    test('logout revoga o token; token desconhecido não lança', () async {
      final login = await entrar();
      await endpoints.auth.logout(
        sessionBuilder,
        refreshToken: login.refreshToken!,
      );
      await expectLater(
        endpoints.auth.refreshSession(
          sessionBuilder,
          refreshToken: login.refreshToken!,
          deviceId: _aparelho,
        ),
        throwsA(isA<SessionExpiredException>()),
      );
      await endpoints.auth.logout(sessionBuilder, refreshToken: 'inexistente');
    });
  });
}
