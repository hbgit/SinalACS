import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Assinatura HMAC-SHA256 de uma linha de `consent_logs` (LGPD-RT05, prova de
/// não repúdio do consentimento).
///
/// Mesmo mecanismo de `AuditChain` (`application/audit/audit_chain.dart`) —
/// HMAC, não SHA-256 puro, porque a chave (`AUDIT_CHAIN_SECRET`, o mesmo
/// segredo já usado para assinar `audit_logs`) fica fora do Postgres: quem
/// tem acesso de escrita ao banco não consegue forjar uma assinatura válida
/// sem o segredo. Ao contrário de `AuditChain`, não há cadeia de
/// sequência/hash anterior — `consent_logs` não precisa de encadeamento
/// entre linhas, só de uma assinatura por linha que prove que o valor
/// gravado é o que o servidor calculou sobre aqueles campos.
class ConsentSignature {
  ConsentSignature({required String secret}) : _secret = utf8.encode(secret);

  final List<int> _secret;

  /// Mesmo separador de controle de `AuditChain._separator` (U+001F, "unit
  /// separator") — não aparece em UUID, em nome de finalidade, em
  /// `action`/`version` nem em ISO-8601, então concatenar sem ele não faz
  /// duas linhas diferentes colidirem no mesmo payload assinado.
  static const _separator = '';

  /// HMAC-SHA256, em hexadecimal — mesmo formato de saída de
  /// `AuditChain.computeEntryHash`.
  String compute({
    required String userId,
    required String purpose,
    required String action,
    required String version,
    required DateTime timestamp,
  }) =>
      Hmac(sha256, _secret)
          .convert(utf8.encode([
            userId,
            purpose,
            action,
            version,
            timestamp.toUtc().toIso8601String(),
          ].join(_separator)))
          .toString();
}
