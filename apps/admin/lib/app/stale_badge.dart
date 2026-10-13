import 'package:flutter/material.dart';

import 'package:sinalacs_admin/app/admin_theme.dart';
import 'package:sinalacs_admin/app/monitoring_controller.dart';

/// Faixa de dado desatualizado (#44; ADR "Intervalo e selo de desatualizado").
///
/// Ícone **e** texto (não só cor, WCAG 1.4.1), `liveRegion` para o leitor de
/// tela anunciar quando aparece (WCAG 4.1.3). A cor é `overdueOnSurface`, o
/// laranja de atenção não clínica do backoffice: vermelho, amarelo e verde são
/// só risco clínico, e dado velho não é risco. Contraste sobre `surfaceRaised`
/// e `background` em `test/contrast_tokens_test.dart`. Não é interativa.
class StaleBadge extends StatelessWidget {
  const StaleBadge({required this.lastSuccess, required this.now, super.key = const Key('stale_badge')});

  final DateTime lastSuccess;
  final DateTime now;

  /// Minutos sem atualização, arredondados para cima, no mínimo 1.
  static int minutesSince(DateTime lastSuccess, DateTime now) {
    final segundos = now.difference(lastSuccess).inSeconds;
    final minutos = (segundos / 60).ceil();
    return minutos < 1 ? 1 : minutos;
  }

  static String text(DateTime lastSuccess, DateTime now) {
    final local = lastSuccess.toLocal();
    String dois(int valor) => valor.toString().padLeft(2, '0');
    final hora = '${dois(local.hour)}:${dois(local.minute)}:${dois(local.second)}';
    return 'Dados de $hora — sem atualização há ${minutesSince(lastSuccess, now)} min';
  }

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        container: true,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AdminColors.surfaceRaised,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AdminColors.overdueOnSurface),
          ),
          child: Row(
            children: [
              const Icon(Icons.update_disabled, color: AdminColors.overdueOnSurface, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text(lastSuccess, now),
                  style: const TextStyle(color: AdminColors.overdueOnSurface, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      );
}

/// O selo, só quando o [MonitoringController] diz que o dado está velho.
/// Com o dado em dia não ocupa espaço nenhum.
class MonitoringStaleBadge extends StatelessWidget {
  const MonitoringStaleBadge(this.monitoring, {super.key});

  final MonitoringController monitoring;

  @override
  Widget build(BuildContext context) {
    final ultimo = monitoring.lastSuccess;
    if (!monitoring.stale || ultimo == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: StaleBadge(lastSuccess: ultimo, now: monitoring.now()),
    );
  }
}
