# Finalização do app ACS — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fechar o que falta para o app `apps/acs` fazer, num aparelho de verdade, o que o PRD promete — GPS do check-in (RF12), acionamento do SAMU (RF13) — e provar a jornada inteira do ACS no `emulator-5554` com login real contra o banco de teste.

**Architecture:** Quatro correções independentes, cada uma com teste que falha antes: (1) manifesto Android declara o que o código já usa; (2) botão do SAMU abre o discador por uma interface injetável; (3) o caminho de GPS real do check-in é provado no emulador com `adb emu geo fix`; (4) um e2e do ACS no molde do `patient_full_e2e.sh` (banco `sinalacs_e2e`, fixtures sintéticas, login institucional pela tela). O resto é documentação e a barra final.

**Tech Stack:** Flutter 3 / Dart, `geolocator`, `url_launcher` (nomeado no PRD, RF13), `integration_test`, Docker Compose (`docker-compose.e2e.yml`), bash, Python 3 (`otp_relay.py`), `adb`.

**Spec:** `spec/PRD_system.md` (RF07–RF13, §2.2), `docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md` (§4 geofencing: só em primeiro plano, sem localização em background), `spec/lgpd_design.md`, `apps/CLAUDE.md`.

> **Desvios da execução (2026-10-01) — leia antes do resto.** O plano abaixo é o que
> foi escrito; o que foi entregue difere em dois pontos, ambos medidos:
> 1. **Task 3 não prova o fix de GPS.** Neste AVD (Android 16, Play Services) nem
>    `adb emu geo fix`, nem provider de teste, nem `forceLocationManager` entregam
>    posição ao app. O e2e prova a **permissão** em runtime (e falha com o manifesto
>    antigo); "Local alcançado" com posição segue coberto só por testes com posição
>    injetada. Onde o texto abaixo diz "GPS real"/`adb emu geo fix`, leia isto.
> 2. **Task 4 não cobre MQTT/ACK.** O `aclfile` do broker só libera o UUID de
>    microárea do seed de dev e as fixtures de e2e são aleatórias. Onde o texto
>    diz "alerta MQTT"/"ACK" no e2e do banco de teste, leia isto; o alerta pelo
>    broker segue provado por `smoke`/`red_alert_cycle` na stack de dev.
> Também mudaram: nomes `*_e2e.dart`, `flutter drive` na Task 3, e um defeito do
> `dispose` do painel corrigido na Task 4. Os `Ruling:` completos estão no PROGRESS.md.

## Estado verificado em 2026-10-01

Medido nesta sessão, não herdado de documento:

- `flutter analyze` em `apps/acs`: **No issues found**. `flutter test`: **198 passam**.
- `emulator-5554` **não estava no ar** (`adb devices` vazio; `adb` não está no `PATH`). AVDs existentes: `Medium_Phone`, `Medium_Tablet`. Foi iniciado com `emulator -avd Medium_Phone -port 5554 -no-snapshot-save -no-boot-anim`.
- Stack de desenvolvimento subida (`docker compose up --build -d`, `database-seed`, `sync_dev_ca.sh`). Bateria `integration_test` do ACS no emulador, com os `--dart-define` de `e2e.sh`: **15 testes passam** (`smoke`, `red_alert_cycle`, `map_flow`, `encrypted_storage`). Chave do Google Maps presente no `.env`.
- **Achado 1 (defeito real, RF12):** `aapt2 dump permissions` nos APKs de debug **e** de release do ACS não mostra `ACCESS_FINE_LOCATION` nem `ACCESS_COARSE_LOCATION`. O `AndroidManifest.xml` `main` não declara nenhuma `uses-permission`. Sem elas, `Geolocator.requestPermission()` não pode mostrar o diálogo e `_loadCurrentPosition` (`apps/acs/lib/app/app.dart:549`) engole o erro num `catch (_)`: `_currentPosition` fica `null` para sempre e o check-in passivo nunca chega a "Local alcançado". Os testes atuais passam porque **injetam** `currentPosition`/`initialPosition`; nenhum exercita o GPS do aparelho. O documento de decisão §4 diz que a permissão "declarada no `AndroidManifest.xml`" existe — não existe.
- **Achado 2 (hipótese minha que a medição desmentiu):** `INTERNET` **está** no APK de release (vem de uma dependência transitiva, não do manifesto do app). Não é defeito; a Task 1 a declara explicitamente só para não depender de uma dependência.
- **Achado 3 (RF13, L-07):** `EscalationScreen` (`app.dart:1915`) ainda mostra `'Discagem não está integrada neste protótipo.'` no botão do SAMU e `'Encaminhamento será integrado à UBS.'` no da UBS. `url_launcher` não está no `pubspec.yaml`.
- **Achado 4 (lacuna de teste):** todos os `integration_test/` e `tool/` do ACS usam `developmentLogin(role: 'acs')`. O paciente tem jornada completa com login real no banco de teste (`scripts/qa/patient_full_e2e.sh`); o ACS não tem equivalente — o login institucional (RF07) e o fluxo pela tela nunca rodam no emulador.
- **Achado 5 (fora do ACS, a verificar):** o manifesto `main` do paciente também não tem `uses-permission` de `INTERNET`; como o ACS, deve vir de dependência. Não mexer aqui; só registrar (Task 5).

## Fora deste plano (e por quê)

| Item | Motivo |
|---|---|
| MFA/TOTP e refresh token do ACS | Adiados de propósito (`PROGRESS.md`, `spec/security_assessment.md` F5). |
| RF08 — cache persistido da microárea (offline) | Guardar nome e condições crônicas de pacientes no aparelho exige decisão de LGPD (minimização, SQLCipher, expurgo) e é uma feature do tamanho de um plano próprio. **Recomendo um plano separado**, depois de decidido o desenho em `spec/lgpd_design.md`. |
| Botão "Encaminhar para UBS Central" | Não há fonte de contato da UBS (telefone/URL) nem no modelo de dados nem no envelope MQTT. É decisão de produto; a Task 2 deixa o botão exatamente como está e o diz na tela de documentação. |
| iOS | `apps/acs/ios/` não existe. |
| Restrição/cobrança da chave do Google Maps | Operacional, fora do código. |

## Global Constraints

- Nenhum dado real de paciente em teste, log, captura ou config; CPFs/nomes só sintéticos. `integration_test` novos usam UUIDs/fixtures sintéticos.
- Triagem determinística e alerta vermelho nunca descartado/atrasado: nenhuma tarefa toca `triage.evaluate`, `AlertQueue` ou a fila offline além de ler.
- **Sem localização em segundo plano** (decisão §4): `ACCESS_BACKGROUND_LOCATION` não pode aparecer no manifesto (teste da Task 1 garante).
- O botão do SAMU **abre o discador, nunca liga sozinho** (`ACTION_DIAL`; sem `CALL_PHONE`). Alvo de toque ≥ `64x60` dp (já é; não regredir — `spec/ux_accessibility_assessment.md`).
- Cor clínica usada como texto/ícone usa o token `*OnSurface` (`apps/CLAUDE.md`).
- Textos de UI, comentários e commits em português.
- **Commits sem qualquer atribuição de IA** (`Co-Authored-By`, "Generated with Claude Code"): regra adicionada ao `CLAUDE.md` em `ef140a5`. Isto substitui o rodapé `Co-Authored-By` dos planos anteriores. Sem push nem merge.
- `flutter analyze` em `apps/acs` sem problemas antes de cada commit; baseline `flutter test`: 198 (só pode crescer).
- O manifesto `.e2e/fixtures.json` tem a senha do ACS: gitignorado, `chmod 600`, apagado ao final.
- `adb`/`flutter`/`serverpod` não estão no `PATH` desta máquina: `export PATH="$PATH:$HOME/Android/Sdk/platform-tools:$HOME/Android/Sdk/emulator:$HOME/flutter/bin:$HOME/.pub-cache/bin"`.

## Review Focus

As entradas e condições que a spec implica, nenhuma tarefa exercitaria sozinha e mais provavelmente morderiam quem usa o app. Cada linha tem o teste que a fixa na tarefa dona:

1. **Permissão de localização negada** (ACS toca "Negar"): o check-in mostra "Localização atual indisponível…" e o registro de visita continua disponível pelo caminho manual — nunca trava o ACS. → teste na Task 3.
2. **Sem discador no aparelho** (`launchUrl` devolve `false` ou lança): o botão do SAMU mostra o número em texto ("Ligue manualmente para 192"), nunca falha em silêncio. É o botão mais crítico da UI. → teste na Task 2.
3. **Toque duplo no SAMU:** abrir o discador duas vezes não pode empilhar duas telas de discagem. → teste na Task 2.
4. **Senha errada no login institucional:** erro visível (`login_error`) e o painel **não** abre; a sessão certa logo depois funciona sem reiniciar. → teste na Task 4.
5. **Paciente de outra microárea** não aparece no seletor de visita do ACS (RBAC por território, RNF06). → teste na Task 4.

---

### Task 1: Declarar a localização no manifesto Android

**Files:**
- Create: `apps/acs/test/android_manifest_test.dart`
- Modify: `apps/acs/android/app/src/main/AndroidManifest.xml:1-2` (acrescentar `uses-permission` antes de `<application`)

**Interfaces:**
- Consumes: nada de tarefa anterior.
- Produces: `android_manifest_test.dart` com a variável `manifest` e o helper local `declares(String permission)`; a Task 2 acrescenta um teste ali (consulta `tel`).

- [ ] **Step 1: Escrever o teste que falha**

Criar `apps/acs/test/android_manifest_test.dart` (mesmo idioma de `apps/patient/test/android_push_manifest_test.dart`: lê o texto-fonte, porque o manifesto não existe no `flutter test`):

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// O check-in passivo (RF12) e o mapa dependem de `Geolocator`, que só pede
/// permissão em runtime se ela estiver DECLARADA no manifesto. Sem a
/// declaração o `requestPermission()` não mostra diálogo nenhum e
/// `_loadCurrentPosition` engole o erro: o GPS some em silêncio. Os testes de
/// widget injetam a posição e nunca viram isso — por isso este teste lê o
/// manifesto de release (`main`), o que o APK de produção realmente leva.
void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  bool declares(String permission) => RegExp(
        '<uses-permission\\s+android:name="android\\.permission\\.$permission"\\s*/>',
      ).hasMatch(manifest);

  test('declara localização precisa e aproximada (RF12)', () {
    expect(declares('ACCESS_FINE_LOCATION'), isTrue);
    expect(declares('ACCESS_COARSE_LOCATION'), isTrue);
  });

  test('declara INTERNET no manifesto de release, sem depender de plugin', () {
    expect(declares('INTERNET'), isTrue);
  });

  test('NÃO pede localização em segundo plano (decisão §4 de 2026-09-16)', () {
    expect(declares('ACCESS_BACKGROUND_LOCATION'), isFalse,
        reason: 'o geofence é só em primeiro plano; background exigiria revisão da loja e LGPD');
  });
}
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd apps/acs && flutter test test/android_manifest_test.dart`
Expected: FAIL — `declara localização precisa e aproximada` e `declara INTERNET…` com `Expected: true Actual: <false>`; o terceiro passa.

- [ ] **Step 3: Implementação mínima**

Em `apps/acs/android/app/src/main/AndroidManifest.xml`, logo depois de `<manifest …>` e antes de `<application`:

```xml
    <!-- Declaradas (e não herdadas de plugin) porque o app as usa direto:
         INTERNET para o RPC e o MQTT; localização para o mapa e o check-in
         passivo (RF12). Só primeiro plano: a decisão de 2026-09-16 (§4)
         rejeita ACCESS_BACKGROUND_LOCATION. -->
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
```

- [ ] **Step 4: Rodar e ver passar**

Run: `cd apps/acs && flutter test test/android_manifest_test.dart`
Expected: PASS (3 testes).

- [ ] **Step 5: Provar no APK real (debug e release)**

```bash
export PATH="$PATH:$HOME/Android/Sdk/platform-tools:$HOME/flutter/bin"
cd apps/acs
flutter build apk --debug
flutter build apk --release --android-project-arg=sinalacs.allowMissingMqttPassword=true
AAPT="$HOME/Android/Sdk/build-tools/36.0.0/aapt2"
for apk in debug release; do echo "== $apk"; "$AAPT" dump permissions build/app/outputs/flutter-apk/app-$apk.apk | grep -E "LOCATION|INTERNET"; done
```
Expected: nos dois, `ACCESS_COARSE_LOCATION`, `ACCESS_FINE_LOCATION` e `INTERNET`; **nenhum** `ACCESS_BACKGROUND_LOCATION`.

- [ ] **Step 6: Commit**

```bash
git add apps/acs/test/android_manifest_test.dart apps/acs/android/app/src/main/AndroidManifest.xml
git commit -m "fix(acs): declara localização e INTERNET no manifesto de release (RF12)"
```

---

### Task 2: Acionar o SAMU pelo discador (RF13 / L-07)

**Files:**
- Create: `apps/acs/lib/core/services/emergency_dialer.dart`
- Create: `apps/acs/test/escalation_dialer_test.dart`
- Modify: `apps/acs/pubspec.yaml` (dependência `url_launcher`)
- Modify: `apps/acs/lib/app/app.dart:1915-1962` (`EscalationScreen`)
- Modify: `apps/acs/android/app/src/main/AndroidManifest.xml` (`<queries>`)
- Modify: `apps/acs/test/android_manifest_test.dart` (um teste)
- Modify: `apps/acs/integration_test/map_flow_test.dart` (um teste)

**Interfaces:**
- Consumes: `declares(...)` e `manifest` da Task 1; `_message(BuildContext, String)` de `app.dart:2224`; `testAlert(...)` e `seedMicroAreaId` de `test/support/fakes.dart`.
- Produces: `const samuNumber = '192'`; `abstract interface class EmergencyDialer { Future<bool> dial(String number); }`; `class UrlLauncherEmergencyDialer implements EmergencyDialer` (const); `EscalationScreen({alert, onVisit, EmergencyDialer dialer = const UrlLauncherEmergencyDialer()})`.

- [ ] **Step 1: Escrever os testes que falham**

Criar `apps/acs/test/escalation_dialer_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/app/app.dart';
import 'package:sinalacs_acs/core/services/emergency_dialer.dart';

import 'support/fakes.dart';

class _FakeDialer implements EmergencyDialer {
  _FakeDialer({this.opens = true, this.throws = false});

  final bool opens;
  final bool throws;
  final dialed = <String>[];

  @override
  Future<bool> dial(String number) async {
    dialed.add(number);
    if (throws) throw StateError('sem discador');
    return opens;
  }
}

Future<void> _pump(WidgetTester tester, _FakeDialer dialer) => tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EscalationScreen(alert: testAlert(alertId: 'a1'), dialer: dialer),
      ),
    ));

void main() {
  testWidgets('o botão do SAMU abre o discador com 192', (tester) async {
    final dialer = _FakeDialer();
    await _pump(tester, dialer);

    await tester.tap(find.text('Ligar para o SAMU (192)'));
    await tester.pump();

    expect(dialer.dialed, ['192']);
    expect(find.text('Discagem não está integrada neste protótipo.'), findsNothing);
  });

  testWidgets('sem discador, mostra o número em texto em vez de falhar em silêncio', (tester) async {
    final dialer = _FakeDialer(opens: false);
    await _pump(tester, dialer);

    await tester.tap(find.text('Ligar para o SAMU (192)'));
    await tester.pump();

    expect(find.textContaining('Ligue manualmente para 192'), findsOneWidget);
  });

  testWidgets('um erro do discador cai no mesmo aviso, sem derrubar a tela', (tester) async {
    final dialer = _FakeDialer(throws: true);
    await _pump(tester, dialer);

    await tester.tap(find.text('Ligar para o SAMU (192)'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Ligue manualmente para 192'), findsOneWidget);
  });

  testWidgets('toque duplo não abre dois discadores', (tester) async {
    final dialer = _FakeDialer();
    await _pump(tester, dialer);

    await tester.tap(find.text('Ligar para o SAMU (192)'));
    await tester.tap(find.text('Ligar para o SAMU (192)'));
    await tester.pump();

    expect(dialer.dialed, ['192']);
  });

  testWidgets('o botão da UBS continua sendo o aviso honesto (sem contato cadastrado)', (tester) async {
    await _pump(tester, _FakeDialer());

    await tester.tap(find.text('Encaminhar para UBS Central'));
    await tester.pump();

    expect(find.text('Encaminhamento será integrado à UBS.'), findsOneWidget);
  });
}
```

Acrescentar a `apps/acs/test/android_manifest_test.dart`, dentro de `main()`:

```dart
  test('declara a consulta ao discador (tel:) para o botão do SAMU (RF13)', () {
    // Android 11+: sem <queries>, `canLaunchUrl(tel:)` devolve false mesmo com discador.
    expect(
      RegExp(r'<action\s+android:name="android\.intent\.action\.DIAL"\s*/>\s*<data\s+android:scheme="tel"\s*/>')
          .hasMatch(manifest),
      isTrue,
    );
  });
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd apps/acs && flutter test test/escalation_dialer_test.dart test/android_manifest_test.dart`
Expected: FAIL — `escalation_dialer_test.dart` não compila (`emergency_dialer.dart` não existe) e o teste de `tel:` falha.

- [ ] **Step 3: Dependência e interface**

Em `apps/acs/pubspec.yaml`, em `dependencies:` (junto de `qr_flutter`):

```yaml
  # RF13: abre o discador do aparelho (tel:192). O PRD já a nomeia na matriz
  # de capacidades; é invólucro de intent do sistema, não framework novo.
  url_launcher: ^6.3.0
```

Run: `cd apps/acs && flutter pub get`

Criar `apps/acs/lib/core/services/emergency_dialer.dart`:

```dart
import 'package:url_launcher/url_launcher.dart';

/// Número do SAMU. Constante de domínio (PRD, RF13), não configuração.
const samuNumber = '192';

/// Abre o discador do aparelho com o número já digitado.
///
/// **Nunca liga sozinho:** `tel:` abre o discador e a pessoa confirma a
/// chamada. É o que dispensa `CALL_PHONE` no manifesto (permissão sensível,
/// revisada pela loja) e evita uma ligação por toque acidental.
abstract interface class EmergencyDialer {
  /// `true` se o discador foi aberto; `false` se o aparelho não tem como.
  Future<bool> dial(String number);
}

class UrlLauncherEmergencyDialer implements EmergencyDialer {
  const UrlLauncherEmergencyDialer();

  @override
  Future<bool> dial(String number) async {
    try {
      return await launchUrl(Uri(scheme: 'tel', path: number));
    } catch (_) {
      // Qualquer falha vira "não abriu": quem chama mostra o número em texto.
      return false;
    }
  }
}
```

- [ ] **Step 4: Ligar na tela**

Em `apps/acs/lib/app/app.dart`, `import 'package:sinalacs_acs/core/services/emergency_dialer.dart';` junto dos outros imports de `core/services`. Trocar a classe `EscalationScreen` (`StatelessWidget` → `StatefulWidget`, para guardar o "já abri"):

```dart
class EscalationScreen extends StatefulWidget {
  const EscalationScreen({
    super.key,
    this.alert,
    this.onVisit,
    this.dialer = const UrlLauncherEmergencyDialer(),
  });

  final PrioritizedAlert? alert;
  final void Function(PrioritizedAlert alert)? onVisit;
  final EmergencyDialer dialer;

  @override
  State<EscalationScreen> createState() => _EscalationScreenState();
}

class _EscalationScreenState extends State<EscalationScreen> {
  /// Trava o toque duplo: dois `launchUrl` seguidos empilham dois discadores.
  bool _dialing = false;

  Future<void> _callSamu() async {
    if (_dialing) return;
    setState(() => _dialing = true);
    var opened = false;
    try {
      opened = await widget.dialer.dial(samuNumber);
    } catch (_) {
      opened = false;
    }
    if (!mounted) return;
    setState(() => _dialing = false);
    if (!opened) {
      _message(context, 'Não foi possível abrir o discador. Ligue manualmente para $samuNumber.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.alert;
    final onVisit = widget.onVisit;
    // ... corpo atual de build(), com duas trocas:
    //   1. `onPressed: () => _message(context, 'Discagem não está integrada neste protótipo.')`
    //      vira `onPressed: _dialing ? null : _callSamu`
    //   2. `onPressed: onVisit == null ? null : () => onVisit!(current)` vira
    //      `onPressed: onVisit == null ? null : () => onVisit(current)`
  }
}
```

(O resto do `build` — `_InfoRow`, botão da UBS com `'Encaminhamento será integrado à UBS.'`, `escalation_visit`, o texto "A visita é acompanhamento do caso…" — fica **igual**, só trocando `alert`/`onVisit` por `current`/`onVisit` locais como acima. `minimumSize: const Size(64, 60)` do SAMU não muda.)

Em `AndroidManifest.xml`, dentro de `<queries>`:

```xml
        <intent>
            <action android:name="android.intent.action.DIAL"/>
            <data android:scheme="tel"/>
        </intent>
```

- [ ] **Step 5: Rodar e ver passar**

Run: `cd apps/acs && flutter test test/escalation_dialer_test.dart test/android_manifest_test.dart test/login_flow_test.dart && flutter analyze`
Expected: PASS (os testes existentes de `EscalationScreen` em `login_flow_test.dart:775` continuam verdes) e `No issues found`.

- [ ] **Step 6: Provar no emulador que o discador resolve**

Acrescentar a `apps/acs/integration_test/map_flow_test.dart`, dentro de `main()`:

```dart
  testWidgets('o discador do aparelho resolve tel:192 (RF13)', (tester) async {
    // Prova o que o widget test não alcança: <queries> declarada e um
    // handler de `tel:` presente no aparelho. Não abre a chamada.
    final available = await canLaunchUrl(Uri(scheme: 'tel', path: '192'));
    expect(available, isTrue,
        reason: 'sem <queries> para tel: (Android 11+) ou sem discador no emulador');
  });
```
(import `package:url_launcher/url_launcher.dart`.)

Run (stack de dev de pé, emulador no ar — ver Task 6 para o preparo):
`cd apps/acs && flutter test integration_test/map_flow_test.dart -d emulator-5554 --dart-define=SINALACS_HOST=https://localhost:8443/ --dart-define=SINALACS_MQTT_HOST=localhost --dart-define=SINALACS_MQTT_PASSWORD="$MQTT_ACS_PASSWORD"`
Expected: PASS. **Se `false`:** `adb -s emulator-5554 shell pm resolve-activity -a android.intent.action.DIAL -d tel:192` — vazio quer dizer imagem de emulador sem discador (registrar, não é defeito do app).

- [ ] **Step 7: Commit**

```bash
git add apps/acs/pubspec.yaml apps/acs/pubspec.lock apps/acs/lib/core/services/emergency_dialer.dart apps/acs/lib/app/app.dart apps/acs/android/app/src/main/AndroidManifest.xml apps/acs/test/escalation_dialer_test.dart apps/acs/test/android_manifest_test.dart apps/acs/integration_test/map_flow_test.dart
git commit -m "feat(acs): botão do SAMU abre o discador com 192 (RF13, L-07)"
```

---

### Task 3: Provar o GPS real do check-in no emulador (RF12)

**Files:**
- Create: `apps/acs/integration_test/geofence_gps_e2e.dart`
- Create: `scripts/qa/acs_gps_e2e.sh`

**Interfaces:**
- Consumes: manifesto da Task 1; `SinalAcsApp`, `FakeAcsBackend`, `FakeAlertFeed`, `testAlert`, `seedMicroAreaId`, `testLocationCell` (`test/support/fakes.dart`); chaves `matricula_field`, `senha_field`, `login_button`, `geofence_status`.
- Produces: `scripts/qa/acs_gps_e2e.sh [--sem-permissao]` (exit 0 = passou).

O diálogo de permissão é do sistema: o `integration_test` não o toca. Então o script instala o APK **já com a permissão concedida** (`adb install -g`) e posiciona o GPS do emulador (`adb emu geo fix <lon> <lat>`). A célula `-1580:-4783` tem centro em lat `-15.795`, lon `-47.825` e o raio de chegada é 150 m (`RouteService.arrivalThresholdKm = 0.15`).

- [ ] **Step 1: Descobrir se `flutter test` aceita APK pronto (decide o mecanismo)**

Run: `cd apps/acs && flutter test --help | grep -i "use-application-binary"`
Expected: uma linha com `--use-application-binary`. Se **não** houver, usar o caminho B do Step 4.

- [ ] **Step 2: Escrever o teste que falha**

Criar `apps/acs/integration_test/geofence_gps_e2e.dart`:

```dart
/// RF12 com o GPS do aparelho, não com posição injetada. Pré-requisitos e
/// cenário em `scripts/qa/acs_gps_e2e.sh` (concede/nega a permissão e fixa a
/// posição do emulador antes de rodar). `--dart-define=EXPECT_PERMISSION=granted|denied`.
@Timeout(Duration(minutes: 2))
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sinalacs_acs/app/app.dart';

import '../test/support/fakes.dart';

const _expect = String.fromEnvironment('EXPECT_PERMISSION', defaultValue: 'granted');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('o GPS do aparelho decide o check-in passivo ($_expect)', (tester) async {
    final alert = testAlert(alertId: 'gps-1', locationCell: testLocationCell);
    final backend = FakeAcsBackend();

    await tester.pumpWidget(SinalAcsApp(
      backend: backend,
      feedBuilder: (queue) => FakeAlertFeed(queue),
      initialAlert: alert,
      // `currentPosition` AUSENTE de propósito: a posição tem de vir do Geolocator.
    ));
    await tester.enterText(find.byKey(const Key('matricula_field')), '123456');
    await tester.enterText(find.byKey(const Key('senha_field')), 'qualquer');
    await tester.tap(find.byKey(const Key('login_button')));
    await _pumpFor(tester, const Duration(seconds: 3));

    await tester.tap(find.text('Mais'));
    await _pumpFor(tester, const Duration(milliseconds: 500));
    await tester.tap(find.text('Geofencing'));
    // O GPS leva alguns segundos para o primeiro fix no emulador.
    await _pumpUntil(
      tester,
      () => _expect == 'granted'
          ? find.text('Local alcançado. O registro da visita está liberado.').evaluate().isNotEmpty
          : find.textContaining('Localização atual indisponível').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 30),
    );

    if (_expect == 'granted') {
      expect(find.text('Local alcançado. O registro da visita está liberado.'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('geofence_visit'))).onPressed, isNotNull);
    } else {
      // Review Focus 1: permissão negada nunca trava o ACS.
      expect(find.textContaining('Localização atual indisponível'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}

Future<void> _pumpFor(WidgetTester tester, Duration d) async {
  final fim = DateTime.now().add(d);
  while (DateTime.now().isBefore(fim)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() done, {required Duration timeout}) async {
  final fim = DateTime.now().add(timeout);
  while (!done() && DateTime.now().isBefore(fim)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}
```

Run (sem o script, permissão ainda não concedida, deve falhar):
`cd apps/acs && flutter test integration_test/geofence_gps_e2e.dart -d emulator-5554`
Expected: FAIL por timeout — a posição nunca chega (sem permissão concedida, e o diálogo do sistema fica sem ninguém para tocar).

- [ ] **Step 3: Criar o script**

Criar `scripts/qa/acs_gps_e2e.sh` (`chmod +x`):

```bash
#!/usr/bin/env bash
#
# GPS real do check-in do ACS (RF12) no emulador-5554.
#
#   ./scripts/qa/acs_gps_e2e.sh                  # permissão concedida: "Local alcançado"
#   ./scripts/qa/acs_gps_e2e.sh --sem-permissao  # permissão negada: "indisponível", sem travar
#
# O diálogo de permissão é do sistema e o integration_test não o toca: o APK é
# instalado já com a permissão concedida (ou negada) por `pm`, e a posição do
# emulador é fixada por `adb emu geo fix` no centro da célula `-1580:-4783`
# (lat -15.795, lon -47.825), a 0 m do destino (raio de chegada: 150 m).
# Não precisa da stack: o teste usa FakeAcsBackend.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root/apps/acs"
export PATH="$PATH:$HOME/Android/Sdk/platform-tools:$HOME/flutter/bin"

dev=emulator-5554
pkg=br.com.prismrr.sinalacs.acs
expect=granted
[[ "${1:-}" == --sem-permissao ]] && expect=denied
adb -s "$dev" get-state >/dev/null 2>&1 || { echo "emulador $dev não encontrado (adb devices)"; exit 4; }

flutter build apk --debug >/dev/null
adb -s "$dev" uninstall "$pkg" >/dev/null 2>&1 || true
adb -s "$dev" install -r build/app/outputs/flutter-apk/app-debug.apk >/dev/null
for p in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION; do
  if [[ "$expect" == granted ]]; then
    adb -s "$dev" shell pm grant "$pkg" "android.permission.$p"
  else
    adb -s "$dev" shell pm revoke "$pkg" "android.permission.$p" || true
  fi
done
adb -s "$dev" emu geo fix -47.825 -15.795 >/dev/null

# --use-application-binary: reaproveita o APK que recebeu a permissão (um
# `flutter test` normal reinstalaria e perderia a concessão).
flutter test integration_test/geofence_gps_e2e.dart -d "$dev" \
  --use-application-binary=build/app/outputs/flutter-apk/app-debug.apk \
  --dart-define=EXPECT_PERMISSION="$expect"
echo "OK — check-in por GPS real ($expect)"
```

- [ ] **Step 4: Rodar e ver passar**

Run: `./scripts/qa/acs_gps_e2e.sh && ./scripts/qa/acs_gps_e2e.sh --sem-permissao`
Expected: os dois imprimem `OK — check-in por GPS real (granted)` e `(denied)`.

**Caminho B** (se o Step 1 não achou `--use-application-binary`, ou se `flutter test` reinstalar e perder a concessão — sintoma: o `granted` expira por timeout): trocar o `flutter test` final por `flutter drive --driver=test_driver/integration_test.dart --target=integration_test/geofence_gps_e2e.dart -d "$dev" --use-application-binary=…` e criar `apps/acs/test_driver/integration_test.dart` com `import 'package:integration_test/integration_test_driver.dart'; Future<void> main() => integrationDriver();`. Registrar no commit qual caminho foi preciso.

- [ ] **Step 5: Commit**

```bash
git add apps/acs/integration_test/geofence_gps_e2e.dart scripts/qa/acs_gps_e2e.sh
git commit -m "test(acs): GPS real do check-in no emulador, com e sem permissão (RF12)"
```

---

### Task 4: Jornada completa do ACS no banco de teste (login institucional real)

**Files:**
- Modify: `scripts/qa/otp_relay.py` (endpoint opt-in `GET /acs`)
- Modify: `scripts/qa/otp_relay_test.py`
- Create: `apps/acs/integration_test/support/e2e_acs.dart`
- Create: `apps/acs/integration_test/full_journey_e2e.dart`
- Create: `scripts/qa/acs_full_e2e.sh`

**Interfaces:**
- Consumes: `e2e_stack.sh up|seed|down` e `.e2e/fixtures.json` (`E2eFixtures`: `acs{matricula,password}`, `patients[]{role,name,cpf,birthDate,microAreaId,id}`, `microAreaId`, `otherMicroAreaId`); `otp_relay.py` (`/now`, `/code?since=`); chaves `matricula_field`, `senha_field`, `login_button`, `login_error`, `patient_picker`, `patient_<id>`, `patient_search`, `save_visit`, `sync_visits`, `pending_visits_count`, `ack_<alertId>`; `api.Client` de `sinalacs_client`.
- Produces: `E2eAcsConfig` e `acsCredentialFromRelay()` em `support/e2e_acs.dart`; `acs_full_e2e.sh [--sem-gps]`.

**Decisão a registrar (e que o usuário pode reverter):** a senha do ACS é aleatória e descartável, mas o `patient_full_e2e.sh` a tira de propósito do `--dart-define` (revisão I1: argv visível em `ps` e embutida no APK). Para o teste de tela ela precisa chegar ao aparelho. Escolha: **servi-la pelo relé de OTP, opt-in** (`E2E_FIXTURES_FILE` definido). Fica fora do APK; **continua legível por qualquer processo local em `127.0.0.1`** — mesma exposição do argv, só que sem ir para o APK e sem aparecer em `ps`. Aceitável para credencial sintética destruída ao final; se não for, a alternativa é só rodar o login institucional no host (como `tool/territory_check.dart`) e testar a tela com `FakeAcsBackend`.

- [ ] **Step 1: Teste Python do endpoint `/acs` (falha primeiro)**

Acrescentar a `scripts/qa/otp_relay_test.py`, antes do `if __name__`:

```python
class AcsTest(unittest.TestCase):
    def test_le_matricula_e_senha_do_manifesto(self):
        import json, tempfile
        from otp_relay import acs_do_manifesto
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump({"acs": {"matricula": "E2E-1234", "password": "s3nha"}}, f)
        self.assertEqual(acs_do_manifesto(f.name), {"matricula": "E2E-1234", "senha": "s3nha"})

    def test_sem_arquivo_nao_serve_nada(self):
        from otp_relay import acs_do_manifesto
        self.assertIsNone(acs_do_manifesto(None))
        self.assertIsNone(acs_do_manifesto("/nao/existe.json"))
```

Run: `cd scripts/qa && python3 otp_relay_test.py`
Expected: FAIL — `ImportError: cannot import name 'acs_do_manifesto'`.

- [ ] **Step 2: Implementar `/acs` (opt-in)**

Em `scripts/qa/otp_relay.py`: `import json, os` ao lado dos imports; antes de `class Handler`:

```python
def acs_do_manifesto(caminho):
    """Matrícula e senha sintéticas do ACS do manifesto de e2e, ou None.

    Só existe para o e2e de TELA do ACS. Opt-in: sem E2E_FIXTURES_FILE o relé
    não serve credencial nenhuma, e o e2e do paciente segue exatamente como era."""
    if not caminho:
        return None
    try:
        with open(caminho) as f:
            acs = json.load(f)["acs"]
        return {"matricula": acs["matricula"], "senha": acs["password"]}
    except (OSError, KeyError, ValueError):
        return None
```

Em `Handler.do_GET`, logo depois do bloco do `/now`:

```python
        if url.path == "/acs":
            credencial = acs_do_manifesto(os.environ.get("E2E_FIXTURES_FILE"))
            if credencial is None:
                self.send_error(404); return
            self.send_response(200); self.send_header("Content-Type", "application/json"); self.end_headers()
            self.wfile.write(json.dumps(credencial).encode())
            return
```

Run: `cd scripts/qa && python3 otp_relay_test.py`
Expected: PASS (todos os testes, os antigos inclusive).

- [ ] **Step 3: Suporte Dart do ACS**

Criar `apps/acs/integration_test/support/e2e_acs.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:sinalacs_client/sinalacs_client.dart' as api;

/// Manifesto de fixtures SEM o bloco `acs` (a senha vem do relé, nunca do
/// `--dart-define`): `--dart-define=E2E_FIXTURES='{"patients":[…]}'`.
const _fixtures = String.fromEnvironment('E2E_FIXTURES');
const relayBase = String.fromEnvironment('OTP_RELAY_BASE', defaultValue: 'http://localhost:8765');

class E2ePatient {
  const E2ePatient({required this.id, required this.role, required this.name, required this.cpf, required this.birthDate, required this.microAreaId});
  final String id;
  final String role;
  final String name;
  final String cpf; // nunca em log
  final String birthDate; // AAAA-MM-DD
  final String microAreaId;
  @override
  String toString() => 'E2ePatient($role)';
}

List<E2ePatient> e2ePatients() {
  if (_fixtures.isEmpty) throw StateError('sem --dart-define=E2E_FIXTURES (use scripts/qa/acs_full_e2e.sh)');
  final map = (jsonDecode(_fixtures) as Map).cast<String, Object?>();
  return [
    for (final raw in (map['patients']! as List).cast<Map>())
      E2ePatient(
        id: raw['id'] as String,
        role: raw['role'] as String,
        name: raw['name'] as String,
        cpf: raw['cpf'] as String,
        birthDate: raw['birthDate'] as String,
        microAreaId: raw['microAreaId'] as String,
      ),
  ];
}

E2ePatient e2ePatient(String role) => e2ePatients().firstWhere((p) => p.role == role);

Future<String> _get(String path, {String query = ''}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(relayBase).replace(path: path, query: query));
    final response = await request.close();
    final body = await utf8.decodeStream(response);
    if (response.statusCode != 200) throw StateError('o relé respondeu ${response.statusCode} a $path');
    return body.trim();
  } on SocketException {
    throw StateError('o relé não está no ar (scripts/qa/otp_relay.py + adb reverse tcp:8765 tcp:8765)');
  } finally {
    client.close(force: true);
  }
}

/// Matrícula e senha do ACS da fixture, servidas pelo relé (opt-in).
Future<({String matricula, String senha})> acsCredentialFromRelay() async {
  final json = jsonDecode(await _get('/acs')) as Map;
  return (matricula: json['matricula'] as String, senha: json['senha'] as String);
}

/// Entra como o paciente [role] pelo OTP real e devolve o token.
Future<String> loginPatientOtp(api.Client client, String role) async {
  final p = e2ePatient(role);
  final pedidoEm = int.parse(await _get('/now'));
  await client.auth.requestOtp(cpf: p.cpf, birthDate: DateTime.parse(p.birthDate));
  for (var i = 0; i < 20; i++) {
    try {
      final code = await _get('/code', query: 'since=$pedidoEm');
      final session = await client.auth.verifyOtp(cpf: p.cpf, code: code);
      return session.accessToken;
    } on StateError {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }
  throw StateError('o relé não devolveu o código do OTP');
}
```

- [ ] **Step 4: Escrever a jornada (falha primeiro)**

Criar `apps/acs/integration_test/full_journey_e2e.dart`:

```dart
/// Jornada completa do ACS contra o BANCO DE TESTE, pela tela, com login
/// institucional real (RF07) e MQTT real. Rodada por `scripts/qa/acs_full_e2e.sh`.
///
/// PRIVACIDADE: só fixtures sintéticas geradas na execução; nada de CPF em log.
@Timeout(Duration(minutes: 4))
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sinalacs_acs/app/app.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/network/backend_config.dart';
import 'package:sinalacs_client/sinalacs_client.dart' as api;

import 'support/e2e_acs.dart';

Future<void> _pumpUntil(WidgetTester tester, bool Function() done, {Duration timeout = const Duration(seconds: 30)}) async {
  final fim = DateTime.now().add(timeout);
  while (!done() && DateTime.now().isBefore(fim)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(done(), isTrue, reason: 'condição não atingida em ${timeout.inSeconds}s');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('login real, alerta pelo MQTT, visita pelo seletor e sincronização', (tester) async {
    final ca = (await rootBundle.load(BackendConfig.rpcCaAsset)).buffer.asUint8List();
    final backend = BackendClient(trustedCaBytes: ca);
    addTearDown(backend.close);
    final host = const String.fromEnvironment('SINALACS_HOST', defaultValue: 'https://10.0.2.2/');
    final patientClient = api.Client(host, securityContext: SecurityContext()..setTrustedCertificatesBytes(ca))
      ..connectivityMonitor = null;
    addTearDown(patientClient.close);

    final cred = await acsCredentialFromRelay();
    final main = e2ePatient('main');
    final outsider = e2ePatient('outsider');

    await tester.pumpWidget(SinalAcsApp(backend: backend));

    // Review Focus 4 — senha errada: erro visível, painel fechado.
    await tester.enterText(find.byKey(const Key('matricula_field')), cred.matricula);
    await tester.enterText(find.byKey(const Key('senha_field')), '${cred.senha}-errada');
    await tester.tap(find.byKey(const Key('login_button')));
    await _pumpUntil(tester, () => find.byKey(const Key('login_error')).evaluate().isNotEmpty);
    expect(find.byKey(const Key('login_button')), findsOneWidget, reason: 'o painel não pode abrir');

    // A sessão certa logo depois funciona, sem reiniciar.
    await tester.enterText(find.byKey(const Key('senha_field')), cred.senha);
    await tester.tap(find.byKey(const Key('login_button')));
    await _pumpUntil(tester, () => find.byKey(const Key('login_button')).evaluate().isEmpty);

    // Alerta vermelho do paciente (OTP real) chega ao painel pelo broker.
    final token = await loginPatientOtp(patientClient, 'api');
    final created = await patientClient.alerts.createRedAlert(
      accessToken: token,
      idempotencyKey: 'e2e-acs-${DateTime.now().microsecondsSinceEpoch}',
      locationHash: 'sem-local-00',
    );
    await _pumpUntil(tester, () => find.byKey(Key('alert_${created.alertId}')).evaluate().isNotEmpty);
    await tester.tap(find.byKey(Key('ack_${created.alertId}')));
    await _pumpUntil(tester, () => find.byKey(Key('ack_${created.alertId}')).evaluate().isEmpty);

    // Visita de rotina pelo seletor: o paciente da microárea aparece; o de fora, não (RNF06).
    await tester.tap(find.text('Visita'));
    await _pumpUntil(tester, () => find.byKey(const Key('patient_picker')).evaluate().isNotEmpty);
    expect(find.byKey(Key('patient_${main.id}')), findsOneWidget);
    expect(find.byKey(Key('patient_${outsider.id}')), findsNothing, reason: 'outra microárea');

    await tester.tap(find.byKey(Key('patient_${main.id}')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('save_visit')));
    await _pumpUntil(tester, () => find.byKey(const Key('pending_visits_count')).evaluate().isNotEmpty);
    await tester.tap(find.byKey(const Key('sync_visits')));
    await _pumpUntil(tester, () => find.byKey(const Key('pending_visits_count')).evaluate().isEmpty);

    // A visita está NO SERVIDOR (e só o ACS da microárea a enxerga).
    final acsClient = api.Client(host, securityContext: SecurityContext()..setTrustedCertificatesBytes(ca))
      ..connectivityMonitor = null;
    addTearDown(acsClient.close);
    final acs = await acsClient.auth.loginInstitutional(matricula: cred.matricula, password: cred.senha);
    final remotas = await acsClient.visits.pull(accessToken: acs.accessToken, since: DateTime.fromMillisecondsSinceEpoch(0));
    expect(remotas.any((v) => v.patientId == main.id), isTrue);
  });
}
```

**Nome de arquivo (`_e2e.dart`, não `_test.dart`) é de propósito:** `flutter test integration_test` descobre `*_test.dart` recursivamente, e `e2e.sh --emulator --full` rodaria este teste contra a stack de desenvolvimento, onde não há fixtures nem relé. Com `_e2e.dart` só o script o roda, por caminho explícito.

**Já conferido contra o código** (2026-10-01): `auth.loginInstitutional` recebe `password:` (`client.dart:138`); as abas são `Área`, `Fila`, `Mapa`, `Visita`, `Mais`; `ack_<id>` só existe enquanto `!alert.acknowledged` (`app.dart:1123`). **Ainda a conferir ao rodar:** que a fila marca o alerta como confirmado depois do `acknowledge` (o `ack_<id>` precisa sumir); se não sumir, ler como `app.dart:714` atualiza o alerta e trocar a espera por um texto de "confirmado" — não afrouxar a asserção.

- [ ] **Step 5: Criar o orquestrador**

Criar `scripts/qa/acs_full_e2e.sh` (`chmod +x`), espelhando `patient_full_e2e.sh`:

```bash
#!/usr/bin/env bash
#
# Jornada completa do ACS no emulador-5554, contra o BANCO DE TESTE.
#
#   ./scripts/qa/acs_full_e2e.sh
#
# Sobe a stack de e2e (e2e_stack.sh: banco sinalacs_e2e, sem login de
# desenvolvimento), semeia fixtures sintéticas (UUIDs, CPFs e a senha do ACS
# novos a cada execução), sobe o relé (OTP + credencial do ACS, opt-in) e roda
# integration_test/full_journey_e2e.dart no emulador. Nada é escrito no banco
# de desenvolvimento; o banco e o manifesto são apagados ao final.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
export PATH="$PATH:$HOME/Android/Sdk/platform-tools:$HOME/flutter/bin:$HOME/.pub-cache/bin"

dev=emulator-5554
adb -s "$dev" get-state >/dev/null 2>&1 || { echo "emulador $dev não encontrado (adb devices)"; exit 4; }

relay_pid=""
cleanup() {
  [[ -n "$relay_pid" ]] && kill "$relay_pid" 2>/dev/null || true
  rm -f .e2e/fixtures.json   # primeiro: tem a senha do ACS, mesmo se o down falhar
  ./scripts/qa/e2e_stack.sh down >/dev/null 2>&1 \
    || echo 'aviso: e2e_stack.sh down falhou; o banco sinalacs_e2e pode ter sobrado' >&2
  echo 'A stack de desenvolvimento foi substituída pela de e2e: rode `docker compose up -d` para voltá-la.'
}
trap cleanup EXIT

if ss -ltn 2>/dev/null | grep -q '127.0.0.1:8765 '; then
  echo 'erro: a porta 8765 já está ocupada (relé antigo?). Encerre-o: pkill -f scripts/qa/otp_relay.py' >&2
  exit 1
fi

echo "== stack de e2e (banco de teste)"
./scripts/qa/e2e_stack.sh up
./scripts/qa/e2e_stack.sh seed
./scripts/dev/sync_dev_ca.sh >/dev/null 2>&1 || true
set -a; source .env; set +a
adb -s "$dev" reverse tcp:8443 tcp:443 >/dev/null
adb -s "$dev" reverse tcp:8883 tcp:8883 >/dev/null
adb -s "$dev" reverse tcp:8765 tcp:8765 >/dev/null

E2E_FIXTURES_FILE="$repo_root/.e2e/fixtures.json" python3 scripts/qa/otp_relay.py >/dev/null 2>&1 &
relay_pid=$!
for _ in $(seq 1 20); do
  curl -fs http://127.0.0.1:8765/now >/dev/null 2>&1 && break
  sleep 0.25
done
kill -0 "$relay_pid" 2>/dev/null || { echo 'erro: o relé não subiu' >&2; exit 1; }

# Sem o bloco `acs`: a senha chega pelo relé, nunca pelo argv do flutter test nem no APK.
fixtures="$(python3 -c "import json;d=json.load(open('.e2e/fixtures.json'));d.pop('acs',None);print(json.dumps(d))")"

echo "== jornada do ACS no emulador"
( cd apps/acs && flutter pub get >/dev/null && flutter test integration_test/full_journey_e2e.dart -d "$dev" \
    --dart-define=SINALACS_HOST=https://localhost:8443/ \
    --dart-define=SINALACS_MQTT_HOST=localhost \
    --dart-define=SINALACS_MQTT_PASSWORD="$MQTT_ACS_PASSWORD" \
    --dart-define=E2E_FIXTURES="$fixtures" )
echo 'OK — jornada completa do ACS contra o banco de teste'
```

- [ ] **Step 6: Rodar e ver passar**

Run: `./scripts/qa/acs_full_e2e.sh`
Expected: `OK — jornada completa do ACS contra o banco de teste`, e depois `ls .e2e/fixtures.json` → `No such file`.
Se o teste falhar por um dos três nomes do Step 4, corrigi-lo e rodar de novo; **não** afrouxar uma asserção para passar.

- [ ] **Step 7: Voltar a stack de desenvolvimento**

Run: `docker compose up -d && docker compose ps --format '{{.Name}} {{.Status}}'`
Expected: `sinalacs-serverpod … (healthy)`.

- [ ] **Step 8: Commit**

```bash
git add scripts/qa/otp_relay.py scripts/qa/otp_relay_test.py scripts/qa/acs_full_e2e.sh apps/acs/integration_test/support/e2e_acs.dart apps/acs/integration_test/full_journey_e2e.dart
git commit -m "test(acs): jornada completa com login institucional real no banco de teste"
```

---

### Task 5: Documentação

**Files:**
- Modify: `PROGRESS.md` (seção nova "Finalização do app ACS (2026-10-01)")
- Modify: `apps/CLAUDE.md` (ACS: permissões, discador, `acs_gps_e2e.sh`, `acs_full_e2e.sh`)
- Modify: `spec/validation_report.md` (linha RF13 e L-07; **só** isso, ele é velho nos dois sentidos)
- Modify: `docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md` (§4: a permissão passou a existir de fato)
- Modify: `docs/roteiro-video-sponsor.md:153` (a mensagem do SAMU mudou)

**Interfaces:** consome tudo das Tasks 1–4.

- [ ] **Step 1: Atualizar os textos**

- `PROGRESS.md`: registrar os 5 achados do topo deste plano, o que mudou e o que ficou de fora (RF08 cache, UBS, MFA/refresh token), com a data.
- `apps/CLAUDE.md`: onde descreve o ACS, acrescentar uma frase por item — manifesto declara localização (guardado por `test/android_manifest_test.dart`); `EmergencyDialer` (`core/services/emergency_dialer.dart`) abre o discador, nunca liga; `scripts/qa/acs_gps_e2e.sh` e `scripts/qa/acs_full_e2e.sh` e o que cada um prova.
- `spec/validation_report.md`: linha RF13 de `ausente` para `parcial` ("SAMU abre o discador; UBS segue sem fonte de contato") e riscar L-07 (`~~…~~`) com a nota de que a UBS permanece.
- Decisão §4: nota curta "a permissão de localização em primeiro plano só passou a estar no manifesto em 2026-10-01".
- `docs/roteiro-video-sponsor.md:153`: a linha do SAMU deixa de citar a mensagem de protótipo; a da UBS fica.

- [ ] **Step 2: Registrar o achado do paciente, sem mexer nele**

Em `PROGRESS.md`, uma linha em "O que continua em aberto": "`apps/patient` — manifesto `main` sem `INTERNET` explícito (hoje herdado de dependência); verificar com `aapt2 dump permissions` no APK de release antes de qualquer mudança."

- [ ] **Step 3: Conferir links**

Run: `./scripts/dev/check_documentation_links.sh`
Expected: sem links quebrados.

- [ ] **Step 4: Commit**

```bash
git add PROGRESS.md apps/CLAUDE.md spec/validation_report.md docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md docs/roteiro-video-sponsor.md
git commit -m "docs: registra a finalização do app ACS (localização, SAMU, e2e)"
```

---

### Task 6: Barra final no emulador

**Files:** nenhum (só verificação; qualquer correção volta à tarefa dona).

**Interfaces:** consome Tasks 1–5.

- [ ] **Step 1: Suítes herméticas**

Run: `cd apps/acs && flutter analyze && flutter test`
Expected: `No issues found!` e **mais** de 198 testes (198 + 3 manifesto + 1 manifesto `tel` + 5 do discador = **207**), `All tests passed!`.

- [ ] **Step 2: Emulador e stack no ar**

```bash
export PATH="$PATH:$HOME/Android/Sdk/platform-tools:$HOME/Android/Sdk/emulator:$HOME/flutter/bin"
adb devices | grep -q "emulator-5554.*device" || { (cd /tmp && nohup emulator -avd Medium_Phone -port 5554 -no-snapshot-save -no-boot-anim >/tmp/emu.log 2>&1 &); adb wait-for-device; until [ "$(adb -s emulator-5554 shell getprop sys.boot_completed | tr -d '\r')" = 1 ]; do sleep 2; done; }
docker compose ps --format '{{.Name}} {{.Status}}' | grep -q 'sinalacs-serverpod.*healthy' || docker compose up --build -d
docker compose up database-seed
./scripts/dev/sync_dev_ca.sh
```
Expected: `adb devices` lista `emulator-5554 device`; `sinalacs-serverpod … (healthy)`.

- [ ] **Step 3: Bateria `integration_test` do ACS (stack de desenvolvimento)**

```bash
set -a; source .env; set +a
adb -s emulator-5554 reverse tcp:8443 tcp:443; adb -s emulator-5554 reverse tcp:8883 tcp:8883
( cd apps/acs && flutter test integration_test -d emulator-5554 \
    --dart-define=SINALACS_HOST=https://localhost:8443/ \
    --dart-define=SINALACS_MQTT_HOST=localhost \
    --dart-define=SINALACS_MQTT_PASSWORD="$MQTT_ACS_PASSWORD" \
    --dart-define=GOOGLE_MAPS_API_KEY="$GOOGLE_MAPS_API_KEY" )
```
Expected: os 15 do baseline **+ 1** (o do discador, Task 2) = 16 passam. Os dois `*_e2e.dart` não rodam aqui (o sufixo os esconde da descoberta por pasta), o que mantém `e2e.sh --emulator --full` e a CI iguais.

- [ ] **Step 4: Os dois e2e novos**

Run: `./scripts/qa/acs_gps_e2e.sh && ./scripts/qa/acs_gps_e2e.sh --sem-permissao && ./scripts/qa/acs_full_e2e.sh`
Expected: três `OK — …`. Depois: `docker compose up -d` e `ls .e2e/` sem `fixtures.json`.

- [ ] **Step 5: Guardas do repositório**

Run: `./scripts/qa/ci_invariants.sh && python3 scripts/qa/otp_relay_test.py && ./scripts/dev/check_documentation_links.sh`
Expected: todos verdes. (Os scripts novos **não** entram na CI: o `ci_invariants.sh` vigia a lista de jobs e o `android-e2e` já roda `e2e.sh --emulator`. Incluir o `acs_full_e2e.sh` na CI é decisão à parte — exige o banco de teste no runner.)

- [ ] **Step 6: Estado do repositório**

Run: `git status --short && git log --oneline -6`
Expected: árvore limpa; um commit por tarefa, **sem** `Co-Authored-By`. Sem push.

---

## Self-review

**Cobertura:** RF12 (GPS real: Tasks 1, 3), RF13/L-07 (SAMU: Task 2; UBS fora, justificado), RF07 + RF09 + RF11 + RBAC fim a fim no emulador (Task 4: login real, alerta MQTT, ACK, seletor com território, visita sincronizada e conferida no servidor), documentação (Task 5), execução no `emulator-5554` (Tasks 2–4, 6). RF08 cache, MFA/refresh token, iOS ficam explicitamente fora, com motivo.

**Placeholders:** dois pontos dependem de execução e têm o caminho de decisão escrito: o `ack_<id>` sumir após confirmar (Task 4, Step 4) e o caminho B do `--use-application-binary` (Task 3, Step 4, com os comandos). Nenhum "TBD".

**Consistência de tipos/nomes:** `EmergencyDialer.dial(String) → Future<bool>` e `samuNumber` (Task 2) usados só na Task 2; `declares()`/`manifest` (Task 1) reusados na Task 2; `acsCredentialFromRelay()` devolve `({String matricula, String senha})` e é consumido com `.matricula`/`.senha` na Task 4; `E2ePatient.id` usado em `patient_<id>`.

**Review Focus:** as 5 linhas têm teste dono — 1 → Task 3 (`denied`), 2 e 3 → Task 2, 4 e 5 → Task 4.

**Riscos que só a execução resolve:** (1) `flutter test --use-application-binary` preservar a permissão concedida (Task 3 tem o caminho B); (2) a imagem `Medium_Phone` ter discador (Task 2, Step 6 diz como distinguir); (3) o `pumpAndSettle` nunca assenta com MQTT/timers ativos — por isso `_pumpUntil` em vez de `pumpAndSettle`.
