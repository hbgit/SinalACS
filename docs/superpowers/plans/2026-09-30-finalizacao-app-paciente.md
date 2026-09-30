# Finalização do app do paciente — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fechar o que resta técnico no `apps/patient` (lacuna LGPD do token FCM pedido sem consentimento), provar o app inteiro no emulador `emulator-5554` e deixar o repositório pronto para a primeira execução da CI da branch `fix/patient`.

**Architecture:** O app só pede o token ao FCM depois de confirmar, no servidor, que a decisão mais recente de `segmentedPush` é `granted` (mesma fonte que `PatientDataOverview.consents` já expõe; sem espelho local novo). O resto do plano é verificação: bateria do app, e2e no emulador e conferência do que a CI vai rodar.

**Tech Stack:** Flutter 3 / Dart, `sinalacs_client` (Serverpod), Docker Compose, `scripts/qa/e2e.sh`, `scripts/qa/push_e2e.sh`, emulador Android.

**Spec:** `spec/PRD_system.md` (RF01–RF06, RF14, RF16, RF18), `spec/lgpd_design.md` (seção "`ConsentPurpose.segmentedPush` tem leitor, com uma lacuna no aparelho"), `PROGRESS.md` (seção "RF14: Gorush e FCM provados no emulador").

## Estado verificado em 2026-09-30 (antes deste plano)

- `flutter analyze` em `apps/patient`: sem problemas. `flutter test`: **225 passam**.
- RF01–RF06, RF14 (Android), RF18, "Meus Dados" LGPD, QR, termos: construídos (ver `PROGRESS.md`).
- **Emulador 5554 NÃO está no ar**: `adb devices` vem vazio e o AVD `sinal-acs` citado no `PROGRESS.md` não existe nesta máquina (só `Medium_Phone` e `Medium_Tablet`). `adb` não está no `PATH`: usar `~/Android/Sdk/platform-tools/adb`. A Task 0 resolve isso.
- Compose: só o `gorush` está de pé; o resto da stack está parado.

## Global Constraints

- Textos de UI, comentários e mensagens de commit em português.
- Alerta vermelho nunca é descartado nem atrasado: nada aqui pode bloquear login, home ou o botão de urgência. O registro de push continua silencioso e fora do caminho crítico.
- Nenhum dado real de paciente em testes, logs ou capturas.
- Classificação de risco continua vinda só de `triage.evaluate` (determinística).
- `legalDocumentsVersion` (app) == `consentPolicyVersion` (backend): não mudar versão nem agendar mudança de termos.
- `flutter analyze` sem problemas e `flutter test` verde antes de cada commit.
- Commits terminam com `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. Sem push nem merge sem o usuário pedir.

## Review Focus

- Consentimento `segmentedPush` revogado ou nunca decidido: o app **não** chama `currentDevice()` (nem o FCM). Teste na Task 1.
- `myData()` lento, falhando ou sem rede no login: o login/home não atrasam e nada é registrado (falha fecha, não abre). Teste na Task 1.
- Consentimento concedido na tela "Meus Dados" depois do login: o token é pedido e registrado nessa hora, sem nova chamada a `myData()`. Teste na Task 1.
- Histórico de consentimento com `granted` seguido de `revoked`: vale o mais recente. Teste na Task 1.
- Emulador sem a permissão `POST_NOTIFICATIONS`: o token registra mas o aviso não aparece; o e2e concede por `adb`. Conferido na Task 3.

---

### Task 0: Emulador 5554 e stack local

**Files:**
- Nenhum arquivo do repositório muda (ambiente).

**Interfaces:**
- Produces: `emulator-5554` em `device`, stack do Compose saudável, `.env` presente. As Tasks 2 e 3 dependem disso.

- [ ] **Step 1: Confirmar o estado**

```bash
export PATH="$HOME/Android/Sdk/platform-tools:$HOME/Android/Sdk/emulator:$PATH"
adb devices -l
emulator -list-avds
```
Expected hoje: lista de devices vazia; AVDs `Medium_Phone` e `Medium_Tablet`.

- [ ] **Step 2: Subir o emulador (o primeiro a subir recebe a porta 5554)**

```bash
emulator -avd Medium_Phone -no-snapshot-save -no-audio > /tmp/emu.log 2>&1 &
adb wait-for-device
until [ "$(adb shell getprop sys.boot_completed | tr -d '\r')" = "1" ]; do sleep 3; done
adb devices
```
Expected: `emulator-5554   device`. Se vier outra porta (já havia um emulador), fechar o outro e repetir: os scripts usam `emulator-5554` fixo. Se o AVD for API < 29 ou sem Google Play services, o teste de push (Task 3) não terá FCM; criar um AVD com imagem `google_apis` (`sdkmanager`/`avdmanager`) chamado `sinal-acs`.

- [ ] **Step 3: Configurar e subir a stack**

```bash
cd /home/rock/Documents/Dev/APPs/SinalACS
[ -f .env ] || ./scripts/dev/bootstrap_env.sh
docker compose up --build -d
docker compose ps
```
Expected: `backend`, `postgres`, `mosquitto`, `traefik` saudáveis e os quatro seeds concluídos (`database-seed`, `health-data-seed`, `acs-credential-seed`, `cpf-hash-seed`). Um `pg_data/` antigo pode perder dados clínicos sintéticos (migração `20260917191250458`): aceitável, ou `docker compose down && rm -rf pg_data/` antes.

- [ ] **Step 4: Sem commit** (nada versionado mudou).

---

### Task 1: Não pedir o token ao FCM sem consentimento `segmentedPush` (fecha a lacuna LGPD)

**Files:**
- Modify: `apps/patient/lib/core/push/push_token_source.dart` (função `registerPushDevice`, linhas 36-44)
- Modify: `apps/patient/lib/app/app.dart:462`, `:815` (chamadas pós-login) e `:1870` (chamada pós-concessão)
- Modify: `apps/patient/test/support/fake_patient_backend.dart` (o `myData()` do fake precisa aceitar consentimentos configuráveis; ler o arquivo antes)
- Test: `apps/patient/test/push_registration_test.dart`

**Interfaces:**
- Consumes: `PatientBackend.myData()` → `PatientDataOverview` (com `.consents`); `currentConsentDecisions(List<PatientConsentRecord>) → Map<ConsentPurpose, bool>` em `lib/core/consent/consent_decisions.dart`; `PushTokenSource.currentDevice()`.
- Produces: `Future<void> registerPushDevice(PatientBackend backend, PushTokenSource source, {bool consentKnownGranted = false})`. Com `consentKnownGranted: false` ela consulta `myData()` (teto de 3 s) e só prossegue se `currentConsentDecisions(...)[ConsentPurpose.segmentedPush] == true`.

- [ ] **Step 1: Ler o fake e os testes existentes**

Ler `test/support/fake_patient_backend.dart` (como `myData()` e `pushRegistrations` estão montados) e `test/push_registration_test.dart` inteiro. Os testes atuais esperam registro logo após o login: passam a precisar de um fake cujo `myData()` devolva `segmentedPush` `granted`. Adicionar ao fake um campo `List<PatientConsentRecord> consents` (padrão: `segmentedPush` granted) usado por `myData()`, sem mudar o que os outros testes veem (o padrão deve reproduzir o que eles já assumem; se algum depender de histórico vazio, dar a esse teste um fake próprio).

- [ ] **Step 2: Escrever os testes que falham**

Acrescentar em `test/push_registration_test.dart` (mesmo estilo do arquivo; `login`, `_FakeSource` e `_aparelho` já existem). Usar um `_FakeSource` que conta chamadas:

```dart
class _CountingSource implements PushTokenSource {
  int calls = 0;
  @override
  Future<PushDevice?> currentDevice() async {
    calls++;
    return _aparelho;
  }
}

testWidgets('sem consentimento de avisos, nem pergunta o token ao provedor', (tester) async {
  final backend = FakePatientBackend(consents: const []);
  final source = _CountingSource();
  await tester.pumpWidget(SinalAcsApp(backend: backend, pushTokens: source));
  await login(tester);

  expect(source.calls, 0);
  expect(backend.pushRegistrations, isEmpty);
  expect(find.byType(PatientHomeShell), findsOneWidget);
});

testWidgets('consentimento revogado depois de concedido vale o mais recente', (tester) async {
  final backend = FakePatientBackend(consents: [
    _registro('segmentedPush', 'granted', DateTime(2026, 9, 1)),
    _registro('segmentedPush', 'revoked', DateTime(2026, 9, 2)),
  ]);
  final source = _CountingSource();
  await tester.pumpWidget(SinalAcsApp(backend: backend, pushTokens: source));
  await login(tester);

  expect(source.calls, 0);
});

testWidgets('myData falhando no login fecha: nada é pedido nem registrado', (tester) async {
  final backend = FakePatientBackend()..failMyData = true;
  final source = _CountingSource();
  await tester.pumpWidget(SinalAcsApp(backend: backend, pushTokens: source));
  await login(tester);

  expect(source.calls, 0);
  expect(find.byType(PatientHomeShell), findsOneWidget);
});
```
`_registro(purpose, action, timestamp)` monta um `PatientConsentRecord` com os campos que o arquivo de fake já usa em outros testes (copiar a construção de lá; se o fake ainda não tiver `failMyData`, adicioná-lo: `myData()` lança `BackendFailure('falha')` quando `true`).

- [ ] **Step 3: Rodar e ver falhar**

Run: `cd apps/patient && flutter test test/push_registration_test.dart`
Expected: os três testes novos FALHAM (hoje o app pergunta o token sempre); os antigos seguem verdes.

- [ ] **Step 4: Implementar**

Em `lib/core/push/push_token_source.dart`, substituir `registerPushDevice`:

```dart
const _consentLookupTimeout = Duration(seconds: 3);

Future<void> registerPushDevice(
  PatientBackend backend,
  PushTokenSource source, {
  bool consentKnownGranted = false,
}) async {
  try {
    // LGPD: o aparelho só fala com o provedor (Google/Apple) depois de o
    // servidor confirmar o consentimento vigente de avisos. Na dúvida (falha,
    // teto estourado, nunca decidiu) não pergunta: fecha, não abre.
    if (!consentKnownGranted) {
      final overview = await backend.myData().timeout(_consentLookupTimeout);
      if (currentConsentDecisions(overview.consents)[ConsentPurpose.segmentedPush] != true) return;
    }
    final device = await source.currentDevice();
    if (device == null) return;
    await backend.registerPushToken(token: device.token, platform: device.platform);
  } catch (_) {
    // Intencionalmente silencioso — ver acima.
  }
}
```
Adicionar os imports de `consent_decisions.dart` e de `ConsentPurpose` (o mesmo import que `app.dart` usa). Em `app.dart:1870`, a chamada logo após conceder passa `consentKnownGranted: true`. Conferir que o texto do comentário de documentação acima da função continue verdadeiro e ajustá-lo (ele diz "tenta de novo no próximo login ou ao conceder").

- [ ] **Step 5: Teste da concessão posterior**

Acrescentar (o teste deve falhar se a chamada de `:1870` perder o flag e passar a consultar `myData()` de novo — o fake conta chamadas de `myData`):

```dart
testWidgets('conceder avisos em Meus Dados registra o token sem nova consulta', (tester) async {
  final backend = FakePatientBackend(consents: const []);
  final source = _CountingSource();
  await tester.pumpWidget(SinalAcsApp(backend: backend, pushTokens: source));
  await login(tester);
  final antes = backend.myDataCalls;

  // abrir Meus Dados e conceder "Avisos da equipe": copiar os gestos do teste
  // equivalente de `patient_app_mvp_test.dart` que concede `segmentedPush`.
  await concederAvisos(tester);

  expect(backend.pushRegistrations, [('tok-1', 'android')]);
  expect(backend.myDataCalls - antes, lessThanOrEqualTo(1)); // só o refresh da própria tela
});
```
`concederAvisos` é uma função de apoio do arquivo: localizar em `patient_app_mvp_test.dart` o teste que concede `segmentedPush` e reaproveitar os mesmos `find`/`tap`. O fake ganha `int myDataCalls`.

- [ ] **Step 6: Rodar tudo do app**

Run: `cd apps/patient && flutter analyze && flutter test`
Expected: sem problemas; todos os testes verdes (225 + novos).

- [ ] **Step 7: Documentação**

Em `spec/lgpd_design.md` (parágrafo "Lacuna:" logo após `ConsentPurpose.segmentedPush tem leitor`), trocar a lacuna por: o app só pede o token ao FCM depois de `myData()` mostrar `segmentedPush` vigente como `granted`, e fecha na dúvida. Em `apps/CLAUDE.md`, remover a frase "app still asks FCM for token every login even without `segmentedPush` consent … known LGPD gap". Em `PROGRESS.md`, acrescentar a seção "Token de push só com consentimento (2026-09-30)" com o que foi feito e a nova contagem de testes.

- [ ] **Step 8: Commit**

```bash
git add apps/patient spec/lgpd_design.md apps/CLAUDE.md PROGRESS.md
git commit -m "fix(paciente): token de push só é pedido ao provedor com consentimento de avisos vigente (RF14, LGPD)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Bateria e2e do app do paciente no emulador 5554

**Files:**
- Nenhum arquivo muda, salvo correções que a execução exigir (cada correção vira commit próprio, com teste).
- Usa: `scripts/qa/e2e.sh`, `apps/patient/integration_test/{smoke_test,backend_connection_test}.dart`, `apps/patient/tool/live_check.dart`.

**Interfaces:**
- Consumes: Task 0 (emulador + stack) e Task 1 (código novo já no app que vai ser instalado).
- Produces: registro em `PROGRESS.md` do que passou no emulador, com data e comando.

- [ ] **Step 1: Ler o uso do script**

Run: `./scripts/qa/e2e.sh --help 2>&1 | head -40` (se não houver `--help`, ler o cabeçalho do arquivo). Confirmar as flags `--emulator` e `--full` e se existe filtro por app.

- [ ] **Step 2: Checagem viva contra o backend (sem emulador)**

Run: `cd apps/patient && dart run tool/live_check.dart`
Expected: passa contra `https://localhost/` (login OTP, triagem, alerta, status, Meus Dados).

- [ ] **Step 3: Smoke + conexão real no emulador**

Run: `./scripts/qa/e2e.sh --emulator` e depois, para só o paciente, `cd apps/patient && flutter test integration_test/smoke_test.dart integration_test/backend_connection_test.dart -d emulator-5554`
Expected: verde. Falha de `adb install` com "Broken pipe" é transitória conhecida (o script já repete).

- [ ] **Step 4: Se algo falhar, seguir `superpowers:systematic-debugging`**

Reproduzir, achar a causa, escrever o teste que falha, corrigir, repetir o Step 3. Nada de "retry até passar".

- [ ] **Step 5: Registrar e commitar**

Acrescentar a `PROGRESS.md` uma linha sob a seção da Task 1: comandos rodados, emulador (AVD/API) e resultado. Commit:

```bash
git add PROGRESS.md
git commit -m "docs: registra a bateria e2e do app do paciente no emulador 5554

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Entrega de push ponta a ponta com o consentimento novo

**Files:**
- Nenhum arquivo muda, salvo correções.
- Usa: `scripts/qa/push_e2e.sh`, `apps/patient/integration_test/{push_register_test,push_native_token_test}.dart` (só rodam com `--dart-define=PUSH_E2E=1`).

**Interfaces:**
- Consumes: Task 1 (o app agora consulta `myData()` antes do token) e a chave de serviço do FCM em `GORUSH_CREDENTIALS_DIR` + `android/app/google-services.json` (ambos fora do git).
- Produces: prova de que a Task 1 não quebrou a entrega no emulador.

- [ ] **Step 1: Pré-condições**

```bash
ls apps/patient/android/app/google-services.json
unset GORUSH_CREDENTIALS_DIR   # o script ignora o valor do ambiente, mas melhor não arrastá-lo
```
Sem `google-services.json` ou sem a chave do FCM, **pular esta task e registrar que não foi possível**; não fingir que passou.

- [ ] **Step 2: Rodar**

Run: `./scripts/qa/push_e2e.sh --negativos`
Expected: `recipients=1 accepted=1`; os negativos (token falso podado, Gorush parado, revogação) passam como em `PROGRESS.md`. O teste de registro usa `Avisos da equipe` concedido, então deve continuar registrando com a Task 1.

- [ ] **Step 3: Conferir o caso novo à mão no emulador**

Com o app instalado, entrar com um paciente do seed que **não** concedeu `segmentedPush`, e confirmar no backend que não há linha nova em `push_tokens`:

```bash
docker compose exec postgres psql -U postgres -d sinalacs -c 'select count(*) from push_tokens;'
```
Expected: contagem inalterada após o login. (Nome do banco/usuário: ver `.env`; ajustar se diferir.)

- [ ] **Step 4: Registrar e commitar** (mesmo formato da Task 2, Step 5).

---

### Task 4: Pronto para a primeira execução da CI

**Files:**
- Modify: `PROGRESS.md` (registro).
- Sem código novo, salvo correções.

**Interfaces:**
- Consumes: Tasks 1–3 commitadas.
- Produces: branch `fix/patient` limpa e verificada localmente com o que a CI rodará para o paciente.

- [ ] **Step 1: Invariantes da CI**

Run: `./scripts/qa/ci_invariants.sh`
Expected: sem falhas (a branch nunca rodou na CI; este é o mais perto disso sem rede).

- [ ] **Step 2: Mesmo caminho do job `patient-app`**

```bash
cd apps/patient && flutter pub get && flutter analyze && flutter test
flutter build apk --debug
```
Expected: verde. O build sem `google-services.json` precisa funcionar (o plugin do Google Services só aplica quando o arquivo existe); se o arquivo existir localmente, renomeá-lo temporariamente para simular a CI e devolver depois.

- [ ] **Step 3: Backend (só se a Task 1 tiver tocado algo lá — não deve)**

Run: `cd backend/sinalacs_server && dart test` — pular se `git diff main --stat -- backend` não mostrar mudança nesta rodada.

- [ ] **Step 4: Atualizar a contagem de testes e o "o que falta"**

Em `PROGRESS.md`, atualizar a contagem de testes do paciente e listar o que **continua** fora deste plano: iOS/APNs, aparelho físico, Gorush hospedado, revisão jurídica do texto 2026.1, backoffice que atende exclusão/correção (LGPD), MFA/refresh token, menores deferidos do RF14.

- [ ] **Step 5: Commit**

```bash
git add PROGRESS.md
git commit -m "docs: fecha a rodada de finalização do app do paciente e lista o que segue aberto

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## Fora do escopo (decisões e dependências externas)

- **iOS/APNs:** exige Mac/Xcode e chave APNs; o lado Swift do `sinalacs/push_token` não existe.
- **Aparelho físico e Gorush hospedado:** dependem de infraestrutura e de credenciais fora do repositório.
- **Backoffice de atendimento** de exclusão/correção (`apps/admin` ainda é mock): é outro plano, com backend próprio.
- **Revisão jurídica** do texto 2026.1 dos termos.
- **Permissões do host (fora do repo):** `chmod 600` na cópia da chave em `/opt/apps_android/fcm-service-account.json`.

## Self-review

- **Cobertura:** a lacuna LGPD (Task 1), configuração do ambiente (Task 0), testes no emulador (Tasks 2–3) e prontidão para CI (Task 4) estão cobertos; RF01–RF06/RF16/RF18 já passam na bateria existente e são reexecutados na Task 2.
- **Placeholders:** os helpers `_registro`, `concederAvisos`, `failMyData`, `myDataCalls` e `consents` do fake são definidos nas Steps 1, 2 e 5 da Task 1 com instrução de onde copiar a construção; nenhum outro trecho depende de tipo indefinido.
- **Consistência:** a assinatura `registerPushDevice(backend, source, {consentKnownGranted})` é a mesma na definição (Step 4) e nos usos (`app.dart:462`, `:815` sem flag; `:1870` com flag).
