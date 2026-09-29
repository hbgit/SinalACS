import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Lê um QR Code e devolve o texto dele, ou `null` se a pessoa voltar sem ler.
/// Pode lançar quando a câmera não está disponível.
typedef QrScanner = Future<String?> Function(BuildContext context);

/// Disponibiliza o [QrScanner] para a árvore de widgets.
///
/// Mesmo padrão de `BackendScope`/`LocationScope`: a tela de onboarding não
/// abre a câmera diretamente, o que permite trocar o leitor por um duplo em
/// teste hermético — a câmera real é canal de plataforma e não existe no
/// `flutter test`.
class QrScannerScope extends InheritedWidget {
  const QrScannerScope({required this.scanner, required super.child, super.key});

  final QrScanner scanner;

  static QrScanner of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<QrScannerScope>();
    assert(scope != null, 'Nenhum QrScannerScope acima deste widget.');
    return scope!.scanner;
  }

  @override
  bool updateShouldNotify(QrScannerScope oldWidget) => scanner != oldWidget.scanner;
}

/// Leitor real: abre a câmera numa tela própria e devolve o primeiro QR lido.
/// A imagem não é guardada nem enviada — só o texto do QR volta.
Future<String?> scanQrWithCamera(BuildContext context) =>
    Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _CameraScanPage()),
    );

class _CameraScanPage extends StatefulWidget {
  const _CameraScanPage();

  @override
  State<_CameraScanPage> createState() => _CameraScanPageState();
}

class _CameraScanPageState extends State<_CameraScanPage> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);

  // A câmera entrega vários quadros por segundo: sem esta trava, o mesmo QR
  // tentaria fechar a tela várias vezes.
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.isNotEmpty) {
        _done = true;
        Navigator.of(context).pop(value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ler QR Code do convite')),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Não foi possível usar a câmera. Volte e digite o código do convite.',
                  key: Key('camera_error'),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          const Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Aponte a câmera para o QR Code mostrado pelo agente de saúde.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
