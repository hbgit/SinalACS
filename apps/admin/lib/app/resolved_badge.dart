import 'package:flutter/material.dart';
import 'package:sinalacs_admin/app/escalate_alert_dialog.dart' show horaLocal;

/// Selo do alerta cujo atendimento o ACS concluiu (#76/#87). Ícone + texto,
/// nunca só cor — e sem cor clínica: verde é risco, não estado. Só é montado
/// com `resolvedAt`; uma linha `resolved` sem a hora mostra só o estado.
class ResolvedBadge extends StatelessWidget {
  const ResolvedBadge(this.resolvedAt, {super.key});

  final DateTime resolvedAt;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline, size: 18, color: Colors.white70),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'Concluído às ${horaLocal(resolvedAt)}',
              style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      );
}
