/// Formulário de agendamento de aviso (#46).
///
/// O texto digitado nunca vai para log nem para a trilha de auditoria; o
/// servidor valida de novo e é a fonte da verdade.
library;

import 'package:flutter/material.dart';

import 'package:sinalacs_admin/app/admin_async_states.dart';
import 'package:sinalacs_admin/app/admin_theme.dart';
import 'package:sinalacs_admin/core/data/admin_data_source.dart';

const _alvoMinimo = Size(48, 52);
const _erroDeHorario = 'O horário do aviso deve ser pelo menos 1 minuto à frente.';

String _dois(int v) => v.toString().padLeft(2, '0');

/// 'dd/mm/aaaa HH:mm'.
String _dataHora(DateTime d) => '${_dois(d.day)}/${_dois(d.month)}/${d.year} ${_dois(d.hour)}:${_dois(d.minute)}';

class NoticeFormDialog extends StatefulWidget {
  const NoticeFormDialog({required this.dataSource, required this.now, this.aoVencer, super.key});

  final AdminDataSource dataSource;
  final DateTime Function() now;

  /// Capturado de quem abre: a rota do diálogo fica fora do [AdminSessionScope].
  final VoidCallback? aoVencer;

  /// `true` quando o aviso foi agendado.
  static Future<bool?> show(
    BuildContext context, {
    required AdminDataSource dataSource,
    required DateTime Function() now,
  }) {
    final aoVencer = AdminSessionScope.maybeOf(context);
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => NoticeFormDialog(dataSource: dataSource, now: now, aoVencer: aoVencer),
    );
  }

  @override
  State<NoticeFormDialog> createState() => _NoticeFormDialogState();
}

class _NoticeFormDialogState extends State<NoticeFormDialog> {
  final _titulo = TextEditingController();
  final _mensagem = TextEditingController();
  late final Future<List<MicroAreaSummary>> _areas = widget.dataSource.fetchMicroAreas();
  String? _areaId;
  NoticeAudience _publico = NoticeAudience.everyone;
  late DateTime _quando = _padrao();
  bool _enviando = false;
  String? _erro;

  DateTime _padrao() {
    final base = widget.now().add(const Duration(hours: 1));
    final truncado = DateTime(base.year, base.month, base.day, base.hour, base.minute);
    return truncado.isBefore(base) ? truncado.add(const Duration(minutes: 1)) : truncado;
  }

  @override
  void initState() {
    super.initState();
    _titulo.addListener(_mudou);
    _mensagem.addListener(_mudou);
  }

  @override
  void dispose() {
    _titulo.dispose();
    _mensagem.dispose();
    super.dispose();
  }

  void _mudou() => setState(() => _erro = null);

  bool get _preenchido => _titulo.text.trim().isNotEmpty && _mensagem.text.trim().isNotEmpty && _areaId != null;

  Future<void> _escolherData() async {
    final hoje = widget.now();
    final data = await showDatePicker(
      context: context,
      initialDate: _quando.isBefore(hoje) ? hoje : _quando,
      firstDate: DateTime(hoje.year, hoje.month, hoje.day),
      lastDate: DateTime(hoje.year + 1, hoje.month, hoje.day),
    );
    if (data == null || !mounted) return;
    setState(() {
      _quando = DateTime(data.year, data.month, data.day, _quando.hour, _quando.minute);
      _erro = null;
    });
  }

  Future<void> _escolherHora() async {
    final hora = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_quando));
    if (hora == null || !mounted) return;
    setState(() {
      _quando = DateTime(_quando.year, _quando.month, _quando.day, hora.hour, hora.minute);
      _erro = null;
    });
  }

  Future<void> _agendar() async {
    // Guarda síncrona: dois toques chegam antes do próximo frame.
    if (_enviando || !_preenchido) return;
    if (_quando.isBefore(widget.now().add(const Duration(minutes: 1)))) {
      setState(() => _erro = _erroDeHorario);
      return;
    }
    _enviando = true;
    setState(() => _erro = null);
    final aoVencer = widget.aoVencer ?? AdminSessionScope.maybeOf(context);
    String? erro;
    var ok = false;
    try {
      await widget.dataSource.scheduleNotice(
        microAreaId: _areaId!,
        audience: _publico,
        title: _titulo.text.trim(),
        message: _mensagem.text.trim(),
        scheduledFor: _quando,
      );
      ok = true;
    } on AdminSessionExpired {
      aoVencer?.call();
    } on AdminValidationFailure catch (falha) {
      erro = falha.message;
    } on AdminDataFailure catch (falha) {
      erro = falha.message;
    } catch (_) {
      erro = 'Não foi possível agendar o aviso agora.';
    }
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _enviando = false;
      _erro = erro;
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_enviando,
        child: AlertDialog(
          title: const Text('Novo aviso'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: FutureBuilder<List<MicroAreaSummary>>(
                future: _areas,
                builder: (context, snapshot) => _corpo(context, snapshot),
              ),
            ),
          ),
          actions: [
            TextButton(
              key: const Key('notice_form_cancel'),
              style: TextButton.styleFrom(minimumSize: _alvoMinimo),
              onPressed: _enviando ? null : () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              key: const Key('notice_submit'),
              style: FilledButton.styleFrom(minimumSize: _alvoMinimo),
              onPressed: _enviando || !_preenchido ? null : _agendar,
              child: _enviando
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: 'Agendando'))
                  : const Text('Agendar'),
            ),
          ],
        ),
      );

  Widget _corpo(BuildContext context, AsyncSnapshot<List<MicroAreaSummary>> snapshot) {
    final areas = snapshot.data;
    if (snapshot.hasError) {
      return const Text('Não foi possível carregar as microáreas.');
    }
    if (areas == null) {
      return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
    }
    if (areas.isEmpty) {
      return const Text('Nenhuma microárea disponível.');
    }
    if (_areaId == null || !areas.any((a) => a.id == _areaId)) {
      // Pré-seleciona a primeira; sem setState: o botão relê no próximo frame.
      _areaId = areas.first.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          key: const Key('notice_area'),
          initialValue: _areaId,
          // Sem isto o item pede a largura natural do nome e estoura o diálogo em celular.
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Microárea'),
          items: [for (final a in areas) DropdownMenuItem(value: a.id, child: Text(a.name))],
          onChanged: _enviando ? null : (v) => setState(() => _areaId = v),
        ),
        const SizedBox(height: 16),
        const Text('Público', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        SegmentedButton<NoticeAudience>(
          key: const Key('notice_audience'),
          showSelectedIcon: true,
          style: SegmentedButton.styleFrom(minimumSize: _alvoMinimo),
          segments: const [
            ButtonSegment(value: NoticeAudience.everyone, label: Text('Todos')),
            ButtonSegment(value: NoticeAudience.chronic, label: Text('Só crônicos')),
          ],
          selected: {_publico},
          onSelectionChanged: _enviando ? null : (s) => setState(() => _publico = s.first),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('notice_title'),
          controller: _titulo,
          autofocus: true,
          enabled: !_enviando,
          maxLength: 60,
          decoration: const InputDecoration(labelText: 'Título'),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('notice_message'),
          controller: _mensagem,
          enabled: !_enviando,
          maxLength: 240,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'Mensagem'),
        ),
        const SizedBox(height: 8),
        Semantics(
          container: true,
          label: 'Envio em ${_dataHora(_quando)}',
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                key: const Key('notice_date'),
                style: OutlinedButton.styleFrom(minimumSize: _alvoMinimo),
                onPressed: _enviando ? null : _escolherData,
                icon: const Icon(Icons.calendar_today),
                label: Text('Data ${_dois(_quando.day)}/${_dois(_quando.month)}/${_quando.year}'),
              ),
              OutlinedButton.icon(
                key: const Key('notice_time'),
                style: OutlinedButton.styleFrom(minimumSize: _alvoMinimo),
                onPressed: _enviando ? null : _escolherHora,
                icon: const Icon(Icons.access_time),
                label: Text('Hora ${_dois(_quando.hour)}:${_dois(_quando.minute)}'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text('Envio em ${_dataHora(_quando)}'),
        const SizedBox(height: 8),
        const Text('O texto do aviso não é gravado na trilha de auditoria.'),
        if (_erro != null) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, size: 18, color: AdminColors.redOnSurface),
                const SizedBox(width: 6),
                Flexible(child: Text(_erro!, style: const TextStyle(color: AdminColors.redOnSurface, fontWeight: FontWeight.bold))),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
