/// Formulário de nova versão de termos (#46): cria um rascunho.
///
/// Só se registra o anúncio (versão, resumo e vigência); o texto integral vai no
/// release do app do paciente. O servidor valida de novo.
library;

import 'package:flutter/material.dart';

import 'package:sinalacs_admin/app/admin_async_states.dart';
import 'package:sinalacs_admin/app/admin_theme.dart';
import 'package:sinalacs_admin/core/data/admin_data_source.dart';

const _alvoMinimo = Size(48, 52);

String _dois(int v) => v.toString().padLeft(2, '0');

/// 'dd/mm/aaaa'.
String formatarDataTermos(DateTime d) {
  final l = d.toLocal();
  return '${_dois(l.day)}/${_dois(l.month)}/${l.year}';
}

/// Primeira meia-noite local em ou após `agora + 15 dias`.
DateTime vigenciaMinimaDosTermos(DateTime agora) {
  final limite = agora.add(const Duration(days: 15));
  final meiaNoite = DateTime(limite.year, limite.month, limite.day);
  return meiaNoite.isBefore(limite) ? DateTime(limite.year, limite.month, limite.day + 1) : meiaNoite;
}

class TermsFormDialog extends StatefulWidget {
  const TermsFormDialog({required this.dataSource, required this.now, this.aoVencer, super.key});

  final AdminDataSource dataSource;
  final DateTime Function() now;

  /// Capturado de quem abre: a rota do diálogo fica fora do [AdminSessionScope].
  final VoidCallback? aoVencer;

  /// `true` quando o rascunho foi criado.
  static Future<bool?> show(
    BuildContext context, {
    required AdminDataSource dataSource,
    required DateTime Function() now,
  }) {
    final aoVencer = AdminSessionScope.maybeOf(context);
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TermsFormDialog(dataSource: dataSource, now: now, aoVencer: aoVencer),
    );
  }

  @override
  State<TermsFormDialog> createState() => _TermsFormDialogState();
}

class _TermsFormDialogState extends State<TermsFormDialog> {
  final _versao = TextEditingController();
  final _resumo = TextEditingController();
  late final DateTime _minima = vigenciaMinimaDosTermos(widget.now());
  late DateTime _vigencia = _minima;
  bool _enviando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _versao.addListener(_mudou);
    _resumo.addListener(_mudou);
  }

  @override
  void dispose() {
    _versao.dispose();
    _resumo.dispose();
    super.dispose();
  }

  void _mudou() => setState(() => _erro = null);

  bool get _preenchido => _versao.text.trim().isNotEmpty && _resumo.text.trim().isNotEmpty;

  Future<void> _escolherData() async {
    final data = await showDatePicker(
      context: context,
      initialDate: _vigencia,
      firstDate: _minima,
      lastDate: DateTime(_minima.year + 2, _minima.month, _minima.day),
    );
    if (data == null || !mounted) return;
    setState(() {
      _vigencia = DateTime(data.year, data.month, data.day);
      _erro = null;
    });
  }

  Future<void> _criar() async {
    // Guarda síncrona: dois toques chegam antes do próximo frame.
    if (_enviando || !_preenchido) return;
    _enviando = true;
    setState(() => _erro = null);
    final aoVencer = widget.aoVencer ?? AdminSessionScope.maybeOf(context);
    String? erro;
    var ok = false;
    try {
      await widget.dataSource.draftTermsVersion(
        version: _versao.text.trim(),
        summary: _resumo.text.trim(),
        effectiveFrom: _vigencia,
      );
      ok = true;
    } on AdminSessionExpired {
      aoVencer?.call();
    } on AdminValidationFailure catch (falha) {
      erro = falha.message;
    } on AdminDataFailure catch (falha) {
      erro = falha.message;
    } catch (_) {
      erro = 'Não foi possível criar o rascunho agora.';
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
          title: const Text('Nova versão dos termos'),
          // Título e corpo rolam juntos; só as ações ficam fixas. Sem isto, com
          // fonte a 200% em 320x568 o título e as ações sozinhos passam da altura.
          scrollable: true,
          content: SizedBox(
            width: 560,
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    key: const Key('terms_version'),
                    controller: _versao,
                    autofocus: true,
                    enabled: !_enviando,
                    decoration: const InputDecoration(labelText: 'Versão'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('terms_summary'),
                    controller: _resumo,
                    enabled: !_enviando,
                    maxLength: 280,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Resumo',
                      helperText: 'Resumo público exibido no cartão do paciente.',
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const Key('terms_date'),
                    style: OutlinedButton.styleFrom(minimumSize: _alvoMinimo),
                    onPressed: _enviando ? null : _escolherData,
                    icon: const Icon(Icons.calendar_today),
                    label: Text('Vigora em ${formatarDataTermos(_vigencia)}'),
                  ),
                  const SizedBox(height: 8),
                  const Text('A vigência exige 15 dias de antecedência para publicar.'),
                  if (_erro != null) ...[
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline, size: 18, color: AdminColors.redOnSurface),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(_erro!, style: const TextStyle(color: AdminColors.redOnSurface, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
            ),
          ),
          actions: [
            TextButton(
              key: const Key('terms_form_cancel'),
              style: TextButton.styleFrom(minimumSize: _alvoMinimo),
              onPressed: _enviando ? null : () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              key: const Key('terms_submit'),
              style: FilledButton.styleFrom(minimumSize: _alvoMinimo),
              onPressed: _enviando || !_preenchido ? null : _criar,
              child: _enviando
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: 'Criando'))
                  : const Text('Criar rascunho'),
            ),
          ],
        ),
      );
}
