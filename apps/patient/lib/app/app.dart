import 'package:flutter/material.dart';
import 'package:sinalacs_client/sinalacs_client.dart' show RiskLevel;
import 'package:sinalacs_patient/app/patient_theme.dart';
import 'package:sinalacs_patient/core/network/backend_client.dart';
import 'package:sinalacs_patient/core/network/backend_scope.dart';
import 'package:sinalacs_patient/core/network/idempotency.dart';
import 'package:sinalacs_patient/core/privacy/location_hash.dart';

class SinalAcsApp extends StatefulWidget {
  const SinalAcsApp({super.key, this.backend, this.locationReader});

  /// Injetável para teste. Em execução normal é o [BackendClient] real.
  final PatientBackend? backend;

  /// Injetável para teste. Em execução normal é o [GeolocatorLocationReader]
  /// real, que fala com o GPS do aparelho.
  final LocationReader? locationReader;

  @override
  State<SinalAcsApp> createState() => _SinalAcsAppState();
}

class _SinalAcsAppState extends State<SinalAcsApp> {
  late final PatientBackend _backend = widget.backend ?? BackendClient();
  late final LocationReader _locationReader =
      widget.locationReader ?? const GeolocatorLocationReader();

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
      child: LocationScope(
        reader: _locationReader,
        child: MaterialApp(
          title: 'SinalACS Paciente',
          debugShowCheckedModeBanner: false,
          theme: buildPatientTheme(),
          home: const PatientLoginScreen(),
        ),
      ),
    );
  }
}

/// Disponibiliza o [LocationReader] para a árvore de widgets.
///
/// Mesmo padrão de `BackendScope`: a tela não constrói o próprio leitor de
/// GPS, o que permite injetar um duplo em teste hermético sem tocar canal de
/// plataforma.
class LocationScope extends InheritedWidget {
  const LocationScope({
    required this.reader,
    required super.child,
    super.key,
  });

  final LocationReader reader;

  static LocationReader of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<LocationScope>();
    assert(scope != null, 'Nenhum LocationScope acima deste widget.');
    return scope!.reader;
  }

  @override
  bool updateShouldNotify(LocationScope oldWidget) => reader != oldWidget.reader;
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
                            // SC 4.1.3: o erro aparece sem mover o foco — sem
                            // `liveRegion` o leitor de tela nunca saberia que
                            // o login falhou.
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                key: const Key('login_error'),
                                _error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: PatientColors.dangerOnSurface,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            key: const Key('start_onboarding_button'),
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const OnboardingScreen()),
                            ),
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

/// Tela de onboarding: consome o convite de uso único gerado pelo ACS e
/// grava os 3 consentimentos por finalidade (LGPD-RF02) antes de ativar a
/// sessão do paciente (RF02).
///
/// O campo de texto recebe o valor do token do QR Code — a leitura por
/// câmera é apenas um jeito alternativo de preencher o mesmo campo, não uma
/// dependência nova desta tela (fora de escopo aqui).
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _tokenController = TextEditingController();

  // Nenhum consentimento vem pré-marcado: a decisão de produto (§2.2) exige
  // aceite ou recusa explícitos para cada finalidade, inclusive a obrigatória.
  bool _healthDataConsent = false;
  bool _remindersConsent = false;
  bool _pushConsent = false;

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _complete() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) return;

    // Verificação client-side do consentimento obrigatório: evita uma
    // chamada de rede que o backend rejeitaria de qualquer forma, com a
    // mesma mensagem que `OnboardingService.completeEnrollment` usa.
    if (!_healthDataConsent) {
      setState(() {
        _error = 'O consentimento para processamento de dados de saúde é obrigatório.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await BackendScope.of(context).completeEnrollment(
        token: token,
        healthDataConsent: _healthDataConsent,
        remindersConsent: _remindersConsent,
        pushConsent: _pushConsent,
      );
      if (!mounted) return;
      // Mesmo caminho que `_PatientLoginScreenState._enter()` já usa para
      // entrar na navegação principal — a sessão já está em `BackendScope`,
      // não há estado novo para duplicar aqui.
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
    final tokenEmpty = _tokenController.text.trim().isEmpty;
    return Scaffold(
      appBar: const _PatientHeader(
        eyebrow: 'Convite do ACS',
        title: 'Concluir cadastro',
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
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Cole ou digite o código do convite recebido do agente '
                          'comunitário de saúde. A leitura do QR Code preenche o '
                          'mesmo campo.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          key: const Key('onboarding_token_field'),
                          controller: _tokenController,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(labelText: 'Código do convite'),
                        ),
                        const SizedBox(height: 20),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Consentimentos', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        CheckboxListTile(
                          key: const Key('onboarding_consent_health'),
                          value: _healthDataConsent,
                          onChanged: (value) => setState(() => _healthDataConsent = value ?? false),
                          controlAffinity: ListTileControlAffinity.leading,
                          title: const Text(
                            'Processamento de dados de saúde para triagem/alerta (obrigatório)',
                          ),
                        ),
                        CheckboxListTile(
                          key: const Key('onboarding_consent_reminders'),
                          value: _remindersConsent,
                          onChanged: (value) => setState(() => _remindersConsent = value ?? false),
                          controlAffinity: ListTileControlAffinity.leading,
                          title: const Text('Envio de lembretes locais'),
                        ),
                        CheckboxListTile(
                          key: const Key('onboarding_consent_push'),
                          value: _pushConsent,
                          onChanged: (value) => setState(() => _pushConsent = value ?? false),
                          controlAffinity: ListTileControlAffinity.leading,
                          title: const Text('Recebimento de avisos segmentados por push'),
                        ),
                        const SizedBox(height: 20),
                        Semantics(
                          label: 'Concluir cadastro',
                          button: true,
                          container: true,
                          child: SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              key: const Key('complete_enrollment_button'),
                              onPressed: (_busy || tokenEmpty) ? null : _complete,
                              style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
                              child: _busy
                                  ? const SizedBox(
                                      height: 22,
                                      width: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Text('Concluir cadastro'),
                            ),
                          ),
                        ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            // SC 4.1.3: mesmo padrão do erro de login — sem
                            // `liveRegion` um leitor de tela não saberia que o
                            // onboarding falhou.
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                key: const Key('onboarding_error'),
                                _error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: PatientColors.dangerOnSurface,
                                  fontWeight: FontWeight.bold,
                                ),
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

  /// Texto exibido no cartão de localização.
  ///
  /// Precisa dizer explicitamente quando a localização não pôde ser lida —
  /// nunca mascarar isso silenciosamente atrás de um hash inventado (L-02).
  String _locationStatus = 'A localização disponível será anexada ao alerta.';

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
    final locationReader = LocationScope.of(context);
    final key = _attemptKey ??= newIdempotencyKey();

    setState(() {
      _busy = true;
      _state = 'Enviando alerta...';
    });

    // Lida com o GPS antes de falar com o servidor: se demorar, é o timeout
    // do próprio leitor que limita a espera, não o alerta inteiro.
    final reading = await locationReader.read();
    if (!mounted) return;

    final String locationHash;
    final String? locationCell;
    final String locationStatus;
    switch (reading) {
      case LocationAvailable(:final hash, :final cell):
        locationHash = hash;
        locationCell = cell;
        locationStatus = 'Localização anexada ao alerta.';
      case LocationUnavailable():
        // Alerta vermelho nunca pode ser perdido em silêncio por falta de
        // GPS — segue com o hash de fallback, mas avisa a pessoa disso.
        locationHash = unknownLocationHash;
        locationCell = null;
        locationStatus =
            'Localização indisponível — o alerta será enviado mesmo assim.';
    }
    setState(() => _locationStatus = locationStatus);

    try {
      final result = await backend.createRedAlert(
        idempotencyKey: key,
        locationHash: locationHash,
        locationCell: locationCell,
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
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
          const Icon(Icons.location_on_outlined),
          const SizedBox(height: 8),
          Text(_locationStatus, key: const Key('location_status'), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          // SC 4.1.3: é a confirmação de que o alerta de emergência chegou à
          // equipe — o ponto mais crítico do app para um leitor de tela
          // anunciar sem depender de a pessoa varrer a tela de novo.
          Semantics(
            liveRegion: true,
            child: Text(_state, style: const TextStyle(color: PatientColors.accentOnSurface, fontWeight: FontWeight.bold)),
          ),
        ]))),
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
            child: Semantics(
              liveRegion: true,
              child: Text(
                key: const Key('triage_error'),
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: PatientColors.dangerOnSurface, fontWeight: FontWeight.bold),
              ),
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
    // `color` só é usada como texto/ícone sobre o card (nenhum botão herda
    // este tom), por isso a variante `OnSurface` entra direto na tupla —
    // `PatientColors.danger` e `PatientColors.accent` caem para 3.03:1 e
    // 3.91:1 sobre `surfaceRaised`, abaixo de 4.5:1 (WCAG 1.4.3).
    final (label, color, guidance) = switch (risk) {
      RiskLevel.red => (
          'Risco: Vermelho',
          PatientColors.dangerOnSurface,
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
          PatientColors.accentOnSurface,
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