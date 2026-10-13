import 'package:flutter/material.dart';

import 'package:sinalacs_admin/app/admin_theme.dart';
import 'package:sinalacs_admin/app/monitoring_controller.dart';

/// Faixa "N vermelhos vencidos" (#44, F2), ao lado do título das telas Painel
/// e Alertas ([TitleWithOverdueRed]).
///
/// O número é o `overdueRed` do último pulso (a mesma regra de "vencido" do
/// servidor, `alert_overdue_sql.dart`). Existe porque a lista pode esconder um
/// vencido atrás de um filtro: a faixa diz que ele existe mesmo assim. Some
/// com zero e antes do primeiro pulso. Não é botão.
///
/// Ícone **e** texto (WCAG 1.4.1), `liveRegion` (WCAG 4.1.3). É risco
/// clínico vermelho, por isso `redOnSurface` (o token de texto do vermelho;
/// o `red` de preenchimento cai para ~3:1 sobre `surfaceRaised`), com o par
/// medido em `test/contrast_tokens_test.dart`.
class OverdueRedBanner extends StatelessWidget {
  const OverdueRedBanner(this.monitoring, {super.key});

  final MonitoringController monitoring;

  static String text(int n) => n == 1 ? '1 vermelho vencido' : '$n vermelhos vencidos';

  /// Quantos vencidos o último pulso contou (0 antes do primeiro).
  static int countOf(MonitoringController monitoring) => monitoring.lastPulse?.overdueRed ?? 0;

  @override
  Widget build(BuildContext context) {
    final n = countOf(monitoring);
    if (n <= 0) return const SizedBox.shrink();
    return Semantics(
      key: const Key('overdue_red_banner'),
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AdminColors.surfaceRaised,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AdminColors.redOnSurface),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded, color: AdminColors.redOnSurface, size: 18),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text(n),
                style: const TextStyle(color: AdminColors.redOnSurface, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Título da tela com a faixa [OverdueRedBanner] ao lado (#44).
///
/// Na mesma linha do título, e não numa linha própria acima da lista: no
/// desktop a faixa não empurra os cartões para baixo da dobra; numa tela
/// estreita (ou com fonte grande) o `Wrap` a desce para a linha seguinte.
class TitleWithOverdueRed extends StatelessWidget {
  const TitleWithOverdueRed(this.title, this.monitoring, {super.key});

  final String title;
  final MonitoringController monitoring;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          if (OverdueRedBanner.countOf(monitoring) > 0) OverdueRedBanner(monitoring),
        ],
      );
}
