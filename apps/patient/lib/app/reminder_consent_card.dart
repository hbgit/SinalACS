import 'package:flutter/material.dart';

/// Pergunta, no topo de "Lembretes", se a pessoa autoriza lembretes neste
/// aparelho (#136). Aparece só quando não há decisão local gravada — banco
/// local recomeçado por chave perdida ou "Apagar e recomeçar".
///
/// Não há "Agora não": enquanto a pessoa não escolhe, nada é gravado e nenhum
/// lembrete é agendado. Os textos usam as cores normais do tema; cor clínica
/// não entra aqui.
class ReminderConsentCard extends StatefulWidget {
  const ReminderConsentCard({required this.onDecision, super.key});

  /// Recebe a escolha. O cartão fica desabilitado enquanto ela não termina,
  /// para um segundo toque não virar segunda decisão.
  final Future<void> Function(bool granted) onDecision;

  @override
  State<ReminderConsentCard> createState() => _ReminderConsentCardState();
}

class _ReminderConsentCardState extends State<ReminderConsentCard> {
  bool _busy = false;

  Future<void> _decide(bool granted) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onDecision(granted);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const buttonSize = Size(64, 48);
    final theme = Theme.of(context);
    return Card(
      key: const Key('reminder_consent_card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              liveRegion: true,
              header: true,
              child: Text(
                'Autorizar lembretes neste aparelho?',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton(
                  key: const Key('reminder_consent_grant'),
                  style: FilledButton.styleFrom(minimumSize: buttonSize),
                  onPressed: _busy ? null : () => _decide(true),
                  child: const Text('Autorizo'),
                ),
                OutlinedButton(
                  key: const Key('reminder_consent_deny'),
                  style: OutlinedButton.styleFrom(minimumSize: buttonSize),
                  onPressed: _busy ? null : () => _decide(false),
                  child: const Text('Não autorizo'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
