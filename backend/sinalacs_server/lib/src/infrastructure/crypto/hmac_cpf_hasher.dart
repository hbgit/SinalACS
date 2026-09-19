import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sinalacs_server/src/application/auth/cpf.dart';
import 'package:sinalacs_server/src/application/auth/cpf_hasher.dart';

/// HMAC-SHA-256 com pepper de servidor.
///
/// `package:crypto` em vez de `package:cryptography` porque aqui a operação é
/// síncrona e sem salt — é a mesma primitiva que `DevelopmentAuthService` já
/// usa para assinar o token.
///
/// Os prefixos `sinalacs:cpf:v1:` e `sinalacs:otp:v1:` são separação de
/// domínio: sem eles, um hash de código OTP (`'12345678909'` é um código de 11
/// dígitos válido como string) seria idêntico ao hash de um CPF de mesmo
/// valor, e um valor vazado numa finalidade valeria na outra. O `:v1:` é o
/// mesmo espaço para versionar o esquema sem ambiguidade — trocar o prefixo
/// invalida deliberadamente os hashes antigos, e é assim que se percebe.
class HmacCpfHasher implements CpfHasher {
  HmacCpfHasher({required String pepper}) : _key = _requirePepper(pepper);

  final List<int> _key;

  static const _cpfDomain = 'sinalacs:cpf:v1:';
  static const _otpDomain = 'sinalacs:otp:v1:';

  @override
  String hash(Cpf cpf) => _hmac('$_cpfDomain${cpf.digits}');

  @override
  String hashOtpCode(String code) => _hmac('$_otpDomain$code');

  String _hmac(String message) =>
      Hmac(sha256, _key).convert(utf8.encode(message)).toString();

  /// Pepper vazio é pior que pepper ausente: `Hmac(sha256, [])` produz um hash
  /// perfeitamente válido e sem segredo nenhum — o banco pareceria protegido e
  /// não estaria. `AppConfig` já recusa o valor vazio no boot; esta é a rede
  /// de baixo, para quem construir o hasher fora da config (o seed, os testes).
  static List<int> _requirePepper(String pepper) {
    if (pepper.trim().isEmpty) {
      throw ArgumentError.value(
        pepper.length,
        'pepper',
        'o pepper do CPF não pode ser vazio: sem ele o hash é reversível por '
            'força bruta',
      );
    }
    return utf8.encode(pepper);
  }
}
