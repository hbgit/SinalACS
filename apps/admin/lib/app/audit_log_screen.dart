/// Tela de Auditoria do backoffice (#45): consulta filtrada da trilha, selo por
/// linha e estado da verificação global da cadeia.
///
/// Saiu de `app.dart` quando ganhou estado próprio (filtro, cursor, verificação).
///
/// **A tela nunca decide integridade.** O app não tem o segredo da cadeia: o
/// selo de cada linha e o estado da cadeia são exatamente o que o servidor
/// devolveu. Só `verified` aparece como sucesso (verde, "Íntegro"/"Cadeia
/// íntegra"); `broken`, `unavailable` e `inconclusive` têm textos próprios e
/// nenhum deles reaproveita o texto de sucesso (D3). A cor nunca é o único
/// sinal: todo estado tem ícone, rótulo e `Semantics` (WCAG 1.4.1).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:sinalacs_admin/app/admin_async_states.dart';
import 'package:sinalacs_admin/app/admin_layout.dart';
import 'package:sinalacs_admin/app/admin_theme.dart';
import 'package:sinalacs_admin/core/data/admin_data_source.dart';

/// Timestamp de auditoria em `dd/MM/aaaa HH:mm`, hora local.
///
/// A tela imprimia `DateTime.toString()` cru — `2026-09-15 08:32:11.000Z` —
/// que é largo e cheio de ruído (milissegundos, sufixo Z) sem valor nenhum
/// para quem audita. Sem `intl` de propósito: o backoffice não tem nenhuma
/// dependência externa hoje e um formato pt-BR fixo basta; internacionalização
/// não está no escopo.
String formatAuditTimestamp(DateTime timestamp) {
  final local = timestamp.toLocal();
  String dois(int valor) => valor.toString().padLeft(2, '0');
  return '${dois(local.day)}/${dois(local.month)}/${local.year} ${dois(local.hour)}:${dois(local.minute)}';
}

/// Texto em português de cada motivo fechado do servidor (D9). Nenhum afirma
/// ataque ou adulteração: a mesma quebra aparece se a chave da cadeia for
/// trocada no servidor.
String auditChainReasonText(AuditChainReason motivo) => switch (motivo) {
  AuditChainReason.hashMismatch => 'O conteúdo de um registro não confere com o selo gravado.',
  AuditChainReason.linkBroken => 'O encadeamento entre dois registros consecutivos não confere.',
  AuditChainReason.sequenceGap => 'Há uma lacuna na numeração dos registros.',
  AuditChainReason.tailTruncated => 'Registros recentes que já haviam sido conferidos não foram encontrados.',
  AuditChainReason.checkpointInvalid => 'O último ponto de conferência gravado não confere com o seu selo.',
  AuditChainReason.timeBudget => 'A verificação excedeu o tempo limite e conferiu só parte da trilha.',
  AuditChainReason.databaseError => 'O banco de dados não respondeu à verificação.',
  AuditChainReason.secretUnavailable => 'A chave de verificação não está disponível no servidor.',
};

/// Alvo mínimo dos botões desta tela (WCAG 2.5.5), o mesmo da gestão de contas.
const _alvoMinimo = Size(48, 52);

class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({required this.dataSource, this.now, super.key});

  final AdminDataSource dataSource;

  /// Relógio do período relativo do filtro ("últimos 7 dias"); só os testes o trocam.
  final DateTime Function()? now;

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

/// Período relativo oferecido pelo filtro. `to` fica aberto (até agora).
enum _Periodo {
  qualquer('Qualquer período', null),
  dia('Últimas 24 horas', Duration(hours: 24)),
  semana('Últimos 7 dias', Duration(days: 7)),
  mes('Últimos 30 dias', Duration(days: 30));

  const _Periodo(this.rotulo, this.janela);
  final String rotulo;
  final Duration? janela;
}

const _rotuloDoPapel = {
  AuditActorRole.patient: 'Paciente',
  AuditActorRole.acs: 'ACS',
  AuditActorRole.coordinator: 'Coordenador',
  AuditActorRole.admin: 'Administrador',
};

const _rotuloDaAcao = {'read': 'Leitura', 'write': 'Escrita', 'login': 'Login', 'export': 'Exportação'};

/// Mesma regra do servidor para tipo de recurso e resultado (D1).
final _rotuloValido = RegExp(r'^[a-z0-9_:]{1,64}$');

class _AuditLogScreenState extends State<AuditLogScreen> {
  // Registro do próprio acesso (PRD §4.2.2): sem ele, nada é mostrado.
  bool _acessoRegistrado = false;
  Object? _erroDoRegistro;

  // Filtro aplicado e o rascunho do formulário.
  AuditLogFilter _filtro = const AuditLogFilter();
  final _busca = TextEditingController();
  final _matricula = TextEditingController();
  final _recurso = TextEditingController();
  final _resultado = TextEditingController();
  AuditActorRole? _papel;
  String? _acao;
  _Periodo _periodo = _Periodo.qualquer;
  String? _erroDoFiltro;

  /// Muda a cada "Limpar": recria os campos do formulário, porque um
  /// `DropdownButtonFormField` guarda o próprio valor e ignora um
  /// `initialValue` novo.
  int _limpezas = 0;

  // Lista paginada por keyset.
  final List<AuditLogEntry> _itens = [];
  final Set<int> _vistos = {};
  int? _cursor;
  bool _carregandoLista = false;
  Object? _erroDaLista;
  bool _carregandoMais = false;
  Object? _erroDoMais;

  /// Cada recarga da lista (filtro novo, limpar, tentar de novo) aumenta a
  /// geração: resposta de uma geração antiga é descartada, e "Carregar mais"
  /// de um filtro antigo não se mistura à lista do filtro novo.
  int _geracao = 0;

  // Verificação global da cadeia.
  ChainStatus? _cadeia;
  Object? _erroDaCadeia;
  bool _verificando = false;

  @override
  void initState() {
    super.initState();
    unawaited(_iniciar());
  }

  @override
  void dispose() {
    _busca.dispose();
    _matricula.dispose();
    _recurso.dispose();
    _resultado.dispose();
    super.dispose();
  }

  /// Registra o acesso e só então carrega lista e cadeia. Sem `setState`
  /// antes do primeiro `await`: é chamada também de `initState`.
  Future<void> _iniciar() async {
    try {
      await widget.dataSource.recordAccess(actionType: 'view', resourceType: 'audit_logs');
    } catch (e) {
      if (mounted) setState(() => _erroDoRegistro = e);
      return;
    }
    if (!mounted) return;
    setState(() => _acessoRegistrado = true);
    unawaited(_recarregarLista());
    unawaited(_verificarCadeia());
  }

  Future<void> _recarregarLista() async {
    final geracao = ++_geracao;
    setState(() {
      _itens.clear();
      _vistos.clear();
      _cursor = null;
      _erroDaLista = null;
      _erroDoMais = null;
      _carregandoMais = false;
      _carregandoLista = true;
    });
    try {
      final pagina = await widget.dataSource.fetchAuditLogs(filter: _filtro);
      if (!mounted || geracao != _geracao) return;
      setState(() {
        _acrescentar(pagina);
        _carregandoLista = false;
      });
    } catch (e) {
      if (!mounted || geracao != _geracao) return;
      setState(() {
        _erroDaLista = e;
        _carregandoLista = false;
      });
    }
  }

  Future<void> _carregarMais() async {
    final cursor = _cursor;
    if (cursor == null || _carregandoMais) return;
    final geracao = _geracao;
    setState(() {
      _carregandoMais = true;
      _erroDoMais = null;
    });
    try {
      final pagina = await widget.dataSource.fetchAuditLogs(filter: _filtro, beforeSequence: cursor);
      if (!mounted || geracao != _geracao) return;
      setState(() {
        _acrescentar(pagina);
        _carregandoMais = false;
      });
    } catch (e) {
      if (!mounted || geracao != _geracao) return;
      if (e is AdminSessionExpired) {
        AdminSessionScope.maybeOf(context)?.call();
        return;
      }
      setState(() {
        _erroDoMais = e;
        _carregandoMais = false;
      });
    }
  }

  /// Junta a página à lista sem repetir `sequence` já mostrada.
  void _acrescentar(AuditLogPage pagina) {
    for (final e in pagina.items) {
      if (_vistos.add(e.sequence)) _itens.add(e);
    }
    _cursor = pagina.nextBeforeSequence;
  }

  Future<void> _verificarCadeia() async {
    setState(() {
      _verificando = true;
      _erroDaCadeia = null;
    });
    try {
      final status = await widget.dataSource.verifyAuditChain();
      if (!mounted) return;
      setState(() {
        _cadeia = status;
        _verificando = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (e is AdminSessionExpired) {
        AdminSessionScope.maybeOf(context)?.call();
        return;
      }
      setState(() {
        // Falha ao consultar não é estado da cadeia: o resultado anterior sai
        // da tela para não parecer atual.
        _cadeia = null;
        _erroDaCadeia = e;
        _verificando = false;
      });
    }
  }

  void _aplicarFiltros() {
    String? limpo(TextEditingController c) {
      final t = c.text.trim();
      return t.isEmpty ? null : t;
    }

    final busca = limpo(_busca);
    final matricula = limpo(_matricula);
    final recurso = limpo(_recurso)?.toLowerCase();
    final resultado = limpo(_resultado)?.toLowerCase();

    String? erro;
    if (busca != null && (busca.length < 2 || busca.length > 64)) {
      erro = 'A busca deve ter de 2 a 64 caracteres.';
    } else if (matricula != null && matricula.length > 32) {
      erro = 'A matrícula deve ter no máximo 32 caracteres.';
    } else if (recurso != null && !_rotuloValido.hasMatch(recurso)) {
      erro = 'Tipo de recurso: use só letras sem acento, números, "_" ou ":".';
    } else if (resultado != null && !_rotuloValido.hasMatch(resultado)) {
      erro = 'Resultado: use só letras sem acento, números, "_" ou ":".';
    }
    if (erro != null) {
      setState(() => _erroDoFiltro = erro);
      return;
    }

    final janela = _periodo.janela;
    final agora = (widget.now ?? DateTime.now)().toUtc();
    _erroDoFiltro = null;
    _filtro = AuditLogFilter(
      search: busca,
      actorEnrollmentId: matricula,
      actorRole: _papel,
      actionType: _acao,
      resourceType: recurso,
      result: resultado,
      from: janela == null ? null : agora.subtract(janela),
    );
    unawaited(_recarregarLista());
  }

  void _limparFiltros() {
    _busca.clear();
    _matricula.clear();
    _recurso.clear();
    _resultado.clear();
    _papel = null;
    _acao = null;
    _periodo = _Periodo.qualquer;
    _erroDoFiltro = null;
    _limpezas++;
    _filtro = const AuditLogFilter();
    unawaited(_recarregarLista());
  }

  @override
  Widget build(BuildContext context) {
    if (_erroDoRegistro != null) {
      return AdminAsyncError(
        error: _erroDoRegistro,
        fallback: 'Não foi possível registrar o acesso a esta tela.',
        onRetry: () {
          setState(() => _erroDoRegistro = null);
          unawaited(_iniciar());
        },
      );
    }
    if (!_acessoRegistrado) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Logs de auditoria', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text(
          'Somente leitura. O próprio acesso a esta tela também é auditado. A coordenação vê apenas os registros dos autores com microárea na sua UBS.',
        ),
        const SizedBox(height: 16),
        _PainelDaCadeia(
          status: _cadeia,
          erro: _erroDaCadeia,
          verificando: _verificando,
          onVerificar: _verificando ? null : _verificarCadeia,
        ),
        const SizedBox(height: 16),
        _formularioDeFiltros(),
        const SizedBox(height: 16),
        ..._lista(),
      ],
    );
  }

  List<Widget> _lista() {
    if (_carregandoLista) {
      return const [
        Padding(
          padding: EdgeInsets.only(top: 24),
          child: Center(child: CircularProgressIndicator(key: Key('audit_loading'))),
        ),
      ];
    }
    if (_erroDaLista != null) {
      return [
        AdminAsyncError(
          error: _erroDaLista,
          fallback: 'Não foi possível carregar os logs de auditoria.',
          onRetry: _recarregarLista,
        ),
      ];
    }
    if (_itens.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Text(
            _filtro.isEmpty ? 'Nenhum acesso registrado ainda.' : 'Nenhum registro encontrado para estes filtros.',
          ),
        ),
      ];
    }
    final n = _itens.length;
    return [
      Semantics(
        liveRegion: true,
        child: Text(n == 1 ? '1 registro carregado' : '$n registros carregados', key: const Key('audit_count')),
      ),
      const SizedBox(height: 8),
      for (final entry in _itens) _LinhaDeAuditoria(entry: entry),
      if (_cursor != null) ...[
        const SizedBox(height: 8),
        if (_erroDoMais != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _erroDoMais is AdminDataFailure
                    ? (_erroDoMais! as AdminDataFailure).message
                    : 'Não foi possível carregar mais registros.',
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const Key('audit_load_more'),
            style: OutlinedButton.styleFrom(minimumSize: _alvoMinimo),
            onPressed: _carregandoMais ? null : _carregarMais,
            icon: _carregandoMais
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.expand_more),
            label: const Text('Carregar mais'),
          ),
        ),
      ],
    ];
  }

  /// Quantos campos do filtro APLICADO estão preenchidos (o período conta um).
  int get _filtrosAtivos {
    final f = _filtro;
    return [
      f.search,
      f.actorEnrollmentId,
      f.actorRole,
      f.actionType,
      f.resourceType,
      f.result,
      f.from,
    ].where((v) => v != null).length;
  }

  /// Filtros recolhidos por padrão: abertos, empurrariam a lista para baixo da
  /// dobra. O título diz quantos estão aplicados, para a lista filtrada nunca
  /// parecer a trilha inteira.
  Widget _formularioDeFiltros() {
    final ativos = _filtrosAtivos;
    return Card(
      child: ExpansionTile(
        key: const Key('audit_filters_toggle'),
        shape: const Border(),
        collapsedShape: const Border(),
        minTileHeight: 56,
        leading: const Icon(Icons.filter_alt_outlined),
        title: const Text('Filtros', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(switch (ativos) {
          0 => 'Nenhum filtro aplicado',
          1 => '1 filtro aplicado',
          _ => '$ativos filtros aplicados',
        }, key: const Key('audit_filters_summary')),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [_camposDoFiltro()],
      ),
    );
  }

  Widget _camposDoFiltro() => LayoutBuilder(
    builder: (context, constraints) {
      final compacto = constraints.maxWidth < AdminBreakpoints.stacked;
      final largura = compacto ? constraints.maxWidth : ((constraints.maxWidth - 24) / 3).clamp(200.0, 280.0);
      Widget campo(Widget filho) => SizedBox(width: largura, child: filho);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KeyedSubtree(
            key: ValueKey(_limpezas),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                campo(
                  TextField(
                    key: const Key('audit_filter_search'),
                    controller: _busca,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _aplicarFiltros(),
                    decoration: const InputDecoration(
                      labelText: 'Busca',
                      helperText: 'Início da matrícula, tipo de recurso ou resultado.',
                      helperMaxLines: 3,
                    ),
                  ),
                ),
                campo(
                  TextField(
                    key: const Key('audit_filter_enrollment'),
                    controller: _matricula,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _aplicarFiltros(),
                    decoration: const InputDecoration(labelText: 'Matrícula do autor'),
                  ),
                ),
                campo(
                  DropdownButtonFormField<AuditActorRole?>(
                    key: const Key('audit_filter_role'),
                    initialValue: _papel,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Papel do autor'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Todos os papéis', overflow: TextOverflow.ellipsis),
                      ),
                      for (final p in AuditActorRole.values)
                        DropdownMenuItem(
                          value: p,
                          child: Text(_rotuloDoPapel[p]!, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setState(() => _papel = v),
                  ),
                ),
                campo(
                  DropdownButtonFormField<String?>(
                    key: const Key('audit_filter_action'),
                    initialValue: _acao,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Ação'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Todas as ações', overflow: TextOverflow.ellipsis),
                      ),
                      for (final MapEntry(:key, :value) in _rotuloDaAcao.entries)
                        DropdownMenuItem(
                          value: key,
                          child: Text(value, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setState(() => _acao = v),
                  ),
                ),
                campo(
                  TextField(
                    key: const Key('audit_filter_resource'),
                    controller: _recurso,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _aplicarFiltros(),
                    decoration: const InputDecoration(labelText: 'Tipo de recurso'),
                  ),
                ),
                campo(
                  TextField(
                    key: const Key('audit_filter_result'),
                    controller: _resultado,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _aplicarFiltros(),
                    decoration: const InputDecoration(labelText: 'Resultado'),
                  ),
                ),
                campo(
                  DropdownButtonFormField<_Periodo>(
                    key: const Key('audit_filter_period'),
                    initialValue: _periodo,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Período'),
                    items: [
                      for (final p in _Periodo.values)
                        DropdownMenuItem(
                          value: p,
                          child: Text(p.rotulo, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setState(() => _periodo = v ?? _Periodo.qualquer),
                  ),
                ),
              ],
            ),
          ),
          if (_erroDoFiltro != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline, color: AdminColors.redOnSurface, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _erroDoFiltro!,
                      key: const Key('audit_filter_error'),
                      style: const TextStyle(color: AdminColors.redOnSurface),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: const Key('audit_filter_apply'),
                style: FilledButton.styleFrom(minimumSize: _alvoMinimo),
                onPressed: _aplicarFiltros,
                icon: const Icon(Icons.filter_alt_outlined),
                label: const Text('Aplicar filtros'),
              ),
              OutlinedButton.icon(
                key: const Key('audit_filter_clear'),
                style: OutlinedButton.styleFrom(minimumSize: _alvoMinimo),
                onPressed: _limparFiltros,
                icon: const Icon(Icons.clear),
                label: const Text('Limpar'),
              ),
            ],
          ),
        ],
      );
    },
  );
}

/// Uma linha da trilha com o selo que o servidor deu a ela.
class _LinhaDeAuditoria extends StatelessWidget {
  const _LinhaDeAuditoria({required this.entry});

  final AuditLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final conteudo = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${entry.actionType} • ${entry.resourceType}', style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text('${entry.userLabel} — ${formatAuditTimestamp(entry.timestamp)}'),
        Text('Resultado: ${entry.result} · nº ${entry.sequence}', style: const TextStyle(color: Colors.white70)),
      ],
    );
    final selo = _SeloDaLinha(key: Key('audit_seal_${entry.id}'), seal: entry.seal);
    return Card(
      key: Key('audit_${entry.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Em tela estreita o selo desce para baixo do conteúdo, em vez de
            // espremer o rótulo do autor contra a borda.
            if (constraints.maxWidth < AdminBreakpoints.stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [conteudo, const SizedBox(height: 8), selo],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: conteudo),
                const SizedBox(width: 12),
                ConstrainedBox(constraints: const BoxConstraints(maxWidth: 200), child: selo),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Aparência de cada selo: ícone, rótulo, cor de TEXTO e frase do leitor de tela.
({IconData icone, String rotulo, Color cor, String semantica}) _aparenciaDoSelo(AuditRowSeal seal) => switch (seal) {
  AuditRowSeal.verified => (
    icone: Icons.verified_outlined,
    rotulo: 'Íntegro',
    cor: AdminColors.green,
    semantica: 'Selo do registro: íntegro',
  ),
  AuditRowSeal.invalid => (
    icone: Icons.gpp_bad_outlined,
    rotulo: 'Adulterado?',
    cor: AdminColors.redOnSurface,
    semantica: 'Selo do registro: possível adulteração — o conteúdo não confere com o selo gravado',
  ),
  AuditRowSeal.unverifiable => (
    icone: Icons.help_outline,
    rotulo: 'Não verificável',
    cor: Colors.white70,
    semantica: 'Selo do registro: não verificável — o registro anterior não está disponível para conferência',
  ),
};

class _SeloDaLinha extends StatelessWidget {
  const _SeloDaLinha({required this.seal, super.key});

  final AuditRowSeal seal;

  @override
  Widget build(BuildContext context) {
    final a = _aparenciaDoSelo(seal);
    return Semantics(
      container: true,
      label: a.semantica,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(a.icone, color: a.cor, size: 18),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              a.rotulo,
              style: TextStyle(color: a.cor, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Painel do estado global da cadeia, exatamente como o servidor o devolveu.
class _PainelDaCadeia extends StatelessWidget {
  const _PainelDaCadeia({
    required this.status,
    required this.erro,
    required this.verificando,
    required this.onVerificar,
  });

  final ChainStatus? status;
  final Object? erro;
  final bool verificando;
  final VoidCallback? onVerificar;

  static const _naoEIntegra = 'Isso não significa que a cadeia está íntegra.';

  @override
  Widget build(BuildContext context) {
    final (icone, cor, titulo, linhas) = _conteudo();
    return Card(
      key: const Key('audit_chain_status'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Largo, o botão fica ao lado do estado: a lista começa mais acima.
            final largo = constraints.maxWidth >= AdminBreakpoints.stacked;
            final botao = OutlinedButton.icon(
              key: const Key('audit_chain_retry'),
              style: OutlinedButton.styleFrom(minimumSize: _alvoMinimo),
              onPressed: onVerificar,
              icon: const Icon(Icons.refresh),
              label: const Text('Verificar novamente'),
            );
            final cabecalho = Semantics(
              liveRegion: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  icone,
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Integridade da trilha', style: TextStyle(color: Colors.white70)),
                        Text(
                          titulo,
                          key: const Key('audit_chain_title'),
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (largo)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: cabecalho),
                      const SizedBox(width: 12),
                      botao,
                    ],
                  )
                else
                  cabecalho,
                for (final linha in linhas) ...[const SizedBox(height: 6), Text(linha)],
                if (!largo) ...[const SizedBox(height: 12), botao],
              ],
            );
          },
        ),
      ),
    );
  }

  (Widget, Color?, String, List<String>) _conteudo() {
    final s = status;
    if (s == null) {
      if (erro != null) {
        final detalhe = erro is AdminDataFailure ? (erro! as AdminDataFailure).message : null;
        return (
          const Icon(Icons.sync_problem, color: Colors.white70),
          null,
          'Não foi possível verificar a integridade agora.',
          [?detalhe, _naoEIntegra],
        );
      }
      return (
        const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
        null,
        'Verificando a integridade da trilha…',
        const [],
      );
    }

    final motivo = s.reasonCode == null ? null : auditChainReasonText(s.reasonCode!);
    final conferidos = s.checkedRows == null
        ? null
        : (s.checkedRows == 1 ? '1 registro conferido.' : '${s.checkedRows} registros conferidos.');
    final quando = 'Verificado em ${formatAuditTimestamp(s.verifiedAt)}.';

    return switch (s.state) {
      AuditIntegrityState.verified => (
        const Icon(Icons.verified_outlined, color: AdminColors.green),
        AdminColors.green,
        'Cadeia íntegra',
        [
          [?conferidos, quando].join(' '),
        ],
      ),
      AuditIntegrityState.broken => (
        const Icon(Icons.gpp_bad_outlined, color: AdminColors.redOnSurface),
        AdminColors.redOnSurface,
        'Falha de integridade na cadeia',
        [
          ?motivo,
          if (s.firstBrokenSequence != null) 'Primeiro registro com falha: nº ${s.firstBrokenSequence}.',
          switch (s.brokenInScope) {
            true => 'A falha atinge registros que você vê nesta tela.',
            false => 'Nenhum registro que você vê foi apontado como ponto da falha.',
            null => 'Não foi informado se a falha atinge registros que você vê.',
          },
          'Pode indicar alteração indevida de registros ou troca da chave de verificação no servidor; '
              'sozinha, não é prova de adulteração. Avise a administração do sistema.',
          ?conferidos,
          quando,
        ],
      ),
      AuditIntegrityState.unavailable => (
        const Icon(Icons.cloud_off_outlined, color: Colors.white70),
        null,
        'Verificação indisponível',
        ['O servidor não conseguiu concluir a verificação agora. $_naoEIntegra', ?motivo, quando],
      ),
      AuditIntegrityState.inconclusive => (
        const Icon(Icons.help_outline, color: Colors.white70),
        null,
        'Verificação inconclusiva',
        [
          'A verificação não chegou a uma conclusão (trilha vazia ou conferida só em parte). $_naoEIntegra',
          ?motivo,
          ?conferidos,
          quando,
        ],
      ),
    };
  }
}
