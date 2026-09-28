#!/usr/bin/env bash
#
# Invariantes do próprio workflow de CI (.github/workflows/ci.yml).
#
# Por que existe: a avaliação de 2026-09-28
# (docs/ci-audit/2026-09-28-avaliacao-ci-develop.md) achou derivas que ninguém
# viu acontecer — a documentação contava seis jobs com oito no arquivo, push em
# develop não disparava nada, não havia concorrência, as ações ficaram em
# versões depreciadas e a imagem do runner mudaria sozinha. Cada uma vira aqui
# uma asserção que falha com o número do achado.
#
#   ./scripts/qa/ci_invariants.sh
#
# Não precisa de rede nem da stack; só python3 com PyYAML. Roda no job
# workflow-lint do próprio CI.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

exec python3 - "$repo_root/.github/workflows/ci.yml" "$@" <<'PY'
import json
import sys

import yaml

caminho = sys.argv[1]
with open(caminho, encoding='utf-8') as f:
    wf = yaml.safe_load(f)

# PyYAML segue o YAML 1.1, em que a chave `on` é lida como o booleano True.
gatilhos = wf.get('on', wf.get(True)) or {}
jobs = wf.get('jobs') or {}
falhas = []

# Os jobs que CLAUDE.md e AGENTS.md enumeram. Mudou aqui, muda lá no mesmo
# commit — foi exatamente essa enumeração que envelheceu (FINDING-1).
JOBS_DOCUMENTADOS = {
    'workflow-lint',
    'serverpod-backend',
    'backend-docker-build',
    'patient-app',
    'acs-app',
    'admin-app',
    'coverage-report',
    'android-e2e',
    'admin-android-build',
}


def check_jobs():
    atuais = set(jobs)
    if atuais != JOBS_DOCUMENTADOS:
        falhas.append(
            'FINDING-1: jobs do workflow divergem da lista documentada — '
            f'a mais: {sorted(atuais - JOBS_DOCUMENTADOS)}, '
            f'faltando: {sorted(JOBS_DOCUMENTADOS - atuais)}. '
            'Atualize CLAUDE.md, AGENTS.md e JOBS_DOCUMENTADOS juntos.'
        )


def check_gatilhos():
    push = (gatilhos.get('push') or {}).get('branches') or []
    if 'develop' not in push:
        falhas.append(f'FINDING-2: push não dispara o CI em develop (branches: {push})')
    if 'workflow_dispatch' not in gatilhos:
        falhas.append('FINDING-2: sem workflow_dispatch, não há como disparar o CI à mão')
    if 'pull_request' not in gatilhos:
        falhas.append('pull_request deixou de disparar o CI')


def check_sem_filtro_de_paths():
    # Um check obrigatório que não roda nunca reporta, e a PR fica esperando
    # para sempre. Filtro de paths faria isso com toda PR só de documentação.
    for evento in ('push', 'pull_request'):
        cfg = gatilhos.get(evento) or {}
        for chave in ('paths', 'paths-ignore'):
            if chave in cfg:
                falhas.append(f'{evento}.{chave} faria checks obrigatórios nunca reportarem')


def check_concorrencia():
    c = wf.get('concurrency')
    if not isinstance(c, dict):
        falhas.append('FINDING-7: sem bloco concurrency no nível do workflow')
        return
    grupo = str(c.get('group', ''))
    # Sem o SHA, dois pushes seguidos em develop cairiam no mesmo grupo e o
    # segundo apagaria o resultado do primeiro — o FINDING-4 de novo.
    for termo in ('github.event_name', 'github.event.pull_request.number', 'github.sha'):
        if termo not in grupo:
            falhas.append(f'FINDING-7: concurrency.group sem {termo}: {grupo}')
    if c.get('cancel-in-progress') is not True:
        falhas.append('FINDING-7: concurrency sem cancel-in-progress: true')


def check_limpeza_do_workspace():
    # A stack do android-e2e deixa pg_data/ no workspace com modo 700 e dono
    # do container: o hashFiles('**/pubspec.lock') do pós-passo do
    # flutter-action não consegue varrê-lo e derruba um job cujo E2E passou
    # (run 36494654391). Algum passo depois do E2E tem de apagá-lo, sempre.
    passos = (jobs.get('android-e2e') or {}).get('steps') or []
    nomes = [p.get('name', '') for p in passos]
    if 'E2E no emulador Android' not in nomes:
        falhas.append('android-e2e sem o passo "E2E no emulador Android"')
        return
    depois = passos[nomes.index('E2E no emulador Android') + 1:]
    if not any(p.get('if') == 'always()' and 'pg_data' in (p.get('run') or '') for p in depois):
        falhas.append('android-e2e: nenhum passo if: always() apaga pg_data/ depois do E2E')


# Major mínimo de cada ação da GitHub (FINDING-6): abaixo disso ela roda em
# Node 20, depreciado, ou — setup-java v4 — não recebe mais atualização.
MAJOR_MINIMO = {
    'actions/checkout': 7,
    'actions/setup-java': 6,
    'actions/cache': 6,
    'actions/upload-artifact': 7,
}


def check_versoes_de_acoes():
    for nome_job, job in jobs.items():
        for passo in job.get('steps') or []:
            uses = passo.get('uses') or ''
            acao, _, versao = uses.partition('@')
            minimo = MAJOR_MINIMO.get(acao)
            if minimo is None:
                continue
            if not versao.startswith('v') or not versao[1:].split('.')[0].isdigit():
                # Fixar por SHA é legítimo, mas então esta guarda precisa
                # aprender a ler o comentário de versão — não passar calada.
                falhas.append(f'FINDING-6: {nome_job} usa {uses}; este check só entende tags vN')
                continue
            if int(versao[1:].split('.')[0]) < minimo:
                falhas.append(f'FINDING-6: {nome_job} usa {uses}; mínimo v{minimo}')


# Imagem fixada (FINDING-6): `ubuntu-latest` migra de versão sozinho, no dia
# que a GitHub escolher (Ubuntu 26 a partir de 2026-10-19). Trocar de imagem
# tem de ser um PR, não uma surpresa.
RUNNER = 'ubuntu-24.04'


def check_runner():
    for nome_job, job in jobs.items():
        if job.get('runs-on') != RUNNER:
            falhas.append(f"FINDING-6: {nome_job} roda em {job.get('runs-on')!r}; esperado {RUNNER!r}")


# Checks obrigatórios para merge em main e develop (FINDING-5). O
# android-e2e fica de fora enquanto não tiver histórico verde: torná-lo
# obrigatório hoje travaria toda PR num job sabidamente instável (FINDING-4).
# A proteção de branch é aplicada a partir desta lista (--checks-obrigatorios),
# então renomear um job quebra aqui antes de deixar PRs esperando por um check
# que não existe mais.
CHECKS_OBRIGATORIOS = sorted(JOBS_DOCUMENTADOS - {'android-e2e'})
# App GitHub Actions: amarrar o check ao app impede que outra integração
# publique um status com o mesmo nome e destrave o merge.
APP_GITHUB_ACTIONS = 15368

def check_checks_obrigatorios():
    if 'android-e2e' in CHECKS_OBRIGATORIOS:
        falhas.append('FINDING-4: android-e2e não pode ser obrigatório enquanto for instável')
    for nome in CHECKS_OBRIGATORIOS:
        job = jobs.get(nome)
        if job is None:
            falhas.append(f'FINDING-5: check obrigatório {nome} não existe no workflow')
            continue
        # O nome do check é o `name:` do job, se houver; e um job com `if:`
        # pode não rodar e nunca reportar.
        if job.get('name', nome) != nome:
            falhas.append(f"FINDING-5: {nome} tem name: {job['name']!r}; o check obrigatório não casaria")
        if 'if' in job:
            falhas.append(f'FINDING-5: {nome} tem if: no nível do job; pode nunca reportar')


CHECKS = [check_jobs, check_gatilhos, check_sem_filtro_de_paths, check_concorrencia,
          check_limpeza_do_workspace, check_versoes_de_acoes,
          check_runner, check_checks_obrigatorios]

for check in CHECKS:
    check()

if falhas:
    for falha in falhas:
        print(f'FALHA: {falha}', file=sys.stderr)
    sys.exit(1)
if '--checks-obrigatorios' in sys.argv[2:]:
    print(json.dumps([{'context': c, 'app_id': APP_GITHUB_ACTIONS} for c in CHECKS_OBRIGATORIOS]))
    sys.exit(0)
print(f'ok: {len(CHECKS)} grupos de invariantes do CI')
PY
