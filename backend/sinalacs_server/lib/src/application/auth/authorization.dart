import 'package:sinalacs_server/src/application/auth/development_auth_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

/// A única decisão de "este papel, neste território, pode?" do backend
/// (RNF06, achado F4 de spec/security_assessment.md).
///
/// Antes desta classe a mesma pergunta era respondida oito vezes, à mão, uma
/// por sítio — sete com `StateError` e uma com `TriageAuthorizationException`.
/// Nada obrigava um serviço novo a ter a sua: um caso de uso nascia público por
/// omissão e só uma revisão humana pegava.
///
/// Esta guarda **não escolhe o tipo da exceção**. Ela recebe `onDenied` e lança
/// o que o chamador construir, porque o tipo faz parte do contrato de cada
/// serviço: os endpoints traduzem `StateError` para `AlertPermissionException`
/// (ver `VisitsEndpoint.sync`) e `TriageAuthorizationException` é tipada e
/// serializada ao cliente. Uma guarda que lançasse um tipo próprio quebraria as
/// duas traduções de uma vez.
abstract final class Authorization {
  /// Exige que [user] tenha um dos [roles] e, quando [requireMicroArea], que o
  /// token carregue um território.
  ///
  /// `requireMicroArea` é `true` por omissão porque a territorialização é
  /// invariante (INV-01): quem lê ou escreve dado de paciente o faz *dentro* de
  /// uma microárea, e um token sem território não tem barreira nenhuma para
  /// aplicar.
  ///
  /// O caso `false` existe para os sítios que hoje só checam papel, **e são
  /// exatamente dois**: `alerts.statusFor` (RF05, leitura escopada ao próprio
  /// titular pelo `user.id` do token) e
  /// `TriageSessionService.evaluateAndRecord`
  /// (`triage_session_service.dart:96`, que também só testa o papel — o
  /// `evaluate` sem o `AndRecord` é do `TriageEngine` e não checa papel
  /// nenhum). Passar `true` em qualquer um deles acrescenta uma recusa
  /// territorial que não existe hoje — mudança de comportamento observável,
  /// proibida pelas Global Constraints deste plano. Os outros seis sítios já
  /// checam `|| microAreaId == null` e usam o default.
  static void require(
    AuthenticatedUser user, {
    required Set<UserRole> roles,
    required Object Function() onDenied,
    bool requireMicroArea = true,
  }) {
    if (!roles.contains(user.role)) throw onDenied();
    if (requireMicroArea && user.microAreaId == null) throw onDenied();
  }
}
