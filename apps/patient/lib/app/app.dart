import 'package:flutter/material.dart';
import 'package:sinalacs_client/sinalacs_client.dart' show RiskLevel;
import 'package:sinalacs_patient/app/patient_theme.dart';
import 'package:sinalacs_patient/core/network/backend_client.dart';
import 'package:sinalacs_patient/core/network/backend_scope.dart';
import 'package:sinalacs_patient/core/network/idempotency.dart';
import 'package:sinalacs_patient/core/privacy/location_hash.dart';

class SinalAcsApp extends StatefulWidget {
  const SinalAcsApp({super.key, this.backend});

  /// Injetável para teste. Em execução normal é o [BackendClient] real.
  final PatientBackend? backend;

  @override
  State<SinalAcsApp> createState() => _SinalAcsAppState();
}

class _SinalAcsAppState extends State<SinalAcsApp> {
  late final PatientBackend _backend = widget.backend ?? BackendClient();

  @override
  void dispose() {
    // Só fecha o que este widget criou; um backend injetado é de quem injetou.
    if (widget.backend == null) _backend.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BackendScope(
      backend: _backend,
      child: MaterialApp(
        title: 'SinalACS Paciente',
        debugShowCheckedModeBanner: false,
        theme: buildPatientTheme(),
        home: const PatientLoginScreen(),
      ),
    );
  }
}

class PatientLoginScreen extends StatefulWidget {
  const PatientLoginScreen({super.key});

  @override
  State<PatientLoginScreen> createState() => _PatientLoginScreenState();
}

class _PatientLoginScreenState extends State<PatientLoginScreen> {
  bool _busy = false;
  String? _error;

  /// Autentica de verdade contra `auth.developmentLogin` e só navega em caso de
  /// sucesso. Antes a tela navegava incondicionalmente, ignorando o que era
  /// digitado — não havia como saber se o backend estava sequer alcançável.
  Future<void> _enter() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await BackendScope.of(context).login();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const PatientHomeShell(
            initialDestination: PatientDestination.triage,
          ),
        ),
      );
    } on BackendFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = failure.message;
      });
    }
  }

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
                              onPressed: _busy ? null : _enter,
                              style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
                              child: _busy
                                  ? const SizedBox(
                                      height: 22,
                                      width: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Text('Entrar sem senha'),
                            ),
                          ),
                        ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(
                              key: const Key('login_error'),
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: PatientColors.danger,
                                fontWeight: FontWeight.bold,
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
  bool _busy = false;

  /// Chave da tentativa corrente.
  ///
  /// Gerada uma única vez por confirmação e mantida enquanto o envio não
  /// conclui: se a pessoa tocar de novo depois de uma falha de rede, o servidor
  /// reconhece a mesma chave e devolve o mesmo alerta em vez de criar um
  /// segundo. Só é descartada quando o alerta é aceito.
  String? _attemptKey;

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

    final backend = BackendScope.of(context);
    final key = _attemptKey ??= newIdempotencyKey();

    setState(() {
      _busy = true;
      _state = 'Enviando alerta...';
    });

    try {
      final result = await backend.createRedAlert(
        idempotencyKey: key,
        // A localização real entra aqui quando o permissionamento de GPS for
        // integrado; o contrato só aceita o hash, então a coordenada crua nunca
        // sai do dispositivo (LGPD).
        locationHash: unknownLocationHash,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _attemptKey = null;
        _state = 'Alerta recebido pela equipe'
            '${result.published ? '' : ' — aguardando a rede para notificar'}';
      });
    } on BackendFailure catch (failure) {
      if (!mounted) return;
      // A chave NÃO é limpa aqui: o retry precisa reusar a mesma tentativa.
      setState(() {
        _busy = false;
        _state = failure.message;
      });
    }
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
                onPressed: _busy ? null : _sendAlert,
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

/// Um sintoma do formulário, ligado ao parâmetro correspondente de
/// `triage.evaluate`.
///
/// As perguntas são exatamente as seis que o motor do servidor conhece. Antes
/// eram três perguntas de múltipla escolha que **não** mapeavam para o contrato,
/// e o risco era calculado no cliente por comparação de string — duas regras de
/// risco no mesmo produto, o que viola o determinismo exigido pelo PRD (INV-02).
enum TriageSymptom {
  chestPain('chest_pain', 'Você está com dor no peito?'),
  difficultyBreathing('difficulty_breathing', 'Você está com falta de ar?'),
  bleeding('bleeding', 'Você está com algum sangramento?'),
  severeWeakness('severe_weakness', 'Você está com fraqueza intensa ou desmaio?'),
  fever('fever', 'Você está com febre?'),
  persistentVomiting('persistent_vomiting', 'Você está com vômitos que não param?');

  const TriageSymptom(this.key, this.question);

  final String key;
  final String question;
}

class _TriageScreenState extends State<TriageScreen> {
  static const _symptoms = TriageSymptom.values;

  int _step = 0;
  final Map<TriageSymptom, bool> _answers = <TriageSymptom, bool>{};
  bool _busy = false;
  String? _error;

  /// Risco devolvido pelo servidor. `null` enquanto a triagem não foi concluída.
  ///
  /// Não existe cálculo de risco neste arquivo, e não deve passar a existir.
  RiskLevel? _risk;

  bool get _isLastStep => _step == _symptoms.length - 1;

  Future<void> _submit() async {
    final answer = _answers[_symptoms[_step]];
    if (answer == null) return;

    if (!_isLastStep) {
      setState(() => _step++);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final risk = await BackendScope.of(context).evaluateTriage(
        chestPain: _answers[TriageSymptom.chestPain] ?? false,
        difficultyBreathing: _answers[TriageSymptom.difficultyBreathing] ?? false,
        fever: _answers[TriageSymptom.fever] ?? false,
        persistentVomiting: _answers[TriageSymptom.persistentVomiting] ?? false,
        bleeding: _answers[TriageSymptom.bleeding] ?? false,
        severeWeakness: _answers[TriageSymptom.severeWeakness] ?? false,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _risk = risk;
      });
    } on BackendFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = failure.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final risk = _risk;
    if (risk != null) return _TriageResult(risk: risk, onContinue: widget.onComplete);

    final symptom = _symptoms[_step];
    final answer = _answers[symptom];

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Passo ${_step + 1} de ${_symptoms.length}',
          style: const TextStyle(color: PatientColors.accent, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: (_step + 1) / _symptoms.length),
        const SizedBox(height: 24),
        Text(symptom.question, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        RadioGroup<bool>(
          groupValue: answer,
          onChanged: (value) => setState(() => _answers[symptom] = value ?? false),
          child: Column(
            children: [
              Card(
                child: RadioListTile<bool>(
                  key: Key(symptom.key),
                  value: true,
                  title: const Text('Sim'),
                ),
              ),
              Card(
                child: RadioListTile<bool>(
                  key: Key('${symptom.key}_no'),
                  value: false,
                  title: const Text('Não'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('submit_triage'),
          onPressed: answer == null || _busy ? null : _submit,
          style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
          child: _busy
              ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_isLastStep ? 'Concluir triagem' : 'Próxima pergunta'),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              key: const Key('triage_error'),
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: PatientColors.danger, fontWeight: FontWeight.bold),
            ),
          ),
      ],
    );
  }
}

/// Exibe a classificação que veio do servidor.
///
/// A cor é sinal clínico, nunca decoração: vermelho/amarelo/verde mapeiam
/// estritamente o [RiskLevel].
class _TriageResult extends StatelessWidget {
  const _TriageResult({required this.risk, this.onContinue});

  final RiskLevel risk;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final (label, color, guidance) = switch (risk) {
      RiskLevel.red => (
          'Risco: Vermelho',
          PatientColors.danger,
          'Sua equipe de saúde foi avisada com prioridade máxima. '
              'Se piorar, ligue para o SAMU (192).',
        ),
      RiskLevel.yellow => (
          'Risco: Amarelo',
          const Color(0xFFE0A800),
          'Sua solicitação foi priorizada. O agente de saúde entrará em contato.',
        ),
      RiskLevel.green => (
          'Risco: Verde',
          PatientColors.accent,
          'Sem sinais de urgência. Sua solicitação entrou na fila de rotina.',
        ),
    };

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(Icons.verified_outlined, size: 44, color: color),
                const SizedBox(height: 16),
                Text(
                  key: const Key('triage_risk'),
                  label,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color),
                ),
                const SizedBox(height: 12),
                Text(guidance, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                const Text(
                  'Classificação feita pelo protocolo da equipe de saúde.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('triage_continue'),
          onPressed: onContinue,
          style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
          child: const Text('Acompanhar solicitação'),
        ),
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
      children: const [
        Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Solicitação de visita #4082', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                Text('Triagem Vermelha • criada hoje às 09:30'),
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