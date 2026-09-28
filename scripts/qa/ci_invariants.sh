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


CHECKS = [check_jobs, check_gatilhos, check_sem_filtro_de_paths, check_concorrencia]

for check in CHECKS:
    check()

if falhas:
    for falha in falhas:
        print(f'FALHA: {falha}', file=sys.stderr)
    sys.exit(1)
print(f'ok: {len(CHECKS)} grupos de invariantes do CI')
PY
