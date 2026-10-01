# Gorush + FCM: configuração final e teste ponta a ponta no emulador — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fazer o aviso comunitário chegar de verdade a um aparelho: o app paciente obtém um token FCM real (lado nativo Android), o backend o guarda, `notices.sendSegmented` entrega a lista ao **Gorush real** e a notificação aparece no emulador `emulator-5554`.

**Architecture:** O Gorush roda no Compose (perfil `push`, sem porta publicada) com a **conta de serviço** do FCM; o app usa o `google-services.json` só para pedir o token ao Firebase Messaging pelo canal `sinalacs/push_token`, cujo contrato Dart já existe. A configuração do Gorush e o parser do cliente são validados contra respostas **reais** do Gorush e do FCM (com a chave real da conta de serviço, já presente, e um token falso que não entrega nada a ninguém), porque até aqui o cliente só foi provado contra um servidor HTTP falso.

**Tech Stack:** Gorush 1.22.0 (`appleboy/gorush`), Docker Compose, Android (Gradle/AGP 9.0.1, Kotlin, `firebase-messaging`, plugin `com.google.gms.google-services`), Flutter 3.44 `integration_test`, Dart (backend/ACS), `adb`.

**Spec:** `docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md` §3.2 (revisada para Gorush); `infra/docker/gorush/README.md` (checklist do que nunca foi verificado contra um Gorush real).

## Global Constraints

- **Segredos:** a chave da conta de serviço (`fcm-service-account.json`) tem modo `600`, vive só em `infra/docker/gorush/credentials/` (já no `.gitignore`) e **nunca** é impressa (`cat`, `echo`, logs), nem copiada para fora desse diretório. O token FCM também nunca é impresso: só o tamanho. A chave está hoje com modo `644` (legível por outros usuários da máquina): a Task 1 a corrige para `600`. A imagem do Gorush roda como `gorush` (uid 1000), igual ao uid deste usuário, então `600` continua legível no container **nesta** máquina; com outro uid o container não lê a chave, e o README passa a dizer isso (não relaxar para `644` como atalho: usar `chown`/grupo).
- **Dispositivo:** só `emulator-5554` (`Medium_Phone`, API 36, `google_apis_playstore`, tem Play Services e internet). O `adb` não está no `PATH`: `export PATH=$PATH:~/Android/Sdk/platform-tools:~/flutter/bin`. Nunca `adb uninstall` de pacote que não seja `br.com.prismrr.sinalacs.patient`.
- **Rede do emulador:** o RPC é alcançado por `adb reverse tcp:8443 tcp:443` e `--dart-define=SINALACS_HOST=https://localhost:8443/` (como `scripts/qa/e2e.sh`); `10.0.2.2:443` já falhou medidamente.
- **O build não pode depender do `google-services.json`:** ele é ignorado pelo git, então a CI (`patient-app`, `android-e2e`) e outros devs não o têm. O plugin do Google Services só é aplicado quando o arquivo existe, e o código nativo degrada para "sem push" sem o `FirebaseApp`.
- O Gorush **nunca** publica porta no Compose. Os containers de smoke desta rodada ligam só em `127.0.0.1` e são removidos no fim.
- Alerta vermelho nunca é descartado nem atrasado: nada aqui toca o caminho do alerta MQTT; falha de push nunca bloqueia login, home nem o botão de urgência.
- `flutter analyze` limpo; `dart analyze` do backend no baseline de 51 infos e zero avisos; repetir `dart test` do backend 5 vezes se qualquer arquivo do backend mudar. `docker compose config -q` e `./scripts/qa/ci_invariants.sh` ok ao fim.
- Texto de UI e comentários em português. Nenhum dado real de paciente.
- Não afirmar o que não foi observado: iOS/APNs **não** é testado nesta rodada e o plano não o promete.

## Review Focus

- **Build sem `google-services.json`** (CI, outro dev): compila e o app degrada para "sem push", sem crash.
- **Gorush com iOS desligado e um token `ios` na lista:** o erro dele não apaga o token (não é erro de token) e não derruba a entrega Android.
- **Token inválido real:** o Gorush devolve o erro do FCM v1, o backend reconhece, apaga **só** essa linha e mantém o token bom.
- **`log.hide_token` mascara o token na resposta?** Se sim, a poda nunca casa com `push_tokens.token`: precisa ser visto na resposta real, não suposto.
- **Gorush parado no meio do uso:** `sendSegmented` falha rápido (≤ 5 s), com a mensagem certa, e sem linha de auditoria `granted`.
- **App em primeiro plano:** FCM não mostra mensagem de notificação na bandeja com o app aberto; o teste usa o app em segundo plano e a documentação diz isso.
- **Permissão de notificação negada (Android 13+):** o token ainda registra; só a exibição some.

---

## Estado verificado hoje (2026-09-30)

- Emulador `emulator-5554` de pé, com Play Services e internet.
- `apps/patient/android/app/google-services.json` existe (projeto `sinal-acs`, pacote `br.com.prismrr.sinalacs.patient`) e é ignorado pelo git. `.gitignore` tem uma alteração **não commitada** (a linha `google-services.json`).
- **A chave da conta de serviço existe** em `infra/docker/gorush/credentials/fcm-service-account.json`, é ignorada pelo git e foi validada **só na estrutura**, sem imprimir nada: `type: service_account`, `project_id` = `sinal-acs` (igual ao do `google-services.json`), `private_key` com cabeçalho PEM, `client_email` de conta de serviço. **Não** está provado que ela está ativa, que tem permissão de enviar, nem que a API *Firebase Cloud Messaging API (V1)* está habilitada no projeto: isso só aparece na primeira chamada real (Task 1 Step 3).
- A imagem `appleboy/gorush:1.22.0` já traz `HEALTHCHECK ["/bin/gorush", "--ping"]` e roda como o usuário `gorush` (uid 1000).
- `.env` não define `GORUSH_URL`; o Compose só tem `postgres-test` de pé. O build Android não tem plugin do Google Services, biblioteca do Firebase Messaging nem `POST_NOTIFICATIONS`; `MainActivity.kt` é um `FlutterActivity` vazio (o canal `sinalacs/push_token` não tem lado nativo).
- `infra/docker/gorush/config.yml` liga `ios.enabled: true` com `key_path` para um arquivo que não existe, e o Compose usa `appleboy/gorush:latest`. Hoje o Gorush **provavelmente não sobe** assim: a Task 1 prova (ou refuta) isso.

## Mapa de arquivos

- Infra: `docker-compose.yml`, `infra/docker/gorush/config.yml`, `infra/docker/gorush/README.md`, `scripts/qa/gorush_smoke.sh` (novo), `scripts/qa/push_e2e.sh` (novo), `.gitignore`, `.env` (local, não versionado).
- Backend: `backend/sinalacs_server/test/unit/fixtures/gorush_*.json` (novos), `test/unit/gorush_client_test.dart`, `lib/src/infrastructure/push/gorush_client.dart` (só se a resposta real exigir).
- App paciente (Android): `android/settings.gradle.kts`, `android/app/build.gradle.kts`, `android/app/src/main/kotlin/br/com/prismrr/sinalacs/patient/MainActivity.kt`, `android/app/src/main/AndroidManifest.xml`, `integration_test/push_native_token_test.dart` (novo), `integration_test/push_register_test.dart` (novo).
- App ACS: `apps/acs/tool/send_notice.dart` (novo).
- Docs: `PROGRESS.md`, `apps/CLAUDE.md`, `backend/CLAUDE.md`, `spec/stack.md`, `docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md` §3.2, memória.

---

### Task 1: Gorush sobe com a configuração certa e a resposta real vira contrato

**Files:**
- Modify: `docker-compose.yml`, `infra/docker/gorush/config.yml`, `infra/docker/gorush/README.md`, `.gitignore`
- Create: `scripts/qa/gorush_smoke.sh`, `backend/sinalacs_server/test/unit/fixtures/gorush_invalid_token.json`
- Modify (teste): `backend/sinalacs_server/test/unit/gorush_client_test.dart`; `lib/src/infrastructure/push/gorush_client.dart` só se o teste do contrato falhar

**Interfaces:**
- Produces: imagem do Gorush **fixada** em `appleboy/gorush:1.22.0` no Compose; `ios.enabled: false` no `config.yml`; `scripts/qa/gorush_smoke.sh` (sobe um Gorush descartável em `127.0.0.1:18088` com a chave real, posta um push para um token **falso** e grava a resposta em `$1`).
- Produces: fixture `gorush_invalid_token.json` no formato `{"status": <int>, "body": <json da resposta real>}` e um teste de contrato que a usa e exige a poda do token.
- Consumes: `GorushClient`, `PushTarget`, `PushMessage`, `PushSendReport`, `PushGatewayException(message, {outcomeUnknown})` (já existem).

- [ ] **Step 1: Commitar a alteração do `.gitignore` (é sua, já no working tree)**

Run: `git diff .gitignore | grep '^[+-]' | grep -v '^+++\|^---'` e confirme que só acrescenta `google-services.json`.
Expected: um bloco `# Google services` + `google-services.json`.

```bash
git add .gitignore && git commit -m "chore: ignora google-services.json (credencial do projeto Firebase, não versionada)"
```

- [ ] **Step 2: RED — provar que a configuração atual não sobe, e fechar o modo da chave**

```bash
chmod 600 infra/docker/gorush/credentials/fcm-service-account.json
stat -c '%a %U' infra/docker/gorush/credentials/fcm-service-account.json      # 600 rock
docker run --rm --name gorush-red -v $PWD/infra/docker/gorush/config.yml:/config.yml:ro \
  -v $PWD/infra/docker/gorush/credentials:/credentials:ro appleboy/gorush:1.22.0 -c /config.yml 2>&1 | head -20
```

Expected: o container **encerra com erro** citando o iOS/a chave APNs (`/credentials/apns-key.p8`). Se ele subir normalmente, o achado "ios.enabled quebra o boot" é falso: registre `Ruling:` no ledger e pule a parte do iOS do Step 3. Se ele falhar por **não conseguir ler** `fcm-service-account.json` (permissão), o uid do container não é o do usuário: registre e trate como nas restrições globais, sem `644`.

- [ ] **Step 3: Corrigir a configuração**

`infra/docker/gorush/config.yml`: `ios.enabled: false` (com o comentário: "iOS só liga quando existir chave APNs e um app iOS; ligue com `GORUSH_IOS_ENABLED=true` no ambiente do serviço, que o Gorush lê por `GORUSH_<SEÇÃO>_<CHAVE>`") e confirme, pelo README da **1.22.0** e por `docker run --rm appleboy/gorush:1.22.0 --help`, os nomes reais das chaves `android.*` (o plano assume `android.enabled` e `android.key_path`; se a 1.22.0 usar outro nome, use o dela e ledgere). `docker-compose.yml`: trocar `image: appleboy/gorush:latest` por `image: appleboy/gorush:1.22.0` e **não** acrescentar `healthcheck`: a imagem já traz `CMD ["/bin/gorush", "--ping"]` (intervalo 10 s), que herda o Compose; só confirme com `docker compose --profile push ps` que o serviço chega a `healthy`.

- [ ] **Step 4: Script de smoke e captura da resposta real do FCM**

`scripts/qa/gorush_smoke.sh` (não usa o serviço do Compose: um container descartável, só em `127.0.0.1`; o token é falso, então nada é entregue a ninguém):

```bash
#!/usr/bin/env bash
# Sobe um Gorush descartável com a chave em $GORUSH_SMOKE_CREDENTIALS (diretório com
# fcm-service-account.json), posta UM push para um token FALSO e grava a resposta
# (status + corpo) em $1. Serve para observar o formato REAL que o GorushClient
# precisa entender. Nunca imprime a chave.
set -euo pipefail
out="${1:?uso: gorush_smoke.sh <arquivo-de-saida.json>}"
cred="${GORUSH_SMOKE_CREDENTIALS:?defina GORUSH_SMOKE_CREDENTIALS}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
name="gorush-smoke-$$"
trap 'docker rm -f "$name" >/dev/null 2>&1 || true' EXIT
docker run -d --name "$name" -p 127.0.0.1:18088:8088 \
  -v "$repo_root/infra/docker/gorush/config.yml:/config.yml:ro" \
  -v "$cred:/credentials:ro" appleboy/gorush:1.22.0 -c /config.yml >/dev/null
for _ in $(seq 1 20); do
  curl -fsS -m 2 http://127.0.0.1:18088/healthz >/dev/null 2>&1 && break
  sleep 1
done
curl -fsS -m 2 http://127.0.0.1:18088/healthz >/dev/null || { docker logs "$name" 2>&1 | tail -20 >&2; echo 'erro: o Gorush não ficou saudável' >&2; exit 1; }
token="$(python3 -c "print('x' * 152)")"
status=$(curl -sS -m 30 -o /tmp/gorush_body.$$ -w '%{http_code}' -X POST http://127.0.0.1:18088/api/push \
  -H 'Content-Type: application/json' \
  -d "{\"notifications\":[{\"tokens\":[\"$token\"],\"platform\":2,\"title\":\"t\",\"message\":\"m\"}]}")
python3 - "$status" /tmp/gorush_body.$$ "$out" <<'PYEOF'
import json, sys
status, body_path, out = int(sys.argv[1]), sys.argv[2], sys.argv[3]
raw = open(body_path).read()
try: body = json.loads(raw)
except Exception: body = raw
json.dump({"status": status, "body": body}, open(out, "w"), indent=2, ensure_ascii=False)
PYEOF
rm -f /tmp/gorush_body.$$
```

Run: `chmod +x scripts/qa/gorush_smoke.sh && GORUSH_SMOKE_CREDENTIALS=$PWD/infra/docker/gorush/credentials ./scripts/qa/gorush_smoke.sh /tmp/gorush_invalid_token.json && cat /tmp/gorush_invalid_token.json`
Expected: o Gorush fica saudável (prova que o Step 3 consertou o boot) e o arquivo mostra a resposta real do FCM a um token inválido. **Este é o primeiro contato com o FCM real**, e ele também prova ou refuta a chave: se a resposta for uma falha de **autenticação/permissão** (401/403, `PERMISSION_DENIED`, API V1 desativada) em vez de "token inválido", **pare**, registre a mensagem (sem a chave) e diga ao usuário o que ajustar no console do Firebase (ativar *Firebase Cloud Messaging API (V1)*, papel da conta de serviço). Leia e registre no ledger: o `status` HTTP, se `counts` existe, o formato de `logs[]` (`type`, `error`, `token`) **e se o token aparece mascarado**.

- [ ] **Step 5: O contrato real vira teste (RED se a poda não casar)**

Copie a resposta para `backend/sinalacs_server/test/unit/fixtures/gorush_invalid_token.json`; o token do smoke é falso (`'x' * 152`), então a fixture não contém nada sensível. Em `gorush_client_test.dart` (importe `dart:convert` e `dart:io` se faltarem):

```dart
test('resposta REAL do Gorush a um token inválido: o token é reconhecido e podado', () async {
  final fixture = jsonDecode(File('test/unit/fixtures/gorush_invalid_token.json').readAsStringSync())
      as Map<String, dynamic>;
  final body = fixture['body'];
  final gw = await FakeGorush.start(
    status: fixture['status'] as int,
    rawBody: body is String ? body : jsonEncode(body),
  );
  addTearDown(gw.close);
  final client = GorushClient(baseUrl: gw.url, timeout: const Duration(seconds: 2));
  final falso = 'x' * 152;

  final report = await client.send(
    _msg,
    [PushTarget(token: falso, platform: 'android'), const PushTarget(token: 'tok-bom', platform: 'android')],
  );

  // O erro do FCM é sobre o TOKEN: só ele pode ser apagado, e nunca o bom.
  expect(report.invalidTokens, [falso]);
  expect(report.accepted, lessThanOrEqualTo(1));
});
```

Run: `cd backend/sinalacs_server && dart test test/unit/gorush_client_test.dart`
Expected: se **PASSAR**, o parser já entendia a resposta real: registre "sem RED: o parser já entendia" (o teste ainda vale como contrato). Se **FALHAR** (token mascarado por `log.hide_token`, ou string de erro do FCM v1 fora da lista `_invalidTokenErrors`), esse é o RED real: corrija `GorushClient._post`/`_invalidTokenErrors` ou `config.yml` (`log.hide_token: false` só se o mascaramento for o motivo, e registre a troca no README) **sem enfraquecer o teste**, e ledgere o que a resposta real tinha de diferente.

- [ ] **Step 6: Verificações e commit**

Run: `docker compose --profile push config -q && docker compose config -q; cd backend/sinalacs_server && dart analyze | tail -1 && for i in 1 2 3 4 5; do dart test 2>&1 | tail -1; done; docker rm -f gorush-red 2>/dev/null`
Expected: compose sem erro, analyze em 51 infos, 5 de 5 verdes.

```bash
git add docker-compose.yml infra/docker/gorush scripts/qa/gorush_smoke.sh backend/sinalacs_server
git commit -m "fix(infra): Gorush 1.22.0 fixada, iOS desligado até existir APNs, e a resposta real vira teste de contrato (RF14)"
```

---

### Task 2: Lado nativo Android do token FCM e teste no emulador

**Files:**
- Modify: `apps/patient/android/settings.gradle.kts`, `apps/patient/android/app/build.gradle.kts`, `apps/patient/android/app/src/main/kotlin/br/com/prismrr/sinalacs/patient/MainActivity.kt`, `apps/patient/android/app/src/main/AndroidManifest.xml`
- Create: `apps/patient/integration_test/push_native_token_test.dart`

**Interfaces:**
- Consumes: o contrato do canal de `NativePushTokenSource` (`lib/core/push/native_push_token_source.dart`): canal `sinalacs/push_token`, método `getToken`, resposta `{'token': String, 'platform': 'android'}`; erro de plataforma vira `null` no Dart.
- Produces: o lado nativo desse canal; o plugin do Google Services aplicado **só** quando `android/app/google-services.json` existe.

- [ ] **Step 1: Teste vermelho no emulador**

`integration_test/push_native_token_test.dart`:

```dart
/// Prova, no aparelho, que o canal nativo devolve um token FCM REAL. Precisa de
/// Play Services, internet e do `google-services.json` no build. Nunca imprime o token.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sinalacs_patient/core/push/native_push_token_source.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('o canal nativo devolve um token FCM real do aparelho', () async {
    final device = await const NativePushTokenSource()
        .currentDevice()
        .timeout(const Duration(seconds: 60));

    expect(device, isNotNull,
        reason: 'sem token: o lado nativo falta, ou o build não tem o google-services.json');
    expect(device!.platform, 'android');
    expect(device.token.length, greaterThan(100));
    expect(device.token.contains(':'), isTrue, reason: 'token FCM tem a forma <id>:<segredo>');
  });
}
```

Run: `export PATH=$PATH:~/Android/Sdk/platform-tools:~/flutter/bin && cd apps/patient && flutter test integration_test/push_native_token_test.dart -d emulator-5554`
Expected: FAIL em `device, isNotNull` (o canal não tem lado nativo). Se o app nem instalar, leia o erro antes de seguir.

- [ ] **Step 2: Versões, confirmadas e não supostas**

Confirme as versões **atuais** no Google Maven e registre-as no ledger:

```bash
curl -s https://dl.google.com/dl/android/maven2/com/google/gms/google-services/maven-metadata.xml | grep -E "<release>|<latest>"
curl -s https://dl.google.com/dl/android/maven2/com/google/firebase/firebase-messaging/maven-metadata.xml | grep -E "<release>|<latest>"
```

Use `<release>` de cada um. O AGP do projeto é o `9.0.1` (muito novo): se o plugin do Google Services não for compatível, o build falha na configuração — nesse caso leia o erro, procure a versão compatível e registre um `Ruling:`; **não** remova o AGP nem force uma versão antiga do Gradle.

- [ ] **Step 3: Gradle**

`settings.gradle.kts`, no bloco `plugins { ... }`:

```kotlin
    id("com.google.gms.google-services") version "<RELEASE-CONFIRMADA>" apply false
```

`app/build.gradle.kts`: logo depois do bloco `plugins { ... }`, acrescente:

```kotlin
// google-services.json não é versionado (CI e outros devs não o têm): sem ele o
// plugin derrubaria o build inteiro. Só aplica quando o arquivo existe; sem ele o
// app compila e o lado nativo responde "firebase_unavailable" (sem push).
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}
```

e no bloco `dependencies { ... }`:

```kotlin
    implementation("com.google.firebase:firebase-messaging:<RELEASE-CONFIRMADA>")
```

- [ ] **Step 4: Kotlin e manifesto**

`MainActivity.kt`:

```kotlin
package br.com.prismrr.sinalacs.patient

import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Lado nativo do canal `sinalacs/push_token` (RF14): devolve o token FCM do
/// aparelho. O contrato Dart está em `native_push_token_source.dart`: qualquer erro
/// aqui vira `null` lá, e o app segue sem push.
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sinalacs/push_token")
            .setMethodCallHandler { call, result ->
                if (call.method != "getToken") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                // Sem google-services.json (CI, outro dev) o FirebaseApp não existe.
                if (FirebaseApp.getApps(this).isEmpty()) {
                    result.error("firebase_unavailable", "FirebaseApp não inicializado", null)
                    return@setMethodCallHandler
                }
                FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                    val token = if (task.isSuccessful) task.result else null
                    if (!token.isNullOrBlank()) {
                        result.success(mapOf("token" to token, "platform" to "android"))
                    } else {
                        result.error("token_unavailable", task.exception?.message, null)
                    }
                }
            }
    }
}
```

`AndroidManifest.xml`, junto das outras `uses-permission`:

```xml
    <!-- Android 13+: sem esta permissão o token ainda é obtido e registrado, mas a
         notificação do aviso comunitário não é exibida (RF14). Quem pede a permissão
         em tempo de execução é `main.dart`, por `requestNotificationsPermission()`. -->
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

- [ ] **Step 5: GREEN no emulador e o build sem o arquivo**

Run: `cd apps/patient && flutter test integration_test/push_native_token_test.dart -d emulator-5554`
Expected: PASS. O teste confirma forma e tamanho do token, nunca o conteúdo. Se falhar com `null`, leia `adb -s emulator-5554 logcat -d | grep -i -E "firebase|fcm|gms" | tail -30` (sem colar o token).

Depois prove que o build **sem** o arquivo continua funcionando e o app não quebra:

```bash
cd apps/patient
mv android/app/google-services.json /tmp/gs.json.bak
trap 'mv /tmp/gs.json.bak android/app/google-services.json 2>/dev/null' EXIT
flutter build apk --debug 2>&1 | tail -3
flutter test integration_test/push_native_token_test.dart -d emulator-5554 2>&1 | tail -4
mv /tmp/gs.json.bak android/app/google-services.json; trap - EXIT
```

Expected: o APK **compila** sem o arquivo; o teste de integração **falha** em `device, isNotNull` com a razão da mensagem (degradação, sem crash do app). Se o build falhar sem o arquivo, o `if` do Step 3 está errado: corrija antes de seguir (isso quebraria a CI).

- [ ] **Step 6: Suíte do app e commit**

Run: `cd apps/patient && flutter test && flutter analyze; cd ../acs && flutter test`
Expected: paciente 223, ACS 178, analyze limpo.

```bash
git add apps/patient/android apps/patient/integration_test
git commit -m "feat(paciente): lado nativo Android do token FCM, com o plugin do Google Services só quando há google-services.json (RF14)"
```

---

### Task 3: Ferramentas do teste ponta a ponta (registro real e envio do ACS)

**Files:**
- Create: `apps/patient/integration_test/push_register_test.dart`, `apps/acs/tool/send_notice.dart`

**Interfaces:**
- Consumes: `BackendClient` do paciente (`developmentLogin(role:)`, `updateConsent`, `registerPushToken`) e do ACS (`developmentLogin(role:)`, `sendNotice`), `NativePushTokenSource`, `BackendConfig.rpcCaAsset` (asset da CA) — mesmas APIs que `smoke_test.dart` e `tool/live_check.dart` já usam.
- Produces: um teste de integração que registra o token **real** do aparelho no backend com consentimento; uma ferramenta de linha de comando que envia um aviso como ACS e imprime só `recipients`/`accepted`.

- [ ] **Step 1: O registro real, como teste de integração**

`apps/patient/integration_test/push_register_test.dart` — copie o preâmbulo de `smoke_test.dart` (leitura da CA do asset, `BackendClient(trustedCaBytes:)`, `addTearDown(backend.close)`, login `backend.developmentLogin(role: 'patient')`; leia o arquivo antes de copiar, o nome exato das funções pode diferir) e acrescente:

```dart
  test('registra no backend o token FCM real do aparelho, com consentimento', () async {
    // ... preâmbulo: caBytes, backend, login de paciente ...
    final device = await const NativePushTokenSource()
        .currentDevice()
        .timeout(const Duration(seconds: 60));
    expect(device, isNotNull, reason: 'sem token FCM real: rode a Task 2 antes');

    // Sem consentimento, o servidor recusa e nada é gravado.
    await expectLater(
      backend.registerPushToken(token: device!.token, platform: device.platform),
      throwsA(isA<BackendFailure>()),
    );

    await backend.updateConsent(purpose: ConsentPurpose.segmentedPush, granted: true);
    await backend.registerPushToken(token: device.token, platform: device.platform); // não lança
  });
```

Run (sem stack ainda, só para ver o RED de "sem backend"): `cd apps/patient && flutter test integration_test/push_register_test.dart -d emulator-5554 --dart-define=SINALACS_HOST=https://localhost:8443/`
Expected: FAIL por falta de backend/túnel (conexão), não por erro de compilação. O GREEN vem na Task 4, com a stack de pé.

- [ ] **Step 2: A ferramenta do ACS**

`apps/acs/tool/send_notice.dart` — mesmo esqueleto de `tool/live_check.dart` (lê a CA de `apps/acs/assets/certs/dev_rpc_ca.crt` com `dart:io`, monta `BackendClient(host:, trustedCaBytes:)`, `--host` com default `https://localhost/`):

```dart
/// Envia UM aviso comunitário como ACS de desenvolvimento e imprime só as contagens.
///   dart run tool/send_notice.dart --title "SinalACS e2e" --message "Teste do Gorush" [--chronic] [--host https://localhost/]
/// Precisa da stack de pé com ENABLE_DEV_LOGIN=true. Nunca imprime token nem destinatários.
```

Fluxo: `developmentLogin(role: 'acs')` → `sendNotice(title:, message:, chronicOnly:)` → imprime `recipients=<n> accepted=<m>` e sai com `0`; `BackendFailure` imprime **a mensagem** e sai com `2` (o script de e2e precisa distinguir "falhou" de "0 destinatários").

Run: `cd apps/acs && dart analyze tool/send_notice.dart && dart run tool/send_notice.dart --help`
Expected: analyze limpo; `--help` imprime o uso.

- [ ] **Step 3: Commit**

```bash
git add apps/patient/integration_test/push_register_test.dart apps/acs/tool/send_notice.dart
git commit -m "test(e2e): registro real do token FCM e ferramenta de envio do ACS (RF14)"
```

---

### Task 4: Teste ponta a ponta no emulador com o Gorush real

**Files:**
- Create: `scripts/qa/push_e2e.sh`
- Modify (conforme a resposta real): `backend/sinalacs_server/lib/src/infrastructure/push/gorush_client.dart`, `test/unit/gorush_client_test.dart`, `test/unit/fixtures/`
- Modify: `.env` (local, não versionado), `infra/docker/gorush/README.md`

**Interfaces:**
- Consumes: Tasks 1 a 3.
- Produces: `./scripts/qa/push_e2e.sh` que sobe a stack com o perfil `push`, roda o registro no emulador, envia como ACS e confere a notificação na bandeja do emulador, mais os casos negativos abaixo.

- [ ] **Step 1: Guarda da chave (a chave já existe; isto impede regressão)**

```bash
K=infra/docker/gorush/credentials/fcm-service-account.json
test -f $K || { echo "FALTA $K"; exit 3; }
git check-ignore -q $K || { echo "chave NÃO está ignorada pelo git"; exit 3; }
[ "$(stat -c %a $K)" = "600" ] || { echo "modo da chave diferente de 600"; exit 3; }
python3 - <<'PYEOF'
import json
k = json.load(open('infra/docker/gorush/credentials/fcm-service-account.json'))
g = json.load(open('apps/patient/android/app/google-services.json'))
assert k.get('type') == 'service_account', 'não é chave de conta de serviço'
assert k.get('project_id') == g['project_info']['project_id'], 'project_id difere do google-services.json'
assert k.get('client_email') and k.get('private_key'), 'chave incompleta'
print('chave ok para o projeto', k['project_id'])   # nunca imprime a chave
PYEOF
```

Expected: `chave ok para o projeto sinal-acs`. O mesmo bloco abre `scripts/qa/push_e2e.sh`, que sai com `3` e a instrução quando a chave falta (outra máquina, CI): no console do Firebase, Configurações do projeto → Contas de serviço → Gerar nova chave privada, salvar nesse caminho com modo `600`, e conferir que a API *Firebase Cloud Messaging API (V1)* está ativada no projeto.

- [ ] **Step 2: Stack de pé com o Gorush**

```bash
grep -q '^GORUSH_URL=' .env && sed -i 's|^GORUSH_URL=.*|GORUSH_URL=http://gorush:8088|' .env || echo 'GORUSH_URL=http://gorush:8088' >> .env
docker compose --profile push up -d --build
```

(edite o `.env` só por essa linha; ele é local e não versionado. Nunca imprima o `.env`.) Aguarde `sinalacs-serverpod` saudável e o seed terminar (`docker compose ps`), depois `docker compose logs gorush | tail -5`.
Expected: `gorush` de pé sem erro de credencial; o backend com `GORUSH_URL` definido (`docker compose exec serverpod printenv GORUSH_URL` imprime a URL).

- [ ] **Step 3: Registro real no emulador (GREEN de `push_register_test`)**

```bash
export PATH=$PATH:~/Android/Sdk/platform-tools:~/flutter/bin
adb -s emulator-5554 reverse tcp:8443 tcp:443
adb -s emulator-5554 shell pm grant br.com.prismrr.sinalacs.patient android.permission.POST_NOTIFICATIONS 2>/dev/null || true
cd apps/patient && flutter test integration_test/push_register_test.dart -d emulator-5554 \
  --dart-define=SINALACS_HOST=https://localhost:8443/
cd ../.. && docker compose exec -T postgres psql -U "$(grep ^POSTGRES_USER= .env | cut -d= -f2)" \
  -d "$(grep ^POSTGRES_DB= .env | cut -d= -f2)" -Atc "select count(*), min(platform) from push_tokens"
```

Expected: o teste PASSA e a consulta devolve `1|android` (uma linha, sem imprimir o token). O `pm grant` pode falhar se o app ainda não estiver instalado: rode de novo depois da primeira instalação.

- [ ] **Step 4: O envio real e a notificação na bandeja**

Com o app em **segundo plano** (FCM não mostra mensagem de notificação na bandeja com o app aberto):

```bash
adb -s emulator-5554 shell input keyevent KEYCODE_HOME
adb -s emulator-5554 shell cmd notification cancel_all 2>/dev/null || true
cd apps/acs && dart run tool/send_notice.dart --title "SinalACS e2e" --message "Teste do Gorush" 
sleep 8
adb -s emulator-5554 shell dumpsys notification --noredact | grep -A12 "pkg=br.com.prismrr.sinalacs.patient" | grep -E "title|text|SinalACS e2e|Teste do Gorush" | head
```

Expected: a ferramenta imprime `recipients=1 accepted=1` e o `dumpsys` mostra a notificação do pacote do app com o título `SinalACS e2e` e o texto `Teste do Gorush`. Se `accepted=0`, o erro está no Gorush/FCM: `docker compose logs gorush | tail -20` (com `hide_messages`, o texto não aparece no log). Capture, **sanitizada**, a resposta real do Gorush a esse envio bem-sucedido (o backend não a expõe: use o `gorush_smoke.sh` ou um `docker compose exec` que chame o Gorush de dentro da rede) e salve em `test/unit/fixtures/gorush_success.json`.

- [ ] **Step 5: Casos negativos reais (cada um observado, não suposto)**

1. **Token inválido é podado, o bom fica.** Insira um token falso para o mesmo titular e envie de novo:

```bash
PSQL="docker compose exec -T postgres psql -U $(grep ^POSTGRES_USER= .env | cut -d= -f2) -d $(grep ^POSTGRES_DB= .env | cut -d= -f2) -Atc"
UID_=$($PSQL "select \"userId\" from push_tokens limit 1")
$PSQL "insert into push_tokens (\"userId\",\"microAreaId\",token,platform,\"createdAt\",\"updatedAt\") select \"userId\",\"microAreaId\",'$(python3 -c "print('x'*150)")','android',now(),now() from push_tokens where \"userId\"='$UID_' limit 1"
(cd apps/acs && dart run tool/send_notice.dart --title "SinalACS e2e" --message "Poda")
$PSQL "select count(*) from push_tokens where \"userId\"='$UID_'"
```

Expected: a ferramenta imprime `recipients=2` e o `count` final é **1** (o falso foi apagado, o real ficou). A Task 1 Step 5 já provou a poda contra a resposta real do Gorush em isolamento; aqui ela é provada **de ponta a ponta** (backend → Gorush → FCM → banco). **Se continuar 2**, algo entre o backend e o Gorush difere do isolamento (token truncado na lista, `sync`, tempo): leia `docker compose logs serverpod | tail` e o log do Gorush, e corrija com um teste vermelho antes.

2. **Token `ios` com iOS desligado não apaga nada e não derruba o Android.** Insira uma linha `platform='ios'` e envie: a ferramenta não pode falhar, o token real continua recebendo (`accepted>=1`) e a linha `ios` **não** é apagada (erro de configuração do servidor não é erro do token).
3. **Revogar apaga os tokens e zera os destinatários.** No emulador, com o app de teste, `updateConsent(segmentedPush, granted: false)` (use `push_register_test` com uma variante ou o endpoint via a ferramenta); depois `send_notice` imprime `recipients=0` e nenhuma notificação nova chega.
4. **Gorush parado:** `docker compose stop gorush`, rode `send_notice`: deve sair com código `2` em **≤ 6 s** com "Não foi possível entregar o aviso agora…" (ou "resultado desconhecido", se estourar o tempo); `select result from audit_logs where "resourceType"='community_notice' order by timestamp desc limit 1` **não** pode ser `granted`. Religue com `docker compose start gorush`.
5. **Sem o `google-services.json` no build:** já provado na Task 2 (compila e degrada). Não repetir.

- [ ] **Step 6: O script que repete tudo**

`scripts/qa/push_e2e.sh` encadeia os Steps 1 a 4 (pré-condição da chave, stack, `adb reverse`, `pm grant`, registro no emulador, `KEYCODE_HOME`, envio, `dumpsys`) com `set -euo pipefail`, nenhum `echo` de segredo e `exit 3` claro quando a chave falta. Os casos negativos do Step 5 ficam como funções opcionais (`--negativos`). Escreva o script **depois** de ter rodado os passos à mão, com os comandos que funcionaram.

Run: `./scripts/qa/push_e2e.sh`
Expected: termina com `OK — o aviso chegou ao emulador` e código 0 na máquina que tem a chave; com código 3 e a instrução na que não tem.

- [ ] **Step 7: Suíte e commit**

Run: `cd backend/sinalacs_server && dart analyze | tail -1 && for i in 1 2 3 4 5; do dart test 2>&1 | tail -1; done; docker compose --profile push config -q`
Expected: analyze em 51 infos; 5 de 5 verdes.

```bash
git add scripts/qa/push_e2e.sh infra/docker/gorush backend/sinalacs_server
git commit -m "test(e2e): aviso do ACS chega ao emulador pelo Gorush real; poda e degradação provadas contra o FCM (RF14)"
```

---

### Task 5: Documentação, memória e verificação final

**Files:**
- Modify: `PROGRESS.md`, `apps/CLAUDE.md`, `backend/CLAUDE.md`, `spec/stack.md`, `docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md` (§3.2), `infra/docker/gorush/README.md`, memória (`rf14-gorush-2026-09-29` atualizada ou nova) e `MEMORY.md`.

- [ ] **Step 1:** Atualizar os docs com o que **foi observado**, item a item do checklist do README do Gorush (`counts`/`logs`, máscara do token, strings de erro do FCM v1, boot sem credenciais, tag fixada): cada um vira "verificado em <data> contra a 1.22.0" ou continua "não verificado". Se a Task 4 foi bloqueada pela chave, o texto diz **em primeiro plano** que o envio real NÃO foi provado, e lista o que falta (a chave e a API FCM v1 ativada). `apps/CLAUDE.md`: o lado nativo do canal agora existe, o plugin é condicional e o app degrada sem o arquivo. **iOS/APNs continua sem teste e sem implementação: dizer isso.**

- [ ] **Step 2: Verificação completa**

Run: `cd backend/sinalacs_server && for i in 1 2 3 4 5; do dart test 2>&1 | tail -1; done; dart analyze | tail -1; cd ../../apps/patient && flutter test && flutter analyze; cd ../acs && flutter test && flutter analyze; cd ../.. && docker compose config -q && docker compose --profile push config -q && ./scripts/qa/ci_invariants.sh; graphify update .`
Expected: backend 5 de 5, analyze em 51 infos e zero avisos; paciente e ACS verdes; compose e `ci_invariants` ok.

- [ ] **Step 3: Commit**

```bash
git add PROGRESS.md apps/CLAUDE.md backend/CLAUDE.md spec docs infra
git commit -m "docs: registra o que foi provado contra o Gorush e o FCM reais e o que não foi (RF14)"
```

---

## Fora desta rodada (por decisão)

- **iOS/APNs:** nenhum app iOS, nenhuma chave APNs; `ios.enabled` fica `false`.
- Renovação do token (`onNewToken`) e abrir uma tela ao tocar na notificação (`data.screen`).
- Enviar pelo perfil `admin` (o backend do admin não existe) e agendamento de avisos.
- Hospedar o Gorush fora do Compose local e a rotação da chave da conta de serviço.

## Autorrevisão

- **Cobertura:** "analisar a configuração" → Task 1 (prova que o boot atual falha, corrige, fixa a tag, captura a resposta real); "finalizar a configuração" → Tasks 1 e 2 (Gorush + lado nativo Android + plugin condicional); "testes com o Gorush" → Tasks 3 e 4 (registro real, envio real, bandeja, casos negativos); "emulador 5554" → Tasks 2 e 4; docs → Task 5. Os itens do Review Focus têm teste: build sem o arquivo (Task 2 Step 5), token `ios` (Task 4 Step 5.2), poda real (5.1), máscara do token (5.1 e Task 1 Step 4), Gorush parado (5.4), app em segundo plano (Step 4), permissão (Step 3 com `pm grant`).
- **Placeholders:** `<RELEASE-CONFIRMADA>` (Task 2) é substituído no Step 2 pelo valor lido do Google Maven, que o passo manda ler e registrar; o preâmbulo de `push_register_test` e de `send_notice.dart` remete a dois arquivos existentes com o comando exato para lê-los; as chaves `android.*` do Gorush 1.22.0 são confirmadas por `--help` no Task 1 Step 3. Nenhum comportamento ficou por definir.
- **Tipos:** `PushTarget`/`PushMessage`/`PushSendReport`/`PushGatewayException`, `NativePushTokenSource`, `registerPushToken`, `updateConsent`, `sendNotice` e o canal `sinalacs/push_token` usam os nomes que já existem no código.
- **Riscos declarados:** (1) a chave existe e tem estrutura válida, mas **não está provado que funciona**: API FCM V1 desativada, papel insuficiente ou chave revogada só aparecem no Task 1 Step 4, que para e diz o que ajustar; (2) o plugin do Google Services pode não ser compatível com o AGP 9.0.1; (3) a imagem do emulador pode não entregar FCM de forma confiável (token sai, mas a entrega depende da conectividade do Play Services); (4) `dumpsys notification` varia entre versões do Android — se o formato mudar, o passo de conferência ajusta o `grep`, não o critério (a notificação tem de existir).
