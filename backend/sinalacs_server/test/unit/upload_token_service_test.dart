import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/institutional_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/refresh_token_service.dart';
import 'package:sinalacs_server/src/application/auth/upload_token_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:test/test.dart';

/// Token de envio diferido do ACS (D7 do plano 2026-10-03), com store em
/// memória. Dados sintéticos.
const _acsId = '00000000-0000-4000-8000-0000000000c1';
const _area = '00000000-0000-4000-8000-0000000000c2';
const _novaArea = '00000000-0000-4000-8000-0000000000c3';
const _user = AuthenticatedUser(
    id: _acsId, role: UserRole.acs, microAreaId: _area, deviceId: 'aparelho-A');

String _sha(String t) => sha256.convert(utf8.encode(t)).toString();

class _MemoryStore implements UploadTokenStore {
  final Map<String, UploadTokenRecord> byId = {};
  final Map<String, String> hashToId = {};
  final Map<String, RefreshAccount> accounts = {};

  @override
  Future<void> replace(UploadTokenRecord record, String tokenHash) async {
    for (final e in byId.entries.toList()) {
      final r = e.value;
      if (r.userId == record.userId &&
          r.deviceId == record.deviceId &&
          r.revokedAt == null) {
        byId[e.key] = _copy(r, revokedAt: record.issuedAt);
      }
    }
    byId[record.id] = record;
    hashToId[tokenHash] = record.id;
  }

  @override
  Future<UploadTokenRecord?> findByHash(String tokenHash) async {
    final id = hashToId[tokenHash];
    return id == null ? null : byId[id];
  }

  @override
  Future<void> revoke(String id, DateTime at) async {
    final r = byId[id];
    if (r != null && r.revokedAt == null) byId[id] = _copy(r, revokedAt: at);
  }

  @override
  Future<RefreshAccount?> findAccount(String userId) async => accounts[userId];

  @override
  Future<void> deleteExpiredFor(String userId, DateTime before) async {
    final ids = byId.entries
        .where((e) => e.value.userId == userId && e.value.expiresAt.isBefore(before))
        .map((e) => e.key)
        .toSet();
    byId.removeWhere((k, _) => ids.contains(k));
    hashToId.removeWhere((_, v) => ids.contains(v));
  }

  UploadTokenRecord _copy(UploadTokenRecord r, {DateTime? revokedAt}) =>
      UploadTokenRecord(
        id: r.id,
        userId: r.userId,
        deviceId: r.deviceId,
        issuedAt: r.issuedAt,
        expiresAt: r.expiresAt,
        revokedAt: revokedAt ?? r.revokedAt,
      );
}

class _AuditSpy extends AuditTrail {
  final List<AuditEvent> events = [];
  @override
  Future<void> record(AuditEvent event) async => events.add(event);
  List<String> get results => events.map((e) => e.result).toList();
}

void main() {
  late _MemoryStore store;
  late _AuditSpy audit;
  late UploadTokenService service;
  final t0 = DateTime.utc(2026, 10, 3, 10);

  setUp(() {
    store = _MemoryStore();
    audit = _AuditSpy();
    service = UploadTokenService(store: store, audit: audit);
    store.accounts[_acsId] = const RefreshAccount(active: true, microAreaId: _area);
  });

  /// Toda recusa: a MESMA exceção com a MESMA mensagem.
  Future<void> expectDenied(Future<Object?> Function() call) async {
    try {
      await call();
      fail('deveria recusar');
    } on SessionExpiredException catch (e) {
      expect(e.message, UploadTokenService.deniedMessage);
    }
  }

  test('constantes do contrato', () {
    expect(UploadTokenService.lifetime, const Duration(days: 7));
    expect(UploadTokenService.deniedMessage, 'Envio não autorizado. Entre novamente.');
    // Mensagem própria: não se confunde com a recusa do refresh token.
    expect(UploadTokenService.deniedMessage,
        isNot(RefreshTokenService.deniedMessage));
  });

  test('issue guarda só o hash, amarra ao (usuário, aparelho) e vale 7 dias',
      () async {
    final token = await service.issue(_user, now: t0);
    expect(token.length, greaterThanOrEqualTo(43));
    expect(token, isNot(contains('=')));
    expect(store.hashToId.keys, [_sha(token)]);
    expect(store.hashToId.keys, isNot(contains(token)));
    final r = store.byId.values.single;
    expect(r.userId, _acsId);
    expect(r.deviceId, 'aparelho-A');
    expect(r.issuedAt, t0);
    expect(r.expiresAt, t0.add(const Duration(days: 7)));
    expect(r.revokedAt, isNull);
    expect(r.id, matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(audit.results, ['upload_token_issued']);
    expect(audit.events.single.userId, _acsId);
    // Nada do token na trilha.
    for (final e in audit.events) {
      expect('${e.resourceId}${e.result}${e.resourceType}', isNot(contains(token)));
    }
  });

  test('issue recusa papel que não é ACS e aparelho ausente/sentinela', () async {
    expect(
        () => service.issue(
            const AuthenticatedUser(
                id: _acsId, role: UserRole.patient, microAreaId: _area, deviceId: 'x'),
            now: t0),
        throwsArgumentError);
    for (final device in ['', '   ', InstitutionalAuthService.deviceIdAbsent]) {
      expect(
          () => service.issue(
              AuthenticatedUser(
                  id: _acsId, role: UserRole.acs, microAreaId: _area, deviceId: device),
              now: t0),
          throwsArgumentError,
          reason: 'deviceId="$device"');
    }
    expect(store.byId, isEmpty);
  });

  test('issue revoga o token anterior do MESMO (usuário, aparelho) e só ele',
      () async {
    final primeiro = await service.issue(_user, now: t0);
    final outroAparelho = await service.issue(
        const AuthenticatedUser(
            id: _acsId, role: UserRole.acs, microAreaId: _area, deviceId: 'aparelho-B'),
        now: t0);
    final segundo =
        await service.issue(_user, now: t0.add(const Duration(minutes: 1)));

    await expectDenied(() => service.resolve(
        uploadToken: primeiro, deviceId: 'aparelho-A', now: t0.add(const Duration(minutes: 2))));
    final u = await service.resolve(
        uploadToken: segundo, deviceId: 'aparelho-A', now: t0.add(const Duration(minutes: 2)));
    expect(u.id, _acsId);
    final b = await service.resolve(
        uploadToken: outroAparelho,
        deviceId: 'aparelho-B',
        now: t0.add(const Duration(minutes: 2)));
    expect(b.deviceId, 'aparelho-B');
  });

  test('resolve devolve o dono como ACS, com a microárea RELIDA do banco',
      () async {
    final token = await service.issue(_user, now: t0);
    store.accounts[_acsId] = const RefreshAccount(active: true, microAreaId: _novaArea);
    final u = await service.resolve(
        uploadToken: token, deviceId: 'aparelho-A', now: t0.add(const Duration(days: 6)));
    expect(u.id, _acsId);
    expect(u.role, UserRole.acs);
    expect(u.microAreaId, _novaArea);
    expect(u.deviceId, 'aparelho-A');
  });

  test('resolve vale até 7 dias e recusa em 7 dias + 1 s (vencido)', () async {
    final token = await service.issue(_user, now: t0);
    await service.resolve(
        uploadToken: token,
        deviceId: 'aparelho-A',
        now: t0.add(const Duration(days: 7)).subtract(const Duration(seconds: 1)));
    await expectDenied(() => service.resolve(
        uploadToken: token,
        deviceId: 'aparelho-A',
        now: t0.add(const Duration(days: 7, seconds: 1))));
    expect(audit.results, contains('upload_token_denied_expired'));
  });

  test('fronteira exata: em issuedAt + 7 d recusa; 1 s antes aceita', () async {
    final token = await service.issue(_user, now: t0);
    final limite = t0.add(UploadTokenService.lifetime);
    final u = await service.resolve(
        uploadToken: token,
        deviceId: 'aparelho-A',
        now: limite.subtract(const Duration(seconds: 1)));
    expect(u.id, _acsId);
    await expectDenied(() =>
        service.resolve(uploadToken: token, deviceId: 'aparelho-A', now: limite));
  });

  test('aparelho diferente: recusa, audita e revoga o token', () async {
    final token = await service.issue(_user, now: t0);
    await expectDenied(() => service.resolve(
        uploadToken: token, deviceId: 'aparelho-do-ladrao', now: t0));
    expect(audit.results, contains('upload_token_denied_device'));
    expect(store.byId.values.single.revokedAt, isNotNull);
    // Nem o aparelho certo usa mais.
    await expectDenied(() =>
        service.resolve(uploadToken: token, deviceId: 'aparelho-A', now: t0));
  });

  test('token revogado: recusa com upload_token_denied_revoked', () async {
    final token = await service.issue(_user, now: t0);
    await service.revoke(token, now: t0);
    await expectDenied(() =>
        service.resolve(uploadToken: token, deviceId: 'aparelho-A', now: t0));
    expect(audit.results, containsAll(['upload_token_revoked', 'upload_token_denied_revoked']));
  });

  test('conta inativa: recusa, audita e revoga', () async {
    final token = await service.issue(_user, now: t0);
    store.accounts[_acsId] = const RefreshAccount(active: false, microAreaId: _area);
    await expectDenied(() =>
        service.resolve(uploadToken: token, deviceId: 'aparelho-A', now: t0));
    expect(audit.results, contains('upload_token_denied_inactive'));
    // Reativar não reabre o token revogado.
    store.accounts[_acsId] = const RefreshAccount(active: true, microAreaId: _area);
    await expectDenied(() =>
        service.resolve(uploadToken: token, deviceId: 'aparelho-A', now: t0));
  });

  test('conta sem microárea ou inexistente: recusa', () async {
    final token = await service.issue(_user, now: t0);
    store.accounts[_acsId] = const RefreshAccount(active: true, microAreaId: null);
    await expectDenied(() =>
        service.resolve(uploadToken: token, deviceId: 'aparelho-A', now: t0));
    final token2 = await service.issue(_user, now: t0);
    store.accounts.remove(_acsId);
    await expectDenied(() =>
        service.resolve(uploadToken: token2, deviceId: 'aparelho-A', now: t0));
    expect(audit.results.where((r) => r == 'upload_token_denied_inactive'),
        hasLength(2));
  });

  test('token desconhecido: recusa sem auditoria (não há sujeito)', () async {
    await expectDenied(() => service.resolve(
        uploadToken: 'nao-existe', deviceId: 'aparelho-A', now: t0));
    expect(audit.events, isEmpty);
  });

  test('toda recusa é a MESMA exceção com a MESMA mensagem', () async {
    final messages = <String?>[];
    Future<void> capture(Future<Object?> Function() call) async {
      try {
        await call();
        fail('deveria recusar');
      } on SessionExpiredException catch (e) {
        messages.add(e.message);
      }
    }

    await capture(() =>
        service.resolve(uploadToken: 'desconhecido', deviceId: 'aparelho-A', now: t0));
    final a = await service.issue(_user, now: t0);
    await capture(() =>
        service.resolve(uploadToken: a, deviceId: 'aparelho-B', now: t0)); // aparelho
    final b = await service.issue(_user, now: t0);
    await capture(() => service.resolve(
        uploadToken: b,
        deviceId: 'aparelho-A',
        now: t0.add(const Duration(days: 8)))); // vencido
    final c = await service.issue(_user, now: t0);
    await service.revoke(c, now: t0);
    await capture(() =>
        service.resolve(uploadToken: c, deviceId: 'aparelho-A', now: t0)); // revogado
    final d = await service.issue(_user, now: t0);
    store.accounts[_acsId] = const RefreshAccount(active: false, microAreaId: _area);
    await capture(() =>
        service.resolve(uploadToken: d, deviceId: 'aparelho-A', now: t0)); // inativa
    store.accounts[_acsId] = const RefreshAccount(active: true, microAreaId: null);
    final e = await service.issue(_user, now: t0);
    await capture(() =>
        service.resolve(uploadToken: e, deviceId: 'aparelho-A', now: t0)); // sem área

    expect(messages, hasLength(6));
    expect(messages.toSet(), {UploadTokenService.deniedMessage});
  });

  test('revoke é idempotente e ignora token desconhecido em silêncio', () async {
    final token = await service.issue(_user, now: t0);
    await service.revoke(token, now: t0);
    final revogadoEm = store.byId.values.single.revokedAt;
    await service.revoke(token, now: t0.add(const Duration(hours: 1)));
    expect(store.byId.values.single.revokedAt, revogadoEm);
    await service.revoke('desconhecido', now: t0);
    // Uma linha de revogação só para o desfecho que mudou algo.
    expect(audit.results.where((r) => r == 'upload_token_revoked'), hasLength(1));
  });

  test('issue poda só os tokens VENCIDOS do próprio usuário', () async {
    final velho = await service.issue(_user, now: t0);
    await service.issue(
        const AuthenticatedUser(
            id: _acsId, role: UserRole.acs, microAreaId: _area, deviceId: 'aparelho-B'),
        now: t0.add(const Duration(days: 8)));
    expect(store.hashToId.containsKey(_sha(velho)), isFalse);
    expect(store.byId, hasLength(1));
  });

  test('a auditoria nunca carrega o token', () async {
    final token = await service.issue(_user, now: t0);
    await expectDenied(() =>
        service.resolve(uploadToken: token, deviceId: 'aparelho-X', now: t0));
    await service.revoke(token, now: t0);
    for (final e in audit.events) {
      expect([e.userId, e.actionType, e.resourceType, e.resourceId, e.result].join('|'),
          allOf(isNot(contains(token)), isNot(contains(_sha(token)))));
      expect(e.resourceType, 'upload_token');
    }
  });
}
