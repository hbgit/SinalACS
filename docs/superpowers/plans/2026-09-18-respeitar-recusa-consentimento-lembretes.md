# Respeitar a recusa de consentimento de lembretes locais (LGPD) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the patient app actually respect a refusal recorded in `consent_logs` for `ConsentPurpose.localReminders` — today the refusal is written once during onboarding and never read again, so `RemindersScreen` schedules on-device notifications regardless of what the person chose.

**Architecture:** Onboarding already asks the three consent questions and sends them to the backend, but the in-memory answer is discarded the moment `completeEnrollment` returns — the app has no local memory of what the person decided. This plan adds a small local (on-device, SQLite-backed, no new backend endpoint) `ConsentPreferences` store that mirrors the `localReminders` answer at the moment it's known (onboarding completion), then gates every place `RemindersScreen` would call `ReminderScheduler.schedule` on that stored value. The default when no record exists is **denied** (fail closed) — the worst-case interpretation of missing data, not the most convenient one.

**Tech Stack:** Flutter (`apps/patient`), `sqflite`/`sqflite_common_ffi` (already a dependency, same pattern as `SqfliteReminderStore`), `flutter_test` widget tests.

**Spec:** [spec/lgpd_design.md](../../../spec/lgpd_design.md) (LGPD-RF02/RF04), [docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md](../specs/2026-09-16-decisoes-produto-pos-validacao.md) §2 (consent-per-purpose decision) and §3.1 (RF06 is local-to-device, no backend endpoint, no sync).

## Global Constraints

- RF06 (local reminders) is device-local by product decision — this plan must not introduce a new backend endpoint or a sync mechanism for the consent flag. It mirrors the answer locally, the same way reminders themselves are local-only.
- Default-deny: any state where the local consent record is missing, unreadable, or ambiguous must be treated as **not granted**, never as granted.
- `ConsentPurpose.segmentedPush` is explicitly **out of scope for enforcement** in this plan — see the warning in Task 5. Do not add gating code for it; document why instead.
- Every new/changed write path must keep the existing try/catch + inline-error convention already used throughout `RemindersScreen`/`OnboardingScreen` (no unhandled exceptions bubbling out of a widget callback).
- Run `cd apps/patient && flutter analyze && flutter test` after every task; do not move to the next task with a red suite.

---

### Task 1: `ConsentPreferences` — local, fail-closed store for the `localReminders` consent answer

**Files:**
- Create: `apps/patient/lib/core/consent/consent_preferences.dart`
- Create: `apps/patient/lib/core/consent/sqflite_consent_preferences.dart`
- Test: `apps/patient/test/consent/sqflite_consent_preferences_test.dart`

**Interfaces:**
- Produces: `abstract interface class ConsentPreferences { Future<bool> localRemindersGranted(); Future<void> saveLocalRemindersConsent(bool granted); }` and `class SqfliteConsentPreferences implements ConsentPreferences`, constructor `SqfliteConsentPreferences({String databaseName = 'sinalacs_patient_consent.db'})` — used by Task 2 to wire into `SinalAcsApp`.

- [ ] **Step 1: Write the failing test**

```dart
// apps/patient/test/consent/sqflite_consent_preferences_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/core/consent/sqflite_consent_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SqfliteConsentPreferences store;

  setUp(() {
    // Banco em memória por teste — mesmo padrão de sqflite_reminder_store_test.dart.
    store = SqfliteConsentPreferences(databaseName: inMemoryDatabasePath);
  });

  tearDown(() => store.close());

  test('sem registro local, trata como recusado (fail closed)', () async {
    expect(await store.localRemindersGranted(), isFalse);
  });

  test('grava aceite e recupera', () async {
    await store.saveLocalRemindersConsent(true);
    expect(await store.localRemindersGranted(), isTrue);
  });

  test('grava recusa e recupera', () async {
    await store.saveLocalRemindersConsent(true);
    await store.saveLocalRemindersConsent(false);
    expect(await store.localRemindersGranted(), isFalse);
  });

  test('gravar de novo substitui o valor anterior sem duplicar linha', () async {
    await store.saveLocalRemindersConsent(false);
    await store.saveLocalRemindersConsent(true);
    await store.saveLocalRemindersConsent(true);
    expect(await store.localRemindersGranted(), isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/patient && flutter test test/consent/sqflite_consent_preferences_test.dart`
Expected: FAIL — `package:sinalacs_patient/core/consent/sqflite_consent_preferences.dart` does not exist (`Error: URI doesn't exist`).

- [ ] **Step 3: Write the interface**

```dart
// apps/patient/lib/core/consent/consent_preferences.dart

/// Espelho local (no aparelho) da decisão de consentimento tomada no
/// onboarding para `ConsentPurpose.localReminders`. A gravação de verdade
/// (evidência para auditoria/LGPD) é em `consent_logs`, no backend, pelo
/// fluxo de onboarding — este store existe só porque RF06 é local ao
/// aparelho, sem endpoint de backend (decisão §3.1 de
/// docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md), e
/// portanto o único jeito de `RemindersScreen` saber a resposta é guardar
/// uma cópia no momento em que ela é conhecida (conclusão do onboarding).
abstract interface class ConsentPreferences {
  /// `false` — inclusive quando não há nenhum registro local ainda — nunca
  /// `true` por omissão. Ausência de dado é tratada como recusa, não como
  /// aceite: o risco de agendar uma notificação sem consentimento é maior
  /// que o de deixar de agendar uma que teria sido permitida.
  Future<bool> localRemindersGranted();

  Future<void> saveLocalRemindersConsent(bool granted);
}
```

- [ ] **Step 4: Write the implementation**

```dart
// apps/patient/lib/core/consent/sqflite_consent_preferences.dart
import 'package:sinalacs_client/sinalacs_client.dart' show ConsentPurpose;
import 'package:sqflite/sqflite.dart' hide databaseFactory;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show databaseFactory;

import 'consent_preferences.dart';

/// Implementação de [ConsentPreferences] sobre SQLite comum (`sqflite`),
/// mesmo padrão de `SqfliteReminderStore`: não é dado de saúde, não precisa
/// de SQLCipher.
class SqfliteConsentPreferences implements ConsentPreferences {
  SqfliteConsentPreferences({this.databaseName = 'sinalacs_patient_consent.db'});

  static const _table = 'consent_preferences';
  final String databaseName;
  Database? _database;

  Future<Database> _open() async {
    final existing = _database;
    if (existing != null && existing.isOpen) return existing;

    return _database = await databaseFactory.openDatabase(
      databaseName,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) => db.execute('''
CREATE TABLE $_table (
  purpose TEXT PRIMARY KEY,
  granted INTEGER NOT NULL
)'''),
      ),
    );
  }

  @override
  Future<bool> localRemindersGranted() async {
    final db = await _open();
    final rows = await db.query(
      _table,
      where: 'purpose = ?',
      whereArgs: [ConsentPurpose.localReminders.name],
    );
    if (rows.isEmpty) return false;
    return (rows.first['granted'] as int) == 1;
  }

  @override
  Future<void> saveLocalRemindersConsent(bool granted) async {
    final db = await _open();
    await db.insert(
      _table,
      {
        'purpose': ConsentPurpose.localReminders.name,
        'granted': granted ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd apps/patient && flutter test test/consent/sqflite_consent_preferences_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 6: Commit**

```bash
git add apps/patient/lib/core/consent/consent_preferences.dart apps/patient/lib/core/consent/sqflite_consent_preferences.dart apps/patient/test/consent/sqflite_consent_preferences_test.dart
git commit -m "feat(patient): store local-reminders consent answer on device"
```

---

### Task 2: Wire `ConsentPreferences` into `SinalAcsApp`/`RemindersScope`

**Files:**
- Modify: `apps/patient/lib/app/app.dart:14-129` (`SinalAcsApp`, `_SinalAcsAppState`, `RemindersScope`)
- Modify: `apps/patient/test/patient_app_mvp_test.dart:332-341` (`buildRemindersScreen` helper)

**Interfaces:**
- Consumes: `ConsentPreferences`/`SqfliteConsentPreferences` from Task 1.
- Produces: `RemindersScope.consentPreferences` (a `ConsentPreferences`), read by Task 3 (`OnboardingScreen`) and Task 4 (`RemindersScreen`).

**Context:** `RemindersScope` is the existing `InheritedWidget` that already hands `ReminderStore`/`ReminderScheduler` down the tree (`apps/patient/lib/app/app.dart:109-129`), built once in `_SinalAcsAppState.build` (`apps/patient/lib/app/app.dart:60-75`) and constructed directly (bypassing `SinalAcsApp`) by one test helper. Both call sites need the new field.

- [ ] **Step 1: Add the field to `SinalAcsApp` and `_SinalAcsAppState`**

In `apps/patient/lib/app/app.dart`, add the import and extend the widget:

```dart
import 'package:sinalacs_patient/core/consent/consent_preferences.dart';
import 'package:sinalacs_patient/core/consent/sqflite_consent_preferences.dart';
```

```dart
class SinalAcsApp extends StatefulWidget {
  const SinalAcsApp({
    super.key,
    this.backend,
    this.locationReader,
    this.reminderStore,
    this.reminderScheduler,
    this.consentPreferences,
  });

  final PatientBackend? backend;
  final LocationReader? locationReader;
  final ReminderStore? reminderStore;
  final ReminderScheduler? reminderScheduler;

  /// Injetável para teste. Em execução normal é o [SqfliteConsentPreferences]
  /// real.
  final ConsentPreferences? consentPreferences;

  @override
  State<SinalAcsApp> createState() => _SinalAcsAppState();
}

class _SinalAcsAppState extends State<SinalAcsApp> {
  late final PatientBackend _backend = widget.backend ?? BackendClient();
  late final LocationReader _locationReader =
      widget.locationReader ?? const GeolocatorLocationReader();
  late final ReminderStore _reminderStore = widget.reminderStore ?? SqfliteReminderStore();
  late final ReminderScheduler _reminderScheduler =
      widget.reminderScheduler ?? LocalNotificationsReminderScheduler(FlutterLocalNotificationsPlugin());
  late final ConsentPreferences _consentPreferences =
      widget.consentPreferences ?? SqfliteConsentPreferences();
```

- [ ] **Step 2: Pass it through `build` and `RemindersScope`**

```dart
        child: RemindersScope(
          store: _reminderStore,
          scheduler: _reminderScheduler,
          consentPreferences: _consentPreferences,
          child: MaterialApp(
```

```dart
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
```

- [ ] **Step 3: Run the full test suite to see the now-broken call site**

Run: `cd apps/patient && flutter test`
Expected: FAIL — `patient_app_mvp_test.dart:335` (`RemindersScope(...)` missing required argument `consentPreferences`), compile error.

- [ ] **Step 4: Fix the test helper**

In `apps/patient/test/patient_app_mvp_test.dart`, add an import and a fake next to the other reminder doubles (after `_ThrowingReminderStore`, i.e. after line 92):

```dart
import 'package:sinalacs_patient/core/consent/consent_preferences.dart';
```

```dart
/// Duplo de [ConsentPreferences] com resposta fixa — por padrão simula
/// consentimento concedido, o cenário que os testes existentes de
/// `RemindersScreen` (criados antes deste consentimento existir) já
/// assumem implicitamente.
class _FixedConsentPreferences implements ConsentPreferences {
  _FixedConsentPreferences({this.granted = true});

  bool granted;

  @override
  Future<bool> localRemindersGranted() async => granted;

  @override
  Future<void> saveLocalRemindersConsent(bool value) async => granted = value;
}
```

Then update the helper (`apps/patient/test/patient_app_mvp_test.dart:333-341`) to accept and pass it, defaulting to granted so every existing call site keeps compiling and passing unchanged:

```dart
    Widget buildRemindersScreen(
      ReminderStore store,
      ReminderScheduler scheduler, {
      ConsentPreferences? consentPreferences,
    }) {
      return MaterialApp(
        home: RemindersScope(
          store: store,
          scheduler: scheduler,
          consentPreferences: consentPreferences ?? _FixedConsentPreferences(),
          child: const PatientHomeShell(initialDestination: PatientDestination.reminders),
        ),
      );
    }
```

(The six existing call sites at lines 344, 354, 378, 407, 425, 440, 463 all call `buildRemindersScreen(store, scheduler)` with two positional args, so the new optional named parameter does not require touching them.)

- [ ] **Step 5: Run the full test suite to verify it passes again**

Run: `cd apps/patient && flutter test`
Expected: PASS — all previously-passing tests still pass (the reminders group now runs with an implicit granted consent, unchanged behavior).

- [ ] **Step 6: Commit**

```bash
git add apps/patient/lib/app/app.dart apps/patient/test/patient_app_mvp_test.dart
git commit -m "feat(patient): thread ConsentPreferences through RemindersScope"
```

---

### Task 3: Persist the `localReminders` answer when onboarding completes

**Files:**
- Modify: `apps/patient/lib/app/app.dart` (`_OnboardingScreenState._complete`, around line 311-355)
- Modify: `apps/patient/test/onboarding_flow_test.dart`

**Interfaces:**
- Consumes: `RemindersScope.of(context).consentPreferences.saveLocalRemindersConsent(bool)` from Task 2.

**Context:** This is the only moment the app ever has the person's `localReminders` answer in hand — `_remindersConsent` (`apps/patient/lib/app/app.dart:299`) is a local `bool` in `_OnboardingScreenState` that today is sent to the backend via `completeEnrollment` (line 334) and then thrown away.

- [ ] **Step 1: Write the failing test**

Add to `apps/patient/test/onboarding_flow_test.dart` (needs a new import for `RemindersScope`/`ConsentPreferences`, and a fake — reuse the same shape as `_FixedConsentPreferences` from Task 2, duplicated locally since `patient_app_mvp_test.dart`'s private class isn't importable):

```dart
import 'package:sinalacs_patient/core/consent/consent_preferences.dart';
```

```dart
class _RecordingConsentPreferences implements ConsentPreferences {
  bool? saved;

  @override
  Future<bool> localRemindersGranted() async => saved ?? false;

  @override
  Future<void> saveLocalRemindersConsent(bool granted) async => saved = granted;
}
```

```dart
  testWidgets('concluir o cadastro com o consentimento de lembretes marcado grava isso localmente', (tester) async {
    final backend = FakePatientBackend();
    final consentPreferences = _RecordingConsentPreferences();
    await tester.pumpWidget(SinalAcsApp(backend: backend, consentPreferences: consentPreferences));
    await openOnboarding(tester);

    await tester.enterText(find.byKey(const Key('onboarding_token_field')), 'convite-123');
    await tapKey(tester, 'onboarding_consent_health');
    await tapKey(tester, 'onboarding_consent_reminders');
    await tapKey(tester, 'complete_enrollment_button');

    expect(consentPreferences.saved, isTrue);
  });

  testWidgets('concluir o cadastro com o consentimento de lembretes desmarcado grava a recusa localmente', (tester) async {
    final backend = FakePatientBackend();
    final consentPreferences = _RecordingConsentPreferences();
    await tester.pumpWidget(SinalAcsApp(backend: backend, consentPreferences: consentPreferences));
    await openOnboarding(tester);

    await tester.enterText(find.byKey(const Key('onboarding_token_field')), 'convite-123');
    await tapKey(tester, 'onboarding_consent_health');
    // onboarding_consent_reminders permanece desmarcado.
    await tapKey(tester, 'complete_enrollment_button');

    expect(consentPreferences.saved, isFalse);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/patient && flutter test test/onboarding_flow_test.dart`
Expected: FAIL — both new assertions fail with `saved: null` (nothing writes to the fake yet), or a compile error if `SinalAcsApp` doesn't yet accept `consentPreferences` (it does, from Task 2) — either way, red before the fix.

- [ ] **Step 3: Persist the answer in `_complete`**

In `apps/patient/lib/app/app.dart`, inside `_OnboardingScreenState._complete` (currently lines 330-354):

```dart
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
      await RemindersScope.of(context).consentPreferences.saveLocalRemindersConsent(_remindersConsent);
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/patient && flutter test test/onboarding_flow_test.dart`
Expected: PASS (7 tests: the 5 existing plus the 2 new ones)

- [ ] **Step 5: Run the full suite**

Run: `cd apps/patient && flutter test`
Expected: PASS — no regressions elsewhere.

- [ ] **Step 6: Commit**

```bash
git add apps/patient/lib/app/app.dart apps/patient/test/onboarding_flow_test.dart
git commit -m "feat(patient): persist local-reminders consent answer at onboarding"
```

---

### Task 4: Gate `RemindersScreen` on the stored consent — the actual enforcement

**Files:**
- Modify: `apps/patient/lib/app/app.dart` (`_RemindersScreenState`, lines 1038-1242)
- Modify: `apps/patient/test/patient_app_mvp_test.dart` (new tests in the `'Lembretes locais (RF06)'` group, lines 332-477)

**Interfaces:**
- Consumes: `RemindersScope.of(context).consentPreferences.localRemindersGranted()` from Task 2; `_FixedConsentPreferences` from Task 2's test helper.

**Context:** `_RemindersScreenState._toggleActive` (line 1078) and `._createOrEdit` (line 1115) both call `scope.scheduler.schedule(...)` unconditionally today — this is the exact call site that must never fire without consent. `_load` (line 1055) is where the reminder list is fetched; the consent flag is fetched the same way, once, on screen load.

- [ ] **Step 1: Write the failing tests**

Add to the `'Lembretes locais (RF06)'` group in `apps/patient/test/patient_app_mvp_test.dart`, after the existing `'tratamento de erro nas escritas'` group (before the closing `});` of the outer group, i.e. insert before line 477):

```dart
    group('consentimento recusado (LGPD)', () {
      testWidgets('recusa registrada bloqueia a criação e nunca chama o agendador', (tester) async {
        final store = _InMemoryReminderStore();
        final scheduler = _RecordingReminderScheduler();
        await tester.pumpWidget(buildRemindersScreen(
          store,
          scheduler,
          consentPreferences: _FixedConsentPreferences(granted: false),
        ));
        await tester.pumpAndSettle();

        final addButton = tester.widget<IconButton>(find.byKey(const Key('reminders_add_button')));
        expect(addButton.onPressed, isNull);

        expect(find.byKey(const Key('reminders_consent_denied_banner')), findsOneWidget);
        expect(scheduler.scheduled, isEmpty);
        expect(await store.list(), isEmpty);
      });

      testWidgets('recusa registrada bloqueia reativar um lembrete existente', (tester) async {
        final store = _InMemoryReminderStore();
        final seeded = await store.save(
          const Reminder(id: 0, label: 'Metformina 850 mg', hour: 7, minute: 0, active: false),
        );
        final scheduler = _RecordingReminderScheduler();
        await tester.pumpWidget(buildRemindersScreen(
          store,
          scheduler,
          consentPreferences: _FixedConsentPreferences(granted: false),
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(Key('reminder_switch_${seeded.id}')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('reminders_error')), findsOneWidget);
        expect(scheduler.scheduled, isEmpty);
        final after = await store.list();
        expect(after.single.active, isFalse);
      });

      testWidgets('consentimento concedido continua permitindo criar e agendar normalmente', (tester) async {
        final store = _InMemoryReminderStore();
        final scheduler = _RecordingReminderScheduler();
        await tester.pumpWidget(buildRemindersScreen(
          store,
          scheduler,
          consentPreferences: _FixedConsentPreferences(granted: true),
        ));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('reminders_consent_denied_banner')), findsNothing);

        await tester.tap(find.byKey(const Key('reminders_add_button')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('reminder_label_field')), 'Losartana 50 mg');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('reminder_save_button')));
        await tester.pumpAndSettle();

        final saved = await store.list();
        expect(saved, hasLength(1));
        expect(scheduler.scheduled, [saved.single.id]);
      });
    });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/patient && flutter test test/patient_app_mvp_test.dart`
Expected: FAIL — the first two new tests fail (`addButton.onPressed` is not null; `reminders_consent_denied_banner` not found; `scheduler.scheduled` is not empty) because nothing gates on consent yet. The third new test passes already (matches current behavior) — that's expected and fine, it's the regression guard.

- [ ] **Step 3: Load the consent flag alongside the reminder list**

In `apps/patient/lib/app/app.dart`, `_RemindersScreenState`:

```dart
class _RemindersScreenState extends State<RemindersScreen> {
  List<Reminder>? _reminders;
  String? _error;
  bool _requestedLoad = false;
  // Fail closed até o carregamento terminar: enquanto `_reminders` é `null`
  // a tela mostra o spinner, então o valor inicial aqui não chega a ser
  // exibido, mas ainda assim não deve ser `true` por padrão.
  bool _remindersConsentGranted = false;
```

```dart
  Future<void> _load() async {
    try {
      final scope = RemindersScope.of(context);
      final reminders = await scope.store.list();
      final consentGranted = await scope.consentPreferences.localRemindersGranted();
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
```

- [ ] **Step 4: Guard the two write paths that schedule notifications**

```dart
  static const _consentDeniedMessage =
      'Você recusou o consentimento para lembretes locais no cadastro — não é possível agendar notificações.';

  Future<void> _toggleActive(Reminder reminder, bool active) async {
    if (active && !_remindersConsentGranted) {
      setState(() => _error = _consentDeniedMessage);
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
```

```dart
  Future<void> _createOrEdit({Reminder? existing}) async {
    if (!_remindersConsentGranted) {
      setState(() => _error = _consentDeniedMessage);
      return;
    }
    final result = await showDialog<(String, int, int)>(
      context: context,
      builder: (context) => _ReminderFormDialog(existing: existing),
    );
```

(`_delete` is intentionally left untouched — removing/cancelling a reminder is always safe regardless of consent state.)

- [ ] **Step 5: Disable the add button and show the explanatory banner**

```dart
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
              onPressed: _remindersConsentGranted ? () => _createOrEdit() : null,
              icon: const Icon(Icons.add_alarm_outlined),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (!_remindersConsentGranted)
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
                child: const Text(
                  'Você recusou o consentimento para lembretes locais no cadastro. '
                  'Nenhuma notificação será agendada.',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ),
          ),
        if (_error != null)
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd apps/patient && flutter test test/patient_app_mvp_test.dart`
Expected: PASS — all tests in the file, including the 3 new ones.

- [ ] **Step 7: Run the full suite and analyzer**

Run: `cd apps/patient && flutter analyze && flutter test`
Expected: PASS, no analyzer warnings, all tests green.

- [ ] **Step 8: Commit**

```bash
git add apps/patient/lib/app/app.dart apps/patient/test/patient_app_mvp_test.dart
git commit -m "fix(patient): stop scheduling local reminders when consent was refused"
```

---

### Task 5: Correct the stale LGPD-RF02 note and document the `segmentedPush` gap in writing (the warning)

**Files:**
- Modify: `spec/lgpd_design.md` (the "Estado atual" note under LGPD-RF02, currently lines 61-66)

**Interfaces:** None — documentation only, no code.

**Context:** `spec/lgpd_design.md:61-66` says *"nenhum código do repositório grava uma linha [em `consent_logs`]"*, which is stale — `OnboardingService.completeEnrollment` has written rows since the onboarding feature shipped. Tasks 1-4 close the read-side gap for `localReminders`. `segmentedPush` has no sender anywhere in the repo (confirmed by full-repo search for `firebase_messaging`/`fcm`/`push_notification` — zero hits; RF14 is externally blocked on provisioning a Firebase project, per `docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md` §3.2), so there is nothing to gate yet — leaving it silently unaddressed would misrepresent this plan as closing the whole LGPD gap when it only closes the live half of it.

- [ ] **Step 1: Replace the stale note**

In `spec/lgpd_design.md`, replace the paragraph currently at lines 61-66:

```markdown
**Estado atual (verificado 2026-09-16):** a tabela `consent_logs` existe
migrada, mas nenhum código do repositório grava uma linha nela — não há
escritor. A decisão de produto que liga LGPD-RF02 ao onboarding via QR Code
(RF02) está registrada em
`docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md` §2
(três finalidades mínimas, token de convite de uso único, gravação no
backend no fechamento do onboarding). Ainda não implementada.
```

with:

```markdown
**Estado atual (verificado 2026-09-18):** `consent_logs` é gravada por
`OnboardingService.completeEnrollment` para as três finalidades (§2 de
`docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md`).
Do lado da leitura: `ConsentPurpose.localReminders` agora é respeitada —
`RemindersScreen` (`apps/patient/lib/app/app.dart`) só agenda notificações
locais quando o consentimento espelhado no aparelho
(`core/consent/consent_preferences.dart`) é `true`, com padrão de recusa
(`false`) quando não há registro local.

**Aviso — `ConsentPurpose.segmentedPush` continua sem leitor.** RF14 (avisos
segmentados por push) não tem nenhum código de envio no repositório ainda —
está bloqueado externamente na provisão de um projeto Firebase (§3.2 do
mesmo documento de decisões), não apenas pendente de implementação. Não há
o que "respeitar" hoje porque nada envia. Quando `notices.sendSegmented` for
implementado, ele **deve** consultar o consentimento de `segmentedPush`
antes de enviar, com o mesmo padrão de recusa por omissão adotado aqui para
`localReminders` — tratar isso como parte da implementação de RF14, não
como um item separado a lembrar depois.
```

- [ ] **Step 2: Commit**

```bash
git add spec/lgpd_design.md
git commit -m "docs: update LGPD-RF02 state, flag segmentedPush as still unenforced"
```

---

## Self-Review Notes

- **Spec coverage:** LGPD-RF02 (per-purpose consent, already implemented pre-plan) — Task 5 corrects its stale state note; the actual enforcement gap the user flagged ("grava a recusa mas nada lê") is closed for `localReminders` by Tasks 1-4; `segmentedPush` is explicitly out of scope with a written rationale (Task 5), matching the "fix with a warning" framing of the request.
- **No placeholders:** every step has real, complete code — no "add validation"/"handle edge cases" stand-ins.
- **Type consistency:** `ConsentPreferences.localRemindersGranted()`/`saveLocalRemindersConsent(bool)` (Task 1) are the exact names used unchanged through Tasks 2, 3, 4's tests and production code. `RemindersScope.consentPreferences` (Task 2) is the exact field name used in Task 3 (`_complete`) and Task 4 (`_load`).
