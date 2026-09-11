import 'package:flutter/widgets.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';

/// Disponibiliza o [AcsBackend] para a árvore de widgets.
///
/// Existe para que as telas não construam o próprio cliente: em teste, injeta-se
/// um duplo; em execução, o [BackendClient] real.
class BackendScope extends InheritedWidget {
  const BackendScope({
    required this.backend,
    required super.child,
    super.key,
  });

  final AcsBackend backend;

  static AcsBackend of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<BackendScope>();
    assert(scope != null, 'Nenhum BackendScope acima deste widget.');
    return scope!.backend;
  }

  @override
  bool updateShouldNotify(BackendScope oldWidget) =>
      backend != oldWidget.backend;
}
