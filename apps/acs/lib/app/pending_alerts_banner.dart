import 'package:flutter/material.dart';

import 'acs_theme.dart';

/// Aviso fixo no topo da reautenticação (sessão vencida ou bloqueio): o painel
/// com a fila de alertas fica por baixo da rota opaca, e um alerta vermelho que
/// chega ali não pode esperar o novo login para ser notado.
class PendingAlertsBanner extends StatelessWidget {
  const PendingAlertsBanner({super.key, required this.listenable, required this.count});

  final Listenable listenable;
  final int Function() count;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: listenable,
        builder: (context, _) {
          final n = count();
          if (n <= 0) return const SizedBox.shrink();
          final texto = n == 1
              ? '1 alerta vermelho aguardando. Entre para ver.'
              : '$n alertas vermelhos aguardando. Entre para ver.';
          return Material(
            key: const Key('reauth_pending_alerts'),
            // `cardTheme.color` (surfaceRaised), não `cardColor`: é a superfície onde
            // `contrast_tokens_test.dart` mede `redOnSurface` sobre card.
            color: Theme.of(context).cardTheme.color,
            child: Semantics(
              liveRegion: true,
              label: texto,
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  texto,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.acsRisk.redOnSurface, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          );
        },
      );
}
