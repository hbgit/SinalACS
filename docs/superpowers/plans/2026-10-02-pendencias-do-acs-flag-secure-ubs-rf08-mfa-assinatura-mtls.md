# Pendências do ACS: FLAG_SECURE, assinatura, botão da UBS, RF08, MFA e mTLS — Plano de Implementação

> **Para agentes:** SUB-SKILL OBRIGATÓRIA: use superpowers:subagent-driven-development (recomendado) ou superpowers:executing-plans para executar este plano tarefa a tarefa. Os passos usam checkbox (`- [ ]`).

**Goal:** Fechar as seis pendências que o `PROGRESS.md` deixou abertas no app do ACS e no broker: bloquear captura de tela, assinar o release com chave própria, ligar para a UBS, persistir a microárea offline (RF08), exigir MFA (TOTP) no login institucional e exigir certificado de cliente no broker (mTLS).

**Architecture:** Seis frentes independentes, uma ou duas tarefas cada, na ordem do menor para o maior risco: (1) `FLAG_SECURE` na `MainActivity`; (2) `signingConfig` de release lido de `key.properties`/ambiente, com a build falhando sem chave; (3) contato da UBS como coluna nova em `ubs` mais um endpoint `ubs.myContact` e o botão passando a discar; (4) cache da microárea na mesma base SQLCipher, com dono, validade e apagamento; (5)(6) TOTP RFC 6238 no `loginInstitutional` (backend, depois app); (7)(8) o Mosquitto passa a exigir certificado de cliente, o backend e o ACS passam a apresentá-lo. Cada tarefa tem um teste que falha antes e termina com prova no `emulator-5554` quando há o que provar nele.

**Tech Stack:** Kotlin (Android), Gradle Kotlin DSL, Flutter/Dart, Serverpod 3.4.13 (`serverpod generate`/`create-migration`), `sqflite_sqlcipher`, `crypto` (HMAC-SHA1), `qr_flutter`, Mosquitto 2 + OpenSSL, `integration_test`, `scripts/qa/*.sh`.

**Spec:** `spec/PRD_system.md` (RF07, RF08, RF13, RNF04, RNF06), `spec/lgpd_design.md` (LGPD-RT06 §Sessões e autenticação, §5.1 chave local, §5.6 minimização), `docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md` (§4, §5), `spec/lgpd_data_audit.md`, `apps/CLAUDE.md`, `backend/CLAUDE.md`, `PROGRESS.md` (itens "Continua aberto" de 2026-10-02).

## Decisões tomadas neste plano

Cada uma é reversível; a coluna "se errada" diz o custo.

| # | Decisão | Se errada |
|---|---|---|
| D1 | `FLAG_SECURE` na **janela inteira** do ACS, não só na lista da microárea. A lista aparece em Área, Visita e no seletor; proteger tela por tela deixaria uma sem. Efeito colateral aceito: `adb screencap` e gravação de tela do ACS saem pretos. | Remover duas linhas da `MainActivity`. |
| D2 | Chave de release lida de `apps/acs/android/key.properties` (já no `.gitignore`) **ou** de variáveis `SINALACS_KEYSTORE_*`. Sem chave, `assembleRelease` **falha**; assinar com a de debug exige `-Psinalacs.allowDebugSigning=true`. O plano **não cria** keystore real nem segredo de CI. | Apagar o guard. |
| D3 | O telefone da UBS é a coluna **nullable** `ubs.contactPhone`, entregue ao ACS por `ubs.myContact`. Sem telefone, o botão avisa e não liga. Quem cadastra o número é o backoffice, que ainda é mock: hoje vale a seed. | Coluna e endpoint são aditivos. |
| D4 | O cache de RF08 guarda **só o que a tela de visita já mostra** (nome, `isChronic`, condições) na base SQLCipher; validade de **72 h**; chaveado por `userId\|microAreaId`; apagado quando o dono muda ou a validade vence; **só entra no lugar de uma falha recuperável de rede**, nunca de uma recusa do servidor. | Mudar `maxAge`; ou apagar a tabela v6. |
| D5 | MFA = **TOTP RFC 6238** (SHA-1, 6 dígitos, 30 s, janela ±1). O segredo é cifrado com a mesma chave AES-256-GCM dos dados clínicos. A ativação **não usa token**: exige matrícula + senha + um código válido. `REQUIRE_ACS_MFA` é `false` em `development` e `true` fora dele. Sem MFA em produção, o ACS é obrigado a ativar antes de entrar. | Exigir só em produção já é o padrão; trocar o default. |
| D6 | Refresh token **continua fora** (a pendência era "MFA e refresh token"; o pedido foi só MFA). Redefinição de MFA por coordenador também fica fora: hoje se faz zerando as colunas no banco. | Plano à parte. |
| D7 | mTLS **mantém a senha MQTT**: `require_certificate true` sem `use_identity_as_username`. Trocar a senha pela identidade do certificado derrubaria o guard do Gradle, `BackendConfig.mqttPasswordMissing`, os scripts de dev e o CI. Fica cert **e** senha. | Passar a `use_identity_as_username` é plano à parte. |
| D8 | O certificado de cliente do ACS vem de **asset de desenvolvimento** (`assets/certs/acs_client.*`, gitignorado, copiado por `sync_dev_ca.sh`). A chave privada no APK serve só ao dev. Um release com ela dentro **falha** a build. O provisionamento por aparelho em produção (CSR no cadastro, chave no Keystore) **não** entra: o mTLS fica entregue na stack local e **aberto** para produção. | Dizer isso no `PROGRESS.md`; não fingir fechamento. |

## Estado verificado em 2026-10-02

Medido ou lido nesta sessão:

- ACS: `flutter analyze` limpo, `flutter test` com **220** testes passando; `emulator-5554` no ar.
- `MainActivity.kt` do ACS é `class MainActivity : FlutterActivity()`, sem `FLAG_SECURE`.
- `build.gradle.kts`: `buildTypes.release` assina com `signingConfigs.getByName("debug")` (comentário `TODO`); `android/.gitignore` já ignora `key.properties`, `*.jks`, `*.keystore`.
- `EscalationScreen` (`app.dart` ~1936): "Encaminhar para UBS Central" só mostra `Encaminhamento será integrado à UBS.`; `ubs` não tem coluna de contato; o `Acs` tem `ubsId`.
- RF08: `patients.listMicroArea` é chamada **ao vivo** em dois pontos (`_loadMicroAreaPatients`, painel; `_loadPatients`, tela de visita). Falha vira `BackendFailure` com `isRecoverable`; recusa de sessão vem com `isRecoverable: false`. A base local é `sinalacs_acs.db`, `schemaVersion = 5`, com `offline_visits` e `sync_cursor`.
- MFA: `InstitutionalAuthService.login` (`institutional_auth_service.dart`) verifica Argon2id, bloqueia em 5 falhas por 15 min, devolve a mesma mensagem para matrícula inexistente e senha errada; `user_credentials` não tem coluna de MFA; `HealthDataCipher.encrypt/decrypt` cifram `String`.
- mTLS: `mosquitto.conf` tem `allow_anonymous false` + `password_file` + `acl_file`, **sem** `require_certificate`; `init.sh` gera só o certificado do servidor; o app (`mqtt_secure_client.dart:290`) e o backend (`mqtt_alert_dispatcher.dart:61`) só confiam na CA, não apresentam certificado.

## Fora deste plano

Refresh token; redefinição de MFA por coordenador; assinatura de release dos apps `patient` e `admin`; segredos de assinatura no CI; cadastro do telefone da UBS pelo backoffice; provisionamento de certificado por aparelho em produção; iOS (`apps/acs/ios/` não existe).

## Global Constraints

- Português em comentários, mensagens de commit e texto de UI, como o resto do repositório.
- Commits **sem** atribuição de IA: nenhuma linha "Co-Authored-By", nenhuma "Generated with Claude Code" (regra do `CLAUDE.md` do projeto, que prevalece sobre o lembrete de atribuição da sessão). Tudo na branch `fix/app_acs`, sem push, merge nem PR.
- Nada de dado real de paciente em teste, log ou captura; só fixtures sintéticas. Segredo nunca em `argv` de `docker`/`gradle` quando houver alternativa (variável de ambiente).
- Migração do banco do servidor: só aditiva (coluna nullable ou tabela nova). Depois de mexer em `.spy.yaml` ou endpoint: `serverpod generate` e `serverpod create-migration` em `backend/sinalacs_server`.
- Migração da base local do ACS: só aditiva (`CREATE TABLE IF NOT EXISTS`), e `EncryptedLocalDatabase.schemaVersion` sobe junto com `_upgrade`.
- Triagem determinística e a semântica de retry/conflito/rejeição de `OfflineVisitQueue` não mudam. RNF06: o território vem sempre do token.
- Os scripts `acs_full_e2e.sh` e `patient_full_e2e.sh` derrubam a stack de desenvolvimento: rodar `docker compose up -d` depois. Nenhum script apaga um app já instalado sem `--reinstalar`.
- Ambiente de todos os comandos: `export PATH="$PATH:$HOME/Android/Sdk/platform-tools:$HOME/flutter/bin:$HOME/.pub-cache/bin"`; raiz `/home/rock/Documents/Dev/APPs/SinalACS`.
- Cor clínica usada como texto passa pelo token `*OnSurface` (`apps/CLAUDE.md`); este plano não adiciona cor.

## Review Focus

1. **Código TOTP reaproveitado dentro da mesma janela de 30 s (replay):** deve ser recusado. → Task 5, teste `recusa o mesmo código usado duas vezes`.
2. **Código TOTP errado depois de senha certa:** conta como tentativa, tranca no 5º erro como a senha, e **não** consome o passo. → Task 5, testes `código errado conta tentativa e tranca` e `código errado não consome o passo`.
3. **Cache da microárea servido a outro usuário/outra microárea, ou depois de 72 h:** nunca. → Task 4, testes `outro dono apaga e não serve` e `vencido não serve e é apagado`; e recusa do servidor nunca cai no cache.
4. **Broker aceitando cliente sem certificado ou com certificado de outra CA:** deve recusar, e a senha continua exigida. → Task 7, script `mtls_invariants.sh` (quatro casos).
5. **Release saindo com chave de debug ou com a chave privada de desenvolvimento dentro:** a build deve falhar. → Task 2 (sem chave) e Task 8 (chave de dev no asset).

---

### Task 1: Janela do ACS com `FLAG_SECURE`

**Files:**
- Modify: `apps/acs/android/app/src/main/kotlin/br/com/prismrr/sinalacs/acs/MainActivity.kt`
- Create: `apps/acs/test/secure_window_test.dart`
- Create: `scripts/qa/acs_secure_window.sh`
- Modify: `spec/lgpd_design.md` (fim da §5.1), `apps/CLAUDE.md`

**Interfaces:** Consumes: —. Produces: nada que outra task use.

- [ ] **Step 1: Escrever o teste de fonte que falha**

Criar `apps/acs/test/secure_window_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A lista da microárea mostra nome e condições crônicas (LGPD §5.6). Sem
/// `FLAG_SECURE`, o sistema deixa a tela ser capturada, gravada e reduzida a
/// miniatura nos "apps recentes" — dado de saúde fora do controle do app.
/// Este teste lê a `MainActivity` porque `flutter test` não tem janela
/// Android; a prova na janela de verdade é `scripts/qa/acs_secure_window.sh`.
void main() {
  final fonte = File(
    'android/app/src/main/kotlin/br/com/prismrr/sinalacs/acs/MainActivity.kt',
  ).readAsStringSync();

  test('a janela do ACS é FLAG_SECURE (sem captura, gravação nem miniatura)', () {
    expect(fonte, contains('override fun onCreate'));
    expect(fonte, contains('WindowManager.LayoutParams.FLAG_SECURE'));
    expect(fonte, contains('window.setFlags('));
  });
}
```

- [ ] **Step 2: Escrever o verificador no emulador**

Criar `scripts/qa/acs_secure_window.sh` e `chmod +x`:

```bash
#!/usr/bin/env bash
#
# A janela do app do ACS tem FLAG_SECURE no emulador-5554 (sem captura de tela,
# gravação nem miniatura nos recentes). A prova é a flag da janela segundo o
# WindowManager (`dumpsys window windows`, linha `fl=`), não a leitura do código.
#
#   ./scripts/qa/acs_secure_window.sh [--reinstalar]
#
# Aborta (exit 3) se o app já está instalado: reinstalar APAGA a fila de visitas
# offline (SQLCipher) e a chave do Keystore do app de desenvolvimento.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
export PATH="$PATH:$HOME/Android/Sdk/platform-tools:$HOME/flutter/bin"
if [[ -f .env ]]; then set -a; source .env; set +a; fi
: "${MQTT_ACS_PASSWORD:?exporte MQTT_ACS_PASSWORD ou rode ./scripts/dev/bootstrap_env.sh}"

dev=emulator-5554
pkg=br.com.prismrr.sinalacs.acs
reinstalar=0
for arg in "$@"; do
  case "$arg" in
    --reinstalar) reinstalar=1 ;;
    *) echo "argumento desconhecido: $arg" >&2; exit 2 ;;
  esac
done
adb -s "$dev" get-state >/dev/null 2>&1 || { echo "emulador $dev não encontrado (adb devices)"; exit 4; }

instalado() { adb -s "$dev" shell pm list packages "$pkg" 2>/dev/null | grep -q "^package:$pkg\$"; }
if instalado && [[ "$reinstalar" -eq 0 ]]; then
  echo "erro: $pkg já está instalado em $dev; reinstalar APAGA a fila offline e a chave do Keystore." >&2
  echo "      Se for só o app de teste de uma execução anterior, rode com --reinstalar." >&2
  exit 3
fi

log="$(mktemp)"
instalamos=0
limpar() {
  rm -f "$log"
  if [[ "$instalamos" -eq 1 ]]; then adb -s "$dev" uninstall "$pkg" >/dev/null 2>&1 || true; fi
}
trap limpar EXIT

if ! (cd apps/acs && flutter build apk --debug \
      --dart-define=SINALACS_MQTT_PASSWORD="$MQTT_ACS_PASSWORD" >"$log" 2>&1); then
  echo "erro: o build do APK falhou. Últimas linhas:" >&2
  tail -n 30 "$log" >&2
  exit 1
fi
if instalado; then adb -s "$dev" uninstall "$pkg" >/dev/null 2>&1 || true; fi
adb -s "$dev" install -r apps/acs/build/app/outputs/flutter-apk/app-debug.apk >/dev/null
instalamos=1
adb -s "$dev" shell monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 6

# Primeiro `fl=` do bloco da janela do app (a linha `pfl=` é de outra coisa).
flags="$(adb -s "$dev" shell dumpsys window windows | awk -v pkg="$pkg" '
  /^  Window #/ { dentro = index($0, pkg "/") > 0 }
  dentro && /^ +fl=/ { print; exit }')"
if [[ -z "$flags" ]]; then
  echo "erro: a janela de $pkg não apareceu em dumpsys window (o app abriu?)." >&2
  exit 4
fi
if ! grep -qw SECURE <<<"$flags"; then
  echo "erro: a janela do ACS não tem FLAG_SECURE: $flags" >&2
  exit 1
fi
echo "OK — janela do ACS com FLAG_SECURE"
```

- [ ] **Step 3: Ver os dois falharem**

Run: `cd apps/acs && flutter test test/secure_window_test.dart 2>&1 | tail -6; cd ../.. && ./scripts/qa/acs_secure_window.sh; echo rc=$?`
Expected: o teste **FALHA** (`Expected: contains 'override fun onCreate'`); o script imprime `erro: a janela do ACS não tem FLAG_SECURE: fl=...` e `rc=1`. Se o script der `rc=4` (janela não apareceu), o `awk` não casou com o formato do `dumpsys` deste Android: rode `adb shell dumpsys window windows | grep -n "Window #\|fl="` com o app aberto e ajuste **só** a expressão do `awk` até achar o `fl=` do app **sem** SECURE (é o vermelho certo). Não siga com `rc=4`.

- [ ] **Step 4: Implementar**

Substituir o conteúdo de `MainActivity.kt`:

```kotlin
package br.com.prismrr.sinalacs.acs

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // A lista da microárea mostra nome e condições crônicas. FLAG_SECURE
        // bloqueia captura de tela, gravação e a miniatura nos apps recentes,
        // na janela INTEIRA: Área, Visita e o seletor de paciente a exibem, e
        // proteger tela por tela deixaria uma de fora.
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
    }
}
```

- [ ] **Step 5: Ver os dois passarem**

Run: `cd apps/acs && flutter test test/secure_window_test.dart 2>&1 | tail -2; cd ../.. && ./scripts/qa/acs_secure_window.sh; echo rc=$?`
Expected: `All tests passed!`; `OK — janela do ACS com FLAG_SECURE` e `rc=0`; depois, `adb -s emulator-5554 shell pm list packages br.com.prismrr.sinalacs.acs` não lista nada (o script remove o app).

- [ ] **Step 6: Conferir que nada que já rodava no emulador depende de captura**

Run: `grep -rn "screencap\|takeScreenshot\|--screenshot" scripts apps/acs/integration_test apps/acs/test_driver 2>/dev/null | head; ./scripts/qa/acs_gps_e2e.sh && ./scripts/qa/acs_gps_e2e.sh --sem-permissao`
Expected: o `grep` não acha nada; os dois cenários de GPS terminam em `OK` (o `uiautomator dump` do tocador continua funcionando; ele lê a árvore de acessibilidade, não a imagem).

- [ ] **Step 7: Documentar e commitar**

Em `spec/lgpd_design.md`, no fim da §5.1 (onde está a decisão da chave local do SQLCipher), acrescentar: "**Captura de tela (2026-10-02).** A janela do app do ACS é `FLAG_SECURE`: o sistema não permite captura de tela, gravação nem miniatura nos apps recentes. Decisão: a janela inteira, porque a lista da microárea (nome e condições crônicas) aparece em mais de uma tela. Consequência aceita: `adb screencap` do ACS sai preto. Provado por `scripts/qa/acs_secure_window.sh`."

Em `apps/CLAUDE.md`, no parágrafo "ACS: permissões, SAMU e e2e", acrescentar: "A janela do ACS é `FLAG_SECURE` (`MainActivity.kt`); `scripts/qa/acs_secure_window.sh` confere a flag no WindowManager e `test/secure_window_test.dart` guarda o código."

```bash
git add apps/acs/android/app/src/main/kotlin apps/acs/test/secure_window_test.dart scripts/qa/acs_secure_window.sh spec/lgpd_design.md apps/CLAUDE.md
git commit -m "feat(acs): janela com FLAG_SECURE bloqueia captura de tela, gravação e miniatura dos recentes"
```

---

### Task 2: Assinatura de release com chave própria

**Files:**
- Modify: `apps/acs/android/app/build.gradle.kts`
- Create: `scripts/qa/acs_release_signing.sh`
- Modify: `apps/CLAUDE.md`

**Interfaces:** Consumes: —. Produces: propriedades Gradle `sinalacs.allowDebugSigning` (usada nesta task e na Task 8) e as variáveis `SINALACS_KEYSTORE_PATH`, `SINALACS_KEYSTORE_PASSWORD`, `SINALACS_KEY_ALIAS`, `SINALACS_KEY_PASSWORD`.

- [ ] **Step 1: Escrever o verificador (falha porque hoje a build assina com debug)**

Criar `scripts/qa/acs_release_signing.sh` e `chmod +x`:

```bash
#!/usr/bin/env bash
#
# A build de release do ACS não sai com a chave de debug sem pedir.
#
#   ./scripts/qa/acs_release_signing.sh
#
# Três cenários, cada um uma build de release (~1 min):
#   1. sem chave de release e sem a licença de debug  -> a build FALHA, dizendo por quê;
#   2. com -Psinalacs.allowDebugSigning=true          -> assina com "Android Debug";
#   3. com um keystore descartável (criado aqui, em /tmp) por variáveis de ambiente
#                                                     -> assina com o CN do keystore.
# Nenhum segredo real é tocado: o keystore do cenário 3 nasce e morre neste script.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
export PATH="$PATH:$HOME/Android/Sdk/platform-tools:$HOME/flutter/bin"
if [[ -f .env ]]; then set -a; source .env; set +a; fi
: "${MQTT_ACS_PASSWORD:?exporte MQTT_ACS_PASSWORD ou rode ./scripts/dev/bootstrap_env.sh}"

if [[ -f apps/acs/android/key.properties ]]; then
  echo "erro: apps/acs/android/key.properties existe; ele mudaria o cenário 1. Mova-o para fora e rode de novo." >&2
  exit 3
fi
apksigner="$(ls "$HOME"/Android/Sdk/build-tools/*/apksigner | tail -1)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
apk=apps/acs/build/app/outputs/flutter-apk/app-release.apk
define="--dart-define=SINALACS_MQTT_PASSWORD=$MQTT_ACS_PASSWORD"

# O Gradle lê as variáveis SINALACS_KEYSTORE_* do ambiente; nos cenários 1 e 2 elas não existem.
construir() { (cd apps/acs && flutter build apk --release "$define" "$@"); }

echo "== cenário 1: sem chave de release =="
if saida="$(env -u SINALACS_KEYSTORE_PATH construir 2>&1)"; then
  echo "erro: a build de release passou sem chave de release." >&2
  exit 1
fi
grep -q "assinatura de release" <<<"$saida" || { echo "erro: a falha não explicou o motivo:" >&2; tail -n 15 <<<"$saida" >&2; exit 1; }

echo "== cenário 2: -Psinalacs.allowDebugSigning=true =="
construir -Psinalacs.allowDebugSigning=true >/dev/null
"$apksigner" verify --print-certs "$apk" | grep -q "CN=Android Debug" \
  || { echo "erro: o cenário 2 não assinou com a chave de debug." >&2; exit 1; }

echo "== cenário 3: keystore descartável por variáveis de ambiente =="
keytool -genkeypair -keystore "$tmp/teste.jks" -storepass senhateste -keypass senhateste \
  -alias teste -keyalg RSA -keysize 2048 -validity 2 -dname "CN=SinalACS Teste" >/dev/null 2>&1
SINALACS_KEYSTORE_PATH="$tmp/teste.jks" SINALACS_KEYSTORE_PASSWORD=senhateste \
SINALACS_KEY_ALIAS=teste SINALACS_KEY_PASSWORD=senhateste construir >/dev/null
"$apksigner" verify --print-certs "$apk" | grep -q "CN=SinalACS Teste" \
  || { echo "erro: o cenário 3 não assinou com o keystore informado." >&2; exit 1; }

echo "OK — release exige chave própria; debug só com licença explícita"
```

- [ ] **Step 2: Ver falhar**

Run: `./scripts/qa/acs_release_signing.sh; echo rc=$?`
Expected: `erro: a build de release passou sem chave de release.` e `rc=1` (o cenário 1 já falha o script: hoje a build assina com debug e passa).

- [ ] **Step 3: Implementar no Gradle**

Em `apps/acs/android/app/build.gradle.kts`: acrescentar, junto do `import java.util.Base64` do topo,

```kotlin
import java.io.FileInputStream
import java.util.Properties
```

Depois da função `dartDefineValue` e antes do bloco `plugins`, acrescentar:

```kotlin
// Chave de release: de `apps/acs/android/key.properties` (gitignorado) ou, para
// CI e shell, das variáveis SINALACS_KEYSTORE_*. Nenhum valor mora no repositório.
//   storeFile=/caminho/para/release.jks
//   storePassword=...
//   keyAlias=...
//   keyPassword=...
val keyProperties = Properties().apply {
    val arquivo = rootProject.file("key.properties")
    if (arquivo.exists()) FileInputStream(arquivo).use { load(it) }
}

fun assinatura(propriedade: String, ambiente: String): String? =
    keyProperties.getProperty(propriedade)?.takeIf { it.isNotBlank() }
        ?: System.getenv(ambiente)?.takeIf { it.isNotBlank() }

val releaseStoreFile = assinatura("storeFile", "SINALACS_KEYSTORE_PATH")
val releaseStorePassword = assinatura("storePassword", "SINALACS_KEYSTORE_PASSWORD")
val releaseKeyAlias = assinatura("keyAlias", "SINALACS_KEY_ALIAS")
val releaseKeyPassword = assinatura("keyPassword", "SINALACS_KEY_PASSWORD")
val temChaveDeRelease = listOf(
    releaseStoreFile, releaseStorePassword, releaseKeyAlias, releaseKeyPassword,
).all { it != null }
```

Dentro de `android { ... }`, antes de `buildTypes`, acrescentar e trocar o bloco `release`:

```kotlin
    signingConfigs {
        if (temChaveDeRelease) {
            create("release") {
                storeFile = file(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            // Sem chave, a configuração continua carregável (sync da IDE, debug):
            // quem barra a build de RELEASE é o guard `taskGraph.whenReady` abaixo.
            signingConfig = signingConfigs.getByName(if (temChaveDeRelease) "release" else "debug")
        }
    }
```

No fim do arquivo, acrescentar o guard:

```kotlin
// Guard de release: só quando uma tarefa de release está no grafo (o sync da IDE
// e `flutter run` em debug não passam por aqui). Sem chave de release, assinar
// com a de debug exige pedir (-Psinalacs.allowDebugSigning=true).
gradle.taskGraph.whenReady {
    val buildaRelease = allTasks.any {
        it.path.endsWith(":assembleRelease") ||
            it.path.endsWith(":bundleRelease") ||
            it.path.endsWith(":packageRelease")
    }
    if (buildaRelease && !temChaveDeRelease && !project.hasProperty("sinalacs.allowDebugSigning")) {
        throw GradleException(
            """
            |Sem chave de assinatura de release: esta build sairia assinada com a chave de debug.
            |
            |Informe a chave por apps/acs/android/key.properties (storeFile, storePassword,
            |keyAlias, keyPassword) ou pelas variáveis SINALACS_KEYSTORE_PATH,
            |SINALACS_KEYSTORE_PASSWORD, SINALACS_KEY_ALIAS e SINALACS_KEY_PASSWORD.
            |
            |Para assinar com a chave de debug DE PROPÓSITO (teste local, nunca distribuição):
            |  flutter build apk --release -Psinalacs.allowDebugSigning=true
            """.trimMargin()
        )
    }
}
```

- [ ] **Step 4: Ver passar**

Run: `./scripts/qa/acs_release_signing.sh; echo rc=$?`
Expected: três cabeçalhos `== cenário N ==` e `OK — release exige chave própria; debug só com licença explícita`, `rc=0`. Se o cenário 1 falhar por o `grep "assinatura de release"` não casar, a mensagem do `GradleException` está certa e o Flutter a reformatou: ajuste o `grep` para uma palavra que apareça na saída real (`Sem chave de assinatura`) e **não** a mensagem. Se o `-P` do cenário 2 não chegar ao Gradle, use `--android-project-arg=sinalacs.allowDebugSigning=true` (flag do Flutter para argumentos do Gradle) nos scripts **e** na documentação.

- [ ] **Step 5: Documentar e commitar**

Em `apps/CLAUDE.md`, no parágrafo "ACS: permissões, SAMU e e2e", acrescentar: "A build de **release** do ACS exige chave própria (`android/key.properties` ou `SINALACS_KEYSTORE_*`) e **falha** sem ela; assinar com a de debug exige `-Psinalacs.allowDebugSigning=true`. `scripts/qa/acs_release_signing.sh` prova os três cenários com um keystore descartável. O CI não faz build de release e não guarda segredo de assinatura (aberto)."

```bash
git add apps/acs/android/app/build.gradle.kts scripts/qa/acs_release_signing.sh apps/CLAUDE.md
git commit -m "feat(acs): build de release exige chave própria; debug só com licença explícita"
```

---

### Task 3: Botão da UBS passa a discar (RF13)

**Files:**
- Modify: `backend/sinalacs_server/lib/src/models/ubs.spy.yaml`
- Create: `backend/sinalacs_server/lib/src/models/api/ubs_contact.spy.yaml`
- Create: `backend/sinalacs_server/lib/src/application/ubs/ubs_contact_service.dart`
- Create: `backend/sinalacs_server/lib/src/infrastructure/database/orm_ubs_contact_store.dart`
- Create: `backend/sinalacs_server/lib/src/endpoints/ubs_endpoint.dart`
- Modify: `backend/sinalacs_server/lib/src/runtime/alert_runtime.dart` (fábrica `ubsContactServiceFor`)
- Modify: `backend/sinalacs_server/lib/src/infrastructure/database/seeds/development.sql`, `backend/sinalacs_server/bin/seed_e2e_fixtures.dart`
- Test: `backend/sinalacs_server/test/unit/ubs_contact_service_test.dart`
- Modify: `apps/acs/lib/core/network/backend_client.dart`, `apps/acs/lib/app/app.dart`, `apps/acs/test/support/fakes.dart`
- Test: `apps/acs/test/escalation_ubs_test.dart`
- Modify: `spec/lgpd_data_audit.md`, `apps/CLAUDE.md`

**Interfaces:**
- Consumes: `Authorization.require(user, roles:, onDenied:)` (usado por `VisitSyncService`), `AuthenticatedEndpoint.authenticate(accessToken)`, `EmergencyDialer.dial(String) -> Future<bool>`, `BackendScope.of(context)`.
- Produces: protocolo `UbsContact{ String name; String? phone }`; RPC `ubs.myContact(accessToken:)`; `AcsBackend.ubsContact() -> Future<UbsContact>`; `UbsContactService.contactFor(AuthenticatedUser) -> Future<UbsContact>`.

- [ ] **Step 1: Teste do serviço (falha: o serviço não existe)**

Criar `backend/sinalacs_server/test/unit/ubs_contact_service_test.dart`:

```dart
import 'package:sinalacs_server/src/application/ubs/ubs_contact_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:test/test.dart';

const _acsId = '00000000-0000-4000-8000-000000000002';

class _FakeStore implements UbsContactStore {
  _FakeStore(this.record);
  UbsContactRecord? record;
  final consultados = <String>[];

  @override
  Future<UbsContactRecord?> findForAcs(String acsId) async {
    consultados.add(acsId);
    return record;
  }
}

AuthenticatedUser _usuario(UserRole role) => AuthenticatedUser(
      id: _acsId,
      role: role,
      microAreaId: '00000000-0000-4000-8000-000000000003',
      deviceId: 'dispositivo-teste',
    );

void main() {
  test('devolve nome e telefone da UBS do ACS', () async {
    final service = UbsContactService(
      store: _FakeStore(const UbsContactRecord(name: 'UBS Teste', phone: '+55 11 5550-0100')),
    );

    final contato = await service.contactFor(_usuario(UserRole.acs));

    expect(contato.name, 'UBS Teste');
    expect(contato.phone, '+55 11 5550-0100');
  });

  test('UBS sem telefone cadastrado devolve phone nulo, sem falhar', () async {
    final service = UbsContactService(
      store: _FakeStore(const UbsContactRecord(name: 'UBS Sem Fone', phone: null)),
    );
    final contato = await service.contactFor(_usuario(UserRole.acs));
    expect(contato.phone, isNull);
  });

  test('telefone só com espaços vale como não cadastrado', () async {
    final service = UbsContactService(
      store: _FakeStore(const UbsContactRecord(name: 'UBS', phone: '   ')),
    );
    expect((await service.contactFor(_usuario(UserRole.acs))).phone, isNull);
  });

  test('paciente não consulta o contato (nem toca no banco)', () async {
    final store = _FakeStore(const UbsContactRecord(name: 'UBS', phone: '1'));
    final service = UbsContactService(store: store);

    expect(() => service.contactFor(_usuario(UserRole.patient)), throwsA(isA<StateError>()));
    expect(store.consultados, isEmpty);
  });

  test('ACS sem linha na tabela acs é erro, não contato vazio', () async {
    final service = UbsContactService(store: _FakeStore(null));
    expect(() => service.contactFor(_usuario(UserRole.acs)), throwsA(isA<StateError>()));
  });
}
```

- [ ] **Step 2: Ver falhar**

Run: `cd backend/sinalacs_server && dart test test/unit/ubs_contact_service_test.dart 2>&1 | tail -6`
Expected: **FAIL** de compilação (`Target of URI doesn't exist: ...ubs_contact_service.dart`). Antes disso, anotar a linha de base: `dart test test/unit 2>&1 | tail -2` (o total de testes unitários) no ledger.

- [ ] **Step 3: Modelos, serviço, store e endpoint**

`ubs.spy.yaml`, acrescentar ao final de `fields:`:

```yaml
  ### Telefone de contato da UBS para o ACS escalar um caso (RF13). Dado da
  ### unidade, não de pessoa. `null` = ainda não cadastrado: o app avisa, não liga.
  contactPhone: String?
```

Criar `models/api/ubs_contact.spy.yaml`:

```yaml
### Contato da UBS do ACS autenticado (RF13). Só o que o botão "Ligar para a UBS"
### precisa: o nome para a mensagem e o telefone para o discador.
class: UbsContact
fields:
  name: String
  phone: String?
```

Criar `application/ubs/ubs_contact_service.dart`:

```dart
import 'package:sinalacs_server/src/application/auth/authorization.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

class UbsContactRecord {
  const UbsContactRecord({required this.name, required this.phone});

  final String name;
  final String? phone;
}

abstract interface class UbsContactStore {
  /// UBS do ACS `acsId`, ou `null` se o ACS ou a UBS não existirem.
  Future<UbsContactRecord?> findForAcs(String acsId);
}

/// Contato da UBS para o botão de escalonamento do ACS (RF13).
///
/// A UBS vem do **token** (`user.id` é o id do ACS), nunca de parâmetro — mesma
/// regra de território das outras consultas do ACS.
class UbsContactService {
  UbsContactService({required this.store});

  final UbsContactStore store;

  Future<UbsContact> contactFor(AuthenticatedUser user) async {
    Authorization.require(
      user,
      roles: {UserRole.acs},
      onDenied: () => StateError('Somente ACS consultam o contato da UBS.'),
    );

    final record = await store.findForAcs(user.id);
    if (record == null) {
      throw StateError('UBS do ACS não encontrada.');
    }
    final phone = record.phone?.trim();
    return UbsContact(
      name: record.name,
      phone: (phone == null || phone.isEmpty) ? null : phone,
    );
  }
}
```

Se `Authorization` não estiver em `application/auth/authorization.dart` ou exigir `microAreaId`, copie o formato exato da chamada em `application/visits/*` (o `VisitSyncService.pull` usa `Authorization.require(user, roles: {UserRole.acs}, onDenied: ...)`) e ajuste o `import`.

Criar `infrastructure/database/orm_ubs_contact_store.dart`:

```dart
import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/application/ubs/ubs_contact_service.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';

class OrmUbsContactStore implements UbsContactStore {
  OrmUbsContactStore(this._session);

  final Session _session;

  @override
  Future<UbsContactRecord?> findForAcs(String acsId) async {
    final acs = await Acs.db.findById(_session, UuidValue.fromString(acsId));
    if (acs == null) return null;
    final ubs = await Ubs.db.findById(_session, acs.ubsId);
    if (ubs == null) return null;
    return UbsContactRecord(name: ubs.name, phone: ubs.contactPhone);
  }
}
```

Criar `endpoints/ubs_endpoint.dart`:

```dart
import 'package:serverpod/serverpod.dart';
import 'package:sinalacs_server/src/endpoints/authenticated_endpoint.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/runtime/alert_runtime.dart';

/// Contato da UBS do ACS (RF13).
class UbsEndpoint extends AuthenticatedEndpoint {
  Future<UbsContact> myContact(
    Session session, {
    required String accessToken,
  }) async {
    final user = authenticate(accessToken);
    try {
      return await AlertRuntime.instance.ubsContactServiceFor(session).contactFor(user);
    } on StateError catch (error) {
      throw AlertPermissionException(message: error.message);
    }
  }
}
```

Em `runtime/alert_runtime.dart`, ao lado de `patientDirectoryServiceFor` (linha ~206), acrescentar (com os `import`s do serviço e do store):

```dart
  /// Contato da UBS do ACS (RF13), para uma requisição.
  UbsContactService ubsContactServiceFor(Session session) =>
      UbsContactService(store: OrmUbsContactStore(session));
```

- [ ] **Step 4: Gerar, migrar e ver o serviço passar**

Run: `cd backend/sinalacs_server && serverpod generate 2>&1 | tail -3 && serverpod create-migration 2>&1 | tail -3 && dart analyze 2>&1 | tail -2 && dart test test/unit/ubs_contact_service_test.dart 2>&1 | tail -2`
Expected: `generate` e `create-migration` sem erro (uma pasta nova em `migrations/` com `ALTER TABLE "ubs" ADD COLUMN "contactPhone" text;`); `No issues found!`; `All tests passed!` (5 testes). Conferir no SQL gerado que a coluna é **nullable** e que nada é `DROP`.

- [ ] **Step 5: Seed de desenvolvimento e de e2e**

Em `development.sql`, **depois** do `INSERT INTO "ubs" ... ON CONFLICT ("id") DO NOTHING;`, acrescentar (o `DO NOTHING` não atualiza bancos que já têm a UBS):

```sql
-- Telefone sintético (RF13). O UPDATE cobre bancos de dev criados antes da coluna.
UPDATE "ubs" SET "contactPhone" = '+55 11 5550-0100'
WHERE "id" = '00000000-0000-4000-8000-000000000004' AND "contactPhone" IS NULL;
```

Em `bin/seed_e2e_fixtures.dart` (~linha 52), trocar o `INSERT INTO "ubs"` por:

```dart
        Sql.named('INSERT INTO "ubs" ("id","name","address","city","state","contactPhone") '
            "VALUES (@id, 'UBS E2E', 'Endereço de teste', 'São Paulo', 'SP', '+55 11 5550-0199')"),
```

- [ ] **Step 6: Teste do app (falha: não há `ubsContact`)**

Em `apps/acs/test/support/fakes.dart`, dentro de `FakeAcsBackend`, acrescentar:

```dart
  /// Contato que `ubsContact()` devolve; `null` simula uma UBS sem telefone.
  UbsContact ubsContactResult = UbsContact(name: 'UBS Teste', phone: '+55 11 5550-0100');

  /// Falha da chamada, como uma queda de rede.
  BackendFailure? ubsContactFailure;

  int ubsContactCount = 0;

  @override
  Future<UbsContact> ubsContact() async {
    ubsContactCount++;
    final falha = ubsContactFailure;
    if (falha != null) throw falha;
    return ubsContactResult;
  }
```

Criar `apps/acs/test/escalation_ubs_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/app/app.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/network/backend_scope.dart';
import 'package:sinalacs_acs/core/services/emergency_dialer.dart';
import 'package:sinalacs_client/sinalacs_client.dart' show UbsContact;

import 'support/fakes.dart';

class _Dialer implements EmergencyDialer {
  _Dialer({this.abre = true});
  final bool abre;
  final discados = <String>[];

  @override
  Future<bool> dial(String number) async {
    discados.add(number);
    return abre;
  }
}

Future<void> _abrir(WidgetTester tester, FakeAcsBackend backend, _Dialer dialer) =>
    tester.pumpWidget(MaterialApp(
      home: BackendScope(
        backend: backend,
        child: Scaffold(
          body: EscalationScreen(alert: testAlert(alertId: 'a1'), dialer: dialer),
        ),
      ),
    ));

void main() {
  testWidgets('o botão da UBS abre o discador com o telefone cadastrado, só dígitos e +', (tester) async {
    final backend = FakeAcsBackend();
    final dialer = _Dialer();
    await _abrir(tester, backend, dialer);

    await tester.tap(find.byKey(const Key('escalation_ubs')));
    await tester.pumpAndSettle();

    expect(dialer.discados, ['+551155500100']);
    expect(backend.ubsContactCount, 1);
  });

  testWidgets('UBS sem telefone: avisa e não liga', (tester) async {
    final backend = FakeAcsBackend()..ubsContactResult = UbsContact(name: 'UBS Sem Fone');
    final dialer = _Dialer();
    await _abrir(tester, backend, dialer);

    await tester.tap(find.byKey(const Key('escalation_ubs')));
    await tester.pumpAndSettle();

    expect(dialer.discados, isEmpty);
    expect(find.textContaining('UBS Sem Fone ainda não cadastrou um telefone'), findsOneWidget);
  });

  testWidgets('sem discador, mostra o telefone em texto', (tester) async {
    final backend = FakeAcsBackend();
    final dialer = _Dialer(abre: false);
    await _abrir(tester, backend, dialer);

    await tester.tap(find.byKey(const Key('escalation_ubs')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Ligue manualmente para +55 11 5550-0100'), findsOneWidget);
  });

  testWidgets('falha ao obter o contato mostra a mensagem do backend e não liga', (tester) async {
    final backend = FakeAcsBackend()..ubsContactFailure = const BackendFailure('Sem conexão.');
    final dialer = _Dialer();
    await _abrir(tester, backend, dialer);

    await tester.tap(find.byKey(const Key('escalation_ubs')));
    await tester.pumpAndSettle();

    expect(dialer.discados, isEmpty);
    expect(find.text('Sem conexão.'), findsOneWidget);
  });
}
```

- [ ] **Step 7: Ver falhar**

Run: `cd apps/acs && flutter test test/escalation_ubs_test.dart 2>&1 | tail -6`
Expected: **FAIL** de compilação (`The method 'ubsContact' isn't defined` / `Key('escalation_ubs')` ausente). Se `UbsContact` não for exportado por `sinalacs_client`, rode `cd backend && dart pub get` e confira que o `serverpod generate` do Step 4 regenerou `backend/sinalacs_client`.

- [ ] **Step 8: Implementar no app**

Em `backend_client.dart`: na interface `AcsBackend` acrescentar

```dart
  /// Contato da UBS do ACS (RF13): nome e telefone, que pode não estar cadastrado.
  Future<UbsContact> ubsContact();
```

na classe que recusa tudo (a que tem `_recusar()`):

```dart
  @override
  Future<UbsContact> ubsContact() async => _recusar();
```

e no `BackendClient`, ao lado de `listPatients`:

```dart
  @override
  Future<UbsContact> ubsContact() async {
    final token = await _requireToken();
    return _guard(() => _client.ubs.myContact(accessToken: token));
  }
```

Em `app.dart`, em `_EscalationScreenState`, depois de `_callSamu`:

```dart
  /// Liga para a UBS do ACS (RF13). O telefone vem do servidor; sem ele, avisa.
  Future<void> _callUbs() async {
    if (_dialing) return;
    setState(() => _dialing = true);
    String? aviso;
    try {
      final contato = await BackendScope.of(context).ubsContact();
      final telefone = contato.phone?.trim();
      if (telefone == null || telefone.isEmpty) {
        aviso = '${contato.name} ainda não cadastrou um telefone. Acione a coordenação.';
      } else {
        // O discador recebe só dígitos e `+`: espaço e hífen viram %20 no `tel:`.
        final numero = telefone.replaceAll(RegExp(r'[^0-9+]'), '');
        if (!await widget.dialer.dial(numero)) {
          aviso = 'Não foi possível abrir o discador. Ligue manualmente para $telefone.';
        }
      }
    } on BackendFailure catch (falha) {
      aviso = falha.message;
    } catch (_) {
      aviso = 'Não foi possível obter o contato da UBS.';
    }
    if (!mounted) return;
    setState(() => _dialing = false);
    if (aviso != null) _message(context, aviso);
  }
```

e trocar o `OutlinedButton` "Encaminhar para UBS Central" por:

```dart
      OutlinedButton.icon(
        key: const Key('escalation_ubs'),
        onPressed: _dialing ? null : _callUbs,
        style: OutlinedButton.styleFrom(minimumSize: const Size(48, 52)),
        icon: const Icon(Icons.local_hospital_outlined),
        label: const Text('Ligar para a UBS'),
      ),
```

Procurar referências ao texto antigo: `grep -rn "Encaminhar para UBS\|será integrado à UBS" apps spec docs PROGRESS.md --include=*.dart --include=*.md`. Atualizar os testes que o citam (`escalation_dialer_test.dart` etc.) para o novo comportamento, e os `.md` que dizem "botão da UBS segue sendo um aviso" (`PROGRESS.md`, `apps/CLAUDE.md`, `spec/validation_report.md` linha RF13) para "o botão liga para a UBS (`ubs.myContact`); sem telefone cadastrado, avisa".

- [ ] **Step 9: Ver passar e rodar tudo**

Run: `cd apps/acs && flutter analyze 2>&1 | tail -2 && flutter test 2>&1 | tail -2`
Expected: `No issues found!`; `All tests passed!` com **≥ 224** testes (220 + 4).

- [ ] **Step 10: Prova no emulador contra o servidor real**

Em `apps/acs/integration_test/full_journey_e2e.dart`, dentro do **primeiro** `testWidgets` (depois do `pullVisits`, onde já existe `acsClient` logado), acrescentar:

```dart
    // RF13: o contato da UBS chega pelo servidor real, escopado pelo token do ACS.
    final contato = await acsClient.ubs.myContact(accessToken: acs.accessToken);
    expect(contato.name, 'UBS E2E');
    expect(contato.phone, '+55 11 5550-0199');
```

Run: `docker compose up -d --build 2>&1 | tail -2; ./scripts/qa/acs_full_e2e.sh 2>&1 | grep -E "OK —|Some tests|Expected|Actual|rc=" ; docker compose up -d`
Expected: `OK — jornada completa do ACS contra o banco de teste`. (O `acs_full_e2e.sh` sobe a stack de e2e a partir do código atual; se ele não reconstruir a imagem do servidor, o `myContact` não existirá e o teste falha com `404`: rode `docker compose -f docker-compose.e2e.yml build` antes e registre no ledger.)

- [ ] **Step 11: Documentar e commitar**

Em `spec/lgpd_data_audit.md`, na tabela de `ubs`, acrescentar a linha `contactPhone | String? | Dado da unidade (não pessoal) | Telefone para escalonamento (RF13) | Nullable`; e **re-medir** a contagem de tabelas citada no `CLAUDE.md` da raiz (`definition.sql` da última migração) — a tabela não muda de número, só ganha coluna.

```bash
git add backend apps/acs spec PROGRESS.md apps/CLAUDE.md
git commit -m "feat(acs): botão da UBS liga para o telefone cadastrado (RF13) via ubs.myContact"
```

---

### Task 4: RF08 — microárea persistida e criptografada no aparelho

**Files:**
- Modify: `spec/lgpd_design.md` (nova seção), `spec/lgpd_data_audit.md`
- Modify: `apps/acs/lib/core/database/encrypted_database.dart` (v6)
- Create: `apps/acs/lib/core/database/micro_area_cache_store.dart`
- Create: `apps/acs/lib/core/services/micro_area_directory.dart`
- Create: `apps/acs/lib/core/services/micro_area_directory_factory.dart`
- Modify: `apps/acs/lib/app/app.dart` (montagem e dois pontos de chamada, aviso de cache)
- Test: `apps/acs/test/micro_area_cache_store_test.dart`, `apps/acs/test/micro_area_directory_test.dart`, `apps/acs/test/encrypted_database_test.dart` (migração v6)
- Modify: `apps/acs/integration_test/full_journey_e2e.dart` (prova na base criptografada do aparelho)

**Interfaces:**
- Consumes: `MicroAreaPatient({patientId, name, isChronic, chronicConditions})` (de `sinalacs_client`), `AuthSession{userId, microAreaId}` (`auth_session.dart`), `BackendFailure{message, isRecoverable}`, `DatabaseKeyStore.readOrCreate()`, `EncryptedLocalDatabase.open({databaseName, passphrase, allowUnencryptedForTesting})`.
- Produces:
  - `class CachedMicroArea { final List<MicroAreaPatient> patients; final DateTime fetchedAt; }`
  - `class MicroAreaCacheStore { Future<CachedMicroArea?> read({required String owner}); Future<void> write({required String owner, required List<MicroAreaPatient> patients, required DateTime at}); Future<void> clear(); }`
  - `class MicroAreaSnapshot { final List<MicroAreaPatient> patients; final DateTime fetchedAt; final bool fromCache; }`
  - `class MicroAreaDirectory { MicroAreaDirectory({required Future<List<MicroAreaPatient>> Function() fetch, required AuthSession? Function() session, required MicroAreaCacheStore store, DateTime Function()? clock, Duration maxAge = const Duration(hours: 72)}); Future<MicroAreaSnapshot> load(); }`
  - `MicroAreaDirectory buildMicroAreaDirectory({required AcsBackend backend})` e a constante `microAreaCacheMaxAge`.

- [ ] **Step 1: Escrever a decisão de LGPD antes do código**

Em `spec/lgpd_design.md`, depois da §5.6 (minimização), acrescentar a seção:

```markdown
### 5.7 Cache local da microárea (RF08)

| | |
|---|---|
| **Decisão** | O ACS guarda no aparelho a última lista da microárea (`patients.listMicroArea`) para registrar visita **sem rede**. |
| **O que guarda** | Só o que a tela de visita já mostra: `patientId`, nome, `isChronic` e condições crônicas — o mesmo conjunto da §5.6. Nada de contato de emergência, endereço, histórico ou triagem. |
| **Onde** | Tabelas `micro_area_cache` e `micro_area_cache_meta` na **mesma base SQLCipher** das visitas offline (INV-04; chave no Keystore, §5.1). |
| **Dono** | A lista pertence a `userId\|microAreaId` da sessão que a baixou. Outro usuário ou outra microárea **apaga** o cache e não o serve (RNF06). |
| **Validade** | 72 horas desde o último download bem-sucedido. Vencida, **não é usada e é apagada**. |
| **Quando entra** | Só no lugar de uma falha **recuperável** de rede. Uma recusa do servidor (sessão inválida, território negado, `isRecoverable: false`) nunca cai no cache. |
| **Transparência** | A tela diz que a lista é do cache e de quando. |
| **Retenção** | Some pela validade, pelo troca de dono e com a desinstalação; nunca é enviada a lugar nenhum. |
| **Se for revisto** | Reduzir `microAreaCacheMaxAge` ou apagar a tabela v6 é migração aditiva reversível. |
```

Em `spec/lgpd_data_audit.md`, acrescentar as duas tabelas **locais** do aparelho (`micro_area_cache`: `patient_id`, `name` = identificador pessoal, `is_chronic`, `chronic_conditions` = dado sensível de saúde; `micro_area_cache_meta`: `owner`, `fetched_at` = metadado) com a mesma classificação das colunas equivalentes de `patients`, e a nota "no aparelho, sob SQLCipher".

- [ ] **Step 2: Teste da migração v6 (falha: `schemaVersion` é 5)**

Em `apps/acs/test/encrypted_database_test.dart`, copiando o `setUp`/`tearDown` e o jeito de criar um banco antigo dos testes de migração que já existem nesse arquivo (o de v4 → v5 para `sync_cursor`), acrescentar o caso: criar um banco **v5** com uma visita pendente em `offline_visits`, abri-lo com `EncryptedLocalDatabase.open`, e afirmar que (a) as duas tabelas novas existem (`SELECT name FROM sqlite_master WHERE name IN ('micro_area_cache','micro_area_cache_meta')` devolve 2 linhas), (b) a visita pendente continua lá, (c) `EncryptedLocalDatabase.schemaVersion == 6`.

Run: `cd apps/acs && flutter test test/encrypted_database_test.dart 2>&1 | tail -6`
Expected: o caso novo **FALHA** (`Expected: <6> Actual: <5>`).

- [ ] **Step 3: Implementar a migração v6**

Em `encrypted_database.dart`: `static const schemaVersion = 6;`, acrescentar à doc da versão "v6 acrescenta `micro_area_cache` e `micro_area_cache_meta`, o cache da microárea (RF08, `spec/lgpd_design.md` §5.7)", e:

```dart
  /// Cache da microárea (RF08, §5.7 de spec/lgpd_design.md): a última lista que
  /// o servidor devolveu, de um dono (`userId|microAreaId`), com a data do
  /// download. Sob a mesma criptografia das visitas.
  static const createMicroAreaCache = '''
CREATE TABLE IF NOT EXISTS micro_area_cache (
  patient_id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  is_chronic INTEGER NOT NULL,
  chronic_conditions TEXT NOT NULL
)''';

  static const createMicroAreaCacheMeta = '''
CREATE TABLE IF NOT EXISTS micro_area_cache_meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
)''';
```

Nos dois caminhos que criam o banco do zero (`onCreate`, linhas ~156 e ~171 — onde já se executam `createOfflineVisits` e `createSyncCursor`), executar também as duas novas; em `_upgrade`, depois do bloco `from < 5`:

```dart
    if (from < 6) {
      // Aditiva: `CREATE TABLE IF NOT EXISTS` não toca em nada que já existe.
      await db.execute(createMicroAreaCache);
      await db.execute(createMicroAreaCacheMeta);
    }
```

Atualizar o comentário "Migração v1 → v2, … e v4 → v5" para incluir v5 → v6.

Run: `cd apps/acs && flutter test test/encrypted_database_test.dart 2>&1 | tail -3`
Expected: `All tests passed!`.

- [ ] **Step 4: Teste do store (falha: o store não existe)**

Criar `apps/acs/test/micro_area_cache_store_test.dart`. Copie o cabeçalho de `test/sync_cursor_store_test.dart` (imports, `InMemoryDatabaseKeyStore`, nome de banco único por teste e remoção do arquivo no `tearDown`) e use `MicroAreaCacheStore(keyStore: ..., databaseName: ..., allowUnencryptedForTesting: true)`:

```dart
MicroAreaPatient _paciente(int n, {bool cronico = false}) => MicroAreaPatient(
      patientId: syntheticPatientId(n),
      name: 'Paciente Sintético $n',
      isChronic: cronico,
      chronicConditions: cronico ? ['hipertensão', 'diabetes'] : const [],
    );

// ... dentro de main(), com o store criado no setUp:
test('sem nada gravado, read devolve null', () async {
  expect(await store.read(owner: 'u1|m1'), isNull);
});

test('grava e lê de volta a lista, a data e as condições crônicas', () async {
  final em = DateTime.utc(2026, 10, 2, 8);
  await store.write(owner: 'u1|m1', patients: [_paciente(1), _paciente(2, cronico: true)], at: em);

  final lido = await store.read(owner: 'u1|m1');

  expect(lido!.fetchedAt, em);
  expect(lido.patients.map((p) => p.patientId), [syntheticPatientId(1), syntheticPatientId(2)]);
  expect(lido.patients.last.isChronic, isTrue);
  expect(lido.patients.last.chronicConditions, ['hipertensão', 'diabetes']);
});

test('outro dono apaga e não serve', () async {
  await store.write(owner: 'u1|m1', patients: [_paciente(1)], at: DateTime.utc(2026, 10, 2));

  expect(await store.read(owner: 'u2|m1'), isNull, reason: 'outro usuário');
  expect(await store.read(owner: 'u1|m1'), isNull, reason: 'o cache do dono antigo foi APAGADO, não só escondido');
});

test('regravar substitui a lista inteira (paciente que saiu da microárea some)', () async {
  await store.write(owner: 'u1|m1', patients: [_paciente(1), _paciente(2)], at: DateTime.utc(2026, 10, 2));
  await store.write(owner: 'u1|m1', patients: [_paciente(2)], at: DateTime.utc(2026, 10, 3));

  final lido = await store.read(owner: 'u1|m1');
  expect(lido!.patients.map((p) => p.patientId), [syntheticPatientId(2)]);
});

test('clear apaga tudo', () async {
  await store.write(owner: 'u1|m1', patients: [_paciente(1)], at: DateTime.utc(2026, 10, 2));
  await store.clear();
  expect(await store.read(owner: 'u1|m1'), isNull);
});
```

(`syntheticPatientId` vem de `test/support/fakes.dart`; `MicroAreaPatient` de `package:sinalacs_client/sinalacs_client.dart`.)

Run: `cd apps/acs && flutter test test/micro_area_cache_store_test.dart 2>&1 | tail -4`
Expected: **FAIL** de compilação (`micro_area_cache_store.dart` não existe).

- [ ] **Step 5: Implementar o store**

Criar `lib/core/database/micro_area_cache_store.dart`:

```dart
import 'dart:convert';

import 'package:sinalacs_acs/core/database/encrypted_database.dart';
import 'package:sinalacs_acs/core/security/database_key_store.dart';
import 'package:sinalacs_client/sinalacs_client.dart' show MicroAreaPatient;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show ConflictAlgorithm, Database;

class CachedMicroArea {
  const CachedMicroArea({required this.patients, required this.fetchedAt});

  final List<MicroAreaPatient> patients;
  final DateTime fetchedAt;
}

/// Última lista da microárea no aparelho (RF08), na base SQLCipher das visitas.
///
/// Política em `spec/lgpd_design.md` §5.7: a lista pertence a um dono
/// (`userId|microAreaId`); [read] de **outro** dono apaga o cache em vez de
/// só escondê-lo — dado de outro território não fica no disco esperando uma
/// confusão.
class MicroAreaCacheStore {
  MicroAreaCacheStore({
    required DatabaseKeyStore keyStore,
    this.databaseName = 'sinalacs_acs.db',
    this.allowUnencryptedForTesting = false,
  }) : _keyStore = keyStore;

  static const _tabela = 'micro_area_cache';
  static const _meta = 'micro_area_cache_meta';
  static const _chaveDono = 'owner';
  static const _chaveData = 'fetched_at';

  final DatabaseKeyStore _keyStore;
  final String databaseName;
  final bool allowUnencryptedForTesting;
  Database? _database;

  Future<Database> _open() async {
    final existente = _database;
    if (existente != null && existente.isOpen) return existente;
    final passphrase = await _keyStore.readOrCreate();
    return _database = await EncryptedLocalDatabase.open(
      databaseName: databaseName,
      passphrase: passphrase,
      allowUnencryptedForTesting: allowUnencryptedForTesting,
    );
  }

  Future<CachedMicroArea?> read({required String owner}) async {
    final db = await _open();
    final meta = {
      for (final linha in await db.query(_meta)) linha['key'] as String: linha['value'] as String,
    };
    final donoGravado = meta[_chaveDono];
    final data = meta[_chaveData];
    if (donoGravado == null || data == null) return null;
    if (donoGravado != owner) {
      await clear();
      return null;
    }

    final linhas = await db.query(_tabela, orderBy: 'rowid');
    return CachedMicroArea(
      fetchedAt: DateTime.parse(data),
      patients: [
        for (final linha in linhas)
          MicroAreaPatient(
            patientId: linha['patient_id'] as String,
            name: linha['name'] as String,
            isChronic: (linha['is_chronic'] as int) == 1,
            chronicConditions: (jsonDecode(linha['chronic_conditions'] as String) as List).cast<String>(),
          ),
      ],
    );
  }

  Future<void> write({
    required String owner,
    required List<MicroAreaPatient> patients,
    required DateTime at,
  }) async {
    final db = await _open();
    await db.transaction((txn) async {
      await txn.delete(_tabela);
      for (final p in patients) {
        await txn.insert(_tabela, {
          'patient_id': p.patientId,
          'name': p.name,
          'is_chronic': p.isChronic ? 1 : 0,
          'chronic_conditions': jsonEncode(p.chronicConditions),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await txn.insert(_meta, {'key': _chaveDono, 'value': owner}, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert(_meta, {'key': _chaveData, 'value': at.toUtc().toIso8601String()},
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> clear() async {
    final db = await _open();
    await db.transaction((txn) async {
      await txn.delete(_tabela);
      await txn.delete(_meta);
    });
  }
}
```

Run: `cd apps/acs && flutter test test/micro_area_cache_store_test.dart 2>&1 | tail -3`
Expected: `All tests passed!` (5 testes).

- [ ] **Step 6: Teste do `MicroAreaDirectory` (falha: não existe)**

Criar `apps/acs/test/micro_area_directory_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_acs/core/database/micro_area_cache_store.dart';
import 'package:sinalacs_acs/core/network/auth_session.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/services/micro_area_directory.dart';
import 'package:sinalacs_client/sinalacs_client.dart' show MicroAreaPatient;

import 'support/fakes.dart';

/// Store em memória: o que se testa aqui é a REGRA (quando serve cache), não o SQLite.
class _Store implements MicroAreaCacheStore {
  String? owner;
  List<MicroAreaPatient>? patients;
  DateTime? at;
  int clears = 0;
  bool falhaAoGravar = false;

  @override
  Future<CachedMicroArea?> read({required String owner}) async {
    if (this.owner == null) return null;
    if (this.owner != owner) {
      await clear();
      return null;
    }
    return CachedMicroArea(patients: patients!, fetchedAt: at!);
  }

  @override
  Future<void> write({required String owner, required List<MicroAreaPatient> patients, required DateTime at}) async {
    if (falhaAoGravar) throw StateError('disco cheio');
    this.owner = owner;
    this.patients = patients;
    this.at = at;
  }

  @override
  Future<void> clear() async {
    clears++;
    owner = null;
    patients = null;
    at = null;
  }
}

AuthSession _sessao({String userId = 'u1', String? microAreaId = 'm1'}) => AuthSession(
      accessToken: 't',
      tokenType: 'Bearer',
      userId: userId,
      role: 'acs',
      microAreaId: microAreaId,
      expiresAt: DateTime.utc(2030),
    );

MicroAreaPatient _p(int n) =>
    MicroAreaPatient(patientId: syntheticPatientId(n), name: 'P$n', isChronic: false, chronicConditions: const []);

void main() {
  late _Store store;
  late DateTime agora;
  late AuthSession? sessao;
  late Future<List<MicroAreaPatient>> Function() busca;

  MicroAreaDirectory diretorio() => MicroAreaDirectory(
        fetch: () => busca(),
        session: () => sessao,
        store: store,
        clock: () => agora,
      );

  setUp(() {
    store = _Store();
    agora = DateTime.utc(2026, 10, 2, 8);
    sessao = _sessao();
    busca = () async => [_p(1), _p(2)];
  });

  test('com rede: devolve a lista fresca e grava', () async {
    final r = await diretorio().load();

    expect(r.fromCache, isFalse);
    expect(r.patients, hasLength(2));
    expect(store.patients, hasLength(2));
    expect(store.owner, 'u1|m1');
  });

  test('sem rede, com cache do mesmo dono: serve o cache e diz a data', () async {
    await diretorio().load();
    agora = agora.add(const Duration(hours: 5));
    busca = () async => throw const BackendFailure('Sem conexão.');

    final r = await diretorio().load();

    expect(r.fromCache, isTrue);
    expect(r.patients, hasLength(2));
    expect(r.fetchedAt, DateTime.utc(2026, 10, 2, 8));
  });

  test('sem rede e sem cache: a falha original sobe', () async {
    busca = () async => throw const BackendFailure('Sem conexão.');
    expect(diretorio().load(), throwsA(isA<BackendFailure>()));
  });

  test('recusa do servidor NUNCA cai no cache', () async {
    await diretorio().load();
    busca = () async => throw const BackendFailure('Sessão inválida.', isRecoverable: false);

    expect(diretorio().load(), throwsA(isA<BackendFailure>()));
  });

  test('outro dono apaga e não serve', () async {
    await diretorio().load();
    sessao = _sessao(userId: 'u2');
    busca = () async => throw const BackendFailure('Sem conexão.');

    expect(diretorio().load(), throwsA(isA<BackendFailure>()));
    expect(store.owner, isNull, reason: 'o cache do outro usuário foi apagado');
  });

  test('outra microárea apaga e não serve', () async {
    await diretorio().load();
    sessao = _sessao(microAreaId: 'm2');
    busca = () async => throw const BackendFailure('Sem conexão.');

    expect(diretorio().load(), throwsA(isA<BackendFailure>()));
    expect(store.owner, isNull);
  });

  test('vencido não serve e é apagado', () async {
    await diretorio().load();
    agora = agora.add(const Duration(hours: 73));
    busca = () async => throw const BackendFailure('Sem conexão.');

    expect(diretorio().load(), throwsA(isA<BackendFailure>()));
    expect(store.owner, isNull);
  });

  test('exatamente 72 h ainda serve', () async {
    await diretorio().load();
    agora = agora.add(const Duration(hours: 72));
    busca = () async => throw const BackendFailure('Sem conexão.');

    expect((await diretorio().load()).fromCache, isTrue);
  });

  test('falha ao gravar o cache não derruba a lista fresca', () async {
    store.falhaAoGravar = true;
    final r = await diretorio().load();
    expect(r.patients, hasLength(2));
    expect(r.fromCache, isFalse);
  });

  test('sem sessão não há dono: nada é lido nem gravado', () async {
    sessao = null;
    final r = await diretorio().load();
    expect(r.fromCache, isFalse);
    expect(store.owner, isNull);
  });

  test('lista vazia fresca substitui o cache (a microárea esvaziou)', () async {
    await diretorio().load();
    busca = () async => <MicroAreaPatient>[];
    await diretorio().load();
    expect(store.patients, isEmpty);
  });
}
```

Run: `cd apps/acs && flutter test test/micro_area_directory_test.dart 2>&1 | tail -4`
Expected: **FAIL** de compilação (`micro_area_directory.dart` não existe).

- [ ] **Step 7: Implementar o serviço e a fábrica**

Criar `lib/core/services/micro_area_directory.dart`:

```dart
import 'dart:developer' as developer;

import 'package:sinalacs_acs/core/database/micro_area_cache_store.dart';
import 'package:sinalacs_acs/core/network/auth_session.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_client/sinalacs_client.dart' show MicroAreaPatient;

/// Validade do cache da microárea (spec/lgpd_design.md §5.7).
const microAreaCacheMaxAge = Duration(hours: 72);

class MicroAreaSnapshot {
  const MicroAreaSnapshot({required this.patients, required this.fetchedAt, required this.fromCache});

  final List<MicroAreaPatient> patients;
  final DateTime fetchedAt;

  /// `true` quando a lista veio do aparelho porque a central não respondeu.
  final bool fromCache;
}

/// Lista da microárea com cache no aparelho (RF08).
///
/// Regra única, em um lugar só: o cache entra **apenas** no lugar de uma falha
/// recuperável (`isRecoverable`) e **apenas** para o mesmo `userId|microAreaId`
/// e dentro da validade. Recusa do servidor (`isRecoverable: false`) sobe como
/// veio — um território negado não pode ser contornado por um cache antigo.
class MicroAreaDirectory {
  MicroAreaDirectory({
    required Future<List<MicroAreaPatient>> Function() fetch,
    required AuthSession? Function() session,
    required MicroAreaCacheStore store,
    DateTime Function()? clock,
    this.maxAge = microAreaCacheMaxAge,
  })  : _fetch = fetch,
        _session = session,
        _store = store,
        _clock = clock ?? DateTime.now;

  final Future<List<MicroAreaPatient>> Function() _fetch;
  final AuthSession? Function() _session;
  final MicroAreaCacheStore _store;
  final DateTime Function() _clock;
  final Duration maxAge;

  String? _owner() {
    final s = _session();
    if (s == null || s.microAreaId == null) return null;
    return '${s.userId}|${s.microAreaId}';
  }

  Future<MicroAreaSnapshot> load() async {
    final owner = _owner();
    try {
      final fresh = await _fetch();
      final at = _clock().toUtc();
      if (owner != null) {
        try {
          await _store.write(owner: owner, patients: fresh, at: at);
        } catch (error, stack) {
          // Gravar o cache é conforto; nunca derruba a lista que acabou de chegar.
          developer.log('não foi possível gravar o cache da microárea',
              name: 'sinalacs.acs.micro_area_directory', error: error, stackTrace: stack);
        }
      }
      return MicroAreaSnapshot(patients: fresh, fetchedAt: at, fromCache: false);
    } on BackendFailure catch (falha) {
      if (!falha.isRecoverable || owner == null) rethrow;
      final guardado = await _lerSemFalhar(owner);
      if (guardado == null) rethrow;
      if (_clock().toUtc().difference(guardado.fetchedAt) > maxAge) {
        await _apagarSemFalhar();
        rethrow;
      }
      return MicroAreaSnapshot(patients: guardado.patients, fetchedAt: guardado.fetchedAt, fromCache: true);
    }
  }

  Future<CachedMicroArea?> _lerSemFalhar(String owner) async {
    try {
      return await _store.read(owner: owner);
    } catch (_) {
      return null; // cache ilegível = sem cache; a falha da rede é a que importa
    }
  }

  Future<void> _apagarSemFalhar() async {
    try {
      await _store.clear();
    } catch (_) {}
  }
}
```

Criar `lib/core/services/micro_area_directory_factory.dart` (mesmo desenho de `visit_pull_service_factory.dart`: em produção o `keyStore` é o do Keystore/Keychain do aparelho e `allowUnencryptedForTesting` fica `false`):

```dart
import 'package:sinalacs_acs/core/database/micro_area_cache_store.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/security/database_key_store.dart';
import 'package:sinalacs_acs/core/services/micro_area_directory.dart';

/// Monta o diretório da microárea sobre o backend e a base SQLCipher do aparelho.
///
/// [cacheStore] existe só para um teste inspecionar o que foi gravado; em
/// produção a chamada não passa nada e usa o padrão, respaldado pelo
/// Keystore/Keychain.
MicroAreaDirectory buildMicroAreaDirectory({
  required AcsBackend backend,
  MicroAreaCacheStore? cacheStore,
}) =>
    MicroAreaDirectory(
      fetch: backend.listPatients,
      session: () => backend.session,
      store: cacheStore ?? MicroAreaCacheStore(keyStore: SecureStorageDatabaseKeyStore()),
    );
```

Os testes de widget que **não** injetam um `MicroAreaDirectory` usam este de produção; o store só abre a base na primeira leitura/gravação e, no `flutter test`, o Keystore não existe — a falha é engolida pelo próprio `MicroAreaDirectory` (`falha ao gravar o cache não derruba a lista fresca`), então esses testes seguem verdes.

Run: `cd apps/acs && flutter test test/micro_area_directory_test.dart 2>&1 | tail -3`
Expected: `All tests passed!` (11 testes).

- [ ] **Step 8: Ligar nos dois pontos de chamada, com aviso**

Em `app.dart`:

1. `_SinalAcsAppState` (onde `_visitStore`/`buildVisitPullService` são montados, linhas ~81–98): acrescentar `late final MicroAreaDirectory _microAreaDirectory = widget.microAreaDirectory ?? buildMicroAreaDirectory(backend: widget.backend);` e o parâmetro opcional `MicroAreaDirectory? microAreaDirectory` em `SinalAcsApp` (para os testes), repassado a `AcsHomeShell` como `directory`.
2. `AcsHomeShell._loadMicroAreaPatients` (~436): trocar `final patients = await backend.listPatients();` por
   ```dart
   final snapshot = widget.directory == null
       ? null
       : await widget.directory!.load();
   final patients = snapshot?.patients ?? await backend.listPatients();
   ```
   e, no `setState`, `_microAreaPatientsLoadedAt = snapshot?.fetchedAt ?? DateTime.now();` e `_microAreaFromCache = snapshot?.fromCache ?? false;` (campo novo, `false` no início de cada carga).
3. `_VisitRegistrationScreenState._loadPatients` (~1602): receber `directory` por parâmetro opcional de `VisitRegistrationScreen` (o shell o repassa) e trocar `final result = await BackendScope.of(context).listPatients();` por `final snapshot = widget.directory == null ? null : await widget.directory!.load(); final result = snapshot?.patients ?? await BackendScope.of(context).listPatients();` guardando `_patientsFromCache = snapshot?.fromCache ?? false; _patientsFetchedAt = snapshot?.fetchedAt;`.
4. Aviso (nas duas telas, logo acima da lista/contador, quando `fromCache`), com a chave `micro_area_cache_notice` na tela de visita e `micro_area_cache_notice_area` na de Área:

```dart
if (_patientsFromCache && _patientsFetchedAt != null)
  Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Semantics(
      liveRegion: true,
      child: Text(
        key: const Key('micro_area_cache_notice'),
        'Sem conexão com a central: lista salva em ${_formatarDataHora(_patientsFetchedAt!)}.',
        style: TextStyle(color: context.acsRisk.accentOnSurface, fontWeight: FontWeight.bold),
      ),
    ),
  ),
```

com a função de nível de arquivo (sem `intl`, o app não a usa):

```dart
String _formatarDataHora(DateTime utc) {
  final d = utc.toLocal();
  String dois(int n) => n.toString().padLeft(2, '0');
  return '${dois(d.day)}/${dois(d.month)} às ${dois(d.hour)}:${dois(d.minute)}';
}
```

Os dois parâmetros novos são **opcionais**: os 220+ testes existentes, que não os passam, seguem iguais.

- [ ] **Step 9: Teste de widget do aviso e do offline na tela de visita**

Em `apps/acs/test/login_flow_test.dart` (ou arquivo novo `micro_area_cache_ui_test.dart` no mesmo estilo de `login_flow_test.dart`), caso: `FakeAcsBackend` com `patients` preenchidos; um `MicroAreaDirectory(fetch: backend.listPatients, session: () => backend.session, store: _Store())` com o `_Store` em memória do passo 6; abrir a aba Visita (primeira carga grava), depois `backend.listPatientsFailure = const BackendFailure('Sem conexão.')`, tocar "Tentar de novo"/reabrir a aba, e afirmar que `find.byKey(const Key('micro_area_cache_notice'))` aparece e que o paciente continua em `patient_picker`. Outro caso: com `listPatientsFailure = BackendFailure('Sessão inválida.', isRecoverable: false)` o aviso **não** aparece e o erro da tela sim.

Run: `cd apps/acs && flutter analyze 2>&1 | tail -2 && flutter test 2>&1 | tail -2`
Expected: `No issues found!`; `All tests passed!` com **≥ 242** testes (224 + 1 migração + 5 store + 11 diretório + 2 de tela).

- [ ] **Step 10: Prova no emulador: cacheia, cai a rede, serve, e o disco está cifrado**

Em `integration_test/full_journey_e2e.dart`, acrescentar um `testWidgets` **entre** o da rajada e o fim do arquivo (antes de qualquer teste de MFA da Task 6), com os `import`s de `micro_area_cache_store.dart`, `micro_area_directory.dart`, `database_key_store.dart` e `encrypted_database.dart`:

```dart
  testWidgets('RF08: a microárea fica no aparelho, sobrevive à queda de rede e está cifrada', (tester) async {
    final ca = (await rootBundle.load(BackendConfig.rpcCaAsset)).buffer.asUint8List();
    final backend = BackendClient(trustedCaBytes: ca);
    addTearDown(backend.close);
    final cred = await acsCredentialFromRelay();
    final main = e2ePatient('main');
    await backend.login(matricula: cred.matricula, senha: cred.senha);

    // O `keyStore` de PRODUÇÃO (Keystore do aparelho), numa base própria deste teste.
    final store = MicroAreaCacheStore(keyStore: SecureStorageDatabaseKeyStore(), databaseName: 'rf08_e2e.db');
    final online = MicroAreaDirectory(fetch: backend.listPatients, session: () => backend.session, store: store);
    final primeira = await online.load();
    expect(primeira.fromCache, isFalse);
    expect(primeira.patients.any((p) => p.patientId == main.id), isTrue);

    // Rede caída: a central "não responde", o aparelho serve o que guardou.
    final offline = MicroAreaDirectory(
      fetch: () async => throw const BackendFailure('Sem conexão.'),
      session: () => backend.session,
      store: store,
    );
    final segunda = await offline.load();
    expect(segunda.fromCache, isTrue);
    expect(segunda.patients.any((p) => p.patientId == main.id), isTrue);

    // O arquivo no disco NÃO contém o nome do paciente em texto claro (SQLCipher no aparelho).
    final bytes = await File(await EncryptedLocalDatabase.pathFor('rf08_e2e.db')).readAsBytes();
    expect(String.fromCharCodes(bytes).contains(main.name), isFalse,
        reason: 'o nome do paciente não pode estar legível no arquivo do banco');
    expect(String.fromCharCodes(bytes.take(16)), isNot(startsWith('SQLite format 3')));
    await store.clear();
  });
```

Run: `./scripts/qa/acs_full_e2e.sh 2>&1 | grep -E "OK —|Some tests|Expected|Actual|rc="; docker compose up -d`
Expected: `OK — jornada completa do ACS contra o banco de teste`. Se a asserção do nome falhar, a base **não** está cifrada neste caminho: é achado de segurança — pare e investigue (`allowUnencryptedForTesting` ligado fora de teste?), não relaxe a asserção.

- [ ] **Step 11: Documentar e commitar**

`PROGRESS.md`: marcar RF08 como "cache persistido e cifrado (72 h, por dono)" e remover "RF08 persistido" de "Continua aberto"; `apps/CLAUDE.md`: um parágrafo curto sobre `MicroAreaDirectory`/`MicroAreaCacheStore`; `spec/validation_report.md`: se a linha RF08 diz "parcial", atualizar a frase e rodar `python3 scripts/qa/contagem_validation_report.py` (a contagem muda de `parcial` para `backend + app`; ajuste a linha **Contagem** à mão e confira que o conferidor volta a `ok`).

```bash
git add apps/acs spec PROGRESS.md apps/CLAUDE.md
git commit -m "feat(acs): RF08 — microárea persistida na base SQLCipher, por dono e com validade de 72 h"
```

---

### Task 5: MFA (TOTP) no login institucional — backend

**Files:**
- Create: `backend/sinalacs_server/lib/src/application/auth/totp.dart`
- Create: `backend/sinalacs_server/lib/src/application/auth/totp_secret_vault.dart`
- Create: `backend/sinalacs_server/lib/src/infrastructure/crypto/health_cipher_totp_vault.dart`
- Modify: `backend/sinalacs_server/lib/src/application/auth/institutional_auth_service.dart`
- Modify: `backend/sinalacs_server/lib/src/infrastructure/database/orm_acs_credential_store.dart`
- Modify: `backend/sinalacs_server/lib/src/models/user_credential.spy.yaml`
- Create: `backend/sinalacs_server/lib/src/models/exceptions/mfa_required_exception.spy.yaml`, `mfa_enrollment_required_exception.spy.yaml`, `backend/sinalacs_server/lib/src/models/api/totp_enrollment_start.spy.yaml`
- Modify: `backend/sinalacs_server/lib/src/endpoints/auth_endpoint.dart`, `lib/src/runtime/alert_runtime.dart`, `lib/src/config/app_config.dart`, `.env.example`, `docker-compose.yml`
- Test: `backend/sinalacs_server/test/unit/totp_test.dart`, `backend/sinalacs_server/test/unit/institutional_auth_mfa_test.dart`, `backend/sinalacs_server/test/unit/app_config_test.dart`

**Interfaces:**
- Consumes: `InstitutionalAuthService` (`store`, `hasher`, `audit`, `maxFailedAttempts`, `lockDuration`, `_recordAudit`, `_invalidCredentials`), `AcsCredentialRecord`, `PasswordHasher.derive/matches`, `HealthDataCipher.encrypt(String) -> EncryptedValue{ciphertextBase64,keyVersion}` / `decrypt(EncryptedValue) -> String`.
- Produces:
  - `Totp.code(Uint8List secret, DateTime at) -> String`; `Totp.stepOf(DateTime) -> int`; `Totp.verify(Uint8List secret, String code, DateTime at, {int window = 1, int? lastStep}) -> int?`; `Totp.base32(Uint8List) -> String`; `Totp.otpauthUri({required String secretBase32, required String account, String issuer = 'SinalACS'}) -> String`.
  - `class SealedSecret { String ciphertextBase64; int keyVersion }`; `abstract interface class TotpSecretVault { Future<SealedSecret> seal(Uint8List); Future<Uint8List> open(SealedSecret); }`.
  - `class TotpEnrollment { SealedSecret sealed; bool enabled; int? lastStep }`; `AcsCredentialRecord.totp` (opcional, `null` = sem MFA).
  - `abstract interface class TotpStore { Future<void> saveSecret(String acsId, SealedSecret s, DateTime at); Future<void> enable(String acsId, int step, DateTime at); Future<void> registerStep(String acsId, int step); }`
  - `InstitutionalAuthService({..., TotpStore? totpStore, TotpSecretVault? vault, bool requireMfa = false, Random? random})`; `login(..., String? totpCode)`; `beginTotpEnrollment({matricula, password}) -> TotpEnrollmentStart`; `confirmTotpEnrollment({matricula, password, code})`.
  - RPC: `auth.loginInstitutional(matricula:, password:, deviceId:, totpCode:)`, `auth.beginTotpEnrollment(matricula:, password:)`, `auth.confirmTotpEnrollment(matricula:, password:, code:)`; exceções `MfaRequiredException{message}`, `MfaEnrollmentRequiredException{message}`.

- [ ] **Step 1: Teste do `Totp` com os vetores da RFC 6238 (falha: não existe)**

Criar `backend/sinalacs_server/test/unit/totp_test.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:sinalacs_server/src/application/auth/totp.dart';
import 'package:test/test.dart';

void main() {
  // Segredo da RFC 6238 (Apêndice B): ASCII "12345678901234567890".
  final segredo = Uint8List.fromList(ascii.encode('12345678901234567890'));
  DateTime em(int segundos) => DateTime.fromMillisecondsSinceEpoch(segundos * 1000, isUtc: true);

  group('RFC 6238 — vetores do SHA-1 (6 últimos dígitos)', () {
    final vetores = {
      59: '287082',
      1111111109: '081804',
      1111111111: '050471',
      1234567890: '005924',
      2000000000: '279037',
      20000000000: '353130',
    };
    vetores.forEach((t, esperado) {
      test('T=$t → $esperado', () => expect(Totp.code(segredo, em(t)), esperado));
    });
  });

  test('base32 do segredo da RFC é o valor conhecido', () {
    expect(Totp.base32(segredo), 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ');
  });

  test('o passo muda a cada 30 s', () {
    expect(Totp.stepOf(em(29)), 0);
    expect(Totp.stepOf(em(30)), 1);
  });

  group('verify', () {
    test('aceita o código do passo atual e devolve o passo', () {
      final agora = em(1111111111);
      expect(Totp.verify(segredo, Totp.code(segredo, agora), agora), Totp.stepOf(agora));
    });

    test('aceita um passo antes e um depois (relógio fora por até 30 s)', () {
      final agora = em(1111111111);
      expect(Totp.verify(segredo, Totp.code(segredo, agora.subtract(const Duration(seconds: 30))), agora),
          Totp.stepOf(agora) - 1);
      expect(Totp.verify(segredo, Totp.code(segredo, agora.add(const Duration(seconds: 30))), agora),
          Totp.stepOf(agora) + 1);
    });

    test('recusa dois passos de distância', () {
      final agora = em(1111111111);
      expect(Totp.verify(segredo, Totp.code(segredo, agora.add(const Duration(seconds: 60))), agora), isNull);
    });

    test('recusa passo já usado (replay): só aceita passo MAIOR que lastStep', () {
      final agora = em(1111111111);
      final passo = Totp.stepOf(agora);
      expect(Totp.verify(segredo, Totp.code(segredo, agora), agora, lastStep: passo), isNull);
      expect(Totp.verify(segredo, Totp.code(segredo, agora), agora, lastStep: passo - 1), passo);
    });

    test('recusa código com tamanho errado ou não numérico, sem lançar', () {
      final agora = em(1111111111);
      expect(Totp.verify(segredo, '12345', agora), isNull);
      expect(Totp.verify(segredo, '1234567', agora), isNull);
      expect(Totp.verify(segredo, 'abcdef', agora), isNull);
      expect(Totp.verify(segredo, '', agora), isNull);
    });

    test('ignora espaços em volta do código (apps agrupam "123 456")', () {
      final agora = em(1111111111);
      final c = Totp.code(segredo, agora);
      expect(Totp.verify(segredo, '${c.substring(0, 3)} ${c.substring(3)}', agora), Totp.stepOf(agora));
    });
  });

  test('otpauthUri tem o formato que os autenticadores leem', () {
    final uri = Totp.otpauthUri(secretBase32: 'ABC234', account: 'ACS-001');
    expect(uri, 'otpauth://totp/SinalACS:ACS-001?secret=ABC234&issuer=SinalACS&algorithm=SHA1&digits=6&period=30');
  });
}
```

Run: `cd backend/sinalacs_server && dart test test/unit/totp_test.dart 2>&1 | tail -4`
Expected: **FAIL** de compilação (`totp.dart` não existe).

- [ ] **Step 2: Implementar o `Totp`**

Criar `lib/src/application/auth/totp.dart`:

```dart
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// TOTP (RFC 6238) com SHA-1, 6 dígitos e passo de 30 s — o padrão que todo
/// aplicativo autenticador entende. Função pura: sem relógio, sem I/O.
class Totp {
  Totp._();

  static const period = 30;
  static const digits = 6;
  static const _alfabeto = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  static int stepOf(DateTime at) => at.toUtc().millisecondsSinceEpoch ~/ 1000 ~/ period;

  static String code(Uint8List secret, DateTime at) => _hotp(secret, stepOf(at));

  /// Passo (`stepOf`) em que [code] confere, dentro de ±[window] passos de [at],
  /// ou `null`. Com [lastStep], só aceita passo **maior** que ele: é o que
  /// impede reaproveitar um código já usado dentro da janela (replay).
  static int? verify(
    Uint8List secret,
    String code,
    DateTime at, {
    int window = 1,
    int? lastStep,
  }) {
    final limpo = code.replaceAll(RegExp(r'\s'), '');
    if (limpo.length != digits || !RegExp(r'^\d+$').hasMatch(limpo)) return null;
    final atual = stepOf(at);
    for (var passo = atual - window; passo <= atual + window; passo++) {
      if (lastStep != null && passo <= lastStep) continue;
      if (_hotp(secret, passo) == limpo) return passo;
    }
    return null;
  }

  static String _hotp(Uint8List secret, int counter) {
    final mensagem = ByteData(8)..setUint64(0, counter);
    final h = Hmac(sha1, secret).convert(mensagem.buffer.asUint8List()).bytes;
    final o = h[h.length - 1] & 0x0f;
    final bin = ((h[o] & 0x7f) << 24) | (h[o + 1] << 16) | (h[o + 2] << 8) | h[o + 3];
    return (bin % 1000000).toString().padLeft(digits, '0');
  }

  /// Base32 (RFC 4648, sem preenchimento): o formato do segredo que o aplicativo
  /// autenticador pede quando a pessoa não lê o QR.
  static String base32(Uint8List bytes) {
    var bits = 0;
    var valor = 0;
    final saida = StringBuffer();
    for (final b in bytes) {
      valor = (valor << 8) | b;
      bits += 8;
      while (bits >= 5) {
        saida.write(_alfabeto[(valor >> (bits - 5)) & 31]);
        bits -= 5;
      }
      valor &= (1 << bits) - 1;
    }
    if (bits > 0) saida.write(_alfabeto[(valor << (5 - bits)) & 31]);
    return saida.toString();
  }

  static String otpauthUri({
    required String secretBase32,
    required String account,
    String issuer = 'SinalACS',
  }) =>
      'otpauth://totp/${Uri.encodeComponent(issuer)}:${Uri.encodeComponent(account)}'
      '?secret=$secretBase32&issuer=${Uri.encodeComponent(issuer)}'
      '&algorithm=SHA1&digits=$digits&period=$period';
}
```

Run: `dart test test/unit/totp_test.dart 2>&1 | tail -3`
Expected: `All tests passed!` (todos). Se um vetor da RFC falhar, o defeito é do `_hotp` (endianness do contador ou truncamento dinâmico), nunca do vetor.

- [ ] **Step 3: Modelo, exceções e migração**

`user_credential.spy.yaml`, acrescentar ao fim de `fields:` (antes de `indexes:`):

```yaml
  ### MFA por TOTP (RFC 6238). `null` = sem segredo gravado. O segredo é cifrado
  ### (AES-256-GCM, a mesma chave dos dados clínicos); **nunca** em claro.
  totpSecretEncrypted: String?
  totpKeyVersion: int?
  ### `null` = enrollment começou e não foi confirmado: a MFA ainda NÃO vale.
  totpEnabledAt: DateTime?
  ### Último passo de 30 s aceito. O mesmo código não entra duas vezes (replay).
  totpLastStep: int?
```

Criar as duas exceções copiando o formato de `authentication_failed_exception.spy.yaml`:

```yaml
### O ACS tem MFA ativa, a senha conferiu e faltou o código do autenticador.
### Só é lançada DEPOIS de a senha estar certa: não revela matrícula nem senha.
exception: MfaRequiredException
fields:
  message: String
```

```yaml
### O servidor exige MFA e este ACS ainda não a ativou: a pessoa precisa
### ativar (auth.beginTotpEnrollment) antes de entrar.
exception: MfaEnrollmentRequiredException
fields:
  message: String
```

`models/api/totp_enrollment_start.spy.yaml`:

```yaml
### Início da ativação da MFA: o segredo para o autenticador (base32) e a URI
### `otpauth://` que vira o QR. Volta só nesta resposta; nunca é gravado em claro.
class: TotpEnrollmentStart
fields:
  secretBase32: String
  otpauthUri: String
```

Run: `cd backend/sinalacs_server && serverpod generate 2>&1 | tail -3 && serverpod create-migration 2>&1 | tail -3`
Expected: sem erro; a migração nova só tem `ALTER TABLE "user_credentials" ADD COLUMN ...` das 4 colunas, todas nullable.

- [ ] **Step 4: Testes do serviço (falham: não há MFA no serviço)**

Criar `backend/sinalacs_server/test/unit/institutional_auth_mfa_test.dart`:

```dart
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:sinalacs_server/src/application/audit/audit_trail.dart';
import 'package:sinalacs_server/src/application/auth/institutional_auth_service.dart';
import 'package:sinalacs_server/src/application/auth/password_hasher.dart';
import 'package:sinalacs_server/src/application/auth/totp.dart';
import 'package:sinalacs_server/src/application/auth/totp_secret_vault.dart';
import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/argon2_password_hasher.dart';
import 'package:test/test.dart';

const _acsId = '00000000-0000-4000-8000-000000000002';
const _microAreaId = '00000000-0000-4000-8000-000000000003';
const _senha = 'senha-sintetica-de-teste';

/// Cofre de teste: base64 reversível. Quem prova a cifra real é `health_data_cipher_test.dart`.
class _Cofre implements TotpSecretVault {
  @override
  Future<SealedSecret> seal(Uint8List secret) async =>
      SealedSecret(ciphertextBase64: base64Encode(secret), keyVersion: 1);

  @override
  Future<Uint8List> open(SealedSecret sealed) async => base64Decode(sealed.ciphertextBase64);
}

class _Store implements AcsCredentialStore, TotpStore {
  _Store(this.record);
  AcsCredentialRecord record;
  int enabledCalls = 0;
  int? lastRegisteredStep;

  @override
  Future<AcsCredentialRecord?> findByEnrollmentId(String enrollmentId) async =>
      enrollmentId == 'ACS-001' ? record : null;

  @override
  Future<void> registerFailedAttempt(String acsId,
      {required bool restartCounter,
      required int maxFailedAttempts,
      required DateTime lockUntil,
      required DateTime at}) async {
    final anterior = record.failedAttempts;
    final proximo = restartCounter ? 1 : anterior + 1;
    record = _copia(failedAttempts: proximo, lockedUntil: proximo >= maxFailedAttempts ? lockUntil : null);
  }

  @override
  Future<void> registerSuccessfulLogin(String acsId, DateTime at) async {
    record = _copia(failedAttempts: 0, lockedUntil: null);
  }

  @override
  Future<void> saveCredential(String acsId, PasswordDigest digest, DateTime at) async {}

  @override
  Future<void> saveSecret(String acsId, SealedSecret s, DateTime at) async {
    record = _copia(totp: TotpEnrollment(sealed: s, enabled: false, lastStep: null));
  }

  @override
  Future<void> enable(String acsId, int step, DateTime at) async {
    enabledCalls++;
    final t = record.totp!;
    record = _copia(totp: TotpEnrollment(sealed: t.sealed, enabled: true, lastStep: step));
  }

  @override
  Future<void> registerStep(String acsId, int step) async {
    lastRegisteredStep = step;
    final t = record.totp!;
    record = _copia(totp: TotpEnrollment(sealed: t.sealed, enabled: t.enabled, lastStep: step));
  }

  AcsCredentialRecord _copia({int? failedAttempts, DateTime? lockedUntil, TotpEnrollment? totp}) =>
      AcsCredentialRecord(
        acsId: record.acsId,
        microAreaId: record.microAreaId,
        active: record.active,
        digest: record.digest,
        failedAttempts: failedAttempts ?? record.failedAttempts,
        lockedUntil: failedAttempts != null ? lockedUntil : record.lockedUntil,
        totp: totp ?? record.totp,
      );
}

class _Audit extends AuditTrail {
  @override
  Future<void> record(AuditEvent event) async {}
}

void main() {
  final hasher = Argon2PasswordHasher(memoryKb: 512, iterations: 1, parallelism: 1);
  final cofre = _Cofre();
  final segredo = Uint8List.fromList(List<int>.generate(20, (i) => i + 1));
  final t0 = DateTime.utc(2026, 10, 2, 12);

  Future<({InstitutionalAuthService servico, _Store store})> montar({
    bool comMfa = true,
    bool exigir = false,
  }) async {
    final digest = await hasher.derive(_senha);
    final sealed = await cofre.seal(segredo);
    final store = _Store(AcsCredentialRecord(
      acsId: _acsId,
      microAreaId: _microAreaId,
      active: true,
      digest: digest,
      failedAttempts: 0,
      lockedUntil: null,
      totp: comMfa ? TotpEnrollment(sealed: sealed, enabled: true, lastStep: null) : null,
    ));
    final servico = InstitutionalAuthService(
      store: store,
      hasher: hasher,
      audit: _Audit(),
      totpStore: store,
      vault: cofre,
      requireMfa: exigir,
      random: Random(7),
    );
    return (servico: servico, store: store);
  }

  group('login com MFA ativa', () {
    test('senha certa sem código → MfaRequiredException, sem contar tentativa', () async {
      final m = await montar();
      await expectLater(
        m.servico.login(matricula: 'ACS-001', password: _senha, now: t0),
        throwsA(isA<MfaRequiredException>()),
      );
      expect(m.store.record.failedAttempts, 0);
    });

    test('senha certa + código certo → entra e grava o passo usado', () async {
      final m = await montar();
      final user = await m.servico
          .login(matricula: 'ACS-001', password: _senha, totpCode: Totp.code(segredo, t0), now: t0);
      expect(user.id, _acsId);
      expect(m.store.lastRegisteredStep, Totp.stepOf(t0));
    });

    test('recusa o mesmo código usado duas vezes (replay)', () async {
      final m = await montar();
      final codigo = Totp.code(segredo, t0);
      await m.servico.login(matricula: 'ACS-001', password: _senha, totpCode: codigo, now: t0);

      await expectLater(
        m.servico.login(matricula: 'ACS-001', password: _senha, totpCode: codigo, now: t0),
        throwsA(isA<AuthenticationFailedException>()),
      );
    });

    test('código do passo SEGUINTE ainda entra depois de um login (relógio adiantado)', () async {
      final m = await montar();
      await m.servico.login(matricula: 'ACS-001', password: _senha, totpCode: Totp.code(segredo, t0), now: t0);
      final proximo = t0.add(const Duration(seconds: 30));
      final user = await m.servico
          .login(matricula: 'ACS-001', password: _senha, totpCode: Totp.code(segredo, proximo), now: proximo);
      expect(user.id, _acsId);
    });

    test('código errado conta tentativa e tranca no 5º erro', () async {
      final m = await montar();
      for (var i = 0; i < 4; i++) {
        await expectLater(
          m.servico.login(matricula: 'ACS-001', password: _senha, totpCode: '000000', now: t0),
          throwsA(isA<AuthenticationFailedException>()),
        );
      }
      expect(m.store.record.failedAttempts, 4);
      await expectLater(
        m.servico.login(matricula: 'ACS-001', password: _senha, totpCode: '000000', now: t0),
        throwsA(isA<AuthenticationFailedException>()),
      );
      expect(m.store.record.lockedUntil, isNotNull);
    });

    test('código errado não consome o passo (o certo logo depois entra)', () async {
      final m = await montar();
      await expectLater(
        m.servico.login(matricula: 'ACS-001', password: _senha, totpCode: '000000', now: t0),
        throwsA(isA<AuthenticationFailedException>()),
      );
      expect(m.store.lastRegisteredStep, isNull);
      final user = await m.servico
          .login(matricula: 'ACS-001', password: _senha, totpCode: Totp.code(segredo, t0), now: t0);
      expect(user.id, _acsId);
    });

    test('senha errada continua dando a mensagem única, com ou sem código', () async {
      final m = await montar();
      await expectLater(
        m.servico.login(matricula: 'ACS-001', password: 'errada', totpCode: Totp.code(segredo, t0), now: t0),
        throwsA(isA<AuthenticationFailedException>()),
      );
    });
  });

  group('login sem MFA ativa', () {
    test('com REQUIRE_ACS_MFA desligado, entra só com a senha', () async {
      final m = await montar(comMfa: false);
      expect((await m.servico.login(matricula: 'ACS-001', password: _senha, now: t0)).id, _acsId);
    });

    test('com REQUIRE_ACS_MFA ligado, a senha certa recebe MfaEnrollmentRequiredException', () async {
      final m = await montar(comMfa: false, exigir: true);
      await expectLater(
        m.servico.login(matricula: 'ACS-001', password: _senha, now: t0),
        throwsA(isA<MfaEnrollmentRequiredException>()),
      );
    });

    test('enrollment começado e NÃO confirmado não vale: entra só com a senha', () async {
      final m = await montar(comMfa: false);
      await m.servico.beginTotpEnrollment(matricula: 'ACS-001', password: _senha);
      expect(m.store.record.totp!.enabled, isFalse);
      expect((await m.servico.login(matricula: 'ACS-001', password: _senha, now: t0)).id, _acsId);
    });
  });

  group('ativação', () {
    test('begin devolve segredo e URI; confirm com o código certo ativa', () async {
      final m = await montar(comMfa: false);
      final inicio = await m.servico.beginTotpEnrollment(matricula: 'ACS-001', password: _senha);
      expect(inicio.otpauthUri, startsWith('otpauth://totp/SinalACS:ACS-001?secret=${inicio.secretBase32}'));

      final segredoSorteado = await cofre.open(m.store.record.totp!.sealed);
      await m.servico.confirmTotpEnrollment(
        matricula: 'ACS-001',
        password: _senha,
        code: Totp.code(segredoSorteado, t0),
        now: t0,
      );
      expect(m.store.enabledCalls, 1);
      expect(m.store.record.totp!.enabled, isTrue);
    });

    test('confirm com código errado não ativa e conta tentativa', () async {
      final m = await montar(comMfa: false);
      await m.servico.beginTotpEnrollment(matricula: 'ACS-001', password: _senha);
      await expectLater(
        m.servico.confirmTotpEnrollment(matricula: 'ACS-001', password: _senha, code: '000000', now: t0),
        throwsA(isA<AuthenticationFailedException>()),
      );
      expect(m.store.enabledCalls, 0);
      expect(m.store.record.failedAttempts, 1);
    });

    test('begin com senha errada é recusado como o login (mensagem única)', () async {
      final m = await montar(comMfa: false);
      await expectLater(
        m.servico.beginTotpEnrollment(matricula: 'ACS-001', password: 'errada'),
        throwsA(isA<AuthenticationFailedException>()),
      );
    });

    test('begin com MFA já ativa é recusado (redefinir exige a coordenação)', () async {
      final m = await montar();
      await expectLater(
        m.servico.beginTotpEnrollment(matricula: 'ACS-001', password: _senha),
        throwsA(isA<AuthenticationFailedException>()),
      );
    });
  });
}
```

Run: `cd backend/sinalacs_server && dart test test/unit/institutional_auth_mfa_test.dart 2>&1 | tail -5`
Expected: **FAIL** de compilação (`totp_secret_vault.dart`, `TotpStore`, `TotpEnrollment`, parâmetros `totpCode`/`requireMfa` não existem).

- [ ] **Step 5: Implementar cofre, estado e serviço**

Criar `lib/src/application/auth/totp_secret_vault.dart`:

```dart
import 'dart:typed_data';

/// Segredo TOTP já cifrado, com a versão da chave que o cifrou.
class SealedSecret {
  const SealedSecret({required this.ciphertextBase64, required this.keyVersion});

  final String ciphertextBase64;
  final int keyVersion;
}

/// Cifra e decifra o segredo TOTP. A camada de aplicação não conhece a cifra:
/// quem decide o algoritmo é `infrastructure/` (`HealthCipherTotpVault`).
abstract interface class TotpSecretVault {
  Future<SealedSecret> seal(Uint8List secret);
  Future<Uint8List> open(SealedSecret sealed);
}
```

Criar `lib/src/infrastructure/crypto/health_cipher_totp_vault.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:sinalacs_server/src/application/auth/totp_secret_vault.dart';
import 'package:sinalacs_server/src/infrastructure/crypto/health_data_cipher.dart';

/// Cofre do segredo TOTP sobre a mesma AES-256-GCM dos dados clínicos
/// (`HEALTH_DATA_ENCRYPTION_KEY`). Uma chave a menos para gerir; o custo é que
/// quem a perde, perde também as MFAs — e a redefinição é manual (decisão D6).
class HealthCipherTotpVault implements TotpSecretVault {
  HealthCipherTotpVault(this._cipher);

  final HealthDataCipher _cipher;

  @override
  Future<SealedSecret> seal(Uint8List secret) async {
    final v = await _cipher.encrypt(base64Encode(secret));
    return SealedSecret(ciphertextBase64: v.ciphertextBase64, keyVersion: v.keyVersion);
  }

  @override
  Future<Uint8List> open(SealedSecret sealed) async {
    final claro = await _cipher.decrypt(
      EncryptedValue(ciphertextBase64: sealed.ciphertextBase64, keyVersion: sealed.keyVersion),
    );
    return base64Decode(claro);
  }
}
```

Em `institutional_auth_service.dart`:

1. Imports: `dart:math`, `dart:typed_data`, `totp.dart`, `totp_secret_vault.dart`.
2. Antes de `AcsCredentialRecord`, acrescentar:

```dart
/// Estado da MFA de um ACS, como está gravado.
class TotpEnrollment {
  const TotpEnrollment({required this.sealed, required this.enabled, required this.lastStep});

  final SealedSecret sealed;

  /// `false` = a ativação começou e não foi confirmada: a MFA ainda NÃO vale.
  final bool enabled;
  final int? lastStep;
}

/// Escrita do estado da MFA. Interface à parte de [AcsCredentialStore] de
/// propósito: quem só lê credencial (e os fakes que já existem) não muda.
abstract interface class TotpStore {
  Future<void> saveSecret(String acsId, SealedSecret secret, DateTime at);
  Future<void> enable(String acsId, int step, DateTime at);
  Future<void> registerStep(String acsId, int step);
}
```

3. Em `AcsCredentialRecord`: parâmetro **opcional** `this.totp` no construtor e `final TotpEnrollment? totp;` (`null` = sem MFA).
4. No serviço: parâmetros opcionais do construtor `this.totpStore, this.vault, this.requireMfa = false, Random? random` (`_random = random ?? Random.secure()`), e `static const _invalidCode = 'Código de verificação inválido.';`.
5. **Extrair** a parte do `login` que vai de "normaliza matrícula" até a senha conferida (e o bloqueio decidido) para um método privado `Future<AcsCredentialRecord> _authenticatePassword({required String matricula, required String password, required DateTime at})` que devolve a linha quando a senha confere e **lança** exatamente o que o `login` hoje lança nos outros casos (matrícula inexistente, senha errada, bloqueio, inativo). `login` passa a chamar esse método e seguir. **Refatoração pura:** `dart test test/unit/institutional_auth_service_test.dart` tem de continuar verde **antes** de seguir para o passo 6.
6. Em `login`, novo parâmetro `String? totpCode`, e **depois** de `_authenticatePassword` e **antes** de `store.registerSuccessfulLogin`:

```dart
    final totp = record.totp;
    if (totp != null && totp.enabled) {
      final codigo = totpCode?.trim() ?? '';
      if (codigo.isEmpty) {
        // A senha conferiu; falta o código. Não é falha: não conta tentativa.
        throw MfaRequiredException(message: 'Informe o código do aplicativo autenticador.');
      }
      final segredo = await vault!.open(totp.sealed);
      final passo = Totp.verify(segredo, codigo, at, lastStep: totp.lastStep);
      if (passo == null) {
        await _registrarFalha(record, at);
        await _recordAudit(record.acsId, 'denied_totp');
        throw AuthenticationFailedException(message: _invalidCode);
      }
      await totpStore!.registerStep(record.acsId, passo);
    } else if (requireMfa) {
      await _recordAudit(record.acsId, 'denied_mfa_not_enrolled');
      throw MfaEnrollmentRequiredException(
        message: 'Ative a verificação em duas etapas antes de entrar.',
      );
    }
```

`_registrarFalha(record, at)` chama `store.registerFailedAttempt(record.acsId, restartCounter: <mesma regra do ramo de senha errada: bloqueio vencido recomeça o contador>, maxFailedAttempts: maxFailedAttempts, lockUntil: at.add(lockDuration), at: at)` — extraia do ramo da senha errada o cálculo de `restartCounter` para um helper compartilhado e use-o nos dois lugares (o código atual está no ramo `if (!await hasher.matches(...))`). Se `vault`/`totpStore` forem `null` com MFA ativa, é erro de montagem: `StateError('MFA ativa sem cofre configurado')`.

7. Dois métodos públicos:

```dart
  /// Começa a ativação da MFA. Exige matrícula **e senha** (o ACS ainda não tem
  /// token) e conta tentativa errada como o login. Só grava o segredo como
  /// "pendente": a MFA vale depois de [confirmTotpEnrollment].
  Future<TotpEnrollmentStart> beginTotpEnrollment({
    required String matricula,
    required String password,
    DateTime? now,
  }) async {
    final at = (now ?? DateTime.now()).toUtc();
    final record = await _authenticatePassword(matricula: matricula, password: password, at: at);
    if (record.totp?.enabled ?? false) {
      throw AuthenticationFailedException(
        message: 'A verificação em duas etapas já está ativa. Peça a redefinição à coordenação.',
      );
    }
    final bytes = Uint8List.fromList(List<int>.generate(20, (_) => _random.nextInt(256)));
    await totpStore!.saveSecret(record.acsId, await vault!.seal(bytes), at);
    final base32 = Totp.base32(bytes);
    return TotpEnrollmentStart(
      secretBase32: base32,
      otpauthUri: Totp.otpauthUri(secretBase32: base32, account: matricula.trim()),
    );
  }

  /// Confirma a ativação com um código válido do segredo pendente.
  Future<void> confirmTotpEnrollment({
    required String matricula,
    required String password,
    required String code,
    DateTime? now,
  }) async {
    final at = (now ?? DateTime.now()).toUtc();
    final record = await _authenticatePassword(matricula: matricula, password: password, at: at);
    final totp = record.totp;
    if (totp == null || totp.enabled) {
      throw AuthenticationFailedException(message: 'Não há ativação pendente para esta matrícula.');
    }
    final passo = Totp.verify(await vault!.open(totp.sealed), code, at);
    if (passo == null) {
      await _registrarFalha(record, at);
      await _recordAudit(record.acsId, 'denied_totp_enrollment');
      throw AuthenticationFailedException(message: _invalidCode);
    }
    await totpStore!.enable(record.acsId, passo, at);
    await _recordAudit(record.acsId, 'mfa_enabled');
  }
```

Run: `cd backend/sinalacs_server && dart test test/unit/institutional_auth_service_test.dart test/unit/institutional_auth_mfa_test.dart test/unit/totp_test.dart 2>&1 | tail -4`
Expected: `All tests passed!` (os antigos continuam verdes e os novos também). Qualquer teste **antigo** vermelho = a refatoração do passo 5 mudou comportamento: desfaça e refaça menor.

- [ ] **Step 6: ORM, endpoint, runtime e configuração**

`orm_acs_credential_store.dart` (siga o estilo do próprio arquivo, que já faz o `UPDATE` de tentativas): `findByEnrollmentId` passa a preencher `totp:` quando `credential.totpSecretEncrypted != null` — `TotpEnrollment(sealed: SealedSecret(ciphertextBase64: ..., keyVersion: credential.totpKeyVersion!), enabled: credential.totpEnabledAt != null, lastStep: credential.totpLastStep)`; a classe passa a implementar também `TotpStore`:

```dart
  @override
  Future<void> saveSecret(String acsId, SealedSecret secret, DateTime at) async {
    await _setColumns(acsId, (t) => [
          t.totpSecretEncrypted.set(secret.ciphertextBase64),
          t.totpKeyVersion.set(secret.keyVersion),
          t.totpEnabledAt.set(null),
          t.totpLastStep.set(null),
        ]);
  }

  @override
  Future<void> enable(String acsId, int step, DateTime at) async {
    await _setColumns(acsId, (t) => [t.totpEnabledAt.set(at), t.totpLastStep.set(step)]);
  }

  @override
  Future<void> registerStep(String acsId, int step) async {
    await _setColumns(acsId, (t) => [t.totpLastStep.set(step)]);
  }
```

com `_setColumns` usando `UserCredential.db.updateWhere(session(), columnValues: columns, where: (t) => t.userId.equals(UuidValue.fromString(acsId)))` — **confira** no arquivo como o store já obtém a sessão (`session: () => session`) e como escreve; se `updateWhere` não existir nesta versão do Serverpod, use o mesmo mecanismo (SQL nomeado) que `registerSuccessfulLogin` usa.

`alert_runtime.dart`, em `institutionalAuthServiceFor`:

```dart
  InstitutionalAuthService institutionalAuthServiceFor(Session session) {
    final store = OrmAcsCredentialStore(session: () => session);
    return InstitutionalAuthService(
      store: store,
      hasher: passwordHasher,
      audit: auditTrailFor(session),
      totpStore: store,
      vault: HealthCipherTotpVault(healthDataCipher),
      requireMfa: config.requireAcsMfa,
    );
  }
```

`auth_endpoint.dart`: `loginInstitutional` ganha `String? totpCode` (repassado ao serviço) e acrescentar:

```dart
  /// Começa a ativação da MFA do ACS (RF07). Sem token: o ACS prova matrícula e senha.
  Future<TotpEnrollmentStart> beginTotpEnrollment(
    Session session, {
    required String matricula,
    required String password,
  }) =>
      AlertRuntime.instance
          .institutionalAuthServiceFor(session)
          .beginTotpEnrollment(matricula: matricula, password: password);

  /// Confirma a ativação com o primeiro código do autenticador.
  Future<void> confirmTotpEnrollment(
    Session session, {
    required String matricula,
    required String password,
    required String code,
  }) =>
      AlertRuntime.instance
          .institutionalAuthServiceFor(session)
          .confirmTotpEnrollment(matricula: matricula, password: password, code: code);
```

`app_config.dart`: campo `final bool requireAcsMfa;` e, no `fromEnvironment`, seguindo `enableDevLogin`: `requireAcsMfa: environment['REQUIRE_ACS_MFA'] != null ? environment['REQUIRE_ACS_MFA'] == 'true' : environment['APP_ENV'] != 'development'` (padrão **ligado fora de development**). Teste em `test/unit/app_config_test.dart`: em `development` sem a variável é `false`; com `APP_ENV=production` sem a variável é `true`; `REQUIRE_ACS_MFA=false` explícito desliga mesmo em produção.

`.env.example` e `docker-compose.yml` (serviço do servidor): `REQUIRE_ACS_MFA: ${REQUIRE_ACS_MFA:-false}` com a nota "em produção o padrão é `true`; este default é só da stack local".

- [ ] **Step 7: Gerar, analisar e rodar a suíte do backend**

Run: `cd backend/sinalacs_server && serverpod generate 2>&1 | tail -2 && dart analyze 2>&1 | tail -2 && dart test 2>&1 | tail -3`
Expected: `No issues found!`; `All tests passed!`. A suíte completa usa o banco de teste (`docker compose --profile test up -d postgres-test`); a contagem total sobe pelos testes novos (anotar no ledger o antes/depois).

- [ ] **Step 8: Documentar e commitar**

`spec/lgpd_data_audit.md`: acrescentar as 4 colunas de `user_credentials` (`totpSecretEncrypted` = segredo de autenticação, cifrado; `totpKeyVersion`, `totpEnabledAt`, `totpLastStep` = metadado de segurança) e **re-medir** a contagem de tabelas/colunas. `backend/CLAUDE.md`: parágrafo sobre `REQUIRE_ACS_MFA`, o cofre sobre a chave dos dados clínicos e a redefinição manual (zerar as quatro colunas).

```bash
git add backend spec .env.example docker-compose.yml
git commit -m "feat(auth): MFA por TOTP no login institucional do ACS (RF07, LGPD-RT06), com replay barrado"
```

---

### Task 6: MFA — app do ACS e prova no emulador

**Files:**
- Modify: `apps/acs/lib/core/network/backend_client.dart`, `apps/acs/lib/app/app.dart` (LoginScreen)
- Create: `apps/acs/lib/app/mfa_enrollment_screen.dart`
- Create: `apps/acs/integration_test/support/totp.dart`, `apps/acs/test/support/totp.dart` (mesma implementação mínima, só para teste)
- Test: `apps/acs/test/mfa_login_test.dart`, `apps/acs/test/totp_support_test.dart`
- Modify: `apps/acs/test/support/fakes.dart`, `apps/acs/integration_test/full_journey_e2e.dart`, `PROGRESS.md`, `apps/CLAUDE.md`

**Interfaces:**
- Consumes (Task 5): RPC `auth.loginInstitutional(…, totpCode:)`, `auth.beginTotpEnrollment`, `auth.confirmTotpEnrollment`; exceções `MfaRequiredException`, `MfaEnrollmentRequiredException`; `TotpEnrollmentStart{secretBase32, otpauthUri}`. `qr_flutter` (`QrImageView`, já usado em `invite_screen.dart`).
- Produces:
  - `AcsBackend.login({required String matricula, required String senha, String? totpCode})`
  - `AcsBackend.beginTotpEnrollment({required String matricula, required String senha}) -> Future<TotpEnrollmentStart>`; `AcsBackend.confirmTotpEnrollment({required String matricula, required String senha, required String code}) -> Future<void>`
  - `class MfaCodeRequired extends BackendFailure`, `class MfaEnrollmentRequired extends BackendFailure`
  - `class MfaEnrollmentScreen` com chaves `mfa_secret`, `mfa_code_field`, `mfa_confirm_button`.
  - `String Totp.code(Uint8List secret, DateTime at)` em `test/support/totp.dart` e `integration_test/support/totp.dart`.

- [ ] **Step 1: Testes do app (falham: não há campo de código)**

Em `test/support/fakes.dart`, `FakeAcsBackend`: o `login` passa a aceitar `String? totpCode`, guardar `lastTotpCode` e consultar `mfaRequired`/`mfaEnrollmentRequired`:

```dart
  /// Simula o servidor com MFA ativa: sem [totpCode] igual a [expectedTotpCode], levanta [MfaCodeRequired].
  String? expectedTotpCode;
  bool mfaEnrollmentRequired = false;
  String? lastTotpCode;
  TotpEnrollmentStart enrollmentStart =
      TotpEnrollmentStart(secretBase32: 'GEZDGNBVGY3TQOJQ', otpauthUri: 'otpauth://totp/SinalACS:ACS-001?secret=GEZDGNBVGY3TQOJQ');
  String? confirmedCode;

  @override
  Future<void> confirmTotpEnrollment({required String matricula, required String senha, required String code}) async {
    confirmedCode = code;
  }

  @override
  Future<TotpEnrollmentStart> beginTotpEnrollment({required String matricula, required String senha}) async =>
      enrollmentStart;
```

e, no início do `login` do fake (depois de registrar matrícula/senha):

```dart
    lastTotpCode = totpCode;
    if (mfaEnrollmentRequired) throw const MfaEnrollmentRequired();
    if (expectedTotpCode != null && totpCode != expectedTotpCode) {
      throw totpCode == null ? const MfaCodeRequired() : const BackendFailure('Código de verificação inválido.', isRecoverable: false);
    }
```

Criar `apps/acs/test/mfa_login_test.dart` (use `entrar(tester)` e o estilo de `login_flow_test.dart`):

```dart
// 1. MFA exigida: depois de matrícula+senha, aparece o campo de código e o painel NÃO abre.
testWidgets('pede o código do autenticador depois de matrícula e senha', (tester) async {
  final backend = FakeAcsBackend()..expectedTotpCode = '123456';
  await tester.pumpWidget(SinalAcsApp(backend: backend, feedBuilder: (q) => FakeAlertFeed(q)));
  await entrar(tester);
  await tester.pumpAndSettle();

  expect(find.byKey(const Key('totp_field')), findsOneWidget);
  expect(find.byKey(const Key('login_button')), findsOneWidget, reason: 'o painel não abriu');
});

// 2. Código certo: entra, e o app reenviou matrícula+senha COM o código.
testWidgets('com o código certo, entra', (tester) async {
  final backend = FakeAcsBackend()..expectedTotpCode = '123456';
  await tester.pumpWidget(SinalAcsApp(backend: backend, feedBuilder: (q) => FakeAlertFeed(q)));
  await entrar(tester);
  await tester.pumpAndSettle();

  await tester.enterText(find.byKey(const Key('totp_field')), '123456');
  await tester.tap(find.byKey(const Key('login_button')));
  await tester.pumpAndSettle();

  expect(backend.lastTotpCode, '123456');
  expect(find.byKey(const Key('login_button')), findsNothing, reason: 'o painel abriu');
});

// 3. Código errado: erro visível, painel fechado, campo continua.
testWidgets('com o código errado, mostra o erro e fica no login', (tester) async {
  final backend = FakeAcsBackend()..expectedTotpCode = '123456';
  await tester.pumpWidget(SinalAcsApp(backend: backend, feedBuilder: (q) => FakeAlertFeed(q)));
  await entrar(tester);
  await tester.pumpAndSettle();

  await tester.enterText(find.byKey(const Key('totp_field')), '000000');
  await tester.tap(find.byKey(const Key('login_button')));
  await tester.pumpAndSettle();

  expect(find.byKey(const Key('login_error')), findsOneWidget);
  expect(find.byKey(const Key('totp_field')), findsOneWidget);
});

// 4. Servidor exige MFA e o ACS não a tem: vai para a tela de ativação, com segredo e campo de código.
testWidgets('sem MFA ativada, leva à ativação e confirma com o código', (tester) async {
  final backend = FakeAcsBackend()..mfaEnrollmentRequired = true;
  await tester.pumpWidget(SinalAcsApp(backend: backend, feedBuilder: (q) => FakeAlertFeed(q)));
  await entrar(tester);
  await tester.pumpAndSettle();

  expect(find.byKey(const Key('mfa_secret')), findsOneWidget);
  expect(find.textContaining('GEZDGNBVGY3TQOJQ'), findsOneWidget);

  await tester.enterText(find.byKey(const Key('mfa_code_field')), '654321');
  await tester.tap(find.byKey(const Key('mfa_confirm_button')));
  await tester.pumpAndSettle();

  expect(backend.confirmedCode, '654321');
  // Voltou ao login, pronto para entrar de novo (agora com MFA).
  expect(find.byKey(const Key('login_button')), findsOneWidget);
});

// 5. O código é só dígitos: o campo recusa letras e passa de 6.
testWidgets('o campo de código aceita só 6 dígitos', (tester) async {
  final backend = FakeAcsBackend()..expectedTotpCode = '123456';
  await tester.pumpWidget(SinalAcsApp(backend: backend, feedBuilder: (q) => FakeAlertFeed(q)));
  await entrar(tester);
  await tester.pumpAndSettle();

  await tester.enterText(find.byKey(const Key('totp_field')), '12ab34567');

  final campo = tester.widget<TextField>(find.byKey(const Key('totp_field')));
  expect(campo.controller!.text, '123456', reason: 'letras caem fora e o 7º dígito não entra');
  expect(campo.keyboardType, TextInputType.number);
});
```

Run: `cd apps/acs && flutter test test/mfa_login_test.dart 2>&1 | tail -4`
Expected: **FAIL** de compilação (`MfaCodeRequired`, `totpCode` não existem).

- [ ] **Step 2: Implementar no cliente**

`backend_client.dart`: `AcsBackend.login` ganha `String? totpCode`; acrescentar os dois métodos novos à interface, à classe que recusa tudo (`_recusar()`) e ao `BackendClient`; as duas falhas tipadas:

```dart
/// O ACS tem MFA ativa e a senha conferiu: falta o código do autenticador.
class MfaCodeRequired extends BackendFailure {
  const MfaCodeRequired() : super('Informe o código do aplicativo autenticador.');
}

/// O servidor exige MFA e este ACS ainda não a ativou.
class MfaEnrollmentRequired extends BackendFailure {
  const MfaEnrollmentRequired() : super('Ative a verificação em duas etapas antes de entrar.', isRecoverable: false);
}
```

No `BackendClient.login`, repassar `totpCode:` a `_client.auth.loginInstitutional(...)`; e no `_guard` (onde `AuthenticationFailedException` vira `BackendFailure`, ~linha 411), antes dele:

```dart
    } on MfaRequiredException {
      throw const MfaCodeRequired();
    } on MfaEnrollmentRequiredException {
      throw const MfaEnrollmentRequired();
```

`beginTotpEnrollment`/`confirmTotpEnrollment` chamam `_client.auth.beginTotpEnrollment(matricula:, password:)` / `confirmTotpEnrollment(matricula:, password:, code:)` **sem** `_requireToken()` (não há token) e dentro de `_guard`. A credencial segue só em memória (`_credentials`): nada novo é gravado em disco.

- [ ] **Step 3: Implementar a tela de login e a de ativação**

`_LoginScreenState` (`app.dart` ~161): estado `bool _pedeCodigo = false;` e `final _totp = TextEditingController();` (descartar no `dispose`); no tratamento da falha do `_enter`:

```dart
    } on MfaCodeRequired {
      if (!mounted) return;
      setState(() { _pedeCodigo = true; _loginError = null; _entering = false; });
    } on MfaEnrollmentRequired {
      if (!mounted) return;
      setState(() => _entering = false);
      final ativou = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => MfaEnrollmentScreen(
          backend: widget.backend,
          matricula: _matricula.text.trim(),
          senha: _senha.text,
        ),
      ));
      if (ativou == true && mounted) {
        setState(() => _pedeCodigo = true);
      }
      return;
    }
```

`_enter` passa `totpCode: _pedeCodigo ? _totp.text.trim() : null` ao `backend.login`. O campo (só quando `_pedeCodigo`), com os mesmos espaçamentos dos outros campos:

```dart
              if (_pedeCodigo) ...[
                const SizedBox(height: 12),
                TextField(
                  key: const Key('totp_field'),
                  controller: _totp,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Código do autenticador (6 dígitos)'),
                  onSubmitted: (_) => _enter(),
                ),
              ],
```

(`FilteringTextInputFormatter` vem de `package:flutter/services.dart`.) Se a pessoa **mudar** matrícula ou senha com o campo aberto, `setState(() => _pedeCodigo = false)` e limpar `_totp` — o código pertence à sessão que o pediu.

Criar `lib/app/mfa_enrollment_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_client/sinalacs_client.dart' show TotpEnrollmentStart;

/// Ativação da verificação em duas etapas (RF07 / LGPD-RT06).
///
/// Sem token: o ACS acabou de provar matrícula e senha. O segredo aparece só
/// aqui, em QR e em texto, e **não** é gravado no aparelho.
class MfaEnrollmentScreen extends StatefulWidget {
  const MfaEnrollmentScreen({
    super.key,
    required this.backend,
    required this.matricula,
    required this.senha,
  });

  final AcsBackend backend;
  final String matricula;
  final String senha;

  @override
  State<MfaEnrollmentScreen> createState() => _MfaEnrollmentScreenState();
}

class _MfaEnrollmentScreenState extends State<MfaEnrollmentScreen> {
  final _codigo = TextEditingController();
  TotpEnrollmentStart? _inicio;
  String? _erro;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  @override
  void dispose() {
    _codigo.dispose();
    super.dispose();
  }

  Future<void> _iniciar() async {
    try {
      final inicio = await widget.backend.beginTotpEnrollment(matricula: widget.matricula, senha: widget.senha);
      if (mounted) setState(() => _inicio = inicio);
    } on BackendFailure catch (falha) {
      if (mounted) setState(() => _erro = falha.message);
    }
  }

  Future<void> _confirmar() async {
    if (_ocupado) return;
    setState(() { _ocupado = true; _erro = null; });
    try {
      await widget.backend.confirmTotpEnrollment(
        matricula: widget.matricula,
        senha: widget.senha,
        code: _codigo.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on BackendFailure catch (falha) {
      if (mounted) setState(() { _erro = falha.message; _ocupado = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final inicio = _inicio;
    return Scaffold(
      appBar: AppBar(title: const Text('Verificação em duas etapas')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text('Leia o QR no aplicativo autenticador (ou digite a chave) e informe o código de 6 dígitos que ele mostrar.'),
          const SizedBox(height: 16),
          if (inicio == null && _erro == null) const Center(child: CircularProgressIndicator()),
          if (inicio != null) ...[
            Center(child: QrImageView(data: inicio.otpauthUri, size: 200, backgroundColor: Colors.white)),
            const SizedBox(height: 12),
            SelectableText(inicio.secretBase32, key: const Key('mfa_secret')),
          ],
          if (_erro != null)
            Semantics(liveRegion: true, child: Text(_erro!, key: const Key('mfa_error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: 16),
          TextField(
            key: const Key('mfa_code_field'),
            controller: _codigo,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Código de 6 dígitos'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('mfa_confirm_button'),
            onPressed: inicio == null || _ocupado ? null : _confirmar,
            style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
            child: const Text('Ativar'),
          ),
        ],
      ),
    );
  }
}
```

Importar a tela em `app.dart` (`import 'package:sinalacs_acs/app/mfa_enrollment_screen.dart';`). O QR é **branco com módulos escuros** por exigência de leitura (`invite_screen.dart` faz igual): não usar token de tema para ele.

Run: `cd apps/acs && flutter analyze 2>&1 | tail -2 && flutter test test/mfa_login_test.dart 2>&1 | tail -3`
Expected: `No issues found!`; `All tests passed!` (5 testes). Depois a suíte inteira: `flutter test 2>&1 | tail -2` com **≥ 247** (242 + 5); os testes de login que chamam `login(...)` sem `totpCode` seguem verdes (parâmetro opcional).

- [ ] **Step 2b: Teste de fonte ampliada nas telas novas**

Em `test/text_scale_test.dart`, acrescentar caso a 130% e 200% que abre `MfaEnrollmentScreen` (com o `FakeAcsBackend`) em 360x800 e usa `percorrerTelaInteira` do harness da Task 1 anterior (`test/support/layout_harness.dart`), e outro com o campo de código aberto no login. Se estourar, corrigir com `Flexible`/rolagem como no plano anterior; sem `withClampedTextScaling`.

- [ ] **Step 4: Gerador de código para os testes (RFC 6238, com os mesmos vetores)**

Criar `apps/acs/test/support/totp.dart` e copiar byte a byte para `apps/acs/integration_test/support/totp.dart` (o `integration_test` não importa de `test/`):

```dart
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Gerador TOTP (RFC 6238, SHA-1, 6 dígitos, 30 s) SÓ para testes: a prova de
/// MFA no emulador precisa produzir o código que o autenticador produziria.
String totpCode(Uint8List secret, DateTime at) {
  final passo = at.toUtc().millisecondsSinceEpoch ~/ 1000 ~/ 30;
  final mensagem = ByteData(8)..setUint64(0, passo);
  final h = Hmac(sha1, secret).convert(mensagem.buffer.asUint8List()).bytes;
  final o = h[h.length - 1] & 0x0f;
  final bin = ((h[o] & 0x7f) << 24) | (h[o + 1] << 16) | (h[o + 2] << 8) | h[o + 3];
  return (bin % 1000000).toString().padLeft(6, '0');
}

/// Decodifica base32 (RFC 4648, sem preenchimento) — o que o servidor entrega em `secretBase32`.
Uint8List base32Decode(String texto) {
  const alfabeto = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  var bits = 0;
  var valor = 0;
  final saida = <int>[];
  for (final c in texto.toUpperCase().split('')) {
    final i = alfabeto.indexOf(c);
    if (i < 0) continue;
    valor = (valor << 5) | i;
    bits += 5;
    if (bits >= 8) {
      saida.add((valor >> (bits - 8)) & 0xff);
      bits -= 8;
      valor &= (1 << bits) - 1;
    }
  }
  return Uint8List.fromList(saida);
}
```

Garantir `crypto` em `apps/acs/pubspec.yaml` (`dependencies:` — já está: `crypto: ^3.0.0`). Teste `test/totp_support_test.dart`: `totpCode(ascii('12345678901234567890'), DateTime.fromMillisecondsSinceEpoch(59000, isUtc: true)) == '287082'` e `base32Decode('GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ')` igual aos 20 bytes ASCII. Run: `flutter test test/totp_support_test.dart 2>&1 | tail -2` → `All tests passed!`.

- [ ] **Step 5: Prova no emulador, contra o servidor real, pela tela**

O relé entrega a credencial **uma vez** (memorizada por `acsCredentialFromRelay`) e a ativação persiste no banco da execução: este teste vai **por último** em `integration_test/full_journey_e2e.dart`, depois de todos os que fazem login só com a senha. O compose de e2e mantém `REQUIRE_ACS_MFA: "false"` (os outros testes entram só com a senha), então o teste **liga a MFA pelo RPC** e só então prova o login **pela tela**, com o campo de código. A tela de ativação (`mfa_secret`) fica provada pelos testes de widget do Step 1; registre isso como `Ruling:` no ledger. (Imports a acrescentar: `support/totp.dart`.)

```dart
  testWidgets('MFA: com a verificação ativa, o login pela tela pede e aceita o código', (tester) async {
    final ca = (await rootBundle.load(BackendConfig.rpcCaAsset)).buffer.asUint8List();
    final backend = BackendClient(trustedCaBytes: ca);
    addTearDown(backend.close);
    const host = String.fromEnvironment('SINALACS_HOST', defaultValue: 'https://10.0.2.2/');
    final cliente = api.Client(host, securityContext: SecurityContext()..setTrustedCertificatesBytes(ca))
      ..connectivityMonitor = null;
    addTearDown(cliente.close);
    final cred = await acsCredentialFromRelay();

    // 1) Liga a MFA pelo RPC: matrícula + senha + o código do segredo recém-sorteado.
    final inicio = await cliente.auth.beginTotpEnrollment(matricula: cred.matricula, password: cred.senha);
    final segredo = base32Decode(inicio.secretBase32);
    await cliente.auth.confirmTotpEnrollment(
      matricula: cred.matricula,
      password: cred.senha,
      code: totpCode(segredo, DateTime.now()),
    );

    // 2) Login pela tela: matrícula + senha → o app pede o código e o painel NÃO abre.
    await tester.pumpWidget(SinalAcsApp(backend: backend));
    await tester.enterText(find.byKey(const Key('matricula_field')), cred.matricula);
    await tester.enterText(find.byKey(const Key('senha_field')), cred.senha);
    await tester.tap(find.byKey(const Key('login_button')));
    await _pumpUntil(tester, () => find.byKey(const Key('totp_field')).evaluate().isNotEmpty);
    expect(find.byKey(const Key('login_button')), findsOneWidget, reason: 'o painel não pode abrir sem o código');

    // 3) O código da ativação já foi usado (replay barrado): entra com o do PASSO SEGUINTE,
    //    que a janela de ±1 aceita.
    await tester.enterText(
      find.byKey(const Key('totp_field')),
      totpCode(segredo, DateTime.now().add(const Duration(seconds: 30))),
    );
    await tester.tap(find.byKey(const Key('login_button')));
    await _pumpUntil(tester, () => find.byKey(const Key('login_button')).evaluate().isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
```

Run: `./scripts/qa/acs_full_e2e.sh 2>&1 | grep -E "OK —|Some tests|Expected|Actual|rc="; docker compose up -d`
Expected: `OK — jornada completa do ACS contra o banco de teste` (reconstruir a imagem do servidor antes, como na Task 3).

- [ ] **Step 6: Documentar e commitar**

`PROGRESS.md`: "MFA/TOTP do ACS entregue (RF07, LGPD-RT06): TOTP no `loginInstitutional`, ativação por matrícula+senha+código, replay barrado, exigida fora de `development` (`REQUIRE_ACS_MFA`); refresh token e redefinição por coordenador seguem abertos"; remover "MFA" de "Continua aberto" e de "adiados". `apps/CLAUDE.md`: parágrafo curto do fluxo (campo de código no login, `MfaEnrollmentScreen`, `acsCredentialFromRelay`, código do passo seguinte no e2e).

```bash
git add apps/acs docker-compose.e2e.yml PROGRESS.md apps/CLAUDE.md
git commit -m "feat(acs): login com código TOTP e tela de ativação da verificação em duas etapas"
```

---

### Task 7: mTLS no broker — certificados de cliente e prova de recusa

**Files:**
- Modify: `infra/docker/mosquitto/init.sh`, `infra/docker/mosquitto/mosquitto.conf`
- Create: `scripts/qa/mtls_invariants.sh`
- Modify: `docker-compose.yml`, `.env.example`
- Modify: `backend/sinalacs_server/lib/src/config/app_config.dart`, `backend/sinalacs_server/lib/src/infrastructure/mqtt/mqtt_alert_dispatcher.dart`
- Test: `backend/sinalacs_server/test/unit/app_config_test.dart`
- Modify: `spec/stack.md` (nota de mTLS), `backend/CLAUDE.md`, `CLAUDE.md`

**Interfaces:**
- Consumes: CA de desenvolvimento em `infra/docker/mosquitto/runtime/certs/ca.{crt,key}`; usuários MQTT `backend` e `acs-area-12`.
- Produces: `runtime/certs/backend.{crt,key}` e `runtime/certs/acs-area-12.{crt,key}` (CN = usuário MQTT, `extendedKeyUsage=clientAuth`); variáveis `MQTT_CLIENT_CERT_PATH` e `MQTT_CLIENT_KEY_PATH` do backend; `AppConfig.mqttClientCertificatePath/mqttClientKeyPath`.

- [ ] **Step 1: Escrever o verificador de mTLS (falha: o broker aceita cliente sem certificado)**

Criar `scripts/qa/mtls_invariants.sh` e `chmod +x`:

```bash
#!/usr/bin/env bash
#
# O broker MQTT exige certificado de cliente (mTLS) E mantém a senha.
#
#   ./scripts/qa/mtls_invariants.sh
#
# Precisa da stack de desenvolvimento no ar (docker compose up) e do .env.
# Quatro casos, cada um uma publicação de `mosquitto_pub` na porta 8883:
#   A) senha certa, SEM certificado de cliente             -> RECUSADO
#   B) senha certa + certificado assinado pela CA do broker -> ACEITO
#   C) senha certa + certificado de OUTRA CA                -> RECUSADO
#   D) certificado certo + senha errada                     -> RECUSADO
# Nenhum segredo é impresso.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
if [[ -f .env ]]; then set -a; source .env; set +a; fi
: "${MQTT_BACKEND_PASSWORD:?exporte MQTT_BACKEND_PASSWORD ou rode ./scripts/dev/bootstrap_env.sh}"

certs="$repo_root/infra/docker/mosquitto/runtime/certs"
for f in ca.crt backend.crt backend.key; do
  [[ -f "$certs/$f" ]] || { echo "erro: $certs/$f não existe (a stack subiu com o init.sh novo?)." >&2; exit 4; }
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Certificado "de fora": CA própria e uma folha dela, com o mesmo CN de um usuário real.
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -keyout "$tmp/fora-ca.key" -out "$tmp/fora-ca.crt" \
  -subj '/CN=ca-de-fora' >/dev/null 2>&1
openssl req -newkey rsa:2048 -nodes -keyout "$tmp/fora.key" -out "$tmp/fora.csr" -subj '/CN=backend' >/dev/null 2>&1
printf 'extendedKeyUsage=clientAuth\n' >"$tmp/fora.ext"
openssl x509 -req -days 2 -in "$tmp/fora.csr" -CA "$tmp/fora-ca.crt" -CAkey "$tmp/fora-ca.key" \
  -CAcreateserial -extfile "$tmp/fora.ext" -out "$tmp/fora.crt" >/dev/null 2>&1
chmod 644 "$tmp"/*

publicar() { # publicar <senha> [--cert X --key Y]   (devolve o código de saída)
  local senha="$1"; shift
  timeout 20 docker run --rm --network host \
    -v "$certs:/c:ro" -v "$tmp:/f:ro" -e MQTT_PW="$senha" eclipse-mosquitto:2 \
    sh -c 'mosquitto_pub -h localhost -p 8883 --cafile /c/ca.crt -u backend -P "$MQTT_PW" \
           -t sinalacs/v1/mtls/probe -m x '"$*" >/dev/null 2>&1
}

falhas=0
esperar() { # esperar <aceito|recusado> <nome> <comando...>
  local quer="$1" nome="$2"; shift 2
  if "$@"; then got=aceito; else got=recusado; fi
  if [[ "$got" == "$quer" ]]; then echo "ok:    $nome ($got)"; else echo "FALHOU: $nome — esperava $quer, foi $got"; falhas=$((falhas + 1)); fi
}

esperar recusado "A) senha certa, sem certificado de cliente" publicar "$MQTT_BACKEND_PASSWORD"
esperar aceito   "B) senha certa + certificado da CA do broker" \
  publicar "$MQTT_BACKEND_PASSWORD" --cert /c/backend.crt --key /c/backend.key
esperar recusado "C) certificado de outra CA" \
  publicar "$MQTT_BACKEND_PASSWORD" --cert /f/fora.crt --key /f/fora.key
esperar recusado "D) certificado certo, senha errada" \
  publicar "senha-errada" --cert /c/backend.crt --key /c/backend.key

[[ "$falhas" -eq 0 ]] && echo "OK — o broker exige certificado de cliente e mantém a senha" || { echo "$falhas falha(s)"; exit 1; }
```

- [ ] **Step 2: Ver falhar**

Run: `./scripts/qa/mtls_invariants.sh; echo rc=$?`
Expected: `erro: .../runtime/certs/backend.crt não existe` e `rc=4` (o `init.sh` ainda não emite certificado de cliente). Esse é o vermelho do passo; depois do Step 3 o vermelho passa a ser o caso A aceito.

- [ ] **Step 3: Emitir certificados de cliente no `init.sh`**

Em `infra/docker/mosquitto/init.sh`, depois do bloco do certificado do servidor e **antes** de `rm -f "$password_file"`, acrescentar:

```sh
client_days=397

# Certificado de CLIENTE (mTLS): CN = o usuário MQTT, assinado pela mesma CA do
# servidor, só para autenticação de cliente. Renova quando vence, quando a CA
# mudou (o `verify` falha) ou quando não existe — mesma regra do servidor.
issue_client() {
  cn="$1"
  if [ -f "$certs_dir/$cn.crt" ] && [ -f "$certs_dir/$cn.key" ] \
     && openssl x509 -in "$certs_dir/$cn.crt" -noout -checkend 86400 >/dev/null 2>&1 \
     && openssl verify -CAfile "$certs_dir/ca.crt" "$certs_dir/$cn.crt" >/dev/null 2>&1; then
    return 0
  fi
  echo "Gerando certificado de cliente para $cn..."
  printf 'basicConstraints=CA:FALSE\nkeyUsage=digitalSignature\nextendedKeyUsage=clientAuth\n' \
    > "$certs_dir/$cn.ext"
  openssl req -newkey rsa:2048 -nodes -keyout "$certs_dir/$cn.key" \
    -out "$certs_dir/$cn.csr" -subj "/CN=$cn"
  openssl x509 -req -days "$client_days" -in "$certs_dir/$cn.csr" \
    -CA "$certs_dir/ca.crt" -CAkey "$certs_dir/ca.key" -CAcreateserial \
    -extfile "$certs_dir/$cn.ext" -out "$certs_dir/$cn.crt"
  rm -f "$certs_dir/$cn.csr" "$certs_dir/$cn.ext"
}

issue_client backend
issue_client acs-area-12
```

(O `chmod 644 "$certs_dir"/*.crt "$certs_dir"/*.key` que já existe no fim cobre os arquivos novos; chave de cliente legível por todos é só o dev, como a do servidor.)

Em `mosquitto.conf`, depois de `keyfile ...`, acrescentar:

```
# mTLS: o cliente precisa apresentar certificado assinado pela CA acima. A senha
# e o ACL continuam valendo (sem use_identity_as_username): cert + senha.
require_certificate true
```

- [ ] **Step 4: Backend apresenta o certificado**

`app_config.dart`: campos `final String? mqttClientCertificatePath; final String? mqttClientKeyPath;` lidos de `MQTT_CLIENT_CERT_PATH` e `MQTT_CLIENT_KEY_PATH` (vazio = `null`); regra de boot, no mesmo lugar e estilo das outras validações: **só um dos dois** definido é erro (`StateError('MQTT_CLIENT_CERT_PATH e MQTT_CLIENT_KEY_PATH devem vir juntos')`) e, **fora de `development`** com `MQTT_USE_TLS=true`, os dois são obrigatórios. Testes em `test/unit/app_config_test.dart`: (1) só o cert → erro; (2) os dois em `development` → ok; (3) nenhum em `development` → ok; (4) nenhum em `production` com TLS → erro; (5) nenhum em `production` **sem** TLS → ok (o broker de teste do CI sem TLS).

`mqtt_alert_dispatcher.dart` (~linha 61):

```dart
    if (_config.mqttUseTls && _config.mqttCaCertificatePath != null) {
      final contexto = SecurityContext(withTrustedRoots: false)
        ..setTrustedCertificates(_config.mqttCaCertificatePath!);
      final cert = _config.mqttClientCertificatePath;
      final chave = _config.mqttClientKeyPath;
      if (cert != null && chave != null) {
        contexto
          ..useCertificateChain(cert)
          ..usePrivateKey(chave);
      }
      client.securityContext = contexto;
    }
```

(Mantenha o que o trecho original já faz além disso; só acrescente o cert de cliente.)

`docker-compose.yml`, serviço do servidor: ao lado de onde `MQTT_CA_CERT_PATH` é definido e a CA montada, acrescentar `MQTT_CLIENT_CERT_PATH` e `MQTT_CLIENT_KEY_PATH` apontando para os arquivos `backend.crt`/`backend.key` **no mesmo diretório montado** onde está a CA (confira com `grep -n "MQTT_CA_CERT_PATH\|mosquitto/runtime\|/certs" docker-compose.yml`; se a CA vem por uma montagem de arquivo único, monte também os dois novos). `.env.example`: documentar as duas variáveis. Faça o mesmo no `docker-compose.e2e.yml` se ele tiver o próprio servidor com `MQTT_CA_CERT_PATH`.

- [ ] **Step 5: Subir, ver o vermelho certo e o verde**

Run: `cd backend/sinalacs_server && dart test test/unit/app_config_test.dart 2>&1 | tail -2; cd ../.. && docker compose up -d --build 2>&1 | tail -3; sleep 25; docker compose ps --format '{{.Name}} {{.Status}}' | grep -E "mosquitto|serverpod"; ./scripts/qa/mtls_invariants.sh; echo rc=$?`
Expected: `All tests passed!`; os dois containers `Up`/`healthy`; as quatro linhas `ok:` e `OK — o broker exige certificado de cliente e mantém a senha`, `rc=0`. **Para ver o vermelho de verdade**, antes de aplicar o `require_certificate`, rode o script com `init.sh` novo e `mosquitto.conf` antigo: o caso A sai `FALHOU — esperava recusado, foi aceito`. Se o backend não conectar ao broker depois do `require_certificate` (log `docker compose logs serverpod | grep -i mqtt`), os caminhos de `MQTT_CLIENT_*` não batem com a montagem: corrija a montagem, **nunca** desligue o `require_certificate`.

- [ ] **Step 6: Alerta ponta a ponta no servidor (o backend publica, o broker entrega)**

Run: `docker compose exec -T serverpod true 2>/dev/null; ./scripts/qa/e2e.sh --help 2>&1 | head -5`
Expected: a ajuda lista o modo `--emulator`. (A prova do alerta pelo broker com mTLS depende do app do ACS apresentar o certificado — Task 8. Aqui só se confere que o backend segue conectado: `docker compose logs --tail 20 serverpod | grep -i "mqtt"` sem `Connection refused`/`bad certificate`.)

- [ ] **Step 7: Documentar e commitar**

`backend/CLAUDE.md`: acrescentar `MQTT_CLIENT_CERT_PATH`/`MQTT_CLIENT_KEY_PATH` à lista de variáveis MQTT e a regra de boot. `spec/stack.md`: nota "Broker com mTLS (2026-10-02): `require_certificate true`; certificado de cliente por usuário MQTT, emitido pela CA de desenvolvimento; senha e ACL mantidos; produção exige provisionamento por aparelho (aberto)". `CLAUDE.md` da raiz: trocar "mTLS on the broker (no client certificates)" da lista do que falta por "mTLS: o broker exige certificado de cliente (dev); falta o provisionamento por aparelho em produção".

```bash
git add infra scripts/qa/mtls_invariants.sh docker-compose.yml docker-compose.e2e.yml .env.example backend spec CLAUDE.md
git commit -m "feat(infra): broker MQTT exige certificado de cliente (mTLS), mantendo senha e ACL; backend apresenta o seu"
```

---

### Task 8: mTLS — o app do ACS apresenta o certificado

**Files:**
- Modify: `scripts/dev/sync_dev_ca.sh`
- Modify: `apps/acs/lib/core/network/backend_config.dart`, `apps/acs/lib/core/services/mqtt_secure_client.dart`, `apps/acs/lib/core/services/alert_feed.dart`, `apps/acs/lib/app/app.dart` (mensagem do banner), `apps/acs/pubspec.yaml`, `.gitignore` de `apps/acs`
- Modify: `apps/acs/android/app/build.gradle.kts` (guard da chave de dev), `scripts/qa/acs_release_signing.sh`
- Test: `apps/acs/test/alert_feed_test.dart`, `apps/acs/test/mqtt_secure_client_test.dart`
- Modify: `PROGRESS.md`, `apps/CLAUDE.md`

**Interfaces:**
- Consumes (Task 7): `runtime/certs/acs-area-12.{crt,key}`; broker com `require_certificate true`.
- Produces: assets `apps/acs/assets/certs/acs_client.crt` e `acs_client.key` (gitignorados); `BackendConfig.mqttClientCertAsset`, `BackendConfig.mqttClientKeyAsset`; `SecureMqttConfig.clientCertificate/clientPrivateKey` (`Uint8List?`); `AlertFeedFailureKind.missingClientCertificate`; propriedade Gradle `sinalacs.allowDevClientKey`.

- [ ] **Step 1: Ver o app ser recusado pelo broker (vermelho no emulador)**

Run: `./scripts/qa/e2e.sh --emulator 2>&1 | tail -15`
Expected (com a stack da Task 7 de pé): os testes de `smoke_test.dart` e `red_alert_cycle_test.dart` **falham** no passo do MQTT (o banner `Sem central`/recusa do broker). É o vermelho de dispositivo: o ACS não apresenta certificado. Anote as linhas no ledger. (Se o script exigir `--full` ou outros flags, use os que o cabeçalho de `scripts/qa/e2e.sh` documenta para rodar `smoke` e `red_alert_cycle` no `emulator-5554`.)

- [ ] **Step 2: Testes unitários do app (falham: não há certificado de cliente na config)**

Em `apps/acs/test/mqtt_secure_client_test.dart`, acrescentar, no estilo do arquivo, um caso que monta `SecureMqttConfig` **com** `clientCertificate`/`clientPrivateKey` e outro **sem**, e afirma que a config guarda os dois (e que, sem os dois, ficam `null`); e um caso de `buildMqttSecurityContext(config)` (função de nível de arquivo que o Step 3 extrai do ponto onde `client.securityContext` é montado, linha ~290): com um par cert+chave **PEM gerado no teste por `openssl`** (`Process.run('openssl', [...])` num `Directory.systemTemp.createTempSync()`, pulado com `skip:` se `openssl` não existir) o contexto monta sem lançar; com bytes de lixo, lança `TlsException`.

Em `apps/acs/test/alert_feed_test.dart`, acrescentar: `AlertFeedFailureKind.values` contém `missingClientCertificate`, e um `AlertFeedFailure(AlertFeedFailureKind.missingClientCertificate, ...)` tem `transient == false` por padrão.

Run: `cd apps/acs && flutter test test/mqtt_secure_client_test.dart test/alert_feed_test.dart 2>&1 | tail -5`
Expected: **FAIL** de compilação (`clientCertificate`, `buildMqttSecurityContext`, `missingClientCertificate` não existem).

- [ ] **Step 3: Implementar no app**

`backend_config.dart`: constantes

```dart
  /// Certificado e chave de CLIENTE para o mTLS do broker (spec/stack.md).
  /// **Só desenvolvimento**: a chave privada num asset serve para a stack local; em
  /// produção o certificado é provisionado por aparelho (aberto).
  static const mqttClientCertAsset = 'assets/certs/acs_client.crt';
  static const mqttClientKeyAsset = 'assets/certs/acs_client.key';
```

`mqtt_secure_client.dart`: em `SecureMqttConfig`, campos opcionais `final Uint8List? clientCertificate;` e `final Uint8List? clientPrivateKey;`; extrair para uma função de nível de arquivo e usar no ponto da linha ~290:

```dart
/// Contexto TLS do cliente MQTT: confia **só** na CA do projeto e, se houver
/// certificado de cliente, o apresenta (mTLS). Hostname segue verificado.
SecurityContext buildMqttSecurityContext(SecureMqttConfig config) {
  final contexto = SecurityContext(withTrustedRoots: false)
    ..setTrustedCertificatesBytes(config.caCertificate);
  final cert = config.clientCertificate;
  final chave = config.clientPrivateKey;
  if (cert != null && chave != null) {
    contexto
      ..useCertificateChainBytes(cert)
      ..usePrivateKeyBytes(chave);
  }
  return contexto;
}
```

(`client.securityContext = buildMqttSecurityContext(config);` no lugar do trecho antigo; mantenha o resto do `connect` como está.)

`alert_feed.dart`: novo `AlertFeedFailureKind.missingClientCertificate` ("Falta o certificado de cliente do ACS nos assets (`scripts/dev/sync_dev_ca.sh`)"), carregado **depois** do da CA, com o mesmo padrão `try { rootBundle.load } catch → AlertFeedFailure(missingClientCertificate, title: 'Falta o certificado de cliente da central neste aplicativo.', detail: 'Sem ele o broker recusa a conexão.', cause: error)`, e passado a `SecureMqttConfig(clientCertificate: ..., clientPrivateKey: ...)`. Em `app.dart`, onde o banner mapeia `AlertFeedFailureKind` (`grep -n "AlertFeedFailureKind" apps/acs/lib`), tratar o novo valor igual a `missingCaAsset` (não transitório, precisa recompilar/sincronizar).

`apps/acs/pubspec.yaml`: confirmar que `assets/certs/` está listado como diretório (se listar arquivos um a um, acrescentar `acs_client.crt` e `acs_client.key`). `apps/acs/.gitignore` (ou o `.gitignore` da raiz, onde `dev_ca.crt` já é ignorado — confira com `git check-ignore -v apps/acs/assets/certs/dev_ca.crt`): ignorar `acs_client.crt` e `acs_client.key` do mesmo jeito.

`scripts/dev/sync_dev_ca.sh`: ao copiar a CA para os assets, copiar também `infra/docker/mosquitto/runtime/certs/acs-area-12.crt` → `apps/acs/assets/certs/acs_client.crt` e `acs-area-12.key` → `acs_client.key`, **com a mesma verificação** que o script já faz da CA (`openssl verify -CAfile ca.crt acs-area-12.crt`) e o mesmo padrão de temporário + `mv`; `chmod 600` na chave copiada.

Run: `./scripts/dev/sync_dev_ca.sh && cd apps/acs && flutter analyze 2>&1 | tail -2 && flutter test 2>&1 | tail -2`
Expected: assets copiados; `No issues found!`; `All tests passed!` (≥ 250).

- [ ] **Step 4: Prova no emulador: o alerta volta a chegar, agora com mTLS**

Run: `./scripts/qa/e2e.sh --emulator 2>&1 | tail -12; ./scripts/qa/mtls_invariants.sh`
Expected: `smoke_test`/`red_alert_cycle_test` **passam** (o ACS conecta ao broker com certificado + senha e recebe o alerta); as quatro linhas do `mtls_invariants.sh` seguem `ok:`. Conferir no log do broker que o cliente do app autenticou como `acs-area-12`: `docker compose logs mosquitto --tail 40 | grep -i "acs-area-12"`.

- [ ] **Step 5: Release não leva a chave privada de desenvolvimento**

Em `build.gradle.kts`, **dentro** do `gradle.taskGraph.whenReady` da Task 2, depois do guard de assinatura, acrescentar:

```kotlin
    // A chave privada de CLIENTE do broker de desenvolvimento (assets/certs/acs_client.key)
    // não pode ir dentro de um APK de release: qualquer pessoa com o APK a extrairia.
    val chaveDeDev = rootProject.file("../assets/certs/acs_client.key")
    if (buildaRelease && chaveDeDev.exists() && !project.hasProperty("sinalacs.allowDevClientKey")) {
        throw GradleException(
            """
            |O release levaria a chave privada de desenvolvimento do broker (assets/certs/acs_client.key).
            |
            |Remova o arquivo antes de gerar o release (em produção o certificado de cliente é
            |provisionado por aparelho — ainda não implementado). Para um release de TESTE LOCAL,
            |acrescente -Psinalacs.allowDevClientKey=true.
            """.trimMargin()
        )
    }
```

Em `scripts/qa/acs_release_signing.sh`, os cenários 2 e 3 passam `-Psinalacs.allowDevClientKey=true`, e um **cenário 4** novo prova o guard: com a chave de dev presente (rode `sync_dev_ca.sh` antes ou crie um arquivo vazio descartável em `assets/certs/acs_client.key` e o remova no `trap`), `construir -Psinalacs.allowDebugSigning=true` **falha** com `chave privada de desenvolvimento`.

Run: `./scripts/qa/acs_release_signing.sh; echo rc=$?`
Expected: quatro cenários e `OK — ...`, `rc=0`. (Para ver o vermelho: antes de acrescentar o guard, o cenário 4 sai `erro: o release passou levando a chave de desenvolvimento`.)

- [ ] **Step 6: Documentar e commitar**

`PROGRESS.md`: "mTLS do broker entregue **na stack local**: `require_certificate true`, certificado de cliente para o backend e para o ACS (asset de dev), senha e ACL mantidos; `scripts/qa/mtls_invariants.sh` prova os quatro casos. **Aberto:** provisionamento por aparelho em produção (CSR no cadastro, chave no Keystore); release com a chave de dev é barrado." Remover "mTLS" da lista de pendências do ACS. `apps/CLAUDE.md`: parágrafo curto (assets, `sync_dev_ca.sh`, `buildMqttSecurityContext`, guard do release).

```bash
git add scripts apps/acs PROGRESS.md apps/CLAUDE.md
git commit -m "feat(acs): app apresenta certificado de cliente ao broker (mTLS); release barra a chave de desenvolvimento"
```

---

### Task 9: Registro final e barra no emulador

**Files:**
- Modify: `PROGRESS.md`, `CLAUDE.md` (raiz: a frase "Still missing: MFA and refresh token…, mTLS on the broker…, a backend for the admin backoffice…")

**Interfaces:** nenhuma.

- [ ] **Step 1: Atualizar o estado do projeto**

No `CLAUDE.md` da raiz, parágrafo "Project overview", reescrever "Still missing" para: refresh token, provisionamento de certificado por aparelho em produção (o broker já exige certificado de cliente na stack local), backend do backoffice, deploy de produção; e acrescentar ao "Already delivered": MFA TOTP do ACS, RF08 persistido, `FLAG_SECURE`, release assinado com chave própria, botão da UBS. Em `PROGRESS.md`, a seção "Pendências do ACS (2026-10-02)" com uma linha por tarefa (commit, prova, o que ficou aberto) e **o que foi decidido** (D1–D8 resumidos).

- [ ] **Step 2: Barra final**

```bash
export PATH="$PATH:$HOME/Android/Sdk/platform-tools:$HOME/flutter/bin:$HOME/.pub-cache/bin"
(cd backend/sinalacs_server && dart analyze && dart test 2>&1 | tail -2)
(cd apps/acs && flutter analyze && flutter test 2>&1 | tail -2)
python3 scripts/qa/contagem_validation_report.py
./scripts/qa/lib_rele_test.sh && ./scripts/qa/acs_gps_e2e_test.sh
./scripts/qa/ci_invariants.sh && ./scripts/qa/check_documentation_links.sh
docker compose up -d --build && sleep 25 && ./scripts/qa/mtls_invariants.sh
adb -s emulator-5554 shell pm list packages br.com.prismrr.sinalacs.acs   # vazio
./scripts/qa/acs_secure_window.sh && ./scripts/qa/acs_gps_e2e.sh && ./scripts/qa/acs_gps_e2e.sh --sem-permissao
./scripts/qa/e2e.sh --emulator
./scripts/qa/acs_release_signing.sh
./scripts/qa/acs_full_e2e.sh; docker compose up -d
```

Expected: `No issues found!` nos dois; suíte do backend e `flutter test` **todos verdes** (o ACS com ≥ 250 testes); conferidor da contagem `ok`; `ok: lib_rele` e `ok: acs_gps_e2e`; `ci_invariants` `ok`; links sem erro; `OK — o broker exige certificado de cliente e mantém a senha`; `OK — janela do ACS com FLAG_SECURE`; os dois GPS `OK`; o e2e do emulador verde com mTLS; `OK — release exige chave própria...`; jornada `OK` (com as linhas `rajada:` e a prova de RF08/MFA); `sinalacs-serverpod … (healthy)`; `ls .e2e/fixtures.json` → inexistente; nenhum app do ACS instalado no fim.

Se `ci_invariants.sh` apontar o CI (por exemplo, o job `serverpod-backend` precisar de `REQUIRE_ACS_MFA` ou dos caminhos `MQTT_CLIENT_*` para o broker de teste), corrigir `.github/workflows/ci.yml` **mantendo** as invariantes (runner `ubuntu-24.04`, sem `paths`, concurrency) e registrar a mudança no ledger.

- [ ] **Step 3: Estado do repositório e commit**

```bash
git status --short && git log --oneline -12 && git log -12 --format=%B | grep -ci "co-authored\|generated with"
git add PROGRESS.md CLAUDE.md
git commit -m "docs: registra o fechamento das pendências do ACS (FLAG_SECURE, assinatura, UBS, RF08, MFA, mTLS)"
```

Expected: árvore limpa depois do commit; **`0`** na contagem de atribuições de IA; sem push.

---

## Auto-revisão

**Cobertura:** FLAG_SECURE → Task 1; assinatura de release → Task 2 (e o guard da chave de dev na Task 8); botão da UBS → Task 3; RF08 → Task 4 (com a decisão de LGPD escrita **antes** do código, como o `PROGRESS.md` exigia); MFA → Tasks 5 (backend) e 6 (app + emulador); mTLS → Tasks 7 (broker + backend) e 8 (app + emulador). A barra final e o registro estão na Task 9. O que **não** entra (refresh token, redefinição de MFA, provisionamento de certificado por aparelho, backoffice) tem o motivo escrito e vira "aberto" no `PROGRESS.md`, sem fingir fechamento.

**Placeholders:** não há "TBD". Três pontos dependem de **ler um arquivo que esta sessão não abriu por inteiro** e dizem exatamente o quê: o corpo do `login` institucional (Task 5, Step 5 — com refatoração guardada pelos testes existentes), a sintaxe de escrita do store do ORM (Task 5, Step 6) e a montagem dos certificados no `docker-compose.yml` (Task 7, Step 4). Cada um tem o teste que prova o resultado.

**Consistência de nomes:** `MicroAreaDirectory.load()`/`MicroAreaSnapshot`/`MicroAreaCacheStore.read/write/clear` iguais nas Tasks 4 (store, serviço, telas e e2e); `TotpEnrollment{sealed,enabled,lastStep}`, `TotpStore.saveSecret/enable/registerStep`, `SealedSecret`, `TotpSecretVault.seal/open` iguais entre o teste e a implementação da Task 5; `AcsBackend.login(..., totpCode)`, `MfaCodeRequired`/`MfaEnrollmentRequired`, chaves `totp_field`/`mfa_secret`/`mfa_code_field`/`mfa_confirm_button` iguais entre os testes e as telas da Task 6; `sinalacs.allowDebugSigning` (Task 2) e `sinalacs.allowDevClientKey` (Task 8) usados nos mesmos scripts.

**Review Focus:** as 5 linhas têm teste dono (replay e tentativa errada na Task 5; cache de outro dono e vencido na Task 4; recusa sem certificado e de outra CA na Task 7; release sem chave na Task 2 e com a chave de dev na Task 8).

**Riscos que só a execução resolve:** (1) o formato do `dumpsys window windows` no Android 16 (Task 1 manda ajustar o `awk` até ver o vermelho certo); (2) se `-P` chega ao Gradle pelo `flutter build` (Task 2 traz a alternativa `--android-project-arg`); (3) a refatoração do `login` (Task 5) mexe em código de segurança — os testes antigos são a rede; (4) se o `acs_full_e2e.sh` reconstrói a imagem do servidor (Tasks 3, 5 e 6 mandam conferir); (5) se o `eclipse-mosquitto:2` com `--network host` alcança `localhost:8883` neste host (Task 7); (6) a base do aparelho estar mesmo cifrada no caminho do cache (Task 4, Step 10 trata como achado de segurança se não estiver).

**Escopo:** este plano junta seis frentes independentes (a skill sugere um plano por subsistema). Cada Task termina em software testável por si e pode ser executada, commitada e revertida sozinha; a ordem só importa entre 5→6 (MFA) e 7→8 (mTLS), e a Task 8 altera o guard da Task 2.
