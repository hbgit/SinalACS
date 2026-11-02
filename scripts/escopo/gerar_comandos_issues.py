"""Gera os comandos `gh` da classificação aprovada das issues. Nunca executa nada.

Uso:
  python3 -I scripts/escopo/gerar_comandos_issues.py <documento> --hash <aprovado> --lote <lote>
  python3 -I scripts/escopo/gerar_comandos_issues.py --conferir-corpo <N>

Lotes: rotulos, milestones, existentes, reescritas, novas.

Regras (plano docs/superpowers/plans/2026-11-02-milestones-issues.md):
- recusa rodar se `git hash-object <documento>` for diferente do hash aprovado;
- consulta o estado atual no GitHub para ser idempotente: rótulo/milestone
  existente, issue com título exato existente, comentário com o marcador,
  corpo já começando com o bloco de escopo;
- na reescrita, a checagem "já reescrita" vem antes da guarda de corpo;
- bodies e comentários vão para arquivos em .git/escopo-issues/, nunca em
  linha de comando;
- comparação de corpos normaliza \\r\\n e espaços no fim das linhas.
"""

import json
import os
import re
import shlex
import subprocess
import sys

REPO = 'hbgit/SinalACS'
MARCADOR = '<!-- escopo-2026-11-02 -->'
BLOCO_INICIO = '> **Escopo revisto (2026-11-02):**'
ROTULOS = {
    'futuro': ('BFD4F2', 'Trabalho futuro (spec/trabalhos_futuros.md)'),
    'a-decidir': ('FBCA04', 'Classificação a decidir pela equipe'),
    'acao-equipe': ('C5DEF5', 'Ação da equipe do projeto (não é código)'),
}
MILESTONES = {
    'Pilot': 'Pronto antes da primeira coleta com participantes. Sem data: depende do parecer do CEP (P-04). '
             'Ver https://github.com/hbgit/SinalACS/blob/develop/spec/plano_piloto.md',
    'v1.0': 'Requisitos Desejáveis, mudanças fora do portão e correções que o piloto revelar. '
            'Ver https://github.com/hbgit/SinalACS/blob/develop/spec/requisitos_piloto.md',
}


def sh(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


def gitdir():
    return sh('git', 'rev-parse', '--absolute-git-dir').strip()


def inventario():
    with open(os.path.join(gitdir(), 'issues-inventario.json'), encoding='utf-8') as f:
        return {i['number']: i for i in json.load(f)}


def norm(t):
    return '\n'.join(l.rstrip() for l in (t or '').replace('\r\n', '\n').split('\n')).strip()


def tmpfile(nome, conteudo):
    d = os.path.join(gitdir(), 'escopo-issues')
    os.makedirs(d, exist_ok=True)
    p = os.path.join(d, nome)
    with open(p, 'w', encoding='utf-8') as f:
        f.write(conteudo)
    return p


def secao(doc, titulo):
    limpo = re.sub(r'<!-- corpo -->.*?<!-- /corpo -->', lambda m: m.group(0).replace('\n## ', '\n#§ '), doc, flags=re.S)
    m = re.search(r'^## ' + re.escape(titulo) + r'\n(.*?)(?=^## |\Z)', limpo, re.M | re.S)
    return m.group(1).replace('\n#§ ', '\n## ') if m else ''


def tabela(doc):
    linhas = []
    for m in re.finditer(r'^\| (\d+) \|.*$', secao(doc, 'Tabela'), re.M):
        cols = [c.strip() for c in m.group(0).strip('|').split('|')]
        linhas.append({
            'n': int(cols[0]),
            'milestone': cols[2] if cols[2] in ('Pilot', 'v1.0') else None,
            'rotulos': re.findall(r'`([a-z][a-z0-9-]*)`', cols[3]),
        })
    return linhas


def novas(doc):
    out = []
    sec = secao(doc, 'Issues novas')
    for m in re.finditer(r'^### (N\d+) — (.+?)\nMilestone: (.+?)\nRótulos: (.*?)\n<!-- corpo -->\n(.*?)<!-- /corpo -->',
                         sec, re.M | re.S):
        out.append({'id': m.group(1), 'titulo': m.group(2).strip(), 'milestone': m.group(3).strip(),
                    'rotulos': re.findall(r'`([a-z][a-z0-9-]*)`', m.group(4)), 'corpo': m.group(5).strip() + '\n'})
    return out


def reescritas(doc):
    out = []
    sec = secao(doc, 'Reescritas de escopo')
    for m in re.finditer(r'^### #(\d+) — .*?\nTítulo novo: (.*?)\n<!-- bloco -->\n?(.*?)<!-- /bloco -->\n'
                         r'<!-- comentario -->\n(.*?)<!-- /comentario -->', sec, re.M | re.S):
        titulo = m.group(2).strip()
        out.append({'n': int(m.group(1)), 'titulo': None if titulo == '—' else titulo,
                    'bloco': m.group(3).strip(), 'comentario': m.group(4).strip() + '\n'})
    return out


def estado_issue(n):
    d = json.loads(sh('gh', 'issue', 'view', str(n), '-R', REPO, '--json', 'title,body,labels,milestone,comments'))
    return {
        'titulo': d['title'], 'corpo': d['body'] or '',
        'rotulos': {l['name'] for l in d['labels']},
        'milestone': (d['milestone'] or {}).get('title'),
        'tem_marcador': any(MARCADOR in (c.get('body') or '') for c in d['comments']),
    }


def q(x):
    return shlex.quote(str(x))


def lote_rotulos(doc):
    existentes = set(sh('gh', 'label', 'list', '-R', REPO, '--limit', '500', '--json', 'name', '-q', '.[].name').split('\n'))
    for nome, (cor, desc) in ROTULOS.items():
        if nome not in existentes:
            print(f'gh label create {q(nome)} -R {REPO} --color {cor} --description {q(desc)}')


def lote_milestones(doc):
    existentes = set(sh('gh', 'api', f'repos/{REPO}/milestones?state=all', '-q', '.[].title').split('\n'))
    for nome, desc in MILESTONES.items():
        if nome not in existentes:
            print(f'gh api -X POST repos/{REPO}/milestones -f title={q(nome)} -f description={q(desc)}')


def lote_existentes(doc):
    for l in tabela(doc):
        e = estado_issue(l['n'])
        args = []
        if l['milestone'] and e['milestone'] != l['milestone']:
            args += ['--milestone', q(l['milestone'])]
        for r in l['rotulos']:
            if r not in e['rotulos']:
                args += ['--add-label', q(r)]
        if args:
            print(f'gh issue edit {l["n"]} -R {REPO} ' + ' '.join(args))


def lote_reescritas(doc, script):
    inv = inventario()
    for r in reescritas(doc):
        e = estado_issue(r['n'])
        if r['bloco'] and not norm(e['corpo']).startswith(norm(BLOCO_INICIO)):
            corpo_novo = r['bloco'] + '\n\n' + (inv[r['n']]['body'] or '')
            arq = tmpfile(f'corpo-{r["n"]}.md', corpo_novo)
            extra = f' --title {q(r["titulo"])}' if r['titulo'] and e['titulo'] != r['titulo'] else ''
            print(f'python3 -I {q(script)} --conferir-corpo {r["n"]} && '
                  f'gh issue edit {r["n"]} -R {REPO} --body-file {q(arq)}{extra}')
        elif r['titulo'] and e['titulo'] != r['titulo']:
            print(f'gh issue edit {r["n"]} -R {REPO} --title {q(r["titulo"])}')
        if not e['tem_marcador']:
            arq = tmpfile(f'comentario-{r["n"]}.md', r['comentario'])
            print(f'gh issue comment {r["n"]} -R {REPO} --body-file {q(arq)}')


def lote_novas(doc):
    titulos = set(json.loads(sh('gh', 'issue', 'list', '-R', REPO, '--state', 'all', '--limit', '1000',
                                '--json', 'title', '-q', '[.[].title]')))
    for n in novas(doc):
        if n['titulo'] in titulos:
            continue
        arq = tmpfile(f'nova-{n["id"]}.md', n['corpo'])
        rot = ''.join(f' --label {q(r)}' for r in n['rotulos'])
        print(f'gh issue create -R {REPO} --title {q(n["titulo"])} --body-file {q(arq)} '
              f'--milestone {q(n["milestone"])}{rot}')


def conferir_corpo(n):
    atual = json.loads(sh('gh', 'issue', 'view', str(n), '-R', REPO, '--json', 'body'))['body']
    if norm(atual) != norm(inventario()[n]['body']):
        print(f'corpo da #{n} mudou depois do inventário: parar e reaprovar a reescrita sobre o corpo atual',
              file=sys.stderr)
        return 1
    return 0


def main(argv):
    if argv[:1] == ['--conferir-corpo']:
        return conferir_corpo(int(argv[1]))
    doc_path = argv[0]
    opts = dict(zip(argv[1::2], argv[2::2]))
    atual = sh('git', 'hash-object', doc_path).strip()
    if opts.get('--hash') != atual:
        print(f'recusado: hash do documento ({atual}) diferente do aprovado ({opts.get("--hash")})', file=sys.stderr)
        return 2
    with open(doc_path, encoding='utf-8') as f:
        doc = f.read()
    lote = opts.get('--lote')
    script = os.path.relpath(__file__)
    if lote == 'rotulos':
        lote_rotulos(doc)
    elif lote == 'milestones':
        lote_milestones(doc)
    elif lote == 'existentes':
        lote_existentes(doc)
    elif lote == 'reescritas':
        lote_reescritas(doc, script)
    elif lote == 'novas':
        lote_novas(doc)
    else:
        print('lote desconhecido', file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
