/// A primeira abertura não fica presa ao diálogo de permissão de notificações
/// (#153, RF06/RF14/INV-03).
///
/// Antes, o `main.dart` esperava `requestNotificationsPermission()` **antes**
/// do `runApp`: no Android 13+, numa instalação limpa, nenhuma tela era
/// desenhada — nem a de urgência — enquanto o diálogo do sistema não recebia
/// resposta.
///
/// Aqui o `main()` **real** sobe com o canal do `flutter_local_notifications`
/// respondendo `initialize`, mas deixando `requestNotificationsPermission`
/// pendente para sempre — um diálogo que ninguém responde. O `main()` não é
/// aguardado antes da asserção de propósito: com o defeito de volta ele nunca
/// termina, e o teste reprova por não achar a tela, em vez de ficar pendurado.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/main.dart' as app;

const _canalDeNotificacoes = MethodChannel('dexterous.com/flutter/local_notifications');

void main() {
  final chamadas = <String>[];

  setUp(() {
    chamadas.clear();
    // O asset da CA ausente (o canal não responde): o `main()` segue sem ela,
    // como em `main_boot_ca_test.dart`.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (_) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_canalDeNotificacoes, (call) {
      chamadas.add(call.method);
      if (call.method == 'requestNotificationsPermission') {
        // O diálogo do sistema aberto e sem resposta.
        return Completer<bool?>().future;
      }
      return Future<bool>.value(true);
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_canalDeNotificacoes, null);
  });

  testWidgets('a primeira tela é desenhada com o pedido de permissão pendente', (tester) async {
    final originalDebugPrint = debugPrint;
    final originalPlatform = debugDefaultTargetPlatformOverride;
    // Android simulado: é onde o plugin pediria a permissão (fora dele o
    // `resolvePlatformSpecificImplementation` devolve `null` e o teste não
    // mediria nada). O `debugPrint` é silenciado só pelo log da CA ausente.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    debugPrint = (String? message, {int? wrapWidth}) {};
    try {
      var subiu = false;
      unawaited(app.main(defaultHost: 'https://10.0.2.2/').then((_) => subiu = true));
      for (var i = 0; i < 10 && !subiu; i++) {
        await tester.pump();
      }

      expect(subiu, isTrue, reason: 'o main() não pode esperar o diálogo de permissão');
      expect(find.byKey(const Key('cpf_field')), findsOneWidget);
      expect(chamadas, contains('initialize'));
      expect(
        chamadas,
        isNot(contains('requestNotificationsPermission')),
        reason: 'a partida não pede a permissão; o pedido é feito ao criar um lembrete',
      );
    } finally {
      debugPrint = originalDebugPrint;
      debugDefaultTargetPlatformOverride = originalPlatform;
    }
  });
}
