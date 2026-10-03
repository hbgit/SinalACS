import 'package:flutter/material.dart';

import '../core/security/biometric_gate.dart';
import 'acs_theme.dart';

/// Bloqueio por inatividade. O [child] nunca é desmontado: o estado do painel
/// (formulários, rotas) sobrevive ao bloqueio.
///
/// Contrato para o chamador (Task 7):
/// (a) colocar em `MaterialApp.builder`, ACIMA do Navigator, para cobrir também
///     as rotas empilhadas;
/// (b) o estado de bloqueio vive só na memória: numa partida a frio o gate
///     nasce desbloqueado, então o chamador deve exigir `authenticate()` (ou a
///     senha) antes de mostrar dados quando houver sessão restaurada;
/// (d) passar `navigatorKey` (a mesma do MaterialApp) para o botão voltar do
///     Android ficar engolido enquanto bloqueado;
/// (c) `authenticate()` que falha, lança, ou volta `lockedOut`/`unavailable`
///     NUNCA desbloqueia: falha fechada, e a saída é "Entrar com senha"
///     (`onUsePassword`).
class AppLockGate extends StatefulWidget {
  const AppLockGate({
    super.key,
    required this.gate,
    required this.child,
    this.lockAfter = const Duration(seconds: 30),
    this.clock,
    this.onUsePassword,
    this.navigatorKey,
  });

  final BiometricGate gate;
  final Widget child;
  final Duration lockAfter;
  final DateTime Function()? clock;
  final VoidCallback? onUsePassword;

  /// Navigator do app. Como o gate fica ACIMA do Navigator, um `PopScope` aqui
  /// não intercepta o botão voltar do Android; com a chave, o gate empurra uma
  /// rota invisível com `canPop: false` enquanto bloqueado, que engole o voltar.
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  static const _reason = 'Desbloqueie o SinalACS para continuar';

  DateTime? _leftAt;
  bool _locked = false;
  bool _prompting = false;
  UnlockResult? _last;
  Route<void>? _backBlocker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _leftAt ??= (widget.clock ?? DateTime.now)();
    } else if (state == AppLifecycleState.resumed) {
      final left = _leftAt;
      _leftAt = null;
      if (left == null || _locked) return;
      final away = (widget.clock ?? DateTime.now)().difference(left);
      // Relógio que andou para trás também bloqueia: não dá para provar o prazo.
      if (away.isNegative || away >= widget.lockAfter) {
        setState(() {
          _locked = true;
          _last = null;
        });
        FocusManager.instance.primaryFocus?.unfocus();
        _blockBack();
        _prompt();
      }
    }
  }

  void _blockBack() {
    final nav = widget.navigatorKey?.currentState;
    if (nav == null || _backBlocker != null) return;
    final route = PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: false,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, __, ___) =>
          const PopScope(canPop: false, child: SizedBox.shrink()),
    );
    _backBlocker = route;
    nav.push(route);
  }

  void _unblockBack() {
    final route = _backBlocker;
    _backBlocker = null;
    final nav = route?.navigator;
    if (route != null && nav != null) {
      nav.removeRoute(route);
    }
  }

  Future<void> _prompt() async {
    if (_prompting) return;
    _prompting = true;
    UnlockResult result;
    try {
      result = await widget.gate.authenticate(reason: _reason);
    } catch (_) {
      result = UnlockResult.unavailable; // falha fechada
    } finally {
      _prompting = false;
    }
    if (!mounted) return;
    setState(() {
      _last = result;
      if (result == UnlockResult.unlocked) {
        _locked = false;
        _unblockBack();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final blockedOut =
        _last == UnlockResult.lockedOut || _last == UnlockResult.unavailable;
    return PopScope(
      canPop: !_locked,
      child: Stack(
        children: [
          ExcludeSemantics(
            excluding: _locked,
            child: ExcludeFocus(
              excluding: _locked,
              child: IgnorePointer(ignoring: _locked, child: widget.child),
            ),
          ),
          if (_locked)
            Positioned.fill(
              child: _LockCover(
                message: switch (_last) {
                  UnlockResult.lockedOut =>
                    'Biometria bloqueada por tentativas. Entre com a senha.',
                  UnlockResult.unavailable =>
                    'Desbloqueio do aparelho indisponível. Entre com a senha.',
                  _ =>
                    'Alertas continuam chegando; eles estarão no painel ao desbloquear.',
                },
                canRetry: !blockedOut,
                onRetry: _prompt,
                onUsePassword: widget.onUsePassword,
              ),
            ),
        ],
      ),
    );
  }
}

class _LockCover extends StatelessWidget {
  const _LockCover({
    required this.message,
    required this.canRetry,
    required this.onRetry,
    required this.onUsePassword,
  });

  final String message;
  final bool canRetry;
  final VoidCallback onRetry;
  final VoidCallback? onUsePassword;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const minSize = Size(double.infinity, 48);
    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: Icon(
                    Icons.fingerprint,
                    size: 72,
                    color: context.acsRisk.accentOnSurface,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Aplicativo bloqueado',
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (canRetry)
                  FilledButton(
                    style: FilledButton.styleFrom(minimumSize: minSize),
                    onPressed: onRetry,
                    child: const Text('Desbloquear'),
                  ),
                const SizedBox(height: 12),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: minSize),
                  onPressed: onUsePassword,
                  child: const Text('Entrar com senha'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
