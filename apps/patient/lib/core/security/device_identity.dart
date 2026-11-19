import 'dart:convert';
import 'dart:math';

/// Sorteio da identidade de instalação e do segredo da credencial de
/// dispositivo (C-05, RF24). Rode uma vez por instalação: o par é o que liga
/// ESTE aparelho ao identificador pseudônimo no servidor.
///
/// `deviceId` é um UUID v4 minúsculo — um identificador de instalação
/// efêmero, **nunca** um identificador de hardware (`spec/lgpd_data_audit.md`
/// §2.4) — e o segredo tem 32 bytes de `Random.secure()` (256 bits), que não
/// deixa espaço de busca a enumerar: por isso o servidor guarda só o SHA-256.

/// UUID v4 minúsculo a partir de `Random.secure()`, sem dependência do pacote
/// `uuid` — só os 6 bits de versão/variante do RFC 4122.
String generateUuidV4({Random? random}) {
  final rng = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // versão 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variante 10xx
  final hex =
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Segredo de 32 bytes em base64url sem padding (43 caracteres).
String generateDeviceSecret({Random? random}) {
  final rng = random ?? Random.secure();
  final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}
