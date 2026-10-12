/// Atualização quase em tempo real do backoffice por pulso (#44; ADR
/// `docs/superpowers/specs/2026-10-11-adr-tempo-real-alertas-admin.md`, D5).
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:sinalacs_admin/app/admin_async_states.dart';
import 'package:sinalacs_admin/core/data/admin_data_source.dart';

/// Dono do **único** timer e do **único** pulso por ciclo do app.
///
/// As telas de monitoração (painel e lista de alertas) o observam como
/// [ChangeNotifier] e se anexam com [attach]/[detach]: o ciclo só existe com
/// pelo menos uma tela anexada, porque o pulso abre uma sessão de
/// monitoramento auditada no servidor (`MONITORING_SESSION_START`) e não faz
/// sentido mantê-la aberta com o coordenador na Auditoria ou nas Microáreas.
/// Ao anexar a primeira tela, o 1º pulso sai na hora; ao desanexar a última,
/// o timer para e `endMonitoringSession` é disparado sem `await`.
///
/// Numa troca de aba entre Painel e Alertas a tela nova é montada (initState,
/// [attach]) antes de a antiga ser descartada (dispose, [detach]): a contagem
/// vai de 1 a 2 e volta a 1, sem fechar a sessão nem reiniciar o ciclo.
///
/// Falha do pulso nunca apaga dado na tela: só move o estado [stale].
/// [AdminSessionExpired] não vira selo: para o ciclo e chama
/// [onSessionExpired], o mesmo encerramento de sessão do resto do app.
class MonitoringController extends ChangeNotifier with WidgetsBindingObserver {
  MonitoringController({
    required this.dataSource,
    this.pollInterval = const Duration(seconds: 30),
    DateTime Function()? now,
    this.onSessionExpired,
  }) : now = now ?? DateTime.now;

  final AdminDataSource dataSource;

  /// Intervalo entre pulsos (ADR: 30 s).
  final Duration pollInterval;

  /// Relógio injetável: o estado [stale] é medido nele.
  final DateTime Function() now;

  /// Encerramento da sessão vencida. O `AdminHomeShell` passa o dele; uma
  /// tela usada isoladamente preenche com o do `AdminSessionScope`, se houver.
  VoidCallback? onSessionExpired;

  /// Estados em que o app conta como fora de primeiro plano: o timer pausa.
  static const _foraDoPrimeiroPlano = {
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  };

  int _telas = 0;
  Timer? _timer;
  bool _emSegundoPlano = false;
  bool _emVoo = false;
  bool _sessaoAberta = false;
  bool _sessaoVencida = false;
  bool _descartado = false;

  AlertsPulse? _ultimoPulso;
  DateTime? _ultimoSucesso;
  int _revisao = 0;

  /// Último pulso bem-sucedido; `null` antes do primeiro do ciclo.
  AlertsPulse? get lastPulse => _ultimoPulso;

  /// Instante (no relógio [now]) do último pulso ou carregamento de tela
  /// bem-sucedido.
  DateTime? get lastSuccess => _ultimoSucesso;

  /// Sobe quando um pulso difere do anterior em `maxChangedAt` **ou** nas
  /// contagens (`maxChangedAt` é cego a alerta que sai do escopo). A lista
  /// recarrega quando vê a revisão mudar; o 1º pulso só faz a linha de base.
  int get revision => _revisao;

  /// Limite de "desatualizado": 2 × o intervalo (tolera um pulso falho).
  Duration get staleAfter => pollInterval * 2;

  /// Desatualizado quando `now − lastSuccess` passa de [staleAfter].
  bool get stale {
    final ultimo = _ultimoSucesso;
    return ultimo != null && now().difference(ultimo) > staleAfter;
  }

  @visibleForTesting
  bool get timerActive => _timer?.isActive ?? false;

  void attach() {
    if (_descartado) return;
    if (_telas++ == 0) _iniciar();
  }

  void detach() {
    if (_telas == 0) return;
    if (--_telas == 0) _parar();
  }

  /// Uma tela carregou dado do servidor com sucesso (carregamento inicial ou
  /// recarga da lista).
  void reportSuccess() {
    if (_descartado) return;
    _ultimoSucesso = now();
    notifyListeners();
  }

  /// A recarga de uma tela falhou: o dado anterior fica; só o selo pode mudar.
  void reportFailure() {
    if (_descartado) return;
    notifyListeners();
  }

  void _iniciar() {
    WidgetsBinding.instance.addObserver(this);
    // Ciclo novo, linha de base nova: a tela recém-montada já carrega sozinha.
    _ultimoPulso = null;
    _ultimoSucesso = null;
    _emSegundoPlano = false;
    _retomar();
  }

  void _parar() {
    WidgetsBinding.instance.removeObserver(this);
    _suspender();
  }

  void _retomar() {
    if (_sessaoVencida) return;
    _timer?.cancel();
    _timer = Timer.periodic(pollInterval, (_) => _pulsar());
    _pulsar();
  }

  void _suspender() {
    _timer?.cancel();
    _timer = null;
    _encerrarSessao();
  }

  /// Melhor esforço, sem `await`: o END não tem timeout e o app pode estar
  /// sendo fechado. O servidor fecha sessão órfã sozinho (90 s).
  void _encerrarSessao() {
    if (!_sessaoAberta || _sessaoVencida) return;
    _sessaoAberta = false;
    unawaited(dataSource.endMonitoringSession().catchError((Object _) {}));
  }

  Future<void> _pulsar() async {
    // Um pulso por vez: um ciclo que chega com o anterior em voo é pulado.
    if (_emVoo || _sessaoVencida || _descartado) return;
    _emVoo = true;
    _sessaoAberta = true;
    try {
      final pulso = await dataSource.alertsPulse();
      if (_descartado || _telas == 0) return;
      final anterior = _ultimoPulso;
      if (anterior != null && _mudou(anterior, pulso)) _revisao++;
      _ultimoPulso = pulso;
      _ultimoSucesso = now();
      notifyListeners();
    } on AdminSessionExpired {
      _vencerSessao();
    } catch (_) {
      if (_descartado || _telas == 0) return;
      notifyListeners();
    } finally {
      _emVoo = false;
    }
  }

  void _vencerSessao() {
    if (_sessaoVencida) return;
    _sessaoVencida = true;
    _timer?.cancel();
    _timer = null;
    onSessionExpired?.call();
  }

  static bool _mudou(AlertsPulse a, AlertsPulse b) {
    if (a.maxChangedAt != b.maxChangedAt || a.overdueRed != b.overdueRed) return true;
    final ia = a.indicators;
    final ib = b.indicators;
    if (ia.openRedAlerts != ib.openRedAlerts ||
        ia.acknowledgedRedAlerts != ib.acknowledgedRedAlerts ||
        ia.tmravSeconds != ib.tmravSeconds) {
      return true;
    }
    return RiskLevel.values.any((nivel) => (ia.countsByRisk[nivel] ?? 0) != (ib.countsByRisk[nivel] ?? 0));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_telas == 0 || _descartado) return;
    if (state == AppLifecycleState.resumed) {
      if (!_emSegundoPlano) return;
      _emSegundoPlano = false;
      // Pulso imediato ao voltar; a linha de base é mantida, então o que mudou
      // em segundo plano recarrega a lista.
      _retomar();
    } else if (_foraDoPrimeiroPlano.contains(state) && !_emSegundoPlano) {
      _emSegundoPlano = true;
      _suspender();
    }
  }

  /// O dono (shell ou tela isolada) descarta: para o timer e dispara o END se
  /// a sessão ainda estiver aberta (normalmente as telas já se desanexaram).
  @override
  void dispose() {
    if (_telas > 0) {
      _telas = 0;
      _parar();
    } else {
      _encerrarSessao();
    }
    _descartado = true;
    super.dispose();
  }
}

/// Liga uma tela de monitoração ao [MonitoringController]: usa o injetado (o
/// do `AdminHomeShell`, compartilhado entre as telas) ou, sem ele, cria e
/// descarta o próprio — a tela usada isoladamente continua funcionando.
mixin MonitoredScreenState<T extends StatefulWidget> on State<T> {
  /// O controlador vindo do widget, ou `null` para a tela criar o seu.
  MonitoringController? get injectedMonitoring;
  AdminDataSource get monitoredDataSource;

  late final MonitoringController monitoring;
  bool _donoDoMonitoramento = false;

  /// Chamado a cada mudança do controlador. Por padrão, reconstrói a tela.
  void onMonitoringChanged() => setState(() {});

  void _aoMudar() {
    if (mounted) onMonitoringChanged();
  }

  @override
  void initState() {
    super.initState();
    final injetado = injectedMonitoring;
    if (injetado != null) {
      monitoring = injetado;
    } else {
      _donoDoMonitoramento = true;
      monitoring = MonitoringController(dataSource: monitoredDataSource)
        ..onSessionExpired = () {
          if (mounted) AdminSessionScope.maybeOf(context)?.call();
        };
    }
    monitoring
      ..addListener(_aoMudar)
      ..attach();
  }

  @override
  void dispose() {
    monitoring
      ..removeListener(_aoMudar)
      ..detach();
    if (_donoDoMonitoramento) monitoring.dispose();
    super.dispose();
  }
}
