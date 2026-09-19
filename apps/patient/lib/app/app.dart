import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show TextEditingValue, TextInputFormatter, TextSelection;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sinalacs_client/sinalacs_client.dart'
    show AlertStatus, AlertStatusResult, RiskLevel;
import 'package:sinalacs_patient/app/patient_theme.dart';
import 'package:sinalacs_patient/core/consent/consent_preferences.dart';
import 'package:sinalacs_patient/core/consent/sqflite_consent_preferences.dart';
import 'package:sinalacs_patient/core/network/backend_client.dart';
import 'package:sinalacs_patient/core/network/backend_scope.dart';
import 'package:sinalacs_patient/core/network/idempotency.dart';
import 'package:sinalacs_patient/core/privacy/location_hash.dart';
import 'package:sinalacs_patient/core/reminders/reminder.dart';
import 'package:sinalacs_patient/core/reminders/reminder_scheduler.dart';
import 'package:sinalacs_patient/core/reminders/reminder_store.dart';
import 'package:sinalacs_patient/core/reminders/sqflite_reminder_store.dart';

class SinalAcsApp extends StatefulWidget {
  const SinalAcsApp({
    super.key,
    required this.backend,
    this.locationReader,
    this.reminderStore,
    this.reminderScheduler,
    this.consentPreferences,
  });

  /// Backend do app. **Obrigatório, e construído em `main.dart`.**
  ///
  /// Havia aqui um `widget.backend ?? BackendClient()`: um cliente **sem a CA do
  /// RPC** (RNF04/L-08) falando com o `https` padrão. Em produção o `main` sempre
  /// injetou, então ele nunca mordeu — mas era o caminho que um teste ou uma
  /// tela nova pegava sem perceber, e que falharia no handshake com a cara de
  /// "problema de servidor". Só o `main` pode construir este cliente: é o único
  /// lugar onde a CA já foi lida do bundle. Injetável para teste, onde o duplo
  /// entra no lugar do real. Os demais parâmetros continuam opcionais: os
  /// fallbacks deles não carregam CA nem apontam para a rede.
  final PatientBackend backend;

  /// Injetável para teste. Em execução normal é o [GeolocatorLocationReader]
  /// real, que fala com o GPS do aparelho.
  final LocationReader? locationReader;

  /// Injetável para teste. Em execução normal é o [SqfliteReminderStore]
  /// real.
  final ReminderStore? reminderStore;

  /// Injetável para teste. Em execução normal é o
  /// [LocalNotificationsReminderScheduler] real — o plugin precisa já ter
  /// sido inicializado em `main.dart` antes de `runApp`.
  final ReminderScheduler? reminderScheduler;

  /// Injetável para teste. Em execução normal é o [SqfliteConsentPreferences]
  /// real.
  final ConsentPreferences? consentPreferences;

  @override
  State<SinalAcsApp> createState() => _SinalAcsAppState();
}

class _SinalAcsAppState extends State<SinalAcsApp> {
  late final LocationReader _locationReader =
      widget.locationReader ?? const GeolocatorLocationReader();
  late final ReminderStore _reminderStore = widget.reminderStore ?? SqfliteReminderStore();
  late final ReminderScheduler _reminderScheduler =
      widget.reminderScheduler ?? LocalNotificationsReminderScheduler(FlutterLocalNotificationsPlugin());
  late final ConsentPreferences _consentPreferences =
      widget.consentPreferences ?? SqfliteConsentPreferences();

  // Sem `dispose`: este widget não cria mais cliente nenhum (o `main` é quem
  // constrói e injeta), então não há o que fechar — fechar um backend injetado
  // seria fechar o de quem injetou.

  @override
  Widget build(BuildContext context) {
    return BackendScope(
      backend: widget.backend,
      child: LocationScope(
        reader: _locationReader,
        child: RemindersScope(
          store: _reminderStore,
          scheduler: _reminderScheduler,
          consentPreferences: _consentPreferences,
          child: MaterialApp(
            title: 'SinalACS Paciente',
            debugShowCheckedModeBanner: false,
            theme: buildPatientTheme(),
            home: const PatientLoginScreen(),
          ),
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

/// Disponibiliza [ReminderStore] e [ReminderScheduler] para a árvore de
/// widgets.
///
/// Mesmo padrão de `BackendScope`/`LocationScope`: a tela não constrói o
/// próprio armazenamento nem o próprio agendador, o que permite injetar
/// duplos em teste hermético sem tocar SQLite real nem canal de plataforma.
class RemindersScope extends InheritedWidget {
  const RemindersScope({
    required this.store,
    required this.scheduler,
    required this.consentPreferences,
    required super.child,
    super.key,
  });

  final ReminderStore store;
  final ReminderScheduler scheduler;
  final ConsentPreferences consentPreferences;

  static RemindersScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<RemindersScope>();
    assert(scope != null, 'Nenhum RemindersScope acima deste widget.');
    return scope!;
  }

  @override
  bool updateShouldNotify(RemindersScope oldWidget) =>
      store != oldWidget.store ||
      scheduler != oldWidget.scheduler ||
      consentPreferences != oldWidget.consentPreferences;
}

class PatientLoginScreen extends StatefulWidget {
  const PatientLoginScreen({super.key});

  @override
  State<PatientLoginScreen> createState() => _PatientLoginScreenState();
}

/// Passo do acesso: as credenciais (CPF + nascimento) ou o código que chegou
/// por SMS (RF01).
enum _LoginStep { credenciais, codigo }

/// Máscara de CPF do app: 11 dígitos exibidos como `000.000.000-00`.
///
/// O backend normaliza de qualquer forma (`Cpf.tryParse` aceita o texto cru),
/// mas o app tem um formato de exibição próprio — e é esse formato que sai
/// daqui: o que a tela mostra e o que vai para o servidor precisam ser a mesma
/// coisa, senão dois lugares passam a discordar sobre o que é "o mesmo CPF".
String _formatCpf(String input) {
  final digits = input.replaceAll(RegExp(r'\D'), '');
  final limited = digits.length > 11 ? digits.substring(0, 11) : digits;
  final buffer = StringBuffer();
  for (var index = 0; index < limited.length; index++) {
    if (index == 3 || index == 6) buffer.write('.');
    if (index == 9) buffer.write('-');
    buffer.write(limited[index]);
  }
  return buffer.toString();
}

/// Aplica [_formatCpf] enquanto a pessoa digita.
///
/// O cursor é recolocado depois do mesmo número de dígitos, e não no fim do
/// campo: sem isso, corrigir um dígito do meio jogaria o cursor para o final a
/// cada tecla.
class _CpfInputFormatter extends TextInputFormatter {
  const _CpfInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatted = _formatCpf(newValue.text);
    if (!newValue.selection.isValid) {
      return TextEditingValue(text: formatted);
    }

    final digitsBeforeCursor = RegExp(r'\d')
        .allMatches(newValue.text.substring(0, newValue.selection.baseOffset))
        .length;
    var offset = 0;
    var seen = 0;
    while (offset < formatted.length && seen < digitsBeforeCursor) {
      if (RegExp(r'\d').hasMatch(formatted[offset])) seen++;
      offset++;
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

class _PatientLoginScreenState extends State<PatientLoginScreen> {
  final _cpf = TextEditingController();
  final _nascimento = TextEditingController();
  final _codigo = TextEditingController();

  _LoginStep _step = _LoginStep.credenciais;
  bool _busy = false;
  String? _error;

  /// CPF exatamente como foi enviado em [PatientBackend.requestOtp].
  ///
  /// [PatientBackend.verifyOtp] precisa do **mesmo** valor, e reler o campo do
  /// formulário no segundo passo devolveria o que a pessoa deixou lá — que pode
  /// ter mudado no meio do caminho.
  String? _cpfDigitado;

  @override
  void dispose() {
    _cpf.dispose();
    _nascimento.dispose();
    _codigo.dispose();
    super.dispose();
  }

  /// Converte o que a pessoa digitou em data e pede o código (RF01).
  ///
  /// A data vem como `DD/MM/AAAA` da máscara do campo. Um valor que não
  /// converte é erro de digitação — e a tela diz isso, em vez de mandar um
  /// pedido que o servidor vai ignorar em silêncio (a resposta dele é a mesma
  /// para "não existe" e "data errada", de propósito).
  DateTime? _parseNascimento(String input) {
    final partes = input.trim().split(RegExp(r'[/-]'));
    if (partes.length != 3) return null;
    final dia = int.tryParse(partes[0]);
    final mes = int.tryParse(partes[1]);
    final ano = int.tryParse(partes[2]);
    if (dia == null || mes == null || ano == null) return null;
    if (dia < 1 || dia > 31 || mes < 1 || mes > 12 || ano < 1900 || ano > 2100) {
      return null;
    }
    final data = DateTime.utc(ano, mes, dia);
    // `DateTime.utc` normaliza dia inexistente em vez de recusá-lo: 31/02 vira
    // 02/03. Sem esta checagem, o erro de digitação viraria uma data válida e
    // diferente da cadastrada — e o servidor, de propósito, não diz nada sobre
    // data errada. Por isso a conferência é contra o que foi digitado.
    if (data.day != dia || data.month != mes || data.year != ano) return null;
    return data;
  }

  Future<void> _pedirCodigo() async {
    final nascimento = _parseNascimento(_nascimento.text);
    if (nascimento == null) {
      setState(() => _error = 'Confira a data de nascimento (DD/MM/AAAA).');
      return;
    }

    final cpf = _formatCpf(_cpf.text);
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await BackendScope.of(context).requestOtp(
        cpf: cpf,
        birthDate: nascimento,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _cpfDigitado = cpf;
        _codigo.clear();
        _step = _LoginStep.codigo;
      });
    } on BackendFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = failure.message;
      });
    }
  }

  /// Verifica o código e só navega em caso de sucesso.
  ///
  /// Antes a tela navegava incondicionalmente, ignorando o que era digitado —
  /// não havia como saber se o backend estava sequer alcançável.
  Future<void> _entrar() async {
    final cpf = _cpfDigitado;
    // Inalcançável hoje: o passo do código só existe depois do sucesso de
    // `_pedirCodigo`, que é quem guarda `_cpfDigitado`. O `assert` está aqui
    // para que uma tela futura que torne o passo alcançável sem CPF falhe alto
    // em desenvolvimento, em vez de deixar o CTA principal num no-op silencioso
    // (o `return` abaixo continua sendo o comportamento de release).
    assert(cpf != null, 'o passo do código exige o CPF guardado por _pedirCodigo');
    if (cpf == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await BackendScope.of(context).verifyOtp(cpf: cpf, code: _codigo.text.trim());
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

  void _voltarParaCredenciais() {
    setState(() {
      _step = _LoginStep.credenciais;
      _error = null;
      _codigo.clear();
    });
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
                        Text(
                          _step == _LoginStep.credenciais ? 'Acesso sem senha' : 'Código de acesso',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _step == _LoginStep.credenciais
                              ? 'Use CPF e data de nascimento para receber o código de acesso.'
                              // Nem "enviado para o seu celular": o app não sabe o
                              // telefone cadastrado, e afirmar isso seria inventar.
                              : 'Digite o código de 6 dígitos enviado pela sua unidade de saúde.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 24),
                        if (_step == _LoginStep.credenciais) ..._camposDeCredenciais() else ..._camposDoCodigo(),
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
                        if (_step == _LoginStep.credenciais) ...[
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

  List<Widget> _camposDeCredenciais() => [
        TextField(
          key: const Key('cpf_field'),
          controller: _cpf,
          keyboardType: TextInputType.number,
          inputFormatters: const [_CpfInputFormatter()],
          decoration: const InputDecoration(
            labelText: 'CPF do paciente',
            hintText: '000.000.000-00',
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('birth_date_field'),
          controller: _nascimento,
          keyboardType: TextInputType.datetime,
          decoration: const InputDecoration(
            labelText: 'Data de nascimento',
            hintText: 'DD/MM/AAAA',
          ),
        ),
        const SizedBox(height: 20),
        // Sem `Semantics` em volta: o `Text` do botão já é o nome acessível, o
        // `FilledButton` já expõe papel e ação de toque. Um wrapper com outro
        // `label` e `container: true` não funde com o botão — cria um nó
        // próprio, **sem ação**, anunciado ANTES do botão real: nome que não
        // contém o texto visível (WCAG 2.5.3, nível A) e nó inerte (WCAG 4.1.2).
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const Key('enter_button'),
            onPressed: _busy ? null : _pedirCodigo,
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
      ];

  List<Widget> _camposDoCodigo() => [
        TextField(
          key: const Key('otp_code_field'),
          controller: _codigo,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Código de acesso',
            hintText: '000000',
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('verify_code_button'),
          onPressed: _busy ? null : _entrar,
          style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
          child: _busy
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Entrar'),
        ),
        const SizedBox(height: 12),
        // Não repete o pedido: dentro de um minuto o servidor **não envia** um
        // segundo código para o mesmo CPF — e não responde nada de diferente,
        // de propósito: um aviso de "aguarde um minuto" só seria alcançável por
        // quem já acertou CPF e nascimento, ou seja, seria o verificador do par.
        // Voltar ao passo anterior devolve o controle a quem está logando, que
        // reenvia pelo botão de sempre — e, dentro do intervalo, o pedido passa
        // em silêncio: nenhum código novo chega, e a tela não diz nada.
        //
        // Esse aviso é DESTE lado — é o app que sabe quando o pedido anterior
        // saiu — e ainda não existe. Lacuna registrada no `PROGRESS.md`, com
        // dono: quem mexer no app do paciente, que é este arquivo.
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            key: const Key('request_new_code_button'),
            onPressed: _busy ? null : _voltarParaCredenciais,
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 52)),
            child: const Text('Pedir outro código'),
          ),
        ),
      ];
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
      // Espelha localmente a resposta já enviada ao backend — é o único
      // momento em que o app conhece essa decisão; `RemindersScreen` não
      // tem outro jeito de saber se pode agendar notificações (RF06 é local
      // ao aparelho, sem endpoint de consulta de consentimento no backend).
      // Best-effort: o backend já gravou a decisão (fonte de verdade); se a
      // cópia local falhar, o app não pode travar a conclusão do cadastro
      // por causa disso — e `localRemindersGranted()` já degrada para
      // recusado (fail closed) quando não há linha local, então uma falha
      // aqui nunca resulta em agendar sem consentimento.
      try {
        await RemindersScope.of(context).consentPreferences.saveLocalRemindersConsent(_remindersConsent);
      } catch (_) {
        // Intencionalmente silencioso — ver comentário acima.
      }
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

  /// Sessão do paciente expirou com o app aberto.
  ///
  /// O paciente não tem renovação silenciosa (ver `BackendClient._requireToken`:
  /// o código OTP é de uso único e não há credencial reutilizável), então a
  /// única saída é entrar de novo — e é o app que precisa oferecer a porta, no
  /// lugar onde a pessoa está, em vez de deixá-la presa numa tela que só
  /// devolve "sua sessão expirou".
  bool _sessionExpired = false;

  @override
  void initState() {
    super.initState();
    _destination = widget.initialDestination;
  }

  void _select(PatientDestination destination) => setState(() => _destination = destination);

  /// Reage a uma falha relatada por uma das telas do shell.
  ///
  /// Quem decide se a pessoa é mandada de volta ao login é o shell, e não a
  /// tela: a condição é a do plano — falha **não recuperável** *e* sessão já
  /// expirada. Uma falha não recuperável com a sessão válida (permissão
  /// negada, por exemplo) não tem nada a ver com sessão expirada, e oferecer
  /// "Entrar novamente" ali seria mandar a pessoa refazer o login à toa.
  void _reportFailure(BackendFailure failure) {
    if (failure.isRecoverable) return;
    final session = BackendScope.of(context).session;
    if (session == null || !session.isExpired()) return;
    if (!mounted || _sessionExpired) return;
    setState(() => _sessionExpired = true);
  }

  void _reenter() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const PatientLoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = switch (_destination) {
      PatientDestination.emergency => EmergencyScreen(onFailure: _reportFailure),
      PatientDestination.triage => TriageScreen(
          onComplete: () => _select(PatientDestination.status),
          onFailure: _reportFailure,
        ),
      PatientDestination.questions => const QuestionsScreen(),
      PatientDestination.profile => const ClinicalProfileScreen(),
      PatientDestination.status => StatusScreen(onFailure: _reportFailure),
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
      body: SafeArea(
        child: Column(
          children: [
            if (_sessionExpired) _SessionExpiredBanner(onReenter: _reenter),
            Expanded(child: content),
          ],
        ),
      ),
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

/// Aviso de sessão expirada, com a porta de volta para o login.
///
/// Fica no shell, acima do conteúdo, e não dentro da tela que falhou: a sessão
/// vale para o app inteiro, e a pessoa pode estar em qualquer aba quando ela
/// expira.
class _SessionExpiredBanner extends StatelessWidget {
  const _SessionExpiredBanner({required this.onReenter});

  final VoidCallback onReenter;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // SC 4.1.3: a sessão expirou sem que a pessoa tenha feito nada —
              // sem `liveRegion` um leitor de tela não saberia que o app parou
              // de responder ao servidor nem que existe um botão para voltar.
              Semantics(
                liveRegion: true,
                child: const Text(
                  key: Key('session_expired_notice'),
                  'Sua sessão expirou. Entre novamente com o código de acesso.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('reenter_button'),
                onPressed: onReenter,
                style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
                child: const Text('Entrar novamente'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key, this.onFailure});

  /// Relata ao shell a falha capturada nesta tela. Ver
  /// `_PatientHomeShellState._reportFailure` para o que o shell decide com ela.
  final ValueChanged<BackendFailure>? onFailure;

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
      widget.onFailure?.call(failure);
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
          // `MergeSemantics`, e não só o `Semantics`: em volta de um botão de
          // verdade o `Semantics` **não funde** com ele — cria um nó próprio,
          // com papel de botão e sem ação de toque (medido na árvore:
          // `Rect.fromLTRB(0, 0, 752, 208)`, a largura toda), anunciado ANTES
          // do botão real. No controle mais crítico do app o leitor de tela
          // encontrava primeiro um "botão" que não faz nada (WCAG 4.1.2) e cujo
          // nome não continha o texto visível (WCAG 2.5.3, nível A). Mesclado,
          // sobra UM nó: nome "Enviar alerta de emergência\nEMERGÊNCIA", com a
          // ação de toque, e a moldura volta a ser a do botão (208x208).
          child: MergeSemantics(
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
  const TriageScreen({super.key, this.onComplete, this.onFailure});
  final VoidCallback? onComplete;

  /// Relata ao shell a falha capturada nesta tela. Ver
  /// `_PatientHomeShellState._reportFailure`.
  final ValueChanged<BackendFailure>? onFailure;

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
      widget.onFailure?.call(failure);
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

/// Acompanhamento da solicitação do paciente (RF05, decisão §5) — consome
/// `alerts.statusFor`, escopado ao próprio paciente pelo token.
///
/// Antes mostrava sempre "Solicitação de visita #4082" com passos fixos,
/// inclusive para quem nunca disparou um alerta (L-03, "Tela de Status
/// mente para o paciente" em spec/validation_report.md). Estado próprio
/// (não no shell): um teste existente constrói `PatientHomeShell` só sob
/// `RemindersScope`, sem `BackendScope` — buscar o status no shell quebraria
/// esse teste mesmo quando a aba aberta é outra.
class StatusScreen extends StatelessWidget {
  const StatusScreen({super.key, this.syncInterval = const Duration(minutes: 5), this.onFailure});

  /// Intervalo da sincronização periódica em segundo plano, além da busca ao
  /// abrir a aba e do botão manual. Produção usa o default (5 minutos);
  /// testes passam um valor curto para não esperar tempo real.
  final Duration syncInterval;

  /// Relata ao shell a falha capturada nesta tela. Ver
  /// `_PatientHomeShellState._reportFailure`.
  final ValueChanged<BackendFailure>? onFailure;

  @override
  Widget build(BuildContext context) => _StatusScreenBody(
        syncInterval: syncInterval,
        onFailure: onFailure,
      );
}

class _StatusScreenBody extends StatefulWidget {
  const _StatusScreenBody({required this.syncInterval, this.onFailure});

  final Duration syncInterval;
  final ValueChanged<BackendFailure>? onFailure;

  @override
  State<_StatusScreenBody> createState() => _StatusScreenBodyState();
}

class _StatusScreenBodyState extends State<_StatusScreenBody> with WidgetsBindingObserver {
  bool _loading = false;
  AlertStatusResult? _status;
  String? _error;
  DateTime? _checkedAt;
  bool _requestedLoad = false;

  /// `null` quando nenhum ciclo periódico está agendado (app em segundo
  /// plano, ou ainda não iniciado).
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // BackendScope.of(context) só é seguro a partir daqui, não em
    // initState — mesmo padrão de RemindersScreen._requestedLoad.
    if (!_requestedLoad) {
      _requestedLoad = true;
      _load();
      _startPeriodicSync();
    }
  }

  /// Sincronização periódica em segundo plano: repete `_load()` a cada
  /// `widget.syncInterval` enquanto a aba Status está montada e o app em
  /// primeiro plano — sem isto, o paciente só via um status novo reabrindo
  /// a aba ou apertando "Verificar status agora".
  void _startPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(widget.syncInterval, (_) => _load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Um Timer em segundo plano no Android não é confiável e só gastaria
      // bateria; a tentativa volta ao primeiro plano — mesmo padrão do ACS
      // (`_AcsHomeShellState._periodicSyncTimer`).
      _syncTimer?.cancel();
      _syncTimer = null;
    } else if (state == AppLifecycleState.resumed) {
      _load();
      _startPeriodicSync();
    }
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final status = await BackendScope.of(context).statusFor();
      if (!mounted) return;
      setState(() {
        _status = status;
        _checkedAt = DateTime.now();
      });
    } on BackendFailure catch (failure) {
      if (!mounted) return;
      widget.onFailure?.call(failure);
      setState(() => _error = failure.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Não foi possível verificar o status da solicitação.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _status;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            // SC 4.1.3, mesmo padrão do erro de login/onboarding/lembretes.
            child: Semantics(
              liveRegion: true,
              child: Text(
                key: const Key('status_error'),
                _error!,
                style: const TextStyle(color: PatientColors.dangerOnSurface, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        if (current == null || !current.found)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    key: const Key('status_empty'),
                    _loading ? 'Verificando...' : 'Nenhuma solicitação registrada ainda.',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Um alerta de urgência ou uma triagem concluída aparece aqui assim que a equipe recebe.',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          )
        else
          _StatusCard(status: current),
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('refresh_status'),
          onPressed: _loading ? null : _load,
          style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
          child: _loading
              ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Verificar status agora'),
        ),
        if (_checkedAt != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Verificado às ${_formatTime(_checkedAt!)}',
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status});

  final AlertStatusResult status;

  @override
  Widget build(BuildContext context) {
    // Mesma disciplina de cor de `_TriageResult`: `OnSurface` porque o tom
    // aparece como texto sobre `Card`, não como preenchimento.
    final (riskLabel, riskColor) = switch (status.riskLevel) {
      RiskLevel.red => ('Vermelho', PatientColors.dangerOnSurface),
      RiskLevel.yellow => ('Amarelo', const Color(0xFFE0A800)),
      RiskLevel.green => ('Verde', PatientColors.accentOnSurface),
      null => ('Não classificado', Colors.white70),
    };
    final statusLabel = switch (status.status) {
      AlertStatus.pending => 'Enviado — aguardando confirmação da equipe',
      AlertStatus.acknowledged => 'Recebido pela equipe de saúde',
      AlertStatus.resolved => 'Atendimento concluído',
      AlertStatus.escalated => 'Encaminhado para o SAMU',
      null => 'Sem status',
    };
    final triggeredAt = status.triggeredAt;
    final acknowledgedAt = status.acknowledgedAt;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              key: const Key('status_risk'),
              'Risco: $riskLabel',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: riskColor),
            ),
            if (triggeredAt != null) ...[
              const SizedBox(height: 8),
              Text('Disparado às ${_formatTime(triggeredAt)}'),
            ],
            const SizedBox(height: 16),
            Text(
              key: const Key('status_label'),
              statusLabel,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (acknowledgedAt != null) ...[
              const SizedBox(height: 4),
              Text('Confirmado pela equipe às ${_formatTime(acknowledgedAt)}'),
            ],
          ],
        ),
      ),
    );
  }
}

String _formatTime(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

/// Lembretes locais de saúde (medicamento, pesagem, etc.), RF06 §3.1.
///
/// Carrega do [ReminderStore] injetado via [RemindersScope]; abre vazia
/// quando não há nenhum lembrete cadastrado ainda (sem lista fixa de
/// exemplo). Criar/editar grava no store e agenda via [ReminderScheduler];
/// alternar o switch ou excluir grava a mudança e agenda/cancela a
/// notificação correspondente.
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});
  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  List<Reminder>? _reminders;
  String? _error;
  bool _requestedLoad = false;
  // `null` até o primeiro carregamento terminar, e continua `null` se não
  // houver registro local de consentimento (aparelho que nunca passou pelo
  // onboarding) — distinto de `false` (recusa explícita), embora ambos
  // bloqueiem o agendamento do mesmo jeito (ver `ConsentPreferences`).
  bool? _remindersConsentGranted;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `RemindersScope.of` depende do `InheritedWidget` acima na árvore, que
    // só está disponível a partir daqui (não em `initState`); a flag evita
    // recarregar a cada rebuild.
    if (!_requestedLoad) {
      _requestedLoad = true;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final scope = RemindersScope.of(context);
      var reminders = await scope.store.list();
      final consentGranted = await scope.consentPreferences.localRemindersGranted();
      if (consentGranted != true) {
        // Recusa (ou estado desconhecido, tratado como recusa por padrão de
        // segurança): nenhum lembrete pode continuar agendado no sistema
        // operacional depois disso — sem isso, um lembrete criado antes da
        // recusa continuaria disparando mesmo depois dela (LGPD-RF05).
        final stillActive = reminders.where((r) => r.active).toList();
        for (final r in stillActive) {
          await scope.scheduler.cancel(r.id);
          await scope.store.save(r.copyWith(active: false));
        }
        if (stillActive.isNotEmpty) {
          reminders = await scope.store.list();
        }
      }
      if (!mounted) return;
      setState(() {
        _reminders = reminders;
        _remindersConsentGranted = consentGranted;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Não foi possível carregar os lembretes.');
    }
  }

  // As três escritas abaixo (`_toggleActive`/`_delete`/`_createOrEdit`)
  // seguem o mesmo formato de `_PatientLoginScreenState._enter()`/
  // `_EmergencyScreenState._sendAlert()`/`_OnboardingScreenState._complete()`:
  // `try`/`catch` ao redor da escrita, `setState` limpando o erro em caso de
  // sucesso ou gravando uma mensagem em português em caso de falha, sem
  // deixar a exceção subir sem tratamento — `scheduler.schedule`/`cancel`
  // fala com um plugin de plataforma real (`flutter_local_notifications`),
  // que pode falhar em dispositivo por motivos fora do controle da tela.

  String _consentDeniedMessage(bool? granted) {
    if (granted == false) {
      return 'Você recusou o consentimento para lembretes locais no cadastro — '
          'não é possível agendar notificações.';
    }
    return 'Não encontramos seu consentimento para lembretes locais neste '
        'aparelho — conclua o cadastro para ativar notificações.';
  }

  Future<void> _toggleActive(Reminder reminder, bool active) async {
    if (active && _remindersConsentGranted != true) {
      setState(() => _error = _consentDeniedMessage(_remindersConsentGranted));
      return;
    }
    final scope = RemindersScope.of(context);
    final updated = reminder.copyWith(active: active);
    try {
      await scope.store.save(updated);
      if (active) {
        await scope.scheduler.schedule(updated);
      } else {
        await scope.scheduler.cancel(updated.id);
      }
      if (!mounted) return;
      setState(() {
        _error = null;
        _reminders = [for (final r in _reminders ?? const <Reminder>[]) if (r.id == updated.id) updated else r];
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Não foi possível atualizar o lembrete.');
    }
  }

  Future<void> _delete(Reminder reminder) async {
    final scope = RemindersScope.of(context);
    try {
      await scope.store.delete(reminder.id);
      await scope.scheduler.cancel(reminder.id);
      if (!mounted) return;
      setState(() {
        _error = null;
        _reminders = [for (final r in _reminders ?? const <Reminder>[]) if (r.id != reminder.id) r];
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Não foi possível excluir o lembrete.');
    }
  }

  Future<void> _createOrEdit({Reminder? existing}) async {
    if (_remindersConsentGranted != true) {
      setState(() => _error = _consentDeniedMessage(_remindersConsentGranted));
      return;
    }
    final result = await showDialog<(String, int, int)>(
      context: context,
      builder: (context) => _ReminderFormDialog(existing: existing),
    );
    if (result == null || !mounted) return;
    final (label, hour, minute) = result;

    final scope = RemindersScope.of(context);
    final base = existing ?? const Reminder(id: 0, label: '', hour: 0, minute: 0, active: true);
    try {
      final saved = await scope.store.save(base.copyWith(label: label, hour: hour, minute: minute));
      if (saved.active) {
        await scope.scheduler.schedule(saved);
      } else {
        await scope.scheduler.cancel(saved.id);
      }
      if (!mounted) return;
      setState(() {
        _error = null;
        final withoutSaved = [for (final r in _reminders ?? const <Reminder>[]) if (r.id != saved.id) r];
        _reminders = [...withoutSaved, saved]..sort(
            (a, b) => a.hour != b.hour ? a.hour - b.hour : a.minute - b.minute,
          );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Não foi possível salvar o lembrete.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final reminders = _reminders;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Alarmes e medicamentos', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            IconButton(
              key: const Key('reminders_add_button'),
              tooltip: 'Novo alarme',
              onPressed: _remindersConsentGranted == true ? () => _createOrEdit() : null,
              icon: const Icon(Icons.add_alarm_outlined),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (reminders != null && _remindersConsentGranted != true)
          // SC 4.1.3, mesmo padrão do banner de erro logo abaixo: quem usa
          // leitor de tela precisa saber por que o botão "+" está desabilitado.
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Semantics(
              liveRegion: true,
              child: Container(
                key: const Key('reminders_consent_denied_banner'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white24),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _consentDeniedMessage(_remindersConsentGranted),
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ),
          ),
        if (_error != null)
          // SC 4.1.3: mesmo padrão do erro de login/onboarding — sem
          // `liveRegion` um leitor de tela não saberia que a operação (carregar,
          // salvar, alternar ou excluir um lembrete) falhou.
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                key: const Key('reminders_error'),
                style: const TextStyle(color: PatientColors.dangerOnSurface, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        // As três ramificações abaixo são mutuamente exclusivas e, juntas,
        // não cobrem "reminders == null && _error != null" (carregamento
        // falhou): nesse caso só o banner de erro acima aparece, sem spinner
        // por baixo. Uma falha ao salvar/alternar/excluir, ao contrário, faz
        // `_error` e `_reminders` (já carregado antes) conviverem — o banner
        // aparece por cima da lista existente, não no lugar dela.
        if (reminders == null && _error == null)
          const Padding(
            padding: EdgeInsets.only(top: 40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (reminders != null && reminders.isEmpty)
          const Padding(
            key: Key('reminders_empty_state'),
            padding: EdgeInsets.only(top: 40),
            child: Center(
              child: Text(
                'Você ainda não tem lembretes. Toque em "+" para criar o primeiro.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54),
              ),
            ),
          )
        else if (reminders != null)
          ...reminders.map(
            (reminder) => Card(
              child: Column(
                children: [
                  ListTile(
                    key: Key('reminder_tile_${reminder.id}'),
                    title: Text(_reminderLabel(reminder)),
                    subtitle: Text(reminder.active ? 'Ativo' : 'Pausado'),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          key: Key('reminder_edit_${reminder.id}'),
                          tooltip: 'Editar lembrete',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _createOrEdit(existing: reminder),
                        ),
                        IconButton(
                          key: Key('reminder_delete_${reminder.id}'),
                          tooltip: 'Excluir lembrete',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(reminder),
                        ),
                      ],
                    ),
                  ),
                  SwitchListTile(
                    key: Key('reminder_switch_${reminder.id}'),
                    value: reminder.active,
                    onChanged: (value) => _toggleActive(reminder, value),
                    title: const Text('Notificação ativa'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

String _reminderLabel(Reminder reminder) {
  final hour = reminder.hour.toString().padLeft(2, '0');
  final minute = reminder.minute.toString().padLeft(2, '0');
  return '$hour:$minute - ${reminder.label}';
}

/// Formulário de criação/edição de um [Reminder]: descrição livre + horário.
/// Devolve `(label, hour, minute)` ao confirmar, ou `null` se cancelado.
class _ReminderFormDialog extends StatefulWidget {
  const _ReminderFormDialog({this.existing});

  final Reminder? existing;

  @override
  State<_ReminderFormDialog> createState() => _ReminderFormDialogState();
}

class _ReminderFormDialogState extends State<_ReminderFormDialog> {
  late final _labelController = TextEditingController(text: widget.existing?.label ?? '');
  late TimeOfDay _time = widget.existing != null
      ? TimeOfDay(hour: widget.existing!.hour, minute: widget.existing!.minute)
      : TimeOfDay.now();

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  @override
  Widget build(BuildContext context) {
    final label = _labelController.text.trim();
    return AlertDialog(
      title: Text(widget.existing == null ? 'Novo lembrete' : 'Editar lembrete'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('reminder_label_field'),
            controller: _labelController,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Descrição (ex.: Losartana 50 mg)'),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: const Key('reminder_time_button'),
            onPressed: _pickTime,
            icon: const Icon(Icons.access_time),
            label: Text(_time.format(context)),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          key: const Key('reminder_save_button'),
          onPressed: label.isEmpty ? null : () => Navigator.pop(context, (label, _time.hour, _time.minute)),
          child: const Text('Salvar'),
        ),
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