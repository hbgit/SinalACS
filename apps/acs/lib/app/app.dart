import 'package:flutter/material.dart';
import 'package:sinalacs_acs/app/acs_theme.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';

class SinalAcsApp extends StatelessWidget {
  const SinalAcsApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'SinalACS ACS',
        debugShowCheckedModeBanner: false,
        theme: buildAcsTheme(),
        home: const LoginScreen(),
      );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _matricula = TextEditingController(text: 'ACS-001');
  final _senha = TextEditingController(text: '123456');
  @override
  void dispose() { _matricula.dispose(); _senha.dispose(); super.dispose(); }
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
          Semantics(label: 'Entrar no painel de priorização', button: true, container: true, child: SizedBox(width: double.infinity, child: FilledButton(key: const Key('login_button'), style: FilledButton.styleFrom(minimumSize: const Size(48, 52)), onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AcsHomeShell())), child: const Text('Entrar com credenciais')))),
        ]))),
      ]),
    )),
  );
}

enum AcsDestination { area, queue, map, visit, escalation, geofencing, notices }

class AcsHomeShell extends StatefulWidget { const AcsHomeShell({super.key}); @override State<AcsHomeShell> createState() => _AcsHomeShellState(); }
class _AcsHomeShellState extends State<AcsHomeShell> {
  AcsDestination destination = AcsDestination.queue;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const _Header('ACS • offline ready', 'Painel operacional'),
    body: SafeArea(child: switch (destination) {
      AcsDestination.area => const TerritorializationScreen(),
      AcsDestination.queue => DashboardScreen(onEscalate: () => setState(() => destination = AcsDestination.escalation), onVisit: () => setState(() => destination = AcsDestination.visit)),
      AcsDestination.map => const MapScreen(),
      AcsDestination.visit => const VisitRegistrationScreen(patientName: 'Maria Oliveira'),
      AcsDestination.escalation => const EscalationScreen(),
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

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, this.onEscalate, this.onVisit}); final VoidCallback? onEscalate; final VoidCallback? onVisit;
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: [
    const Text('Painel de Priorização', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), const SizedBox(height: 4), const Text('Fila ordenada por risco clínico'), const SizedBox(height: 16),
    _card('Maria Oliveira, 72a', 'Maria Souza', 'Risco: Vermelho', 'Falta de ar aguda relatada via app.', AcsColors.red, 'Acionar SAMU / Atender', onEscalate), const SizedBox(height: 12),
    _card('João Pereira, 65a', null, 'Risco: Amarelo', 'Glicemia descompensada na triagem.', AcsColors.yellow, 'Iniciar rota de visita', onVisit), const SizedBox(height: 12),
    _card('Ana Costa, 28a', null, 'Risco: Verde', 'Dúvida sobre vacinação.', AcsColors.green, 'Ver dúvida / responder', () => _message(context, 'Canal de dúvidas demonstrativo.')),
  ]);
  Widget _card(String name, String? alias, String risk, String detail, Color color, String action, VoidCallback? onPressed) => Card(child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(border: Border(left: BorderSide(color: color, width: 4))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(name, style: const TextStyle(fontWeight: FontWeight.bold)), if (alias != null) Text(alias), const SizedBox(height: 6), Text(risk, style: TextStyle(color: color, fontWeight: FontWeight.bold)), const SizedBox(height: 6), Text(detail), const SizedBox(height: 12), SizedBox(width: double.infinity, child: FilledButton(onPressed: onPressed, style: FilledButton.styleFrom(backgroundColor: color), child: Text(action)))])));
}

class MapScreen extends StatelessWidget { const MapScreen({super.key}); @override Widget build(BuildContext context) => _page([Container(height: 220, decoration: BoxDecoration(color: AcsColors.surface, borderRadius: BorderRadius.circular(8)), child: const Stack(children: [Align(alignment: Alignment(-.55, -.4), child: Icon(Icons.location_on, color: AcsColors.red, size: 38)), Align(alignment: Alignment(.55, .1), child: Icon(Icons.location_on, color: AcsColors.yellow, size: 38)), Align(alignment: Alignment(-.1, .65), child: Icon(Icons.location_on, color: AcsColors.green, size: 38)), Center(child: Text('Mapa demonstrativo'))])), const SizedBox(height: 16), const Text('Pinos representam a prioridade clínica no território.', textAlign: TextAlign.center), const SizedBox(height: 16), FilledButton(onPressed: () => _message(context, 'Traçado de rota depende da integração de mapas.'), child: const Text('Traçar rota eficiente'))]); }

class VisitRegistrationScreen extends StatefulWidget { const VisitRegistrationScreen({required this.patientName, super.key}); final String patientName; @override State<VisitRegistrationScreen> createState() => _VisitRegistrationScreenState(); }
class _VisitRegistrationScreenState extends State<VisitRegistrationScreen> { String outcome = 'Realizada com sucesso'; final notes = TextEditingController(); @override void dispose() { notes.dispose(); super.dispose(); } Future<void> _save() async { await OfflineVisitQueue().add(OfflineVisitRecord(patientName: widget.patientName, risk: 'VERMELHO', status: 'PENDENTE')); if (mounted) _message(context, 'Visita salva e enfileirada localmente para sincronização.'); } @override Widget build(BuildContext context) => _page([Text(widget.patientName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), const SizedBox(height: 16), DropdownButtonFormField<String>(value: outcome, decoration: const InputDecoration(labelText: 'Status do atendimento'), items: const ['Realizada com sucesso', 'Paciente ausente', 'Recusou atendimento'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) => setState(() => outcome = v!)), const SizedBox(height: 16), TextField(controller: notes, maxLines: 4, decoration: const InputDecoration(labelText: 'Observações de campo')), const SizedBox(height: 20), FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined), label: const Text('Salvar e enfileirar sincronização'))]); }

class EscalationScreen extends StatelessWidget { const EscalationScreen({super.key}); @override Widget build(BuildContext context) => _page([const Text('Escalonamento rápido', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), const SizedBox(height: 16), const _InfoRow('Paciente', 'Maria Oliveira, 72a'), const _InfoRow('Risco', 'Vermelho - falta de ar aguda'), const _InfoRow('Endereço', 'Rua das Flores, 120'), const SizedBox(height: 20), FilledButton.icon(onPressed: () => _message(context, 'Discagem não está integrada neste protótipo.'), style: FilledButton.styleFrom(backgroundColor: AcsColors.red), icon: const Icon(Icons.call), label: const Text('Ligar para o SAMU (192)')), const SizedBox(height: 12), OutlinedButton(onPressed: () => _message(context, 'Encaminhamento será integrado à UBS.'), child: const Text('Encaminhar para UBS Central'))]); }
class GeofencingScreen extends StatelessWidget { const GeofencingScreen({super.key}); @override Widget build(BuildContext context) => _page([const Icon(Icons.location_searching, size: 44), const SizedBox(height: 16), const Text('Check-in passivo', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), const SizedBox(height: 8), const Text('Proximidade demonstrativa: residência de Maria Oliveira, a 18 metros.'), const SizedBox(height: 20), FilledButton(onPressed: () => _message(context, 'Use a tela Visita para registrar o atendimento.'), child: const Text('Abrir formulário da visita'))]); }
class NoticesScreen extends StatefulWidget { const NoticesScreen({super.key}); @override State<NoticesScreen> createState() => _NoticesScreenState(); }
class _NoticesScreenState extends State<NoticesScreen> { final notice = TextEditingController(); @override void dispose() { notice.dispose(); super.dispose(); } @override Widget build(BuildContext context) => _page([const Text('Aviso comunitário', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), const SizedBox(height: 16), const TextField(decoration: InputDecoration(labelText: 'Público-alvo', hintText: 'Pacientes com condições crônicas')), const SizedBox(height: 16), TextField(controller: notice, maxLines: 4, decoration: const InputDecoration(labelText: 'Mensagem')), const SizedBox(height: 20), FilledButton(onPressed: () => _message(context, 'Envio depende da integração de notificações push.'), child: const Text('Preparar aviso'))]); }

Widget _page(List<Widget> children) => ListView(padding: const EdgeInsets.all(20), children: [Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children)))]);
class _InfoRow extends StatelessWidget { const _InfoRow(this.label, this.value); final String label; final String value; @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label), Flexible(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.bold)))])); }
class _Header extends StatelessWidget implements PreferredSizeWidget { const _Header(this.eyebrow, this.title); final String eyebrow; final String title; @override Size get preferredSize => const Size.fromHeight(72); @override Widget build(BuildContext context) => AppBar(title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(eyebrow.toUpperCase(), style: const TextStyle(fontSize: 10, color: AcsColors.accent, fontWeight: FontWeight.bold)), Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))]), actions: const [Padding(padding: EdgeInsets.only(right: 12), child: Chip(label: Text('Offline ready')))]); }
void _message(BuildContext context, String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));