import 'dart:convert';

/// Sessão autenticada contra o backend.
///
/// **Não é autenticação institucional.** O token vem de
/// `auth.developmentLogin`, que só existe com `ENABLE_DEV_LOGIN=true` e serve
/// para validar a conexão, não para proteger dado real.
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

  /// O token de desenvolvimento vive 15 minutos.
  ///
  /// A margem existe para não enviar um token que expira no meio da viagem:
  /// sem ela, um fluxo longo falha com erro de permissão em vez de
  /// reautenticar, que é um sintoma bem mais confuso de diagnosticar.
  bool isExpired({
    DateTime? now,
    Duration margin = const Duration(seconds: 30),
  }) {
    final reference = (now ?? DateTime.now().toUtc()).add(margin);
    return !expiresAt.isAfter(reference);
  }
}
