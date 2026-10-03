import 'package:flutter/material.dart';

import '../core/security/biometric_gate.dart';
import 'acs_theme.dart';

/// Bloqueio por inatividade. Deve ficar ACIMA do Navigator (`MaterialApp.builder`)
/// para cobrir também as rotas empilhadas. O [child] nunca é desmontado: o
/// estado do painel (formulários, rotas) sobrevive ao bloqueio.
class AppLockGate extends StatefulWidget {
  const AppLockGate({
    super.key,
    required this.gate,
    required this.child,
    this.lockAfter = const Duration(seconds: 30),
    this.clock,
    this.onUsePassword,
  });

  final BiometricGate gate;
  final Widget child;
  final Duration lockAfter;
  final DateTime Function()? clock;
  final VoidCallback? onUsePassword;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  static const _reason = 'Desbloqueie o SinalACS para continuar';

  DateTime? _leftAt;
  bool _locked = false;
  bool _prompting = false;
  UnlockResult? _last;

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
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _leftAt ??= (widget.clock ?? DateTime.now)();
    } else if (state == AppLifecycleState.resumed) {
      final left = _leftAt;
      _leftAt = null;
      if (left == null || _locked) return;
      if ((widget.clock ?? DateTime.now)().difference(left) >= widget.lockAfter) {
        setState(() {
          _locked = true;
          _last = null;
        });
        _prompt();
      }
    }
  }

  Future<void> _prompt() async {
    if (_prompting) return;
    _prompting = true;
    final result = await widget.gate.authenticate(reason: _reason);
    _prompting = false;
    if (!mounted) return;
    setState(() {
      _last = result;
      if (result == UnlockResult.unlocked) _locked = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final blockedOut = _last == UnlockResult.lockedOut || _last == UnlockResult.unavailable;
    return Stack(
      children: [
        ExcludeSemantics(
          excluding: _locked,
          child: IgnorePointer(ignoring: _locked, child: widget.child),
        ),
        if (_locked)
          Positioned.fill(
            child: _LockCover(
              message: switch (_last) {
                UnlockResult.lockedOut => 'Biometria bloqueada por tentativas. Entre com a senha.',
                UnlockResult.unavailable => 'Desbloqueio do aparelho indisponível. Entre com a senha.',
                _ => 'Alertas continuam chegando; eles estarão no painel ao desbloquear.',
              },
              canRetry: !blockedOut,
              onRetry: _prompt,
              onUsePassword: widget.onUsePassword,
            ),
          ),
      ],
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
                  child: Icon(Icons.fingerprint, size: 72, color: context.acsRisk.accentOnSurface),
                ),
                const SizedBox(height: 16),
                Text('Aplicativo bloqueado', style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
