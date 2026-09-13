import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:sinalacs_acs/app/acs_theme.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/network/backend_scope.dart';
import 'package:sinalacs_acs/core/services/alert_feed.dart';
import 'package:sinalacs_acs/core/services/alert_queue.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';
import 'package:sinalacs_client/sinalacs_client.dart' show MicroAreaPatient;
import 'package:sinalacs_acs/core/services/reconnect_schedule.dart';
import 'package:sinalacs_acs/core/services/route_service.dart';
import 'package:sinalacs_acs/core/services/visit_queue_factory.dart';

class SinalAcsApp extends StatefulWidget {
  const SinalAcsApp({
    super.key,
    this.backend,
    this.feedBuilder,
    this.visitQueue,
    this.initialAlert,
    this.currentPosition,
  });

  /// Injetáveis para teste. Em execução normal são as implementações reais.
  final AcsBackend? backend;
  final AlertFeed Function(AlertQueue queue)? feedBuilder;
  final OfflineVisitQueue? visitQueue;
  final PrioritizedAlert? initialAlert;
  final LatLng? currentPosition;

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
  late final OfflineVisitQueue _visitQueue = widget.visitQueue ?? _persistentQueue();

  /// Fila respaldada pelo banco criptografado, com o sincronizador ligado.
  ///
  /// A chave vive no Keystore/Keychain, nunca no código. Deixou de ser `static`
  /// para enxergar [_backend]: sem sincronizador, `sync()` caía no ramo sem
  /// remetente e devolvia erro — as visitas nunca subiam ao servidor e o que já
  /// estava confirmado nunca era apagado do disco.
  OfflineVisitQueue _persistentQueue() => buildVisitQueue(backend: _backend);

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
            initialAlert: widget.initialAlert,
            initialPosition: widget.currentPosition,
          ),
        ),
      );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    required this.visitQueue,
    super.key,
    this.feedBuilder,
    this.initialAlert,
    this.initialPosition,
  });

  final AlertFeed Function(AlertQueue queue)? feedBuilder;
  final OfflineVisitQueue visitQueue;
  final PrioritizedAlert? initialAlert;
  final LatLng? initialPosition;

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
          initialAlert: widget.initialAlert,
          initialPosition: widget.initialPosition,
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

/// Aviso de infraestrutura: o que quebrou e a consequência prática.
///
/// O subtítulo era fixo no [DashboardScreen] e passou a mentir quando o banner
/// exibido era o de armazenamento — "Novos alertas podem não estar chegando"
/// sobre uma falha de disco.
typedef InfraNotice = ({String title, String detail});

class AcsHomeShell extends StatefulWidget {
  const AcsHomeShell({
    required this.microAreaId,
    required this.acsId,
    required this.visitQueue,
    super.key,
    this.feedBuilder,
    this.initialAlert,
    this.initialPosition,
  });

  final String microAreaId;
  final String acsId;
  final AlertFeed Function(AlertQueue queue)? feedBuilder;
  final PrioritizedAlert? initialAlert;
  final LatLng? initialPosition;

  /// Obrigatória: a tela de visita usava `widget.visitQueue ?? OfflineVisitQueue()`,
  /// e um dia em que o shell fosse construído sem fila voltaria a descartar a
  /// visita em silêncio.
  final OfflineVisitQueue visitQueue;

  @override
  State<AcsHomeShell> createState() => _AcsHomeShellState();
}

class _AcsHomeShellState extends State<AcsHomeShell> with WidgetsBindingObserver {
  AcsDestination destination = AcsDestination.queue;

  late final AlertQueue _queue = AlertQueue(microAreaId: widget.microAreaId);
  late final AlertFeed _feed =
      (widget.feedBuilder ?? (queue) => MqttAlertFeed(queue: queue))(_queue);

  bool _brokerConnected = false;
  InfraNotice? _feedError;
  bool _feedErrorIsTransient = false;
  PrioritizedAlert? _selected;
  LatLng? _currentPosition;

  /// Só existe enquanto uma falha transitória está sendo retentada. `null`
  /// quer dizer "nada agendado" — nem depois de um sucesso, nem depois de uma
  /// falha permanente.
  Timer? _reconnectTimer;
  final ReconnectSchedule _reconnectDelay = ReconnectSchedule();

  @override
  void initState() {
    super.initState();
    _selected = widget.initialAlert;
    _currentPosition ??= widget.initialPosition;
    WidgetsBinding.instance.addObserver(this);
    // Assinado antes de start(): uma queda depois de conectar chega aqui
    // sozinha, via autoReconnect do mqtt_client — é o que mantém o chip do
    // cabeçalho honesto sem o shell abrir um segundo laço de retentativa.
    _feed.onConnectionChanged = _onBrokerConnectionChanged;
    _connectFeed();
    _restoreVisits();
    _loadCurrentPosition();
  }

  /// Recarrega as visitas gravadas em execuções anteriores.
  ///
  /// Sem esta chamada, persistir não serviria para nada — `restore()` existia e
  /// só era exercitado por teste.
  ///
  /// Falhar aqui **não** pode ser silencioso nem fatal: o ACS segue registrando
  /// visitas em memória, para não travar o trabalho em campo, mas precisa saber
  /// que elas não estão sendo salvas. Cair para memória sem avisar perderia
  /// visitas sem ninguém perceber. Manter em RAM não viola o INV-04, que proíbe
  /// *persistir* em texto plano.
  Future<void> _restoreVisits() async {
    await widget.visitQueue.restore();
    // `setState` sem estado próprio: o que mudou está DENTRO da fila, e o aviso
    // é lido de lá a cada build. Guardar a resposta num campo era o defeito —
    // o sinalizador congelava aqui e toda falha posterior de `add()`/`sync()`
    // ficava invisível.
    if (mounted) setState(() {});
  }

  Future<void> _loadCurrentPosition() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          return;
        }
      }

      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
      });
    } catch (_) {
      // Localização não é crítica para a fila; sem GPS ou permissão, o mapa
      // continua funcional com o centro do território em vez de quebrar.
    }
  }

  /// Aviso de persistência, lido do estado corrente da fila.
  ///
  /// [OfflineVisitQueue] continua sendo um serviço puro (`import 'dart:math'`
  /// apenas): transformá-la em `ChangeNotifier` traria `package:flutter` para
  /// dentro dela, o que este repositório já recusou. Ler no `build` basta
  /// **enquanto** toda escrita na fila partir da tela de Visita — voltar para a
  /// Fila passa obrigatoriamente pelo `setState` da `NavigationBar`. Se um dia
  /// existir sincronização automática em segundo plano, o próximo passo é um
  /// `void Function(bool)? onPersistenceChanged` na fila, no molde de
  /// `MqttAlertFeed.onConnectionChanged` — não um `ChangeNotifier`.
  InfraNotice? get _storageNotice => widget.visitQueue.persistenceFailed
      ? (
          title: 'As visitas não estão sendo salvas neste aparelho.',
          detail: 'O que está na fila só existe na memória. '
              'Sincronize antes de fechar o aplicativo.',
        )
      : null;

  /// Assina o tópico da microárea da sessão.
  ///
  /// Falhar aqui não derruba o painel, mas **precisa ficar visível**: um ACS que
  /// não sabe que parou de receber alertas é o pior modo de falha do produto.
  ///
  /// Antes rodava só uma vez, no `initState`: se falhasse, o app nunca mais
  /// tentava, e reabrir era o único jeito de recuperar um alerta que o broker
  /// já estava guardando com QoS 1. Falhas transitórias agora são retentadas
  /// sozinhas por [_scheduleReconnect]; falhas permanentes (senha ausente, CA
  /// ausente, credencial recusada) não são — insistir nelas não muda nada e só
  /// gastaria bateria.
  Future<void> _connectFeed() async {
    try {
      await _feed.start(microAreaId: widget.microAreaId, acsId: widget.acsId);
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _reconnectDelay.reset();
      if (!mounted) return;
      setState(() {
        _brokerConnected = _feed.isConnected;
        _feedError = null;
        _feedErrorIsTransient = false;
      });
    } on AlertFeedFailure catch (failure, stackTrace) {
      developer.log(
        'não foi possível assinar o tópico de alertas',
        name: 'sinalacs.acs.alert_feed',
        error: failure.cause ?? failure,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _brokerConnected = false;
        _feedErrorIsTransient = failure.transient;
        _feedError = (
          title: failure.title,
          detail: failure.transient
              ? '${failure.detail} Tentando reconectar automaticamente.'
              : failure.detail,
        );
      });
      if (failure.transient) _scheduleReconnect();
    } catch (error, stackTrace) {
      // Defesa: hoje só um AlertFeed de teste chega aqui. Logar em vez de
      // descartar — antes o erro era engolido e a tela dizia sempre o mesmo.
      // Na dúvida sobre a natureza da falha, tratar como transitória: silêncio
      // de alertas é o pior modo de falha do produto.
      developer.log(
        'falha não classificada ao assinar o tópico de alertas',
        name: 'sinalacs.acs.alert_feed',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _brokerConnected = false;
        _feedErrorIsTransient = true;
        _feedError = (
          title: 'Sem conexão com a central de alertas.',
          detail: 'Novos alertas podem não estar chegando. '
              'Tentando reconectar automaticamente.',
        );
      });
      _scheduleReconnect();
    }
  }

  /// Agenda a próxima tentativa, cancelando qualquer uma já pendente.
  ///
  /// O cancelamento prévio é o que impede "Tentar agora" durante a espera de
  /// deixar dois timers vivos.
  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay.next(), () {
      if (mounted) _connectFeed();
    });
  }

  /// O botão "Tentar agora" do banner: pula a fila do backoff.
  void _retryFeedNow() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectDelay.reset();
    _connectFeed();
  }

  /// Notificado pelo [AlertFeed] a cada mudança de conexão — inclusive depois
  /// do `start()` já ter retornado. Sem isto, uma queda que acontecesse depois
  /// de uma conexão bem-sucedida nunca chegaria ao cabeçalho, que continuaria
  /// dizendo "em linha" indefinidamente enquanto o `autoReconnect` do
  /// `mqtt_client` trabalhava por baixo em silêncio.
  void _onBrokerConnectionChanged(bool connected) {
    if (!mounted) return;
    setState(() => _brokerConnected = connected);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Um Timer em segundo plano no Android não é confiável e só gastaria
      // bateria; a tentativa volta ao primeiro plano.
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
    } else if (state == AppLifecycleState.resumed && _feedErrorIsTransient) {
      // O gatilho que mais importa na prática: o sinal costuma voltar com a
      // tela apagada, e o ACS tira o aparelho do bolso já esperando o alerta.
      _reconnectDelay.reset();
      _connectFeed();
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
    _reconnectTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
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
          onRetryFeed: _feedErrorIsTransient ? _retryFeedNow : null,
          storageError: _storageNotice,
          onAcknowledge: _acknowledge,
          onEscalate: (alert) => setState(() { _selected = alert; destination = AcsDestination.escalation; }),
          onVisit: (alert) => setState(() { _selected = alert; destination = AcsDestination.visit; }),
        ),
      AcsDestination.map => MapScreen(
          queue: _queue,
          currentPosition: _currentPosition,
          apiKey: const String.fromEnvironment('GOOGLE_MAPS_API_KEY', defaultValue: ''),
          onVisit: (alert) => setState(() {
            _selected = alert;
            destination = AcsDestination.visit;
          }),
        ),
      AcsDestination.visit => VisitRegistrationScreen(
          alert: _selected,
          queue: widget.visitQueue,
          currentPosition: _currentPosition,
        ),
      AcsDestination.escalation => EscalationScreen(
          alert: _selected,
          onVisit: (alert) => setState(() {
            _selected = alert;
            destination = AcsDestination.visit;
          }),
        ),
      AcsDestination.geofencing => GeofencingScreen(
          queue: _queue,
          currentPosition: _currentPosition,
          onVisit: (alert) => setState(() {
            _selected = alert;
            destination = AcsDestination.visit;
          }),
        ),
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
    this.onRetryFeed,
    this.storageError,
    this.onAcknowledge,
    this.onEscalate,
    this.onVisit,
  });

  final AlertQueue queue;
  final InfraNotice? feedError;

  /// Presente só quando [feedError] é uma falha transitória — dá ao ACS que já
  /// vê o sinal voltar a chance de não esperar o backoff automático. `null`
  /// numa falha permanente (senha ausente, CA ausente) evita oferecer um botão
  /// que nunca vai funcionar.
  final VoidCallback? onRetryFeed;

  /// Armazenamento local recusando gravação.
  ///
  /// Coexiste com [feedError] em vez de disputar o mesmo espaço: em campo os
  /// dois caem juntos, e um `??` entre eles escondia justamente o que ninguém
  /// descobre sozinho — que as visitas do dia não estão sendo salvas.
  final InfraNotice? storageError;
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
            // Alertas primeiro: é o aviso com risco de vida atrás.
            if (feedError != null) _InfraBanner(
              key: const Key('feed_error'),
              icon: Icons.cloud_off_outlined,
              notice: feedError!,
              onRetry: onRetryFeed,
            ),
            if (storageError != null) _InfraBanner(
              key: const Key('storage_error'),
              icon: Icons.sd_card_alert_outlined,
              notice: storageError!,
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

/// Aviso de infraestrutura no painel.
///
/// Azul, e não vermelho: `docs/telas-acs.md` reserva a cor para a gravidade
/// clínica, e um card vermelho de "sem conexão" competia visualmente com o
/// alerta vermelho de um paciente logo abaixo, na mesma lista.
///
/// A `Key` vem de fora e é o único identificador do aviso — pô-la também no
/// `ListTile` faria `find.byKey` achar dois widgets.
class _InfraBanner extends StatelessWidget {
  const _InfraBanner({required this.icon, required this.notice, super.key, this.onRetry});

  final IconData icon;
  final InfraNotice notice;

  /// Presente só nas falhas transitórias — ver [DashboardScreen.onRetryFeed].
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Card(
          color: AcsColors.accent.withValues(alpha: 0.15),
          child: ListTile(
            leading: Icon(icon, color: AcsColors.accent),
            title: Text(notice.title, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(notice.detail),
            trailing: onRetry == null ? null : TextButton(
              key: const Key('retry_feed'),
              onPressed: onRetry,
              child: const Text('Tentar agora'),
            ),
          ),
        ),
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

class MapScreen extends StatefulWidget {
  const MapScreen({
    required this.queue,
    this.currentPosition,
    this.apiKey = '',
    this.onVisit,
    super.key,
  });

  final AlertQueue queue;
  final LatLng? currentPosition;
  final String apiKey;
  final void Function(PrioritizedAlert alert)? onVisit;

  static const LatLng _fallbackCenter = LatLng(-15.7942, -47.8828);

  static LatLng alertPositionFor(PrioritizedAlert alert) {
    final hash = alert.locationHash;
    final seed = hash.codeUnits.fold<int>(0, (sum, code) => sum + code) % 1000;
    final lat = -15.7942 + ((seed % 7) * 0.0025);
    final lng = -47.8828 + (((seed ~/ 7) % 9) * 0.0035);
    return LatLng(lat, lng);
  }

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  PrioritizedAlert? _selectedAlert;
  List<LatLng> _routePoints = const <LatLng>[];
  RoutePlan? _routePlan;
  final RouteService _routeService = const RouteService(speedKmh: 20);

  void _buildRouteFor([PrioritizedAlert? alert]) {
    final target = alert ?? _selectedAlert ?? (widget.queue.alerts.isEmpty ? null : widget.queue.alerts.first);
    final origin = widget.currentPosition;
    if (target == null || origin == null) {
      setState(() {
        _routePoints = const <LatLng>[];
        _routePlan = null;
      });
      _message(context, 'Sem posição atual ou alerta disponível para traçar a rota.');
      return;
    }

    final destination = _markerPosition(target);
    final plan = _routeService.plan(origin: origin, destination: destination);
    setState(() {
      _selectedAlert = target;
      _routePoints = plan.points;
      _routePlan = plan;
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.queue,
        builder: (context, _) {
          final hasApiKey = widget.apiKey.trim().isNotEmpty;
          final center = widget.currentPosition ?? MapScreen._fallbackCenter;
          final markers = <Marker>{
            if (widget.currentPosition != null)
              Marker(
                markerId: const MarkerId('acs_location'),
                position: widget.currentPosition!,
                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
                infoWindow: const InfoWindow(title: 'Localização atual'),
              ),
            for (final alert in widget.queue.alerts)
              Marker(
                markerId: MarkerId('alert_${alert.alertId}'),
                position: _markerPosition(alert),
                icon: _markerColor(alert.riskLevel),
                consumeTapEvents: true,
                onTap: () {
                  _buildRouteFor(alert);
                  _showAlertDetail(context, alert);
                },
                infoWindow: InfoWindow(
                  title: 'Paciente ${alert.patientId.substring(0, 8)}',
                  snippet: '${_riskLabel(alert.riskLevel)} • ${_time(alert.triggeredAt)}',
                ),
              ),
          };

          final polylines = <Polyline>{
            if (_routePoints.length >= 2)
              Polyline(
                polylineId: const PolylineId('route_active'),
                points: _routePoints,
                color: AcsColors.accent,
                width: 6,
              ),
          };

          final map = hasApiKey
              ? GoogleMap(
                  initialCameraPosition: CameraPosition(target: center, zoom: 13),
                  markers: markers,
                  polylines: polylines,
                  myLocationEnabled: widget.currentPosition != null,
                  myLocationButtonEnabled: false,
                  mapToolbarEnabled: false,
                  onTap: (_) => setState(() => _selectedAlert = null),
                )
              : Container(
                  height: 260,
                  decoration: const BoxDecoration(
                    color: AcsColors.surface,
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                  child: const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Mapa operacional indisponível sem chave de API do Google Maps.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                );

          return _page([
            const Text('Mapa operacional', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              widget.currentPosition == null
                  ? 'Localização atual indisponível. Exibindo centro do território.'
                  : 'Localização atual',
            ),
            if (_selectedAlert != null) ...[
              const SizedBox(height: 12),
              _AlertMapSummary(alert: _selectedAlert!),
            ],
            if (_routePlan != null) ...[
              const SizedBox(height: 8),
              Text(
                switch (_routePlan!.status) {
                  RouteStatus.complete => 'Rota concluída • ${_routePlan!.distanceKm.toStringAsFixed(1)} km • ETA ${_routePlan!.etaMinutes} min',
                  _ => 'Rota ativa • ${_routePlan!.distanceKm.toStringAsFixed(1)} km • ETA ${_routePlan!.etaMinutes} min',
                },
                style: const TextStyle(color: AcsColors.accent, fontWeight: FontWeight.bold),
              ),
              if (_routePlan!.status == RouteStatus.complete && _selectedAlert != null) ...[
                const SizedBox(height: 8),
                const Text(
                  'Local alcançado. Você pode abrir o registro de visita agora.',
                  style: TextStyle(color: AcsColors.green, fontWeight: FontWeight.bold),
                ),
              ],
            ],
            const SizedBox(height: 12),
            SizedBox(height: 260, child: map),
            const SizedBox(height: 12),
            if (_routePlan != null && _routePlan!.status == RouteStatus.complete && _selectedAlert != null) ...[
              FilledButton.icon(
                key: const Key('visit_at_destination'),
                onPressed: () => widget.onVisit?.call(_selectedAlert!),
                icon: const Icon(Icons.assignment_turned_in_outlined),
                label: const Text('Registrar visita no local'),
              ),
              const SizedBox(height: 12),
            ],
            const Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _LegendChip(color: AcsColors.red, label: 'Vermelho'),
                _LegendChip(color: AcsColors.yellow, label: 'Amarelo'),
                _LegendChip(color: AcsColors.green, label: 'Verde'),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => _buildRouteFor(),
              child: const Text('Traçar rota eficiente'),
            ),
          ]);
        },
      );

  void _showAlertDetail(BuildContext context, PrioritizedAlert alert) {
    final riskLabel = _riskLabel(alert.riskLevel);
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Paciente ${alert.patientId.substring(0, 8)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 8),
              Text('$riskLabel • ${_time(alert.triggeredAt)}', style: TextStyle(color: _riskColor(alert.riskLevel))),
              const SizedBox(height: 8),
              Text('Microárea: ${alert.microAreaId.substring(0, 8)}'),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _buildRouteFor(alert);
                      },
                      child: const Text('Traçar rota'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        widget.onVisit?.call(alert);
                      },
                      child: const Text('Ir para visita'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  child: const Text('Fechar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  BitmapDescriptor _markerColor(String riskLevel) {
    final normalized = riskLevel.toLowerCase();
    switch (normalized) {
      case 'red':
      case 'vermelho':
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
      case 'yellow':
      case 'amarelo':
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow);
      case 'green':
      case 'verde':
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
      default:
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
    }
  }

  Color _riskColor(String riskLevel) => switch (riskLevel.toLowerCase()) {
        'red' || 'vermelho' => AcsColors.red,
        'yellow' || 'amarelo' => AcsColors.yellow,
        'green' || 'verde' => AcsColors.green,
        _ => AcsColors.accent,
      };

  String _riskLabel(String riskLevel) => switch (riskLevel.toLowerCase()) {
        'red' || 'vermelho' => 'Vermelho',
        'yellow' || 'amarelo' => 'Amarelo',
        'green' || 'verde' => 'Verde',
        _ => 'Não classificado',
      };

  LatLng _markerPosition(PrioritizedAlert alert) => MapScreen.alertPositionFor(alert);

  String _time(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _AlertMapSummary extends StatelessWidget {
  const _AlertMapSummary({required this.alert});

  final PrioritizedAlert alert;

  @override
  Widget build(BuildContext context) {
    final color = switch (alert.riskLevel.toLowerCase()) {
      'red' || 'vermelho' => AcsColors.red,
      'yellow' || 'amarelo' => AcsColors.yellow,
      'green' || 'verde' => AcsColors.green,
      _ => AcsColors.accent,
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Icon(Icons.location_on, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Alerta selecionado: ${alert.patientId.substring(0, 8)} • ${switch (alert.riskLevel.toLowerCase()) { 'red' || 'vermelho' => 'Vermelho', 'yellow' || 'amarelo' => 'Amarelo', 'green' || 'verde' => 'Verde', _ => 'Não classificado' }}',
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(label),
          ],
        ),
      );
}

class VisitRegistrationScreen extends StatefulWidget {
  const VisitRegistrationScreen({required this.queue, super.key, this.alert, this.currentPosition});

  /// A fila é recebida pronta, não construída aqui: uma instância por gravação
  /// descartava a visita assim que o callback retornava.
  final OfflineVisitQueue queue;
  final PrioritizedAlert? alert;
  final LatLng? currentPosition;

  @override
  State<VisitRegistrationScreen> createState() => _VisitRegistrationScreenState();
}

class _VisitRegistrationScreenState extends State<VisitRegistrationScreen> {
  String outcome = 'Realizada com sucesso';
  final notes = TextEditingController();
  final _patientQuery = TextEditingController();
  bool _syncing = false;
  bool _arrivalConfirmed = false;

  /// Paciente escolhido no seletor, quando a visita não parte de um alerta.
  ///
  /// O nome vive só aqui, em memória, para o rótulo da tela — nunca é
  /// gravado. O que sai para a fila é sempre `MicroAreaPatient.patientId`,
  /// mesma disciplina do `alert.patientId` (LGPD-RF01).
  MicroAreaPatient? _selectedPatient;

  /// `null` = ainda não carregou. Buscado uma vez, em [didChangeDependencies],
  /// só quando a tela abre sem alerta — o caminho por alerta não precisa da
  /// lista.
  List<MicroAreaPatient>? _patients;
  BackendFailure? _patientsError;
  bool _loadingPatients = false;
  bool _patientsRequested = false;

  @override
  void initState() {
    super.initState();
    _arrivalConfirmed = _gpsArrivalMatches();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.alert == null && !_patientsRequested) {
      _patientsRequested = true;
      _loadPatients();
    }
  }

  @override
  void didUpdateWidget(covariant VisitRegistrationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentPosition != widget.currentPosition || oldWidget.alert != widget.alert) {
      _arrivalConfirmed = _gpsArrivalMatches();
    }
  }

  @override
  void dispose() { notes.dispose(); _patientQuery.dispose(); super.dispose(); }

  bool _gpsArrivalMatches() {
    final alert = widget.alert;
    final position = widget.currentPosition;
    if (alert == null || position == null) return false;

    final destination = MapScreen.alertPositionFor(alert);
    const routeService = RouteService();
    return routeService.arrivalStatus(origin: position, destination: destination) == ArrivalStatus.arrived;
  }

  /// Diretório de pacientes da microárea, para a visita de rotina.
  ///
  /// Falhar aqui NÃO pode travar a tela: o caminho por alerta continua
  /// funcionando mesmo sem rede (o app é offline-first), então o erro vira
  /// aviso com um jeito de tentar de novo, nunca uma tela presa.
  Future<void> _loadPatients() async {
    setState(() { _loadingPatients = true; _patientsError = null; });
    try {
      final result = await BackendScope.of(context).listPatients();
      if (!mounted) return;
      setState(() { _patients = result; _loadingPatients = false; });
    } on BackendFailure catch (failure) {
      if (!mounted) return;
      setState(() { _patientsError = failure; _loadingPatients = false; });
    }
  }

  /// Identificador efetivo: do alerta, ou do paciente escolhido no seletor.
  String? get _effectivePatientId => widget.alert?.patientId ?? _selectedPatient?.patientId;

  bool get _hasPatient => _effectivePatientId != null;

  /// Rótulo montado a cada build.
  ///
  /// Nunca é gravado: o que vai para a fila é sempre o UUID. Antes persistia-se
  /// este texto e o UUID era descartado, então o servidor recusava a visita
  /// por identificador inválido — e o disco guardava, sem precisar, uma linha
  /// legível sobre a pessoa.
  String get _patientLabel {
    final alert = widget.alert;
    if (alert != null) return 'Paciente ${alert.patientId.substring(0, 8)}';
    final selected = _selectedPatient;
    // Nome, e não UUID, aqui é minimização correta, não violação dela: é
    // exatamente o dado que spec/lgpd_design.md:364 autoriza para a visita de
    // rotina — "o ACS vê apenas o nome... cadastrado".
    if (selected != null) return selected.name;
    return 'Visita sem alerta vinculado';
  }

  Future<void> _save() async {
    final patientId = _effectivePatientId;
    // Sem paciente não há UUID, e `visits.sync` exige UUID: gravar aqui
    // criaria um registro que nunca sobe e nunca sai do aparelho.
    if (patientId == null) return;

    await widget.queue.add(OfflineVisitRecord(
      patientId: patientId,
      // Visita de rotina não tem risco: `BackendVisitSynchronizer` já trata
      // qualquer valor não reconhecido como RiskLevel.green, o piso seguro.
      risk: widget.alert?.riskLevel ?? 'rotina',
      status: 'PENDENTE',
      outcome: outcome,
      notes: notes.text.trim(),
    ));
    if (!mounted) return;
    setState(() {});
    _message(context, 'Visita salva e enfileirada localmente para sincronização.');
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);

    final SyncOutcome result;
    try {
      result = await widget.queue.sync();
    } finally {
      // A fila já captura falha de rede, mas um erro inesperado aqui deixaria
      // o botão desabilitado para o resto da sessão.
      if (mounted) setState(() => _syncing = false);
    }
    if (!mounted) return;

    _message(context, switch (result.kind) {
      SyncOutcomeKind.synced => '${result.processed} visita(s) enviada(s) ao servidor.',
      SyncOutcomeKind.conflict => '${result.processed} visita(s) em conflito. Continuam na fila para resolução.',
      SyncOutcomeKind.empty => 'Não há visitas pendentes.',
      SyncOutcomeKind.error => result.message ??
          (widget.queue.persistenceFailed
              ? 'Não foi possível sincronizar. As visitas estão apenas na memória deste aparelho.'
              : 'Não foi possível sincronizar. As visitas continuam salvas no aparelho.'),
    });
  }

  /// Seletor de pacientes da microárea, para quando a visita não vem de um
  /// alerta. Substitui o antigo aviso estático `visit_needs_alert`: antes a
  /// aba simplesmente dizia "selecione um alerta" e não havia outro caminho —
  /// e como o único produtor de alertas publica só risco vermelho (emergência,
  /// SAMU), a visita de rotina do PRD (≥ 8/dia) nunca tinha de onde partir.
  List<Widget> _buildPatientPicker() {
    if (_loadingPatients) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }

    final error = _patientsError;
    if (error != null) {
      return [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            key: const Key('patient_directory_error'),
            error.message,
            style: const TextStyle(color: AcsColors.accent, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: _loadPatients, child: const Text('Tentar de novo')),
      ];
    }

    final all = _patients ?? const [];
    if (all.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            key: Key('visit_needs_alert'),
            'Nenhum paciente cadastrado na sua microárea ainda. Selecione um '
            'alerta na fila para registrar a visita.',
            style: TextStyle(color: AcsColors.accent),
          ),
        ),
      ];
    }

    final query = _patientQuery.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? all
        : all.where((p) => p.name.toLowerCase().contains(query)).toList();

    return [
      const SizedBox(height: 8),
      TextField(
        key: const Key('patient_search'),
        controller: _patientQuery,
        decoration: const InputDecoration(labelText: 'Buscar paciente pelo nome'),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 8),
      ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 240),
        child: ListView(
          key: const Key('patient_picker'),
          shrinkWrap: true,
          children: [
            for (final patient in filtered)
              ListTile(
                key: Key('patient_${patient.patientId}'),
                title: Text(patient.name),
                subtitle: patient.isChronic
                    ? Text(patient.chronicConditions.join(', '))
                    : null,
                onTap: () => setState(() => _selectedPatient = patient),
              ),
            if (filtered.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Nenhum paciente encontrado com esse nome.'),
              ),
          ],
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final queue = widget.queue;
    final semAlerta = widget.alert == null;
    final selected = _selectedPatient;
    final hasPatient = _hasPatient;

    return _page([
      Text(_patientLabel, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      if (semAlerta && selected == null) ..._buildPatientPicker(),
      if (semAlerta && selected != null) Padding(
        padding: const EdgeInsets.only(top: 8),
        child: TextButton.icon(
          onPressed: () => setState(() => _selectedPatient = null),
          icon: const Icon(Icons.swap_horiz),
          label: const Text('Trocar paciente'),
        ),
      ),
      // Aqui, e não só no painel: é nesta tela que a pessoa acabou de gravar.
      // Obrigá-la a voltar para a Fila para descobrir que não salvou seria o
      // mesmo defeito de outra forma.
      if (queue.persistenceFailed) const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text(
          key: Key('visit_storage_error'),
          'As visitas não estão sendo salvas neste aparelho — elas só existem '
          'na memória até sincronizar.',
          style: TextStyle(color: AcsColors.accent, fontWeight: FontWeight.bold),
        ),
      ),
      const SizedBox(height: 16),
      if (hasPatient) CheckboxListTile(
        key: const Key('arrival_confirmation'),
        value: _arrivalConfirmed,
        onChanged: (value) => setState(() => _arrivalConfirmed = value ?? false),
        title: const Text('Cheguei ao local e confirmei a presença do paciente.'),
        contentPadding: EdgeInsets.zero,
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(initialValue: outcome, decoration: const InputDecoration(labelText: 'Status do atendimento'), items: const ['Realizada com sucesso', 'Paciente ausente', 'Recusou atendimento'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: !hasPatient || !_arrivalConfirmed ? null : (v) => setState(() => outcome = v!)),
      const SizedBox(height: 16),
      TextField(
        controller: notes,
        maxLines: 4,
        enabled: hasPatient && _arrivalConfirmed,
        decoration: const InputDecoration(
          labelText: 'Observações de campo',
          helperText: 'São salvas localmente e enviadas com a visita quando sincronizar.',
        ),
      ),
      const SizedBox(height: 20),
      FilledButton.icon(key: const Key('save_visit'), onPressed: !hasPatient || !_arrivalConfirmed ? null : _save, icon: const Icon(Icons.save_outlined), label: const Text('Salvar e enfileirar sincronização')),
      if (hasPatient && _arrivalConfirmed) ...[
        const SizedBox(height: 12),
        const Text(
          'Local alcançado. Você pode registrar a visita agora.',
          style: TextStyle(color: AcsColors.green, fontWeight: FontWeight.bold),
        ),
      ],
      const Divider(height: 32),
      Text(
        key: const Key('pending_visits_count'),
        'Pendentes de sincronização: ${queue.pendingCount}'
        '${queue.persistenceFailed ? ' (em memória)' : ''}',
      ),
      if (queue.conflictCount > 0) Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          key: const Key('conflict_visits_count'),
          'Em conflito: ${queue.conflictCount}',
          // Conflito de sincronização é operacional, não gravidade clínica.
          style: const TextStyle(color: AcsColors.accent, fontWeight: FontWeight.bold),
        ),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        key: const Key('sync_visits'),
        onPressed: _syncing || queue.pendingCount == 0 ? null : _sync,
        style: OutlinedButton.styleFrom(minimumSize: const Size(48, 52)),
        icon: _syncing
            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.cloud_upload_outlined),
        label: const Text('Sincronizar agora'),
      ),
    ]);
  }
}

class EscalationScreen extends StatelessWidget {
  const EscalationScreen({super.key, this.alert, this.onVisit});

  final PrioritizedAlert? alert;
  final void Function(PrioritizedAlert alert)? onVisit;

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
      if (current != null) ...[
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('escalation_visit'),
          onPressed: onVisit == null ? null : () => onVisit!(current),
          icon: const Icon(Icons.alt_route_outlined),
          label: const Text('Iniciar rota de visita'),
        ),
        const SizedBox(height: 8),
        const Text(
          'A visita é acompanhamento do caso e não substitui o acionamento do SAMU.',
          style: TextStyle(color: AcsColors.accent),
        ),
      ],
    ]);
  }
}
class GeofencingScreen extends StatelessWidget {
  const GeofencingScreen({
    required this.queue,
    this.currentPosition,
    this.onVisit,
    super.key,
  });

  final AlertQueue queue;
  final LatLng? currentPosition;
  final void Function(PrioritizedAlert alert)? onVisit;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: queue,
        builder: (context, _) {
          final alert = queue.alerts.firstOrNull;
          if (alert == null) {
            return _page([
              const Icon(Icons.location_searching, size: 44),
              const SizedBox(height: 16),
              const Text('Check-in passivo', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Nenhum alerta disponível para monitorar proximidade.'),
            ]);
          }

          final destination = MapScreen.alertPositionFor(alert);
          const routeService = RouteService();
          final status = routeService.arrivalStatus(origin: currentPosition, destination: destination);
          final distance = currentPosition == null
              ? null
              : routeService.distanceToDestination(origin: currentPosition!, destination: destination);

          return _page([
            const Icon(Icons.location_searching, size: 44),
            const SizedBox(height: 16),
            const Text('Check-in passivo', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _InfoRow('Paciente', 'Paciente ${alert.patientId.substring(0, 8)}'),
            _InfoRow('Risco', alert.riskLevel),
            _InfoRow('Raio de chegada', '${(routeService.arrivalThresholdKm * 1000).round()} m'),
            const SizedBox(height: 12),
            Text(
              switch (status) {
                ArrivalStatus.unavailable => 'Localização atual indisponível. O check-in não pode ser confirmado.',
                ArrivalStatus.approaching => 'A caminho do local${distance == null ? '' : ' • ${(distance * 1000).round()} m restantes'}.',
                ArrivalStatus.arrived => 'Local alcançado. O registro da visita está liberado.',
              },
              key: const Key('geofence_status'),
              style: TextStyle(
                color: status == ArrivalStatus.arrived ? AcsColors.green : AcsColors.accent,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('geofence_visit'),
              onPressed: status == ArrivalStatus.arrived ? () => onVisit?.call(alert) : null,
              icon: const Icon(Icons.assignment_turned_in_outlined),
              label: const Text('Abrir registro da visita'),
            ),
          ]);
        },
      );
}
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
/// Mostra uma mensagem, substituindo a anterior em vez de enfileirar.
///
/// Sem `hideCurrentSnackBar`, a confirmação da gravação ficava 4 s na tela e o
/// resultado da sincronização entrava na fila atrás dela: a pessoa tocava em
/// "Sincronizar agora" e continuava lendo "visita salva".
void _message(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}