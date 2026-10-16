import 'package:sinalacs_server/src/config/app_config.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/encrypted_json.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/encrypted_risk_level.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/health_data_cipher.dart';
import 'package:test/test.dart';

/// Codec do risco cifrado (issue #75, INV-04). Hermético: só a cifra, sem banco.
void main() {
  final cipher = HealthDataCipher(
    keyHex: AppConfig.developmentHealthDataEncryptionKey,
    keyVersion: 1,
  );

  test('cada nível e a ausência fazem ida e volta', () async {
    for (final risk in <RiskLevel?>[...RiskLevel.values, null]) {
      final encrypted = await cipher.encryptRiskLevel(risk);
      expect(
        await cipher.decryptRiskLevel(encrypted.ciphertextBase64, encrypted.keyVersion),
        risk,
        reason: 'ida e volta de $risk',
      );
    }
  });

  test('o tamanho do ciphertext não revela a classe: todos têm o mesmo '
      'comprimento, inclusive a ausência', () async {
    final lengths = {
      for (final risk in <RiskLevel?>[...RiskLevel.values, null])
        risk: (await cipher.encryptRiskLevel(risk)).ciphertextBase64.length,
    };
    expect(lengths.values.toSet(), hasLength(1), reason: 'comprimentos: $lengths');
  });

  test('o mesmo risco cifrado duas vezes dá ciphertexts diferentes (nonce '
      'aleatório: igualdade de coluna não agrupa pacientes por risco)', () async {
    final a = await cipher.encryptRiskLevel(RiskLevel.red);
    final b = await cipher.encryptRiskLevel(RiskLevel.red);
    expect(a.ciphertextBase64, isNot(b.ciphertextBase64));
  });

  test('ciphertext vazio (linha nunca escrita pelo caminho Dart) vira null', () async {
    expect(await cipher.decryptRiskLevel('', 1), isNull);
  });

  test('nome desconhecido lança em vez de inventar um risco (INV-02)', () async {
    final forjado = await cipher.encryptJson('purple');
    expect(
      () => cipher.decryptRiskLevel(forjado.ciphertextBase64, forjado.keyVersion),
      throwsArgumentError,
    );
  });
}
