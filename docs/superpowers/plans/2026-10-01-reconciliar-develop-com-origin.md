# Reconciliar `develop` local com `origin/develop` — Plano

> **Para agentes:** SUB-SKILL OBRIGATÓRIA: use superpowers:executing-plans (recomendado, é uma sequência única e acoplada) ou superpowers:subagent-driven-development. Passos usam checkbox (`- [ ]`).

**Goal:** Integrar os 7 commits de `origin/develop` nos 90 commits locais de `develop`, sem perder nenhum dos dois lados e sem reescrever histórico publicado.

**Architecture:** Um único `git merge origin/develop` (não rebase: 90 commits repetiriam os mesmos conflitos 90 vezes, e o remoto já usa merge commits de PR). Rede de segurança com tag de backup. Os 8 arquivos em conflito são resolvidos um a um, depois validados com os testes dos apps e o guarda de CI. A publicação vai por branch + PR, porque `develop` é protegida.

**Tech Stack:** git, Flutter/Dart (apps ACS e Paciente), bash/python (`scripts/qa/ci_invariants.sh`), GitHub CLI.

**Spec:** não há spec; a fonte é a análise de `git log` abaixo.

## Diagnóstico (medido em 2026-10-01)

- Merge-base: `a9757fd` (2026-09-28 21:22).
- Local (90 commits, todos de Herbert): RF05/RF14/RF18 LGPD, QR de onboarding, push/Gorush/FCM, endurecimento do CI.
- Remoto (7 commits, 3 PRs): 
  - PR #11 `feat/theme-light-dark` (vinimartinsufrr): tema claro/escuro/automático nos apps ACS e Paciente (`acs_theme.dart`, `patient_theme.dart`, `theme_controller.dart`, `shared_preferences`, `contrast_tokens_light_test.dart`).
  - PR #27 `fix/ci-invariants-parsing`: `ci_invariants.sh` aceita `on:` string/lista e rejeita flag errada (issue #22).
  - PR #29 `docs/publicacao-google-play` (sarah): `docs/publicacao-google-play.md`, `docs/README.md`.
- Simulação `git merge-tree` (sem tocar na árvore): 8 arquivos em conflito.

| Arquivo | Natureza do conflito | Resolução |
|---|---|---|
| `CLAUDE.md` | 2 bullets de CI reescritos dos dois lados | manter a versão **local** (tem FCM/Gorush/guarda ampliado) e conferir se a versão remota acrescenta algo |
| `scripts/qa/ci_invariants.sh` | remoto: `PYTHONIOENCODING` + `$caminho_workflow`; local: `${CI_WORKFLOW_PATH:-...}` | **união**: manter o parsing de `on:`/flags do remoto **e** os checks novos do local |
| `apps/acs/pubspec.yaml` | local `qr_flutter`, remoto `shared_preferences` | manter **as duas** dependências |
| `apps/acs/pubspec.lock`, `apps/patient/pubspec.lock` | lock divergente | nunca editar à mão: resolver `pubspec.yaml` e regenerar com `flutter pub get` |
| `apps/patient/.flutter-plugins-dependencies` | arquivo gerado, versionado por engano (2 no repo) | regenerar com `flutter pub get`; abrir issue para tirá-lo do índice |
| `apps/acs/lib/app/app.dart` (4 hunks) | remoto refatora para tema controlável; local adiciona fluxos | integrar os dois, ver Task 3 |
| `apps/patient/lib/app/app.dart` (6 hunks) | idem, com termos/consentimento/QR | idem |
| `apps/patient/test/contrast_tokens_test.dart` | remoto troca `PatientColors.*` por `PatientDarkColors.*`/`risk.*`; local adicionou 3 casos do cartão de termos | manter os casos novos do local, escritos com o esquema de cores do remoto |

## Global Constraints

- Nunca `git push --force` em `develop`/`main` (protegidas; `origin/develop` já recebeu PRs de terceiros).
- Nunca perder commit: tag `backup/develop-pre-merge-2026-10-01` antes de qualquer coisa.
- Contraste WCAG: texto/ícone em cor clínica usa os tokens `*OnSurface`, medidos sobre `Card`/`surfaceRaised` (CLAUDE.md). Vale para os **dois** temas.
- Os 8 checks obrigatórios de `./scripts/qa/ci_invariants.sh --checks-obrigatorios` devem passar para o PR entrar.
- Mensagens de commit em português, no estilo `tipo(escopo): resumo`.

## Review Focus

- Tema claro: telas novas do local (Privacidade e termos, QR, cartão de aviso de termos, Meus dados) podem usar `PatientColors.*` fixo escuro e ficar ilegíveis no tema claro. Esperado: contraste ≥ 4.5:1 nos dois temas.
- `ci_invariants.sh` mesclado pode aceitar flag errada de novo ou quebrar com `on: push`. Esperado: exit 2 e JSON só em `--checks-obrigatorios`.
- Migração/dados: nenhum arquivo do backend é tocado pelo remoto, mas confirme que nada de `backend/` aparece no diff final além do esperado.
- Lock files: `pubspec.lock` regenerado não deve rebaixar pacotes que o local já havia fixado.

---

### Task 1: Rede de segurança e árvore limpa

**Files:** nenhum arquivo muda.

**Interfaces:**
- Produces: tag `backup/develop-pre-merge-2026-10-01` apontando para `f0666dc`.

- [ ] **Step 1: Confirmar árvore limpa e ponto de partida**

Run: `git status --short && git rev-parse --short HEAD`
Expected: saída de status vazia; `f0666dc`.

- [ ] **Step 2: Criar backup e buscar o remoto**

```bash
git tag backup/develop-pre-merge-2026-10-01 HEAD
git fetch origin
git rev-list --left-right --count develop...origin/develop
```
Expected: `90	7` (se o remoto andou, o segundo número sobe; reavalie os conflitos com `git merge-tree --write-tree --name-only develop origin/develop`).

- [ ] **Step 3: Trabalhar em branch de integração**

```bash
git switch -c integrar/develop-com-origin-2026-10-01
```
Expected: `develop` local fica intacta até o fim (fácil de abandonar).

### Task 2: Iniciar o merge e resolver os arquivos textuais simples

**Files:**
- Modify: `CLAUDE.md`, `apps/acs/pubspec.yaml`, `scripts/qa/ci_invariants.sh`

**Interfaces:**
- Consumes: branch da Task 1.
- Produces: `pubspec.yaml` do ACS com `qr_flutter` **e** `shared_preferences`; `ci_invariants.sh` sem marcadores de conflito.

- [ ] **Step 1: Iniciar o merge sem commit**

Run: `git merge --no-commit --no-ff origin/develop`
Expected: `CONFLICT` em 8 arquivos (lista da tabela acima) e auto-merge no restante.

- [ ] **Step 2: `CLAUDE.md`**

Abra o arquivo, localize `<<<<<<< HEAD`. Fique com o lado local (`HEAD`) dos dois bullets de CI. Compare com o lado remoto (`git show origin/develop:CLAUDE.md | grep -n 'CI lives'`) e traga qualquer fato novo que só o remoto tenha. Remova os marcadores.
Run: `grep -n '^<<<<<<<\|^=======\|^>>>>>>>' CLAUDE.md`
Expected: sem saída.

- [ ] **Step 3: `apps/acs/pubspec.yaml`**

Deixe as duas linhas em `dependencies:`:

```yaml
  qr_flutter: ^4.1.0
  # Preferência de tema (claro/escuro/automático) — dado de UI não sensível,
  # não precisa do Keystore/Keychain do flutter_secure_storage.
  shared_preferences: ^2.3.2
```

- [ ] **Step 4: `scripts/qa/ci_invariants.sh`**

Fique com a linha de exec do local, que respeita `CI_WORKFLOW_PATH`, e acrescente o `PYTHONIOENCODING` do remoto antes dela:

```bash
export PYTHONIOENCODING=utf-8

exec python3 - "${CI_WORKFLOW_PATH:-$repo_root/.github/workflows/ci.yml}" "$@" <<'PY'
```

Confira que `$caminho_workflow` não ficou referenciado em outro ponto: `grep -n caminho_workflow scripts/qa/ci_invariants.sh`. Se aparecer, defina a variável acima do `exec` com o mesmo valor padrão (`caminho_workflow="${CI_WORKFLOW_PATH:-$repo_root/.github/workflows/ci.yml}"`) e use-a.

- [ ] **Step 5: Provar que o guarda funciona (teste do remoto + testes do local)**

```bash
bash -n scripts/qa/ci_invariants.sh
./scripts/qa/ci_invariants.sh
./scripts/qa/ci_invariants.sh --checks-obrigatorio; echo "exit=$?"
bash scripts/qa/ci_invariants_fcm_test.sh
bash scripts/ci/decode_secret_file_test.sh
```
Expected: guarda `ok`; flag errada com `exit=2`; os dois testes terminam com exit 0.

- [ ] **Step 6: Marcar como resolvido (sem commit ainda)**

```bash
git add CLAUDE.md apps/acs/pubspec.yaml scripts/qa/ci_invariants.sh
```

### Task 3: Resolver `app.dart` dos dois apps

**Files:**
- Modify: `apps/acs/lib/app/app.dart`, `apps/patient/lib/app/app.dart`

**Interfaces:**
- Consumes: do remoto, `ThemeController` (`apps/*/lib/core/services/theme_controller.dart`) e os temas `buildAcsTheme`/`buildPatientTheme` com variante clara/escura.
- Produces: `app.dart` que monta o `MaterialApp` com `theme`, `darkTheme` e `themeMode` do controller **e** mantém todos os providers/rotas/fluxos do local.

- [ ] **Step 1: Ler as duas intenções antes de editar**

```bash
git diff a9757fd origin/develop -- apps/acs/lib/app/app.dart
git diff a9757fd f0666dc -- apps/acs/lib/app/app.dart
```
O remoto mexe na construção do `MaterialApp`/tema; o local, nas dependências injetadas e rotas. As mudanças são ortogonais: em cada hunk, mantenha a lógica do local e aplique a estrutura de tema do remoto por cima. Não descarte um lado inteiro.

- [ ] **Step 2: Resolver hunk a hunk e analisar**

Edite os 4 hunks do ACS e os 6 do Paciente. Em seguida:
```bash
grep -c '^<<<<<<<' apps/acs/lib/app/app.dart apps/patient/lib/app/app.dart
```
Expected: `0` e `0`.

- [ ] **Step 3: Resolver os pubspecs e regenerar locks**

Para `apps/patient/pubspec.yaml` (auto-merge) confira que tem `shared_preferences` e as dependências do local. Depois, para cada app:
```bash
git checkout --theirs apps/patient/pubspec.lock apps/acs/pubspec.lock 2>/dev/null; true
(cd apps/acs && flutter pub get)
(cd apps/patient && flutter pub get)
```
Expected: ambos terminam sem erro e reescrevem lock e `.flutter-plugins-dependencies`. Confira que nenhum pacote que o local fixou foi rebaixado: `git diff HEAD -- apps/*/pubspec.lock | grep '^-.*version'` e revise cada linha.

- [ ] **Step 7: Análise estática**

```bash
(cd apps/acs && flutter analyze)
(cd apps/patient && flutter analyze)
```
Expected: `No issues found!` nos dois.

- [ ] **Step 8: Marcar resolvidos**

```bash
git add apps/acs/lib/app/app.dart apps/patient/lib/app/app.dart apps/acs/pubspec.lock apps/patient/pubspec.lock apps/patient/.flutter-plugins-dependencies apps/acs/.flutter-plugins-dependencies
```

### Task 4: Resolver o teste de contraste e cobrir o tema claro

**Files:**
- Modify: `apps/patient/test/contrast_tokens_test.dart`
- Test: `apps/patient/test/contrast_tokens_light_test.dart` (vem do remoto), `apps/acs/test/contrast_tokens_light_test.dart`

**Interfaces:**
- Consumes: `PatientDarkColors`, `risk` (extensão de tema do remoto) e `buildPatientTheme()`.

- [ ] **Step 1: Resolver o conflito**

Use as linhas do remoto (`PatientDarkColors.background`, `risk.yellowOnSurface` etc.) como base e **acrescente** os três casos do local, reescritos para o novo esquema:

```dart
  final scheme = buildPatientTheme().colorScheme;
  // ... casos do remoto ...
  ('branco sobre accentDark (passos do resumo legal)', Colors.white, PatientColors.accentDark, normalText),
  ('texto do cartão de aviso (onSurface) sobre card', scheme.onSurface, PatientDarkColors.surfaceRaised, normalText),
  ('TextButton do cartão de aviso (primary) sobre card', scheme.primary, PatientDarkColors.surfaceRaised, normalText),
  ('ícone de fechar do cartão de aviso (onSurfaceVariant) sobre card', scheme.onSurfaceVariant, PatientDarkColors.surfaceRaised, largeTextOrUi),
```
Se `buildPatientTheme()` agora recebe o brilho como parâmetro, passe o argumento equivalente ao escuro. Veja a assinatura em `apps/patient/lib/app/patient_theme.dart`.

- [ ] **Step 2: Rodar a suíte de contraste dos dois apps**

```bash
(cd apps/patient && flutter test test/contrast_tokens_test.dart test/contrast_tokens_light_test.dart)
(cd apps/acs && flutter test test/contrast_tokens_test.dart test/contrast_tokens_light_test.dart)
```
Expected: PASS. Falha em caso do local contra o tema claro é **achado real** (Review Focus 1), não erro de merge: corrija o token em `patient_theme.dart` com a variante `*OnSurface` clara, não afrouxe o limiar.

- [ ] **Step 3: Marcar resolvido**

```bash
git add apps/patient/test/contrast_tokens_test.dart
git diff --name-only --diff-filter=U
```
Expected: segunda saída vazia (nenhum arquivo em conflito).

### Task 5: Validar o resultado integrado

**Files:** nenhum, só verificação.

- [ ] **Step 1: Suítes completas dos apps**

```bash
(cd apps/acs && flutter test)
(cd apps/patient && flutter test)
```
Expected: tudo verde (ACS ≈158 e Paciente ≈106 testes ou mais, segundo a memória do projeto, mais os de tema). Qualquer falha em tela do local sob tema claro: corrija antes de fechar o merge.

- [ ] **Step 2: Backend não foi tocado pelo remoto**

Run: `git diff --stat HEAD -- backend | tail -1` (com o merge ainda não commitado, compara com o local)
Expected: sem saída.

- [ ] **Step 3: Guarda de CI e actionlint**

```bash
./scripts/qa/ci_invariants.sh --checks-obrigatorios
```
Expected: JSON com os 8 checks.

- [ ] **Step 4: Concluir o merge**

```bash
git commit -m "merge: integra origin/develop (tema claro/escuro, ci_invariants, guia Google Play) na develop local

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
git rev-list --left-right --count origin/develop...HEAD
```
Expected: `0	98` (os 7 do remoto já contidos; 90 locais + o merge + os 7 não contam à esquerda).

- [ ] **Step 5: Atualizar o grafo**

Run: `graphify update .`

### Task 6: Publicar sem force-push

**Files:** nenhum.

- [ ] **Step 1: Confirmar com o dono antes de publicar** (ação externa e de 90 commits)

Mostre `git log --oneline origin/develop..HEAD | wc -l` e peça o OK explícito.

- [ ] **Step 2: Publicar a branch de integração e abrir PR para `develop`**

```bash
git push -u origin integrar/develop-com-origin-2026-10-01
gh pr create --base develop --head integrar/develop-com-origin-2026-10-01 \
  --title "merge: integra develop local (RF05/RF14/RF18, QR, push, CI) com tema claro/escuro" \
  --body "Resolve a divergência 90/7. Conflitos resolvidos em CLAUDE.md, ci_invariants.sh, pubspecs, app.dart (ACS e Paciente) e contrast_tokens_test.dart. Local validado: flutter test dos dois apps, ci_invariants.sh.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```
Expected: os 8 checks obrigatórios ficam verdes (`android-e2e` é informativo).

- [ ] **Step 3: Após o merge do PR, alinhar a `develop` local**

```bash
git switch develop
git fetch origin
git reset --hard origin/develop   # só depois de confirmar que o PR foi mergeado e o backup existe
git rev-list --left-right --count develop...origin/develop
```
Expected: `0	0`. Remover a tag de backup apenas depois de alguns dias.

### Task 7 (opcional, separada): higiene

- [ ] Abrir issue: `.flutter-plugins-dependencies` está versionado em `apps/acs` e `apps/patient`; é arquivo gerado e causou conflito. Corrigir com `git rm --cached` e entrada no `.gitignore` em PR próprio, fora deste merge.

## Auto-revisão

- Cobertura: os 8 arquivos em conflito têm resolução (Tasks 2–4); validação (Task 5); publicação (Task 6).
- Riscos fora do escopo do remoto: nenhum arquivo de `backend/` ou migração é tocado pelo lado remoto.
- Reversão: `git switch develop` (intacta até a Task 6) ou `git reset --hard backup/develop-pre-merge-2026-10-01`.
