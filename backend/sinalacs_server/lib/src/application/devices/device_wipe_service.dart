import 'package:sinalacs_server/src/application/admin/admin_account_service.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/institutional_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// Pedidos de limpeza remota e aparelhos do ACS sobre o banco (issue #81).
/// Interface à parte do ORM, no espírito de `AdminAccountStore`.
abstract interface class DeviceWipeStore {
  /// Aparelhos do ACS [acsId] (os que têm refresh token ou token de envio),
  /// do visto por último ao mais antigo, com o estado do pedido de limpeza.
  ///
  /// Devolve também a sentinela `deviceIdAbsent`, se houver: quem a esconde é
  /// o serviço, que é quem conhece a regra.
  Future<List<AdminAcsDevice>> devicesOf(String acsId);

  /// `true` se existe linha em `acs_refresh_tokens` ou `acs_upload_tokens` com
  /// `userId = acsId` e esse [deviceId].
  Future<bool> deviceBelongsTo(String acsId, String deviceId);

  /// Grava o pedido de limpeza e revoga os tokens do aparelho numa **única
  /// transação**: insere (ou lê, se o índice único de `deviceId` já tem linha)
  /// o pedido e, só quando [created], carimba `revokedAt = at` em toda linha
  /// viva de `acs_refresh_tokens` e `acs_upload_tokens` com esse `deviceId` —
  /// de todos os donos. Repetir não cria linha nem revoga de novo.
  Future<({DeviceWipeOrder order, bool created})> orderWipe({
    required String deviceId,
    required String targetUserId,
    required String requestedBy,
    required DeviceWipeReason reason,
    required DateTime at,
  });

  /// O pedido de limpeza do aparelho, ou `null`.
  Future<DeviceWipeOrder?> orderFor(String deviceId);

  /// Carimba `deliveredAt`. `true` só na primeira vez.
  Future<bool> markDelivered(String orderId, DateTime at);

  /// Carimba `confirmedAt`. `true` só na primeira vez e só se o par
  /// ([deviceId], [orderId]) for o do pedido.
  Future<bool> markConfirmed(String deviceId, String orderId, DateTime at);
}

/// Limpeza remota do aparelho de um ACS pelo backoffice (issue #81).
///
/// Papel e escopo vêm do [AdminScopeResolver]: só `coordinator`/`admin`; o
/// coordenador opera **apenas** ACS da própria UBS. ACS fora do escopo, ACS
/// inexistente, aparelho que não é do ACS e a sentinela
/// `InstitutionalAuthService.deviceIdAbsent` recebem a **mesma** recusa
/// (`Aparelho não encontrado.`), com a linha `denied` na trilha antes de lançar.
///
/// Auditoria fail-closed, sempre com `record`: a listagem audita `read`/
/// `admin_acs_devices` antes de consultar; o pedido audita `write`/
/// `admin_device` depois do commit (`wipe_ordered` ou `already_ordered`), com o
/// id do pedido em `resourceId`.
class DeviceWipeService {
  DeviceWipeService({
    required this.store,
    required this.accounts,
    required this.audit,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final DeviceWipeStore store;

  /// Escopo e existência do ACS (`acsById`).
  final AdminAccountStore accounts;

  final AuditTrail audit;
  final DateTime Function() _clock;

  late final AdminScopeResolver _resolver = AdminScopeResolver(
    store: accounts,
    audit: audit,
  );

  static const _naoEncontrado = 'Aparelho não encontrado.';

  /// Aparelhos do ACS, sem a sentinela.
  Future<List<AdminAcsDevice>> devicesOf(
    AuthenticatedUser user, {
    required String acsId,
  }) async {
    const recurso = 'admin_acs_devices';
    final escopo = await _resolver.resolve(user, recurso: recurso);
    if (await accounts.acsById(escopo, acsId) == null) {
      await _negar(user, recurso, actionType: 'read');
    }
    await audit.record(
      AuditEvent(
        userId: user.id,
        actionType: 'read',
        resourceType: recurso,
        resourceId: acsId,
        result: 'success',
      ),
    );
    final todos = await store.devicesOf(acsId);
    return [
      for (final d in todos)
        if (d.deviceId != InstitutionalAuthService.deviceIdAbsent) d,
    ];
  }

  /// Pede a limpeza do aparelho [deviceId] do ACS [acsId] e revoga os tokens
  /// dele. Repetir é idempotente: `alreadyOrdered` e o `requestedAt` original.
  Future<AdminDeviceWipeResult> orderWipe(
    AuthenticatedUser user, {
    required String acsId,
    required String deviceId,
    required DeviceWipeReason reason,
  }) async {
    const recurso = 'admin_device';
    final escopo = await _resolver.resolve(
      user,
      recurso: 'admin_acs',
      actionType: 'write',
    );
    if (await accounts.acsById(escopo, acsId) == null ||
        deviceId.trim().isEmpty ||
        deviceId == InstitutionalAuthService.deviceIdAbsent ||
        !await store.deviceBelongsTo(acsId, deviceId)) {
      await _negar(user, recurso, actionType: 'write');
    }

    final r = await store.orderWipe(
      deviceId: deviceId,
      targetUserId: acsId,
      requestedBy: user.id,
      reason: reason,
      at: _clock().toUtc(),
    );
    final orderId = r.order.id.toString();
    await audit.record(
      AuditEvent(
        userId: user.id,
        actionType: 'write',
        resourceType: recurso,
        resourceId: orderId,
        result: r.created ? 'wipe_ordered' : 'already_ordered',
      ),
    );
    return AdminDeviceWipeResult(
      orderId: orderId,
      requestedAt: r.order.requestedAt,
      alreadyOrdered: !r.created,
    );
  }

  /// Recusa com linha `denied` ANTES de lançar; a mesma mensagem para "não
  /// existe" e "não é seu".
  Future<Never> _negar(
    AuthenticatedUser user,
    String recurso, {
    required String actionType,
  }) async {
    await audit.record(
      AuditEvent(
        userId: user.id,
        actionType: actionType,
        resourceType: recurso,
        result: 'denied',
      ),
    );
    throw AdminInvalidRequestException(message: _naoEncontrado);
  }
}
