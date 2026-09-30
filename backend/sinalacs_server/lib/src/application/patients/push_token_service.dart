import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/authorization.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// Persistência dos tokens de push (RF14, decisão §3.2). Interface aqui,
/// implementação ORM em `infrastructure/`.
abstract interface class PushTokenStore {
  /// Registra o token **só se** a linha mais recente de `segmentedPush` do
  /// titular for `granted`, tudo numa transação sob lock por titular: a leitura
  /// do consentimento e a gravação não têm janela entre si, e a revogação
  /// (`recordConsentRevokingPush`) espera o mesmo lock.
  ///
  /// - [PushRegistration.registered]: token novo, ou já era do titular.
  /// - [PushRegistration.ownerChanged]: o token existia para outro titular e mudou
  ///   de dono.
  /// - [PushRegistration.refused]: sem consentimento vigente — e nesse caso apaga
  ///   o vínculo de outro titular com o mesmo token, porque quem apresenta o token
  ///   está com o aparelho em mãos.
  ///
  /// Depois de gravar, o titular nunca fica com mais de [maxPushTokensPerUser]
  /// tokens: os mais antigos (por `updatedAt`) saem.
  Future<PushRegistrationResult> registerIfConsented({
    required String userId,
    required String? microAreaId,
    required String token,
    required String platform,
    required DateTime now,
  });
}

/// Desfecho de [PushTokenStore.registerIfConsented].
enum PushRegistration { registered, ownerChanged, refused }

/// O desfecho mais, quando o token mudou de dono, quem era o dono anterior — para
/// o titular que perdeu o vínculo sem agir também ter rastro (LGPD-RF08).
class PushRegistrationResult {
  const PushRegistrationResult(this.outcome, {this.previousOwnerId});

  final PushRegistration outcome;
  final String? previousOwnerId;
}

/// Teto de aparelhos por titular. Passou do teto, o token mais antigo sai: quem
/// troca de celular nunca é recusado por causa de aparelhos velhos.
const int maxPushTokensPerUser = 10;

/// Teto do token: o do FCM tem cerca de 160 caracteres, o do APNs 64.
const int pushTokenMaxLength = 4096;
const Set<String> pushPlatforms = {'android', 'ios'};

/// Registro do aparelho do paciente para avisos segmentados (RF14).
///
/// `userId` vem SEMPRE de `user.id` (INV-05). Só grava com o consentimento
/// `segmentedPush` vigente: o token liga aparelho a titular, então sem base
/// legal ele nem é guardado.
class PushTokenService {
  PushTokenService({
    required PushTokenStore store,
    required AuditTrail audit,
    DateTime Function()? clock,
  })  : _store = store,
        _audit = audit,
        _clock = clock ?? DateTime.now;

  final PushTokenStore _store;
  final AuditTrail _audit;
  final DateTime Function() _clock;

  Future<void> register(
    AuthenticatedUser user, {
    required String token,
    required String platform,
  }) async {
    Authorization.require(
      user,
      roles: {UserRole.patient},
      onDenied: () => StateError('Somente o próprio paciente registra o aparelho para avisos.'),
      requireMicroArea: false,
    );
    final trimmed = token.trim();
    if (trimmed.isEmpty ||
        trimmed.length > pushTokenMaxLength ||
        !pushPlatforms.contains(platform)) {
      throw DataRightsException(message: 'Aparelho inválido para receber avisos.');
    }
    final result = await _store.registerIfConsented(
      userId: user.id,
      microAreaId: user.microAreaId,
      token: trimmed,
      platform: platform,
      now: _clock().toUtc(),
    );
    if (result.outcome == PushRegistration.refused) {
      throw DataRightsException(
        message: 'Ative "Avisos da equipe de saúde" em Meus Dados para receber avisos.',
      );
    }
    // Só a troca de dono deixa rastro: é o único evento que move um vínculo
    // aparelho↔titular sem ação do titular anterior. Registrar e repetir não
    // auditam, para não gravar uma linha por login; o token nunca entra na trilha.
    if (result.outcome == PushRegistration.ownerChanged) {
      await _audit.recordSafely(AuditEvent(
        userId: user.id,
        actionType: 'write',
        resourceType: 'push_token',
        result: 'granted',
      ));
      final previous = result.previousOwnerId;
      if (previous != null) {
        await _audit.recordSafely(AuditEvent(
          userId: previous,
          actionType: 'write',
          resourceType: 'push_token',
          result: 'lost',
        ));
      }
    }
  }
}
