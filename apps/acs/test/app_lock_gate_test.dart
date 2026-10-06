import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/app/acs_theme.dart';
import 'package:sinalacs_acs/app/app_lock_gate.dart';
import 'package:sinalacs_acs/core/security/biometric_gate.dart';

import 'support/layout_harness.dart' show redimensionar;

class FakeBiometricGate implements BiometricGate {
  UnlockResult result = UnlockResult.unlocked;
  int calls = 0;
  bool throwOnAuth = false;
  Completer<UnlockResult>? pending;
  @override
  Future<bool> get isAvailable async => true;
  @override
  Future<UnlockResult> authenticate({required String reason}) async {
    calls++;
    if (throwOnAuth) throw StateError('boom');
    if (pending != null) return pending!.future;
    return result;
  }
}

class _Painel extends StatefulWidget {
  const _Painel({required this.focus});
  final FocusNode focus;
  @override
  State<_Painel> createState() => _PainelState();
}

class _PainelState extends State<_Painel> {
  int n = 0;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      TextField(key: const Key('campo'), focusNode: widget.focus),
      Text('n=$n'),
      TextButton(
        onPressed: () => setState(() => n++),
        child: const Text('mais'),
      ),
    ],
  );
}

void main() {
  late FakeBiometricGate gate;
  late DateTime now;
  late FocusNode focus;
  late GlobalKey<NavigatorState> navKey;
  var passwordTaps = 0;

  setUp(() {
    gate = FakeBiometricGate();
    now = DateTime(2026, 10, 3, 12);
    focus = FocusNode();
    navKey = GlobalKey<NavigatorState>();
    passwordTaps = 0;
  });

  Future<void> pump(WidgetTester t) => t.pumpWidget(
    MaterialApp(
      navigatorKey: navKey,
      theme: buildAcsDarkTheme(),
      builder: (context, child) => AppLockGate(
        navigatorKey: navKey,
        gate: gate,
        clock: () => now,
        onUsePassword: () => passwordTaps++,
        child: child!,
      ),
      home: Scaffold(body: _Painel(focus: focus)),
    ),
  );

  Future<void> background(
    WidgetTester t,
    Duration away, {
    bool settle = true,
  }) async {
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = now.add(away);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    if (settle) await t.pumpAndSettle();
  }

  testWidgets('fica desbloqueado se voltar do segundo plano antes do prazo', (
    t,
  ) async {
    await pump(t);
    await background(t, const Duration(seconds: 10));
    expect(find.text('Aplicativo bloqueado'), findsNothing);
    expect(gate.calls, 0);
  });

  testWidgets('bloqueia ao voltar depois do prazo e mostra "Desbloquear"', (
    t,
  ) async {
    gate.result = UnlockResult.cancelled;
    await pump(t);
    await background(t, const Duration(seconds: 31));
    expect(find.text('Aplicativo bloqueado'), findsOneWidget);
    expect(find.text('Desbloquear'), findsOneWidget);
  });

  testWidgets(
    'o filho continua MONTADO e com o mesmo estado enquanto bloqueado',
    (t) async {
      gate.result = UnlockResult.cancelled;
      await pump(t);
      await t.enterText(find.byKey(const Key('campo')), 'rascunho');
      await t.tap(find.text('mais'));
      await t.pump();
      final navigator = t.state(find.byType(Navigator));
      await background(t, const Duration(minutes: 2));
      expect(find.text('Aplicativo bloqueado'), findsOneWidget);
      expect(find.text('n=1', skipOffstage: false), findsOneWidget);
      expect(find.text('rascunho', skipOffstage: false), findsOneWidget);
      expect(t.state(find.byType(Navigator)), same(navigator));
    },
  );

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

  testWidgets(
    'a cobertura não expõe o conteúdo ao leitor de tela nem a toques',
    (t) async {
      gate.result = UnlockResult.cancelled;
      await pump(t);
      await background(t, const Duration(minutes: 1));
      final sem = t.ensureSemantics();
      await t.tap(find.text('mais', skipOffstage: false), warnIfMissed: false);
      await t.pump();
      expect(find.text('n=0', skipOffstage: false), findsOneWidget);
      expect(find.semantics.byLabel('mais'), findsNothing);
      sem.dispose();
    },
  );

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

  testWidgets(
    'bloquear tira o foco e o campo não recebe foco nem texto enquanto bloqueado',
    (t) async {
      gate.result = UnlockResult.cancelled;
      await pump(t);
      await t.tap(find.byKey(const Key('campo')));
      await t.pump();
      expect(focus.hasFocus, isTrue);
      await background(t, const Duration(minutes: 1));
      expect(focus.hasFocus, isFalse);
      await t.tap(
        find.byKey(const Key('campo'), skipOffstage: false),
        warnIfMissed: false,
      );
      await t.pump();
      expect(focus.hasFocus, isFalse);
      await t
          .showKeyboard(find.byKey(const Key('campo'), skipOffstage: false))
          .catchError((_) {});
      expect(focus.hasFocus, isFalse);
    },
  );

  testWidgets(
    'voltar fica engolido enquanto bloqueado e funciona desbloqueado',
    (t) async {
      gate.result = UnlockResult.cancelled;
      final nav = GlobalKey<NavigatorState>();
      await t.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          theme: buildAcsDarkTheme(),
          builder: (context, child) => AppLockGate(
            gate: gate,
            clock: () => now,
            navigatorKey: nav,
            child: child!,
          ),
          home: const Scaffold(body: Text('raiz')),
        ),
      );
      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('segunda')),
        ),
      );
      await t.pumpAndSettle();
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('segunda'), findsNothing); // desbloqueado: voltou

      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('segunda')),
        ),
      );
      await t.pumpAndSettle();
      await background(t, const Duration(minutes: 1));
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(
        find.text('segunda', skipOffstage: false),
        findsOneWidget,
      ); // bloqueado: engolido
    },
  );

  testWidgets('relógio que anda para trás bloqueia', (t) async {
    gate.result = UnlockResult.cancelled;
    await pump(t);
    await background(t, const Duration(hours: -1));
    expect(find.text('Aplicativo bloqueado'), findsOneWidget);
  });

  testWidgets(
    'gate que lança falha fechada: continua bloqueado e oferece senha',
    (t) async {
      gate.throwOnAuth = true;
      await pump(t);
      await background(t, const Duration(minutes: 1));
      expect(find.text('Aplicativo bloqueado'), findsOneWidget);
      expect(find.text('Entrar com senha'), findsOneWidget);
      // _prompting foi liberado: o próximo toque não fica preso (botão de retry some em unavailable)
      expect(find.text('Desbloquear'), findsNothing);
    },
  );

  testWidgets(
    '"Desbloquear" some em lockedOut e unavailable; aparece após cancelar',
    (t) async {
      for (final r in [UnlockResult.lockedOut, UnlockResult.unavailable]) {
        gate.result = r;
        await pump(t);
        await background(t, const Duration(minutes: 1));
        expect(find.text('Desbloquear'), findsNothing, reason: '$r');
        await t.pumpWidget(const SizedBox());
      }
      gate.result = UnlockResult.cancelled;
      await pump(t);
      await background(t, const Duration(minutes: 1));
      expect(find.text('Desbloquear'), findsOneWidget);
    },
  );

  testWidgets('dispose do gate bloqueado remove o bloqueio do voltar', (
    t,
  ) async {
    gate.result = UnlockResult.cancelled;
    await pump(t);
    navKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('segunda')),
      ),
    );
    await t.pumpAndSettle();
    await background(t, const Duration(minutes: 1));
    // tira o gate da árvore (chave diferente) com o Navigator preservado
    await t.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        home: const Scaffold(body: Text('raiz')),
      ),
    );
    await t.pumpAndSettle();
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('segunda'), findsNothing);
  });

  testWidgets(
    'Navigator que aparece depois de bloquear recebe o bloqueio do voltar',
    (t) async {
      gate.result = UnlockResult.cancelled;
      final key = GlobalKey<NavigatorState>();
      var mostrar = false;
      late StateSetter set;
      await t.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: StatefulBuilder(
            builder: (c, s) {
              set = s;
              return AppLockGate(
                gate: gate,
                clock: () => now,
                navigatorKey: key,
                child: mostrar
                    ? Navigator(
                        key: key,
                        onGenerateRoute: (_) => MaterialPageRoute<void>(
                          builder: (_) => const Text('raiz'),
                        ),
                      )
                    : const SizedBox(),
              );
            },
          ),
        ),
      );
      await background(t, const Duration(minutes: 1));
      expect(key.currentState, isNull);
      set(() => mostrar = true);
      await t.pumpAndSettle();
      expect(key.currentState, isNotNull);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      // com o bloqueio instalado o pop é engolido; sem ele o app sairia (rota única)
      expect(find.text('raiz', skipOffstage: false), findsOneWidget);
      expect(
        key.currentState!.canPop(),
        isTrue,
      ); // há a rota-bloqueio empilhada
    },
  );

  testWidgets('descartar o gate com authenticate pendente não chama setState', (
    t,
  ) async {
    gate.pending = Completer<UnlockResult>();
    await pump(t);
    await background(t, const Duration(minutes: 1), settle: false);
    await t.pump();
    expect(gate.calls, 1);
    await t.pumpWidget(const SizedBox());
    gate.pending!.complete(UnlockResult.unlocked);
    await t.pump();
    expect(t.takeException(), isNull);
  });

  testWidgets('a cobertura não mostra dado de paciente', (t) async {
    gate.result = UnlockResult.cancelled;
    await pump(t);
    await background(t, const Duration(minutes: 1));
    final textos = find
        .descendant(
          of: find
              .ancestor(
                of: find.text('Aplicativo bloqueado'),
                matching: find.byType(SafeArea),
              )
              .first,
          matching: find.byType(Text),
        )
        .evaluate()
        .map((e) => (e.widget as Text).data)
        .toSet();
    expect(textos, {
      'Aplicativo bloqueado',
      'Alertas continuam chegando; eles estarão no painel ao desbloquear.',
      'Desbloquear',
      'Entrar com senha',
    });
  });

  for (final tema in [buildAcsDarkTheme(), buildAcsLightTheme()]) {
    testWidgets(
      'cobertura com fonte 2.0 não estoura (${tema.brightness.name})',
      (t) async {
        gate.result = UnlockResult.cancelled;
        redimensionar(t, const Size(320, 480), escalaDeFonte: 2.0);
        addTearDown(() {
          t.view.reset();
          t.platformDispatcher.clearTextScaleFactorTestValue();
        });
        await t.pumpWidget(
          MaterialApp(
            navigatorKey: navKey,
            theme: tema,
            builder: (context, child) => AppLockGate(
              gate: gate,
              clock: () => now,
              navigatorKey: navKey,
              child: child!,
            ),
            home: const Scaffold(body: Text('x')),
          ),
        );
        await background(t, const Duration(minutes: 1));
        expect(find.text('Aplicativo bloqueado'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  }
}
