/// Estados assíncronos compartilhados pelas telas do backoffice. Saíram de
/// `app.dart` (eram privados) quando a tela de pedidos do titular (#42) ganhou
/// arquivo próprio e passou a precisar dos mesmos erro/retry e sessão vencida.
library;

import 'package:flutter/material.dart';

import 'package:sinalacs_admin/core/data/admin_data_source.dart';

/// Estado de erro compartilhado pelas telas assíncronas, com retry.
///
/// Sem isso, um `FutureBuilder` que falha fica com `hasData == false` para
/// sempre (spinner infinito) ou, pior, cai no mesmo ramo de "vazio" que os
/// dados realmente vazios — escondendo uma falha de rede/backend como se
/// não houvesse nada para mostrar (achado da revisão do Copilot no PR).
class AdminAsyncError extends StatelessWidget {
  const AdminAsyncError({required this.error, required this.fallback, required this.onRetry, super.key});

  /// O que o `FutureBuilder` capturou. [AdminDataFailure] traz o texto próprio
  /// da falha; [AdminSessionExpired] leva ao login em vez de oferecer retry.
  final Object? error;

  /// Texto da tela quando a falha não traz mensagem própria.
  final String fallback;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (error is AdminSessionExpired) {
      // Navegar durante o build não pode: adia para depois do frame.
      final aoVencer = AdminSessionScope.maybeOf(context);
      WidgetsBinding.instance.addPostFrameCallback((_) => aoVencer?.call());
      return const Center(child: CircularProgressIndicator());
    }
    final message = error is AdminDataFailure ? (error! as AdminDataFailure).message : fallback;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 32, color: Colors.white70),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Tentar novamente')),
          ],
        ),
      ),
    );
  }
}

/// Entrega às telas a ação de encerrar a sessão vencida (volta ao login), sem
/// passar um callback por cada construtor.
class AdminSessionScope extends InheritedWidget {
  const AdminSessionScope({required this.aoVencer, required super.child, super.key});

  final VoidCallback aoVencer;

  static VoidCallback? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AdminSessionScope>()?.aoVencer;

  @override
  bool updateShouldNotify(AdminSessionScope old) => false;
}
