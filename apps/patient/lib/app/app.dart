import 'package:flutter/material.dart';
import 'package:sinalacs_patient/app/patient_theme.dart';

class SinalAcsApp extends StatelessWidget {
  const SinalAcsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SinalACS Paciente',
      debugShowCheckedModeBanner: false,
      theme: buildPatientTheme(),
      home: const PatientLoginScreen(),
    );
  }
}

class PatientLoginScreen extends StatelessWidget {
  const PatientLoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const _PatientHeader(
        eyebrow: 'Módulo de acesso',
        title: 'Autenticação inclusiva',
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const CircleAvatar(
                          radius: 32,
                          backgroundColor: Color(0x332CCDC0),
                          child: Icon(Icons.key_rounded, size: 32),
                        ),
                        const SizedBox(height: 16),
                        const Text('SinalACS', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        const Text('Acesso sem senha', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        const Text(
                          'Use CPF e data de nascimento para receber o código de acesso.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 24),
                        const TextField(
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: 'CPF do paciente', hintText: '000.000.000-00'),
                        ),
                        const SizedBox(height: 16),
                        const TextField(
                          keyboardType: TextInputType.datetime,
                          decoration: InputDecoration(labelText: 'Data de nascimento', hintText: 'DD/MM/AAAA'),
                        ),
                        const SizedBox(height: 20),
                        Semantics(
                          label: 'Entrar na triagem do paciente',
                          button: true,
                          container: true,
                          child: SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              key: const Key('enter_button'),
                              onPressed: () => Navigator.of(context).pushReplacement(
                                MaterialPageRoute(builder: (_) => const PatientHomeShell(initialDestination: PatientDestination.triage)),
                              ),
                              style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
                              child: const Text('Entrar sem senha'),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _showPrototypeMessage(context, 'Leitura de QR Code será disponibilizada com o onboarding integrado.'),
                            icon: const Icon(Icons.qr_code_scanner_outlined),
                            label: const Text('Escanear QR Code do ACS'),
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
      ),
    );
  }
}

enum PatientDestination { emergency, triage, questions, profile, status, reminders }

class PatientHomeShell extends StatefulWidget {
  const PatientHomeShell({super.key, this.initialDestination = PatientDestination.emergency});

  final PatientDestination initialDestination;

  @override
  State<PatientHomeShell> createState() => _PatientHomeShellState();
}

class _PatientHomeShellState extends State<PatientHomeShell> {
  late PatientDestination _destination;

  @override
  void initState() {
    super.initState();
    _destination = widget.initialDestination;
  }

  void _select(PatientDestination destination) => setState(() => _destination = destination);

  @override
  Widget build(BuildContext context) {
    final content = switch (_destination) {
      PatientDestination.emergency => const EmergencyScreen(),
      PatientDestination.triage => TriageScreen(onComplete: () => _select(PatientDestination.status)),
      PatientDestination.questions => const QuestionsScreen(),
      PatientDestination.profile => const ClinicalProfileScreen(),
      PatientDestination.status => const StatusScreen(),
      PatientDestination.reminders => const RemindersScreen(),
    };
    final title = switch (_destination) {
      PatientDestination.emergency => 'Alerta de urgência',
      PatientDestination.triage => 'Triagem rápida',
      PatientDestination.questions => 'Canal de dúvidas',
      PatientDestination.profile => 'Perfil clínico',
      PatientDestination.status => 'Acompanhamento',
      PatientDestination.reminders => 'Lembretes',
    };

    return Scaffold(
      appBar: _PatientHeader(eyebrow: 'SinalACS paciente', title: title),
      body: SafeArea(child: content),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navigationIndex(_destination),
        onDestinationSelected: (index) {
          if (index == 3) {
            _showMoreDestinations(context, _select);
            return;
          }
          _select([PatientDestination.emergency, PatientDestination.triage, PatientDestination.status][index]);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.warning_amber_outlined), selectedIcon: Icon(Icons.warning_amber), label: 'Urgência'),
          NavigationDestination(icon: Icon(Icons.assignment_outlined), selectedIcon: Icon(Icons.assignment), label: 'Triagem'),
          NavigationDestination(icon: Icon(Icons.timeline_outlined), selectedIcon: Icon(Icons.timeline), label: 'Status'),
          NavigationDestination(icon: Icon(Icons.more_horiz), label: 'Mais'),
        ],
      ),
    );
  }

  int _navigationIndex(PatientDestination destination) => switch (destination) {
    PatientDestination.emergency => 0,
    PatientDestination.triage => 1,
    PatientDestination.status => 2,
    _ => 3,
  };
}

class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  String _state = 'Pronto para enviar';

  Future<void> _sendAlert() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar alerta de emergência?'),
        content: const Text('O alerta será registrado com a localização disponível neste dispositivo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirmar alerta')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _state = 'Alerta enfileirado localmente');
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('Em uma situação grave, envie um alerta imediato à sua equipe de saúde.', textAlign: TextAlign.center),
        const SizedBox(height: 28),
        Center(
          child: Semantics(
            label: 'Enviar alerta de emergência',
            button: true,
            child: SizedBox(
              width: 208,
              height: 208,
              child: FilledButton(
                key: const Key('panic_button'),
                onPressed: _sendAlert,
                style: FilledButton.styleFrom(
                  backgroundColor: PatientColors.danger,
                  shape: const CircleBorder(),
                ),
                child: const Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.warning_amber_rounded, size: 52), SizedBox(height: 8), Text('EMERGÊNCIA', style: TextStyle(fontWeight: FontWeight.bold))]),
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [const Icon(Icons.location_on_outlined), const SizedBox(height: 8), const Text('A localização disponível será anexada ao alerta.', textAlign: TextAlign.center), const SizedBox(height: 8), Text(_state, style: const TextStyle(color: PatientColors.accent, fontWeight: FontWeight.bold))]))),
      ],
    );
  }
}

class TriageScreen extends StatefulWidget {
  const TriageScreen({super.key, this.onComplete});
  final VoidCallback? onComplete;

  @override
  State<TriageScreen> createState() => _TriageScreenState();
}

class _TriageScreenState extends State<TriageScreen> {
  int _step = 0;
  final List<String?> _answers = List<String?>.filled(3, null);
  final _questions = const [
    ('Qual o sintoma principal?', ['Falta de ar ou cansaço intenso', 'Tontura ou pressão alterada', 'Dor localizada ou febre moderada', 'Dúvida de rotina ou medicação']),
    ('O sintoma começou de forma súbita?', ['Sim, começou de repente', 'Não, começou aos poucos']),
    ('Há algum sinal de agravamento?', ['Dor no peito ou sangramento', 'Sem sinal de agravamento']),
  ];

  String get _risk => _answers.any((answer) => answer == 'Dor no peito ou sangramento' || answer == 'Falta de ar ou cansaço intenso') ? 'Risco: Vermelho' : _answers.any((answer) => answer != null) ? 'Risco: Amarelo' : 'Risco: Verde';

  @override
  Widget build(BuildContext context) {
    final question = _questions[_step];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Passo ${_step + 1} de 3', style: const TextStyle(color: PatientColors.accent, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: (_step + 1) / 3),
        const SizedBox(height: 24),
        Text(question.$1, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        ...question.$2.map((answer) => Card(child: RadioListTile<String>(key: Key(_step == 0 && answer.startsWith('Falta') ? 'difficulty_breathing' : _step == 2 && answer.startsWith('Dor') ? 'chest_pain' : 'triage_${_step}_${question.$2.indexOf(answer)}'), value: answer, groupValue: _answers[_step], onChanged: (value) => setState(() => _answers[_step] = value), title: Text(answer)))),
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('submit_triage'),
          onPressed: _answers[_step] == null ? null : () {
            if (_step < 2) setState(() => _step++); else widget.onComplete?.call();
          },
          style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
          child: Text(_step == 2 ? 'Concluir triagem' : 'Próxima pergunta'),
        ),
        if (_step == 2) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_risk, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
      ],
    );
  }
}

class QuestionsScreen extends StatefulWidget {
  const QuestionsScreen({super.key});
  @override
  State<QuestionsScreen> createState() => _QuestionsScreenState();
}

class _QuestionsScreenState extends State<QuestionsScreen> {
  final _controller = TextEditingController();
  final _messages = <String>['UBS Central: Como podemos ajudar hoje?'];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: _messages.length,
            itemBuilder: (_, index) => Align(
              alignment: index.isEven ? Alignment.centerLeft : Alignment.centerRight,
              child: Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(_messages[index]))),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(child: TextField(controller: _controller, decoration: const InputDecoration(hintText: 'Digite sua mensagem'))),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Enviar mensagem',
                onPressed: () {
                  if (_controller.text.isEmpty) return;
                  setState(() {
                    _messages.add('Você: ${_controller.text}');
                    _messages.add('Resposta automática: Para informações sobre vacinação, procure a UBS Central.');
                    _controller.clear();
                  });
                },
                icon: const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class ClinicalProfileScreen extends StatefulWidget {
  const ClinicalProfileScreen({super.key});
  @override
  State<ClinicalProfileScreen> createState() => _ClinicalProfileScreenState();
}

class _ClinicalProfileScreenState extends State<ClinicalProfileScreen> {
  final conditions = <String, bool>{'Hipertensão arterial': true, 'Diabetes mellitus tipo 2': true, 'Uso contínuo de insulina': false, 'Gestante na família': false};

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Condições de saúde e histórico', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Essas informações apoiam a priorização clínica.'),
        const SizedBox(height: 16),
        ...conditions.entries.map((entry) => Card(child: CheckboxListTile(value: entry.value, onChanged: (value) => setState(() => conditions[entry.key] = value ?? false), title: Text(entry.key), subtitle: Text(entry.value ? 'Ativo' : 'Inativo')))),
        const SizedBox(height: 16),
        FilledButton(onPressed: () => _showPrototypeMessage(context, 'Alterações salvas apenas neste protótipo.'), child: const Text('Salvar alterações no perfil')),
      ],
    );
  }
}

class StatusScreen extends StatelessWidget {
  const StatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('Solicitação de visita #4082', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                Text('Triagem Amarela • criada hoje às 09:30'),
                SizedBox(height: 28),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_StatusStep('Enviado', true), _StatusStep('Visualizado', true), _StatusStep('Em análise', true), _StatusStep('Agendado', false)]),
                SizedBox(height: 28),
                Divider(),
                SizedBox(height: 12),
                Text('Última atualização pelo ACS', style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text('Chamado recebido e priorizado na fila da microárea.'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusStep extends StatelessWidget { const _StatusStep(this.label, this.done); final String label; final bool done; @override Widget build(BuildContext context) => Column(children: [Icon(done ? Icons.check_circle : Icons.calendar_today_outlined, color: done ? PatientColors.accent : Colors.white54), const SizedBox(height: 6), SizedBox(width: 65, child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)))]); }

class RemindersScreen extends StatefulWidget { const RemindersScreen({super.key}); @override State<RemindersScreen> createState() => _RemindersScreenState(); }
class _RemindersScreenState extends State<RemindersScreen> {
  final reminders = <String, bool>{'08:00 - Losartana 50 mg': true, '14:00 - Metformina 850 mg': false, 'Quarta-feira - Pesagem de rotina': false};

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Alarmes e medicamentos', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), IconButton(tooltip: 'Novo alarme', onPressed: () => _showPrototypeMessage(context, 'Criação de lembrete será persistida quando as notificações locais forem integradas.'), icon: const Icon(Icons.add_alarm_outlined))]),
        const SizedBox(height: 16),
        ...reminders.entries.map((entry) => Card(child: SwitchListTile(value: entry.value, onChanged: (value) => setState(() => reminders[entry.key] = value), title: Text(entry.key), subtitle: Text(entry.value ? 'Ativo' : 'Pausado')))),
      ],
    );
  }
}

class _PatientHeader extends StatelessWidget implements PreferredSizeWidget {
  const _PatientHeader({required this.eyebrow, required this.title}); final String eyebrow; final String title;
  @override Size get preferredSize => const Size.fromHeight(72);
  @override Widget build(BuildContext context) => AppBar(title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(eyebrow.toUpperCase(), style: const TextStyle(fontSize: 10, color: PatientColors.accent, fontWeight: FontWeight.bold)), Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))]), actions: const [Padding(padding: EdgeInsets.only(right: 16), child: CircleAvatar(child: Icon(Icons.person_outline)))]) ;
}

void _showMoreDestinations(BuildContext context, ValueChanged<PatientDestination> select) {
  showModalBottomSheet<void>(context: context, builder: (sheetContext) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [ListTile(leading: const Icon(Icons.chat_bubble_outline), title: const Text('Dúvidas'), onTap: () { Navigator.pop(sheetContext); select(PatientDestination.questions); }), ListTile(leading: const Icon(Icons.person_outline), title: const Text('Perfil clínico'), onTap: () { Navigator.pop(sheetContext); select(PatientDestination.profile); }), ListTile(leading: const Icon(Icons.alarm_outlined), title: const Text('Lembretes'), onTap: () { Navigator.pop(sheetContext); select(PatientDestination.reminders); })])));
}

void _showPrototypeMessage(BuildContext context, String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));