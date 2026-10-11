/// Tela "Pedidos do titular" (#42): a fila de pedidos de exclusão e correção
/// (LGPD Art. 18) ordenada pelo prazo, o detalhe com o texto decifrado e as
/// decisões do coordenador/admin.
///
/// Nenhum texto de pedido, nota ou motivo vai para log: só para a tela.
library;

import 'package:flutter/material.dart';

import 'package:sinalacs_admin/app/admin_async_states.dart';
import 'package:sinalacs_admin/app/admin_layout.dart';
import 'package:sinalacs_admin/app/admin_theme.dart';
import 'package:sinalacs_admin/core/data/admin_data_source.dart';

String dataRequestTypeLabel(DataRequestType type) => switch (type) {
      DataRequestType.deletion => 'Exclusão dos dados',
      DataRequestType.correction => 'Correção de dados',
    };

String dataRequestStatusLabel(DataRequestStatus status) => switch (status) {
      DataRequestStatus.open => 'Aberto',
      DataRequestStatus.inReview => 'Em análise',
      DataRequestStatus.completed => 'Atendido',
      DataRequestStatus.rejected => 'Recusado',
    };

/// "Vencido há N dias", contado do prazo até [agora]. Menos de um dia de
/// atraso conta como 1: o servidor já disse que venceu, e "há 0 dias" leria
/// como "no prazo".
String overdueLabel(DateTime dueAt, DateTime agora) {
  final dias = agora.difference(dueAt).inDays;
  final n = dias < 1 ? 1 : dias;
  return n == 1 ? 'Vencido há 1 dia' : 'Vencido há $n dias';
}

String _dois(int valor) => valor.toString().padLeft(2, '0');

String _data(DateTime instante) {
  final local = instante.toLocal();
  return '${_dois(local.day)}/${_dois(local.month)}/${local.year}';
}

String _dataHora(DateTime instante) {
  final local = instante.toLocal();
  return '${_data(local)} ${_dois(local.hour)}:${_dois(local.minute)}';
}

const _alvoMinimo = Size(48, 52);

class DataRequestsScreen extends StatefulWidget {
  const DataRequestsScreen({required this.dataSource, this.now = DateTime.now, super.key});

  final AdminDataSource dataSource;

  /// Relógio injetável: o "Vencido há N dias" depende dele.
  final DateTime Function() now;

  @override
  State<DataRequestsScreen> createState() => _DataRequestsScreenState();
}

class _DataRequestsScreenState extends State<DataRequestsScreen> {
  DataRequestStatus? _filtro;
  String? _selecionado;
  late Future<List<DataRequestSummary>> _lista = _carregar();

  /// Registra o acesso antes de expor a fila, como as outras telas sensíveis
  /// (no backend é no-op: o servidor já audita a leitura).
  Future<List<DataRequestSummary>> _carregar() async {
    await widget.dataSource.recordAccess(actionType: 'view', resourceType: 'data_subject_requests');
    return widget.dataSource.fetchDataRequests(status: _filtro);
  }

  void _recarregar() => setState(() {
        _lista = _carregar();
      });

  @override
  Widget build(BuildContext context) {
    final id = _selecionado;
    if (id != null) {
      return _DetalheDoPedido(
        key: ValueKey(id),
        dataSource: widget.dataSource,
        id: id,
        now: widget.now,
        onVoltar: () => setState(() => _selecionado = null),
        onAlterado: _recarregar,
      );
    }
    return FutureBuilder<List<DataRequestSummary>>(
      future: _lista,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AdminAsyncError(error: snapshot.error, fallback: 'Não foi possível carregar os pedidos.', onRetry: _recarregar);
        }
        final pedidos = snapshot.data ?? const <DataRequestSummary>[];
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('Pedidos do titular (LGPD)', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Exclusão e correção pedidas pelos pacientes, do prazo mais próximo para o mais distante.'),
            const SizedBox(height: 16),
            DropdownButtonFormField<DataRequestStatus?>(
              key: const Key('data_requests_status_filter'),
              initialValue: _filtro,
              isExpanded: true,
              hint: const Text('Todos'),
              decoration: const InputDecoration(labelText: 'Status'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Todos')),
                for (final status in DataRequestStatus.values)
                  DropdownMenuItem(value: status, child: Text(dataRequestStatusLabel(status), overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (valor) => setState(() {
                _filtro = valor;
                _lista = _carregar();
              }),
            ),
            const SizedBox(height: 16),
            if (snapshot.connectionState == ConnectionState.waiting)
              const Center(child: CircularProgressIndicator())
            else if (pedidos.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Text(_filtro == null ? 'Nenhum pedido pendente.' : 'Nenhum pedido para o filtro selecionado.'),
              )
            else
              for (final pedido in pedidos)
                _LinhaDoPedido(
                  pedido: pedido,
                  agora: widget.now(),
                  onTap: () => setState(() => _selecionado = pedido.id),
                ),
          ],
        );
      },
    );
  }
}

/// Uma linha da fila, lida pelo leitor de tela como uma frase só.
class _LinhaDoPedido extends StatelessWidget {
  const _LinhaDoPedido({required this.pedido, required this.agora, required this.onTap});

  final DataRequestSummary pedido;
  final DateTime agora;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        key: Key('data_request_${pedido.id}'),
        margin: const EdgeInsets.only(bottom: 12),
        clipBehavior: Clip.antiAlias,
        shape: pedido.overdue
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: AdminColors.overdueOnSurface, width: 2),
              )
            : null,
        child: MergeSemantics(
          child: Semantics(
            button: true,
            hint: 'Abrir o pedido',
            child: InkWell(
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(dataRequestTypeLabel(pedido.type), style: const TextStyle(fontWeight: FontWeight.bold)),
                          _SeloDeStatus(pedido.status),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(pedido.patientLabel),
                      Text('Prazo: ${_data(pedido.dueAt)}'),
                      if (pedido.overdue) ...[
                        const SizedBox(height: 6),
                        _AvisoDeVencido(dueAt: pedido.dueAt, agora: agora),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

/// Ícone + texto: o atraso não depende só da cor (WCAG 1.4.1).
class _AvisoDeVencido extends StatelessWidget {
  const _AvisoDeVencido({required this.dueAt, required this.agora});

  final DateTime dueAt;
  final DateTime agora;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.schedule, key: Key('overdue_icon'), size: 18, color: AdminColors.overdueOnSurface),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              overdueLabel(dueAt, agora),
              style: const TextStyle(color: AdminColors.overdueOnSurface, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      );
}

class _SeloDeStatus extends StatelessWidget {
  const _SeloDeStatus(this.status);

  final DataRequestStatus status;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AdminColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AdminColors.border),
        ),
        child: Text(dataRequestStatusLabel(status)),
      );
}

class _DetalheDoPedido extends StatefulWidget {
  const _DetalheDoPedido({
    required this.dataSource,
    required this.id,
    required this.now,
    required this.onVoltar,
    required this.onAlterado,
    super.key,
  });

  final AdminDataSource dataSource;
  final String id;
  final DateTime Function() now;
  final VoidCallback onVoltar;

  /// Avisa a fila de que uma decisão foi tentada: ela relê a lista.
  final VoidCallback onAlterado;

  @override
  State<_DetalheDoPedido> createState() => _DetalheDoPedidoState();
}

class _DetalheDoPedidoState extends State<_DetalheDoPedido> {
  late Future<DataRequestDetail> _detalhe = widget.dataSource.fetchDataRequest(widget.id);
  final _resposta = TextEditingController();

  /// Uma decisão por vez: o botão fica desabilitado enquanto a chamada está
  /// pendente, e [_agir] ignora um segundo toque que escape disso.
  bool _enviando = false;
  String? _erroAcao;
  String? _aviso;

  @override
  void initState() {
    super.initState();
    _resposta.addListener(_textoMudou);
  }

  @override
  void dispose() {
    _resposta.dispose();
    super.dispose();
  }

  void _textoMudou() => setState(() {});

  void _reler() => setState(() {
        _detalhe = widget.dataSource.fetchDataRequest(widget.id);
      });

  Future<void> _agir(Future<void> Function() chamada) async {
    if (_enviando) return;
    setState(() {
      _enviando = true;
      _erroAcao = null;
      _aviso = null;
    });
    var atualizarLista = true;
    try {
      await chamada();
      if (!mounted) return;
      _resposta.clear();
      _aviso = 'Pedido atualizado.';
      _reler();
    } on AdminSessionExpired {
      atualizarLista = false;
      if (mounted) AdminSessionScope.maybeOf(context)?.call();
    } on AdminDataFailure catch (falha) {
      if (mounted) setState(() => _erroAcao = falha.message);
    } catch (_) {
      // O texto da exceção não vai para a tela nem para log.
      if (mounted) setState(() => _erroAcao = 'Não foi possível concluir a ação. Tente novamente.');
    } finally {
      if (mounted) setState(() => _enviando = false);
      if (atualizarLista && mounted) widget.onAlterado();
    }
  }

  Future<bool> _confirmar({required String titulo, required String texto, required String confirmar}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: Text(titulo),
        content: Text(texto),
        actions: [
          TextButton(
            style: TextButton.styleFrom(minimumSize: _alvoMinimo),
            onPressed: () => Navigator.of(contexto).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('confirm_action'),
            style: FilledButton.styleFrom(minimumSize: _alvoMinimo),
            onPressed: () => Navigator.of(contexto).pop(true),
            child: Text(confirmar),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _atender(DataRequestDetail pedido) async {
    final texto = _resposta.text.trim();
    if (pedido.type == DataRequestType.deletion) {
      final ok = await _confirmar(
        titulo: 'Atender a exclusão?',
        texto: 'Atender a exclusão anonimiza os dados do titular (nome, CPF, condições crônicas e respostas de '
            'triagem) e encerra o acesso dele ao aplicativo. A ação é irreversível.',
        confirmar: 'Confirmar exclusão',
      );
      if (!ok) return;
    }
    await _agir(() => widget.dataSource.completeDataRequest(pedido.id, note: texto.isEmpty ? null : texto));
  }

  Future<void> _recusar(DataRequestDetail pedido) async {
    final motivo = _resposta.text.trim();
    final ok = await _confirmar(
      titulo: 'Recusar o pedido?',
      texto: 'O titular verá o motivo informado. A recusa é definitiva para este pedido.',
      confirmar: 'Recusar pedido',
    );
    if (!ok) return;
    await _agir(() => widget.dataSource.rejectDataRequest(pedido.id, reason: motivo));
  }

  Widget _voltar() => Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const Key('data_request_back'),
          style: TextButton.styleFrom(minimumSize: _alvoMinimo),
          onPressed: widget.onVoltar,
          icon: const Icon(Icons.arrow_back),
          label: const Text('Voltar à lista'),
        ),
      );

  @override
  Widget build(BuildContext context) => FutureBuilder<DataRequestDetail>(
        future: _detalhe,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Column(
              children: [
                Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 0), child: _voltar()),
                Expanded(
                  child: AdminAsyncError(error: snapshot.error, fallback: 'Não foi possível carregar o pedido.', onRetry: _reler),
                ),
              ],
            );
          }
          final pedido = snapshot.data;
          // Só o primeiro carregamento mostra o spinner; ao reler depois de uma
          // decisão, o conteúdo antigo fica até o novo chegar.
          if (pedido == null) return const Center(child: CircularProgressIndicator());
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _voltar(),
              const SizedBox(height: 8),
              Text(dataRequestTypeLabel(pedido.type), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Campo('Paciente', pedido.patientLabel),
                      _Campo('Situação', dataRequestStatusLabel(pedido.status)),
                      _Campo('Recebido em', _dataHora(pedido.createdAt)),
                      _Campo('Prazo', _data(pedido.dueAt)),
                      if (pedido.overdue) ...[
                        const SizedBox(height: 4),
                        _AvisoDeVencido(dueAt: pedido.dueAt, agora: widget.now()),
                      ],
                      if (pedido.decidedAt != null) ...[
                        const SizedBox(height: 4),
                        Text('Decidido em ${_dataHora(pedido.decidedAt!)}'),
                      ],
                    ],
                  ),
                ),
              ),
              if (pedido.details != null) ...[
                const SizedBox(height: 16),
                _Bloco(titulo: 'Texto do pedido', texto: pedido.details!),
              ],
              if (pedido.resolution != null) ...[
                const SizedBox(height: 16),
                _Bloco(
                  titulo: pedido.status == DataRequestStatus.rejected ? 'Motivo da recusa' : 'Resposta ao titular',
                  texto: pedido.resolution!,
                ),
              ],
              if (_aviso != null) ...[
                const SizedBox(height: 16),
                Semantics(liveRegion: true, child: Text(_aviso!, key: const Key('data_request_action_notice'))),
              ],
              if (pedido.status == DataRequestStatus.open || pedido.status == DataRequestStatus.inReview)
                ..._acoes(pedido),
            ],
          );
        },
      );

  List<Widget> _acoes(DataRequestDetail pedido) {
    final correcao = pedido.type == DataRequestType.correction;
    final texto = _resposta.text;
    final valido = dataRequestTextIsValid(texto);
    // Correção: a nota é obrigatória. Exclusão: opcional, mas, se veio, tem de
    // passar na mesma régua.
    final podeAtender = !_enviando && (correcao ? valido : (texto.trim().isEmpty || valido));
    final podeRecusar = !_enviando && valido;
    return [
      const SizedBox(height: 20),
      const Divider(),
      const SizedBox(height: 12),
      const Text('Decisão', style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      TextField(
        key: const Key('resolution_field'),
        controller: _resposta,
        enabled: !_enviando,
        minLines: 3,
        maxLines: 6,
        maxLength: dataRequestTextMax,
        decoration: InputDecoration(
          labelText: correcao ? 'Resposta ao titular (obrigatória)' : 'Resposta ao titular (obrigatória para recusar)',
          helperText: 'De $dataRequestTextMin a $dataRequestTextMax caracteres. O titular vê este texto.',
          helperMaxLines: 3,
          alignLabelWithHint: true,
        ),
      ),
      const SizedBox(height: 12),
      LayoutBuilder(
        builder: (context, constraints) {
          final empilhado = constraints.maxWidth < AdminBreakpoints.stacked;
          Widget largo(Widget botao) => empilhado ? SizedBox(width: double.infinity, child: botao) : botao;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (pedido.status == DataRequestStatus.open)
                largo(
                  OutlinedButton(
                    key: const Key('start_review_button'),
                    style: OutlinedButton.styleFrom(minimumSize: _alvoMinimo),
                    onPressed: _enviando ? null : () => _agir(() => widget.dataSource.startDataRequestReview(pedido.id)),
                    child: const Text('Iniciar análise'),
                  ),
                ),
              largo(
                MergeSemantics(
                  child: Semantics(
                    hint: correcao ? 'Exige a resposta ao titular' : 'Pede confirmação: a exclusão é irreversível',
                    child: FilledButton(
                      key: const Key('complete_button'),
                      style: FilledButton.styleFrom(minimumSize: _alvoMinimo),
                      onPressed: podeAtender ? () => _atender(pedido) : null,
                      child: const Text('Atender'),
                    ),
                  ),
                ),
              ),
              largo(
                MergeSemantics(
                  child: Semantics(
                    hint: 'Exige o motivo e pede confirmação',
                    child: OutlinedButton(
                      key: const Key('reject_button'),
                      style: OutlinedButton.styleFrom(minimumSize: _alvoMinimo),
                      onPressed: podeRecusar ? () => _recusar(pedido) : null,
                      child: const Text('Recusar'),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      if (_enviando) ...[
        const SizedBox(height: 12),
        const LinearProgressIndicator(),
      ],
      if (_erroAcao != null) ...[
        const SizedBox(height: 12),
        Semantics(
          liveRegion: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(_erroAcao!, key: const Key('data_request_action_error'))),
            ],
          ),
        ),
      ],
    ];
  }
}

class _Campo extends StatelessWidget {
  const _Campo(this.rotulo, this.valor);

  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: '$rotulo: ', style: const TextStyle(color: Colors.white70)),
            TextSpan(text: valor, style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
        ),
      );
}

/// Texto livre (pedido, nota, motivo) num `Text` comum: `<script>` é só texto.
class _Bloco extends StatelessWidget {
  const _Bloco({required this.titulo, required this.texto});

  final String titulo;
  final String texto;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(texto),
            ],
          ),
        ),
      );
}
