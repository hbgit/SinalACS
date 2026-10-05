# Tema AppCompat e prompt biométrico em Android 8.1 ou anterior (API 24–27) — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Garantir que o `BiometricPrompt` do cofre do refresh token (`KeystoreVault.kt`) abra e devolva resultado em API 24–27, provando em emulador, e fechar o item (f) de `PROGRESS.md`.

**Architecture:** Primeiro **reproduzir** (a hipótese "quebra" vem do README do `local_auth_android` e ainda não foi observada): instalar uma imagem API 27 e rodar o fluxo de partida a frio. Só então trocar o pai dos temas `LaunchTheme`/`NormalTheme` de `@android:style/Theme.*.NoTitleBar` para `Theme.AppCompat.*.NoActionBar` (mantendo o fundo/splash atuais), declarar `androidx.appcompat` explicitamente e cobrir a regressão com um teste que lê os `styles.xml`.

**Tech Stack:** Kotlin (`MainActivity : FlutterFragmentActivity`, `KeystoreVault.kt`), `androidx.biometric:1.1.0`, Android SDK `cmdline-tools/latest`, emulador, bash (`scripts/qa`), `flutter_test`.

**Spec:** `PROGRESS.md` §"Refresh token rotativo e desbloqueio biométrico do ACS" (Não provado, item Aberto (f), linha ~747–748), §"Biometria amarrada ao Keystore" (a3, linha ~759); `docs/superpowers/plans/2026-10-05-biometria-amarrada-ao-keystore.md`.

Contexto levantado com `graphify query`/`explain`: `BiometricPrompt` é usado só em `KeystoreVault.unseal()` (`KeystoreVault.kt:264`, comunidade `KeystoreVault`); `MainActivity` já é `FlutterFragmentActivity`, então o requisito de `FragmentActivity` está atendido — falta só o tema. Temas atuais: `apps/acs/android/app/src/main/res/values/styles.xml` (pai `Theme.Light.NoTitleBar`) e `values-night/styles.xml` (pai `Theme.Black.NoTitleBar`).

## Global Constraints

- `minSdk 24`, `compileSdk 36` (`apps/acs/android/app/build.gradle.kts`). A solução deve degradar, não quebrar, em API 24–29.
- `androidx.biometric` fica em `1.1.0` (a 1.2.0 é alpha); sem framework novo (`spec/stack.md`).
- Nunca registrar token, chave ou mensagem de exceção do Keystore em log (LGPD-RF09). Falha fechada: erro do prompt nunca devolve o token.
- Splash (`@drawable/launch_background`), `FLAG_SECURE` e o fundo escuro/claro por `values-night` não mudam de aparência.
- Textos de UI em português; commits sem atribuição de IA (regra do repositório).
- Rodar `graphify update .` depois de modificar código.

## Review Focus

- API 24–27 **sem** biometria cadastrada nem bloqueio de tela: o app deve cair em login completo (`unavailable`), sem travar nem fechar.
- API 24–27 com prompt aberto e o app indo para o fundo (rotação, `HOME`): sem prompt órfão nem espera eterna no Dart (relacionado a (a5)).
- Tema AppCompat sobre widgets do Flutter: sem barra de ação, sem faixa branca no splash, sem mudança de cor da barra de status em modo escuro.
- Dispositivo API 28+ (prompt do sistema) e API 30+ já provados: o tema novo não pode regredir `acs_keystore_bound_e2e.sh`.
- Imagem com `google_apis` vs AOSP: o prompt de digital em API ≤ 27 usa o diálogo do `androidx.biometric`; um falso negativo por falta de Play Services não pode ser lido como "tema quebrado".

---

### Task 1: Obter imagem API 27 e reproduzir o defeito

**Files:**
- Create: `scripts/qa/acs_api27_avd.sh`

**Interfaces:**
- Produces: AVD `sinalacs_api27` (x86_64) que as Tasks 2–4 usam; `emulator-<porta>` visível em `adb devices`. O script aceita `--api <24..27>` (padrão 27) e `--criar`/`--iniciar`.

Só há `android-36/google_apis_playstore` instalado e `sdkmanager` fora do `PATH` (está em `~/Android/Sdk/cmdline-tools/latest/bin`). A imagem **não está disponível por padrão**, mas é baixável.

- [ ] **Step 1: Escrever o script**

```bash
#!/usr/bin/env bash
#
# Cria/inicia um AVD em API 24–27 para provar o BiometricPrompt abaixo do
# prompt do sistema (API 28+). Usa google_apis (Play Services, como a CI).
#
#   ./scripts/qa/acs_api27_avd.sh [--api 27] [--criar] [--iniciar]
set -euo pipefail

sdk="$HOME/Android/Sdk"
export PATH="$PATH:$sdk/cmdline-tools/latest/bin:$sdk/emulator:$sdk/platform-tools"

api=27; criar=0; iniciar=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --api) api="${2:?--api exige 24..27}"; shift 2 ;;
    --criar) criar=1; shift ;;
    --iniciar) iniciar=1; shift ;;
    *) echo "uso: $0 [--api 24..27] [--criar] [--iniciar]" >&2; exit 2 ;;
  esac
done
[[ "$api" =~ ^2[4-7]$ ]] || { echo "API deve ser 24..27" >&2; exit 2; }

avd="sinalacs_api${api}"
img="system-images;android-${api};google_apis;x86_64"

if [[ $criar -eq 1 ]]; then
  yes | sdkmanager --licenses >/dev/null || true
  sdkmanager "$img"
  echo no | avdmanager create avd -n "$avd" -k "$img" --force
fi
if [[ $iniciar -eq 1 ]]; then
  # Porta fixa 5556 para não colidir com o emulador-5554 dos outros scripts.
  nohup emulator -avd "$avd" -port 5556 -no-snapshot -no-audio >/dev/null 2>&1 &
  adb -s emulator-5556 wait-for-device
  until [[ "$(adb -s emulator-5556 shell getprop sys.boot_completed | tr -d '\r')" == 1 ]]; do sleep 2; done
  echo "emulator-5556 pronto (API $api)"
fi
```

- [ ] **Step 2: Criar e iniciar**

Run: `chmod +x scripts/qa/acs_api27_avd.sh && ./scripts/qa/acs_api27_avd.sh --api 27 --criar --iniciar`
Expected: `emulator-5556 pronto (API 27)`. Se o download falhar por rede/KVM, registre o erro e pare: sem imagem não há prova, e o plano **não** declara o item fechado.

- [ ] **Step 3: Reproduzir com o tema atual (sem editar nada)**

```bash
export PATH="$PATH:$HOME/Android/Sdk/platform-tools:$HOME/flutter/bin"
adb -s emulator-5556 shell locksettings set-pin 1111
adb -s emulator-5556 shell am start -a android.settings.SECURITY_SETTINGS
# cadastra digital 1 pela UI e toca o sensor com: adb -s emulator-5556 emu finger touch 1
cd apps/acs && flutter run -d emulator-5556 --dart-define-from-file=... 
```

Use as mesmas `--dart-define` do `scripts/qa/acs_keystore_bound_e2e.sh` (ler o script; ele fixa `dev=emulator-5554`, então copie só a montagem do build). Faça login (ACS-001), `adb shell input keyevent KEYCODE_HOME`, espere o bloqueio de 30 s ou force-stop e reabra.
Expected (hipótese): `adb logcat -d | grep -iE "AppCompat|IllegalStateException|BiometricPrompt|FingerprintDialog"` mostra `You need to use a Theme.AppCompat theme` **ou** o prompt abre normalmente.
**Anote o resultado literal** em `PROGRESS.md` (Task 4); se o prompt abrir e devolver o token, a hipótese é falsa: pule a Task 3 e vá direto à Task 4, registrando "provado sem mudança" (o teste da Task 2 ainda vale como guarda).

- [ ] **Step 4: Commit**

```bash
git add scripts/qa/acs_api27_avd.sh
git commit -m "chore(qa): script para criar AVD API 24-27 e provar o BiometricPrompt"
```

---

### Task 2: Teste que trava o tema AppCompat (falha primeiro)

**Files:**
- Create: `apps/acs/test/android_theme_test.dart`

**Interfaces:**
- Consumes: os arquivos `apps/acs/android/app/src/main/res/values/styles.xml` e `values-night/styles.xml`.
- Produces: guarda de regressão que roda no job `acs-app` (CI).

- [ ] **Step 1: Escrever o teste**

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// BiometricPrompt abaixo da API 28 desenha o próprio diálogo e exige um tema
// AppCompat na Activity (README do local_auth_android: "Android 8.1 or
// earlier"). Esta guarda impede que alguém volte aos temas @android:style.
void main() {
  const pastas = ['values', 'values-night'];
  for (final pasta in pastas) {
    for (final tema in ['LaunchTheme', 'NormalTheme']) {
      test('$pasta/$tema herda de AppCompat', () {
        final xml = File('android/app/src/main/res/$pasta/styles.xml')
            .readAsStringSync();
        final m = RegExp('<style name="$tema" parent="([^"]+)"').firstMatch(xml);
        expect(m, isNotNull, reason: '$tema ausente em $pasta/styles.xml');
        expect(m!.group(1), contains('Theme.AppCompat'));
        expect(m.group(1), contains('NoActionBar'));
      });
    }
  }
}
```

- [ ] **Step 2: Ver falhar**

Run: `cd apps/acs && flutter test test/android_theme_test.dart`
Expected: 4 falhas (`Expected: contains 'Theme.AppCompat'  Actual: '@android:style/Theme.Light.NoTitleBar'`).

- [ ] **Step 3: Commit do teste vermelho fica junto da Task 3** (não commitar teste quebrado sozinho).

---

### Task 3: Migrar os temas para AppCompat

**Files:**
- Modify: `apps/acs/android/app/src/main/res/values/styles.xml`
- Modify: `apps/acs/android/app/src/main/res/values-night/styles.xml`
- Modify: `apps/acs/android/app/build.gradle.kts:96-99`

**Interfaces:**
- Consumes: `android_theme_test.dart` da Task 2.
- Produces: `LaunchTheme`/`NormalTheme` AppCompat; o `AndroidManifest.xml` não muda (já referencia `@style/LaunchTheme` e `@style/NormalTheme`).

- [ ] **Step 1: `values/styles.xml`** — trocar os dois pais:

```xml
<style name="LaunchTheme" parent="Theme.AppCompat.Light.NoActionBar">
    <item name="android:windowBackground">@drawable/launch_background</item>
</style>
<style name="NormalTheme" parent="Theme.AppCompat.Light.NoActionBar">
    <item name="android:windowBackground">?android:colorBackground</item>
</style>
```

- [ ] **Step 2: `values-night/styles.xml`** — mesma troca com `Theme.AppCompat.NoActionBar` (escuro). Manter os comentários do template.

- [ ] **Step 3: Declarar a dependência** (hoje só chega transitiva por `androidx.biometric`; explícita evita sumir com um bump):

```kotlin
dependencies {
    implementation("androidx.biometric:biometric:1.1.0")
    // Tema AppCompat exigido pelo diálogo do BiometricPrompt em API < 28.
    implementation("androidx.appcompat:appcompat:1.7.0")
}
```

- [ ] **Step 4: Teste verde + build**

Run: `cd apps/acs && flutter test test/android_theme_test.dart && flutter build apk --debug --dart-define-from-file=<mesmo arquivo do e2e>`
Expected: 4 testes passam; build ok. Se o Gradle reclamar de versão do appcompat, usar a que `./gradlew :app:dependencies | grep appcompat` já resolve.

- [ ] **Step 5: Provar no API 27**

Repetir o passo 3 da Task 1 em `emulator-5556`.
Expected: prompt de digital (diálogo do `androidx.biometric`) aparece; `adb -s emulator-5556 emu finger touch 1` libera e o app volta logado sem pedir senha; `emu finger touch 2` mantém o prompt aberto; "Cancelar" resulta em tela de bloqueio com "Tentar de novo" (`cancelled`). Capture `adb logcat -d | grep -iE "AppCompat|IllegalState"` vazio.

- [ ] **Step 6: Regressão em API 36**

Run: `./scripts/qa/acs_keystore_bound_e2e.sh --pin 1111 --preparar` (emulador 5554, ver cabeçalho do script — aborta se o app já estiver instalado).
Expected: mesma saída verde de antes; sem faixa branca/barra de ação (screenshot com `adb exec-out screencap`, sem dados reais).

- [ ] **Step 7: Commit**

```bash
git add apps/acs/test/android_theme_test.dart apps/acs/android/app/src/main/res apps/acs/android/app/build.gradle.kts
git commit -m "fix(acs): tema AppCompat para o BiometricPrompt em API 24-27"
```

---

### Task 4: Casos de borda em API ≤ 27 e documentação

**Files:**
- Modify: `PROGRESS.md` (linhas ~747, 748 item (f), 759 (a3), 770)
- Modify: `CLAUDE.md` (parágrafo "Still missing": remover "the Android theme/AppCompat check on Android ≤ 8.1 (API 24–27)" se provado)
- Modify: `scripts/qa/acs_keystore_bound_e2e.sh` (somente se aceitar `--dev emulator-5556`; hoje `dev` é fixo)

- [ ] **Step 1: Sem biometria nem PIN (API 27)** — `adb -s emulator-5556 shell locksettings clear --old 1111`, reabrir o app a frio.
Expected: login completo (item (a4)), sem crash. Anotar.

- [ ] **Step 2: Prompt aberto e `HOME`** — abrir o prompt, `KEYCODE_HOME`, voltar.
Expected: sem travar; se o prompt ficar órfão, registrar como o (a5) já listado, não corrigir aqui.

- [ ] **Step 3: Repetir em API 24** (`--api 24 --criar --iniciar`) — a menor `minSdk`. Se falhar só na 24, abrir o item à parte.

- [ ] **Step 4: Atualizar `PROGRESS.md`** com o resultado **literal** de cada passo (API testada, imagem `google_apis`, o que foi e não foi exercitado). Fechar (f) e reescrever (a3) para "API 24–27 provada; 28–29 sem prova". Manter "aparelho físico" e "iOS" como não provados. Rodar `./scripts/qa/check_documentation_links.sh` e `python3 scripts/qa/contagem_validation_report.py` se o número de testes citado mudar (+4 testes).

- [ ] **Step 5: Grafo**

Run: `graphify update .`
Expected: sem erro; `graphify query "BiometricPrompt theme AppCompat"` passa a listar `styles.xml`.

- [ ] **Step 6: Commit**

```bash
git add PROGRESS.md CLAUDE.md scripts/qa
git commit -m "docs(acs): prova do prompt biométrico em API 24-27; fecha o item (f)"
```

## Self-Review

- Cobertura: "não há imagem" → Task 1 (imagem baixável via `sdkmanager`); "tema não é AppCompat" → Tasks 2–3; prova e docs → Task 4. Limite honesto: se o download da imagem falhar, o item permanece aberto.
- Placeholders: o único valor a copiar do ambiente é o `--dart-define-from-file`, que vem do `acs_keystore_bound_e2e.sh` existente (Task 1, passo 3 e Task 3, passo 4).
- Consistência: AVD `sinalacs_api<N>`, porta 5556, `android_theme_test.dart` usados de forma igual nas tasks.
