import 'dart:convert';

/// Sessão autenticada contra o backend.
///
/// Vem do login do produto — `auth.verifyOtp`, o RF01 — ou, nas ferramentas de
/// desenvolvimento (`tool/`, `integration_test/`), de `auth.developmentLogin`,
/// que só existe com `ENABLE_DEV_LOGIN=true`. Os dois emitem o mesmo token; o
/// que muda é o TTL (ver [isExpired]).
class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.tokenType,
    required this.userId,
    required this.role,
    required this.microAreaId,
    required this.expiresAt,
  });

  final String accessToken;
  final String tokenType;
  final String userId;
  final String role;

  /// Microárea do usuário. Restringe o acesso ao território (INV do PRD) e, no
  /// app do ACS, define o tópico MQTT assinado.
  final String? microAreaId;

  final DateTime expiresAt;

  /// Lê o payload do token emitido por `DevelopmentAuthService`.
  ///
  /// O token é um JWT HS256 cujo payload carrega `sub`, `role`,
  /// `micro_area_id` e `exp`. A assinatura **não** é verificada aqui: verificar
  /// é papel do servidor, e o app não tem — nem deve ter — o segredo HMAC. A
  /// leitura serve apenas para o app conhecer a própria microárea e a
  /// expiração, o que evita um endpoint extra só para isso.
  ///
  /// Devolve `null` para qualquer token malformado; quem chama decide o que
  /// mostrar. Nunca registre o token em log.
  static AuthSession? tryParse(String accessToken, String tokenType) {
    final sections = accessToken.split('.');
    if (sections.length != 3) return null;

    try {
      final decoded = utf8.decode(
        base64Url.decode(base64Url.normalize(sections[1])),
      );
      final payload = jsonDecode(decoded) as Map<String, dynamic>;

      final exp = payload['exp'];
      final sub = payload['sub'];
      final role = payload['role'];
      if (exp is! int || sub is! String || role is! String) return null;

      return AuthSession(
        accessToken: accessToken,
        tokenType: tokenType,
        userId: sub,
        role: role,
        microAreaId: payload['micro_area_id'] as String?,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
          exp * 1000,
          isUtc: true,
        ),
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  /// O token do paciente vive 1 hora (LGPD-RT06), decidido no servidor.
  ///
  /// São 60 minutos, e não os 15 do ACS, porque não existe renovação silenciosa
  /// deste lado: o código OTP é de uso único e não há credencial reutilizável
  /// para reautenticar sem a pessoa. Ao expirar, o app **não** se renova — pede
  /// que ela entre de novo com um código novo.
  ///
  /// A hora vale para o token de `auth.verifyOtp`, o caminho de login. **Não**
  /// é uma regra do papel `patient`: `onboarding.completeEnrollment` ainda emite
  /// o padrão de 15 minutos para o mesmo papel, lacuna do RF02 com dono
  /// registrado no `PROGRESS.md`. Leia esta descrição como a do login, não como
  /// a da sessão de todo paciente — o app lê a expiração do `exp` do token e
  /// funciona com as duas.
  ///
  /// A margem existe para não enviar um token que expira no meio da viagem:
  /// sem ela, a chamada falharia no servidor com uma resposta que não diz que o
  /// problema foi o relógio.
  bool isExpired({
    DateTime? now,
    Duration margin = const Duration(seconds: 30),
  }) {
    final reference = (now ?? DateTime.now().toUtc()).add(margin);
    return !expiresAt.isAfter(reference);
  }
}
