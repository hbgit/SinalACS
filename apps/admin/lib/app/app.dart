import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:sinalacs_admin/app/admin_theme.dart';
import 'package:sinalacs_admin/core/data/admin_data_source.dart';
import 'package:sinalacs_admin/core/data/mock_admin_data_source.dart';

class SinalAdminApp extends StatelessWidget {
  SinalAdminApp({super.key, AdminDataSource? dataSource, this.devLoginEnabled}) : dataSource = dataSource ?? MockAdminDataSource();

  final AdminDataSource dataSource;

  /// Repassado para [LoginScreen]; `null` mantém o default (`kDebugMode`).
  final bool? devLoginEnabled;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'SinalACS Admin',
        debugShowCheckedModeBanner: false,
        theme: buildAdminTheme(),
        home: LoginScreen(dataSource: dataSource, devLoginEnabled: devLoginEnabled),
      );
}

/// Login local (não chama `auth.developmentLogin`).
///
/// Investigado antes de decidir: `backend/sinalacs_server/lib/src/endpoints/auth_endpoint.dart`
/// só aceita `role: 'patient'` ou `role: 'acs'` — não existe usuário fixo de
/// desenvolvimento para `admin`, então a chamada real falharia com
/// AlertValidationException. Ligar isso de verdade exige uma mudança no
/// backend (fora do escopo desta issue); ver descrição do PR.
class LoginScreen extends StatefulWidget {
  /// O banner "ambiente de desenvolvimento" não é um controle de acesso — só
  /// avisa. Sem isso, `_login` deixaria qualquer pessoa entrar em produção
  /// sem senha (achado da revisão do PR). O default (`kDebugMode`, `false`
  /// em builds profile/release) desativa de verdade o bypass fora de dev;
  /// o parâmetro existe para os testes poderem exercitar os dois estados.
  const LoginScreen({required this.dataSource, super.key, bool? devLoginEnabled}) : devLoginEnabled = devLoginEnabled ?? kDebugMode;

  final AdminDataSource dataSource;
  final bool devLoginEnabled;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _matricula = TextEditingController();
  final _senha = TextEditingController();

  @override
  void dispose() {
    _matricula.dispose();
    _senha.dispose();
    super.dispose();
  }

  void _login() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => AdminHomeShell(dataSource: widget.dataSource)),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const _Header('Backoffice SinalACS', 'Acesso administrativo'),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Container(
                  key: const Key('dev_banner'),
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AdminColors.surfaceRaised,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AdminColors.accent),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.science_outlined, color: AdminColors.accent),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Ambiente de desenvolvimento — sem autenticação institucional real (SSO/gov.br).',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const CircleAvatar(radius: 32, child: Text('ADM')),
                        const SizedBox(height: 16),
                        const Text('SinalACS', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        const Text('Backoffice administrativo', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 20),
                        TextField(
                          key: const Key('matricula_field'),
                          controller: _matricula,
                          decoration: const InputDecoration(labelText: 'Matrícula / CNS'),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          key: const Key('senha_field'),
                          controller: _senha,
                          obscureText: true,
                          decoration: const InputDecoration(labelText: 'Senha de acesso'),
                        ),
                        const SizedBox(height: 20),
                        Semantics(
                          label: 'Entrar no backoffice administrativo',
                          button: true,
                          container: true,
                          child: SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              key: const Key('login_button'),
                              style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
                              onPressed: widget.devLoginEnabled ? _login : null,
                              child: const Text('Entrar'),
                            ),
                          ),
                        ),
                        if (!widget.devLoginEnabled) ...[
                          const SizedBox(height: 12),
                          const Text(
                            'Login de desenvolvimento desativado nesta build (fora do modo debug).',
                            key: Key('dev_login_disabled_notice'),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

enum AdminDestination { indicators, microAreas, alerts, auditLog }

extension on AdminDestination {
  String get label => switch (this) {
        AdminDestination.indicators => 'Indicadores',
        AdminDestination.microAreas => 'Microáreas',
        AdminDestination.alerts => 'Alertas',
        AdminDestination.auditLog => 'Auditoria',
      };

  IconData get icon => switch (this) {
        AdminDestination.indicators => Icons.dashboard_outlined,
        AdminDestination.microAreas => Icons.map_outlined,
        AdminDestination.alerts => Icons.warning_amber_outlined,
        AdminDestination.auditLog => Icons.fact_check_outlined,
      };
}

class AdminHomeShell extends StatefulWidget {
  const AdminHomeShell({required this.dataSource, super.key});

  final AdminDataSource dataSource;

  @override
  State<AdminHomeShell> createState() => _AdminHomeShellState();
}

class _AdminHomeShellState extends State<AdminHomeShell> {
  AdminDestination destination = AdminDestination.indicators;

  Widget _content() => switch (destination) {
        AdminDestination.indicators => IndicatorsScreen(dataSource: widget.dataSource),
        AdminDestination.microAreas => MicroAreasScreen(dataSource: widget.dataSource),
        AdminDestination.alerts => AlertsScreen(dataSource: widget.dataSource),
        AdminDestination.auditLog => AuditLogScreen(dataSource: widget.dataSource),
      };

  void _select(int index) => setState(() => destination = AdminDestination.values[index]);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final content = SafeArea(child: _content());
          // Backoffice é desktop-first (spec/PRD_system.md §2.1): NavigationRail
          // acima de 640px, NavigationBar abaixo — mesmo ThemeData nos dois.
          if (constraints.maxWidth >= 640) {
            return Scaffold(
              appBar: const _Header('Backoffice • admin.dev', 'Painel administrativo'),
              body: Row(
                children: [
                  NavigationRail(
                    key: const Key('admin_navigation_rail'),
                    selectedIndex: destination.index,
                    onDestinationSelected: _select,
                    labelType: NavigationRailLabelType.all,
                    destinations: [
                      for (final value in AdminDestination.values)
                        NavigationRailDestination(icon: Icon(value.icon), label: Text(value.label)),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: content),
                ],
              ),
            );
          }
          return Scaffold(
            appBar: const _Header('Backoffice • admin.dev', 'Painel administrativo'),
            body: content,
            bottomNavigationBar: NavigationBar(
              key: const Key('admin_navigation_bar'),
              selectedIndex: destination.index,
              onDestinationSelected: _select,
              destinations: [
                for (final value in AdminDestination.values)
                  NavigationDestination(icon: Icon(value.icon), label: value.label),
              ],
            ),
          );
        },
      );
}

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

String statusLabel(AlertStatus status) => switch (status) {
      AlertStatus.pending => 'Pendente',
      AlertStatus.acknowledged => 'Reconhecido',
      AlertStatus.resolved => 'Resolvido',
      AlertStatus.escalated => 'Escalonado',
    };

/// Estado de erro compartilhado pelas telas assíncronas, com retry.
///
/// Sem isso, um `FutureBuilder` que falha fica com `hasData == false` para
/// sempre (spinner infinito) ou, pior, cai no mesmo ramo de "vazio" que os
/// dados realmente vazios — escondendo uma falha de rede/backend como se
/// não houvesse nada para mostrar (achado da revisão do Copilot no PR).
class _AsyncError extends StatelessWidget {
  const _AsyncError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 32, color: Colors.white70),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Tentar novamente')),
            ],
          ),
        ),
      );
}

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
            return _AsyncError(message: 'Não foi possível carregar os indicadores.', onRetry: _retry);
          }
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final data = snapshot.data!;
          return _page([
            const Text('Painel de Indicadores', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Contadores por risco clínico da UBS'),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final level in RiskLevel.values)
                  _CounterCard(
                    key: Key('risk_counter_${level.name}'),
                    label: riskLabel(level),
                    value: '${data.countsByRisk[level] ?? 0}',
                    color: riskColor(level),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            const Text('Alertas vermelhos', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _InfoRow('Abertos (pendentes)', '${data.openRedAlerts}'),
            _InfoRow('Reconhecidos', '${data.acknowledgedRedAlerts}'),
            _InfoRow('TMRAV (tempo médio de resposta)', '${data.tmravSeconds}s'),
          ]);
        },
      );
}

class _CounterCard extends StatelessWidget {
  const _CounterCard({required this.label, required this.value, required this.color, super.key});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 160,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AdminColors.surfaceRaised,
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: color, width: 4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          ],
        ),
      );
}

class MicroAreasScreen extends StatefulWidget {
  const MicroAreasScreen({required this.dataSource, super.key});

  final AdminDataSource dataSource;

  @override
  State<MicroAreasScreen> createState() => _MicroAreasScreenState();
}

class _MicroAreasScreenState extends State<MicroAreasScreen> {
  late Future<List<MicroAreaSummary>> _future = _load();

  /// Registra o acesso *antes* de expor os dados — se o registro falhar, a
  /// tela cai no estado de erro em vez de mostrar dado sensível sem auditoria
  /// (PRD §4.2.2: acesso do Administrador precisa ser auditado).
  Future<List<MicroAreaSummary>> _load() async {
    await widget.dataSource.recordAccess(actionType: 'view', resourceType: 'micro_areas');
    return widget.dataSource.fetchMicroAreas();
  }

  void _retry() => setState(() {
        _future = _load();
      });

  @override
  Widget build(BuildContext context) => FutureBuilder<List<MicroAreaSummary>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _AsyncError(message: 'Não foi possível carregar as microáreas.', onRetry: _retry);
          }
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final areas = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text('Microáreas e vínculo ACS', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Listagem somente leitura — edição de vínculo fica para uma próxima issue.'),
              const SizedBox(height: 16),
              for (final area in areas)
                Card(
                  key: Key('micro_area_${area.id}'),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    title: Text(area.name),
                    subtitle: Text('ACS: ${area.acsName} (${area.acsEnrollmentId})'),
                    trailing: Chip(
                      avatar: Icon(area.acsActive ? Icons.check_circle_outline : Icons.remove_circle_outline, size: 18),
                      label: Text(area.acsActive ? 'Ativo' : 'Sem ACS ativo'),
                      backgroundColor: AdminColors.surface,
                    ),
                  ),
                ),
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
            return _AsyncError(
              message: 'Não foi possível registrar o acesso a esta tela.',
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
    final alerts = await dataSource.fetchAlerts(microAreaName: microAreaFilter, status: statusFilter);
    final microAreas = await dataSource.fetchMicroAreas();
    return (alerts: alerts, microAreas: microAreas);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: _load(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _AsyncError(message: 'Não foi possível carregar os alertas.', onRetry: () => onFilterChanged(microAreaFilter, statusFilter));
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
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
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
                          DropdownMenuItem(value: area.name, child: Text(area.name, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (value) => onFilterChanged(value, statusFilter),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<AlertStatus?>(
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
                ],
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
                          Text('Risco: ${riskLabel(alert.riskLevel)}', style: TextStyle(color: riskColor(alert.riskLevel), fontWeight: FontWeight.bold)),
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
            return _AsyncError(
              message: 'Não foi possível registrar o acesso a esta tela.',
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
                return _AsyncError(message: 'Não foi possível carregar os logs de auditoria.', onRetry: () => setState(() {}));
              }
              final entries = snapshot.data ?? const [];
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Text('Logs de auditoria', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text('Somente leitura. O próprio acesso do administrador a esta tela também é auditado.'),
                  const SizedBox(height: 16),
                  if (entries.isEmpty)
                    const Padding(padding: EdgeInsets.only(top: 24), child: Text('Nenhum acesso registrado ainda.'))
                  else
                    for (final entry in entries)
                      Card(
                        key: Key('audit_${entry.id}'),
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const Icon(Icons.verified_user_outlined),
                          title: Text('${entry.actionType} • ${entry.resourceType}'),
                          subtitle: Text('${entry.userLabel} — ${entry.timestamp}'),
                          trailing: Text(entry.result),
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

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(label)),
            const SizedBox(width: 12),
            Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      );
}

class _Header extends StatelessWidget implements PreferredSizeWidget {
  const _Header(this.eyebrow, this.title);

  final String eyebrow;
  final String title;

  @override
  Size get preferredSize => const Size.fromHeight(72);

  @override
  Widget build(BuildContext context) => AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(eyebrow.toUpperCase(), style: const TextStyle(fontSize: 10, color: AdminColors.accent, fontWeight: FontWeight.bold)),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: const [Padding(padding: EdgeInsets.only(right: 12), child: Chip(label: Text('Acesso auditado')))],
      );
}
