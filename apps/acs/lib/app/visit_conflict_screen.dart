import 'package:flutter/material.dart';
import 'package:sinalacs_acs/app/acs_theme.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';

/// Opções de "Status do atendimento", as mesmas do registro da visita.
const visitOutcomeOptions = ['Realizada com sucesso', 'Paciente ausente', 'Recusou atendimento'];

/// `dd/MM/yyyy HH:mm`, na hora local do aparelho.
String formatVisitDateTime(DateTime value) {
  final local = value.toLocal();
  String dois(int n) => n.toString().padLeft(2, '0');
  return '${dois(local.day)}/${dois(local.month)}/${local.year} ${dois(local.hour)}:${dois(local.minute)}';
}

/// Rótulo do paciente montado na tela, nunca gravado: o disco guarda só o
/// UUID (LGPD-RF01), como no registro da visita.
String _patientLabel(String patientId) => 'Paciente ${patientId.length >= 8 ? patientId.substring(0, 8) : patientId}';

/// Mostra uma mensagem, substituindo a anterior em vez de enfileirar.
void _showMessage(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Visitas em conflito com o servidor (#79): uma linha por visita, que abre a
/// comparação. Volta ao registro pelo botão de voltar, inclusive vazia.
class VisitConflictListScreen extends StatefulWidget {
  const VisitConflictListScreen({super.key, required this.queue});

  final OfflineVisitQueue queue;

  @override
  State<VisitConflictListScreen> createState() => _VisitConflictListScreenState();
}

class _VisitConflictListScreenState extends State<VisitConflictListScreen> {
  Future<void> _open(OfflineVisitRecord visit) async {
    final message = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => VisitConflictCompareScreen(queue: widget.queue, localId: visit.localId),
      ),
    );
    if (!mounted) return;
    setState(() {});
    if (message != null) _showMessage(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final conflicts = widget.queue.conflictVisits;
    return Scaffold(
      appBar: AppBar(title: const Text('Visitas em conflito')),
      body: conflicts.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  key: Key('conflict_list_empty'),
                  'Nenhuma visita em conflito.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'O servidor tem outra versão destas visitas. Abra cada uma para '
                  'comparar e escolher qual vale.',
                ),
                const SizedBox(height: 12),
                for (final visit in conflicts)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      key: Key('conflict_item_${visit.localId}'),
                      minVerticalPadding: 12,
                      title: Text(_patientLabel(visit.patientId)),
                      subtitle: Text('Registrada em ${formatVisitDateTime(visit.createdAt)}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(visit),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Comparação lado a lado de uma visita em conflito e a decisão do ACS (#79):
/// manter a do aparelho, editar e enviar, ou manter a do servidor.
///
/// Sai da tela (devolvendo a mensagem a quem abriu) quando a visita deixa de
/// estar em conflito; fica quando o servidor mudou de novo ou a rede falhou.
class VisitConflictCompareScreen extends StatefulWidget {
  const VisitConflictCompareScreen({super.key, required this.queue, required this.localId});

  final OfflineVisitQueue queue;
  final String localId;

  @override
  State<VisitConflictCompareScreen> createState() => _VisitConflictCompareScreenState();
}

class _VisitConflictCompareScreenState extends State<VisitConflictCompareScreen> {
  /// Trava todas as ações enquanto uma chamada está em voo (sem duplo envio).
  bool _busy = false;
  String? _status;
  bool _editing = false;
  String? _editOutcome;
  final _editNotes = TextEditingController();

  @override
  void dispose() {
    _editNotes.dispose();
    super.dispose();
  }

  OfflineVisitRecord? get _visit {
    for (final visit in widget.queue.conflictVisits) {
      if (visit.localId == widget.localId) return visit;
    }
    return null;
  }

  /// Volta para a lista com [message]; aberta sem lista por baixo, mostra aqui.
  void _leave(String message) {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop(message);
    } else {
      setState(() {
        _busy = false;
        _status = message;
      });
    }
  }

  Future<void> _keepLocal({String? outcome, String? notes}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    SyncOutcome result;
    try {
      result = await widget.queue.resolveKeepLocal(widget.localId, outcome: outcome, notes: notes);
    } catch (error) {
      result = SyncOutcome(kind: SyncOutcomeKind.error, processed: 0, message: '$error');
    }
    if (!mounted) return;
    switch (result.kind) {
      case SyncOutcomeKind.synced:
        _leave('Versão do aparelho enviada ao servidor.');
      case SyncOutcomeKind.rejected:
        _leave('O servidor recusou esta visita: ${result.message ?? 'motivo não informado.'}');
      case SyncOutcomeKind.conflict:
        setState(() {
          _busy = false;
          _status = 'A visita mudou de novo no servidor. Compare outra vez antes de decidir.';
        });
      case SyncOutcomeKind.error:
      case SyncOutcomeKind.empty:
        setState(() {
          _busy = false;
          _status = result.message ?? 'Não foi possível enviar. A visita continua neste aparelho.';
        });
    }
  }

  void _startEditing(OfflineVisitRecord visit) {
    setState(() {
      if (!_editing) {
        _editOutcome = visitOutcomeOptions.contains(visit.outcome) ? visit.outcome : null;
        _editNotes.text = visit.notes;
      }
      _editing = true;
    });
  }

  Future<void> _sendEdited() => _keepLocal(outcome: _editOutcome, notes: _editNotes.text.trim());

  /// "Manter a do servidor" (D4): só local, atrás de confirmação destrutiva.
  Future<void> _keepServer() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        scrollable: true,
        title: const Text('Descartar a versão deste aparelho?'),
        content: const Text(
          'A visita registrada neste aparelho será apagada e a do servidor continua valendo. '
          'Isso não pode ser desfeito.',
        ),
        actions: [
          TextButton(
            key: const Key('cancel_keep_server'),
            style: TextButton.styleFrom(minimumSize: const Size(48, 52)),
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            key: const Key('confirm_keep_server'),
            style: TextButton.styleFrom(minimumSize: const Size(48, 52)),
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(
              'Descartar a minha',
              style: TextStyle(color: dialog.acsRisk.redOnSurface, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _busy) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    await widget.queue.resolveKeepServer(widget.localId);
    if (!mounted) return;
    _leave('A versão deste aparelho foi descartada. A do servidor continua valendo.');
  }

  @override
  Widget build(BuildContext context) {
    final visit = _visit;
    final status = _status;
    final statusWidget = status == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Semantics(
              key: const Key('conflict_status'),
              liveRegion: true,
              child: Text(
                status,
                style: TextStyle(color: context.acsRisk.accentOnSurface, fontWeight: FontWeight.bold),
              ),
            ),
          );

    return Scaffold(
      appBar: AppBar(title: const Text('Comparar versões')),
      // Rolagem sem construção preguiçosa: a tela é curta, e as ações têm de
      // existir na árvore mesmo abaixo da dobra (leitor de tela, testes).
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: visit == null
              ? [
                  const Text('Esta visita não está mais em conflito neste aparelho.'),
                  if (statusWidget != null) statusWidget,
                ]
              : [
                  Text(
                    _patientLabel(visit.patientId),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text('Registrada em ${formatVisitDateTime(visit.createdAt)}'),
                  const SizedBox(height: 8),
                  const Text(
                    'Esta visita foi alterada no servidor depois de registrada aqui. '
                    'Compare as duas versões e escolha qual vale.',
                  ),
                  const SizedBox(height: 16),
                  _panels(context, visit),
                  if (statusWidget != null) statusWidget,
                  const SizedBox(height: 20),
                  ..._actions(context, visit),
                ],
        ),
      ),
    );
  }

  Widget _panels(BuildContext context, OfflineVisitRecord visit) {
    final server = visit.conflictServer;
    final localStatus = visit.outcome.isEmpty ? visit.status : visit.outcome;
    final localCompleted = formatVisitDateTime(visit.createdAt);
    final serverCompleted = server?.completedAt == null ? 'Sem registro' : formatVisitDateTime(server!.completedAt!);

    final local = _Panel(
      key: const Key('conflict_local'),
      title: 'Neste aparelho',
      rows: [
        _Row(label: 'Status do atendimento', value: localStatus),
        _Row(label: 'Observações', value: _notesLabel(visit.notes)),
        _Row(label: 'Concluída em', value: localCompleted),
      ],
    );
    final remote = _Panel(
      key: const Key('conflict_server'),
      title: 'No servidor (versão ${server?.version ?? visit.conflictServerVersion})',
      unavailable: server == null,
      rows: server == null
          ? const []
          : [
              _Row(
                label: 'Status do atendimento',
                value: server.status,
                diffKey: server.status.trim() == localStatus.trim() ? null : const Key('conflict_diff_status'),
              ),
              _Row(
                label: 'Observações',
                value: _notesLabel(server.notes),
                diffKey: server.notes.trim() == visit.notes.trim() ? null : const Key('conflict_diff_notes'),
              ),
              _Row(
                label: 'Concluída em',
                value: serverCompleted,
                diffKey: serverCompleted == localCompleted ? null : const Key('conflict_diff_completed'),
              ),
            ],
    );

    // Lado a lado só com largura de tablet; no celular, um embaixo do outro.
    if (MediaQuery.sizeOf(context).width >= 600) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: local),
          const SizedBox(width: 12),
          Expanded(child: remote),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [local, const SizedBox(height: 12), remote],
    );
  }

  static String _notesLabel(String notes) => notes.trim().isEmpty ? 'Sem observações' : notes;

  List<Widget> _actions(BuildContext context, OfflineVisitRecord visit) {
    const size = Size(48, 52);
    return [
      FilledButton.icon(
        key: const Key('conflict_keep_local'),
        onPressed: _busy ? null : () => _keepLocal(),
        style: FilledButton.styleFrom(minimumSize: size),
        icon: _busy
            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.phone_android),
        label: const Text('Manter a minha versão'),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        key: const Key('conflict_edit'),
        onPressed: _busy ? null : () => _startEditing(visit),
        style: OutlinedButton.styleFrom(minimumSize: size),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Editar e enviar'),
      ),
      if (_editing) ...[
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: const Key('conflict_edit_outcome'),
          isExpanded: true,
          initialValue: _editOutcome,
          decoration: const InputDecoration(labelText: 'Status do atendimento'),
          items: visitOutcomeOptions.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
          onChanged: _busy ? null : (v) => setState(() => _editOutcome = v),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('conflict_edit_notes'),
          controller: _editNotes,
          enabled: !_busy,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Observações de campo'),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const Key('conflict_send_edited'),
          onPressed: _busy || _editOutcome == null ? null : _sendEdited,
          style: FilledButton.styleFrom(minimumSize: size),
          icon: const Icon(Icons.cloud_upload_outlined),
          label: const Text('Enviar versão editada'),
        ),
      ],
      const SizedBox(height: 12),
      OutlinedButton.icon(
        key: const Key('conflict_keep_server'),
        onPressed: _busy ? null : _keepServer,
        style: OutlinedButton.styleFrom(minimumSize: size),
        icon: const Icon(Icons.cloud_done_outlined),
        label: const Text('Manter a do servidor'),
      ),
    ];
  }
}

class _Row {
  const _Row({required this.label, required this.value, this.diffKey});

  final String label;
  final String value;

  /// Não-nulo: o valor difere do outro painel; a chave marca a linha.
  final Key? diffKey;
}

class _Panel extends StatelessWidget {
  const _Panel({super.key, required this.title, required this.rows, this.unavailable = false});

  final String title;
  final List<_Row> rows;
  final bool unavailable;

  @override
  Widget build(BuildContext context) {
    final accent = context.acsRisk.accentOnSurface;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (unavailable) const Text('Conteúdo do servidor indisponível neste aparelho.'),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.label, style: TextStyle(color: muted)),
                    Text(row.value, style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (row.diffKey != null)
                      // Ícone + texto, não só cor (WCAG 1.4.1); cor operacional,
                      // nunca de risco clínico.
                      Semantics(
                        key: row.diffKey,
                        label: '${row.label} diferente entre aparelho e servidor',
                        container: true,
                        excludeSemantics: true,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.compare_arrows, size: 18, color: accent),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  'Diferente',
                                  style: TextStyle(color: accent, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
