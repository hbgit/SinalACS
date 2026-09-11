import 'dart:math';

/// Gera a chave de idempotência de um alerta vermelho.
///
/// O servidor usa esta chave para não criar um segundo alerta quando a mesma
/// tentativa é reenviada (`alerts.createRedAlert` grava a chave junto com o
/// alerta). Por isso a chave precisa ser gerada **uma vez por tentativa do
/// usuário** e reaproveitada em todos os retries dessa tentativa — gerar uma
/// nova a cada envio anularia a proteção e duplicaria o alerta.
String newIdempotencyKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));

  // Formato UUID v4, só para manter a chave reconhecível em log do servidor.
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
