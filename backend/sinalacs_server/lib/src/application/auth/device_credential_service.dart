import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart'
    show AuthenticatedUser;
import 'package:sinalacs_server/src/generated/protocol.dart';

/// Uma credencial de dispositivo do participante, do jeito que a store
/// enxerga — sem acoplar `application/` ao ORM.
class StoredPatientDeviceCredential {
  const StoredPatientDeviceCredential({
    required this.id,
    required this.patientId,
    required this.deviceId,
    required this.credentialHash,
    required this.createdAt,
    required this.microAreaId,
    this.lastUsedAt,
    this.revokedAt,
  });

  final String id;
  final String patientId;
  final String deviceId;
  final String credentialHash;
  final DateTime createdAt;

  /// Microárea do titular, relida do banco na consulta (`users.microAreaId`):
  /// nunca um parâmetro do cliente — o JWT sai com o território do cadastro,
  /// não com o que o chamador pedir.
  final String? microAreaId;
  final DateTime? lastUsedAt;
  final DateTime? revokedAt;

  StoredPatientDeviceCredential copyWith({
    DateTime? lastUsedAt,
    DateTime? revokedAt,
  }) =>
      StoredPatientDeviceCredential(
        id: id,
        patientId: patientId,
        deviceId: deviceId,
        credentialHash: credentialHash,
        createdAt: createdAt,
        microAreaId: microAreaId,
        lastUsedAt: lastUsedAt ?? this.lastUsedAt,
        revokedAt: revokedAt ?? this.revokedAt,
      );
}

/// Persistência das credenciais de dispositivo do participante (C-05).
/// Interface aqui, implementação ORM em `infrastructure/`, mesmo padrão de
/// `OnboardingStore`/`RefreshTokenStore`.
abstract interface class DeviceCredentialStore {
  /// A credencial viva ou revogada do `deviceId`, com a microárea do titular
  /// relida do banco; `null` se o aparelho nunca concluiu um convite.
  Future<StoredPatientDeviceCredential?> findByDeviceId(String deviceId);

  /// Grava a credencial nova. Faz parte da MESMA transação que consome o
  /// convite (`OnboardingService.completeEnrollment`): não existe instante
  /// observável com convite consumido e sem credencial (ou o contrário).
  Future<void> create(StoredPatientDeviceCredential credential);

  /// Atualiza `lastUsedAt` do login bem-sucedido (LGPD-RT06: retenção do
  /// acesso do titular).
  Future<void> touchLastUsed(String deviceId, DateTime at);
}

/// Login do participante por credencial de dispositivo (RF24, C-05).
///
/// O app apresenta `deviceId` + segredo de 32 bytes sorteados na conclusão do
/// convite; o servidor compara o hash em tempo constante e emite o JWT de 1 h
/// com o `device_id` da credencial. O PIN local NUNCA sai do aparelho: o que
/// chega aqui é o segredo que ele protegia, e o servidor não tem como (nem
/// precisa) saber se o PIN foi pedido.
class DeviceCredentialService {
  DeviceCredentialService({
    required DeviceCredentialStore store,
    required AuditTrail audit,
  })  : _store = store,
        _audit = audit;

  final DeviceCredentialStore _store;
  final AuditTrail _audit;

  static const _domain = 'sinalacs-pdc-v1';

  /// SHA-256 com domínio próprio do segredo. Hash rápido de propósito: o
  /// segredo tem 256 bits de `Random.secure()` — não há espaço de busca a
  /// enumerar, ao contrário do CPF (que exige HMAC com pepper). O domínio
  /// separa este hash do de qualquer outro artefato do sistema.
  static String hashSecret(String secret) =>
      sha256.convert(utf8.encode('$_domain:$secret')).toString();

  /// Toda recusa de credencial é a MESMA exceção, com a MESMA mensagem:
  /// segredo errado, aparelho desconhecido, credencial revogada e formato
  /// inválido são indistinguíveis para quem sonda (mesma disciplina do
  /// `PasswordlessAuthService`). Falta de território é a única exceção
  /// separada: a credencial é válida (ver `DeviceCredentialTerritoryException`).
  Future<AuthenticatedUser> login({
    required String deviceId,
    required String secret,
  }) async {
    final record = await _store.findByDeviceId(deviceId);

    final negado = record == null ||
        record.revokedAt != null ||
        !_matches(secret, record.credentialHash);
    if (negado) {
      // Sem identidade: um deviceId desconhecido não tem `userId` para
      // associar à trilha. A recusa de credencial conhecida leva o id do
      // titular, como `denied_code` faz no OTP.
      if (record != null) {
        await _audit.recordSafely(AuditEvent(
          userId: record.patientId,
          actionType: 'login',
          resourceType: 'patient_device_credential',
          result: 'denied_credential',
        ));
      }
      throw DeviceCredentialException(
        message: 'Credencial inválida ou revogada.',
      );
    }

    final microAreaId = record.microAreaId;
    if (microAreaId == null) {
      await _audit.recordSafely(AuditEvent(
        userId: record.patientId,
        actionType: 'login',
        resourceType: 'patient_device_credential',
        result: 'denied_no_territory',
      ));
      // Exceção própria, e não a de credencial: o aparelho e o segredo estão
      // certos, então o app NÃO pode apagar a credencial local por causa
      // desta recusa (é estado administrativo do cadastro, possivelmente
      // transitório — ver Inline 12 da revisão da C-05).
      throw DeviceCredentialTerritoryException(
        message: 'Este acesso não está vinculado a uma microárea.',
      );
    }

    await _store.touchLastUsed(deviceId, DateTime.now().toUtc());
    await _audit.recordSafely(AuditEvent(
      userId: record.patientId,
      actionType: 'login',
      resourceType: 'patient_device_credential',
      result: 'granted',
    ));

    return AuthenticatedUser(
      id: record.patientId,
      role: UserRole.patient,
      microAreaId: microAreaId,
      deviceId: deviceId,
    );
  }

  /// Comparação em tempo constante, como a verificação de assinatura do
  /// `DevelopmentAuthService` — o tempo do hash não pode distinguir "errou o
  /// segredo" de "acertou".
  bool _matches(String secret, String expectedHash) {
    final actual = hashSecret(secret);
    if (actual.length != expectedHash.length) return false;
    var difference = 0;
    for (var index = 0; index < actual.length; index++) {
      difference |= actual.codeUnitAt(index) ^ expectedHash.codeUnitAt(index);
    }
    return difference == 0;
  }
}
