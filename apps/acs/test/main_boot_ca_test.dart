/// O boot não pode morrer por causa do asset da CA do RPC (RNF04/L-08).
///
/// `main.dart` lê a CA do RPC do bundle e monta o `SecurityContext` do cliente.
/// O asset pode falhar de duas formas, e **nenhuma das duas é fatal**:
///
///   · **ausente** — `rootBundle.load` lança (`FlutterError: Unable to load
///     asset`), o caso que já era tratado;
///   · **presente mas corrompido** (vazio ou lixo) — `setTrustedCertificatesBytes`
///     lança `TlsException`, e essa exceção acontecia **fora** da guarda, isto é,
///     ANTES do `runApp`: exceção não tratada e app que não sobe. É o buraco que
///     este arquivo tranca.
///
/// O que é chamado aqui é o `main()` **real**, importado do pacote — não uma
/// cópia da sequência. O bundle é substituído pelo canal `flutter/assets`, o
/// mesmo por onde `rootBundle.load` passa no aparelho.
///
/// Medido na VM (não no emulador): o `TlsException` vem do `dart:io`/BoringSSL,
/// que é o mesmo nos dois alvos — o que muda entre eles é o conteúdo do bundle,
/// e é justamente o que este arquivo controla. O aparelho continua provando o
/// caminho do asset VÁLIDO (a suíte de `integration_test/`).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/network/backend_config.dart';
import 'package:sinalacs_acs/main.dart' as app;

void main() {
  final logs = <String>[];

  /// Faz o bundle responder [bytes] para a CA do RPC.
  ///
  /// `null` é o asset ausente: o canal não responde e `rootBundle.load` lança,
  /// exatamente como quando o `sync_dev_ca.sh` nunca rodou.
  void bundleComCa(List<int>? bytes) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
      final key = utf8.decode(message!.buffer.asUint8List());
      if (key != BackendConfig.rpcCaAsset) return null;
      return bytes == null ? null : ByteData.sublistView(Uint8List.fromList(bytes));
    });
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  /// Sobe o app pelo caminho de produção e devolve a tela de login.
  ///
  /// O `debugPrint` é trocado só durante o `main()` e devolvido ao valor
  /// original antes do fim do corpo do teste: a causa real da falha só existe
  /// no log (a tela mostra "erro de conexão"), então é ele que precisa ser
  /// afirmado — e o `flutter_test` reprova qualquer variável de debug da
  /// `foundation` que continue trocada quando o teste termina.
  Future<void> subirOFApp(WidgetTester tester) async {
    logs.clear();
    final originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
    try {
      await app.main();
      await tester.pump();
    } finally {
      debugPrint = originalDebugPrint;
    }
  }

  /// A falha esperada: o app de pé e o log dizendo qual é o problema e o que
  /// fazer. Sem CA o cliente é construído assim mesmo — a conexão falha de
  /// forma explícita no handshake, nunca aceitando qualquer certificado.
  void esperaFalhaNaoFatal() {
    expect(
      logs.join('\n'),
      allOf(
        contains(BackendConfig.rpcCaAsset),
        contains('não pôde ser carregada'),
        contains('sync_dev_ca.sh'),
      ),
    );
  }

  testWidgets('asset ausente: o app sobe e a falta da CA é logada', (tester) async {
    bundleComCa(null);

    await subirOFApp(tester);

    expect(find.byKey(const Key('matricula_field')), findsOneWidget);
    esperaFalhaNaoFatal();
  });

  testWidgets('asset vazio: o app sobe e a corrupção é logada', (tester) async {
    bundleComCa(const <int>[]);

    await subirOFApp(tester);

    expect(find.byKey(const Key('matricula_field')), findsOneWidget);
    esperaFalhaNaoFatal();
  });

  testWidgets('asset com lixo: o app sobe e a corrupção é logada', (tester) async {
    bundleComCa(utf8.encode('isto não é um certificado'));

    await subirOFApp(tester);

    expect(find.byKey(const Key('matricula_field')), findsOneWidget);
    esperaFalhaNaoFatal();
  });
}
