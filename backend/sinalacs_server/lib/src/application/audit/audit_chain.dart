import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Os campos de uma linha de `audit_logs` que entram no cálculo da cadeia de
/// hash, na forma que `application/` conhece — não o `AuditLog` gerado, para
/// não acoplar este cálculo ao ORM.
class AuditChainFields {
  const AuditChainFields({
    required this.sequence,
    required this.previousHash,
    required this.userId,
    required this.actionType,
    required this.resourceType,
    required this.resourceId,
    required this.timestamp,
    required this.ipHash,
    required this.result,
  });

  final int sequence;
  final String previousHash;
  final String userId;
  final String actionType;
  final String resourceType;
  final String? resourceId;
  final DateTime timestamp;
  final String ipHash;
  final String result;
}

/// Calcula o elo de uma cadeia de hash sobre `audit_logs` (LGPD-RT03).
///
/// Cada linha encadeia à anterior por `previousHash`, e `entryHash` é um
/// HMAC-SHA256 do conteúdo da linha — HMAC, não SHA-256 puro, porque a chave
/// fica fora do Postgres (`AUDIT_CHAIN_SECRET`): quem tem acesso de escrita ao
/// banco consegue recalcular um hash simples depois de adulterar uma linha,
/// mas não consegue forjar uma assinatura sem o segredo. `OrmAuditTrail`
/// escreve com esta classe, e `AuditChainVerifier` lê com ela — o mesmo
/// código dos dois lados, para uma segunda implementação do cálculo não virar
/// a forma mais provável de a verificação mentir.
class AuditChain {
  AuditChain({required String secret}) : _secret = utf8.encode(secret);

  final List<int> _secret;

  /// `previousHash` da primeira linha da cadeia. Nunca nulo — gênese e "linha
  /// escrita antes de a cadeia existir" não podem ter a mesma representação.
  static const genesisHash = '0000000000000000000000000000000000000000000000000000000000000000';

  /// HMAC-SHA256, em hexadecimal — mesmo formato de `ipHash`, que já usa
  /// `.toString()` sobre um `Digest`. Não é base64Url: aquele é o formato de
  /// token JWT, um contexto diferente.
  String computeEntryHash(AuditChainFields fields) =>
      Hmac(sha256, _secret).convert(utf8.encode(_payloadOf(fields))).toString();

  /// Compara em tempo constante, no mesmo molde de
  /// `DevelopmentAuthService._matchesSignature` — o campo é uma assinatura,
  /// então comparar com `==` vazaria timing.
  bool matches(AuditChainFields fields, String entryHash) {
    final expected = computeEntryHash(fields);
    if (expected.length != entryHash.length) return false;
    var difference = 0;
    for (var index = 0; index < expected.length; index++) {
      difference |= expected.codeUnitAt(index) ^ entryHash.codeUnitAt(index);
    }
    return difference == 0;
  }

  /// U+001F (INFORMATION SEPARATOR ONE / "unit separator"), o caractere de
  /// controle — não o símbolo visível ␟ (U+241F), que é outro código: não
  /// aparece em UUID, em hex, em ISO-8601 nem nos valores de
  /// `actionType`/`result` já em uso, então concatenar sem ele não faz dois
  /// conjuntos de campos diferentes colidirem no mesmo payload.
  static const _separator = '\u001F';

  String _payloadOf(AuditChainFields fields) => [
        fields.sequence.toString(),
        fields.previousHash,
        fields.userId,
        fields.actionType,
        fields.resourceType,
        fields.resourceId ?? '',
        fields.timestamp.toUtc().toIso8601String(),
        fields.ipHash,
        fields.result,
      ].join(_separator);
}
