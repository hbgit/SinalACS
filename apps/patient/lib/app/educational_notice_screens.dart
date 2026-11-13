import 'package:flutter/material.dart';
import 'package:sinalacs_patient/app/local_protection_notice.dart';
import 'package:sinalacs_patient/core/education/educational_library.dart';
import 'package:sinalacs_patient/core/legal/educational_notice.dart';

/// Primeira abertura (RF21, C-02): o aviso educativo curto, e o app só segue
/// depois de "Entendi".
///
/// Fica no `home` do `MaterialApp`, **antes** do login: nada do resto do app é
/// montado enquanto o aviso não for confirmado. Confirmado uma vez, o aviso não
/// volta, salvo se a versão do texto canônico mudar
/// ([educationalNoticeVersion]).
class EducationalNoticeGate extends StatefulWidget {
  const EducationalNoticeGate({super.key, required this.store, required this.child});

  final EducationalNoticeStore store;
  final Widget child;

  @override
  State<EducationalNoticeGate> createState() => _EducationalNoticeGateState();
}

class _EducationalNoticeGateState extends State<EducationalNoticeGate> {
  /// `null` enquanto a confirmação é lida.
  late bool? _acknowledged = widget.store.knownAcknowledged;

  @override
  void initState() {
    super.initState();
    if (_acknowledged == null) {
      widget.store.isAcknowledged().then(
        (value) {
          if (mounted) setState(() => _acknowledged = value);
        },
        // Na dúvida, o aviso aparece.
        onError: (Object _) {
          if (mounted) setState(() => _acknowledged = false);
        },
      );
    }
  }

  Future<void> _confirm() async {
    setState(() => _acknowledged = true);
    try {
      await widget.store.acknowledge();
    } catch (_) {
      // Gravar falhou: segue nesta abertura, e o aviso volta na próxima.
    }
  }

  @override
  Widget build(BuildContext context) => switch (_acknowledged) {
        true => widget.child,
        false => FirstOpenNoticeScreen(onConfirm: _confirm),
        null => const Scaffold(
            key: Key('educational_notice_loading'),
            body: Center(child: CircularProgressIndicator()),
          ),
      };
}

/// Tela da primeira abertura com a versão curta do aviso educativo.
class FirstOpenNoticeScreen extends StatelessWidget {
  const FirstOpenNoticeScreen({super.key, required this.onConfirm});

  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      key: const Key('first_open_notice'),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.menu_book_outlined, size: 48, color: scheme.onSurfaceVariant),
                  const SizedBox(height: 16),
                  Semantics(
                    header: true,
                    child: const Text(
                      'Antes de começar',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    educationalNoticeShort,
                    key: const Key('educational_notice_short'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, color: scheme.onSurface),
                  ),
                  const SizedBox(height: 32),
                  FilledButton(
                    key: const Key('educational_notice_confirm'),
                    style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
                    onPressed: onConfirm,
                    child: const Text('Entendi'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    key: const Key('educational_notice_about'),
                    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AboutScreen()),
                    ),
                    child: const Text('Ler o aviso completo'),
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

/// Tela "Sobre" (RF21, C-02): a versão longa do aviso educativo, copiada
/// literalmente, e o limite da cifra local (#136), pelo mesmo
/// [LocalProtectionNotice] de "Lembretes" e "Meus dados" — o texto não é
/// repetido aqui.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      key: const Key('about_screen'),
      appBar: AppBar(title: const Text('Sobre o SinalACS')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Semantics(
              header: true,
              child: Text(
                'Aviso educativo',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: scheme.onSurface),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              educationalNoticeLong,
              key: const Key('educational_notice_long'),
              style: TextStyle(color: scheme.onSurface),
            ),
            const SizedBox(height: 24),
            const LocalProtectionNotice(),
            const SizedBox(height: 24),
            // C-03, RNF10: as duas licenças, separadas.
            Semantics(
              header: true,
              child: Text(
                'Licenças',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: scheme.onSurface),
              ),
            ),
            const SizedBox(height: 8),
            Text(codeLicenseLabel, key: const Key('about_code_license'), style: TextStyle(color: scheme.onSurface)),
            const SizedBox(height: 4),
            Text(
              contentLicenseLabel,
              key: const Key('about_content_license'),
              style: TextStyle(color: scheme.onSurface),
            ),
            const SizedBox(height: 4),
            Text('Atribuição: $contentAttribution', style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
