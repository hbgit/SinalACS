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

exec python3 - "${CI_WORKFLOW_PATH:-$repo_root/.github/workflows/ci.yml}" "$@" <<'PY'
import json
import re
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
    # O snapshot do AVD é específico da imagem do runner: sem a imagem na
    # chave, a primeira execução numa imagem nova restauraria o AVD da antiga.
    for passo in jobs.get('android-e2e', {}).get('steps', []):
        chave = str((passo.get('with') or {}).get('key', ''))
        if chave.startswith('avd-') and not chave.endswith(f'-{RUNNER}'):
            falhas.append(f'FINDING-6: chave do cache de AVD {chave!r} não termina em -{RUNNER}')


# Checks obrigatórios para merge em main e develop (FINDING-5). O
# android-e2e fica de fora enquanto não tiver histórico verde: torná-lo
# obrigatório hoje travaria toda PR num job sabidamente instável (FINDING-4).
# A proteção de branch é aplicada a partir desta lista (--checks-obrigatorios).
# Este script não lê a proteção configurada no GitHub: ao renomear ou criar um
# job, reaplique-a (ver CONTRIBUTING.md › CI e merge), senão PRs esperam por um
# check que não existe mais.
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


# Credenciais do FCM (chave de conta de serviço e google-services.json) no android-e2e.
# Os secrets valem acesso ao projeto Firebase; estas propriedades têm de sobreviver a
# edições:
#  1. cada secret entra por `env:` do PASSO — nunca dentro de `run:` (injeção de script, e
#     um `echo` o vazaria) nem no `env:` do JOB (toda ação de terceiros o veria);
#  2. os passos que os decodificam vêm ANTES do E2E (o build do paciente e o push e2e os
#     leem);
#  3. um passo `if: always()` apaga os três arquivos depois;
#  4. o push só entrega com Play Services: o emulador precisa de `target: google_apis` (o
#     padrão da action é a imagem AOSP, sem ele), e a chave do cache do AVD precisa
#     conter o target, senão um AVD antigo seria restaurado em cima do novo.
SEGREDOS_FCM = {
    'FCM_CREDENTIALS_BASE64': 'Decodifica a credencial do FCM',
    'GOOGLE_SERVICES_JSON_BASE64': 'Decodifica o google-services.json',
}
LIMPEZA_FCM = 'Remove as credenciais do FCM'
LIMPEZAS_ESPERADAS = (
    'decode_secret_file.sh --cleanup-temp GOOGLE_APPLICATION_CREDENTIALS',
    '--cleanup-file apps/patient/android/app/google-services.json',
    '--cleanup-file infra/docker/gorush/credentials/fcm-service-account.json',
)
TARGET_EMULADOR = 'google_apis'


def check_credenciais_fcm():
    # Varredura do TEXTO bruto (sem as linhas de comentário): os secrets só podem aparecer UMA
    # vez cada, na linha `env:` do passo que os decodifica. Isso cobre os contornos que a
    # leitura estrutural não vê: `env:` de workflow, `with:` de uma ação, `env:` de outro
    # passo/job, `secrets['NOME']` e `toJSON(secrets)` (que entrega TODOS os secrets).
    with open(caminho, encoding='utf-8') as arquivo:
        texto = '\n'.join(l for l in arquivo.read().splitlines() if not l.lstrip().startswith('#'))
    for segredo in SEGREDOS_FCM:
        usos = (len(re.findall(r'secrets\s*\.\s*' + segredo + r'\b', texto))
                + len(re.findall(r'secrets\s*\[\s*[\'"]' + segredo + r'[\'"]\s*\]', texto)))
        if usos != 1:
            falhas.append(f'FCM: {segredo} aparece {usos}x no workflow; só pode aparecer 1x, no env: do passo que o decodifica')
    if re.search(r'toJSON\(\s*secrets\s*\)', texto):
        falhas.append('FCM: toJSON(secrets) entrega todos os secrets, inclusive os do FCM; não use')
    if re.search(r'secrets\s*\[\s*[^\'"\s]', texto):
        falhas.append('FCM: secrets[<expressão>] é dinâmico e poderia alcançar os secrets do FCM; use o nome literal')
    for nome_job, job in jobs.items():
        for segredo in SEGREDOS_FCM:
            if segredo in (job.get('env') or {}):
                falhas.append(f'FCM: {nome_job} declara {segredo} no env: do job; declare só no passo')
            for passo in job.get('steps') or []:
                if f'secrets.{segredo}' in (passo.get('run') or ''):
                    falhas.append(f"FCM: o passo {passo.get('name')!r} de {nome_job} usa secrets.{segredo} dentro de run:; passe por env: do passo")
    passos = (jobs.get('android-e2e') or {}).get('steps') or []
    nomes = [p.get('name', '') for p in passos]
    indice_e2e = nomes.index('E2E no emulador Android') if 'E2E no emulador Android' in nomes else None
    if indice_e2e is None:
        falhas.append("FCM: android-e2e sem o passo 'E2E no emulador Android'; a ordem das credenciais não pode ser conferida")
    ultimo = -1
    for segredo, nome_passo in SEGREDOS_FCM.items():
        if nome_passo not in nomes:
            falhas.append(f'FCM: android-e2e sem o passo {nome_passo!r}')
            continue
        i = nomes.index(nome_passo)
        ultimo = max(ultimo, i)
        passo = passos[i]
        if (passo.get('env') or {}).get(segredo) != '${{ secrets.' + segredo + ' }}':
            falhas.append(f'FCM: o passo {nome_passo!r} precisa de env: {segredo}: ${{{{ secrets.{segredo} }}}}')
        if 'decode_secret_file.sh' not in (passo.get('run') or ''):
            falhas.append(f'FCM: o passo {nome_passo!r} precisa chamar scripts/ci/decode_secret_file.sh')
        if indice_e2e is not None and i > indice_e2e:
            falhas.append(f'FCM: {nome_passo!r} vem DEPOIS do E2E; o arquivo não existiria nele')
    # As credenciais só podem existir em disco quando o passo do E2E (que as usa) roda: entre a
    # primeira decodificação e ele não pode haver ação de terceiros (setup-java, flutter-action,
    # cache...), que leria os arquivos sem precisar deles. Só passos `run:` ficam no meio.
    decodificados = [nomes.index(n) for n in SEGREDOS_FCM.values() if n in nomes]
    if decodificados and indice_e2e is not None:
        for passo in passos[min(decodificados) + 1:indice_e2e]:
            if passo.get('uses'):
                falhas.append(f"FCM: a ação {passo['uses']!r} roda com as credenciais já em disco; decodifique logo antes de 'E2E no emulador Android'")
    limpeza = [p for p in passos[ultimo + 1:] if p.get('name') == LIMPEZA_FCM]
    if not limpeza:
        falhas.append(f'FCM: nenhum passo {LIMPEZA_FCM!r} depois das decodificações')
    else:
        passo = limpeza[0]
        if indice_e2e is not None and passos.index(passo) < indice_e2e:
            falhas.append(f'FCM: o passo {LIMPEZA_FCM!r} vem ANTES do E2E; apagaria as credenciais que ele usa')
        if passo.get('if') != 'always()':
            falhas.append(f'FCM: o passo {LIMPEZA_FCM!r} precisa de if: always()')
        for trecho in LIMPEZAS_ESPERADAS:
            if trecho not in (passo.get('run') or ''):
                falhas.append(f'FCM: o passo {LIMPEZA_FCM!r} não roda {trecho!r}')
    # Emulador com Play Services e cache do AVD coerente.
    emuladores = [p for p in passos if str(p.get('uses', '')).startswith('reactivecircus/android-emulator-runner')]
    if not emuladores:
        falhas.append('FCM: android-e2e sem passo reactivecircus/android-emulator-runner')
    for passo in emuladores:
        if (passo.get('with') or {}).get('target') != TARGET_EMULADOR:
            falhas.append(f"FCM: o passo {passo.get('name')!r} precisa de target: {TARGET_EMULADOR} (sem Play Services o FCM não entrega token)")
    for passo in passos:
        chave = str((passo.get('with') or {}).get('key', ''))
        if chave.startswith('avd-') and f'-{TARGET_EMULADOR}-' not in chave:
            falhas.append(f'FCM: a chave do cache do AVD {chave!r} não contém o target {TARGET_EMULADOR!r}')


CHECKS = [check_jobs, check_gatilhos, check_sem_filtro_de_paths, check_concorrencia,
          check_limpeza_do_workspace, check_versoes_de_acoes,
          check_runner, check_checks_obrigatorios, check_credenciais_fcm]

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
