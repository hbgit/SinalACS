import 'dart:math';

import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/institutional_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/opaque_token.dart';
import 'package:sinalacs_server/src/application/auth/refresh_token_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

class UploadTokenRecord {
  const UploadTokenRecord({
    required this.id,
    required this.userId,
    required this.deviceId,
    required this.issuedAt,
    required this.expiresAt,
    this.revokedAt,
  });

  final String id;
  final String userId;
  final String deviceId;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final DateTime? revokedAt;
}

abstract interface class UploadTokenStore {
  /// Revoga (com `revokedAt = record.issuedAt`) o token vigente do mesmo
  /// (`userId`, `deviceId`) e grava [record] — sem janela em que dois
  /// vigentes do mesmo par sobrevivam a emissões concorrentes.
  Future<void> replace(UploadTokenRecord record, String tokenHash);
  Future<UploadTokenRecord?> findByHash(String tokenHash);

  /// Marca `revokedAt` se a linha ainda está vigente; nada se já revogada.
  Future<void> revoke(String id, DateTime at);

  /// Todos os tokens do usuário, para a desativação da conta (#43): o envio
  /// diferido não depende de sessão, então derrubar só o refresh deixaria o
  /// aparelho de um ACS desativado subindo visita em nome dele até o token
  /// vencer (7 dias).
  ///
  /// Como no refresh, um token emitido na janela de uma desativação
  /// concorrente já nasce inutilizável: [UploadTokenService.resolve] relê a
  /// conta a cada uso e, inativa, revoga e recusa.
  Future<void> revokeAllForUser(String userId, DateTime at);

  /// Mesma leitura do refresh token: só conta de ACS, com `acs.active` e a
  /// microárea atual de `users`.
  Future<RefreshAccount?> findAccount(String userId);

  /// Poda do próprio usuário: tokens cujo prazo já passou.
  Future<void> deleteExpiredFor(String userId, DateTime before);
}

/// Token de envio diferido do ACS (D7 do plano 2026-10-03).
///
/// Deixa o aparelho subir as visitas pendentes de um ACS que já saiu, **com a
/// autoria dele**, sem sessão: o único uso é `visits.syncDeferred` (e a
/// revogação). Não lê nada, não renova sessão, não serve a nenhuma outra
/// chamada — por isso é independente da família do refresh token, e o "Sair"
/// não o derruba (o app o revoga quando a fila do dono zera).
///
/// Mesmo desenho do [RefreshTokenService]: token opaco de 256 bits, só o
/// SHA-256 no banco, amarrado ao `deviceId` da instalação, e toda recusa é a
/// mesma [SessionExpiredException] com [deniedMessage] — sem dizer o motivo.
/// A microárea do usuário devolvido é **relida do banco** a cada uso (INV-01):
/// o envio diferido entra no território atual do dono, nunca no da emissão.
class UploadTokenService {
  UploadTokenService({required this.store, required this.audit, Random? random})
      : _random = random ?? Random.secure();

  final UploadTokenStore store;
  final AuditTrail audit;
  final Random _random;

  static const lifetime = Duration(days: 7);
  static const deniedMessage = 'Envio não autorizado. Entre novamente.';

  /// Emite um token novo para (`user.id`, `user.deviceId`) e revoga o anterior
  /// do mesmo par. Exige um aparelho real: o sentinela de
  /// `InstitutionalAuthService.deviceIdAbsent` é público e anularia a amarração.
  Future<String> issue(AuthenticatedUser user, {DateTime? now}) async {
    final at = (now ?? DateTime.now()).toUtc();
    if (user.role != UserRole.acs) {
      throw ArgumentError.value(user.role, 'user.role', 'só o ACS tem envio diferido');
    }
    final device = user.deviceId;
    if (device.trim().isEmpty || device == InstitutionalAuthService.deviceIdAbsent) {
      throw ArgumentError.value('<omitido>', 'user.deviceId', 'aparelho obrigatório');
    }
    await store.deleteExpiredFor(user.id, at);
    final token = OpaqueToken.generate(_random);
    await store.replace(
      UploadTokenRecord(
        id: OpaqueToken.uuid(_random),
        userId: user.id,
        deviceId: device,
        issuedAt: at,
        expiresAt: at.add(lifetime),
      ),
      OpaqueToken.hash(token),
    );
    await _audit(user.id, 'upload_token_issued');
    return token;
  }

  /// O dono do token, como ACS da microárea ATUAL. Qualquer recusa —
  /// desconhecido, vencido, revogado, outro aparelho, conta inativa ou sem
  /// microárea — lança a mesma [SessionExpiredException].
  Future<AuthenticatedUser> resolve({
    required String uploadToken,
    required String deviceId,
    DateTime? now,
  }) async {
    final at = (now ?? DateTime.now()).toUtc();
    final record = await store.findByHash(OpaqueToken.hash(uploadToken));
    if (record == null) throw _denied(); // sem sujeito para auditar

    if (record.revokedAt != null) {
      await _audit(record.userId, 'upload_token_denied_revoked');
      throw _denied();
    }
    if (record.deviceId != deviceId) {
      // Token fora do aparelho que o recebeu: sinal de vazamento. Revoga.
      await store.revoke(record.id, at);
      await _audit(record.userId, 'upload_token_denied_device');
      throw _denied();
    }
    if (!at.isBefore(record.expiresAt)) {
      await _audit(record.userId, 'upload_token_denied_expired');
      throw _denied();
    }

    final account = await store.findAccount(record.userId);
    final microAreaId = account?.microAreaId;
    if (account == null || !account.active || microAreaId == null) {
      await store.revoke(record.id, at);
      await _audit(record.userId, 'upload_token_denied_inactive');
      throw _denied();
    }

    return AuthenticatedUser(
      id: record.userId,
      role: UserRole.acs,
      microAreaId: microAreaId, // relida agora (INV-01)
      deviceId: record.deviceId,
    );
  }

  /// Revoga o token. Idempotente: já revogado ou desconhecido não lança nem
  /// audita de novo.
  Future<void> revoke(String uploadToken, {DateTime? now}) async {
    final at = (now ?? DateTime.now()).toUtc();
    final record = await store.findByHash(OpaqueToken.hash(uploadToken));
    if (record == null || record.revokedAt != null) return;
    await store.revoke(record.id, at);
    await _audit(record.userId, 'upload_token_revoked');
  }

  SessionExpiredException _denied() =>
      SessionExpiredException(message: deniedMessage);

  Future<void> _audit(String userId, String result) => audit.recordSafely(
        AuditEvent(
          userId: userId,
          actionType: 'login',
          resourceType: 'upload_token',
          result: result,
        ),
      );
}
