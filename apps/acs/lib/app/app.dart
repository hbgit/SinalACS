import 'package:flutter/material.dart';
import 'package:sinalacs_acs/app/acs_theme.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/network/backend_scope.dart';
import 'package:sinalacs_acs/core/services/alert_feed.dart';
import 'package:sinalacs_acs/core/services/alert_queue.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';

class SinalAcsApp extends StatefulWidget {
  const SinalAcsApp({super.key, this.backend, this.feedBuilder, this.visitQueue});

  /// Injetáveis para teste. Em execução normal são as implementações reais.
  final AcsBackend? backend;
  final AlertFeed Function(AlertQueue queue)? feedBuilder;
  final OfflineVisitQueue? visitQueue;

  @override
  State<SinalAcsApp> createState() => _SinalAcsAppState();
}

class _SinalAcsAppState extends State<SinalAcsApp> {
  late final AcsBackend _backend = widget.backend ?? BackendClient();

  /// Uma única fila por execução do app.
  ///
  /// A tela de visita antes fazia `OfflineVisitQueue()` a cada gravação — uma
  /// instância nova por visita, descartada no retorno do callback. A visita
  /// simplesmente sumia.
  late final OfflineVisitQueue _visitQueue = widget.visitQueue ?? OfflineVisitQueue();

  @override
  void dispose() {
    if (widget.backend == null) _backend.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BackendScope(
        backend: _backend,
        child: MaterialApp(
          title: 'SinalACS ACS',
          debugShowCheckedModeBanner: false,
          theme: buildAcsTheme(),
          home: LoginScreen(
            feedBuilder: widget.feedBuilder,
            visitQueue: _visitQueue,
          ),
        ),
      );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.feedBuilder, this.visitQueue});

  final AlertFeed Function(AlertQueue queue)? feedBuilder;
  final OfflineVisitQueue? visitQueue;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Sem credencial pré-preenchida: o formulário antes vinha com 'ACS-001' e
  // '123456' embutidos, e o botão navegava sem olhar para nenhum dos dois.
  final _matricula = TextEditingController();
  final _senha = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() { _matricula.dispose(); _senha.dispose(); super.dispose(); }

  /// Autentica contra `auth.developmentLogin` e só então abre o painel.
  Future<void> _enter() async {
    setState(() { _busy = true; _error = null; });

    try {
      final session = await BackendScope.of(context).login();
      final microAreaId = session.microAreaId;
      if (microAreaId == null) {
        // Sem microárea não há território, e sem território não há fila: é
        // preferível barrar a entrada a abrir um painel que não pode filtrar.
        setState(() {
          _busy = false;
          _error = 'Este acesso não está vinculado a uma microárea.';
        });
        return;
      }
      if (!mounted) return;

      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => AcsHomeShell(
          microAreaId: microAreaId,
          acsId: session.userId,
          feedBuilder: widget.feedBuilder,
          visitQueue: widget.visitQueue,
        ),
      ));
    } on BackendFailure catch (failure) {
      if (!mounted) return;
      setState(() { _busy = false; _error = failure.message; });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const _Header('Segurança e rastreabilidade', 'Acesso institucional'),
    body: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 600),
      child: ListView(padding: const EdgeInsets.all(24), children: [
        Card(child: Padding(padding: const EdgeInsets.all(24), child: Column(children: [
          const CircleAvatar(radius: 32, child: Text('ACS')),
          const SizedBox(height: 16),
          const Text('SinalACS', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Acesso profissional', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          TextField(key: const Key('matricula_field'), controller: _matricula, decoration: const InputDecoration(labelText: 'Matrícula / CNS')),
          const SizedBox(height: 16),
          TextField(key: const Key('senha_field'), controller: _senha, obscureText: true, decoration: const InputDecoration(labelText: 'Senha de acesso')),
          const SizedBox(height: 20),
          Semantics(label: 'Entrar no painel de priorização', button: true, container: true, child: SizedBox(width: double.infinity, child: FilledButton(
            key: const Key('login_button'),
            style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
            onPressed: _busy ? null : _enter,
            child: _busy
                ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Entrar com credenciais'),
          ))),
          if (_error != null) Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(key: const Key('login_error'), _error!, textAlign: TextAlign.center, style: const TextStyle(color: AcsColors.red, fontWeight: FontWeight.bold)),
          ),
        ]))),
      ]),
    )),
  );
}

enum AcsDestination { area, queue, map, visit, escalation, geofencing, notices }

class AcsHomeShell extends StatefulWidget {
  const AcsHomeShell({
    required this.microAreaId,
    required this.acsId,
    super.key,
    this.feedBuilder,
    this.visitQueue,
  });

  final String microAreaId;
  final String acsId;
  final AlertFeed Function(AlertQueue queue)? feedBuilder;
  final OfflineVisitQueue? visitQueue;

  @override
  State<AcsHomeShell> createState() => _AcsHomeShellState();
}

class _AcsHomeShellState extends State<AcsHomeShell> {
  AcsDestination destination = AcsDestination.queue;

  late final AlertQueue _queue = AlertQueue(microAreaId: widget.microAreaId);
  late final AlertFeed _feed =
      (widget.feedBuilder ?? (queue) => MqttAlertFeed(queue: queue))(_queue);

  bool _brokerConnected = false;
  String? _feedError;
  PrioritizedAlert? _selected;

  @override
  void initState() {
    super.initState();
    _connectFeed();
  }

  /// Assina o tópico da microárea da sessão.
  ///
  /// Falhar aqui não derruba o painel, mas **precisa ficar visível**: um ACS que
  /// não sabe que parou de receber alertas é o pior modo de falha do produto.
  Future<void> _connectFeed() async {
    try {
      await _feed.start(microAreaId: widget.microAreaId, acsId: widget.acsId);
      if (!mounted) return;
      setState(() {
        _brokerConnected = _feed.isConnected;
        _feedError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _brokerConnected = false;
        _feedError = 'Sem conexão com a central de alertas.';
      });
    }
  }

  Future<void> _acknowledge(PrioritizedAlert alert) async {
    try {
      final result = await BackendScope.of(context).acknowledge(alertId: alert.alertId);
      if (!mounted) return;
      if (result.acknowledged) _queue.markAcknowledged(alert.alertId);
      _message(context, result.acknowledged
          ? 'Recebimento confirmado à central.'
          : 'A central não reconheceu este alerta.');
    } on BackendFailure catch (failure) {
      if (!mounted) return;
      _message(context, failure.message);
    }
  }

  @override
  void dispose() {
    _feed.stop();
    _queue.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: _Header('ACS • ${_brokerConnected ? 'em linha' : 'sem conexão'}', 'Painel operacional', connected: _brokerConnected),
    body: SafeArea(child: switch (destination) {
      AcsDestination.area => const TerritorializationScreen(),
      AcsDestination.queue => DashboardScreen(
          queue: _queue,
          feedError: _feedError,
          onAcknowledge: _acknowledge,
          onEscalate: (alert) => setState(() { _selected = alert; destination = AcsDestination.escalation; }),
          onVisit: (alert) => setState(() { _selected = alert; destination = AcsDestination.visit; }),
        ),
      AcsDestination.map => const MapScreen(),
      AcsDestination.visit => VisitRegistrationScreen(
          alert: _selected,
          queue: widget.visitQueue ?? OfflineVisitQueue(),
        ),
      AcsDestination.escalation => EscalationScreen(alert: _selected),
      AcsDestination.geofencing => const GeofencingScreen(),
      AcsDestination.notices => const NoticesScreen(),
    }),
    bottomNavigationBar: NavigationBar(
      selectedIndex: destination.index <= 3 ? destination.index : 4,
      onDestinationSelected: (index) { if (index == 4) { _more(context); } else { setState(() => destination = AcsDestination.values[index]); } },
      destinations: const [NavigationDestination(icon: Icon(Icons.storage_outlined), label: 'Área'), NavigationDestination(icon: Icon(Icons.grid_view_outlined), label: 'Fila'), NavigationDestination(icon: Icon(Icons.map_outlined), label: 'Mapa'), NavigationDestination(icon: Icon(Icons.assignment_outlined), label: 'Visita'), NavigationDestination(icon: Icon(Icons.more_horiz), label: 'Mais')],
    ),
  );
  void _more(BuildContext context) => showModalBottomSheet<void>(context: context, builder: (sheet) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
    _moreItem(sheet, Icons.call_outlined, 'Acionamento', AcsDestination.escalation),
    _moreItem(sheet, Icons.location_searching, 'Geofencing', AcsDestination.geofencing),
    _moreItem(sheet, Icons.campaign_outlined, 'Avisos à comunidade', AcsDestination.notices),
  ])));
  Widget _moreItem(BuildContext sheet, IconData icon, String label, AcsDestination value) => ListTile(leading: Icon(icon), title: Text(label), onTap: () { Navigator.pop(sheet); setState(() => destination = value); });
}

class TerritorializationScreen extends StatelessWidget { const TerritorializationScreen({super.key}); @override Widget build(BuildContext context) => _page([const Text('Microárea 12 - Zona Rural', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), const SizedBox(height: 12), const _InfoRow('Pacientes sincronizados', '142 cadastrados'), const _InfoRow('Cache local', 'Atualizado há 10 min'), const SizedBox(height: 20), FilledButton(onPressed: () => _message(context, 'Atualização será integrada à API central.'), child: const Text('Atualizar dados da microárea'))]); }

/// Painel de priorização alimentado pelos alertas que chegam do broker.
///
/// Antes eram três cartões fixos no código. A fila agora é a [AlertQueue], que
/// ordena de forma determinística por risco e, no mesmo risco, por antiguidade.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    required this.queue,
    super.key,
    this.feedError,
    this.onAcknowledge,
    this.onEscalate,
    this.onVisit,
  });

  final AlertQueue queue;
  final String? feedError;
  final void Function(PrioritizedAlert alert)? onAcknowledge;
  final void Function(PrioritizedAlert alert)? onEscalate;
  final void Function(PrioritizedAlert alert)? onVisit;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: queue,
        builder: (context, _) {
          final alerts = queue.alerts;
          return ListView(padding: const EdgeInsets.all(20), children: [
            const Text('Painel de Priorização', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Fila ordenada por risco clínico'),
            if (feedError != null) Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Card(
                color: AcsColors.red.withValues(alpha: 0.15),
                child: ListTile(
                  key: const Key('feed_error'),
                  leading: const Icon(Icons.cloud_off_outlined, color: AcsColors.red),
                  title: Text(feedError!, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Novos alertas podem não estar chegando.'),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (alerts.isEmpty) const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(children: [
                  Icon(Icons.inbox_outlined, size: 40),
                  SizedBox(height: 12),
                  Text('Nenhum alerta na sua microárea agora.', textAlign: TextAlign.center),
                ]),
              ),
            ),
            for (final alert in alerts) Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _AlertCard(
                alert: alert,
                onAcknowledge: onAcknowledge,
                onEscalate: onEscalate,
                onVisit: onVisit,
              ),
            ),
          ]);
        },
      );
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert, this.onAcknowledge, this.onEscalate, this.onVisit});

  final PrioritizedAlert alert;
  final void Function(PrioritizedAlert alert)? onAcknowledge;
  final void Function(PrioritizedAlert alert)? onEscalate;
  final void Function(PrioritizedAlert alert)? onVisit;

  /// Cor é sinal clínico, nunca decoração: mapeia estritamente o risco vindo do
  /// servidor.
  (Color, String) get _risk => switch (alert.riskLevel.toLowerCase()) {
        'red' || 'vermelho' => (AcsColors.red, 'Risco: Vermelho'),
        'yellow' || 'amarelo' => (AcsColors.yellow, 'Risco: Amarelo'),
        'green' || 'verde' => (AcsColors.green, 'Risco: Verde'),
        _ => (AcsColors.accent, 'Risco: não classificado'),
      };

  @override
  Widget build(BuildContext context) {
    final (color, label) = _risk;
    final isRed = alert.riskLevel.toLowerCase() == 'red' || alert.riskLevel.toLowerCase() == 'vermelho';

    return Card(
      key: Key('alert_${alert.alertId}'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(border: Border(left: BorderSide(color: color, width: 4))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Identificação direta do paciente não trafega no envelope MQTT
          // (LGPD): o alerta carrega identificadores, não nome nem endereço.
          Text('Paciente ${alert.patientId.substring(0, 8)}', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('Recebido às ${_time(alert.triggeredAt)} • local ${alert.locationHash}'),
          if (alert.acknowledged) const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Row(children: [
              Icon(Icons.check_circle, size: 16, color: AcsColors.green),
              SizedBox(width: 6),
              Text('Recebimento confirmado', style: TextStyle(color: AcsColors.green)),
            ]),
          ),
          const SizedBox(height: 12),
          if (!alert.acknowledged) SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: Key('ack_${alert.alertId}'),
              onPressed: onAcknowledge == null ? null : () => onAcknowledge!(alert),
              style: FilledButton.styleFrom(backgroundColor: color, minimumSize: const Size(48, 52)),
              child: const Text('Confirmar recebimento'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: isRed
                  ? (onEscalate == null ? null : () => onEscalate!(alert))
                  : (onVisit == null ? null : () => onVisit!(alert)),
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 52)),
              child: Text(isRed ? 'Acionar SAMU / Atender' : 'Iniciar rota de visita'),
            ),
          ),
        ]),
      ),
    );
  }

  String _time(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class MapScreen extends StatelessWidget { const MapScreen({super.key}); @override Widget build(BuildContext context) => _page([Container(height: 220, decoration: BoxDecoration(color: AcsColors.surface, borderRadius: BorderRadius.circular(8)), child: const Stack(children: [Align(alignment: Alignment(-.55, -.4), child: Icon(Icons.location_on, color: AcsColors.red, size: 38)), Align(alignment: Alignment(.55, .1), child: Icon(Icons.location_on, color: AcsColors.yellow, size: 38)), Align(alignment: Alignment(-.1, .65), child: Icon(Icons.location_on, color: AcsColors.green, size: 38)), Center(child: Text('Mapa demonstrativo'))])), const SizedBox(height: 16), const Text('Pinos representam a prioridade clínica no território.', textAlign: TextAlign.center), const SizedBox(height: 16), FilledButton(onPressed: () => _message(context, 'Traçado de rota depende da integração de mapas.'), child: const Text('Traçar rota eficiente'))]); }

class VisitRegistrationScreen extends StatefulWidget {
  const VisitRegistrationScreen({required this.queue, super.key, this.alert});

  /// A fila é recebida pronta, não construída aqui: uma instância por gravação
  /// descartava a visita assim que o callback retornava.
  final OfflineVisitQueue queue;
  final PrioritizedAlert? alert;

  @override
  State<VisitRegistrationScreen> createState() => _VisitRegistrationScreenState();
}

class _VisitRegistrationScreenState extends State<VisitRegistrationScreen> {
  String outcome = 'Realizada com sucesso';
  final notes = TextEditingController();

  @override
  void dispose() { notes.dispose(); super.dispose(); }

  String get _patientLabel {
    final alert = widget.alert;
    return alert == null ? 'Visita sem alerta vinculado' : 'Paciente ${alert.patientId.substring(0, 8)}';
  }

  Future<void> _save() async {
    await widget.queue.add(OfflineVisitRecord(
      patientName: _patientLabel,
      risk: widget.alert?.riskLevel ?? 'desconhecido',
      status: 'PENDENTE',
      outcome: outcome,
    ));
    if (!mounted) return;
    _message(context, 'Visita salva e enfileirada localmente para sincronização.');
  }

  @override
  Widget build(BuildContext context) => _page([
    Text(_patientLabel, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
    const SizedBox(height: 16),
    DropdownButtonFormField<String>(initialValue: outcome, decoration: const InputDecoration(labelText: 'Status do atendimento'), items: const ['Realizada com sucesso', 'Paciente ausente', 'Recusou atendimento'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) => setState(() => outcome = v!)),
    const SizedBox(height: 16),
    TextField(controller: notes, maxLines: 4, decoration: const InputDecoration(labelText: 'Observações de campo')),
    const SizedBox(height: 20),
    FilledButton.icon(key: const Key('save_visit'), onPressed: _save, icon: const Icon(Icons.save_outlined), label: const Text('Salvar e enfileirar sincronização')),
  ]);
}

class EscalationScreen extends StatelessWidget {
  const EscalationScreen({super.key, this.alert});

  final PrioritizedAlert? alert;

  @override
  Widget build(BuildContext context) {
    final current = alert;
    return _page([
      const Text('Escalonamento rápido', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 16),
      _InfoRow('Paciente', current == null ? '—' : current.patientId.substring(0, 8)),
      _InfoRow('Risco', current?.riskLevel ?? '—'),
      // O envelope MQTT não carrega endereço: só o hash da localização (LGPD).
      _InfoRow('Local (hash)', current?.locationHash ?? '—'),
      const SizedBox(height: 20),
      FilledButton.icon(onPressed: () => _message(context, 'Discagem não está integrada neste protótipo.'), style: FilledButton.styleFrom(backgroundColor: AcsColors.red), icon: const Icon(Icons.call), label: const Text('Ligar para o SAMU (192)')),
      const SizedBox(height: 12),
      OutlinedButton(onPressed: () => _message(context, 'Encaminhamento será integrado à UBS.'), child: const Text('Encaminhar para UBS Central')),
    ]);
  }
}
class GeofencingScreen extends StatelessWidget { const GeofencingScreen({super.key}); @override Widget build(BuildContext context) => _page([const Icon(Icons.location_searching, size: 44), const SizedBox(height: 16), const Text('Check-in passivo', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), const SizedBox(height: 8), const Text('Proximidade demonstrativa: residência de Maria Oliveira, a 18 metros.'), const SizedBox(height: 20), FilledButton(onPressed: () => _message(context, 'Use a tela Visita para registrar o atendimento.'), child: const Text('Abrir formulário da visita'))]); }
class NoticesScreen extends StatefulWidget { const NoticesScreen({super.key}); @override State<NoticesScreen> createState() => _NoticesScreenState(); }
class _NoticesScreenState extends State<NoticesScreen> { final notice = TextEditingController(); @override void dispose() { notice.dispose(); super.dispose(); } @override Widget build(BuildContext context) => _page([const Text('Aviso comunitário', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), const SizedBox(height: 16), const TextField(decoration: InputDecoration(labelText: 'Público-alvo', hintText: 'Pacientes com condições crônicas')), const SizedBox(height: 16), TextField(controller: notice, maxLines: 4, decoration: const InputDecoration(labelText: 'Mensagem')), const SizedBox(height: 20), FilledButton(onPressed: () => _message(context, 'Envio depende da integração de notificações push.'), child: const Text('Preparar aviso'))]); }

Widget _page(List<Widget> children) => ListView(padding: const EdgeInsets.all(20), children: [Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children)))]);
class _InfoRow extends StatelessWidget { const _InfoRow(this.label, this.value); final String label; final String value; @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label), Flexible(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.bold)))])); }
class _Header extends StatelessWidget implements PreferredSizeWidget {
  const _Header(this.eyebrow, this.title, {this.connected});

  final String eyebrow;
  final String title;

  /// Estado da conexão com o broker. `null` fora do painel.
  ///
  /// Fica no cabeçalho de propósito: um ACS precisa saber, sem procurar, que
  /// parou de receber alertas.
  final bool? connected;

  @override
  Size get preferredSize => const Size.fromHeight(72);

  @override
  Widget build(BuildContext context) => AppBar(
    title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(eyebrow.toUpperCase(), style: const TextStyle(fontSize: 10, color: AcsColors.accent, fontWeight: FontWeight.bold)),
      Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    ]),
    actions: [
      Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Chip(
          key: const Key('broker_status'),
          avatar: connected == null ? null : Icon(
            connected! ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
            size: 18,
            color: connected! ? AcsColors.green : AcsColors.red,
          ),
          label: Text(switch (connected) {
            null => 'Offline ready',
            true => 'Alertas em tempo real',
            false => 'Sem central',
          }),
        ),
      ),
    ],
  );
}
void _message(BuildContext context, String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));