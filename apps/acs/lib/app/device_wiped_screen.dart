import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

/// Tela final da limpeza remota pedida pela coordenação (#81).
///
/// Aparece no lugar de tudo (a pilha inteira sai), e o [AppLockGate] não vale
/// para ela: não há dado nenhum para proteger, e o bloqueio por digital pediria
/// para "desbloquear" um aparelho que já não tem sessão. Quem tira o gate é o
/// `SinalAcsApp` enquanto esta tela está à vista.
///
/// INV-03: os alertas não foram descartados; continuam `pending` no servidor,
/// com a equipe da UBS.
class DeviceWipedScreen extends StatelessWidget {
  const DeviceWipedScreen({super.key, required this.pendingConfirm, required this.onLoginAgain});

  /// `true` enquanto o diário está em `erased`: o aparelho está limpo, mas o
  /// servidor ainda não recebeu a confirmação.
  final ValueListenable<bool> pendingConfirm;

  /// "Entrar de novo": volta a um login novo (com outro id da instalação).
  final VoidCallback onLoginAgain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Semantics(
            key: const Key('device_wiped'),
            liveRegion: true,
            container: true,
            // Coluna rolável, e não `ListView`: com fonte grande a linha da
            // confirmação pendente ficaria fora da área construída.
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.phonelink_erase, size: 48, color: theme.colorScheme.onSurface),
                  const SizedBox(height: 16),
                  Text('Aparelho limpo pela coordenação', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 12),
                  const Text(
                    'Os dados do SinalACS deste aparelho foram apagados a pedido da coordenação da UBS, '
                    'inclusive as visitas que ainda não tinham sido enviadas. Os alertas continuam com a equipe da UBS.',
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: pendingConfirm,
                    builder: (context, pending, _) => pending
                        ? Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Semantics(
                              liveRegion: true,
                              child: const Text(
                                'A confirmação ainda não chegou ao servidor; será enviada quando houver conexão.',
                                key: Key('device_wiped_pending_confirm'),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    key: const Key('device_wiped_login'),
                    style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
                    onPressed: onLoginAgain,
                    child: const Text('Entrar de novo'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
