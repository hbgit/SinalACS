import 'package:flutter/material.dart';
import 'package:sinalacs_admin/app/admin_layout.dart';
import 'package:sinalacs_admin/app/admin_theme.dart';

class AdminHeader extends StatelessWidget implements PreferredSizeWidget {
  const AdminHeader(this.eyebrow, this.title, {required this.height, super.key});

  final String eyebrow;
  final String title;

  /// Calculada por quem monta o Scaffold, via [adminHeaderHeight] — ver o
  /// porquê lá: `preferredSize` não tem acesso ao `BuildContext`.
  final double height;

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    // O selo é informação, não controle. Em tela estreita ele disputa espaço
    // com duas linhas de título num AppBar, então vira ícone — mantendo o
    // rótulo para leitores de tela, que é o que de fato carrega o significado.
    final estreito = MediaQuery.sizeOf(context).width < AdminBreakpoints.stacked;
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            eyebrow.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, color: AdminColors.accentOnSurface, fontWeight: FontWeight.bold),
          ),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: estreito
              ? Tooltip(
                  message: 'Acesso auditado',
                  child: Semantics(
                    label: 'Acesso auditado',
                    child: const Icon(key: Key('admin_audit_badge'), Icons.verified_user_outlined),
                  ),
                )
              : const Chip(key: Key('admin_audit_badge'), label: Text('Acesso auditado')),
        ),
      ],
    );
  }
}
