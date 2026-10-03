import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/refresh_token_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:test/test.dart';

const _acsId = '00000000-0000-4000-8000-000000000091';
const _area = '00000000-0000-4000-8000-000000000092';
const _user = AuthenticatedUser(
    id: _acsId, role: UserRole.acs, microAreaId: _area, deviceId: 'aparelho-A');

class _MemoryStore implements RefreshTokenStore {
  final Map<String, RefreshTokenRecord> byId = {};
  final Map<String, String> hashToId = {};
  final Map<String, RefreshAccount> accounts = {};

  @override
  Future<void> insert(RefreshTokenRecord record, String tokenHash) async {
    byId[record.id] = record;
    hashToId[tokenHash] = record.id;
  }

  @override
  Future<RefreshTokenRecord?> findByHash(String tokenHash) async {
    final id = hashToId[tokenHash];
    return id == null ? null : byId[id];
  }

  @override
  Future<bool> markRotated(String id, DateTime at) async {
    final r = byId[id]!;
    if (r.rotatedAt != null || r.revokedAt != null) return false;
    byId[id] = _copy(r, rotatedAt: at);
    return true;
  }

  @override
  Future<void> revokeFamily(String familyId, DateTime at) async {
    for (final e in byId.entries.toList()) {
      if (e.value.familyId == familyId && e.value.revokedAt == null) {
        byId[e.key] = _copy(e.value, revokedAt: at);
      }
    }
  }

  @override
  Future<RefreshAccount?> findAccount(String userId) async => accounts[userId];

  @override
  Future<void> deleteExpiredFor(String userId, DateTime before) async {
    byId.removeWhere((_, r) =>
        r.userId == userId && !r.absoluteExpiresAt.isAfter(before));
  }

  RefreshTokenRecord _copy(RefreshTokenRecord r,
          {DateTime? rotatedAt, DateTime? revokedAt}) =>
      RefreshTokenRecord(
        id: r.id,
        userId: r.userId,
        familyId: r.familyId,
        deviceId: r.deviceId,
        issuedAt: r.issuedAt,
        idleExpiresAt: r.idleExpiresAt,
        absoluteExpiresAt: r.absoluteExpiresAt,
        rotatedAt: rotatedAt ?? r.rotatedAt,
        revokedAt: revokedAt ?? r.revokedAt,
      );
}

class _AuditSpy extends AuditTrail {
  final List<AuditEvent> events = [];
  @override
  Future<void> record(AuditEvent event) async => events.add(event);
  List<String> get results => events.map((e) => e.result).toList();
}

Future<void> _expectDenied(Future<Object?> Function() call) async {
  await expectLater(call, throwsA(isA<SessionExpiredException>()));
}

void main() {
  late _MemoryStore store;
  late _AuditSpy audit;
  late RefreshTokenService service;
  final t0 = DateTime.utc(2026, 10, 3, 10);

  setUp(() {
    store = _MemoryStore();
    audit = _AuditSpy();
    service = RefreshTokenService(store: store, audit: audit);
    store.accounts[_acsId] = const RefreshAccount(active: true, microAreaId: _area);
  });

  test('issue grava só o hash e devolve token de 43+ caracteres', () async {
    final token = await service.issue(_user, now: t0);
    expect(token.length, greaterThanOrEqualTo(43));
    expect(token, isNot(contains('=')));
    final hash = sha256.convert(utf8.encode(token)).toString();
    expect(store.hashToId.keys, [hash]);
    expect(store.hashToId.keys, isNot(contains(token)));
    final r = store.byId.values.single;
    expect(r.userId, _acsId);
    expect(r.deviceId, 'aparelho-A');
    expect(r.idleExpiresAt, t0.add(RefreshTokenService.idleWindow));
    expect(r.absoluteExpiresAt, t0.add(RefreshTokenService.absoluteWindow));
    expect(r.id, matches(RegExp(r'^[0-9a-f-]{36}$')));
  });

  test('refresh rotaciona: devolve token novo, marca o antigo, mesma família',
      () async {
    final first = await service.issue(_user, now: t0);
    final at = t0.add(const Duration(minutes: 10));
    final s = await service.refresh(
        refreshToken: first, deviceId: 'aparelho-A', now: at);
    expect(s.refreshToken, isNot(first));
    expect(s.user.id, _acsId);
    expect(s.user.role, UserRole.acs);
    expect(s.user.deviceId, 'aparelho-A');
    final old = await store.findByHash(sha256.convert(utf8.encode(first)).toString());
    final child = await store.findByHash(
        sha256.convert(utf8.encode(s.refreshToken)).toString());
    expect(old!.rotatedAt, at);
    expect(child!.rotatedAt, isNull);
    expect(child.familyId, old.familyId);
    // o novo token funciona
    await service.refresh(
        refreshToken: s.refreshToken, deviceId: 'aparelho-A', now: at);
  });

  test('refresh relê a microárea do banco, não a do token', () async {
    final token = await service.issue(_user, now: t0);
    const novaArea = '00000000-0000-4000-8000-000000000093';
    store.accounts[_acsId] =
        const RefreshAccount(active: true, microAreaId: novaArea);
    final s = await service.refresh(
        refreshToken: token,
        deviceId: 'aparelho-A',
        now: t0.add(const Duration(minutes: 1)));
    expect(s.user.microAreaId, novaArea);
  });

  test('conta desativada: recusa e revoga a família', () async {
    final token = await service.issue(_user, now: t0);
    store.accounts[_acsId] =
        const RefreshAccount(active: false, microAreaId: _area);
    await _expectDenied(() => service.refresh(
        refreshToken: token,
        deviceId: 'aparelho-A',
        now: t0.add(const Duration(minutes: 1))));
    expect(store.byId.values.every((r) => r.revokedAt != null), isTrue);
    expect(audit.results, contains('denied_inactive'));
  });

  test('conta sem microárea: recusa e revoga a família', () async {
    final token = await service.issue(_user, now: t0);
    store.accounts[_acsId] =
        const RefreshAccount(active: true, microAreaId: null);
    await _expectDenied(() => service.refresh(
        refreshToken: token,
        deviceId: 'aparelho-A',
        now: t0.add(const Duration(minutes: 1))));
    expect(store.byId.values.every((r) => r.revokedAt != null), isTrue);
    expect(audit.results, contains('denied_inactive'));
  });

  test('aparelho diferente: recusa e revoga a família', () async {
    final token = await service.issue(_user, now: t0);
    await _expectDenied(() => service.refresh(
        refreshToken: token,
        deviceId: 'aparelho-B',
        now: t0.add(const Duration(minutes: 1))));
    expect(store.byId.values.every((r) => r.revokedAt != null), isTrue);
    expect(audit.results, contains('denied_device'));
  });

  test('janela ociosa vencida: recusa', () async {
    final token = await service.issue(_user, now: t0);
    await _expectDenied(() => service.refresh(
        refreshToken: token,
        deviceId: 'aparelho-A',
        now: t0.add(const Duration(hours: 2, minutes: 1))));
  });

  test('teto absoluto vencido mesmo com rotação recente: recusa', () async {
    var token = await service.issue(_user, now: t0);
    var at = t0;
    // rotaciona a cada 1h50 até passar do teto de 8h
    for (var i = 0; i < 4; i++) {
      at = at.add(const Duration(hours: 1, minutes: 50));
      token = (await service.refresh(
              refreshToken: token, deviceId: 'aparelho-A', now: at))
          .refreshToken;
    }
    // at = 7h20; a próxima, em 8h01, está dentro da janela ociosa mas fora do teto
    await _expectDenied(() => service.refresh(
        refreshToken: token,
        deviceId: 'aparelho-A',
        now: t0.add(const Duration(hours: 8, minutes: 1))));
  });

  test('filho nunca passa do teto absoluto do pai', () async {
    final absolute = t0.add(RefreshTokenService.absoluteWindow);
    var token = await service.issue(_user, now: t0);
    var at = t0;
    // longe do teto: idle == agora + 2h
    at = at.add(const Duration(hours: 1, minutes: 50));
    var s = await service.refresh(
        refreshToken: token, deviceId: 'aparelho-A', now: at);
    var child = await store
        .findByHash(sha256.convert(utf8.encode(s.refreshToken)).toString());
    expect(child!.idleExpiresAt, at.add(RefreshTokenService.idleWindow));
    expect(child.absoluteExpiresAt, absolute);
    token = s.refreshToken;
    // perto do teto (7h20 + 2h > 8h): idle == teto do pai
    for (var i = 0; i < 3; i++) {
      at = at.add(const Duration(hours: 1, minutes: 50));
      s = await service.refresh(
          refreshToken: token, deviceId: 'aparelho-A', now: at);
      token = s.refreshToken;
    }
    child = await store
        .findByHash(sha256.convert(utf8.encode(token)).toString());
    expect(child!.absoluteExpiresAt, absolute);
    expect(child.idleExpiresAt, absolute);
    expect(child.idleExpiresAt,
        isNot(at.add(RefreshTokenService.idleWindow)));
  });

  test('reuso dentro da tolerância (30 s): emite token novo e NÃO revoga',
      () async {
    final first = await service.issue(_user, now: t0);
    final at = t0.add(const Duration(minutes: 5));
    await service.refresh(refreshToken: first, deviceId: 'aparelho-A', now: at);
    final s = await service.refresh(
        refreshToken: first,
        deviceId: 'aparelho-A',
        now: at.add(const Duration(seconds: 10)));
    expect(s.refreshToken, isNotEmpty);
    expect(store.byId.values.every((r) => r.revokedAt == null), isTrue);
  });

  test('reuso fora da tolerância: revoga a família inteira e recusa', () async {
    final first = await service.issue(_user, now: t0);
    final at = t0.add(const Duration(minutes: 5));
    final s = await service.refresh(
        refreshToken: first, deviceId: 'aparelho-A', now: at);
    await _expectDenied(() => service.refresh(
        refreshToken: first,
        deviceId: 'aparelho-A',
        now: at.add(const Duration(seconds: 31))));
    expect(store.byId.values.every((r) => r.revokedAt != null), isTrue);
    expect(audit.results, contains('denied_reuse'));
    // o filho vigente também caiu
    await _expectDenied(() => service.refresh(
        refreshToken: s.refreshToken,
        deviceId: 'aparelho-A',
        now: at.add(const Duration(seconds: 40))));
  });

  test('token desconhecido: recusa, sem auditoria (sem sujeito)', () async {
    await _expectDenied(() => service.refresh(
        refreshToken: 'nao-existe', deviceId: 'aparelho-A', now: t0));
    expect(audit.events, isEmpty);
  });

  test('revoke apaga a família; revoke de token desconhecido não lança',
      () async {
    final first = await service.issue(_user, now: t0);
    final s = await service.refresh(
        refreshToken: first,
        deviceId: 'aparelho-A',
        now: t0.add(const Duration(minutes: 1)));
    await service.revoke(s.refreshToken, now: t0.add(const Duration(minutes: 2)));
    expect(store.byId.values.every((r) => r.revokedAt != null), isTrue);
    await _expectDenied(() => service.refresh(
        refreshToken: s.refreshToken,
        deviceId: 'aparelho-A',
        now: t0.add(const Duration(minutes: 3))));
    await service.revoke('desconhecido', now: t0);
  });

  test('toda recusa lança a MESMA mensagem', () async {
    final messages = <String?>[];
    Future<void> capture(Future<Object?> Function() call) async {
      try {
        await call();
        fail('deveria recusar');
      } on SessionExpiredException catch (e) {
        messages.add(e.message);
      }
    }

    final a = await service.issue(_user, now: t0);
    await capture(() => service.refresh(
        refreshToken: 'desconhecido', deviceId: 'aparelho-A', now: t0));
    await capture(() => service.refresh(
        refreshToken: a, deviceId: 'aparelho-B', now: t0)); // aparelho
    final b = await service.issue(_user, now: t0);
    await capture(() => service.refresh(
        refreshToken: b,
        deviceId: 'aparelho-A',
        now: t0.add(const Duration(hours: 3)))); // expirado
    final c = await service.issue(_user, now: t0);
    store.accounts[_acsId] =
        const RefreshAccount(active: false, microAreaId: _area);
    await capture(() => service.refresh(
        refreshToken: c, deviceId: 'aparelho-A', now: t0)); // inativa

    expect(messages, hasLength(4));
    expect(messages.toSet(), {RefreshTokenService.deniedMessage});
  });

  test(
      'cada desfecho relevante gera auditoria: refresh_granted, denied_reuse, denied_device, denied_inactive',
      () async {
    final a = await service.issue(_user, now: t0);
    final at = t0.add(const Duration(minutes: 1));
    await service.refresh(refreshToken: a, deviceId: 'aparelho-A', now: at);
    await _expectDenied(() => service.refresh(
        refreshToken: a,
        deviceId: 'aparelho-A',
        now: at.add(const Duration(minutes: 1)))); // reuso
    final b = await service.issue(_user, now: t0);
    await _expectDenied(() =>
        service.refresh(refreshToken: b, deviceId: 'aparelho-B', now: at));
    final c = await service.issue(_user, now: t0);
    store.accounts[_acsId] =
        const RefreshAccount(active: false, microAreaId: _area);
    await _expectDenied(() =>
        service.refresh(refreshToken: c, deviceId: 'aparelho-A', now: at));

    expect(
        audit.results,
        containsAll(
            ['refresh_granted', 'denied_reuse', 'denied_device', 'denied_inactive']));
    expect(audit.events.every((e) => e.userId == _acsId), isTrue);
    expect(audit.events.every((e) => e.resourceType == 'session_refresh'), isTrue);
  });
}
