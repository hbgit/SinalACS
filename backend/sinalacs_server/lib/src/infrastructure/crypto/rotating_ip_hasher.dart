import 'dart:convert';

import 'package:crypto/crypto.dart';

/// HMAC-SHA-256 do IP com chave rotativa DIÁRIA (spec/lgpd_data_audit.md §2.1
/// e §2.6).
///
/// O espaço de endereçamento público do IPv4 tem 2^32 combinações: SHA-256
/// puro sobre o IP é reversível por força bruta/rainbow table quase imediata.
/// Aqui o hash é chaveado — o segredo vem de `AUDIT_CHAIN_SECRET`, o mesmo da
/// cadeia de `audit_logs`, que fica FORA do Postgres — e a chave efetiva roda
/// todo dia, em dois passos:
///
///   1. deriva a chave do dia: `HMAC(secret, 'sinalacs:ip:v1:<YYYY-MM-DD>')`;
///   2. hasheia o endereço com ela: `HMAC(chaveDoDia, remoteInfo)`.
///
/// Consequências deliberadas:
///   - sem o segredo, não há pré-computação possível (rainbow table morre);
///   - dentro do MESMO dia UTC, o mesmo IP produz o mesmo hash — a correlação
///     de incidentes da janela, que a §2.6 pede para preservar, continua
///     possível;
///   - entre dias, o hash muda — o rastro de rede do titular não persiste
///     além da janela de rotação.
///
/// O prefixo `sinalacs:ip:v1:` é separação de domínio, no mesmo molde de
/// `sinalacs:cpf:v1:`/`sinalacs:otp:v1:` (`HmacCpfHasher`): a derivação de
/// chave não pode colidir com outro protocolo que use o mesmo segredo.
/// `package:crypto` em vez de `package:cryptography` pelo mesmo motivo do
/// hasher de CPF: operação síncrona e barata.
class RotatingIpHasher {
  RotatingIpHasher({required String secret, DateTime Function()? clock})
      : _secret = _requireSecret(secret),
        _clock = clock ?? DateTime.now;

  final List<int> _secret;
  final DateTime Function() _clock;

  static const _domain = 'sinalacs:ip:v1:';

  /// HMAC-SHA-256 em hexadecimal — mesmo formato do `ipHash` anterior.
  String hash(String remoteInfo) {
    final dayKey = Hmac(sha256, _secret)
        .convert(utf8.encode('$_domain${_dayOf(_clock())}'))
        .bytes;
    return Hmac(sha256, dayKey).convert(utf8.encode(remoteInfo)).toString();
  }

  static String _dayOf(DateTime now) {
    final utc = now.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}-'
        '${utc.month.toString().padLeft(2, '0')}-'
        '${utc.day.toString().padLeft(2, '0')}';
  }

  /// Segredo vazio é pior que ausente: `Hmac(sha256, [])` produz um hash
  /// perfeitamente válido e sem segredo nenhum — a coluna pareceria protegida
  /// e não estaria. `AppConfig` já recusa `AUDIT_CHAIN_SECRET` vazio no boot;
  /// esta é a rede de baixo, para quem construir o hasher fora da config.
  static List<int> _requireSecret(String secret) {
    if (secret.trim().isEmpty) {
      throw ArgumentError.value(
        secret.length,
        'secret',
        'o segredo do hash de IP não pode ser vazio: sem ele o hash é '
            'reversível por força bruta',
      );
    }
    return utf8.encode(secret);
  }
}
