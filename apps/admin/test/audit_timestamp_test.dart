import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/layout_harness.dart';

/// A tela de auditoria imprimia `DateTime.toString()` cru.
///
/// Em arquivo próprio, e não somado a `audit_log_screen_test.dart`, para que os
/// testes que já existiam continuem servindo de gabarito intocado do
/// comportamento desktop.
///
/// Não usa `intl`: o backoffice não tem nenhuma dependência externa hoje, e um
/// formato pt-BR fixo basta — internacionalização não está no escopo.
void main() {
  testWidgets('formata o horário do log como dd/MM/aaaa HH:mm', (tester) async {
    await abrirBackoffice(tester, tamanho: const Size(1024, 768));
    await irPara(tester, 'Auditoria');

    expect(
      find.textContaining('.000'),
      findsNothing,
      reason: 'milissegundos e sufixo Z são ruído de DateTime.toString(), não informação de auditoria',
    );
    expect(find.textContaining(RegExp(r'\d{2}/\d{2}/\d{4} \d{2}:\d{2}')), findsWidgets);
  });
}
