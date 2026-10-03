import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

class RefreshAccount {
  const RefreshAccount({required this.active, required this.microAreaId});
  final bool active;
  final String? microAreaId;
}

class RefreshTokenRecord {
  const RefreshTokenRecord({
    required this.id,
    required this.userId,
    required this.familyId,
    required this.deviceId,
    required this.issuedAt,
    required this.idleExpiresAt,
    required this.absoluteExpiresAt,
    this.rotatedAt,
    this.revokedAt,
  });

  final String id;
  final String userId;
  final String familyId;
  final String deviceId;
  final DateTime issuedAt;
  final DateTime idleExpiresAt;
  final DateTime absoluteExpiresAt;
  final DateTime? rotatedAt;
  final DateTime? revokedAt;
}

abstract interface class RefreshTokenStore {
  Future<void> insert(RefreshTokenRecord record, String tokenHash);
  Future<RefreshTokenRecord?> findByHash(String tokenHash);

  /// Marca `rotatedAt` **só se** a linha ainda não foi rotacionada nem
  /// revogada (um `UPDATE` condicional). `false` = outra requisição ganhou.
  Future<bool> markRotated(String id, DateTime at);

  Future<void> revokeFamily(String familyId, DateTime at);
  Future<RefreshAccount?> findAccount(String userId);

  /// Poda do próprio usuário: tokens cujo teto absoluto já passou.
  Future<void> deleteExpiredFor(String userId, DateTime before);
}

class RefreshedSession {
  const RefreshedSession({required this.user, required this.refreshToken});
  final AuthenticatedUser user;
  final String refreshToken;
}

class RefreshTokenService {
  RefreshTokenService({required this.store, required this.audit, Random? random})
      : _random = random ?? Random.secure();

  final RefreshTokenStore store;
  final AuditTrail audit;
  final Random _random;

  static const idleWindow = Duration(hours: 2);
  static const absoluteWindow = Duration(hours: 8);
  static const reuseGrace = Duration(seconds: 30);
  static const deniedMessage = 'Sessão expirada. Entre novamente.';

  /// Primeiro token de uma família nova (login por senha+TOTP).
  Future<String> issue(AuthenticatedUser user, {DateTime? now}) async {
    final at = (now ?? DateTime.now()).toUtc();
    await store.deleteExpiredFor(user.id, at);
    return _insert(
      userId: user.id,
      familyId: _uuid(),
      deviceId: user.deviceId,
      at: at,
      absoluteExpiresAt: at.add(absoluteWindow),
    );
  }

  Future<RefreshedSession> refresh({
    required String refreshToken,
    required String deviceId,
    DateTime? now,
  }) async {
    final at = (now ?? DateTime.now()).toUtc();
    final record = await store.findByHash(_hash(refreshToken));
    if (record == null) throw _denied(); // sem sujeito para auditar

    if (record.revokedAt != null) {
      await _audit(record.userId, 'denied_revoked');
      throw _denied();
    }
    if (record.deviceId != deviceId) {
      await store.revokeFamily(record.familyId, at);
      await _audit(record.userId, 'denied_device');
      throw _denied();
    }
    if (!at.isBefore(record.absoluteExpiresAt) ||
        !at.isBefore(record.idleExpiresAt)) {
      await _audit(record.userId, 'denied_expired');
      throw _denied();
    }

    final rotatedAt = record.rotatedAt;
    if (rotatedAt != null && at.difference(rotatedAt) > reuseGrace) {
      await store.revokeFamily(record.familyId, at);
      await _audit(record.userId, 'denied_reuse');
      throw _denied();
    }

    final account = await store.findAccount(record.userId);
    final microAreaId = account?.microAreaId;
    if (account == null || !account.active || microAreaId == null) {
      await store.revokeFamily(record.familyId, at);
      await _audit(record.userId, 'denied_inactive');
      throw _denied();
    }

    // Quem perde a corrida do UPDATE é uma chamada concorrente com o mesmo
    // token, no mesmo instante: cai na mesma tolerância do reuso, não é roubo.
    if (rotatedAt == null) await store.markRotated(record.id, at);

    final child = await _insert(
      userId: record.userId,
      familyId: record.familyId,
      deviceId: deviceId,
      at: at,
      absoluteExpiresAt: record.absoluteExpiresAt,
    );
    await _audit(record.userId, 'refresh_granted');
    return RefreshedSession(
      user: AuthenticatedUser(
        id: record.userId,
        role: UserRole.acs,
        microAreaId: microAreaId, // relida agora (INV-01)
        deviceId: deviceId,
      ),
      refreshToken: child,
    );
  }

  Future<void> revoke(String refreshToken, {DateTime? now}) async {
    final at = (now ?? DateTime.now()).toUtc();
    final record = await store.findByHash(_hash(refreshToken));
    if (record == null) return;
    await store.revokeFamily(record.familyId, at);
    await _audit(record.userId, 'logout');
  }

  Future<String> _insert({
    required String userId,
    required String familyId,
    required String deviceId,
    required DateTime at,
    required DateTime absoluteExpiresAt,
  }) async {
    final token = base64Url
        .encode(List<int>.generate(32, (_) => _random.nextInt(256)))
        .replaceAll('=', '');
    final idle = at.add(idleWindow);
    await store.insert(
      RefreshTokenRecord(
        id: _uuid(),
        userId: userId,
        familyId: familyId,
        deviceId: deviceId,
        issuedAt: at,
        idleExpiresAt: idle.isAfter(absoluteExpiresAt) ? absoluteExpiresAt : idle,
        absoluteExpiresAt: absoluteExpiresAt,
      ),
      _hash(token),
    );
    return token;
  }

  String _hash(String token) => sha256.convert(utf8.encode(token)).toString();

  String _uuid() {
    final b = List<int>.generate(16, (_) => _random.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }

  SessionExpiredException _denied() =>
      SessionExpiredException(message: deniedMessage);

  Future<void> _audit(String userId, String result) => audit.recordSafely(
        AuditEvent(
          userId: userId,
          actionType: 'login',
          resourceType: 'session_refresh',
          result: result,
        ),
      );
}
