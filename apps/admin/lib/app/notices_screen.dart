/// Aba "Avisos" (#46): o histórico dos avisos às comunidades e, só para o
/// admin, a sub-aba de termos de uso.
///
/// A mensagem do aviso nunca é exibida aqui: o histórico só carrega o título.
library;

import 'package:flutter/material.dart';

import 'package:sinalacs_admin/app/admin_async_states.dart';
import 'package:sinalacs_admin/app/admin_theme.dart';
import 'package:sinalacs_admin/app/notice_form_dialog.dart';
import 'package:sinalacs_admin/core/data/admin_data_source.dart';

String noticeStatusLabel(NoticeStatus status) => switch (status) {
      NoticeStatus.pending => 'Agendado',
      NoticeStatus.sending => 'Enviando',
      NoticeStatus.sent => 'Enviado',
      NoticeStatus.unknown => 'Resultado desconhecido — confira antes de reenviar',
      NoticeStatus.failed => 'Falhou',
      NoticeStatus.cancelled => 'Cancelado',
    };

String noticeAudienceLabel(NoticeAudience audience) => switch (audience) {
      NoticeAudience.everyone => 'Todos',
      NoticeAudience.chronic => 'Só crônicos',
    };

IconData _noticeStatusIcon(NoticeStatus status) => switch (status) {
      NoticeStatus.pending => Icons.schedule,
      NoticeStatus.sending => Icons.send_outlined,
      NoticeStatus.sent => Icons.check_circle_outline,
      NoticeStatus.unknown => Icons.help_outline,
      NoticeStatus.failed => Icons.error_outline,
      NoticeStatus.cancelled => Icons.block,
    };

// Todas passam de 4,5:1 sobre surfaceRaised (ver comentário em admin_theme.dart).
Color _noticeStatusColor(NoticeStatus status) => switch (status) {
      NoticeStatus.pending || NoticeStatus.sending => AdminColors.accentOnSurface,
      NoticeStatus.sent => AdminColors.green,
      NoticeStatus.unknown => AdminColors.yellow,
      NoticeStatus.failed => AdminColors.redOnSurface,
      NoticeStatus.cancelled => Colors.white70,
    };

String _dois(int valor) => valor.toString().padLeft(2, '0');

String _dataHora(DateTime instante) {
  final l = instante.toLocal();
  return '${_dois(l.day)}/${_dois(l.month)}/${l.year} ${_dois(l.hour)}:${_dois(l.minute)}';
}

const _alvoMinimo = Size(48, 52);

class NoticesScreen extends StatelessWidget {
  const NoticesScreen({required this.dataSource, required this.role, this.now = DateTime.now, super.key});

  final AdminDataSource dataSource;

  /// 'coordinator' ou 'admin': só o admin vê a sub-aba de termos.
  final String role;
  final DateTime Function() now;

  @override
  Widget build(BuildContext context) {
    final admin = role == 'admin';
    return DefaultTabController(
      key: ValueKey(admin),
      length: admin ? 2 : 1,
      child: Column(
        children: [
          TabBar(
            tabs: [
              const Tab(key: Key('notices_tab_history'), text: 'Avisos'),
              if (admin) const Tab(key: Key('notices_tab_terms'), text: 'Termos'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _NoticeHistory(dataSource: dataSource, now: now),
                // provisório: a Task 3.5 troca por TermsPanel
                if (admin) const Center(child: Text('Termos')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoticeHistory extends StatefulWidget {
  const _NoticeHistory({required this.dataSource, required this.now});

  final AdminDataSource dataSource;
  final DateTime Function() now;

  @override
  State<_NoticeHistory> createState() => _NoticeHistoryState();
}

class _NoticeHistoryState extends State<_NoticeHistory> {
  late Future<List<NoticeHistoryItem>> _lista = _carregar();
  bool _cancelando = false;

  Future<List<NoticeHistoryItem>> _carregar() async {
    await widget.dataSource.recordAccess(actionType: 'view', resourceType: 'community_notices');
    return widget.dataSource.fetchNoticeHistory(limit: 50, offset: 0);
  }

  void _recarregar() => setState(() {
        _lista = _carregar();
      });

  void _mensagem(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> _novo() async {
    final agendou = await NoticeFormDialog.show(context, dataSource: widget.dataSource, now: widget.now);
    if (agendou != true || !mounted) return;
    _recarregar();
    _mensagem('Aviso agendado.');
  }

  Future<void> _cancelar(NoticeHistoryItem aviso) async {
    if (_cancelando) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: const Text('Cancelar aviso'),
        content: Text('Cancelar o aviso "${aviso.title}"? Ele não será enviado.'),
        actions: [
          TextButton(
            style: TextButton.styleFrom(minimumSize: _alvoMinimo),
            onPressed: () => Navigator.of(contexto).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            key: const Key('notice_cancel_confirm'),
            style: FilledButton.styleFrom(minimumSize: _alvoMinimo),
            onPressed: () => Navigator.of(contexto).pop(true),
            child: const Text('Cancelar aviso'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted || _cancelando) return;
    setState(() => _cancelando = true);
    try {
      await widget.dataSource.cancelScheduledNotice(aviso.id);
      _mensagem('Aviso cancelado.');
    } on AdminSessionExpired {
      if (mounted) AdminSessionScope.maybeOf(context)?.call();
    } on AdminValidationFailure catch (falha) {
      _mensagem(falha.message);
    } on AdminDataFailure catch (falha) {
      _mensagem(falha.message);
    } catch (_) {
      _mensagem('Não foi possível cancelar o aviso. Tente novamente.');
    } finally {
      if (mounted) {
        setState(() => _cancelando = false);
        _recarregar();
      }
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<NoticeHistoryItem>>(
        future: _lista,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return AdminAsyncError(error: snapshot.error, fallback: 'Não foi possível carregar os avisos.', onRetry: _recarregar);
          }
          final avisos = snapshot.data ?? const <NoticeHistoryItem>[];
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text('Avisos às comunidades', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  key: const Key('notice_new_button'),
                  style: FilledButton.styleFrom(minimumSize: _alvoMinimo),
                  onPressed: _novo,
                  icon: const Icon(Icons.add),
                  label: const Text('Novo aviso'),
                ),
              ),
              const SizedBox(height: 16),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Center(child: CircularProgressIndicator())
              else if (avisos.isEmpty)
                const Text('Nenhum aviso agendado ou enviado ainda.')
              else
                for (final aviso in avisos)
                  _CartaoDoAviso(
                    aviso: aviso,
                    ocupado: _cancelando,
                    onCancelar: () => _cancelar(aviso),
                  ),
            ],
          );
        },
      );
}

class _CartaoDoAviso extends StatelessWidget {
  const _CartaoDoAviso({required this.aviso, required this.ocupado, required this.onCancelar});

  final NoticeHistoryItem aviso;
  final bool ocupado;
  final VoidCallback onCancelar;

  @override
  Widget build(BuildContext context) {
    final cor = _noticeStatusColor(aviso.status);
    final recipients = aviso.recipients;
    final accepted = aviso.accepted;
    return Card(
      key: Key('notice_row_${aviso.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(aviso.title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('${aviso.microAreaName} • ${noticeAudienceLabel(aviso.audience)}'),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(_noticeStatusIcon(aviso.status), size: 18, color: cor),
                const SizedBox(width: 6),
                Flexible(child: Text(noticeStatusLabel(aviso.status), style: TextStyle(color: cor, fontWeight: FontWeight.bold))),
              ],
            ),
            const SizedBox(height: 4),
            Text('Agendado para ${_dataHora(aviso.scheduledFor)}'),
            if (recipients != null && accepted != null) Text('$accepted de $recipients pacientes'),
            if (aviso.failureReason != null) Text('Motivo: ${aviso.failureReason}'),
            Text('Criado por ${aviso.createdByLabel}'),
            if (aviso.status == NoticeStatus.pending) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                key: Key('notice_cancel_${aviso.id}'),
                style: OutlinedButton.styleFrom(minimumSize: _alvoMinimo),
                onPressed: ocupado ? null : onCancelar,
                child: const Text('Cancelar'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
