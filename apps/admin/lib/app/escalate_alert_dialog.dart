import 'package:flutter/material.dart';
import 'package:sinalacs_admin/app/admin_accounts.dart';
import 'package:sinalacs_admin/app/admin_async_states.dart';
import 'package:sinalacs_admin/app/admin_theme.dart';
import 'package:sinalacs_admin/core/data/admin_data_source.dart';

/// "HH:mm" na hora local de [instante].
String horaLocal(DateTime instante) {
  final local = instante.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

/// "#A18F" a partir de "Paciente #A18F": o rótulo minimizado, nunca nome/CPF.
String _etiqueta(String patientLabel) => patientLabel.replaceFirst(RegExp(r'^Paciente\s+'), '');

/// Selo do alerta que o backoffice já escalonou. O alerta segue pendente e
/// listado: escalonar não o confirma nem o encerra. Ícone + texto, nunca só cor.
class EscalatedBadge extends StatelessWidget {
  const EscalatedBadge(this.escalatedAt, {super.key});

  final DateTime escalatedAt;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.trending_up, size: 18, color: Colors.white70),
          const SizedBox(width: 6),
          Flexible(child: Text('Escalonado às ${horaLocal(escalatedAt)}', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold))),
        ],
      );
}

/// Botão "Escalonar" da linha de um alerta vencido (#44). Só é montado quando o
/// SERVIDOR diz `overdue`; o dado é a única fonte do vencimento.
///
/// Abre a confirmação com o motivo (conjunto fechado). Depois do resultado
/// chama [onChanged] com `true` quando a lista precisa ser relida (sucesso, já
/// escalonado ou estado que mudou no servidor).
class EscalateAlertButton extends StatefulWidget {
  const EscalateAlertButton({required this.alert, required this.dataSource, required this.onChanged, super.key});

  final AlertSummary alert;
  final AdminDataSource dataSource;
  final VoidCallback onChanged;

  @override
  State<EscalateAlertButton> createState() => _EscalateAlertButtonState();
}

class _EscalateAlertButtonState extends State<EscalateAlertButton> {
  bool _aberto = false;

  Future<void> _abrir() async {
    if (_aberto) return;
    _aberto = true;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final aoVencer = AdminSessionScope.maybeOf(context);
    final resultado = await showDialog<_Resultado>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EscalateDialog(alert: widget.alert, dataSource: widget.dataSource),
    );
    _aberto = false;
    if (resultado == null) return;
    final erro = resultado.erro;
    if (erro is AdminSessionExpired) {
      aoVencer?.call();
      return;
    }
    if (erro != null) {
      messenger?.showSnackBar(SnackBar(content: Text(erro is AdminDataFailure ? erro.message : mensagemDaFalhaEscrita(erro))));
      // O estado pode ter mudado (já confirmado, não encontrado): relê.
      if (erro is AdminValidationFailure) widget.onChanged();
      return;
    }
    final saida = resultado.outcome!;
    messenger?.showSnackBar(SnackBar(
      content: Text(saida.alreadyEscalated
          ? 'Este alerta já havia sido escalonado às ${horaLocal(saida.escalatedAt)}.'
          : 'Escalonamento registrado. O alerta segue pendente até a confirmação.'),
    ));
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        button: true,
        label: 'Escalonar alerta ${_etiqueta(widget.alert.patientLabel)}',
        excludeSemantics: true,
        onTap: _abrir,
        child: OutlinedButton.icon(
          onPressed: _abrir,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 48),
            foregroundColor: AdminColors.overdueOnSurface,
            side: const BorderSide(color: AdminColors.overdueOnSurface),
          ),
          icon: const Icon(Icons.trending_up),
          label: const Text('Escalonar'),
        ),
      );
}

/// O que o diálogo devolve: o resultado do servidor ou o erro dele.
class _Resultado {
  const _Resultado.ok(EscalationOutcome this.outcome) : erro = null;
  const _Resultado.falha(Object this.erro) : outcome = null;

  final EscalationOutcome? outcome;
  final Object? erro;
}

class _EscalateDialog extends StatefulWidget {
  const _EscalateDialog({required this.alert, required this.dataSource});

  final AlertSummary alert;
  final AdminDataSource dataSource;

  @override
  State<_EscalateDialog> createState() => _EscalateDialogState();
}

class _EscalateDialogState extends State<_EscalateDialog> {
  EscalationReasonCode? _motivo;
  bool _enviando = false;

  Future<void> _confirmar() async {
    final motivo = _motivo;
    // Guarda síncrona: dois toques seguidos chegam antes do próximo frame.
    if (motivo == null || _enviando) return;
    _enviando = true;
    setState(() {});
    _Resultado resultado;
    try {
      resultado = _Resultado.ok(await widget.dataSource.escalateAlert(widget.alert.id, motivo));
    } catch (erro) {
      resultado = _Resultado.falha(erro);
    }
    if (mounted) Navigator.of(context).pop(resultado);
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_enviando,
        child: AlertDialog(
          title: Text('Escalonar alerta ${_etiqueta(widget.alert.patientLabel)}?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'O alerta não será encerrado nem silenciado: continua pendente '
                  'até a confirmação real do ACS. O escalonamento só registra que a coordenação agiu.',
                ),
                const SizedBox(height: 12),
                const Text('Motivo', style: TextStyle(fontWeight: FontWeight.bold)),
                RadioGroup<EscalationReasonCode>(
                  groupValue: _motivo,
                  onChanged: (valor) {
                    if (!_enviando) setState(() => _motivo = valor);
                  },
                  child: Column(
                    children: [
                      for (final motivo in EscalationReasonCode.values)
                        RadioListTile<EscalationReasonCode>(
                          value: motivo,
                          contentPadding: EdgeInsets.zero,
                          title: Text(motivo.label),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: _enviando ? null : () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: _motivo == null || _enviando ? null : _confirmar,
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              child: _enviando
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: 'Escalonando'))
                  : const Text('Confirmar escalonamento'),
            ),
          ],
        ),
      );
}
