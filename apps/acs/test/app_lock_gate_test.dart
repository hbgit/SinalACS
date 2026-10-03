import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/app/acs_theme.dart';
import 'package:sinalacs_acs/app/app_lock_gate.dart';
import 'package:sinalacs_acs/core/security/biometric_gate.dart';

class FakeBiometricGate implements BiometricGate {
  UnlockResult result = UnlockResult.unlocked;
  int calls = 0;
  @override
  Future<bool> get isAvailable async => true;
  @override
  Future<UnlockResult> authenticate({required String reason}) async {
    calls++;
    return result;
  }
}

void main() {
  late FakeBiometricGate gate;
  late DateTime now;
  late TextEditingController controller;
  var passwordTaps = 0;

  setUp(() {
    gate = FakeBiometricGate();
    now = DateTime(2026, 10, 3, 12);
    controller = TextEditingController();
    passwordTaps = 0;
  });

  Future<void> pump(WidgetTester t) => t.pumpWidget(MaterialApp(
        theme: buildAcsDarkTheme(),
        builder: (context, child) => AppLockGate(
          gate: gate,
          clock: () => now,
          onUsePassword: () => passwordTaps++,
          child: child!,
        ),
        home: Scaffold(body: TextField(controller: controller)),
      ));

  Future<void> background(WidgetTester t, Duration away, {bool settle = true}) async {
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = now.add(away);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    if (settle) await t.pumpAndSettle();
  }

  testWidgets('fica desbloqueado se voltar do segundo plano antes do prazo', (t) async {
    await pump(t);
    await background(t, const Duration(seconds: 10));
    expect(find.text('Aplicativo bloqueado'), findsNothing);
    expect(gate.calls, 0);
  });

  testWidgets('bloqueia ao voltar depois do prazo e mostra "Desbloquear"', (t) async {
    gate.result = UnlockResult.cancelled;
    await pump(t);
    await background(t, const Duration(seconds: 31));
    expect(find.text('Aplicativo bloqueado'), findsOneWidget);
    expect(find.text('Desbloquear'), findsOneWidget);
  });

  testWidgets('o filho continua MONTADO e com o mesmo estado enquanto bloqueado', (t) async {
    gate.result = UnlockResult.cancelled;
    await pump(t);
    await t.enterText(find.byType(TextField), 'rascunho');
    final navigator = t.state(find.byType(Navigator));
    await background(t, const Duration(minutes: 2));
    expect(find.text('Aplicativo bloqueado'), findsOneWidget);
    expect(find.byType(TextField, skipOffstage: false), findsOneWidget);
    expect(controller.text, 'rascunho');
    expect(t.state(find.byType(Navigator)), same(navigator));
  });

  testWidgets('desbloqueio bem-sucedido remove a cobertura', (t) async {
    await pump(t);
    await background(t, const Duration(minutes: 1));
    expect(gate.calls, 1);
    expect(find.text('Aplicativo bloqueado'), findsNothing);
  });

  testWidgets('cancelamento mantém bloqueado, sem laço de prompts', (t) async {
    gate.result = UnlockResult.cancelled;
    await pump(t);
    await background(t, const Duration(minutes: 1));
    expect(gate.calls, 1);
    await t.pumpAndSettle();
    expect(gate.calls, 1);
    await t.tap(find.text('Desbloquear'));
    await t.pumpAndSettle();
    expect(gate.calls, 2);
    expect(find.text('Aplicativo bloqueado'), findsOneWidget);
  });

  for (final r in [UnlockResult.lockedOut, UnlockResult.unavailable]) {
    testWidgets('$r oferece "Entrar com senha" e NÃO desbloqueia', (t) async {
      gate.result = r;
      await pump(t);
      await background(t, const Duration(minutes: 1));
      expect(find.text('Aplicativo bloqueado'), findsOneWidget);
      await t.tap(find.text('Entrar com senha'));
      expect(passwordTaps, 1);
      expect(find.text('Aplicativo bloqueado'), findsOneWidget);
    });
  }

  testWidgets('a cobertura não expõe o conteúdo ao leitor de tela nem a toques', (t) async {
    gate.result = UnlockResult.cancelled;
    await pump(t);
    await background(t, const Duration(minutes: 1));
    final field = find.byType(TextField, skipOffstage: false);
    final excludes = find.ancestor(of: field, matching: find.byType(ExcludeSemantics)).evaluate();
    expect(excludes.any((e) => (e.widget as ExcludeSemantics).excluding), isTrue);
    final ignores = find.ancestor(of: field, matching: find.byType(IgnorePointer)).evaluate();
    expect(ignores.any((e) => (e.widget as IgnorePointer).ignoring), isTrue);
  });

  testWidgets('abre o prompt sozinho ao bloquear', (t) async {
    gate.result = UnlockResult.cancelled;
    await pump(t);
    await background(t, const Duration(minutes: 1));
    expect(gate.calls, 1);
  });

  testWidgets('app que nunca saiu do primeiro plano não bloqueia', (t) async {
    await pump(t);
    now = now.add(const Duration(hours: 1));
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(find.text('Aplicativo bloqueado'), findsNothing);
    expect(gate.calls, 0);
  });
}
