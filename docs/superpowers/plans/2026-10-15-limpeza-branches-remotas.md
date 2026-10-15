# Limpeza das branches remotas (origin) — Plano de Execução

> **Para agentes:** SUB-SKILL OBRIGATÓRIA: use superpowers:subagent-driven-development (recomendado) ou superpowers:executing-plans para executar este plano tarefa a tarefa. Os passos usam checkbox (`- [ ]`).

**Objetivo:** reduzir as 43 branches de `origin` (hbgit/SinalACS) às ativas ou necessárias, sem perder nenhum commit que ainda não esteja na `develop`/`main`.

**Arquitetura:** dois scripts fora do repositório. `classifica_branches.sh` é **somente leitura**: lê `refs/remotes/origin/*` e, opcionalmente, os PRs via `gh`, e gera um relatório TSV (branch, SHA, data, autor, motivo). `remove_branches.sh` é **destrutivo**: recebe um lote aprovado à mão (branch + SHA), recusa branch protegida, SHA que mudou desde o relatório e base de PR aberto, e remove o lote num único `git push --atomic` com `--force-with-lease`. Antes de qualquer remoção, um bundle e refs locais `refs/backup/...` guardam cada ponta removida.

**Stack:** Git padrão (`for-each-ref`, `rev-list`, `cherry`, `merge-base`, `ls-remote`, `bundle`, `push --atomic --force-with-lease`), bash e coreutils GNU (`date -d`). `gh` é **opcional**: sem ele a coluna de PR fica vazia e nenhuma branch com commits fora da base é marcada como REMOVER.

**Pedido de origem:** pedido do mantenedor em 2026-10-15 (levantamento, critérios, branches a manter, relatório para revisão humana, execução em lote com confirmação, reversão e prevenção; nenhuma remoção durante a escrita do plano).

## Restrições globais

- Branches protegidas que **nunca** são removidas: `main`, `develop`, `release/*`. No GitHub só `main` e `develop` estão protegidas hoje (`gh api repos/hbgit/SinalACS/branches`); não há nenhuma `release/*`.
- A **base de merge é `origin/develop`**, não a `main`. O fluxo é `feature → develop` e `develop → main`. A `main` parou em 2026-09-28 (`de86dd8`, PR #7), e os 22 commits dela que não estão na develop têm patch equivalente lá (`git cherry`). Medir merge só contra a `main` marcaria como "não mergeado" quase tudo que já está na develop.
- Nenhuma remoção sem um relatório gerado **no mesmo dia** e revisado por uma pessoa. O SHA aprovado é o SHA removido: se a branch andou, o script recusa.
- Antes de qualquer remoção, todas as pontas do lote ficam guardadas em `refs/backup/limpeza-<data>/` e em um bundle.
- Os scripts e as saídas ficam **fora do repositório**, em `~/limpeza-branches-sinalacs/`. Nada aqui é commitado, exceto este plano e, opcionalmente, a Tarefa 8.
- Um PR mergeado **não basta** para remover a branch: o critério é a ponta da branch estar contida na base (ou ter todos os patches equivalentes nela).
- Commits e PRs sem atribuição de IA (regra do `CLAUDE.md`).

## Foco de revisão

1. **Ponta que andou depois do merge do PR** (o caso real `feat/issue-44` ← `fix/issue-56`): o estado `MERGED` no GitHub não pode virar REMOVER. O ensaio da Tarefa 1 tem `feat/movida` para cobrir isso.
2. **Branch que mudou entre o relatório e a remoção**: o `--force-with-lease` com o SHA do relatório tem que recusar. Coberto pelo caso 2 do ensaio.
3. **Branch protegida dentro de um lote aprovado** (por edição manual): o script tem que abortar antes de qualquer push. Coberto pelo caso 1 do ensaio.
4. **Confirmação errada ou ausente**: nada é removido. Coberto pelos casos 3 e 4 do ensaio.
5. **Branch usada como base de um PR aberto**: remover fecharia o PR. O script consulta o `gh`; o ensaio roda com `SEM_GH=1`, então essa checagem só é exercida no repositório real (a Tarefa 5 confere que não há PR aberto).

---

## Achado do levantamento: correção da #56 fora da develop

O levantamento somente-leitura de 2026-10-15 encontrou trabalho que **não está em nenhuma branch protegida**:

- PR #57 (`feat/issue-44-alertas-escalonar-tempo-real` → `develop`) foi mergeado em 2026-10-13 às 13:24 UTC com a ponta `dd28239`.
- PR #58 (`fix/issue-56-mqtt-queda-processo` → **`feat/issue-44-...`**) foi mergeado **depois**, às 14:07 UTC, e moveu a ponta da issue-44 para `6649c0d`.
- `git cherry origin/develop origin/fix/issue-56-mqtt-queda-processo` mostra **24 commits `+`**, ou seja, sem patch equivalente na develop. Entre eles estão `47fea05 fix(alertas): outbox só marca publicado após o PUBACK do broker`, `c6b0c2c fix(mqtt): erros assíncronos do socket viram queda de conexão tratada…`, `4523af1 feat(runtime): rede de proteção global…` e `5400565 chore(compose): reinício automático do backend…`.
- A issue #56 está **CLOSED**, mas a correção nunca chegou à develop.

Consequência para este plano: `feat/issue-44-alertas-escalonar-tempo-real` e `fix/issue-56-mqtt-queda-processo` são a **única cópia remota** desse trabalho. As duas ficam em MANTER até um PR `fix/issue-56-mqtt-queda-processo → develop` ser mergeado. Esse PR fica **fora** deste plano, porque mexe em código e precisa da CI e da revisão normais. Ele toca o invariante "alerta vermelho nunca é descartado em silêncio", então convém priorizá-lo. Depois do merge, rode a Tarefa 2 de novo e as duas branches devem cair sozinhas em REMOVER.

## Classificação prevista (levantamento de 2026-10-15)

Total em `origin`: 43 branches. Prevista com `manter.tsv` contendo só `ci/ensaio-ubuntu-26.04`. A Tarefa 2 confirma com o script.

### MANTER (5)

| Branch | Último commit | Justificativa |
|---|---|---|
| `main` | 2026-09-28 `de86dd8` | Protegida. |
| `develop` | 2026-10-15 `d74d5a1` | Protegida; base de integração. |
| `feat/issue-44-alertas-escalonar-tempo-real` | 2026-10-13 `6649c0d` | Carrega o merge do #58; 24 commits fora da develop (ver o achado acima). O script dá REVISAR; a decisão humana é MANTER. |
| `fix/issue-56-mqtt-queda-processo` | 2026-10-13 `febfcb7` | Fonte da correção da #56, ainda não mergeada na develop. O script dá REVISAR; a decisão humana é MANTER. |
| `ci/ensaio-ubuntu-26.04` | 2026-09-28 `15a9a3d` | Ensaio "NÃO MESCLAR" (PR #17 fechado) da migração para Ubuntu 26.04, que o `CLAUDE.md` cita; o `ubuntu-latest` migra em 2026-10-19. Remover depois que o PR da migração for mergeado. |

### REMOVER — lote 3: órfã, por decisão do mantenedor (1)

| Branch | Último commit | Autor | Situação |
|---|---|---|---|
| `analysis-cybersec` | 2026-09-14 `8470c67` | rosialdo | Órfã: 3 commits sem PR. Tem 4 linhas a mais em `spec/security_assessment.md` em relação à develop, mais ruído em `.flutter-plugins*`/`pubspec.lock`. O trabalho do mesmo autor entrou pela `security/cibersec-analysis` (PR #10). **Decisão do mantenedor (2026-10-15): remover.** O classificador continua marcando REVISAR, porque há commits fora da base; por isso ela vai num lote próprio, montado à mão (Tarefa 3). É a única remoção que leva commits fora da base: a cópia fica no bundle e nas refs de backup (Tarefa 4), e o diff vai salvo à parte. |

### REMOVER — lote 1: contida na develop, com PR mergeado (29)

`docs/ux-accessibility-assessment` (#6), `feat/admin-backoffice` (#5), `security/cibersec-analysis` (#10), `docs/ui-ux-test-plan-execution` (#12), `ci/correcoes-avaliacao-2026-09-28` (#16), `ci/revisao-final-2026-09-28` (#18), `fix/ci-checks-obrigatorios-skip` (#26), `fix/ci-invariants-parsing` (#27), `fix/patient` (#28), `fix/31-desversionar-flutter-plugins` (#32), `fix/tema-claro-textos-brancos` (#33), `docs/slide-showcase` (#35), `fix/app_acs` (#36/#37/#38), `feat/admin-minors-39` (#49), `fix/staff-totp-activation-48` (#50), `feat/admin-endpoints-40` (#51), `feat/admin-client-41` (#52), `fix/lgpd-conformidade-dados` (#53), `feat/issue-43-gestao-de-acs-e-mfa` (#54), `feat/admin-pedidos-titular-42` (#55), `feat/issue-45-trilha-auditoria-completa` (#59), `feat/issue-46-avisos-e-termos` (#60), `fix/issue-23-concorrencia-por-ref` (#61), `docs/issue-23-conferencia-real` (#62), `fix/issue-63-acabamentos-concorrencia` (#64), `fix/issue-24-grupo-concorrencia-exato` (#65), `fix/issue-46-fechamento` (#66), `fix/issue-68-gatilho-nao-dict` (#69), `docs/atualiza-readme-e-docs` (#70).

### REMOVER — lote 2: contida na main/develop, merge direto sem PR (8)

`feat/video_pub` (2026-09-10), `feat/httpserver` (09-11), `feat/ui` (09-12), `feat/serverpod` (09-14), `feat/admin-android` (09-16), `fix/admin-contrast-tokens` (09-16, mesma ponta `a9dcbc5` da anterior), `fix/backend` (09-19), `fix/app_admin` (10-07).

### Critério "sem commits há mais de N meses"

O padrão é **N = 6 meses**, configurável por `MESES=`. Neste repositório ele **não pega nada**: a branch mais antiga é de 2026-09-10, cerca de 5 semanas. O critério só vale para branches **com commits fora da base**, e mesmo assim manda para REVISAR, nunca para REMOVER direto. Branch contida na base é REMOVER seja qual for a idade.

### Branches de outros autores

`docs/ux-accessibility-assessment` e `docs/ui-ux-test-plan-execution` (sarah), `security/cibersec-analysis` (Rosialdo) e `fix/ci-invariants-parsing` e `fix/ci-checks-obrigatorios-skip` (vinimartinsufrr) estão todas contidas na develop. Remover não perde nada, mas avise os autores antes, por cortesia.

---

## Estrutura de arquivos

Tudo fora do repositório:

```
~/limpeza-branches-sinalacs/
├── ferramentas/
│   ├── classifica_branches.sh   # SOMENTE LEITURA — gera relatorio.tsv
│   ├── remove_branches.sh       # DESTRUTIVO com --executar — remove um lote
│   └── ensaio_limpeza.sh        # teste hermético dos dois, em origin descartável
└── 2026-10-15/                  # uma pasta por rodada (data da execução)
    ├── prs.tsv                  # headRefName<TAB>número<TAB>estado (do gh)
    ├── manter.tsv               # branch<TAB>justificativa (entrada humana)
    ├── relatorio.tsv            # saída do classificador — o que a pessoa revisa
    ├── lote1.tsv / lote2.tsv / lote3.tsv  # branch<TAB>sha aprovados (entrada da remoção)
    ├── analysis-cybersec.patch  # diff da órfã contra a develop, legível sem git
    ├── branches-removidas.bundle
    └── execucao.log
```

**Formatos (interface entre as tarefas):**
- `relatorio.tsv`: cabeçalho `branch sha data autor fora_base sem_equivalente prs categoria motivo` (TAB). `categoria` ∈ {`MANTER`, `REMOVER`, `REVISAR`}. `prs` = `#N:ESTADO[,#M:ESTADO]` ou `-`.
- `loteN.tsv`: `branch<TAB>sha-completo`; linhas vazias e começadas por `#` são ignoradas.
- `manter.tsv`: `branch<TAB>justificativa`.

---

## FASE A — SOMENTE LEITURA (Tarefas 1 a 3)

Nada nesta fase altera o remoto. `git fetch` só atualiza as refs locais.

### Tarefa 1: Ferramentas e ensaio hermético

**Arquivos:**
- Criar: `~/limpeza-branches-sinalacs/ferramentas/ensaio_limpeza.sh`
- Criar: `~/limpeza-branches-sinalacs/ferramentas/classifica_branches.sh`
- Criar: `~/limpeza-branches-sinalacs/ferramentas/remove_branches.sh`

**Interfaces:**
- Produz: `classifica_branches.sh <dir-saida>`, com as variáveis de ambiente `BASE` (padrão `origin/develop`), `MESES` (padrão `6`), `MANTER` (caminho de `manter.tsv`) e `PRS_TSV` (pula o `gh`). Escreve `<dir>/prs.tsv` e `<dir>/relatorio.tsv`.
- Produz: `remove_branches.sh <lote.tsv> [--executar]`, com `SEM_GH=1` para pular a checagem de PR aberto. Sem `--executar` faz só `git push --dry-run`. Com `--executar`, exige digitar `REMOVER <n>`. Sai com código ≠ 0 em qualquer recusa, sem remover nada.

- [ ] **Passo 1: escrever o ensaio (o teste) primeiro**

```bash
mkdir -p ~/limpeza-branches-sinalacs/ferramentas
cat > ~/limpeza-branches-sinalacs/ferramentas/ensaio_limpeza.sh <<'EOF'
#!/usr/bin/env bash
# Prova classifica_branches.sh e remove_branches.sh num origin descartável.
# Não toca no repositório real.
set -euo pipefail
FERR=$(dirname "$(readlink -f "$0")")
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
falhas=0
confere() {
  if [[ $2 == "$3" ]]; then echo "ok    $1"
  else echo "FALHA $1: esperado '$3', obtido '$2'"; falhas=$((falhas+1)); fi
}
commit() { echo "$1" > "$1.txt"; git add "$1.txt"; git commit -qm "$1"; }

git init -q --bare "$T/origin.git"
git clone -q "$T/origin.git" "$T/w" 2>/dev/null
cd "$T/w"
git config user.email ensaio@exemplo.invalid; git config user.name Ensaio
git symbolic-ref HEAD refs/heads/develop
commit base
git push -q origin develop develop:main

# contida na base por merge commit
git checkout -q -b feat/mergeada develop; commit m; git push -q origin feat/mergeada
git checkout -q develop; git merge -q --no-ff -m "merge mergeada" feat/mergeada
# squash: ponta fora da base, patch equivalente dentro
git checkout -q -b feat/squash develop; commit s; git push -q origin feat/squash
git checkout -q develop; git merge -q --squash feat/squash; git commit -qm "squash s"
# PR mergeado e depois a ponta andou (o caso #57/#58)
git checkout -q -b feat/movida develop; commit v1
git checkout -q develop; git merge -q --no-ff -m "merge movida" feat/movida
git checkout -q feat/movida; commit v2; git push -q origin feat/movida
# órfã recente, sem PR
git checkout -q -b feat/orfa develop; commit o; git push -q origin feat/orfa
# antiga, sem merge, sem PR
git checkout -q -b feat/antiga develop; echo a > a.txt; git add a.txt
GIT_AUTHOR_DATE=2025-01-01T00:00:00 GIT_COMMITTER_DATE=2025-01-01T00:00:00 git commit -qm antiga
git push -q origin feat/antiga
# mantida por justificativa humana
git checkout -q -b ci/ensaio develop; commit e; git push -q origin ci/ensaio
# PR aberto
git checkout -q -b feat/aberta develop; commit ab; git push -q origin feat/aberta
git checkout -q develop; git push -q origin develop; git fetch -q origin

printf 'feat/mergeada\t1\tMERGED\nfeat/squash\t2\tMERGED\nfeat/movida\t3\tMERGED\nfeat/aberta\t4\tOPEN\n' > "$T/prs.tsv"
printf 'ci/ensaio\tensaio de runner\n' > "$T/manter.tsv"
PRS_TSV="$T/prs.tsv" MANTER="$T/manter.tsv" "$FERR/classifica_branches.sh" "$T/out" >/dev/null

cat_de() { awk -F'\t' -v b="$1" '$1==b{print $8}' "$T/out/relatorio.tsv"; }
mot_de() { awk -F'\t' -v b="$1" '$1==b{print $9}' "$T/out/relatorio.tsv"; }
confere "develop protegida"        "$(cat_de develop)"       MANTER
confere "main protegida"           "$(cat_de main)"          MANTER
confere "mergeada"                 "$(cat_de feat/mergeada)" REMOVER
confere "squash"                   "$(cat_de feat/squash)"   REMOVER
confere "movida após merge"        "$(cat_de feat/movida)"   REVISAR
confere "movida motivo"            "$(mot_de feat/movida | grep -o 'PR mergeado' || true)" "PR mergeado"
confere "órfã"                     "$(cat_de feat/orfa)"     REVISAR
confere "órfã motivo"              "$(mot_de feat/orfa | grep -o 'órfã' || true)" "órfã"
confere "antiga"                   "$(cat_de feat/antiga)"   REVISAR
confere "antiga motivo"            "$(mot_de feat/antiga | grep -o 'meses' || true)" "meses"
confere "manter.tsv"               "$(cat_de ci/ensaio)"     MANTER
confere "PR aberto"                "$(cat_de feat/aberta)"   MANTER

awk -F'\t' 'NR>1 && $8=="REMOVER"{print $1"\t"$2}' "$T/out/relatorio.tsv" > "$T/lote.tsv"
confere "lote com 2 linhas" "$(wc -l < "$T/lote.tsv")" 2
existe() { git ls-remote origin "refs/heads/$1" | wc -l; }
roda() { if SEM_GH=1 "$FERR/remove_branches.sh" "$@" >/dev/null 2>&1; then echo passou; else echo recusou; fi; }

# 1) branch protegida no lote: aborta antes de qualquer push
{ cat "$T/lote.tsv"; printf 'develop\t%s\n' "$(git rev-parse origin/develop)"; } > "$T/lote_prot.tsv"
confere "1 protegida recusada" "$(echo 'REMOVER 3' | roda "$T/lote_prot.tsv" --executar)" recusou
confere "1 nada removido"      "$(existe feat/mergeada)" 1
# 2) SHA divergente do relatório: recusa
printf 'feat/squash\t%s\n' "$(git rev-parse origin/feat/orfa)" > "$T/lote_velho.tsv"
confere "2 SHA divergente"     "$(echo 'REMOVER 1' | roda "$T/lote_velho.tsv" --executar)" recusou
confere "2 nada removido"      "$(existe feat/squash)" 1
# 3) sem --executar só simula
confere "3 dry-run"            "$(roda "$T/lote.tsv")" passou
confere "3 nada removido"      "$(existe feat/mergeada)" 1
# 4) confirmação errada cancela
confere "4 confirmação errada" "$(echo 'sim' | roda "$T/lote.tsv" --executar)" recusou
confere "4 nada removido"      "$(existe feat/mergeada)" 1
# 5) execução real
confere "5 execução"           "$(echo 'REMOVER 2' | roda "$T/lote.tsv" --executar)" passou
confere "5 mergeada removida"  "$(existe feat/mergeada)" 0
confere "5 squash removida"    "$(existe feat/squash)" 0
confere "5 movida intacta"     "$(existe feat/movida)" 1
confere "5 develop intacta"    "$(existe develop)" 1

if (( falhas == 0 )); then echo "ENSAIO VERDE"; else echo "$falhas falha(s)"; exit 1; fi
EOF
chmod +x ~/limpeza-branches-sinalacs/ferramentas/ensaio_limpeza.sh
```

- [ ] **Passo 2: rodar o ensaio e ver que falha**

Rodar: `~/limpeza-branches-sinalacs/ferramentas/ensaio_limpeza.sh`
Esperado: falha porque `classifica_branches.sh` não existe (`No such file or directory`).

- [ ] **Passo 3: escrever o classificador (somente leitura)**

```bash
cat > ~/limpeza-branches-sinalacs/ferramentas/classifica_branches.sh <<'EOF'
#!/usr/bin/env bash
# SOMENTE LEITURA: lê refs/remotes/origin/* e, se houver gh, a lista de PRs.
# Uso: classifica_branches.sh <dir-saida>
# Ambiente: BASE (origin/develop), MESES (6), MANTER (branch<TAB>justificativa),
#           PRS_TSV (usa este arquivo no lugar do gh).
set -euo pipefail
OUT=${1:?uso: classifica_branches.sh <dir-saida>}
BASE=${BASE:-origin/develop}
MESES=${MESES:-6}
MANTER=${MANTER:-}
PROTEGIDAS_RE='^(main|develop|release/.+)$'
mkdir -p "$OUT"
corte=$(date -d "-${MESES} months" +%s)

if [[ -n ${PRS_TSV:-} ]]; then
  cp "$PRS_TSV" "$OUT/prs.tsv"
elif command -v gh >/dev/null 2>&1; then
  gh pr list --state all --limit 1000 --json number,headRefName,state \
    --jq '.[] | [.headRefName, (.number|tostring), .state] | @tsv' > "$OUT/prs.tsv"
else
  : > "$OUT/prs.tsv"; echo "aviso: sem gh, coluna de PR vazia" >&2
fi

justificativa() {
  [[ -n $MANTER && -f $MANTER ]] || return 0
  awk -F'\t' -v b="$1" '$1==b{print $2; exit}' "$MANTER"
}

printf 'branch\tsha\tdata\tautor\tfora_base\tsem_equivalente\tprs\tcategoria\tmotivo\n' > "$OUT/relatorio.tsv"
git for-each-ref refs/remotes/origin \
  --format='%(refname:lstrip=3)%09%(objectname)%09%(committerdate:short)%09%(committerdate:unix)%09%(authorname)' |
while IFS=$'\t' read -r b sha data ts autor; do
  [[ $b == HEAD ]] && continue
  # commits da ponta que não estão nem na base nem na main
  fora=$(git rev-list --count "origin/$b" --not "$BASE" origin/main)
  # desses, quantos não têm patch equivalente na base (pega squash/rebase)
  sobra=$(git cherry "$BASE" "origin/$b" | grep -c '^+' || true)
  prs=$(awk -F'\t' -v b="$b" '$1==b{printf "%s#%s:%s", (n++?",":""), $2, $3}' "$OUT/prs.tsv")
  j=$(justificativa "$b")
  if [[ $b =~ $PROTEGIDAS_RE ]]; then cat=MANTER; mot="branch protegida"
  elif [[ -n $j ]]; then cat=MANTER; mot="$j"
  elif [[ $prs == *:OPEN* ]]; then cat=MANTER; mot="PR aberto"
  elif (( fora == 0 )); then
    cat=REMOVER
    if [[ -n $prs ]]; then mot="contida na base (PR $prs)"; else mot="contida na base (merge direto, sem PR)"; fi
  elif (( sobra == 0 )); then cat=REMOVER; mot="patches equivalentes já na base (squash/rebase)"
  elif [[ $prs == *:MERGED* ]]; then cat=REVISAR; mot="PR mergeado, mas $sobra commit(s) nunca chegaram à base"
  elif (( ts < corte )); then cat=REVISAR; mot="$sobra commit(s) fora da base e sem commit há mais de $MESES meses"
  elif [[ $prs == *:CLOSED* ]]; then cat=REVISAR; mot="PR fechado sem merge; $sobra commit(s) fora da base"
  else cat=REVISAR; mot="órfã: $sobra commit(s) fora da base e nenhum PR"
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$b" "$sha" "$data" "$autor" "$fora" "$sobra" "${prs:--}" "$cat" "$mot"
done | sort -t$'\t' -k8,8 -k1,1 >> "$OUT/relatorio.tsv"

awk -F'\t' 'NR>1{n[$8]++} END{for(c in n) printf "%s: %d\n", c, n[c]}' "$OUT/relatorio.tsv" | sort
EOF
chmod +x ~/limpeza-branches-sinalacs/ferramentas/classifica_branches.sh
```

- [ ] **Passo 4: escrever o removedor (destrutivo, com travas)**

```bash
cat > ~/limpeza-branches-sinalacs/ferramentas/remove_branches.sh <<'EOF'
#!/usr/bin/env bash
# DESTRUTIVO com --executar. Sem a flag, só mostra o que faria (git push --dry-run).
# Uso: remove_branches.sh <lote.tsv> [--executar]     lote: branch<TAB>sha
# Recusa (e não remove nada) se: branch protegida, SHA no remoto diferente do
# aprovado, branch base de PR aberto, ou confirmação diferente de "REMOVER <n>".
set -euo pipefail
LOTE=${1:?uso: remove_branches.sh <lote.tsv> [--executar]}
MODO=${2:-}
PROTEGIDAS_RE='^(main|develop|release/.+)$'
leases=(); refs=(); nomes=()
while IFS=$'\t' read -r b sha; do
  [[ -z $b || $b == \#* ]] && continue
  if [[ $b =~ $PROTEGIDAS_RE ]]; then echo "RECUSADO: $b é protegida" >&2; exit 1; fi
  atual=$(git ls-remote origin "refs/heads/$b" | awk -v r="refs/heads/$b" '$2==r{print $1}')
  if [[ -z $atual ]]; then echo "já ausente no remoto: $b"; continue; fi
  if [[ $atual != "$sha" ]]; then
    echo "RECUSADO: $b mudou desde o relatório ($sha -> $atual); reclassifique" >&2; exit 1
  fi
  if [[ -z ${SEM_GH:-} ]] && command -v gh >/dev/null 2>&1 &&
     [[ -n $(gh pr list --state open --base "$b" --json number --jq '.[].number') ]]; then
    echo "RECUSADO: $b é base de PR aberto" >&2; exit 1
  fi
  leases+=("--force-with-lease=refs/heads/$b:$sha"); refs+=(":refs/heads/$b"); nomes+=("$b")
done < "$LOTE"
(( ${#refs[@]} )) || { echo "nada a remover"; exit 0; }
printf 'remover: %s\n' "${nomes[@]}"
if [[ $MODO != --executar ]]; then
  git push --dry-run --atomic "${leases[@]}" origin "${refs[@]}"; exit 0
fi
read -r -p "Digite 'REMOVER ${#refs[@]}' para confirmar: " resp
[[ $resp == "REMOVER ${#refs[@]}" ]] || { echo "cancelado" >&2; exit 1; }
git push --atomic "${leases[@]}" origin "${refs[@]}"
EOF
chmod +x ~/limpeza-branches-sinalacs/ferramentas/remove_branches.sh
```

- [ ] **Passo 5: rodar o ensaio e ver que passa**

Rodar: `~/limpeza-branches-sinalacs/ferramentas/ensaio_limpeza.sh`
Esperado: todas as linhas começam com `ok`, e a última é `ENSAIO VERDE`.
Se aparecer `FALHA`, corrija o script (não o ensaio) e rode de novo. Não avance com o ensaio vermelho.

- [ ] **Passo 6: nada a commitar.** As ferramentas ficam fora do repositório.

### Tarefa 2: Levantamento real (somente leitura)

**Interfaces:**
- Consome: `classifica_branches.sh` (Tarefa 1).
- Produz: `~/limpeza-branches-sinalacs/<data>/relatorio.tsv` e `prs.tsv`.

- [ ] **Passo 1: atualizar as refs locais e criar a pasta da rodada**

```bash
cd ~/Documents/Dev/APPs/SinalACS
git fetch origin --prune        # só refs locais; não altera o remoto
R=~/limpeza-branches-sinalacs/$(date +%F); mkdir -p "$R"
printf 'ci/ensaio-ubuntu-26.04\tensaio da migração para ubuntu-26.04 (ubuntu-latest migra em 2026-10-19); remover após o PR da migração\n' > "$R/manter.tsv"
```

- [ ] **Passo 2: listagens brutas, para conferência manual** (as mesmas que o pedido cita)

```bash
git for-each-ref refs/remotes/origin --sort=-committerdate \
  --format='%(committerdate:short)  %(objectname:short)  %(authorname)  %(refname:short)'
git branch -r --merged origin/develop      # contidas na develop
git branch -r --no-merged origin/develop   # com commits fora da develop
git branch -r --merged origin/main         # contidas na main (menos útil: a main está atrás)
gh repo view --json deleteBranchOnMerge     # opcional; hoje: false
gh pr list --state open                     # opcional; hoje: nenhum
```

- [ ] **Passo 3: gerar o relatório**

```bash
MANTER="$R/manter.tsv" ~/limpeza-branches-sinalacs/ferramentas/classifica_branches.sh "$R"
column -t -s$'\t' "$R/relatorio.tsv" | less -S
```

Esperado (se nada mudou desde 2026-10-15; conferido com o classificador nessa data): `MANTER: 3`, `REMOVER: 37`, `REVISAR: 3`. Os REVISAR são `feat/issue-44-alertas-escalonar-tempo-real` e `fix/issue-56-mqtt-queda-processo` (motivo "PR mergeado, mas 24 commit(s) nunca chegaram à base") e `analysis-cybersec` ("órfã: 3 commit(s)…"; já decidida como remover, ver lote 3). Se o PR da #56 já tiver sido mergeado, as duas primeiras aparecem em REMOVER. Qualquer outra diferença em relação às tabelas da seção "Classificação prevista" deve ser explicada antes da Tarefa 3.

- [ ] **Passo 4: conferência cruzada de um REMOVER e de um REVISAR**

```bash
git merge-base --is-ancestor origin/feat/issue-43-gestao-de-acs-e-mfa origin/develop && echo contida
git cherry origin/develop origin/fix/issue-56-mqtt-queda-processo | grep -c '^+'   # esperado: 24 (enquanto a #56 não entrar)
```

### Tarefa 3: Revisão humana e montagem dos lotes

**Interfaces:**
- Consome: `$R/relatorio.tsv`.
- Produz: `$R/lote1.tsv`, `$R/lote2.tsv` e `$R/lote3.tsv` (`branch<TAB>sha`), revisados por uma pessoa.

- [ ] **Passo 1: gerar os rascunhos dos lotes a partir do relatório**

```bash
awk -F'\t' 'NR>1 && $8=="REMOVER" && $7!="-"{print $1"\t"$2}' "$R/relatorio.tsv" > "$R/lote1.tsv"   # com PR
awk -F'\t' 'NR>1 && $8=="REMOVER" && $7=="-"{print $1"\t"$2}' "$R/relatorio.tsv" > "$R/lote2.tsv"   # sem PR
# órfã removida por decisão do mantenedor: sai do relatório pelo nome, com o SHA do dia
awk -F'\t' '$1=="analysis-cybersec" && $8=="REVISAR"{print $1"\t"$2}' "$R/relatorio.tsv" > "$R/lote3.tsv"
wc -l "$R"/lote*.tsv     # esperado: 29, 8 e 1
grep -q $'^analysis-cybersec\t8470c67' "$R/lote3.tsv" && echo "ponta esperada"   # se não imprimir, a branch andou: reveja antes de remover
```

- [ ] **Passo 2: a pessoa revisora decide, linha a linha.** Checklist:
  - [ ] Nenhuma `main`, `develop` ou `release/*` em lote nenhum (o script também recusa).
  - [ ] Nenhuma branch REVISAR entrou num lote sem decisão registrada.
  - [ ] `feat/issue-44-…` e `fix/issue-56-…` **fora** dos lotes enquanto o PR da #56 → develop não for mergeado.
  - [ ] `ci/ensaio-ubuntu-26.04` fora dos lotes até a migração para 26.04 entrar.
  - [ ] `analysis-cybersec` só no `lote3.tsv` e nenhuma outra branch REVISAR em lote algum.
  - [ ] Autores externos (sarah, Rosialdo, vinimartinsufrr) avisados. O rosialdo em especial: a `analysis-cybersec` leva 3 commits que não estão na develop.
  - [ ] `docs/atualiza-readme-e-docs` é a branch local atual do mantenedor: remover no remoto não afeta a local, que passa a aparecer como `[gone]` em `git branch -vv`.

- [ ] **Passo 3: registrar a aprovação** (quem aprovou e quando), no topo de cada lote:

```bash
sed -i "1i # aprovado por <nome> em $(date '+%F %H:%M')" "$R/lote1.tsv" "$R/lote2.tsv" "$R/lote3.tsv"
```

---

## FASE B — DESTRUTIVA (Tarefas 4 a 6b)

> ⚠️ Só comece com o ensaio verde (Tarefa 1), o relatório **do mesmo dia** (Tarefa 2) e os lotes aprovados (Tarefa 3). A Tarefa 4 é local e reversível. As Tarefas 5, 6 e 6b removem do remoto.

### Tarefa 4: Backup das pontas (local, antes de remover)

- [ ] **Passo 1: refs locais de backup** (protegem os objetos do `git gc` depois do `fetch --prune`)

```bash
cd ~/Documents/Dev/APPs/SinalACS
D=$(basename "$R")
cat "$R"/lote*.tsv | grep -v '^#' | while IFS=$'\t' read -r b sha; do
  git update-ref "refs/backup/limpeza-$D/$b" "$sha"
done
git for-each-ref "refs/backup/limpeza-$D/" | wc -l     # esperado: total de linhas dos lotes
```

- [ ] **Passo 2: bundle (backup portátil, fora do clone)**

```bash
git bundle create "$R/branches-removidas.bundle" $(git for-each-ref --format='%(refname)' "refs/backup/limpeza-$D/")
git bundle verify "$R/branches-removidas.bundle"       # esperado: "... is okay"
```

- [ ] **Passo 3: diff legível da órfã** (a única com commits fora da base)

```bash
git format-patch --stdout origin/develop..origin/analysis-cybersec > "$R/analysis-cybersec.patch"
grep -c '^From ' "$R/analysis-cybersec.patch"          # esperado: 3
git bundle list-heads "$R/branches-removidas.bundle" | grep -c analysis-cybersec   # esperado: 1
```

### Tarefa 5: Remoção do lote 1 (contidas na develop, com PR)

- [ ] **Passo 1: pré-condições**

```bash
gh pr list --state open --json number,headRefName,baseRefName    # esperado: [] ou nada que use as branches do lote
```

- [ ] **Passo 2: simulação (dry-run, não remove)**

```bash
~/limpeza-branches-sinalacs/ferramentas/remove_branches.sh "$R/lote1.tsv" 2>&1 | tee -a "$R/execucao.log"
```
Esperado: `remover: …` com 29 nomes e as linhas `- [deleted]` do `--dry-run`, sem nenhum `RECUSADO`. Se aparecer `RECUSADO: … mudou desde o relatório`, volte à Tarefa 2.

- [ ] **Passo 3: execução (DESTRUTIVO)**

```bash
~/limpeza-branches-sinalacs/ferramentas/remove_branches.sh "$R/lote1.tsv" --executar 2>&1 | tee -a "$R/execucao.log"
# digite exatamente: REMOVER 29
```
Esperado: 29 `- [deleted]`. Com `--atomic`, ou todas saem ou nenhuma sai.

- [ ] **Passo 4: conferir**

```bash
grep -v '^#' "$R/lote1.tsv" | cut -f1 | while read -r b; do git ls-remote --exit-code origin "refs/heads/$b" >/dev/null && echo "AINDA EXISTE: $b"; done
```
Esperado: nenhuma saída.

### Tarefa 6: Remoção do lote 2 (merge direto, sem PR)

- [ ] **Passo 1: simulação**: `~/limpeza-branches-sinalacs/ferramentas/remove_branches.sh "$R/lote2.tsv" 2>&1 | tee -a "$R/execucao.log"`. Esperado: 8 nomes.
- [ ] **Passo 2: execução (DESTRUTIVO)**: o mesmo comando com `--executar`; digite `REMOVER 8`.
- [ ] **Passo 3: conferir**: o mesmo laço da Tarefa 5, Passo 4, com `lote2.tsv`.

### Tarefa 6b: Remoção do lote 3 (`analysis-cybersec`, órfã)

Este é o único lote que apaga do remoto commits que não estão na develop. A Tarefa 4, Passo 3, tem que ter passado: patch com 3 commits e bundle com a ponta.

- [ ] **Passo 1: simulação**: `~/limpeza-branches-sinalacs/ferramentas/remove_branches.sh "$R/lote3.tsv" 2>&1 | tee -a "$R/execucao.log"`. Esperado: `remover: analysis-cybersec`.
- [ ] **Passo 2: execução (DESTRUTIVO)**: o mesmo comando com `--executar`; digite `REMOVER 1`.
- [ ] **Passo 3: conferir**: `git ls-remote --exit-code origin refs/heads/analysis-cybersec` deve sair com código 2 (ausente).

---

## FASE C — FECHAMENTO (somente leitura, exceto a Tarefa 8)

### Tarefa 7: Prune e verificação final

- [ ] **Passo 1:** `git fetch --prune origin`
- [ ] **Passo 2:** `git branch -r | wc -l`. Esperado: 6 (`origin/HEAD` + as 5 mantidas).
- [ ] **Passo 3:** rodar o classificador de novo numa pasta nova e conferir que não sobrou nenhum `REMOVER`:

```bash
R2=~/limpeza-branches-sinalacs/$(date +%F)-pos; MANTER="$R/manter.tsv" ~/limpeza-branches-sinalacs/ferramentas/classifica_branches.sh "$R2"
```

- [ ] **Passo 4 (opcional, local):** listar as branches locais cujo upstream sumiu. A decisão de apagá-las é da pessoa; este plano não remove nada local.

```bash
git branch -vv | grep ': gone]'
```

- [ ] **Passo 5:** guardar `$R/` (relatório, lotes, bundle, log) por pelo menos 90 dias.

### Tarefa 8: Prevenção

- [ ] **Passo 1 (ação externa: confirme com o mantenedor antes):** ligar o auto-delete após o merge.

```bash
gh api -X PATCH repos/hbgit/SinalACS -F delete_branch_on_merge=true
gh repo view --json deleteBranchOnMerge     # esperado: true
```
Além de evitar o acúmulo, isso teria evitado o caso #57/#58. Quando o GitHub apaga a branch base de um PR empilhado, ele **redireciona** o PR dependente para a base seguinte (aqui, a `develop`). O #58 teria ido para a develop em vez de para uma branch já mergeada.

- [ ] **Passo 2: regra para PR empilhado** (proposta para o `CONTRIBUTING.md` › CI e merge, em PR próprio). Antes de mergear um PR cuja base não é `develop`/`main`, confira se a base ainda está aberta:

```bash
gh pr view <N> --json baseRefName --jq .baseRefName
gh pr list --head <base> --state merged     # se listar algo: redirecione o PR para develop antes de mergear
```

- [ ] **Passo 3: convenção de nomes** (a que já está em uso desde a #43): `feat|fix|docs|ci/issue-<N>-<slug>`. Branch `ci/ensaio-*` é descartável e se apaga quando a mudança ensaiada entrar. Nada de branch sem prefixo (`analysis-cybersec`).
- [ ] **Passo 4: revisão periódica**: no primeiro dia útil de cada mês, rodar as Tarefas 2 e 3. Com o auto-delete ligado, o REMOVER deve vir quase vazio, e o que importa é a coluna REVISAR.
- [ ] **Passo 5: prune automático nos clones**: `git config --global fetch.prune true`.
- [ ] **Passo 6 (opcional, PR próprio):** trazer `classifica_branches.sh` para `scripts/qa/` com o ensaio rodando no `workflow-lint`, só a parte somente leitura. Isso não muda a lista de jobs do `ci_invariants.sh`.

---

## Reversão

Cada ponta removida está em três lugares: no relatório (`$R/relatorio.tsv`, coluna `sha`), nas refs locais `refs/backup/limpeza-<data>/` e no bundle `$R/branches-removidas.bundle`. Para recriar uma branch no remoto, nesta ordem de preferência:

1. **Pelo backup local** (o caminho mais simples):
   ```bash
   git push origin refs/backup/limpeza-<data>/<branch>:refs/heads/<branch>
   ```
2. **Pelo SHA do relatório**, se o objeto ainda existir localmente:
   ```bash
   sha=$(awk -F'\t' -v b='<branch>' '$1==b{print $2}' "$R/relatorio.tsv")
   git cat-file -t "$sha"                      # esperado: commit
   git push origin "$sha:refs/heads/<branch>"
   ```
3. **Pelo bundle**, em outro clone ou máquina:
   ```bash
   git fetch "$R/branches-removidas.bundle" "refs/backup/limpeza-<data>/<branch>:refs/heads/<branch>"
   git push origin <branch>
   ```
4. **Pelo GitHub**, se tudo o mais faltar: a página do PR mergeado tem o botão "Restore branch". A ref `refs/pull/<N>/head` continua no remoto (`git fetch origin pull/<N>/head:<branch>`), mas aponta para a ponta **no momento do PR**, que pode diferir da ponta removida.
5. **Pelo reflog**, só na máquina que fez o fetch antes da remoção: o `fetch --prune` apaga o reflog da ref remota, então use `git reflog --all | grep <sha-curto>` como último recurso. Os itens 1 a 3 não dependem do reflog.

A `analysis-cybersec` não tem PR, então o item 4 não serve para ela. Restaure pelos itens 1 a 3. Para só ler o conteúdo, há `$R/analysis-cybersec.patch` (`git am` o reaplica sobre outra base).
