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
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/core/network/backend_config.dart';
import 'package:sinalacs_patient/main.dart' as app;

/// Canal do `flutter_local_notifications` — o mesmo que o `main.dart` aciona
/// para inicializar o plugin (RF06). No teste ele é respondido pelo `setUp`.
const _canalDeNotificacoes =
    MethodChannel('dexterous.com/flutter/local_notifications');

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

  setUp(() {
    // Sem isto o `main()` para no plugin de notificações — e para
    // **silenciosamente**: a chamada de canal não respondida não completa no
    // relógio falso do `testWidgets` (medido: o teste fica pendurado, sem
    // exceção nenhuma). No aparelho quem responde é o plugin nativo.
    //
    // `true` e não `null`: `initialize` declara `Future<bool>` e uma resposta
    // nula vira `type 'Null' is not a subtype of type 'FutureOr<bool>'` — um
    // erro do teste, que não tem nada a ver com a guarda da CA.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_canalDeNotificacoes, (call) async => true);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_canalDeNotificacoes, null);
  });

  /// Sobe o app pelo caminho de produção e para na tela de login.
  ///
  /// Duas variáveis de debug da `foundation` são trocadas e devolvidas ao valor
  /// original **antes do fim do corpo do teste** (o `flutter_test` reprova
  /// qualquer uma que continue trocada quando o teste termina):
  ///
  ///   · `defaultTargetPlatform` — o `main()` inicializa o plugin de
  ///     notificações; no alvo Linux o plugin exige `InitializationSettings.linux`
  ///     (que o app não passa, porque só roda no Android) e lançaria
  ///     `ArgumentError` — um erro do alvo do teste, não da guarda que ele mede.
  ///     No Android simulado o plugin segue o mesmo ramo do aparelho, e quem
  ///     responde ao canal é o `setUp` acima;
  ///   · `debugPrint` — a causa real da falha só existe no log (a tela mostra
  ///     "erro de conexão"), então é ele que precisa ser afirmado.
  Future<void> subirOFApp(WidgetTester tester) async {
    logs.clear();
    final originalDebugPrint = debugPrint;
    final originalPlatform = debugDefaultTargetPlatformOverride;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await app.main();
      await tester.pump();
    } finally {
      debugPrint = originalDebugPrint;
      debugDefaultTargetPlatformOverride = originalPlatform;
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

    expect(find.byKey(const Key('cpf_field')), findsOneWidget);
    expect(find.byKey(const Key('enter_button')), findsOneWidget);
    esperaFalhaNaoFatal();
  });

  testWidgets('asset vazio: o app sobe e a corrupção é logada', (tester) async {
    bundleComCa(const <int>[]);

    await subirOFApp(tester);

    expect(find.byKey(const Key('cpf_field')), findsOneWidget);
    esperaFalhaNaoFatal();
  });

  testWidgets('asset com lixo: o app sobe e a corrupção é logada', (tester) async {
    bundleComCa(utf8.encode('isto não é um certificado'));

    await subirOFApp(tester);

    expect(find.byKey(const Key('cpf_field')), findsOneWidget);
    esperaFalhaNaoFatal();
  });
}
