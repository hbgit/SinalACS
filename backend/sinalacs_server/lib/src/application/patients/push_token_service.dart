import 'package:sinalacs_server/src/application/auth/authorization.dart';
import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// Persistência dos tokens de push (RF14, decisão §3.2). Interface aqui,
/// implementação ORM em `infrastructure/`.
abstract interface class PushTokenStore {
  /// Registra o token **só se** a linha mais recente de `segmentedPush` do
  /// titular for `granted`, tudo numa transação sob lock por titular: a leitura
  /// do consentimento e a gravação não têm janela entre si, e a revogação
  /// (`deleteAllFor`) espera o mesmo lock. Se o token já existe, muda o dono e
  /// renova `updatedAt`. Devolve `false` sem consentimento — e nesse caso apaga
  /// o vínculo de outro titular com o mesmo token, porque quem apresenta o
  /// token está com o aparelho em mãos.
  Future<bool> registerIfConsented({
    required String userId,
    required String? microAreaId,
    required String token,
    required String platform,
    required DateTime now,
  });

  /// Apaga todos os tokens do titular (sob o mesmo lock por titular do
  /// registro) e devolve quantos eram.
  Future<int> deleteAllFor(String userId);
}

/// Teto do token: o do FCM tem cerca de 160 caracteres, o do APNs 64.
const int pushTokenMaxLength = 4096;
const Set<String> pushPlatforms = {'android', 'ios'};

/// Registro do aparelho do paciente para avisos segmentados (RF14).
///
/// `userId` vem SEMPRE de `user.id` (INV-05). Só grava com o consentimento
/// `segmentedPush` vigente: o token liga aparelho a titular, então sem base
/// legal ele nem é guardado.
class PushTokenService {
  PushTokenService({required PushTokenStore store, DateTime Function()? clock})
      : _store = store,
        _clock = clock ?? DateTime.now;

  final PushTokenStore _store;
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
    final registered = await _store.registerIfConsented(
      userId: user.id,
      microAreaId: user.microAreaId,
      token: trimmed,
      platform: platform,
      now: _clock().toUtc(),
    );
    if (!registered) {
      throw DataRightsException(
        message: 'Ative "Avisos da equipe de saúde" em Meus Dados para receber avisos.',
      );
    }
  }
}
