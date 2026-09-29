import 'dart:convert';

import 'package:sinalacs_server/src/infrastructure/crypto/health_data_cipher.dart';

/// Ponte entre o valor ESTRUTURADO que `application/` manipula
/// (`List<String>`, `List<TriageAnswer>`, `Map<String, String>`) e o par
/// `(ciphertext, keyVersion)` que a coluna guarda.
///
/// Vive em `infrastructure/` de propósito: é exatamente o conhecimento que
/// não pode vazar para os serviços de domínio (decisão §6.1 de
/// `docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md`).
/// Os três stores ORM cifrados usam este mesmo par de funções, para que a
/// serialização seja idêntica nos três e a rotação de chave tenha um único
/// ponto de mudança.
extension EncryptedJson on HealthDataCipher {
  /// Serializa para JSON e cifra. `null` vira o JSON `null`, não uma coluna
  /// vazia — a ausência de ciphertext é reservada para linhas nunca escritas.
  Future<EncryptedValue> encryptJson(Object? value) => encrypt(jsonEncode(value));

  /// Decifra e desserializa. Um ciphertext vazio devolve `null`: é o estado
  /// de uma linha gravada fora do caminho Dart (seed SQL antes do
  /// `bin/seed_health_data.dart`, por exemplo), e não deve derrubar a leitura
  /// do prontuário inteiro.
  Future<Object?> decryptJson(String ciphertextBase64, int keyVersion) async {
    if (ciphertextBase64.isEmpty) return null;
    final json = await decrypt(EncryptedValue(
      ciphertextBase64: ciphertextBase64,
      keyVersion: keyVersion,
    ));
    return jsonDecode(json);
  }
}
