# Verificação das pendências do backoffice (#39) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Confirmar, com evidência executada, quais das cinco pendências registradas em `PROGRESS.md` (seção "Minors adiados da #39") continuam abertas, usando o smartphone `0087014315`, e registrar o resultado.

**Architecture:** Este é um plano de **verificação**, não de correção. Os itens 1 e 2 são executáveis agora (prova E2E e recaptura de telas no aparelho). Os itens 3 e 4 são lacunas de projeto: o plano as **confirma com testes/leitura de código** e deixa a correção para um plano próprio (exige decisão de produto). O item 5 é fechado se for trivial. A única mudança de código é parametrizar o aparelho no script de E2E (hoje fixo em `emulator-5554`).

**Tech Stack:** bash, adb, Flutter (`integration_test`), Serverpod (Dart), Docker Compose, `oathtool`/Dart para TOTP.

**Spec:** `PROGRESS.md` (seção "Minors adiados da #39 (2026-10-06)" e "Login real do backoffice (issue #39)"); `scripts/qa/admin_login_e2e.sh`; `docs/telas-admin.md`.

## Global Constraints

- Dispositivo de teste: serial `0087014315` (Motorola edge 40 neo, Android 15, API 35, 1080x2400, densidade 400), via USB.
- Só dados sintéticos: o script usa o banco `sinalacs_e2e` e apaga banco e manifesto ao final. Nada no banco de desenvolvimento.
- Commits **sem** `Co-Authored-By` nem "Generated with Claude Code" (regra do `CLAUDE.md` do projeto).
- Texto de documentação em português; `PROGRESS.md` e `docs/telas-admin.md` só afirmam o que foi executado.
- `scripts/qa/e2e_stack.sh up` **recria** `sinalacs-serverpod`, `-traefik`, `-mosquitto`, `-gorush-1` da stack de desenvolvimento. O ambiente recusou isso numa tentativa anterior: o usuário deve rodar esses comandos com o prefixo `!`. Ao final, `docker compose up -d` devolve a stack de desenvolvimento.
- Alterar `scripts/qa/*.sh` não pode quebrar `./scripts/qa/ci_invariants.sh` (CI vigia o workflow, não estes scripts, mas rode-o).

## Review Focus

- Aparelho físico não alcança `localhost` do host: sem `adb reverse tcp:8443 tcp:443` o app falha com erro de rede, não de login. O script já faz o `reverse`; o teste do Task 1 confere que ele usa o serial escolhido.
- Dois aparelhos conectados (emulador + celular): `adb` sem `-s` falha com "more than one device". Todo `adb`/`flutter -d` do plano usa o serial.
- Tela bloqueada ou "Instalar via USB" negado no Motorola: a instalação do `integration_test` falha silenciosamente longa; o preflight confere.
- Relé de credencial entrega a senha do admin **uma vez**: rodar o script duas vezes sem recriar fixtures dá 404 no relé.
- Densidade/tamanho alterados com `wm` precisam ser revertidos mesmo se a captura falhar (trap).
- O segredo TOTP aparece só na tela de ativação (`Key('mfa_secret')`): perder essa tela perde a conta da sessão manual.

---

## File Structure

- Modify: `scripts/qa/admin_login_e2e.sh` — aceitar `DEVICE` (serial); padrão continua `emulator-5554`.
- Create: `scripts/qa/admin_login_e2e_test.sh` — teste de shell (sem Docker) da seleção do aparelho.
- Modify: `docs/telas-admin.md`, `docs/screenshots/admin/02..08-*.png` — recaptura (Task 3).
- Modify: `PROGRESS.md` — registrar o resultado de cada item (Task 7).
- Modify (só se o `dart format` apontar): `backend/sinalacs_server/test/integration/staff_login_test.dart`.

---

### Task 1: Parametrizar o aparelho do `admin_login_e2e.sh`

**Files:**
- Modify: `scripts/qa/admin_login_e2e.sh` (linha `dev=emulator-5554`)
- Create: `scripts/qa/admin_login_e2e_test.sh`

**Interfaces:**
- Produces: variável de ambiente `DEVICE` (serial do `adb`); sem ela, `emulator-5554`.

- [ ] **Step 1: Escrever o teste que falha**

```bash
#!/usr/bin/env bash
# Confere que admin_login_e2e.sh escolhe o aparelho por DEVICE e usa o serial em
# todo adb/flutter. Sem Docker, sem aparelho: lê o texto do script.
set -euo pipefail
cd "$(dirname "$0")/../.."
s=scripts/qa/admin_login_e2e.sh
falhas=0
conferir() { if ! eval "$2"; then echo "FALHOU: $1" >&2; falhas=$((falhas+1)); fi; }

conferir 'DEVICE com padrão emulator-5554' "grep -qE '^dev=\"\\$\\{DEVICE:-emulator-5554\\}\"' $s"
conferir 'nenhum serial fixo fora do padrão' "[[ \$(grep -c 'emulator-5554' $s) -le 3 ]]"
conferir 'adb reverse usa \$dev' "grep -q 'adb -s \"\$dev\" reverse tcp:8443 tcp:443' $s"
conferir 'flutter test usa -d \$dev' "grep -q -- '-d \"\$dev\"' $s"
[[ $falhas -eq 0 ]] && echo 'ok' || exit 1
```

Salvar em `scripts/qa/admin_login_e2e_test.sh`, `chmod +x`.

- [ ] **Step 2: Rodar e ver falhar**

Run: `bash scripts/qa/admin_login_e2e_test.sh`
Expected: `FALHOU: DEVICE com padrão emulator-5554` (o script tem `dev=emulator-5554`).

- [ ] **Step 3: Implementar**

Em `scripts/qa/admin_login_e2e.sh`, trocar `dev=emulator-5554` por:

```bash
dev="${DEVICE:-emulator-5554}"
```

e ajustar a mensagem de erro `emulador $dev não encontrado` para `aparelho $dev não encontrado (adb devices)`. Cabeçalho: acrescentar a linha `#   DEVICE=0087014315 ./scripts/qa/admin_login_e2e.sh   # aparelho físico`.

- [ ] **Step 4: Rodar e ver passar**

Run: `bash scripts/qa/admin_login_e2e_test.sh && bash -n scripts/qa/admin_login_e2e.sh && ./scripts/qa/ci_invariants.sh`
Expected: `ok`, sem erro de sintaxe, invariantes ok.

- [ ] **Step 5: Commit**

```bash
git add scripts/qa/admin_login_e2e.sh scripts/qa/admin_login_e2e_test.sh
git commit -m "test(qa): admin_login_e2e.sh aceita o aparelho por DEVICE"
```

---

### Task 2: Item 1 — rodar a prova E2E do login real no celular

**Files:** nenhum modificado (gera evidência).

**Interfaces:**
- Consumes: `DEVICE` do Task 1.
- Produces: saída do script (cole no Task 7).

- [ ] **Step 1: Preflight do aparelho**

Run:
```bash
export PATH="$PATH:$HOME/Android/Sdk/platform-tools"
adb -s 0087014315 get-state
adb -s 0087014315 shell dumpsys power | grep -E "mWakefulness=|Display Power"
adb -s 0087014315 shell settings put global stay_on_while_plugged_in 3
adb -s 0087014315 shell input keyevent KEYCODE_WAKEUP && adb -s 0087014315 shell wm dismiss-keyguard
```
Expected: `device`; `mWakefulness=Awake`. Se o celular pedir "Permitir instalação via USB", aceitar na tela.

- [ ] **Step 2: Conferir que nenhuma instância do app de teste ficou instalada e a porta 8765 está livre**

Run: `adb -s 0087014315 shell pm list packages | grep -i sinalacs; ss -ltn | grep -E ':8765\b' || echo livre`
Expected: sem pacote do admin de teste ou o usuário concorda em reinstalar; `livre`.

- [ ] **Step 3: Rodar a prova (o usuário executa; recria containers de dev)**

Pedir ao usuário que rode no prompt:
```
! DEVICE=0087014315 ./scripts/qa/admin_login_e2e.sh
```
Expected (resumo): `== login do backoffice no emulador` termina sem erro; linhas `TOTP ativado e passo registrado: true|true` e `tentativas falhas zeradas pelo login: 0`; exit 0. Qualquer outra coisa: usar `superpowers:systematic-debugging` antes de editar; anotar a causa.

- [ ] **Step 4: Devolver a stack de desenvolvimento**

Pedir: `! docker compose up -d && docker compose ps`
Expected: serviços `healthy`.

- [ ] **Step 5: Decidir o estado do item 1**

Aprovado: item 1 **fechado em aparelho físico (Android 15)**, não no emulador — registrar exatamente isso. Reprovado: item 1 segue aberto, com a causa.

---

### Task 3: Item 2 — recapturar as telas 02–08 com sessão real

**Files:**
- Modify: `docs/screenshots/admin/02-indicadores.png` … `08-tablet-rail.png`
- Modify: `docs/telas-admin.md` (parágrafo da linha 13 e legendas)

**Interfaces:**
- Consumes: stack de e2e **no ar** (não rodar o `down` do Task 2 até terminar) e fixtures do admin. O `admin_login_e2e.sh` apaga tudo ao sair; portanto esta tarefa usa a stack manualmente.

Os fixtures do admin vêm de `./scripts/qa/e2e_stack.sh seed`; a senha é entregue pelo relé em `/admin` uma única vez.

- [ ] **Step 1: Subir a stack de e2e e semear (o usuário executa)**

```
! ./scripts/qa/e2e_stack.sh up && ./scripts/qa/e2e_stack.sh seed
```
Depois, com o relé (`scripts/qa/otp_relay.py`, `E2E_FIXTURES_FILE=$PWD/.e2e/fixtures.json`) em segundo plano:
```bash
adb -s 0087014315 reverse tcp:8443 tcp:443
adb -s 0087014315 reverse tcp:8765 tcp:8765
python3 -c "import json;d=json.load(open('.e2e/fixtures.json'))['staff'];print(d['id'])"
curl -fs http://127.0.0.1:8765/admin   # credencial, UMA vez: anotar matrícula e senha
```
Expected: JSON com matrícula e senha sintéticas.

- [ ] **Step 2: Instalar e abrir o app admin no celular**

Run: `cd apps/admin && flutter run -d 0087014315 --dart-define=SINALACS_HOST=https://localhost:8443/`
Expected: tela de login do backoffice.

- [ ] **Step 3: Ativar a MFA e entrar**

Na tela, entrar com matrícula/senha → tela de ativação mostra `SelectableText` com a chave (`Key('mfa_secret')`). **Copiar a chave** e gerar o código:
```bash
oathtool --base32 --totp "<CHAVE>"   # se não houver oathtool: sudo dnf install -y oathtool
```
Digitar o código; esperar o "Painel de Indicadores". Para os logins seguintes, gerar novo código (passo de 30 s; o servidor recusa reutilizar o mesmo passo).

- [ ] **Step 4: Capturar**

```bash
d=0087014315; out=docs/screenshots/admin
adb -s $d exec-out screencap -p > $out/02-indicadores.png   # tela Indicadores
# navegar: Microáreas -> 03, Alertas -> 04, Auditoria -> 05 (mesmo comando)
adb -s $d exec-out screencap -p > $out/06-android-retrato.png
# girar: adb -s $d shell settings put system accelerometer_rotation 0; adb -s $d shell settings put system user_rotation 1
adb -s $d exec-out screencap -p > $out/07-android-paisagem.png
adb -s $d shell settings put system user_rotation 0
```
Expected: PNGs com o cabeçalho novo ("Backoffice • Administrador"), sem dados reais (dados do `MockAdminDataSource`, sintéticos).

- [ ] **Step 5: Captura 08 (tablet com rail) por simulação de tamanho**

```bash
trap 'adb -s 0087014315 shell wm size reset; adb -s 0087014315 shell wm density reset' EXIT
adb -s 0087014315 shell wm size 1600x2560 && adb -s 0087014315 shell wm density 280
adb -s 0087014315 exec-out screencap -p > docs/screenshots/admin/08-tablet-rail.png
```
Expected: layout com navigation rail. Conferir a imagem com Read. Se o app não relayouta sem reiniciar, reabrir o app (nova sessão exige novo código TOTP).

- [ ] **Step 6: Revisar cada PNG**

Abrir cada uma das sete com `Read`. Rejeitar captura com notificação do sistema, barra de status com dados pessoais, ou nome de rede. Recapturar se houver.

- [ ] **Step 7: Atualizar `docs/telas-admin.md`**

Na linha 3 e no parágrafo da linha 13, trocar a afirmação de "capturas 02 a 08 ainda mostram o texto antigo" por: capturas 02–08 recapturadas em 2026-10-07 num Motorola edge 40 neo (Android 15) com sessão real; 08 com `wm size` 1600x2560 simulado (não é um tablet físico). Ajustar também a menção de "emulator-5554" na linha 3 para dizer aparelho físico.

- [ ] **Step 8: Derrubar a stack e voltar à de desenvolvimento (o usuário executa)**

```
! ./scripts/qa/e2e_stack.sh down && docker compose up -d
```
Run depois: `adb -s 0087014315 shell wm size; adb -s 0087014315 shell settings get system user_rotation`
Expected: `Physical size: 1080x2400` sem `Override`; rotação 0.

- [ ] **Step 9: Commit**

```bash
git add docs/screenshots/admin docs/telas-admin.md
git commit -m "docs(admin): recaptura as telas 02-08 com sessão real em aparelho físico (#39)"
```

---

### Task 4: Item 3 — confirmar o trust-on-first-use da ativação do TOTP do staff

**Files:**
- Read: `backend/sinalacs_server/lib/src/application/auth/institutional_auth_service.dart:269-336`, `lib/src/endpoints/auth_endpoint.dart:151-170`
- Test (temporário, não commitado): `/tmp/…/scratchpad/tofu_check_test.dart` ou execução do teste existente

- [ ] **Step 1: Ler o fluxo**

Confirmar no código que `beginTotpEnrollment` e `confirmTotpEnrollment` só chamam `_authenticatePassword(matricula, password)` (nenhum fator extra) e que `beginStaffTotpEnrollment` não exige token de sessão (o doc comment diz "Sem token").

- [ ] **Step 2: Provar contra Postgres de teste**

Run:
```bash
cd backend/sinalacs_server && dart test test/integration/staff_login_test.dart -N "ativação"
```
Expected: os testes de ativação passam com `matricula + password` apenas, o que demonstra que qualquer um que conheça a senha inicial pode registrar o **próprio** autenticador antes do dono. Se `-N` não casar, listar nomes (`grep -n "test(" -A1 test/integration/staff_login_test.dart`) e usar o nome real.

- [ ] **Step 3: Registrar o desenho de correção (sem implementar)**

Anotar para o plano de correção, a ser feito com `superpowers:brainstorming` antes de codar (decisão de produto): código de ativação de uso único, gerado fora de banda (CLI do administrador), guardado só como hash em `staff_accounts` com expiração curta, exigido por `beginStaffTotpEnrollment`/`confirmStaffTotpEnrollment` e consumido na confirmação; ativação por quem já tem sessão de administrador (#43) como alternativa. **Bloqueia a #40.**

- [ ] **Step 4: Estado**

Item 3 **continua aberto** (esperado). Sem commit neste task.

---

### Task 5: Item 4 — confirmar que o staff não tem refresh token

**Files:**
- Read: `backend/sinalacs_server/lib/src/endpoints/auth_endpoint.dart:120-150,170-200`

- [ ] **Step 1: Provar no código e no teste**

Run:
```bash
grep -n "refreshToken" backend/sinalacs_server/lib/src/endpoints/auth_endpoint.dart | sed -n 1,12p
cd backend/sinalacs_server && dart test test/unit/endpoint_auth_posture_test.dart
```
Expected: `loginStaff` devolve `DevelopmentLoginResult` sem `refreshToken`; `refreshSession` é só do ACS (token amarrado a aparelho).

- [ ] **Step 2: Observar no aparelho (opcional, 15 min)**

Com a sessão do Task 3 aberta, aguardar 15 min e abrir qualquer tela que chame o backend. Expected: a sessão expira e o app volta ao login. Só vale se o `AdminDataSource` real existir; hoje os dados são `MockAdminDataSource` (#41), então **não há chamada autenticada para falhar** — registrar isso em vez de forçar o teste.

- [ ] **Step 3: Estado**

Item 4 **continua aberto**. Dependência: o refresh do staff só importa quando a #40/#41 trouxerem chamadas autenticadas; decidir o desenho (cap absoluto, aparelho sem `deviceId` real → hoje sentinela) em plano próprio.

---

### Task 6: Item 5 — minors cosméticos

**Files:**
- Modify (se necessário): `backend/sinalacs_server/test/integration/staff_login_test.dart`

- [ ] **Step 1: Medir o ruído de formatação**

Run: `cd backend/sinalacs_server && dart format --output=none --set-exit-if-changed test/integration/staff_login_test.dart; echo $?`
Expected: `0` (nada a fazer) ou `1` com o arquivo listado.

- [ ] **Step 2: Se `1`, formatar e rodar o teste**

Run: `dart format test/integration/staff_login_test.dart && dart test test/integration/staff_login_test.dart`
Expected: formatação aplicada, testes verdes.

- [ ] **Step 3: Varrer o resto dos "minors" da revisão**

Run: `grep -n "minor" -i PROGRESS.md | sed -n '/#39/,$p' | head -20`. Só o `dart format` está nomeado; qualquer outro item que não apareça aqui não pode ser afirmado como aberto nem fechado — anotar "sem lista nomeada".

- [ ] **Step 4: Commit (se houve mudança)**

```bash
git add backend/sinalacs_server/test/integration/staff_login_test.dart
git commit -m "style(backend): dart format em staff_login_test.dart"
```

---

### Task 7: Registrar o resultado

**Files:**
- Modify: `PROGRESS.md` (seção "Minors adiados da #39", subseção "Continua aberto")

- [ ] **Step 1: Atualizar a seção**

Mover para "Fechados" o que foi comprovado (itens 1, 2 e 5, se os Tasks 2, 3 e 6 passaram) citando: aparelho (Motorola edge 40 neo, Android 15), data 2026-10-07, linhas de saída do script. Manter em "Continua aberto" os itens 3 e 4 com a nota do Task 4/5. Se o Task 2 falhou, o item 1 permanece aberto com a causa. Ajustar também o parágrafo "Prova no emulador: NÃO EXECUTADA" da seção #39 para refletir o resultado. Não escrever "provado no emulador": foi aparelho físico.

- [ ] **Step 2: Conferir links e contagens**

Run: `./scripts/qa/check_documentation_links.sh && ./scripts/qa/ci_invariants.sh`
Expected: ok.

- [ ] **Step 3: Commit**

```bash
git add PROGRESS.md
git commit -m "docs: registra a verificação das pendências da #39 em aparelho físico"
```

---

## Self-Review

- **Cobertura:** item 1 → Tasks 1–2; item 2 → Task 3; item 3 → Task 4; item 4 → Task 5; item 5 → Task 6; registro → Task 7.
- **Placeholders:** o nome do teste de ativação no Task 4 Step 2 depende do arquivo (há comando para listar). O restante é comando literal.
- **Limite honesto:** itens 3 e 4 são só *verificados*; corrigi-los é escopo de outros planos (precisam de decisão de produto). A captura 08 é simulada por `wm size`, e o plano exige dizer isso na documentação.
