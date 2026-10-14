import 'dart:async';

/// Intervalo padrão do laço de disparo dos avisos agendados (#46).
const Duration defaultNoticeDispatchInterval = Duration(seconds: 30);

/// Laço periódico que dispara os avisos agendados vencidos.
///
/// Nunca morre por erro: uma falha em [tick] (ex.: banco fora) é registrada por
/// [onError] — que recebe só o erro, jamais texto de aviso — e o laço segue no
/// próximo ciclo. Não sobrepõe ciclos (um tick lento não empilha outro).
/// [startup] roda uma vez antes do primeiro ciclo (varredura de partida).
/// [timerFactory] existe para os testes injetarem um relógio.
class NoticeDispatchLoop {
  NoticeDispatchLoop({
    required Future<int> Function() tick,
    Future<void> Function()? startup,
    void Function(Object error)? onError,
    this.interval = defaultNoticeDispatchInterval,
    Timer Function(Duration, void Function(Timer))? timerFactory,
  })  : _tick = tick,
        _startup = startup,
        _onError = onError,
        _timerFactory = timerFactory ?? Timer.periodic;

  final Future<int> Function() _tick;
  final Future<void> Function()? _startup;
  final void Function(Object error)? _onError;
  final Timer Function(Duration, void Function(Timer)) _timerFactory;
  final Duration interval;

  Timer? _timer;
  bool _running = false;
  bool _stopped = false;
  Future<void>? _startupDone;

  bool get isStarted => _timer != null;

  void start() {
    if (_timer != null || _stopped) return;
    _startupDone = _runStartup();
    _timer = _timerFactory(interval, (_) => unawaited(runOnce()));
  }

  Future<void> _runStartup() async {
    final startup = _startup;
    if (startup == null) return;
    try {
      await startup();
    } catch (e) {
      _onError?.call(e);
    }
  }

  /// Um ciclo (público para os testes). Devolve quantos avisos processou.
  Future<int> runOnce() async {
    if (_running || _stopped) return 0;
    _running = true;
    try {
      await _startupDone;
      return await _tick();
    } catch (e) {
      _onError?.call(e);
      return 0;
    } finally {
      _running = false;
    }
  }

  /// Encerra o laço (shutdown); ciclo em andamento termina sozinho.
  void stop() {
    _stopped = true;
    _timer?.cancel();
    _timer = null;
  }
}
