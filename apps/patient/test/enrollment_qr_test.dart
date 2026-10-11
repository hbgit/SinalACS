import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/core/onboarding/enrollment_qr.dart';

/// Token sintético no formato real: 43 caracteres base64url.
const conviteSintetico = 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789-_AbCde';

void main() {
  test('aceita um convite no formato do servidor', () {
    expect(conviteSintetico.length, 43);
    expect(parseEnrollmentQr(conviteSintetico), conviteSintetico);
  });

  test('tira espaços e quebras de linha nas pontas', () {
    expect(parseEnrollmentQr('  $conviteSintetico\n'), conviteSintetico);
  });

  test('recusa QR que não é convite', () {
    expect(parseEnrollmentQr('https://exemplo.invalid/pagina'), isNull);
    expect(parseEnrollmentQr('00020126580014br.gov.bcb.pix'), isNull);
    expect(parseEnrollmentQr(''), isNull);
    expect(parseEnrollmentQr(conviteSintetico.substring(1)), isNull, reason: '42 caracteres');
    expect(parseEnrollmentQr('${conviteSintetico}A'), isNull, reason: '44 caracteres');
    expect(parseEnrollmentQr(conviteSintetico.replaceFirst('A', '+')), isNull,
        reason: 'base64 padrão, não url-safe');
  });
}
