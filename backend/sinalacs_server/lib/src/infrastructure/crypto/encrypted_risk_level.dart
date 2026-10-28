import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/encrypted_json.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/health_data_cipher.dart';

/// Cifra de uma classificação de risco em repouso (INV-04, issue #75).
///
/// O AES-GCM não esconde o TAMANHO do texto claro: `"red"` cifrado sairia
/// mais curto que `"yellow"`, e quem lê a coluna bruta separaria os vermelhos
/// pelo comprimento do base64. Por isso o nome vai preenchido com espaços até
/// a largura do maior nome de [RiskLevel], e a ausência (`null`, o
/// `riskLevelAfter` de uma visita ainda não concluída) vai como só espaços,
/// do mesmo tamanho.
///
/// Usada pelos stores ORM de triagem e de visita; vive em `infrastructure/`
/// pelo mesmo motivo de [EncryptedJson].
extension EncryptedRiskLevel on HealthDataCipher {
  static final int _width =
      RiskLevel.values.map((r) => r.name.length).reduce((a, b) => a > b ? a : b);

  Future<EncryptedValue> encryptRiskLevel(RiskLevel? risk) =>
      encryptJson((risk?.name ?? '').padRight(_width));

  /// `null` para ciphertext vazio (linha nunca escrita pelo caminho Dart) e
  /// para a ausência cifrada; quem chama decide se `null` é aceitável. Um
  /// nome desconhecido lança `ArgumentError` — nunca vira um risco inventado.
  Future<RiskLevel?> decryptRiskLevel(String ciphertextBase64, int keyVersion) async {
    final decoded = await decryptJson(ciphertextBase64, keyVersion);
    if (decoded == null) return null;
    final name = (decoded as String).trim();
    if (name.isEmpty) return null;
    return RiskLevel.values.byName(name);
  }
}
