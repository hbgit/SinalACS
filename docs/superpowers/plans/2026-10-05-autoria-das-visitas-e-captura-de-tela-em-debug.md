# Autoria das visitas sob outro token e opt-out de captura de tela só em debug — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** (1) Confirmar, com testes, que visitas de um ACS nunca sobem sob o token de outro ACS nem são atribuídas a quem as transportou, e fechar o que sobrar; (2) permitir captura de tela do app do ACS **apenas** em build de debug, escolhida em tempo de compilação, mantendo `FLAG_SECURE` em release por construção.

**Architecture:** O ponto 1 está **quase todo entregue** (fila por dono, token de envio diferido por dono, `syncLegacy` que nunca atribui autoria ao transportador): o plano mede, prende o que falta com testes de caracterização e deixa um único ponto como **decisão explícita** (as linhas legadas sem dono). O ponto 2 usa um `BuildConfig.ALLOW_SCREEN_CAPTURE` nativo, `false` por padrão, que só o build `debug` pode ligar por uma propriedade do Gradle; o Gradle recusa essa propriedade em release.

**Tech Stack:** Flutter/Dart (`apps/acs`, `flutter test`), Kotlin (`MainActivity.kt`), Gradle Kotlin DSL (AGP 9.0.1), Serverpod/Dart (`backend/sinalacs_server`, `dart test`), bash (`scripts/qa`, `scripts/dev`).

**Spec:** `PROGRESS.md` (seção "Fila de visitas por dono e corrida do login", linhas ~762–775, e "FLAG_SECURE escurece captura e gravação", linha ~612); `docs/superpowers/plans/2026-10-03-fila-de-visitas-por-dono-e-corrida-do-login.md` (D1–D9); `docs/superpowers/plans/2026-10-02-pendencias-do-acs-flag-secure-ubs-rf08-mfa-assinatura-mtls.md` (D1); `spec/lgpd_design.md` §5.6 e §5.11; `CLAUDE.md` (invariantes).

Levantamento com `graphify query` e leitura do código em 2026-10-05, **antes** de executar (a Task 1 repete as medidas):

| Ponto | Estado observado |
|-------|------------------|
| 1a. Fila amarrada ao dono | **Entregue.** `offline_visits.owner` (schema v7), `VisitStorage.forOwner(userId)` só lê/grava/apaga `WHERE owner = ?`; `BackendVisitSynchronizer` recusa sessão de outro dono (`visit_owner_flow_test.dart:421`, `:450`). |
| 1b. Nunca pegar carona no token de outro | **Entregue para linhas com dono.** `DeferredFlushService` sobe a fila de A por `visits.syncDeferred` com o **token de envio diferido de A** (`acs_upload_token|<userId>`), não pelo JWT de B; o servidor resolve o dono pelo token. |
| 1c. Servidor não credita B | **Entregue.** `VisitSyncService.syncLegacy` grava `acsId` nulo, `authorship = legacyUnclaimed`, `originDeviceId`, e audita `visit_legacy_sync` com o transportador como transportador (`visit_sync_service.dart:272-310`, `:396`). |
| 1d. Linhas **legadas** (sem dono, schema v6) sobem pela sessão de quem logar | **Aberto como decisão.** `DeferredFlushService._flushLegacy` usa `syncLegacyVisits` com o JWT do ACS logado como *transporte*. Só existem em aparelho que rodou uma build **anterior a 2026-10-04**; não há release publicada (`CLAUDE.md`: protótipo). |
| 2. Opt-out de captura só em debug | **Aberto.** `MainActivity.onCreate` aplica `FLAG_SECURE` sem condição; `build.gradle.kts` não habilita `buildConfig` (AGP 9 desliga por padrão). `acs_secure_window.sh` e `secure_window_test.dart` provam a flag num **APK de debug**, então um opt-out que abra o debug por padrão os quebraria. |

**Por que `BuildConfig` nativo e não `kReleaseMode`:** a flag é aplicada em `Activity.onCreate`, antes de qualquer Dart rodar; `kReleaseMode` é uma constante do Dart e só poderia agir depois, por um `MethodChannel`, deixando a janela sem proteção até o primeiro quadro (e a miniatura dos recentes). `BuildConfig` é constante de compilação da plataforma, o mesmo princípio pedido, no lugar certo.

## Global Constraints

- Triagem determinística e nunca alterável à mão; alerta vermelho nunca é descartado em silêncio (`CLAUDE.md`).
- A microárea do ACS restringe o acesso aos dados daquele território (INV-01/RNF06).
- Nunca dado real de paciente em teste, log, captura ou configuração de dev; credenciais de teste sintéticas.
- Em release a janela do ACS é `FLAG_SECURE`, sem exceção, sem menu de desenvolvedor, sem propriedade em tempo de execução.
- Sincronização offline: preservar retry/fila/conflito (`offline_visit_queue.dart`, `SyncFsm`); a visita só sai do aparelho em `synced`.
- `-Psinalacs.*` só vale com o texto exato `true` (`licenca()` em `build.gradle.kts`).
- Documentação e UI em português; commits sem atribuição de IA (regra do repositório). Rodar `graphify update .` depois de modificar código.

## Fora do escopo

- Envio em segundo plano do SO (WorkManager) e wipe forçado por supervisor: já listados como abertos no `PROGRESS.md` (D8); exigem decisão fora de `spec/stack.md`.
- iOS (não existe) e o equivalente de `FLAG_SECURE` no App Switcher.
- Credencial de cliente de dispositivo (client credentials) como autenticação do envio: o token de envio por dono já cumpre o papel ("sou o dispositivo X enviando pendências do usuário A"), com revogação no servidor.

## Review Focus

- ACS B loga com visitas de A pendentes: nada de A sai com o JWT de B; o lote de A continua `PENDENTE` e `Sair` mostra o que ficou (já coberto; a Task 2 só prende o lado do servidor).
- Visita de A reenviada com o JWT de B por um cliente adulterado: o servidor recusa o `localId` de outro agente e não muda a autoria (Task 2).
- Linha legada sem dono enviada por B: fica `legacyUnclaimed`, `acsId` nulo, nunca aparece no `pull` de B como dele (Task 2).
- Build de **release** com `-Psinalacs.allowScreenCapture=true`: o Gradle falha com mensagem que diz o porquê (Task 3).
- Build de **debug** sem a propriedade: continua `FLAG_SECURE` (as provas de QA existentes não regridem) (Task 3).

---

### Task 1: Verificar o ponto 1 com evidência (somente medir)

**Files:**
- Modify: nenhum. O resultado vira a tabela do commit da Task 5 e decide a Task 2.

**Interfaces:**
- Produces: `FECHADO`/`ABERTO` para 1a–1d, cada um com o comando e a saída.

- [ ] **Step 1: Orientar-se no grafo (obrigatório antes de abrir código)**

```bash
cd /home/rock/Documents/Dev/APPs/SinalACS
graphify query "DeferredFlushService flushAll syncDeferred syncLegacyVisits owner session" --budget 1200
graphify query "VisitSyncService syncLegacy legacyUnclaimed authorship transporter" --budget 1000
graphify explain "BackendVisitSynchronizer"
```
Expected: nós `DeferredFlushService`, `VisitSyncService.syncLegacy`, `BackendVisitSynchronizer`, `sqlcipher_visit_store.dart`.

- [ ] **Step 2: Rodar os testes que provam 1a–1c (nenhum código muda)**

```bash
cd apps/acs && flutter test test/visit_owner_flow_test.dart test/visit_storage_owner_test.dart test/deferred_flush_service_test.dart test/deferred_flush_triggers_test.dart
cd ../../backend/sinalacs_server && dart test test/unit/visit_legacy_sync_test.dart test/unit/visit_sync_service_test.dart
```
Expected: tudo passa. Anotar, do `visit_owner_flow_test.dart`, o teste `Sair e entrar com OUTRO ACS: o novo não vê, não envia nem descarta visita do anterior` e `BackendVisitSynchronizer recusa enviar com a sessão de outro usuário`; e do servidor, o teste que afirma `acsId` nulo e `legacyUnclaimed` na visita legada.

- [ ] **Step 3: Medir 1d (quem pode ter linha legada)**

```bash
cd /home/rock/Documents/Dev/APPs/SinalACS
grep -n "version:\|_dbVersion\|schemaVersion\|version = " apps/acs/lib/core/database/encrypted_database.dart | head
git log --diff-filter=A --format='%h %ad %s' --date=short -- apps/acs/lib/core/database/sqlcipher_visit_store.dart | tail -2
git tag --list | head; grep -n "release\|publicad" PROGRESS.md | grep -i "play\|loja\|publicad" | head -3
```
Expected: schema local em 7; nenhuma tag de release e nenhuma publicação em loja → as linhas legadas só existem em aparelhos de desenvolvimento anteriores a 2026-10-04. **Decisão registrada:** com esse resultado, 1d **permanece como está** (a visita sobe sem autoria, auditada, e o servidor nunca a credita ao transportador). Se algum release tiver existido, parar e pedir decisão ao responsável antes da Task 2.

- [ ] **Step 4: Registrar** o resultado literal; nada a commitar.

---

### Task 2: Prender, no servidor e no cliente, o que a Task 1 só leu (testes de caracterização)

**Files:**
- Test: `backend/sinalacs_server/test/unit/visit_legacy_sync_test.dart` (acrescentar)
- Test: `backend/sinalacs_server/test/unit/visit_sync_service_test.dart` (acrescentar)

**Interfaces:**
- Consumes: os helpers e fakes já usados por esses dois arquivos (ler o `setUp` e o fake de store de cada um antes de escrever; usar os nomes deles, não os abaixo, se diferirem).

São testes de **caracterização**: o comportamento já existe, então eles passam de primeira. Para cada um, provar que ele **pode** falhar com uma mutação (Step 3), senão não valem nada.

- [ ] **Step 1: Escrever os testes**

Em `visit_sync_service_test.dart`, junto dos testes de autoria:

```dart
    test('o ACS B não consegue reescrever visita do ACS A enviando o mesmo localId', () async {
      // A grava a visita com `localId` L.
      await serviceDeA.sync(user: acsA, deviceId: 'dev-1', entries: [entry(localId: 'L')]);

      // B reenvia o MESMO `localId` com o próprio JWT (cliente adulterado).
      final resultados = await serviceDeB.sync(user: acsB, deviceId: 'dev-1', entries: [entry(localId: 'L')]);

      expect(resultados.single.status, SyncStatus.rejected);
      // A autoria continua a de A, e nada foi regravado.
      final gravada = await store.findByLocalId('L');
      expect(gravada!.acsId, UuidValue.fromString(acsA.id));
      expect(gravada.authorship, VisitAuthorship.acs);
    });
```

Em `visit_legacy_sync_test.dart`, junto do teste de autoria nula:

```dart
    test('visita legada enviada por B nunca vira de B: sem acsId, e fora do pull de B', () async {
      await service.syncLegacy(transporter: acsB, deviceId: 'dev-1', entries: [entry(localId: 'LEG-1')]);

      final gravada = await store.findByLocalId('LEG-1');
      expect(gravada!.acsId, isNull);
      expect(gravada.authorship, VisitAuthorship.legacyUnclaimed);

      final doPullDeB = await service.pull(user: acsB, since: null);
      expect(doPullDeB.visits.map((v) => v.localId), isNot(contains('LEG-1')));
    });
```
(`serviceDeA`/`serviceDeB`, `acsA`/`acsB`, `entry(...)`, `store.findByLocalId` e `service.pull` são os nomes que o arquivo já usa ou o equivalente que ele expõe; se `findByLocalId` não existir no fake, ler o campo que o fake guarda — `written`/`rows` — e asseverar sobre ele.)

- [ ] **Step 2: Rodar**

Run: `cd backend/sinalacs_server && dart test test/unit/visit_sync_service_test.dart test/unit/visit_legacy_sync_test.dart`
Expected: passam (caracterização).

- [ ] **Step 3: Provar que podem falhar (mutação, depois restaurar)**

```bash
cd /home/rock/Documents/Dev/APPs/SinalACS/backend/sinalacs_server
cp lib/src/application/visits/visit_sync_service.dart /tmp/vss.bak
# Mutação: o legado passa a creditar o transportador.
sed -i 's/VisitAuthorship.legacyUnclaimed/VisitAuthorship.acs/' lib/src/application/visits/visit_sync_service.dart
dart test test/unit/visit_legacy_sync_test.dart 2>&1 | tail -3
cp /tmp/vss.bak lib/src/application/visits/visit_sync_service.dart && git diff --stat lib | wc -l
```
Expected: o teste novo (e o antigo de autoria) **falham** com a mutação; depois da restauração `git diff --stat` não lista nada (`0`). Registrar a saída. Repetir para o primeiro teste (mutação: remover a recusa de `localId` de outro agente em `_syncOne`); se `sed` não casar, anotar e usar uma edição manual equivalente.

- [ ] **Step 4: Commit**

```bash
git add backend/sinalacs_server/test/unit
git commit -m "test(visitas): prende que B nao reescreve visita de A e que a legada nao vira de B"
```

---

### Task 3: Opt-out de captura de tela só em debug (falha primeiro)

**Files:**
- Modify: `apps/acs/android/app/build.gradle.kts` (buildFeatures, buildConfigField, guard)
- Modify: `apps/acs/android/app/src/main/kotlin/br/com/prismrr/sinalacs/acs/MainActivity.kt:12-21`
- Modify: `apps/acs/test/secure_window_test.dart`
- Modify: `scripts/qa/acs_release_signing.sh` (cenário 6), `scripts/qa/acs_secure_window.sh` (modo `--captura`)

**Interfaces:**
- Produces: `BuildConfig.ALLOW_SCREEN_CAPTURE: Boolean` (`false` em todo build, exceto `debug` com `-Psinalacs.allowScreenCapture=true`); `MainActivity.onCreate` só aplica `FLAG_SECURE` quando ele é `false`; guard do Gradle que falha em `assembleRelease`/`bundleRelease`/`packageRelease` quando a propriedade vem.

- [ ] **Step 1: Escrever os testes que falham**

Em `apps/acs/test/secure_window_test.dart`, acrescentar (o arquivo lê `MainActivity.kt`; ler também o Gradle):

```dart
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();

  test('FLAG_SECURE só é dispensada pela constante de compilação ALLOW_SCREEN_CAPTURE', () {
    final inicio = fonte.indexOf('override fun onCreate');
    final fim = fonte.indexOf('override fun configureFlutterEngine');
    final corpo = fonte.substring(inicio, fim);
    // A aplicação da flag está condicionada à constante, e a constante não é
    // lida de nenhum outro lugar (nada de SharedPreferences, intent, menu).
    expect(corpo, matches(RegExp(r'if\s*\(\s*!BuildConfig\.ALLOW_SCREEN_CAPTURE\s*\)')));
    expect(fonte, isNot(contains('getSharedPreferences')));
    expect(fonte, isNot(contains('getIntent')));
    expect(fonte, isNot(contains('getBooleanExtra')));
  });

  test('o Gradle liga ALLOW_SCREEN_CAPTURE só no debug e barra a propriedade em release', () {
    expect(gradle, contains('buildConfig = true'));
    // Padrão false para todo build.
    expect(gradle, matches(RegExp(r'defaultConfig\s*\{[\s\S]*?ALLOW_SCREEN_CAPTURE",\s*"false"')));
    // Só o buildType debug lê a propriedade.
    expect(gradle, matches(RegExp(r'debug\s*\{[\s\S]*?licenca\("sinalacs\.allowScreenCapture"\)')));
    // E o release que a recebe falha.
    expect(gradle, contains('sinalacs.allowScreenCapture'));
    expect(gradle, contains('captura de tela'));
  });
```

- [ ] **Step 2: Ver falhar**

Run: `cd apps/acs && flutter test test/secure_window_test.dart`
Expected: os dois testes novos falham (`BuildConfig.ALLOW_SCREEN_CAPTURE` e `buildConfig = true` ainda não existem).

- [ ] **Step 3: Implementar**

`build.gradle.kts` — dentro de `android { ... }`, junto de `defaultConfig`:

```kotlin
    buildFeatures {
        // AGP 9 desliga a geração de BuildConfig por padrão; a captura de tela
        // do debug depende dela.
        buildConfig = true
    }
```
em `defaultConfig { ... }`:

```kotlin
        // Captura de tela: FECHADA em todo build. Só o buildType debug pode abri-la.
        buildConfigField("boolean", "ALLOW_SCREEN_CAPTURE", "false")
```
e no bloco `buildTypes { ... }` (criar o `debug` se não existir; o `release` já existe):

```kotlin
        debug {
            // Opt-out para QA, vídeo de demonstração e Firebase Test Lab: só aqui, só
            // com `-Psinalacs.allowScreenCapture=true` (o texto exato `true`). Release
            // e profile herdam o `false` do defaultConfig e não leem a propriedade.
            buildConfigField("boolean", "ALLOW_SCREEN_CAPTURE", licenca("sinalacs.allowScreenCapture").toString())
        }
```
No guard `gradle.taskGraph.whenReady` (depois dos dois guards de release existentes, antes do fim do bloco), acrescentar:

```kotlin
    if (buildaRelease && licenca("sinalacs.allowScreenCapture")) {
        throw GradleException(
            """
            |-Psinalacs.allowScreenCapture=true não vale em build de release: a janela do ACS
            |(que mostra nome e condições crônicas de pacientes) fica sem captura de tela
            |liberada SOMENTE em debug. Para gravar a demonstração, gere a build de debug:
            |  ./scripts/dev/run_acs.sh --build --captura
            """.trimMargin()
        )
    }
```
`MainActivity.kt` — trocar o `window.setFlags(...)` de `onCreate` por:

```kotlin
        // A lista da microárea mostra nome e condições crônicas. FLAG_SECURE
        // bloqueia captura de tela, gravação e a miniatura nos apps recentes, na
        // janela INTEIRA. A ÚNICA exceção é a constante de compilação abaixo, que
        // o Gradle só liga no buildType debug por `-Psinalacs.allowScreenCapture=true`
        // e recusa em release: nenhum menu, intent ou preferência a altera.
        if (!BuildConfig.ALLOW_SCREEN_CAPTURE) {
            window.setFlags(
                WindowManager.LayoutParams.FLAG_SECURE,
                WindowManager.LayoutParams.FLAG_SECURE,
            )
        }
```
(manter o comentário original sobre Área/Visita/seletor em vez de apagá-lo; o `BuildConfig` do pacote `br.com.prismrr.sinalacs.acs` é o gerado e não precisa de `import`.)

- [ ] **Step 4: Ver passar, e os testes antigos continuarem passando**

Run: `cd apps/acs && flutter test test/secure_window_test.dart test/android_manifest_test.dart`
Expected: passam. O teste antigo "DENTRO de onCreate" procura `window.setFlags(` e `FLAG_SECURE` no corpo de `onCreate`: continua verdadeiro com o `if`.

- [ ] **Step 5: Provar nos três builds (emulador `emulator-5554`)**

Debug **sem** a propriedade (o padrão): `FLAG_SECURE` presente.
```bash
./scripts/qa/acs_secure_window.sh --reinstalar
```
Expected: `OK — janela do ACS com FLAG_SECURE`.

Debug **com** a propriedade: a flag **ausente**. Acrescentar ao `acs_secure_window.sh` um argumento `--captura` (no `case` dos argumentos, `captura=1`), que passa `-Psinalacs.allowScreenCapture=true` ao `flutter build apk --debug` e inverte a asserção:

```bash
if [[ "$captura" -eq 1 ]]; then
  if grep -qw SECURE <<<"$flags"; then
    echo "erro: o build de debug com captura liberada ainda tem FLAG_SECURE: $flags" >&2
    exit 1
  fi
  echo "OK — debug com --captura: janela do ACS SEM FLAG_SECURE (só para demonstração)"
  exit 0
fi
```
(o ramo vai antes do `grep -qw SECURE` já existente, e o `flutter build` passa a receber `${captura:+-Psinalacs.allowScreenCapture=true}`).
```bash
./scripts/qa/acs_secure_window.sh --reinstalar --captura
```
Expected: `OK — debug com --captura: janela do ACS SEM FLAG_SECURE`.

Release: a propriedade é recusada. Em `scripts/qa/acs_release_signing.sh`, depois do cenário 5:

```bash
echo "== cenário 6: -Psinalacs.allowScreenCapture=true NÃO vale em release =="
if saida="$(construir -Psinalacs.allowDebugSigning=true -Psinalacs.allowDevClientKey=true -Psinalacs.allowScreenCapture=true 2>&1)"; then
  echo "erro: o release aceitou allowScreenCapture=true." >&2
  exit 1
fi
grep -q "captura de tela" <<<"$saida" || { echo "erro: a falha não explicou o motivo:" >&2; tail -n 15 <<<"$saida" >&2; exit 1; }
```
Run: `./scripts/qa/acs_release_signing.sh`
Expected: cenários 1–6 passam. Antes de implementar o guard, o cenário 6 deve falhar com "o release aceitou allowScreenCapture=true" (ver o RED rodando o script antes do Step 3, com o `build.gradle.kts` intacto).

Release **instalado**: a flag presente (o `FLAG_SECURE` de release é o ponto do plano). Com o APK que o cenário 2 deixa em `apps/acs/build/app/outputs/flutter-apk/app-release.apk` (assinado com a chave de debug de propósito), conferir no emulador, **sem** apagar nada que importe (o app de desenvolvimento é sacrificável; usar `--reinstalar` como nos outros scripts):
```bash
export PATH="$PATH:$HOME/Android/Sdk/platform-tools"
adb -s emulator-5554 uninstall br.com.prismrr.sinalacs.acs >/dev/null 2>&1 || true
adb -s emulator-5554 install -r apps/acs/build/app/outputs/flutter-apk/app-release.apk
adb -s emulator-5554 shell monkey -p br.com.prismrr.sinalacs.acs -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
adb -s emulator-5554 shell dumpsys window windows | awk '/^  Window #/ { d = index($0,"br.com.prismrr.sinalacs.acs/")>0 } d && /^ +fl=/ && !a { print; a=1 }'
```
Expected: a linha `fl=` contém `SECURE`. (Se o último `flutter build` do script foi o do cenário 6 e falhou, reconstruir o release antes: `cd apps/acs && flutter build apk --release --dart-define=SINALACS_MQTT_PASSWORD=$MQTT_ACS_PASSWORD -Psinalacs.allowDebugSigning=true -Psinalacs.allowDevClientKey=true`.)

- [ ] **Step 6: Commit**

```bash
git add apps/acs/android/app/build.gradle.kts apps/acs/android/app/src/main/kotlin apps/acs/test/secure_window_test.dart scripts/qa/acs_release_signing.sh scripts/qa/acs_secure_window.sh
git commit -m "feat(acs): captura de tela liberada so em debug, por constante de compilacao; release a recusa"
```

---

### Task 4: Caminho de uso para QA e vídeo (`--captura`) e documentação da captura

**Files:**
- Modify: `scripts/dev/run_acs.sh` (flag `--captura`)
- Modify: `docs/telas-acs.md:59`, `video/capture/lib.sh` (cabeçalho/comentário), `PROGRESS.md` (linha ~612 e os "Minors adiados" T1)

**Interfaces:**
- Consumes: `-Psinalacs.allowScreenCapture=true` (Task 3).
- Produces: `./scripts/dev/run_acs.sh [--build] --captura` → APK/execução de debug com captura liberada, e um aviso visível.

- [ ] **Step 1: Teste que falha** — `scripts/dev/run_acs_captura_test.sh` (hermético: usa um `flutter` falso no `PATH` que só grava os argumentos recebidos):

```bash
#!/usr/bin/env bash
# `run_acs.sh --captura` só acrescenta a propriedade do Gradle ao build de debug.
set -euo pipefail
aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
cat >"$tmp/bin/flutter" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" >"$tmp/args"
exit 0
EOF
chmod +x "$tmp/bin/flutter"
falha() { echo "FALHOU: $*" >&2; exit 1; }

# O wrapper exige .env e CAs; o teste só confere a montagem dos argumentos.
PATH="$tmp/bin:$PATH" RUN_ACS_SKIP_ENV_CHECK=1 "$aqui/run_acs.sh" --build --captura --skip-ca >"$tmp/saida" 2>&1 || true
grep -qx -- '-Psinalacs.allowScreenCapture=true' "$tmp/args" || falha "a propriedade não chegou ao flutter: $(cat "$tmp/args" 2>/dev/null)"
grep -q 'captura de tela' "$tmp/saida" || falha "faltou o aviso de que o APK é só para demonstração"

PATH="$tmp/bin:$PATH" RUN_ACS_SKIP_ENV_CHECK=1 "$aqui/run_acs.sh" --build --skip-ca >/dev/null 2>&1 || true
grep -q 'allowScreenCapture' "$tmp/args" && falha "sem --captura a propriedade não pode ir"
echo "OK — run_acs.sh --captura só acrescenta a propriedade quando pedido"
```
Run: `chmod +x scripts/dev/run_acs_captura_test.sh && ./scripts/dev/run_acs_captura_test.sh`
Expected: `FALHOU: a propriedade não chegou ao flutter` (o wrapper ainda não conhece `--captura`). **Antes de escrever o teste, ler `run_acs.sh` por inteiro:** ele exige `.env` e o `sync_dev_ca.sh`; `RUN_ACS_SKIP_ENV_CHECK` **não existe** hoje — se o wrapper abortar antes de chamar o `flutter`, em vez de inventar essa variável no script de produção, montar no teste um `.env` e uma `apps/acs/assets/certs/` falsos num diretório temporário e apontar o wrapper para ele (`SYNC_DEV_CA_ROOT` já existe para o `sync_dev_ca.sh`; para o resto, copiar o padrão de `scripts/dev/sync_dev_ca_test.sh`). Registrar qual caminho foi usado.

- [ ] **Step 2: Implementar** — em `run_acs.sh`, no `case` dos argumentos: `--captura) captura=1; shift ;;`; e onde monta `flutter_args`: `[[ "${captura:-0}" -eq 1 ]] && flutter_args+=(-Psinalacs.allowScreenCapture=true) && echo 'AVISO: build de DEBUG com captura de tela liberada (FLAG_SECURE desligada). Só para QA e demonstração, com dados sintéticos; nunca instalar em aparelho com paciente real.' >&2`. Acrescentar `# ./scripts/dev/run_acs.sh --build --captura` ao cabeçalho de uso.

- [ ] **Step 3: Ver passar**

Run: `./scripts/dev/run_acs_captura_test.sh && bash -n scripts/dev/run_acs.sh`
Expected: `OK — run_acs.sh --captura ...`. Em seguida o fluxo real: `./scripts/dev/run_acs.sh --build --captura` imprime o aviso e gera o APK; instalar no emulador e `adb exec-out screencap -p > /tmp/claude-1000/ok.png` deve devolver um arquivo **não vazio** (antes, com `FLAG_SECURE`, saía preto/vazio). Abrir a imagem só para conferir que não é preta e **apagá-la** (dados sintéticos do seed, mas não a deixe no repositório).

- [ ] **Step 4: Documentar**

- `docs/telas-acs.md:59`: trocar "para regenerar capturas é preciso retirar a flag temporariamente da `MainActivity`" por "gere o APK com `./scripts/dev/run_acs.sh --build --captura` (só debug; o release recusa a propriedade)".
- `video/capture/lib.sh`: no cabeçalho, uma linha dizendo que o app do ACS precisa estar instalado a partir de uma build `--captura`, e um erro claro quando `screencap` volta vazio (em vez de gravar vídeo preto em silêncio) — **só se** a leitura do arquivo mostrar que ele já tem um ponto único onde a captura é feita; senão, só o comentário.
- `PROGRESS.md`: substituir a linha ~612 ("um build de debug com opt-out documentado NÃO foi adicionado (decisão pendente)") pelo desfecho; e o `T1` de "Minors adiados".

- [ ] **Step 5: Commit**

```bash
git add scripts/dev/run_acs.sh scripts/dev/run_acs_captura_test.sh docs/telas-acs.md video/capture/lib.sh PROGRESS.md
git commit -m "feat(dev): run_acs.sh --captura gera o APK de debug com captura de tela liberada"
```

---

### Task 5: Fechar a documentação e o grafo

**Files:**
- Modify: `PROGRESS.md` (seção da fila por dono: o veredito do ponto 1), `CLAUDE.md` e `apps/CLAUDE.md` (a frase de `FLAG_SECURE`), `spec/lgpd_design.md` (nota sobre captura em debug), `.github/workflows/ci.yml` (adicionar `run_acs_captura_test.sh` ao passo "Testes dos scripts de CI", se o teste não depender de Docker nem de emulador)

- [ ] **Step 1: Registrar o veredito do ponto 1** em `PROGRESS.md`, com o resultado literal da Task 1 e da Task 2: o servidor nunca credita o transportador (mutação vista falhar), o JWT de B nunca carrega fila de A (testes citados pelo nome), e a única exceção, as linhas legadas, sobe sem autoria e fica registrada como **decisão aceita** com o motivo medido (nenhuma release publicada), com a condição de reabrir se uma release existir.
- [ ] **Step 2: Atualizar** as frases de `FLAG_SECURE` em `CLAUDE.md` e `apps/CLAUDE.md` ("`FLAG_SECURE` on the ACS window" → "…on every build; only a debug build made with `--captura` opens it, by a compile-time constant that release refuses").
- [ ] **Step 3: CI** — se `run_acs_captura_test.sh` é hermético, acrescentá-lo à lista do passo "Testes dos scripts de CI" de `workflow-lint` e rodar `./scripts/qa/ci_invariants.sh` (a lista de jobs não muda).
- [ ] **Step 4: Verificações finais**

```bash
cd apps/acs && flutter analyze && flutter test
cd ../../backend/sinalacs_server && dart test test/unit
cd ../.. && ./scripts/dev/run_acs_captura_test.sh && ./scripts/qa/ci_invariants.sh && ./scripts/qa/check_documentation_links.sh && python3 scripts/qa/contagem_validation_report.py && graphify update .
```
Expected: tudo verde; se `contagem_validation_report.py` apontar divergência, atualizar o número citado (os testes novos mudam o total).
- [ ] **Step 5: Commit**

```bash
git add PROGRESS.md CLAUDE.md apps/CLAUDE.md spec/lgpd_design.md .github/workflows/ci.yml
git commit -m "docs: veredito da autoria das visitas e da captura de tela em debug"
```

## Self-Review

- **Cobertura:** ponto 1 → Tasks 1 (medir), 2 (prender) e a decisão da linha legada; ponto 2 → Tasks 3 (constante, Gradle, guard, provas nos três builds), 4 (caminho de uso e docs) e 5 (fechamento). A proposta "Background Worker com client credentials" está em "Fora do escopo" com o motivo (o token de envio por dono já faz o papel; WorkManager exige decisão fora da stack).
- **Placeholders:** os nomes de fakes/helpers dos testes da Task 2 e a necessidade de ler `run_acs.sh` antes de escrever o teste da Task 4 estão marcados explicitamente como leitura obrigatória com arquivo e linha; nenhum passo diz "adicionar tratamento apropriado".
- **Consistência de tipos:** `BuildConfig.ALLOW_SCREEN_CAPTURE`, `licenca("sinalacs.allowScreenCapture")`, `--captura` e a propriedade `-Psinalacs.allowScreenCapture=true` aparecem com os mesmos nomes em todas as tasks.
