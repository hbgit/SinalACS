import 'package:flutter/widgets.dart';

/// Pontos de quebra do backoffice.
///
/// O backoffice é desktop-first (`spec/PRD_system.md` §2.1): o layout com
/// NavigationRail continua sendo o padrão e o layout compacto é complemento
/// para celular, nunca substituição.
///
/// Existem como constantes nomeadas porque o mesmo número é consultado em
/// pontos distantes do `app.dart` (shell, cabeçalho, filtros, cartões,
/// listas). Enquanto era o literal `640` solto em um único `LayoutBuilder`,
/// qualquer segundo uso teria sido uma cópia sem relação declarada com a
/// primeira.
abstract final class AdminBreakpoints {
  /// Acima disto, NavigationRail lateral; abaixo, NavigationBar inferior.
  static const double rail = 640;

  /// Abaixo disto, pares de controles lado a lado passam a empilhar: os dois
  /// filtros de Alertas, o rótulo/valor de `_InfoRow` e o `trailing` das
  /// listas. 480 e não 600 porque só afeta pares — a 480dp dois campos ainda
  /// têm ~230dp cada, que é onde o rótulo do dropdown ainda cabe.
  static const double stacked = 480;

  /// Largura-alvo mínima de um cartão de contador antes de reduzir a grade.
  static const double counterCardMin = 160;
}

/// Altura do cabeçalho, acompanhando a escala de fonte do sistema.
///
/// `PreferredSizeWidget.preferredSize` é um getter sem `BuildContext`, então a
/// altura precisa ser calculada por quem monta o `Scaffold` e passada adiante.
/// Sem isso, com fonte grande no Android as duas linhas do título estouram os
/// 72dp fixos — e `AppBar` corta em vez de crescer.
///
/// O teto de 132 existe para que fonte a 200% não coma metade da tela de um
/// celular; o título já usa elipse, então o corte é o do texto, não do layout.
double adminHeaderHeight(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(72).clamp(72.0, 132.0);
