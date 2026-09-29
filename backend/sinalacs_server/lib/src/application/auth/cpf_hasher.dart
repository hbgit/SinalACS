import 'package:sinalacs_server/src/application/auth/cpf.dart';

/// Hash do CPF e do código OTP, para que a busca de login nunca compare o
/// identificador em claro (LGPD, `spec/lgpd_data_audit.md:196`).
///
/// Interface em `application/`, implementação em `infrastructure/` — mesmo
/// arranjo de `PasswordHasher`/`AlertStore`.
abstract interface class CpfHasher {
  /// Índice de busca em `users.cpfHash`. Determinístico por necessidade: é
  /// coluna indexada, e um hash com salt por linha não permitiria procurar.
  /// O pepper é o que substitui o salt aqui — sem ele, o espaço de 10^9 CPFs
  /// é reversível por força bruta em segundos.
  String hash(Cpf cpf);

  /// Hash do código OTP de 6 dígitos, com campo de domínio próprio.
  String hashOtpCode(String code);
}
