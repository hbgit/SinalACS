/// Sub-aba "Termos" (#46): rascunho, revisão jurídica e publicação.
///
/// Só se registra o anúncio da versão; o texto integral vai no release do app.
/// Publicar exige revisão jurídica e 15 dias de antecedência; o servidor é a
/// fonte da verdade e esta tela apenas antecipa as regras.
library;

import 'package:flutter/material.dart';

import 'package:sinalacs_admin/app/admin_async_states.dart';
import 'package:sinalacs_admin/app/admin_theme.dart';
import 'package:sinalacs_admin/app/terms_form_dialog.dart';
import 'package:sinalacs_admin/core/data/admin_data_source.dart';

const _alvoMinimo = Size(48, 52);

String _estadoRotulo(TermsVersionState s) => switch (s) {
      TermsVersionState.draft => 'Rascunho',
      TermsVersionState.reviewed => 'Revisada',
      TermsVersionState.published => 'Publicada',
    };

IconData _estadoIcone(TermsVersionState s) => switch (s) {
      TermsVersionState.draft => Icons.edit_note,
      TermsVersionState.reviewed => Icons.fact_check_outlined,
      TermsVersionState.published => Icons.check_circle_outline,
    };

Color _estadoCor(TermsVersionState s) => switch (s) {
      TermsVersionState.draft => AdminColors.yellow,
      TermsVersionState.reviewed => AdminColors.accentOnSurface,
      TermsVersionState.published => AdminColors.green,
    };

class TermsPanel extends StatefulWidget {
  const TermsPanel({required this.dataSource, required this.now, super.key});

  final AdminDataSource dataSource;
  final DateTime Function() now;

  @override
  State<TermsPanel> createState() => _TermsPanelState();
}

class _TermsPanelState extends State<TermsPanel> {
  late Future<List<TermsVersionSummary>> _lista = _carregar();
  final Set<String> _ocupados = {};

  Future<List<TermsVersionSummary>> _carregar() async {
    await widget.dataSource.recordAccess(actionType: 'view', resourceType: 'terms_versions');
    return widget.dataSource.fetchTermsVersions();
  }

  void _recarregar() => setState(() {
        _lista = _carregar();
      });

  void _mensagem(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> _nova() async {
    final criou = await TermsFormDialog.show(context, dataSource: widget.dataSource, now: widget.now);
    if (criou != true || !mounted) return;
    _recarregar();
    _mensagem('Rascunho criado.');
  }

  Future<bool> _confirmar({required String titulo, required String texto, required String rotulo, required Key chave}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: Text(titulo),
        content: Text(texto),
        actions: [
          TextButton(
            style: TextButton.styleFrom(minimumSize: _alvoMinimo),
            onPressed: () => Navigator.of(contexto).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            key: chave,
            style: FilledButton.styleFrom(minimumSize: _alvoMinimo),
            onPressed: () => Navigator.of(contexto).pop(true),
            child: Text(rotulo),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _executar(TermsVersionSummary termo, Future<void> Function() acao, String falhaGenerica) async {
    if (_ocupados.contains(termo.id)) return;
    setState(() => _ocupados.add(termo.id));
    try {
      await acao();
    } on AdminSessionExpired {
      if (mounted) AdminSessionScope.maybeOf(context)?.call();
    } on AdminValidationFailure catch (falha) {
      _mensagem(falha.message);
    } on AdminDataFailure catch (falha) {
      _mensagem(falha.message);
    } catch (_) {
      _mensagem(falhaGenerica);
    } finally {
      if (mounted) {
        setState(() => _ocupados.remove(termo.id));
        _recarregar();
      }
    }
  }

  Future<void> _revisar(TermsVersionSummary termo) async {
    if (_ocupados.contains(termo.id)) return;
    final ok = await _confirmar(
      titulo: 'Marcar como revisado',
      texto: 'Confirmo que o jurídico revisou a versão ${termo.version}.',
      rotulo: 'Confirmar revisão',
      chave: const Key('terms_review_confirm'),
    );
    if (!ok || !mounted) return;
    await _executar(
      termo,
      () => widget.dataSource.markTermsReviewed(termo.id),
      'Não foi possível marcar a versão como revisada.',
    );
  }

  Future<void> _publicar(TermsVersionSummary termo) async {
    if (_ocupados.contains(termo.id)) return;
    final ok = await _confirmar(
      titulo: 'Publicar versão',
      texto: 'A versão ${termo.version} passará a valer em ${formatarDataTermos(termo.effectiveFrom)}. '
          'Os pacientes verão o aviso desde hoje.',
      rotulo: 'Publicar',
      chave: const Key('terms_publish_confirm'),
    );
    if (!ok || !mounted) return;
    await _executar(
      termo,
      () => widget.dataSource.publishTermsVersion(termo.id),
      'Não foi possível publicar a versão.',
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<TermsVersionSummary>>(
        future: _lista,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return AdminAsyncError(error: snapshot.error, fallback: 'Não foi possível carregar os termos.', onRetry: _recarregar);
          }
          final termos = snapshot.data ?? const <TermsVersionSummary>[];
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text('Termos de uso', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                'Aqui se registra o anúncio da nova versão (versão, resumo e vigência). '
                'O texto integral dos termos vai no release do app do paciente.',
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  key: const Key('terms_new_button'),
                  style: FilledButton.styleFrom(minimumSize: _alvoMinimo),
                  onPressed: _nova,
                  icon: const Icon(Icons.add),
                  label: const Text('Nova versão'),
                ),
              ),
              const SizedBox(height: 16),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Center(child: CircularProgressIndicator())
              else if (termos.isEmpty)
                const Text('Nenhuma versão de termos cadastrada.')
              else
                for (final termo in termos)
                  _CartaoDoTermo(
                    termo: termo,
                    agora: widget.now(),
                    ocupado: _ocupados.contains(termo.id),
                    onRevisar: () => _revisar(termo),
                    onPublicar: () => _publicar(termo),
                  ),
            ],
          );
        },
      );
}

class _CartaoDoTermo extends StatelessWidget {
  const _CartaoDoTermo({
    required this.termo,
    required this.agora,
    required this.ocupado,
    required this.onRevisar,
    required this.onPublicar,
  });

  final TermsVersionSummary termo;
  final DateTime agora;
  final bool ocupado;
  final VoidCallback onRevisar;
  final VoidCallback onPublicar;

  @override
  Widget build(BuildContext context) {
    final estado = termo.state;
    final cor = _estadoCor(estado);
    final prazoEsgotado =
        estado == TermsVersionState.reviewed && termo.effectiveFrom.isBefore(agora.add(const Duration(days: 15)));
    final publicarHabilitado = estado == TermsVersionState.reviewed && !prazoEsgotado && !ocupado;
    return Card(
      key: Key('terms_row_${termo.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Versão ${termo.version}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(_estadoIcone(estado), size: 18, color: cor),
                const SizedBox(width: 6),
                Text(_estadoRotulo(estado), style: TextStyle(color: cor, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 4),
            Text('Vigora em ${formatarDataTermos(termo.effectiveFrom)}'),
            const SizedBox(height: 4),
            Text(termo.summary),
            if (estado == TermsVersionState.published)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Publicada em ${formatarDataTermos(termo.publishedAt!)} · vigora em ${formatarDataTermos(termo.effectiveFrom)}',
                ),
              ),
            if (estado != TermsVersionState.published) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (estado == TermsVersionState.draft)
                    OutlinedButton(
                      key: Key('terms_review_${termo.id}'),
                      style: OutlinedButton.styleFrom(minimumSize: _alvoMinimo),
                      onPressed: ocupado ? null : onRevisar,
                      child: const Text('Marcar como revisado'),
                    ),
                  FilledButton(
                    key: Key('terms_publish_${termo.id}'),
                    style: FilledButton.styleFrom(minimumSize: _alvoMinimo),
                    onPressed: publicarHabilitado ? onPublicar : null,
                    child: const Text('Publicar'),
                  ),
                ],
              ),
              if (estado == TermsVersionState.draft)
                const Padding(padding: EdgeInsets.only(top: 6), child: Text('Aguardando revisão jurídica')),
              if (prazoEsgotado)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('Prazo de 15 dias esgotado: crie uma nova versão com vigência posterior.'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
