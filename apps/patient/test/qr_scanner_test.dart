import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sinalacs_patient/app/qr_scanner.dart';

BarcodeCapture captura(String? valor) =>
    BarcodeCapture(barcodes: [Barcode(rawValue: valor)]);

void main() {
  test('devolve o primeiro QR com texto', () {
    final gate = QrDetectionGate();
    expect(gate.accept(captura(''), routeIsCurrent: true), isNull);
    expect(gate.accept(captura('convite'), routeIsCurrent: true), 'convite');
  });

  test('a câmera entrega vários quadros: só o primeiro fecha a tela', () {
    final gate = QrDetectionGate();
    expect(gate.accept(captura('convite'), routeIsCurrent: true), 'convite');
    expect(gate.accept(captura('convite'), routeIsCurrent: true), isNull);
  });

  test('QR lido depois de a pessoa voltar é ignorado', () {
    // Durante a animação de saída a rota ainda está montada e a câmera ainda
    // entrega quadros; um pop aqui fecharia a tela de onboarding por baixo.
    final gate = QrDetectionGate();
    expect(gate.accept(captura('convite'), routeIsCurrent: false), isNull);
  });
}
