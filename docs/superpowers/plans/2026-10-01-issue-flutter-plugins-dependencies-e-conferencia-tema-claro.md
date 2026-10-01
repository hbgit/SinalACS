# Issue do `.flutter-plugins-dependencies` + conferência visual do tema claro — Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Abrir uma issue no GitHub (e, em seguida, corrigi-la) para tirar `.flutter-plugins-dependencies` (e o irmão legado `.flutter-plugins`) do versionamento em `apps/acs` e `apps/patient`, e conferir visualmente no emulador as telas novas no tema claro.

**Architecture:** Os dois arquivos são gerados por `flutter pub get` e carregam caminhos absolutos e timestamps da máquina de quem rodou — por isso conflitam em todo merge. O `.gitignore` de cada app já lista `.flutter-plugins-dependencies` (linha 30), mas o arquivo foi commitado antes e continua rastreado; `.flutter-plugins` nem está no `.gitignore`. A correção é `git rm --cached` + completar o `.gitignore`. A conferência visual é independente: sobe o emulador, alterna o `ThemeMode` para claro e captura as telas.

**Tech Stack:** git, `gh` CLI, Flutter (`/home/rock/flutter/bin`), Android SDK em `~/Android/Sdk` (`adb`/`emulator` **não** estão no `PATH`).

**Spec:** não há spec; o pedido do usuário (“abrir uma issue para tirar .flutter-plugins-dependencies do versionamento, que causa conflito nos merge. Conferir visualmente as telas novas no tema claro usando o emulador”) e `spec/ux_accessibility_assessment.md` (contraste) fazem as vezes.

## Global Constraints

- Texto de issue, commits, comentários e copy de UI em **português** (CLAUDE.md do projeto).
- Commits terminam com `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`; PRs terminam com `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
- Nunca usar dados reais de paciente em capturas de tela; usar só as fixtures sintéticas do seed/e2e.
- Capturas de tela **não** vão para o git (ficam no scratchpad ou em `build/`, já ignorado); só o resumo textual vai na issue/PR.
- `apps/admin` não tem os arquivos rastreados (verificado: 0) — não mexer nele além de conferir o `.gitignore`.
- CI tem `workflow-lint` com `scripts/qa/ci_invariants.sh`; a mudança não toca workflows, mas rodar o script antes do PR.

## Review Focus

1. Clone limpo / outro dev roda `flutter pub get` depois da mudança: os arquivos são regenerados e **não** aparecem em `git status` (Task 2 verifica).
2. Branches abertas que ainda têm o arquivo rastreado: ao fazer merge da correção, o git pode reportar conflito modify/delete — o corpo da issue documenta a resolução (`git rm --cached`), Task 1.
3. `git rm --cached` NÃO pode apagar o arquivo do disco do dev (Flutter precisa dele para builds): Task 2 confere que os arquivos continuam existindo.
4. Os apps compilam e rodam sem os arquivos rastreados: `flutter pub get` + `flutter analyze` em ambos (Task 2).
5. Tema claro: texto/ícone com token de preenchimento (`red`/`accent`/…) em vez de `*OnSurface` fica ilegível sobre `Card`/`surfaceRaised` — o checklist da Task 3 olha exatamente isso.

---

### Task 1: Abrir a issue

**Files:**
- Create (temporário, scratchpad): `/tmp/claude-1000/-home-rock-Documents-Dev-APPs-SinalACS/cb28809e-5551-4f0b-8789-904ebcc2fcef/scratchpad/issue_flutter_plugins.md`

**Interfaces:**
- Produces: número da issue (`#N`), usado no nome da branch e no `Closes #N` da Task 2.

- [ ] **Step 1: Confirmar o estado atual (evidência para a issue)**

Run:
```bash
cd /home/rock/Documents/Dev/APPs/SinalACS
git ls-files | grep -E 'flutter-plugins'
git check-ignore -v apps/acs/.flutter-plugins-dependencies apps/acs/.flutter-plugins
git log --oneline -5 -- apps/acs/.flutter-plugins-dependencies
```
Expected: 4 arquivos listados (`apps/{acs,patient}/.flutter-plugins` e `.flutter-plugins-dependencies`); `check-ignore` não casa (rastreado vence o ignore) ou casa só o `-dependencies`; log mostra o commit que o adicionou.

- [ ] **Step 2: Escrever o corpo da issue**

Conteúdo do arquivo `issue_flutter_plugins.md`:
```markdown
## Problema

`apps/acs/.flutter-plugins-dependencies`, `apps/patient/.flutter-plugins-dependencies` e os `.flutter-plugins` ao lado deles estão versionados. São arquivos **gerados** por `flutter pub get` e contêm caminhos absolutos da máquina (`/home/<usuario>/...`) e `date_created`. Cada dev regenera um conteúdo diferente, então todo merge entre branches conflita neles.

O `.gitignore` de cada app já lista `.flutter-plugins-dependencies`, mas o arquivo foi commitado antes disso e o git continua rastreando-o. O `.flutter-plugins` (legado) nem está no `.gitignore`.

## Proposta

1. `git rm --cached` nos 4 arquivos (continuam no disco; o Flutter os regenera).
2. Adicionar `.flutter-plugins` ao `.gitignore` de `apps/acs`, `apps/patient` e `apps/admin`.
3. Verificar que `flutter pub get` regenera os arquivos sem que apareçam em `git status`.

## Critérios de aceite

- [ ] `git ls-files | grep flutter-plugins` não retorna nada.
- [ ] `flutter pub get` em `acs` e `patient` não suja o `git status`.
- [ ] `flutter analyze` limpo nos dois apps.
- [ ] CI verde (`workflow-lint`, `patient-app`, `acs-app`).

## Quem tem branch aberta

Ao integrar a correção, se o git acusar conflito modify/delete nesses arquivos, resolva com:

    git rm --cached apps/acs/.flutter-plugins apps/acs/.flutter-plugins-dependencies \
                    apps/patient/.flutter-plugins apps/patient/.flutter-plugins-dependencies

Depois rode `flutter pub get` normalmente.
```

- [ ] **Step 3: Pedir confirmação ao usuário e criar a issue**

Criar issue é uma ação visível a terceiros: mostrar o corpo ao usuário e só então rodar:
```bash
gh issue create \
  --title "Tirar .flutter-plugins-dependencies e .flutter-plugins do versionamento" \
  --body-file /tmp/claude-1000/-home-rock-Documents-Dev-APPs-SinalACS/cb28809e-5551-4f0b-8789-904ebcc2fcef/scratchpad/issue_flutter_plugins.md
```
Expected: URL da issue; anotar o número `N`.

---

### Task 2: Corrigir (desversionar os arquivos)

**Files:**
- Modify: `apps/acs/.gitignore`, `apps/patient/.gitignore`, `apps/admin/.gitignore` (acrescentar `.flutter-plugins` ao lado da linha `.flutter-plugins-dependencies`)
- Remove do índice (não do disco): `apps/acs/.flutter-plugins`, `apps/acs/.flutter-plugins-dependencies`, `apps/patient/.flutter-plugins`, `apps/patient/.flutter-plugins-dependencies`

**Interfaces:**
- Consumes: número `N` da Task 1.

- [ ] **Step 1: Branch a partir da develop**

```bash
git switch develop && git pull --ff-only
git switch -c fix/N-desversionar-flutter-plugins
```
(substituir `N`; se a política do repo for outro prefixo, seguir `CONTRIBUTING.md`.)

- [ ] **Step 2: Completar os `.gitignore`**

Em cada um dos três, logo abaixo da linha `.flutter-plugins-dependencies` (linha 30 no acs), adicionar a linha `.flutter-plugins`. Conferir antes com `grep -n 'flutter-plugins' apps/*/.gitignore` para não duplicar.

- [ ] **Step 3: Desversionar sem apagar do disco**

```bash
git rm --cached apps/acs/.flutter-plugins apps/acs/.flutter-plugins-dependencies \
                apps/patient/.flutter-plugins apps/patient/.flutter-plugins-dependencies
ls apps/acs/.flutter-plugins-dependencies apps/patient/.flutter-plugins-dependencies
```
Expected: `ls` ainda encontra os arquivos (Review Focus 3).

- [ ] **Step 4: Provar que regenerar não suja o git**

```bash
for a in acs patient; do (cd apps/$a && flutter pub get && flutter analyze); done
git status --short
git ls-files | grep flutter-plugins || echo "ok: nada rastreado"
```
Expected: `status` mostra só os `.gitignore` modificados e as 4 remoções (`D`); `analyze` sem issues; "ok: nada rastreado".

- [ ] **Step 5: Guardas da CI**

```bash
./scripts/qa/ci_invariants.sh
```
Expected: saída 0.

- [ ] **Step 6: Commit e PR**

```bash
git add apps/acs/.gitignore apps/patient/.gitignore apps/admin/.gitignore
git commit -m "chore: tira .flutter-plugins e .flutter-plugins-dependencies do versionamento

Arquivos gerados por flutter pub get, com caminhos absolutos da máquina;
conflitavam em todo merge. Closes #N

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```
Abrir PR para `develop` (`gh pr create`, corpo termina com a linha “🤖 Generated with [Claude Code](https://claude.com/claude-code)”) — só após o usuário aprovar o push.

---

### Task 3: Conferência visual das telas novas no tema claro (emulador)

Independente das Tasks 1–2; pode rodar em paralelo. Nenhuma alteração de código esperada; se achar defeito, vira issue/commit à parte.

**Files:**
- Referência: `apps/{acs,patient}/lib/core/services/theme_controller.dart`, `apps/{acs,patient}/lib/app/{acs,patient}_theme.dart`, `apps/{acs,patient}/test/contrast_tokens_test.dart`, `spec/ux_accessibility_assessment.md`
- Saída: capturas em `.../scratchpad/tema-claro/` (fora do git)

**Interfaces:**
- Consumes: `ThemeController` (modo claro/escuro/automático, entregue pelo PR #11 `feat/theme-light-dark`).

- [ ] **Step 1: Disponibilizar `adb` e o emulador**

```bash
export ANDROID_HOME=$HOME/Android/Sdk
export PATH=$PATH:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator
emulator -list-avds
adb devices
```
Expected: ao menos um AVD listado (o e2e usou o `emulator-5554`). Se `adb`/`emulator` não existirem, avisar o usuário — não instalar nada sozinho.

- [ ] **Step 2: Subir o emulador e o backend**

```bash
emulator -avd <AVD_LISTADO> -no-snapshot-save &
adb wait-for-device
./scripts/qa/e2e_stack.sh   # ver --help; sobe a stack com o banco de teste e fixtures sintéticas
```
Consultar a skill `validacao-e2e` para o fluxo exato de login real (OTP via relé) — usar só fixtures sintéticas.

- [ ] **Step 3: Rodar cada app e forçar o tema claro**

```bash
cd apps/patient && flutter run -d emulator-5554
```
No app: Perfil/Configurações → Aparência → **Claro** (ou, se a opção estiver ausente na tela, mudar o `ThemeMode` do `ThemeController` e fazer hot reload). Repetir para `apps/acs`.

- [ ] **Step 4: Percorrer as telas novas e capturar**

Para cada tela, `adb exec-out screencap -p > scratchpad/tema-claro/<app>_<tela>.png` e abrir a imagem com Read para inspecionar. Telas novas a cobrir (a lista vem do histórico recente — confirmar com `git diff --stat 3a6ce44^1 HEAD -- 'apps/*/lib/**/*screen*.dart' 'apps/*/lib/**/*page*.dart'`):
- Paciente: login/OTP, aceite de termos, Meus Dados (LGPD), consentimento/solicitações de titular, aviso de mudança de termos, alerta de urgência, status do pedido.
- ACS: login institucional, fila priorizada, detalhe do paciente, registro de visita offline, mapa/micro-área, convite/QR.

Checklist por tela (Review Focus 5):
- [ ] texto e ícones legíveis sobre `Card`/`surfaceRaised` (cores de risco usando `*OnSurface`, não o fill)
- [ ] nenhum fundo escuro “vazando” (hardcoded `Colors.black`/`0xFF1…`)
- [ ] bordas/divisórias visíveis; alvos de toque ≥ 48dp
- [ ] campos de formulário, estados desabilitado e de erro distinguíveis
- [ ] status bar/navigation bar com ícones de contraste correto

- [ ] **Step 5: Registrar o resultado**

Para cada defeito: tela, app, descrição e o token suspeito (`grep -rn 'Colors\.\|Color(0x' apps/<app>/lib/<arquivo>`). Abrir uma issue por defeito (com confirmação do usuário) ou reportar “nenhum defeito” com a lista de telas conferidas. Não afirmar que uma tela foi conferida sem ter visto a captura.

- [ ] **Step 6: Encerrar**

```bash
adb emu kill
cd /home/rock/Documents/Dev/APPs/SinalACS && docker compose down
```
(`down` sem `-v`; não remover `pg_data/` sem o usuário pedir.)

---

## Self-review

- Cobertura: issue (Task 1), correção que a issue descreve (Task 2), conferência visual (Task 3) — os três pontos do pedido.
- Sem placeholders além de `N` (número da issue, só conhecido após a Task 1) e `<AVD_LISTADO>` (saída do passo anterior).
- Nomes consistentes: os 4 arquivos e a branch `fix/N-desversionar-flutter-plugins` usados igual nas tasks.
