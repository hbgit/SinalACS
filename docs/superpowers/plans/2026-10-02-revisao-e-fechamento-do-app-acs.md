# Revisão e fechamento do app ACS — Plano de Implementação

> **Para agentes:** SUB-SKILL OBRIGATÓRIA: use superpowers:subagent-driven-development (recomendado) ou superpowers:executing-plans para executar este plano tarefa a tarefa. Os passos usam checkbox (`- [ ]`).

**Goal:** Fechar as lacunas que a revisão de 2026-10-02 mediu no app `apps/acs` — layout que estoura com fonte ampliada, configuração Android que deixa dado clínico sair por backup, a meta de sincronização offline sem teste e a documentação de tema desatualizada — e provar tudo no `emulator-5554`.

**Architecture:** Quatro correções independentes, cada uma com um teste que falha antes: (1) o layout passa a aguentar 130% e 200% de fonte, com um harness no molde do `apps/admin`; (2) o manifesto proíbe backup automático e o APK de release é medido e iniciado no emulador; (3) a rajada de 100 visitas offline é provada em teste hermético e na jornada real do emulador; (4) a persistência do tema ganha teste e `spec/ui_design.md` deixa de dizer que o tema é fixo.

**Tech Stack:** Flutter 3 / Dart, `flutter_test`, `integration_test`, `shared_preferences`, Gradle/aapt2, `scripts/qa/acs_full_e2e.sh` (banco de teste), emulador Android 16 em `emulator-5554`.

**Spec:** `spec/PRD_system.md` (RF07–RF13, RNF02, RNF05, M2.4), `spec/ux_accessibility_assessment.md` (WCAG 1.4.4), `spec/lgpd_design.md` (§5.4 backup, INV-04), `spec/ui_design.md`, `apps/CLAUDE.md`.

## Estado verificado em 2026-10-02

Medido nesta sessão, não herdado de documento:

- `flutter analyze` em `apps/acs`: **No issues found**. `flutter test`: **208 passam**. Cobertura de linhas: `app.dart` 88,1%; `theme_controller.dart` 23,1%; `alert_feed.dart` 27,3%; `mqtt_secure_client.dart` 46,4%; `backend_client.dart` 53,9%.
- `emulator-5554` no ar (`adb devices`). `./scripts/qa/acs_full_e2e.sh` na linha de base: **OK** (login real, seletor por microárea, visita sincronizada). O script derruba a stack de desenvolvimento; `docker compose up -d` a restaura.
- **Achado 1 (defeito, RNF05/WCAG 1.4.4):** sonda descartável com `textScaleFactor` 1.3 e 2.0 em 360x800 estoura o layout: `app.dart:2230` (chip de conexão do cabeçalho, 94px a 130% e 308px a 200%), `app.dart:2213` (`_InfoRow`, até 370px), `app.dart:897` (botão "Atualizar dados da microárea", até 561px). A sonda parou na aba Área (um `pumpAndSettle` nunca assenta ali, porque o spinner do pull anima sem parar no fake): as abas Fila, Mapa, Visita e os itens de "Mais" **não foram medidos**. O `apps/admin` tem harness e teste para isso; o ACS, nenhum.
- **Achado 2 (configuração):** o `AndroidManifest.xml` `main` do ACS não declara `android:allowBackup`; o padrão do Android é `true`, então o backup automático pode levar para a nuvem do usuário o `shared_preferences` e o banco local da fila de visitas (dado de saúde, INV-04). `release` ainda assina com a chave de debug (`build.gradle.kts`).
- **Achado 3 (meta sem prova):** o PRD (M2.4) pede "100 registros offline sincronizam em < 5s após rede" e RNF02 pede sincronização > 99,5%. Nenhum teste do ACS enfileira 100 visitas; a fila manda **todas as pendentes num lote só** (`OfflineVisitQueue.sync`), sem teto de tamanho nem no cliente nem em `visits.sync`.
- **Achado 4 (documentação):** `spec/ui_design.md` §1.2 (linha 14) diz que o tema é "fixo e permanente" e que o app não reage a claro/escuro; o código tem `themeMode` + `darkTheme` + tela "Preferências" (Claro/Escuro/Automático, commit `45ae667`). A persistência (`ThemeController`) está em 23% de cobertura.

## Fora deste plano (e por quê)

- **RF08, cache persistido da microárea offline:** exige desenho de LGPD antes (já registrado em `PROGRESS.md`).
- **MFA/TOTP e refresh token:** adiados por decisão (`PROGRESS.md`).
- **iOS (`apps/acs/ios/` não existe), botão da UBS (sem fonte de contato), assinatura de release com chave própria, deploy de produção, mTLS no broker:** decisão de produto ou infraestrutura, sem dono neste plano.
- **`FLAG_SECURE` (bloquear captura de tela e miniatura nos "recentes"):** a lista da microárea mostra nome e condições crônicas; é decisão de produto/LGPD que ninguém registrou. Fica como pergunta ao dono do produto, não como código.
- **Testes de `alert_feed.dart` (`refused`/`unreachable`) e `backend_client.dart`:** `MqttAlertFeed.start` constrói o `MqttSecureClient` por dentro, sem ponto de injeção; testá-lo exigiria refatorar. Esses caminhos são provados no dispositivo por `smoke_test.dart`/`red_alert_cycle_test.dart` (stack de desenvolvimento). Não vale refatorar só para subir o número.
- **`app.dart` com 2266 linhas:** não dividir agora; nenhum achado depende disso.

## Global Constraints

- Português em comentários, mensagens de commit e texto de UI, como o resto do repositório.
- Commits **sem** atribuição de IA: nenhuma linha "Co-Authored-By", nenhuma "Generated with Claude Code" (regra do `CLAUDE.md` do projeto, que prevalece sobre o lembrete de atribuição da sessão). Tudo na branch `fix/app_acs`, sem push, merge nem PR.
- Nada de dado real de paciente em teste, log ou captura: só fixtures sintéticas.
- Cor clínica (`red`/`yellow`/`green`) usada como texto passa pelo token `*OnSurface` (`apps/CLAUDE.md`); este plano não mexe em cor.
- Triagem determinística e fila offline: preservar a semântica de retry/conflito/rejeição de `OfflineVisitQueue` (risco arquitetural nº 1 do `AGENTS.md`).
- O script de GPS e o de e2e nunca apagam um app já instalado sem `--reinstalar`; os novos passos de emulador seguem a mesma regra.
- Ambiente de todos os comandos: `export PATH="$PATH:$HOME/Android/Sdk/platform-tools:$HOME/flutter/bin"`; raiz do repositório `/home/rock/Documents/Dev/APPs/SinalACS`.

## Review Focus

1. **Fonte a 200% em tela baixa ou com teclado aberto:** o formulário de visita (`VisitRegistrationScreen`) é o que mais cresce; a rolagem tem de alcançar o botão "Salvar e enfileirar sincronização". → Task 1, percurso com rolagem e `ensureVisible` do botão.
2. **Fonte alterada com o app já aberto** (Configurações → tamanho da fonte, app em segundo plano): o cabeçalho tem de crescer sem clipar. → Task 1, teste `o cabeçalho cresce quando a escala muda em tempo de execução`.
3. **Restauração de backup em outro aparelho:** o app tem de continuar abrindo e pedir login (a chave do Keystore não migra). → Task 2 prova `allowBackup=false` e que o APK de release sobe sem `FATAL` no emulador; a recuperação de chave perdida já é de `SqlCipherVisitStore`.
4. **Rajada com uma visita recusada no meio:** 100 visitas, uma `rejected` e uma `conflict` não podem travar as outras 98 nem sumir do aparelho. → Task 3, teste `uma recusada e um conflito no meio não seguram as demais`.
5. **Valor inválido gravado na preferência de tema** (arquivo de preferências corrompido ou de versão futura): o app abre em "Automático". → Task 4.

---

### Task 1: Layout aguenta fonte ampliada (RNF05 / WCAG 1.4.4)

**Files:**
- Create: `apps/acs/test/support/layout_harness.dart`
- Create: `apps/acs/test/text_scale_test.dart`
- Modify: `apps/acs/lib/app/app.dart` (linhas 227, 740, 897–903, 2213, 2214–2250)

**Interfaces:**
- Consumes: `SinalAcsApp(backend:, feedBuilder:)`, `FakeAcsBackend`, `FakeAlertFeed`, `testAlert`, `testLocationCell` (`test/support/fakes.dart`); chaves `matricula_field`, `senha_field`, `login_button`.
- Produces (usados só dentro desta task e pela Task 3, que reaproveita `assentar`):
  - `Future<void> abrirPainel(WidgetTester tester, {required Size tamanho, double escalaDeFonte = 1.0})`
  - `Future<void> assentar(WidgetTester tester)` — o equivalente do `settleRealAsync` de `login_flow_test.dart`
  - `void esperarSemEstouro(WidgetTester tester, String contexto)`
  - `Future<void> percorrerPainelInteiro(WidgetTester tester, String contexto)`
  - `double acsHeaderHeight(BuildContext context)` em `app.dart`

- [ ] **Step 1: Escrever o harness**

Criar `apps/acs/test/support/layout_harness.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/app/app.dart';

import 'fakes.dart';

/// Ferramentas para provar que as telas do ACS cabem na janela em que foram
/// postas. Mesmo método do `apps/admin/test/support/layout_harness.dart`, e as
/// mesmas três armadilhas — errar qualquer uma produz um teste que passa
/// sempre:
///
/// 1. `RenderFlex` só denuncia o estouro quando **pinta**; checar antes de
///    assentar os quadros não vê nada.
/// 2. Item de `ListView` fora da viewport não é construído e nunca reclama;
///    daí [percorrerTelaInteira].
/// 3. `takeException()` consome **uma** exceção por chamada; [esperarSemEstouro]
///    esvazia todas.
///
/// Uma quarta é só do ACS: `pumpAndSettle()` **nunca assenta** na aba Área, porque
/// o spinner do pull anima sem parar contra o fake. [assentar] alterna quadros
/// e tempo real, como o `settleRealAsync` de `login_flow_test.dart`.

const destinosDaBarra = ['Área', 'Fila', 'Mapa', 'Visita'];

/// Itens da folha "Mais", pelo rótulo que `_moreItem` mostra.
const itensDoMais = [
  'Acionamento',
  'Geofencing',
  'Avisos à comunidade',
  'Convidar paciente',
  'Preferências',
];

/// Troca o tamanho da janela de uma sessão já aberta. [tamanho] é em dp, porque
/// `devicePixelRatio` é forçado a 1.
void redimensionar(WidgetTester tester, Size tamanho, {double escalaDeFonte = 1.0}) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = tamanho;
  tester.platformDispatcher.textScaleFactorTestValue = escalaDeFonte;
}

Future<void> assentar(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  }
  await tester.pump();
}

/// Falha se algum quadro pintado desde a última checagem reportou estouro.
void esperarSemEstouro(WidgetTester tester, String contexto) {
  final erros = <String>[];
  Object? erro;
  while ((erro = tester.takeException()) != null) {
    erros.add(erro.toString().split('\n').first);
  }
  expect(erros, isEmpty, reason: 'estouro de layout em $contexto: ${erros.join(' | ')}');
}

/// Abre o painel já logado (login pela tela, contra o `FakeAcsBackend`), numa
/// janela de tamanho e escala de fonte fixos. Confere a tela de login ANTES de
/// entrar: ela também tem cabeçalho.
Future<void> abrirPainel(
  WidgetTester tester, {
  required Size tamanho,
  double escalaDeFonte = 1.0,
}) async {
  redimensionar(tester, tamanho, escalaDeFonte: escalaDeFonte);
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  final alerta = testAlert(alertId: 'escala-1', locationCell: testLocationCell);
  await tester.pumpWidget(SinalAcsApp(
    backend: FakeAcsBackend(),
    feedBuilder: (queue) {
      queue.upsert(alerta); // `initialAlert` só seleciona; a tela lê a fila
      return FakeAlertFeed(queue);
    },
  ));
  await tester.pump();
  esperarSemEstouro(tester, 'tela de login');

  await tester.enterText(find.byKey(const Key('matricula_field')), 'ACS-001');
  await tester.enterText(find.byKey(const Key('senha_field')), 'senha-sintetica');
  final entrar = find.byKey(const Key('login_button'));
  await tester.ensureVisible(entrar); // numa janela baixa o botão fica abaixo da dobra
  await tester.pump();
  await tester.tap(entrar);
  await assentar(tester);
}

/// Rola a tela até o fim, checando estouro a cada passo.
Future<void> percorrerTelaInteira(WidgetTester tester, String contexto) async {
  esperarSemEstouro(tester, '$contexto (topo)');
  final rolaveis = find.byType(Scrollable);
  if (rolaveis.evaluate().isEmpty) return; // ex.: o mapa não rola
  for (var passo = 1; passo <= 8; passo++) {
    await tester.drag(rolaveis.last, const Offset(0, -320));
    await assentar(tester);
    esperarSemEstouro(tester, '$contexto (rolagem $passo)');
  }
}

Future<void> irParaDaBarra(WidgetTester tester, String destino) async {
  final alvo = find.descendant(of: find.byType(NavigationBar), matching: find.text(destino));
  await tester.tap(alvo);
  await assentar(tester);
  esperarSemEstouro(tester, 'navegação para $destino');
}

Future<void> irParaDoMais(WidgetTester tester, String item) async {
  final mais = find.descendant(of: find.byType(NavigationBar), matching: find.text('Mais'));
  await tester.tap(mais);
  await assentar(tester);
  esperarSemEstouro(tester, 'folha "Mais"');
  final alvo = find.text(item);
  await tester.ensureVisible(alvo);
  await tester.pump();
  await tester.tap(alvo);
  await assentar(tester);
  esperarSemEstouro(tester, 'navegação para $item');
}

/// Visita os quatro destinos da barra e os cinco itens de "Mais".
Future<void> percorrerPainelInteiro(WidgetTester tester, String contexto) async {
  for (final destino in destinosDaBarra) {
    await irParaDaBarra(tester, destino);
    await percorrerTelaInteira(tester, '$contexto / $destino');
  }
  for (final item in itensDoMais) {
    await irParaDoMais(tester, item);
    await percorrerTelaInteira(tester, '$contexto / $item');
  }
}
```

- [ ] **Step 2: Escrever o teste que falha**

Criar `apps/acs/test/text_scale_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/layout_harness.dart';

/// WCAG 1.4.4 (RNF05): o conteúdo precisa sobreviver a 200% de escala de texto.
///
/// O caminho é o layout aguentar, e não `MediaQuery.withClampedTextScaling`:
/// limitar a escala resolve o estouro desobedecendo à preferência de
/// acessibilidade de quem precisa dela.
void main() {
  for (final escala in const [1.3, 2.0]) {
    testWidgets('não estoura o layout com fonte a ${(escala * 100).toInt()}% em 360x800', (tester) async {
      await abrirPainel(tester, tamanho: const Size(360, 800), escalaDeFonte: escala);
      await percorrerPainelInteiro(tester, 'fonte a ${(escala * 100).toInt()}%');
    });
  }

  testWidgets('o cabeçalho cresce quando a escala muda em tempo de execução', (tester) async {
    // No Android a preferência de tamanho de fonte muda em Configurações, com o
    // app já aberto em segundo plano: o cabeçalho tem de acompanhar.
    await abrirPainel(tester, tamanho: const Size(360, 800));
    final alturaPadrao = tester.getSize(find.byType(AppBar)).height;

    redimensionar(tester, const Size(360, 800), escalaDeFonte: 2.0);
    await assentar(tester);
    final alturaAmpliada = tester.getSize(find.byType(AppBar)).height;

    expect(alturaAmpliada, greaterThan(alturaPadrao));
    esperarSemEstouro(tester, 'cabeçalho com fonte a 200%');
  });
}
```

- [ ] **Step 3: Rodar e ver falhar**

Run: `cd apps/acs && flutter test test/text_scale_test.dart 2>&1 | tail -40`
Expected: **FAIL** nos três testes. Mensagens com `estouro de layout em ... A RenderFlex overflowed by N pixels on the right` (o `-N` do cabeçalho `1.3`/`2.0`). Anotar **todos** os pontos que o relatório lista: os três conhecidos (`app.dart:2230`, `2213`, `897`) e qualquer outro que apareça nas abas Fila, Mapa, Visita ou nos itens de "Mais" — esses ainda não foram medidos. Se o teste passar de primeira, ele não está pegando o estouro: pare e confira o harness (armadilhas 1–3 no topo dele).

- [ ] **Step 4: Corrigir os três pontos conhecidos**

(a) Botão do pull — `app.dart` ~897–903: o `Text` dentro de um `Row(mainAxisSize: min)` não quebra linha. Trocar

```dart
              const Text('Atualizar dados da microárea'),
```
por
```dart
              const Flexible(child: Text('Atualizar dados da microárea', textAlign: TextAlign.center)),
```

(b) `_InfoRow` — `app.dart:2213`: o rótulo à esquerda não encolhe. Trocar `Text(label)` por `Flexible(child: Text(label))` e dar um respiro entre os dois, ficando

```dart
class _InfoRow extends StatelessWidget { const _InfoRow(this.label, this.value); final String label; final String value; @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.start, children: [Flexible(child: Text(label)), const SizedBox(width: 12), Flexible(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.bold)))])); }
```

(c) Cabeçalho — `app.dart` 2214–2250. A altura vem de quem monta o `Scaffold` (um `PreferredSizeWidget` não tem `BuildContext`; é o mesmo desenho do `adminHeaderHeight`). Acrescentar, antes de `_Header`:

```dart
/// Altura do cabeçalho, crescendo com a escala de fonte.
///
/// `preferredSize` não tem acesso ao `BuildContext`, então quem monta o
/// `Scaffold` calcula e entrega. O teto de 132 existe para que fonte a 200% não
/// coma metade da tela de um celular; o título já usa elipse.
double acsHeaderHeight(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(72).clamp(72.0, 132.0);
```

Trocar o construtor, o `preferredSize` e o chip:

```dart
class _Header extends StatelessWidget implements PreferredSizeWidget {
  const _Header(this.eyebrow, this.title, {required this.height, this.connected});

  final String eyebrow;
  final String title;

  /// Calculada por quem monta o Scaffold, via [acsHeaderHeight].
  final double height;

  /// Estado da conexão com o broker. `null` fora do painel.
  ///
  /// Fica no cabeçalho de propósito: um ACS precisa saber, sem procurar, que
  /// parou de receber alertas.
  final bool? connected;

  @override
  Size get preferredSize => Size.fromHeight(height);
```

e, dentro de `actions`, limitar o chip e deixar o rótulo cortar em vez de estourar (o ícone e a cor continuam dizendo o estado; o texto completo vai no `Semantics`):

```dart
      Padding(
        padding: const EdgeInsets.only(right: 12),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.5),
          child: Chip(
            key: const Key('broker_status'),
            avatar: connected == null ? null : Icon(
              connected! ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
              size: 18,
              color: connected! ? context.acsRisk.greenOnSurface : context.acsRisk.redOnSurface,
            ),
            label: Text(
              switch (connected) {
                null => 'Offline ready',
                true => 'Alertas em tempo real',
                false => 'Sem central',
              },
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ),
      ),
```

Os dois chamadores passam a altura (`app.dart:227` e `:740`):

```dart
    appBar: _Header('Segurança e rastreabilidade', 'Acesso institucional', height: acsHeaderHeight(context)),
```
```dart
    appBar: _Header('ACS • ${_brokerConnected ? 'em linha' : 'sem conexão'}', 'Painel operacional', height: acsHeaderHeight(context), connected: _brokerConnected),
```
(O primeiro deixa de ser `const`.)

- [ ] **Step 5: Rodar de novo e tratar o que sobrar**

Run: `cd apps/acs && flutter test test/text_scale_test.dart 2>&1 | tail -40`
Expected: se ainda falhar, cada falha nomeia a linha de `app.dart`. Corrija **cada ponto novo** com o mesmo padrão — `Flexible`/`Expanded` em filho de `Row`, `Wrap` no lugar de `Row` de chips, `maxLines`+`ellipsis` em rótulo secundário —, **sem** `withClampedTextScaling` e **sem** reduzir o tamanho da fonte. Rodar até **PASS 3/3**. Registrar no PROGRESS.md (Task 5) a lista final de pontos corrigidos.

- [ ] **Step 6: Confirmar a regressão completa**

Run: `cd apps/acs && flutter analyze && flutter test 2>&1 | tail -3`
Expected: `No issues found!` e `All tests passed!` com **≥ 211** testes (208 + 3).

- [ ] **Step 7: Provar no emulador com fonte a 200%**

O mapa é onde o layout real (fonte do Android, não a de teste) pode divergir. Usar o teste de integração que não precisa da stack:

```bash
export PATH="$PATH:$HOME/Android/Sdk/platform-tools:$HOME/flutter/bin"
adb -s emulator-5554 shell pm list packages br.com.prismrr.sinalacs.acs   # tem de vir vazio (senão: pare, ver guarda abaixo)
adb -s emulator-5554 shell settings put system font_scale 2.0
cd apps/acs && flutter test integration_test/map_flow_test.dart -d emulator-5554 \
  --dart-define=SINALACS_MQTT_PASSWORD="$(grep ^MQTT_ACS_PASSWORD ../../.env | cut -d= -f2-)" 2>&1 | tail -6
adb -s emulator-5554 shell settings put system font_scale 1.0
adb -s emulator-5554 uninstall br.com.prismrr.sinalacs.acs
```
Expected: `All tests passed!`; sem `A RenderFlex overflowed` no log. Se o teste pedir a stack (o `map_flow_test` declara os mesmos pré-requisitos do `smoke_test`), ela está de pé: `docker compose ps` deve mostrar `sinalacs-serverpod … (healthy)`; se não, `docker compose up -d`. **Guarda:** se o primeiro comando listar o pacote, o app de dev está instalado e reinstalar apagaria a fila SQLCipher e a chave do Keystore: não prossiga sem o usuário autorizar. O `font_scale` volta a `1.0` mesmo se o teste falhar (rodar o penúltimo comando à mão).

- [ ] **Step 8: Commit**

```bash
git add apps/acs/test/support/layout_harness.dart apps/acs/test/text_scale_test.dart apps/acs/lib/app/app.dart
git commit -m "fix(acs): layout aguenta fonte a 130% e 200% (WCAG 1.4.4) com harness no molde do admin"
```

---

### Task 2: Manifesto sem backup automático e APK de release medido (INV-04 / LGPD)

**Files:**
- Modify: `apps/acs/android/app/src/main/AndroidManifest.xml`
- Modify: `apps/acs/test/android_manifest_test.dart`

**Interfaces:**
- Consumes: —
- Produces: nada que outra task use.

- [ ] **Step 1: Escrever os testes que falham**

Acrescentar em `apps/acs/test/android_manifest_test.dart`, antes do `}` final de `main()`:

```dart
  test('NÃO deixa o Android copiar o app para a nuvem (INV-04 / LGPD)', () {
    // allowBackup é `true` por padrão. Sem `false` explícito, o backup
    // automático leva para a conta Google da pessoa o `shared_preferences` e o
    // banco local da fila de visitas — dado de saúde fora do controle do
    // sistema. A chave do SQLCipher vive no Keystore e não migra, então o
    // backup também não restauraria nada que prestasse: só vazaria.
    expect(
      RegExp(r'<application[^>]*android:allowBackup="false"', dotAll: true).hasMatch(manifest),
      isTrue,
    );
  });

  test('o nome na gaveta do aparelho é legível, não o identificador do pacote', () {
    expect(manifest, isNot(contains('android:label="sinalacs_acs"')));
    expect(manifest, contains('android:label="SinalACS ACS"'));
  });
```

- [ ] **Step 2: Ver falhar**

Run: `cd apps/acs && flutter test test/android_manifest_test.dart 2>&1 | tail -15`
Expected: os 2 testes novos **FALHAM** (`Expected: true  Actual: <false>` e `Expected: not contains 'android:label="sinalacs_acs"'`); os 4 antigos passam.

- [ ] **Step 3: Implementar**

Em `AndroidManifest.xml`, na tag `<application`, trocar `android:label="sinalacs_acs"` por `android:label="SinalACS ACS"` e acrescentar `android:allowBackup="false"`:

```xml
    <application
        android:label="SinalACS ACS"
        android:allowBackup="false"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
```

- [ ] **Step 4: Ver passar**

Run: `cd apps/acs && flutter test test/android_manifest_test.dart 2>&1 | tail -4`
Expected: `All tests passed!` (6 testes).

- [ ] **Step 5: Medir o manifesto mesclado do APK de release e subi-lo no emulador**

O teste lê o manifesto-fonte; o que vai para o aparelho é o **mesclado** (plugins acrescentam permissões). Medir o APK real:

```bash
export PATH="$PATH:$HOME/Android/Sdk/platform-tools:$HOME/flutter/bin"
set -a; source .env; set +a
adb -s emulator-5554 shell pm list packages br.com.prismrr.sinalacs.acs   # vazio, senão pare (guarda: reinstalar apaga a fila SQLCipher)
cd apps/acs
flutter build apk --release --dart-define=SINALACS_MQTT_PASSWORD="$MQTT_ACS_PASSWORD" 2>&1 | tail -4
AAPT2="$(ls ~/Android/Sdk/build-tools/*/aapt2 | tail -1)"
"$AAPT2" dump permissions build/app/outputs/flutter-apk/app-release.apk
"$AAPT2" dump badging build/app/outputs/flutter-apk/app-release.apk | grep -E "application-label:|debuggable|allowBackup" || true
```
Expected: `Built build/app/outputs/flutter-apk/app-release.apk`; as permissões são **exatamente** `INTERNET`, `ACCESS_COARSE_LOCATION`, `ACCESS_FINE_LOCATION` (mais a `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` interna do AndroidX, que não conta); `application-label:'SinalACS ACS'`; **sem** `application-debuggable`. Se aparecer qualquer outra permissão (em especial `ACCESS_BACKGROUND_LOCATION` ou `READ_*`/`WRITE_EXTERNAL_STORAGE`), **não siga**: é um plugin puxando permissão contra a decisão §4 — descobrir qual (`./gradlew :app:dependencies`) e registrar no PROGRESS.md antes de decidir. Se o build de release falhar (R8 removendo classe usada por reflexão), é achado real: copie o erro para o ledger e conserte antes de seguir.

Subir e abrir no emulador, conferindo que não há falha de inicialização:

```bash
adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-release.apk
adb -s emulator-5554 logcat -c
adb -s emulator-5554 shell monkey -p br.com.prismrr.sinalacs.acs -c android.intent.category.LAUNCHER 1 >/dev/null
sleep 8
adb -s emulator-5554 shell pidof br.com.prismrr.sinalacs.acs
adb -s emulator-5554 logcat -d | grep -E "FATAL EXCEPTION|AndroidRuntime" | head -5
adb -s emulator-5554 uninstall br.com.prismrr.sinalacs.acs
```
Expected: `pidof` imprime um número (o processo está vivo depois de 8 s); o `grep` não imprime nada; o pacote é removido ao final (o app de release de teste não fica para a próxima rodada).

- [ ] **Step 6: Commit**

```bash
git add apps/acs/android/app/src/main/AndroidManifest.xml apps/acs/test/android_manifest_test.dart
git commit -m "fix(acs): manifesto proíbe backup automático e dá nome legível ao app; release medido no emulador"
```

---

### Task 3: Rajada de 100 visitas offline (M2.4 / RNF02)

**Files:**
- Create: `apps/acs/test/offline_burst_test.dart`
- Modify: `apps/acs/integration_test/full_journey_e2e.dart` (novo `testWidgets` + imports)

**Interfaces:**
- Consumes: `OfflineVisitQueue({VisitStore? store, VisitSynchronizer? synchronizer})`, `OfflineVisitRecord({required patientId, required risk, required status, localId, createdAt, ...})`, `InMemoryVisitStore`, `FakeVisitSynchronizer({statusFor, messageFor, throwOnPush})` com `.batches`, `SyncOutcomeKind`, `syntheticPatientId(int)` (`test/support/fakes.dart`); no dispositivo, `BackendClient`, `BackendVisitSynchronizer(backend:)`, `acsCredentialFromRelay()`, `e2ePatient('main')`.
- Produces: —

- [ ] **Step 1: Escrever o teste hermético (falha por não existir o arquivo; vira vermelho de verdade com o `statusFor`)**

Criar `apps/acs/test/offline_burst_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';

import 'support/fakes.dart';

/// M2.4 / RNF02: "100 registros offline sincronizam em < 5s após rede" e
/// sincronização > 99,5%. Aqui a parte determinística: nada se perde, nada
/// duplica, e a fila sobrevive a um reinício. O tempo contra o servidor de
/// verdade é medido no dispositivo (`integration_test/full_journey_e2e.dart`).
void main() {
  OfflineVisitRecord visita(int n) => OfflineVisitRecord(
        patientId: syntheticPatientId(n),
        risk: 'yellow',
        status: 'PENDENTE',
        localId: 'burst-$n',
        createdAt: DateTime.utc(2026, 10, 2, 8).add(Duration(minutes: n)),
      );

  test('100 visitas enfileiradas, reiniciadas e sincronizadas: nenhuma se perde', () async {
    final disco = InMemoryVisitStore();
    final antes = OfflineVisitQueue(store: disco);
    for (var n = 0; n < 100; n++) {
      await antes.add(visita(n));
    }
    expect(antes.pendingCount, 100);

    // Reinício do app: outra fila sobre o mesmo "disco".
    final envio = FakeVisitSynchronizer();
    final depois = OfflineVisitQueue(store: disco, synchronizer: envio);
    await depois.restore();
    expect(depois.pendingCount, 100, reason: 'o que estava no disco volta inteiro');

    final resultado = await depois.sync();

    expect(resultado.kind, SyncOutcomeKind.synced);
    expect(depois.pendingCount, 0);
    expect(depois.syncedCount, 100);
    expect(envio.batches, hasLength(1), reason: 'um lote só: uma ida e volta ao servidor');
    final enviados = envio.batches.single.map((v) => v.localId).toSet();
    expect(enviados, hasLength(100), reason: 'nenhum localId repetido (dedupe do servidor)');
  });

  test('uma recusada e um conflito no meio não seguram as demais', () async {
    final envio = FakeVisitSynchronizer(
      statusFor: (v) => switch (v.localId) {
        'burst-40' => 'rejected',
        'burst-70' => 'conflict',
        _ => 'synced',
      },
      messageFor: (v) => v.localId == 'burst-40' ? 'paciente de outra microárea' : null,
    );
    final fila = OfflineVisitQueue(synchronizer: envio);
    for (var n = 0; n < 100; n++) {
      await fila.add(visita(n));
    }

    await fila.sync();

    expect(fila.syncedCount, 98);
    expect(fila.rejectedCount, 1, reason: 'a recusada fica visível no aparelho até o ACS descartar');
    expect(fila.rejectedVisits.single.localId, 'burst-40');
    expect(fila.rejectedVisits.single.rejectionReason, 'paciente de outra microárea');
    expect(fila.conflictCount, 1, reason: 'o conflito fica registrado');
    // Conflito VOLTA para a fila (`_applyOutcomes`: "precisa de resolução, não de
    // descarte"); a recusada, não — ela sai da retentativa e fica só visível.
    expect(fila.pendingCount, 1);
    expect(fila.pendingVisits.single.localId, 'burst-70');
    expect(fila.pendingVisits.single.status, 'CONFLITO');
  });

  test('sem rede, as 100 continuam pendentes e a próxima tentativa as leva', () async {
    final envio = FakeVisitSynchronizer(throwOnPush: true);
    final fila = OfflineVisitQueue(synchronizer: envio);
    for (var n = 0; n < 100; n++) {
      await fila.add(visita(n));
    }

    final falha = await fila.sync();
    expect(falha.kind, SyncOutcomeKind.error);
    expect(fila.pendingCount, 100, reason: 'falha de rede não perde o lote');

    envio.throwOnPush = false;
    await fila.sync();
    expect(fila.pendingCount, 0);
    expect(fila.syncedCount, 100);
  });
}
```

- [ ] **Step 2: Rodar**

Run: `cd apps/acs && flutter test test/offline_burst_test.dart 2>&1 | tail -20`
Expected: **PASS 3/3** — é um teste de **caracterização**: o comportamento já existe e este teste o trava (o contrato de conflito e recusa foi lido em `OfflineVisitQueue._applyOutcomes`: `conflict` entra em `_conflicts` **e** volta a `_pending` com status `CONFLITO`; `rejected` vai só para `_rejected`). Se algum falhar, é defeito real da fila (não do teste): pare e use systematic-debugging antes de seguir. Para provar que o teste enxerga uma regressão, trocar temporariamente `'burst-40' => 'rejected'` por `'burst-40' => 'synced'` deve fazer o 2º teste **falhar** (`Expected: <1> Actual: <0>`); desfazer.

- [ ] **Step 3: Escrever a prova no dispositivo (falha antes de a fixture ser usada)**

Em `apps/acs/integration_test/full_journey_e2e.dart`, acrescentar os imports

```dart
import 'package:sinalacs_acs/core/services/backend_visit_synchronizer.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';
```

e, dentro de `main()`, **depois** do `testWidgets` existente (mesmo nível), este teste. Ele usa o `BackendClient` real contra o banco de teste, sem tela:

```dart
  testWidgets('100 visitas offline sobem em menos de 5 s (M2.4)', (tester) async {
    final ca = (await rootBundle.load(BackendConfig.rpcCaAsset)).buffer.asUint8List();
    final backend = BackendClient(trustedCaBytes: ca);
    addTearDown(backend.close);
    final cred = await acsCredentialFromRelay();
    final main = e2ePatient('main');
    await backend.login(matricula: cred.matricula, senha: cred.senha);

    final fila = OfflineVisitQueue(synchronizer: BackendVisitSynchronizer(backend: backend));
    final base = DateTime.now().toUtc().subtract(const Duration(days: 1));
    for (var n = 0; n < 100; n++) {
      // `localId` fica no padrão (um UUID novo): o protocolo o tipa como
      // `UuidValue` e o servidor recusa o que não for UUID.
      await fila.add(OfflineVisitRecord(
        patientId: main.id,
        risk: 'green',
        status: 'PENDENTE',
        createdAt: base.add(Duration(minutes: n)),
      ));
    }
    final enviados = {for (final v in fila.pendingVisits) v.localId.toLowerCase()};
    expect(enviados, hasLength(100));

    final relogio = Stopwatch()..start();
    final resultado = await fila.sync();
    relogio.stop();

    expect(resultado.kind, SyncOutcomeKind.synced, reason: resultado.message);
    expect(fila.syncedCount, 100);
    expect(fila.pendingCount, 0);
    // ignore: avoid_print
    print('rajada: 100 visitas em ${relogio.elapsedMilliseconds} ms');
    expect(relogio.elapsed, lessThan(const Duration(seconds: 5)),
        reason: 'PRD M2.4: 100 registros offline sincronizam em < 5 s');

    final remotas = await backend.pullVisits(since: DateTime.fromMillisecondsSinceEpoch(0));
    final noServidor = {for (final v in remotas) v.localId.toString().toLowerCase()};
    expect(noServidor.containsAll(enviados), isTrue,
        reason: 'as 100 visitas estão no servidor, conferidas por pull');
  });
```

(`backend.login` e `pullVisits` são os métodos de `AcsBackend`: `Future<AuthSession> login({required String matricula, required String senha})` e `Future<List<VisitSyncEntry>> pullVisits({required DateTime since})`; `VisitSyncEntry.localId` é `UuidValue`, por isso o `toString()`.)

- [ ] **Step 4: Rodar no emulador contra o banco de teste**

```bash
export PATH="$PATH:$HOME/Android/Sdk/platform-tools:$HOME/flutter/bin"
adb -s emulator-5554 shell pm list packages br.com.prismrr.sinalacs.acs   # vazio, senão pare
./scripts/qa/acs_full_e2e.sh 2>&1 | tee /tmp/acs_full_rajada.log | tail -12
docker compose up -d    # o script derruba a stack de desenvolvimento
grep "rajada:" /tmp/acs_full_rajada.log
```
Expected: `OK — jornada completa do ACS contra o banco de teste`; linha `rajada: 100 visitas em NNN ms` com NNN < 5000. Se o servidor recusar o lote (corpo grande, transação longa) ou passar de 5 s: **não relaxe o limite**. Meça onde o tempo vai (`docker compose logs backend`), e só então decida entre fatiar em lotes de 50 no `BackendVisitSynchronizer` (com um teste hermético novo que prove que o resultado final é idêntico) e registrar o gargalo no PROGRESS.md. Registrar a decisão como `Ruling:` no ledger.

- [ ] **Step 5: Commit**

```bash
git add apps/acs/test/offline_burst_test.dart apps/acs/integration_test/full_journey_e2e.dart
git commit -m "test(acs): rajada de 100 visitas offline provada na fila e contra o servidor real no emulador"
```

---

### Task 4: Persistência do tema testada e `ui_design.md` corrigido

**Files:**
- Create: `apps/acs/test/theme_controller_test.dart`
- Modify: `spec/ui_design.md:14`
- Modify: `spec/ux_ui_test_plan.md:170`

**Interfaces:**
- Consumes: `ThemeController([ThemeMode value])`, `.restore()`, `.setThemeMode(ThemeMode)`, chave `theme_mode` em `SharedPreferences`.
- Produces: —

- [ ] **Step 1: Escrever os testes**

Criar `apps/acs/test/theme_controller_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinalacs_acs/core/services/theme_controller.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('sem nada gravado, abre em Automático', () async {
    final controller = ThemeController();
    await controller.restore();
    expect(controller.value, ThemeMode.system);
  });

  test('a escolha sobrevive a um reinício', () async {
    final primeira = ThemeController();
    await primeira.setThemeMode(ThemeMode.light);

    final depoisDoReinicio = ThemeController();
    await depoisDoReinicio.restore();
    expect(depoisDoReinicio.value, ThemeMode.light);
  });

  test('valor inválido na preferência (arquivo corrompido ou de versão futura) cai em Automático', () async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'sepia'});
    final controller = ThemeController(ThemeMode.dark);
    await controller.restore();
    expect(controller.value, ThemeMode.system);
  });

  test('o ouvinte é avisado ao trocar', () async {
    final controller = ThemeController();
    var avisos = 0;
    controller.addListener(() => avisos++);
    await controller.setThemeMode(ThemeMode.dark);
    expect(avisos, 1);
    expect(controller.value, ThemeMode.dark);
  });
}
```

- [ ] **Step 2: Rodar**

Run: `cd apps/acs && flutter test test/theme_controller_test.dart 2>&1 | tail -10`
Expected: **PASS 4/4** (caracterização de comportamento já existente). Para provar que o 3º teste enxerga uma regressão, trocar temporariamente `orElse: () => ThemeMode.system` em `theme_controller.dart` por `orElse: () => ThemeMode.dark` e rodar: o teste **falha** (`Expected: ThemeMode:<ThemeMode.system> Actual: ThemeMode:<ThemeMode.dark>`); **desfazer** a troca (`git diff apps/acs/lib` deve sair vazio).

- [ ] **Step 3: Corrigir a documentação**

`spec/ui_design.md`, linha 14, trocar o parágrafo do "Dark Mode (§1.2)" por (preservar o marcador `* **Dark Mode (§1.2):**`):

```
* **Tema (§1.2):** O escuro é o padrão de identidade visual (economia de bateria e menos fadiga em campo), mas **não é fixo**: o ACS e o paciente têm `themeMode` com `darkTheme` e uma tela "Preferências" com Claro, Escuro e Automático (segue o sistema), persistida localmente (`ThemeController`). Os dois temas passam na mesma matriz de contraste WCAG (`contrast_tokens_test.dart` e `contrast_tokens_light_test.dart`). Esta linha dizia que o tema era "fixo e permanente"; deixou de valer com o commit `45ae667`.
```

`spec/ux_ui_test_plan.md`, linha 170, trocar `**[Resolvido] §1.2 (Dark Mode):** Documentado formalmente como fixo/permanente no documento de design.` por:

```
* **[Resolvido, revisto em 2026-10-02] §1.2 (Dark Mode):** A decisão de "fixo/permanente" foi superada: o app passou a oferecer Claro/Escuro/Automático (`45ae667`). O documento de design foi atualizado; o teste de regressão é `theme_controller_test.dart` mais as duas matrizes de contraste.
```
(manter o marcador `*` que a linha já tem no início.)

- [ ] **Step 4: Conferir links e testes**

Run: `./scripts/qa/check_documentation_links.sh && (cd apps/acs && flutter test 2>&1 | tail -2)`
Expected: sem erro de link; `All tests passed!` com **≥ 218** testes (208 + 3 + 3 + 4).

- [ ] **Step 5: Commit**

```bash
git add apps/acs/test/theme_controller_test.dart spec/ui_design.md spec/ux_ui_test_plan.md
git commit -m "test(acs): persistência do tema coberta; ui_design deixa de dizer que o tema é fixo"
```

---

### Task 5: Registro e barra final no emulador

**Files:**
- Modify: `PROGRESS.md` (seção "Finalização do app ACS (2026-10-01)")
- Modify: `apps/CLAUDE.md` (parágrafo "ACS: permissões, SAMU e e2e")

**Interfaces:** nenhuma.

- [ ] **Step 1: Registrar no `PROGRESS.md`**

Depois do item "**Minors da revisão — fechados (2026-10-01).**" acrescentar:

```
- **Revisão do app ACS e fechamento (2026-10-02).** Plano: `docs/superpowers/plans/2026-10-02-revisao-e-fechamento-do-app-acs.md`. (1) **Fonte ampliada (RNF05/WCAG 1.4.4):** o ACS estourava o layout a 130% e 200% (cabeçalho, `_InfoRow`, botão do pull, mais o que o harness achou nas outras abas: <listar os pontos reais da Task 1, Step 5>); corrigido, com `test/support/layout_harness.dart` e `test/text_scale_test.dart`. (2) **Manifesto:** `android:allowBackup="false"` (o padrão era `true`: o backup automático podia levar o banco local e as preferências para a nuvem) e nome legível; o APK de release foi medido (`aapt2 dump permissions`: só INTERNET e localização em primeiro plano) e subiu no emulador sem `FATAL`. (3) **M2.4/RNF02:** 100 visitas offline provadas na fila (`offline_burst_test.dart`) e contra o servidor real no emulador (<medido> ms, meta < 5000). (4) **Tema:** `ThemeController` coberto e `ui_design.md` corrigido. **Continua aberto:** assinatura de release com chave própria, `FLAG_SECURE` (decisão de produto/LGPD: a lista da microárea mostra nome e condições crônicas), RF08 persistido, MFA/refresh token, iOS, botão da UBS.
```
(Substituir os dois marcadores `<...>` pelos valores reais medidos; não deixar os `<>` no arquivo.)

- [ ] **Step 2: Registrar no `apps/CLAUDE.md`**

No parágrafo "**ACS: permissões, SAMU e e2e (2026-10-01).**", acrescentar ao final: "O manifesto do ACS tem `android:allowBackup="false"` (guardado por `android_manifest_test.dart`). `test/text_scale_test.dart` percorre as quatro abas e os cinco itens de "Mais" a 130% e 200% de fonte (`test/support/layout_harness.dart`; `pumpAndSettle` nunca assenta na aba Área, use `assentar`). `test/offline_burst_test.dart` e o segundo teste de `integration_test/full_journey_e2e.dart` guardam a meta de 100 visitas offline em menos de 5 s."

- [ ] **Step 3: Barra final**

```bash
export PATH="$PATH:$HOME/Android/Sdk/platform-tools:$HOME/flutter/bin"
(cd apps/acs && flutter analyze && flutter test 2>&1 | tail -2)
(cd scripts/qa && python3 contagem_validation_report_test.py && python3 otp_relay_test.py)
python3 scripts/qa/contagem_validation_report.py
./scripts/qa/lib_rele_test.sh && ./scripts/qa/acs_gps_e2e_test.sh
./scripts/qa/ci_invariants.sh && ./scripts/qa/check_documentation_links.sh
adb -s emulator-5554 shell pm list packages br.com.prismrr.sinalacs.acs   # vazio
./scripts/qa/acs_gps_e2e.sh && ./scripts/qa/acs_gps_e2e.sh --sem-permissao
./scripts/qa/acs_full_e2e.sh; docker compose up -d
```
Expected: `No issues found!`; `flutter test` **≥ 218** passam; Python `OK`; `ok: contagem do validation_report confere`; `ok: lib_rele` e `ok: acs_gps_e2e`; `ci_invariants` `ok`; links sem erro; os dois GPS `OK` (sem `--reinstalar`: o pacote tem de estar ausente); jornada `OK` com a linha `rajada:`; `sinalacs-serverpod … (healthy)` e `ls .e2e/fixtures.json` → inexistente.

- [ ] **Step 4: Estado do repositório e commit**

```bash
git status --short && git log --oneline -8 && git log -8 --format=%B | grep -ci "co-authored\|generated with"
git add PROGRESS.md apps/CLAUDE.md
git commit -m "docs: registra a revisão e o fechamento do app ACS"
```
Expected: árvore limpa depois do commit; **`0`** na contagem de atribuições de IA; sem push.

---

## Auto-revisão

**Cobertura:** achado 1 → Task 1; achado 2 → Task 2; achado 3 → Task 3; achado 4 → Task 4; registro e barra no emulador → Task 5. Os itens "Fora deste plano" têm o motivo escrito e nenhum vira tarefa escondida.

**Placeholders:** não há "TBD". Dois pontos dependem de medir e têm as duas saídas escritas: os pontos de estouro além dos três conhecidos (Task 1, Step 5: regra de correção, proibição de `withClampedTextScaling`) e o tempo da rajada contra o servidor (Task 3, Step 4: não relaxar o limite; medir; fatiar ou registrar). Os dois `<>` do PROGRESS.md têm instrução explícita de substituição.

**Consistência de nomes:** `assentar`, `esperarSemEstouro`, `abrirPainel`, `percorrerPainelInteiro`, `redimensionar` definidos na Task 1 e usados só nela; `acsHeaderHeight` definido e usado nos dois chamadores de `_Header`; `syntheticPatientId`, `FakeVisitSynchronizer.batches/throwOnPush/statusFor/messageFor` batem com `test/support/fakes.dart`; `backend.login(matricula:, senha:)` e `pullVisits(since:)` batem com `AcsBackend`.

**Review Focus:** as 5 linhas têm teste dono (1 e 2 na Task 1; 3 na Task 2; 4 e a rajada na Task 3; 5 na Task 4).

**Riscos que só a execução resolve:** (1) quantos pontos de estouro existem fora da aba Área (a sonda parou ali); (2) se o release com R8 compila e abre; (3) se `visits.sync` aguenta 100 entradas em um lote dentro de 5 s no banco de teste; (4) se o `map_flow_test` roda sem a stack (Task 1, Step 7).

**Conferido na escrita:** o contrato de conflito/recusa (`_applyOutcomes`: conflito volta a `_pending`, recusa não) e o tipo de `localId` (`UuidValue` no protocolo) foram lidos no código e corrigidos no plano antes de entregar.
