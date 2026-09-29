import 'dart:ui' show Tristate;

import 'package:flutter/rendering.dart' show PipelineOwner;
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// Varredura de nós semânticos anunciados como **botão** que não respondem ao
/// toque.
///
/// É a classe de defeito do WCAG 4.1.2 / 2.5.3 que já apareceu duas vezes neste
/// app: no login e no botão de EMERGÊNCIA. Um `Semantics(button: true, ...)` em
/// volta de um botão de verdade **não funde** com ele — cria um nó próprio, com
/// papel de botão e sem ação de toque, que o leitor de tela anuncia (e por onde
/// a pessoa começa) antes do controle real.
///
/// Prender isso por um sítio não pega a classe: `find.byKey(...)` +
/// `hasAction(tap)` passa justamente com o defeito, porque o nó que carrega o
/// nome é o inerte e o que responde ao toque é o filho. Esta varredura olha a
/// árvore inteira.
///
/// **Controle legitimamente desabilitado não conta.** Um `FilledButton` com
/// `onPressed: null` também é `isButton` sem ação de toque — mas ele *declara*
/// isso (`isEnabled == Tristate.isFalse`) e o leitor de tela anuncia
/// "desativado". Não é um nó inerte, é um controle desabilitado; sem esse
/// cuidado a varredura acusaria toda tela com um botão desabilitado (medido
/// nesta árvore: "Sincronizar agora", "Tentar de novo", "Descartar recusada(s)")
/// e uma varredura que grita onde não há defeito é uma varredura que alguém
/// apaga. Quem não declara estado nenhum (`Tristate.none`) e também não responde
/// ao toque é que é o defeito.
List<String> botoesInertes(WidgetTester tester) {
  // As raízes semânticas vivem nos `PipelineOwner` da árvore, não só na raiz
  // dela — mesmo caminho que o `SemanticsFinder` do `flutter_test` usa.
  final raizes = <SemanticsNode>[];
  void coletar(PipelineOwner owner) {
    final raiz = owner.semanticsOwner?.rootSemanticsNode;
    if (raiz != null) {
      raizes.add(raiz);
    }
    owner.visitChildren(coletar);
  }

  coletar(tester.binding.rootPipelineOwner);
  expect(
    raizes,
    isNotEmpty,
    reason: 'sem árvore semântica: chame tester.ensureSemantics() antes da varredura',
  );

  final inertes = <String>[];
  var botoes = 0;
  void varrer(SemanticsNode node) {
    // Nó mesclado no pai (`MergeSemantics`) não é anunciado por si: o que a
    // plataforma recebe é a fronteira da fusão, com rótulo e ações já
    // combinados. Contá-lo faria a varredura acusar o que ninguém ouve — medido
    // no botão de emergência corrigido: a fronteira `#48` (`merged=false`,
    // rótulo "Enviar alerta de emergência\nEMERGÊNCIA", com `tap`) e o nó do
    // próprio botão `#49` (`merged=true`), que não chega ao leitor de tela.
    if (node.isMergedIntoParent) {
      return;
    }
    final data = node.getSemanticsData();
    if (data.flagsCollection.isButton) {
      botoes++;
      if (!data.hasAction(SemanticsAction.tap) &&
          data.flagsCollection.isEnabled != Tristate.isFalse) {
        inertes.add('${data.label} (rect=${node.rect})');
      }
    }
    node.visitChildren((child) {
      varrer(child);
      return true;
    });
  }

  for (final raiz in raizes) {
    varrer(raiz);
  }

  // Guarda contra o passe vazio: uma tela que não chegou a montar não tem botão
  // nenhum e a varredura passaria sem ter olhado nada.
  expect(
    botoes,
    greaterThan(0),
    reason: 'nenhum nó "botão" na árvore — a varredura não mediu nada',
  );
  return inertes;
}

/// Asserção pronta para os testes de tela: nenhum nó anunciado como botão pode
/// deixar de responder ao toque.
void expectNenhumBotaoInerte(WidgetTester tester) {
  expect(
    botoesInertes(tester),
    isEmpty,
    reason: 'nó "botão" sem ação de toque anunciado ao leitor de tela',
  );
}
