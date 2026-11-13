import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sinalacs_patient/core/events/local_event_log.dart';
import 'package:sinalacs_patient/core/services/emergency_dialer.dart';
import 'package:sinalacs_patient/core/triage/self_assessment.dart';

/// "Ligar 192" e a trilha local de eventos para a árvore de widgets (C-04, #127).
///
/// Mesmo padrão de `LocationScope`/`QrScannerScope`: a tela não constrói o
/// próprio discador nem a própria trilha, e o teste injeta duplos sem canal de
/// plataforma. Sem escopo acima, [dialerOf] cai no discador real e [eventsOf]
/// devolve `null` (a orientação aparece igual, só não grava).
class Call192Scope extends InheritedWidget {
  const Call192Scope({
    required this.dialer,
    required this.events,
    required super.child,
    super.key,
  });

  final EmergencyDialer dialer;

  /// `null` quando o app não tem banco local (lojas injetadas em teste).
  final LocalEventLog? events;

  static Call192Scope? _maybe(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Call192Scope>();

  static EmergencyDialer dialerOf(BuildContext context) =>
      _maybe(context)?.dialer ?? const UrlLauncherEmergencyDialer();

  static LocalEventLog? eventsOf(BuildContext context) => _maybe(context)?.events;

  @override
  bool updateShouldNotify(Call192Scope oldWidget) =>
      dialer != oldWidget.dialer || events != oldWidget.events;
}

/// Botão que abre o discador com 192. Nunca liga sozinho (`tel:`).
///
/// Alvo de 64×60dp, o mesmo da chamada ao SAMU no app do ACS. Sem cor clínica:
/// é uma ação, não um nível de risco (P-11, C-08).
class Call192Button extends StatelessWidget {
  const Call192Button({super.key = const Key('call_192_button')});

  Future<void> _dial(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final opened = await Call192Scope.dialerOf(context).dial(samuNumber);
    if (!opened) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('Não foi possível abrir o discador. Ligue 192 pelo telefone.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: () => _dial(context),
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 60),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      icon: const Icon(Icons.call),
      label: const Text('Ligar 192'),
    );
  }
}

/// Mostra a orientação "Ligar 192" da autoavaliação por cima de tudo, inclusive
/// da barra de navegação, e só volta quando a pessoa a fecha explicitamente.
///
/// **Não gera pedido de contato** (P-09, `spec/requisitos_piloto.md` §INV-03 no
/// piloto, item 2): não há chamada ao backend aqui. Querer também falar com o
/// agente é um ato separado, na aba Contato.
Future<void> showCall192Orientation(BuildContext context) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => const Call192OrientationScreen(),
    ),
  );
}

class Call192OrientationScreen extends StatefulWidget {
  const Call192OrientationScreen({super.key, this.clock = DateTime.now});

  /// Relógio do evento; injetável para teste.
  final DateTime Function() clock;

  @override
  State<Call192OrientationScreen> createState() => _Call192OrientationScreenState();
}

class _Call192OrientationScreenState extends State<Call192OrientationScreen> {
  bool _recorded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_recorded) return;
    _recorded = true;
    // A exibição fica registrada na trilha local cifrada, sem respostas
    // (§INV-03 no piloto, item 2b). A tela nunca espera a gravação: com o
    // banco indisponível a orientação aparece igual, e o erro é descartado sem
    // ir a log (a causa pode carregar material da custódia, como no #136).
    final events = Call192Scope.eventsOf(context);
    if (events == null) return;
    final event = LocalEvent(
      kind: LocalEventKind.call192OrientationShown,
      occurredAt: widget.clock().toUtc(),
      engineVersion: selfAssessmentEngineVersion,
    );
    unawaited(events.record(event).then<void>((_) {}, onError: (_) {}));
  }

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
    // Sem voltar pelo sistema nem pelo cabeçalho: fechar exige a escolha
    // explícita do botão abaixo (§INV-03 no piloto, item 2a).
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Orientação'),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Semantics(
                header: true,
                child: const Text(
                  key: Key('call_192_title'),
                  'Ligue 192 (SAMU) agora',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Pelas suas respostas, a orientação é ligar para o SAMU. '
                'O SinalACS não é um serviço de emergência e não avisou ninguém: '
                'só a ligação para o 192 chama socorro.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              const Call192Button(),
              const SizedBox(height: 16),
              Text(
                'Se não conseguir ligar, peça a alguém por perto para ligar 192.',
                textAlign: TextAlign.center,
                style: muted,
              ),
              const SizedBox(height: 32),
              OutlinedButton(
                key: const Key('call_192_close'),
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(minimumSize: const Size(48, 52)),
                child: const Text('Fechar esta orientação'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
