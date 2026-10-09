import 'package:flutter/material.dart';
import 'dart:async';

import 'package:sinalacs_admin/app/admin_async_states.dart';
import 'package:sinalacs_admin/app/admin_accounts.dart';
import 'package:sinalacs_admin/app/admin_header.dart';
import 'package:sinalacs_admin/app/data_requests_screen.dart';
import 'package:sinalacs_admin/app/admin_layout.dart';
import 'package:sinalacs_admin/app/login_screen.dart';
import 'package:sinalacs_admin/core/auth/admin_auth_backend.dart';
import 'package:sinalacs_admin/core/auth/admin_auth_bootstrap.dart';
import 'package:sinalacs_admin/app/admin_theme.dart';
import 'package:sinalacs_admin/core/data/admin_data_source.dart';
import 'package:sinalacs_admin/core/data/mock_admin_data_source.dart';

class SinalAdminApp extends StatelessWidget {
  /// [dataSourceFor] é o caminho de produção: a fonte de dados nasce da sessão
  /// que o login devolveu (o token vive nela). [dataSource] fixa uma fonte pronta
  /// e existe para os testes de tela; sem nenhum dos dois, o app cai no
  /// [MockAdminDataSource] — **só** para teste, `main.dart` sempre passa
  /// [dataSourceFor].
  SinalAdminApp({super.key, AdminDataSource? dataSource, AdminDataSourceFactory? dataSourceFor, required this.auth})
      : dataSourceFor = dataSourceFor ?? _fixa(dataSource ?? MockAdminDataSource());

  final AdminDataSourceFactory dataSourceFor;

  static AdminDataSourceFactory _fixa(AdminDataSource fonte) => (_) => fonte;

  /// A única porta de entrada do painel: sem sessão devolvida por
  /// [AdminAuthBackend.login] não existe caminho que abra [AdminHomeShell].
  final AdminAuthBackend auth;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'SinalACS Admin',
        debugShowCheckedModeBanner: false,
        theme: buildAdminTheme(),
        home: LoginScreen(auth: auth, dataSourceFor: dataSourceFor),
      );
}

enum AdminDestination { indicators, microAreas, alerts, auditLog, dataRequests }

extension on AdminDestination {
  String get label => switch (this) {
        AdminDestination.indicators => 'Indicadores',
        AdminDestination.microAreas => 'Microáreas',
        AdminDestination.alerts => 'Alertas',
        AdminDestination.auditLog => 'Auditoria',
        AdminDestination.dataRequests => 'Pedidos do titular',
      };

  /// Rótulo da barra inferior do celular, onde com cinco destinos cada um tem
  /// 64–72dp de largura: "Pedidos do titular" quebrava em quatro linhas (a
  /// última cortada abaixo da barra) e "Indicadores" partia no meio da
  /// palavra. O nome completo segue no `tooltip` (toque longo e leitor de
  /// tela) e no NavigationRail. "Painel" é o título da própria tela.
  String get shortLabel => switch (this) {
        AdminDestination.indicators => 'Painel',
        AdminDestination.dataRequests => 'Pedidos',
        _ => label,
      };

  IconData get icon => switch (this) {
        AdminDestination.indicators => Icons.dashboard_outlined,
        AdminDestination.microAreas => Icons.map_outlined,
        AdminDestination.alerts => Icons.warning_amber_outlined,
        AdminDestination.auditLog => Icons.fact_check_outlined,
        AdminDestination.dataRequests => Icons.privacy_tip_outlined,
      };
}

/// Relógio injetável: deixa o teste da sessão vencida sem `sleep`.
typedef AdminClock = DateTime Function();

class AdminHomeShell extends StatefulWidget {
  const AdminHomeShell({
    required this.dataSource,
    required this.dataSourceFor,
    required this.session,
    required this.auth,
    this.now = DateTime.now,
    super.key,
  });

  final AdminDataSource dataSource;

  /// Usada só para reconstruir o login quando a sessão vence: a próxima sessão
  /// tem outro token e portanto outra fonte de dados.
  final AdminDataSourceFactory dataSourceFor;

  /// Sessão devolvida por [AdminAuthBackend.login]. Sem ela o painel não abre.
  final AdminSession session;

  /// Usada só para reconstruir o login quando a sessão vence.
  final AdminAuthBackend auth;
  final AdminClock now;

  @override
  State<AdminHomeShell> createState() => _AdminHomeShellState();
}

class _AdminHomeShellState extends State<AdminHomeShell> {
  AdminDestination destination = AdminDestination.indicators;
  Timer? _vencimento;

  @override
  void initState() {
    super.initState();
    final restante = widget.session.expiresAt.difference(widget.now());
    if (restante <= Duration.zero) {
      // Navegar durante o build não pode: adia para depois do primeiro frame.
      WidgetsBinding.instance.addPostFrameCallback((_) => _encerrarSeVencida());
    } else {
      // O disparo do Timer já é o vencimento: não reconfere o relógio.
      _vencimento = Timer(restante, _encerrar);
    }
  }

  @override
  void dispose() {
    _vencimento?.cancel();
    super.dispose();
  }

  /// Volta ao login, descartando o painel e a sessão, quando ela venceu.
  void _encerrarSeVencida() {
    if (!mounted || widget.now().isBefore(widget.session.expiresAt)) return;
    _encerrar();
  }

  void _encerrar() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => LoginScreen(
          auth: widget.auth,
          dataSourceFor: widget.dataSourceFor,
          aviso: 'Sessão encerrada. Entre novamente.',
        ),
      ),
      (_) => false,
    );
  }

  Widget _content() => AdminSessionScope(aoVencer: _encerrar, child: _telaAtual());

  Widget _telaAtual() => switch (destination) {
        AdminDestination.indicators => IndicatorsScreen(dataSource: widget.dataSource),
        AdminDestination.microAreas =>
          MicroAreasScreen(dataSource: widget.dataSource, role: widget.session.role),
        AdminDestination.alerts => AlertsScreen(dataSource: widget.dataSource),
        AdminDestination.auditLog => AuditLogScreen(dataSource: widget.dataSource),
        AdminDestination.dataRequests => DataRequestsScreen(dataSource: widget.dataSource, now: widget.now),
      };

  void _select(int index) {
    setState(() => destination = AdminDestination.values[index]);
    _encerrarSeVencida();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final content = _content();
          final header = AdminHeader('Backoffice • ${adminRoleLabel(widget.session.role)}', 'Painel administrativo', height: adminHeaderHeight(context));
          // Backoffice é desktop-first (spec/PRD_system.md §2.1): NavigationRail
          // acima de AdminBreakpoints.rail, NavigationBar abaixo — mesmo
          // ThemeData nos dois.
          if (constraints.maxWidth >= AdminBreakpoints.rail) {
            return Scaffold(
              appBar: header,
              // SafeArea envolve a linha inteira, e não só o conteúdo: num
              // celular em paisagem é o rail que encosta no recorte da câmera.
              // `top: false` porque a AppBar já trata o inset de cima.
              body: SafeArea(
                top: false,
                child: Row(
                children: [
                  NavigationRail(
                    key: const Key('admin_navigation_rail'),
                    selectedIndex: destination.index,
                    onDestinationSelected: _select,
                    labelType: NavigationRailLabelType.all,
                    // Em paisagem de celular sobram ~288dp de altura para
                    // quatro destinos rotulados: cabe por poucos pixels com
                    // fonte padrão e estoura com fonte ampliada. `scrollable`
                    // troca o estouro por rolagem em vez de cortar destino.
                    scrollable: true,
                    destinations: [
                      for (final value in AdminDestination.values)
                        NavigationRailDestination(icon: Icon(value.icon), label: Text(value.label)),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: content),
                ],
                ),
              ),
            );
          }
          return Scaffold(
            appBar: header,
            // `bottom: false`: o NavigationBar do Scaffold já trata o inset
            // inferior; duplicar aqui abriria uma faixa morta acima dele.
            body: SafeArea(top: false, bottom: false, child: content),
            bottomNavigationBar: NavigationBar(
              key: const Key('admin_navigation_bar'),
              height: adminNavigationBarHeight(context),
              selectedIndex: destination.index,
              onDestinationSelected: _select,
              destinations: [
                for (final value in AdminDestination.values)
                  NavigationDestination(
                    icon: Icon(value.icon),
                    label: value.shortLabel,
                    tooltip: value.shortLabel == value.label ? null : value.label,
                  ),
              ],
            ),
          );
        },
      );
}

/// Rótulo do papel para o cabeçalho. Valor desconhecido não quebra a tela nem
/// aparece cru: o token só chega aqui com papel de staff, mas o cabeçalho não
/// deve depender disso.
String adminRoleLabel(String role) => switch (role) {
      'admin' => 'Administrador',
      'coordinator' => 'Coordenador',
      _ => 'Equipe',
    };

String riskLabel(RiskLevel level) => switch (level) {
      RiskLevel.red => 'Vermelho',
      RiskLevel.yellow => 'Amarelo',
      RiskLevel.green => 'Verde',
    };

Color riskColor(RiskLevel level) => switch (level) {
      RiskLevel.red => AdminColors.red,
      RiskLevel.yellow => AdminColors.yellow,
      RiskLevel.green => AdminColors.green,
    };

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

String statusLabel(AlertStatus status) => switch (status) {
      AlertStatus.pending => 'Pendente',
      AlertStatus.acknowledged => 'Reconhecido',
      AlertStatus.resolved => 'Resolvido',
      AlertStatus.escalated => 'Escalonado',
    };

class IndicatorsScreen extends StatefulWidget {
  const IndicatorsScreen({required this.dataSource, super.key});

  final AdminDataSource dataSource;

  @override
  State<IndicatorsScreen> createState() => _IndicatorsScreenState();
}

class _IndicatorsScreenState extends State<IndicatorsScreen> {
  late Future<DashboardIndicators> _future = widget.dataSource.fetchDashboardIndicators();

  void _retry() => setState(() {
        _future = widget.dataSource.fetchDashboardIndicators();
      });

  @override
  Widget build(BuildContext context) => FutureBuilder<DashboardIndicators>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return AdminAsyncError(error: snapshot.error, fallback: 'Não foi possível carregar os indicadores.', onRetry: _retry);
          }
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final data = snapshot.data!;
          return _page([
            const Text('Painel de Indicadores', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Contadores por risco clínico da UBS'),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                // Os cartões tinham 160dp fixos dentro de um Wrap: cabiam, mas
                // deixavam um vão à direita no desktop e não se adaptavam a
                // nada. A grade calculada distribui a largura disponível e cai
                // para uma coluna quando não há espaço para duas.
                const espaco = 12.0;
                final colunas = ((constraints.maxWidth + espaco) / (AdminBreakpoints.counterCardMin + espaco))
                    .floor()
                    .clamp(1, RiskLevel.values.length);
                final largura = (constraints.maxWidth - espaco * (colunas - 1)) / colunas;
                return Wrap(
                  spacing: espaco,
                  runSpacing: espaco,
                  children: [
                    for (final level in RiskLevel.values)
                      _CounterCard(
                        key: Key('risk_counter_${level.name}'),
                        label: riskLabel(level),
                        value: '${data.countsByRisk[level] ?? 0}',
                        color: riskColor(level),
                        width: largura,
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            const Text('Alertas vermelhos', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _InfoRow('Abertos (pendentes)', '${data.openRedAlerts}'),
            _InfoRow('Reconhecidos', '${data.acknowledgedRedAlerts}'),
            _InfoRow('TMRAV (tempo médio de resposta)', data.tmravSeconds == null ? '—' : '${data.tmravSeconds}s'),
          ]);
        },
      );
}

class _CounterCard extends StatelessWidget {
  const _CounterCard({required this.label, required this.value, required this.color, required this.width, super.key});

  final String label;
  final String value;
  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AdminColors.surfaceRaised,
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: color, width: 4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: adminOnSurface(color), fontWeight: FontWeight.bold)),
          ],
        ),
      );
}

/// O que a tela Microáreas carrega numa tarefa só: as seções de gestão (#43)
/// precisam das microáreas (opções de vínculo), dos ACS e — só para o
/// administrador — das contas de equipe.
typedef _DadosDaTela = ({
  List<MicroAreaSummary> areas,
  List<AcsSummary> acs,
  List<StaffSummary> staff,
});

class MicroAreasScreen extends StatefulWidget {
  const MicroAreasScreen({required this.dataSource, required this.role, super.key});

  final AdminDataSource dataSource;

  /// Papel da sessão (`admin`/`coordinator`). A seção de Equipe do backoffice
  /// só existe para o administrador — `StaffManagementSection` não é montada
  /// para o coordenador, e o servidor também recusa essa listagem para ele.
  final String role;

  @override
  State<MicroAreasScreen> createState() => _MicroAreasScreenState();
}

class _MicroAreasScreenState extends State<MicroAreasScreen> {
  late Future<_DadosDaTela> _future = _load();

  /// Registra o acesso *antes* de expor os dados — se o registro falhar, a
  /// tela cai no estado de erro em vez de mostrar dado sensível sem auditoria
  /// (PRD §4.2.2: acesso do Administrador precisa ser auditado).
  ///
  /// As três leituras vêm numa tarefa só, em série e depois do registro: a tela
  /// é uma página, e meia página carregada ao lado de outra pela metade (com a
  /// seção de ACS vazia, por exemplo) pareceria "não há nada" em vez de erro.
  Future<_DadosDaTela> _load() async {
    await widget.dataSource.recordAccess(actionType: 'view', resourceType: 'micro_areas');
    final areas = await widget.dataSource.fetchMicroAreas();
    final acs = await widget.dataSource.fetchAcs();
    final staff = widget.role == 'admin' ? await widget.dataSource.fetchStaff() : const <StaffSummary>[];
    return (areas: areas, acs: acs, staff: staff);
  }

  void _retry() => setState(() {
        _future = _load();
      });

  @override
  Widget build(BuildContext context) => FutureBuilder<_DadosDaTela>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return AdminAsyncError(error: snapshot.error, fallback: 'Não foi possível carregar as microáreas.', onRetry: _retry);
          }
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final dados = snapshot.data!;
          // Sessão vencida no meio de uma escrita da seção: as seções não têm o
          // `AdminSessionScope` no escopo delas, então recebem a ação pronta.
          final aoVencer = AdminSessionScope.maybeOf(context);
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text('Microáreas e vínculo ACS', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Território de cada microárea e gestão das contas de ACS — cadastro, vínculo, senha e MFA.'),
              const SizedBox(height: 16),
              for (final area in dados.areas)
                Card(
                  key: Key('micro_area_${area.id}'),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: _LinhaComSelo(
                    titulo: Text(area.name),
                    descricao: Text('ACS: ${area.acsName} (${area.acsEnrollmentId})'),
                    selo: Chip(
                      avatar: Icon(area.acsActive ? Icons.check_circle_outline : Icons.remove_circle_outline, size: 18),
                      label: Text(area.acsActive ? 'Ativo' : 'Sem ACS ativo'),
                      backgroundColor: AdminColors.surface,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              AcsManagementSection(
                dataSource: widget.dataSource,
                microAreas: dados.areas,
                acs: dados.acs,
                onRecarregar: _retry,
                aoVencerSessao: aoVencer,
              ),
              if (widget.role == 'admin') ...[
                const SizedBox(height: 28),
                const Divider(),
                const SizedBox(height: 16),
                StaffManagementSection(
                  dataSource: widget.dataSource,
                  staff: dados.staff,
                  onRecarregar: _retry,
                  aoVencerSessao: aoVencer,
                ),
              ],
            ],
          );
        },
      );
}

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({required this.dataSource, super.key});

  final AdminDataSource dataSource;

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  String? _microAreaFilter;
  AlertStatus? _statusFilter;
  late Future<void> _accessRecorded = widget.dataSource.recordAccess(actionType: 'view', resourceType: 'alerts');

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
        future: _accessRecorded,
        builder: (context, accessSnapshot) {
          if (accessSnapshot.hasError) {
            return AdminAsyncError(
              error: accessSnapshot.error,
              fallback: 'Não foi possível registrar o acesso a esta tela.',
              onRetry: () => setState(() {
                _accessRecorded = widget.dataSource.recordAccess(actionType: 'view', resourceType: 'alerts');
              }),
            );
          }
          if (accessSnapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return _AlertsList(dataSource: widget.dataSource, microAreaFilter: _microAreaFilter, statusFilter: _statusFilter, onFilterChanged: (microArea, status) => setState(() {
            _microAreaFilter = microArea;
            _statusFilter = status;
          }));
        },
      );
}

class _AlertsList extends StatelessWidget {
  const _AlertsList({
    required this.dataSource,
    required this.microAreaFilter,
    required this.statusFilter,
    required this.onFilterChanged,
  });

  final AdminDataSource dataSource;
  final String? microAreaFilter;
  final AlertStatus? statusFilter;
  final void Function(String? microArea, AlertStatus? status) onFilterChanged;

  /// Busca alertas e microáreas juntos. As opções do filtro vêm daqui, não de
  /// uma lista fixa no código — senão uma microárea nova (ou uma fonte real,
  /// no lugar do mock) devolveria alertas para um valor que não existe mais
  /// como opção selecionável (achado da revisão do PR).
  Future<({List<AlertSummary> alerts, List<MicroAreaSummary> microAreas})> _load() async {
    final alerts = await dataSource.fetchAlerts(microAreaId: microAreaFilter, status: statusFilter);
    final microAreas = await dataSource.fetchMicroAreas();
    return (alerts: alerts, microAreas: microAreas);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: _load(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return AdminAsyncError(error: snapshot.error, fallback: 'Não foi possível carregar os alertas.', onRetry: () => onFilterChanged(microAreaFilter, statusFilter));
          }
          final alerts = snapshot.data?.alerts ?? const [];
          final microAreas = snapshot.data?.microAreas ?? const [];
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text('Alertas da UBS', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Consulta somente leitura — nenhuma reclassificação de risco é permitida aqui.'),
              const SizedBox(height: 16),
              _FiltrosDeAlertas(
                microArea: DropdownButtonFormField<String?>(
                      key: const Key('alerts_micro_area_filter'),
                      initialValue: microAreaFilter,
                      isExpanded: true,
                      // DropdownButton exibe o hint (não o child do item) quando o
                      // valor selecionado é null — sem isso, "Todas" some do campo
                      // fechado assim que selecionado (achado da revisão do PR).
                      hint: const Text('Todas'),
                      decoration: const InputDecoration(labelText: 'Microárea'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Todas')),
                        for (final area in microAreas)
                          DropdownMenuItem(value: area.id, child: Text(area.name, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (value) => onFilterChanged(value, statusFilter),
                    ),
                status: DropdownButtonFormField<AlertStatus?>(
                      key: const Key('alerts_status_filter'),
                      initialValue: statusFilter,
                      isExpanded: true,
                      hint: const Text('Todos'),
                      decoration: const InputDecoration(labelText: 'Status'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Todos')),
                        for (final status in AlertStatus.values)
                          DropdownMenuItem(value: status, child: Text(statusLabel(status), overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (value) => onFilterChanged(microAreaFilter, value),
                    ),
              ),
              const SizedBox(height: 16),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Center(child: CircularProgressIndicator())
              else if (alerts.isEmpty)
                const Padding(padding: EdgeInsets.only(top: 24), child: Text('Nenhum alerta para o filtro selecionado.'))
              else
                for (final alert in alerts)
                  Card(
                    key: Key('alert_${alert.id}'),
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(border: Border(left: BorderSide(color: riskColor(alert.riskLevel), width: 4))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(alert.patientLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(alert.microAreaName),
                          const SizedBox(height: 6),
                          Text('Risco: ${riskLabel(alert.riskLevel)}', style: TextStyle(color: adminOnSurface(riskColor(alert.riskLevel)), fontWeight: FontWeight.bold)),
                          Text('Status: ${statusLabel(alert.status)}'),
                        ],
                      ),
                    ),
                  ),
            ],
          );
        },
      );
}

/// Os dois filtros de Alertas, lado a lado ou empilhados.
///
/// Lado a lado num celular cada campo recebia ~170dp: `isExpanded` e a elipse
/// dos itens evitavam o estouro, mas o rótulo do campo e o valor selecionado
/// passavam a disputar a mesma linha e "Microárea 12 — Zona Rural" virava
/// reticências. Não era um bug de layout — era um campo ilegível.
class _FiltrosDeAlertas extends StatelessWidget {
  const _FiltrosDeAlertas({required this.microArea, required this.status});

  final Widget microArea;
  final Widget status;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < AdminBreakpoints.stacked) {
            return Column(children: [microArea, const SizedBox(height: 12), status]);
          }
          return Row(
            children: [
              Expanded(child: microArea),
              const SizedBox(width: 12),
              Expanded(child: status),
            ],
          );
        },
      );
}

class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({required this.dataSource, super.key});

  final AdminDataSource dataSource;

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  late Future<void> _selfAuditRecorded = widget.dataSource.recordAccess(actionType: 'view', resourceType: 'audit_logs');

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
        future: _selfAuditRecorded,
        builder: (context, recordSnapshot) {
          if (recordSnapshot.hasError) {
            return AdminAsyncError(
              error: recordSnapshot.error,
              fallback: 'Não foi possível registrar o acesso a esta tela.',
              onRetry: () => setState(() {
                _selfAuditRecorded = widget.dataSource.recordAccess(actionType: 'view', resourceType: 'audit_logs');
              }),
            );
          }
          if (recordSnapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return FutureBuilder<List<AuditLogEntry>>(
            future: widget.dataSource.fetchAuditLogs(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return AdminAsyncError(error: snapshot.error, fallback: 'Não foi possível carregar os logs de auditoria.', onRetry: () => setState(() {}));
              }
              final entries = snapshot.data ?? const [];
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Text('Logs de auditoria', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text('Somente leitura. O próprio acesso a esta tela também é auditado. A coordenação vê apenas os registros dos autores com microárea na sua UBS.'),
                  const SizedBox(height: 16),
                  if (entries.isEmpty)
                    const Padding(padding: EdgeInsets.only(top: 24), child: Text('Nenhum acesso registrado ainda.'))
                  else
                    for (final entry in entries)
                      Card(
                        key: Key('audit_${entry.id}'),
                        margin: const EdgeInsets.only(bottom: 8),
                        child: _LinhaComSelo(
                          icone: const Icon(Icons.verified_user_outlined),
                          titulo: Text('${entry.actionType} • ${entry.resourceType}'),
                          descricao: Text('${entry.userLabel} — ${formatAuditTimestamp(entry.timestamp)}'),
                          selo: Text(entry.result),
                        ),
                      ),
                ],
              );
            },
          );
        },
      );
}

Widget _page(List<Widget> children) => ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
          ),
        ),
      ],
    );

/// `ListTile` cujo `trailing` desce para baixo da descrição em tela estreita.
///
/// Um `trailing` largo ("Sem ACS ativo") comia ~140dp dos ~320dp úteis de um
/// celular e espremia o título contra a borda. Abaixo do ponto de quebra o selo
/// vira mais uma linha do conteúdo, em vez de competir por largura.
///
/// Usado pelas telas de Microáreas e de Auditoria, que tinham exatamente o
/// mesmo formato e o mesmo problema.
class _LinhaComSelo extends StatelessWidget {
  const _LinhaComSelo({required this.titulo, required this.descricao, required this.selo, this.icone});

  final Widget titulo;
  final Widget descricao;
  final Widget selo;
  final Widget? icone;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final compacto = constraints.maxWidth < AdminBreakpoints.stacked;
          return ListTile(
            leading: icone,
            title: titulo,
            isThreeLine: compacto,
            subtitle: compacto
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      descricao,
                      const SizedBox(height: 8),
                      Align(alignment: Alignment.centerLeft, child: selo),
                    ],
                  )
                : descricao,
            trailing: compacto ? null : selo,
          );
        },
      );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final valor = Text(value, style: const TextStyle(fontWeight: FontWeight.bold));
            // Rótulos como "TMRAV (tempo médio de resposta)" quebram em três
            // linhas ao lado do valor num celular. Empilhados, o rótulo usa a
            // largura toda e lê como uma frase.
            if (constraints.maxWidth < AdminBreakpoints.stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Text(label), valor],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(label)),
                const SizedBox(width: 12),
                Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            );
          },
        ),
      );
}

