/// O boot não pode morrer por causa de configuração (RNF04/L-08).
///
/// São **duas** as falhas de configuração que o `main.dart` encontra, e
/// nenhuma das duas é fatal:
///
///   · **o asset da CA do RPC** — **ausente** (`rootBundle.load` lança) ou
///     **presente mas corrompido** (vazio ou lixo), que faz
///     `setTrustedCertificatesBytes` lançar `TlsException`. Sem CA o cliente é
///     construído assim mesmo e a conexão falha de forma explícita no handshake,
///     nunca aceitando qualquer certificado;
///   · **o host do RPC sem https** — `--dart-define=SINALACS_HOST=http://…`, a
///     receita antiga que `README.md` e a skill de validação ainda traziam. O
///     app sobe, a tela de login aparece, e toda chamada falha dizendo que o
///     endereço não está em HTTPS — o motivo, em nome próprio.
///
/// O que é chamado aqui é o `main()` **real**, importado do pacote — não uma
/// cópia da sequência. O bundle é substituído pelo canal `flutter/assets`, o
/// mesmo por onde `rootBundle.load` passa no aparelho.
///
/// O host vem por `defaultHost:` e não de `--dart-define`, porque a constante de
/// compilação não muda dentro de um `flutter test`. É o que faz este arquivo
/// medir a configuração que ele **declara**, em vez de mudar de resultado
/// conforme o define com que a suíte foi compilada — antes, um `flutter test
/// --dart-define=SINALACS_HOST=http://…` reprovava estes três testes **por
/// acidente**: quem falhava era o host, e o que se afirmava era a CA.
///
/// Medido na VM (não no emulador): o `TlsException` vem do `dart:io`/BoringSSL,
/// que é o mesmo nos dois alvos — o que muda entre eles é o conteúdo do bundle,
/// e é justamente o que este arquivo controla. O aparelho continua provando o
/// caminho do asset VÁLIDO (a suíte de `integration_test/`).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/core/network/backend_config.dart';
import 'package:sinalacs_patient/main.dart' as app;

/// Canal do `flutter_local_notifications` — o mesmo que o `main.dart` aciona
/// para inicializar o plugin (RF06). No teste ele é respondido pelo `setUp`.
const _canalDeNotificacoes =
    MethodChannel('dexterous.com/flutter/local_notifications');

/// O host que o app compila hoje e que este arquivo usa como padrão: os testes
/// da CA medem a CA, e não o host.
const _hostSeguro = 'https://10.0.2.2/';

/// O host da receita antiga — o que faz o `BackendClient` recusar.
const _hostSemHttps = 'http://10.0.2.2:8080/';

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
  Future<void> subirOFApp(
    WidgetTester tester, {
    String defaultHost = _hostSeguro,
  }) async {
    logs.clear();
    final originalDebugPrint = debugPrint;
    final originalPlatform = debugDefaultTargetPlatformOverride;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await app.main(defaultHost: defaultHost);
      await tester.pump();
    } finally {
      debugPrint = originalDebugPrint;
      debugDefaultTargetPlatformOverride = originalPlatform;
    }
  }

  /// Rola o widget para dentro da viewport antes de tocar — o `ListView` da
  /// tela é mais alto que os 600dp do viewport de teste padrão. Mesmo helper de
  /// `onboarding_flow_test.dart`.
  Future<void> tocar(WidgetTester tester, String key) async {
    final finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
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

  testWidgets('host sem https: o app sobe e o log diz o motivo do host', (tester) async {
    bundleComCa(null);

    await subirOFApp(tester, defaultHost: _hostSemHttps);

    // O defeito era aqui: o `main()` subia a `BackendFailure` antes do
    // `runApp`, e a tela não existia.
    expect(find.byKey(const Key('cpf_field')), findsOneWidget);

    final sobreOHost = logs.where((linha) => linha.contains('não está em HTTPS'));
    expect(sobreOHost, isNotEmpty, reason: 'o log tem de dizer por que o host não serve');
    // **Em nome próprio**: antes esta falha só aparecia dentro da frase da CA
    // ("CA do RPC não pôde ser carregada de assets/certs/dev_rpc_ca.crt: O
    // endereço do backend (…) não está em HTTPS"), que afirmava outra coisa.
    expect(
      sobreOHost.any((linha) => !linha.contains(BackendConfig.rpcCaAsset)),
      isTrue,
      reason: 'o motivo do host não pode vir carimbado como falha da CA',
    );
  });

  testWidgets('host sem https: a tela diz o motivo, e o motivo é o host', (tester) async {
    bundleComCa(null);

    await subirOFApp(tester, defaultHost: _hostSemHttps);

    // O onboarding e não o login: é o primeiro ponto do app que fala com o
    // backend sem passar por CPF, data de nascimento ou código — o mesmo
    // motivo pelo qual a resposta do backend não diz se o CPF existe.
    await tocar(tester, 'start_onboarding_button');
    await tester.enterText(
      find.byKey(const Key('onboarding_token_field')),
      'convite-sintetico',
    );
    await tester.pump();
    await tocar(tester, 'onboarding_consent_health');
    await tocar(tester, 'complete_enrollment_button');

    final erro = tester.widget<Text>(find.byKey(const Key('onboarding_error'))).data!;
    expect(erro, contains(_hostSemHttps));
    expect(erro, contains('não está em HTTPS'));
    expect(erro, isNot(contains('CA')));
  });
}
