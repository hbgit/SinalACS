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
///     receita antiga que `README.md` e `apps/CLAUDE.md` ainda traziam. O app
///     sobe, a tela de login aparece, e toda chamada falha dizendo que o
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
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/network/backend_config.dart';
import 'package:sinalacs_acs/main.dart' as app;

/// O host que o app compila hoje e que este arquivo usa como padrão: os testes
/// da CA medem a CA, e não o host.
const _hostSeguro = 'https://10.0.2.2/';

/// O host da receita antiga — o que faz o `BackendClient` recusar.
const _hostSemHttps = 'http://10.0.2.2:8080/';

/// Credencial sintética, os mesmos valores dos testes de tela
/// (`login_flow_test.dart`). Nenhuma senha real, e aqui nenhum backend é
/// alcançado: o que se mede é a mensagem que a tela mostra.
const _matricula = 'ACS-001';
const _senha = 'senha-sintetica';

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
  Future<void> subirOFApp(
    WidgetTester tester, {
    String defaultHost = _hostSeguro,
  }) async {
    logs.clear();
    final originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
    try {
      await app.main(defaultHost: defaultHost);
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

  testWidgets('host sem https: o app sobe e o log diz o motivo do host', (tester) async {
    bundleComCa(null);

    await subirOFApp(tester, defaultHost: _hostSemHttps);

    // O defeito era aqui: o `main()` subia a `BackendFailure` antes do
    // `runApp`, e a tela não existia.
    expect(find.byKey(const Key('matricula_field')), findsOneWidget);

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

    await tester.enterText(find.byKey(const Key('matricula_field')), _matricula);
    await tester.enterText(find.byKey(const Key('senha_field')), _senha);
    await tester.tap(find.byKey(const Key('login_button')));
    await tester.pumpAndSettle();

    final erro = tester.widget<Text>(find.byKey(const Key('login_error'))).data!;
    expect(erro, contains(_hostSemHttps));
    expect(erro, contains('não está em HTTPS'));
    expect(erro, isNot(contains('CA')));
  });
}
