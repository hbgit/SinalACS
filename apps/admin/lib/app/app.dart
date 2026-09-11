import 'package:flutter/material.dart';
import 'package:sinalacs_admin/app/admin_theme.dart';
import 'package:sinalacs_admin/core/data/admin_data_source.dart';
import 'package:sinalacs_admin/core/data/mock_admin_data_source.dart';

class SinalAdminApp extends StatelessWidget {
  SinalAdminApp({super.key, AdminDataSource? dataSource}) : dataSource = dataSource ?? MockAdminDataSource();

  final AdminDataSource dataSource;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'SinalACS Admin',
        debugShowCheckedModeBanner: false,
        theme: buildAdminTheme(),
        home: LoginScreen(dataSource: dataSource),
      );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({required this.dataSource, super.key});

  final AdminDataSource dataSource;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _matricula = TextEditingController(text: 'admin.dev');
  final _senha = TextEditingController(text: '123456');

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
                    border: Border.all(color: AdminColors.yellow),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.science_outlined, color: AdminColors.yellow),
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
                              onPressed: _login,
                              child: const Text('Entrar'),
                            ),
                          ),
                        ),
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

class IndicatorsScreen extends StatelessWidget {
  const IndicatorsScreen({required this.dataSource, super.key});

  final AdminDataSource dataSource;

  @override
  Widget build(BuildContext context) => FutureBuilder<DashboardIndicators>(
        future: dataSource.fetchDashboardIndicators(),
        builder: (context, snapshot) {
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
  @override
  void initState() {
    super.initState();
    widget.dataSource.recordAccess(actionType: 'view', resourceType: 'micro_areas');
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<MicroAreaSummary>>(
        future: widget.dataSource.fetchMicroAreas(),
        builder: (context, snapshot) {
          final areas = snapshot.data ?? const [];
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
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
                      label: Text(area.acsActive ? 'Ativo' : 'Sem ACS ativo'),
                      backgroundColor: area.acsActive ? AdminColors.green.withValues(alpha: 0.2) : AdminColors.surface,
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

  @override
  void initState() {
    super.initState();
    widget.dataSource.recordAccess(actionType: 'view', resourceType: 'alerts');
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<AlertSummary>>(
        future: widget.dataSource.fetchAlerts(microAreaName: _microAreaFilter, status: _statusFilter),
        builder: (context, snapshot) {
          final alerts = snapshot.data ?? const [];
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
                      initialValue: _microAreaFilter,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Microárea'),
                      items: const [
                        DropdownMenuItem(value: null, child: Text('Todas')),
                        DropdownMenuItem(
                          value: 'Microárea 12 — Zona Rural',
                          child: Text('Microárea 12 — Zona Rural', overflow: TextOverflow.ellipsis),
                        ),
                        DropdownMenuItem(
                          value: 'Microárea 07 — Centro',
                          child: Text('Microárea 07 — Centro', overflow: TextOverflow.ellipsis),
                        ),
                        DropdownMenuItem(
                          value: 'Microárea 03 — Vila Esperança',
                          child: Text('Microárea 03 — Vila Esperança', overflow: TextOverflow.ellipsis),
                        ),
                      ],
                      onChanged: (value) => setState(() => _microAreaFilter = value),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<AlertStatus?>(
                      key: const Key('alerts_status_filter'),
                      initialValue: _statusFilter,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Status'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Todos')),
                        for (final status in AlertStatus.values)
                          DropdownMenuItem(value: status, child: Text(statusLabel(status), overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (value) => setState(() => _statusFilter = value),
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
  late final Future<void> _selfAuditRecorded;

  @override
  void initState() {
    super.initState();
    _selfAuditRecorded = widget.dataSource.recordAccess(actionType: 'view', resourceType: 'audit_logs');
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
        future: _selfAuditRecorded,
        builder: (context, recordSnapshot) {
          if (recordSnapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return FutureBuilder<List<AuditLogEntry>>(
            future: widget.dataSource.fetchAuditLogs(),
            builder: (context, snapshot) {
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
