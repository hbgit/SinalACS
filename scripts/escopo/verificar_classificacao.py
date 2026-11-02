"""Verifica docs/escopo/classificacao-issues.md antes da aprovação da tabela.

Uso:
  python3 -I scripts/escopo/verificar_classificacao.py <documento> <inventario.json> <rotulos.txt>

Imprime uma linha por regra (nome e lista de casos) e sai com código 1 se
alguma lista não for vazia. Não acessa a rede nem altera nada.
"""

import json
import re
import sys

PORTAO = ['C-01', 'C-02', 'C-03', 'C-04', 'C-05', 'C-06', 'C-08', 'C-10', 'C-11', 'C-12']
NOVOS_ROTULOS = {'futuro', 'a-decidir', 'acao-equipe'}
MARCADOR = '<!-- escopo-2026-11-02 -->'
LINK = 'https://github.com/hbgit/SinalACS/blob/develop/'
REQUISITOS = 'spec/requisitos_piloto.md'


def secao(doc, titulo):
    # Corpos de issue têm cabeçalhos "## " próprios; não podem fechar a seção.
    doc = re.sub(r'<!-- corpo -->.*?<!-- /corpo -->', '', doc, flags=re.S)
    m = re.search(r'^## ' + re.escape(titulo) + r'\n(.*?)(?=^## |\Z)', doc, re.M | re.S)
    return m.group(1) if m else ''


def main(doc_path, inv_path, rotulos_path):
    doc = open(doc_path, encoding='utf-8').read()
    inv = {i['number'] for i in json.load(open(inv_path, encoding='utf-8'))}
    existentes = set(open(rotulos_path, encoding='utf-8').read().split('\n')) - {''}
    falhas = {}

    tabela = secao(doc, 'Tabela')
    linhas = {int(m.group(1)): m.group(0) for m in re.finditer(r'^\| (\d+) \|.*$', tabela, re.M)}
    falhas['faltam'] = sorted(inv - set(linhas))
    falhas['sobram'] = sorted(set(linhas) - inv)

    sem_destino = []
    rotulos_usados = set()
    for n, linha in linhas.items():
        cols = [c.strip() for c in linha.strip('|').split('|')]
        milestone, rotulos = cols[2], cols[3]
        usados = set(re.findall(r'`([a-z][a-z0-9-]*)`', rotulos))
        rotulos_usados |= usados
        if milestone not in ('Pilot', 'v1.0') and not usados & {'futuro', 'a-decidir'}:
            sem_destino.append(n)
    falhas['sem destino'] = sem_destino

    novas = secao(doc, 'Issues novas')
    ids_novos = re.findall(r'^### N\d+ — \[(C-\d\d)\]', novas, re.M)
    falhas['portão sem issue'] = [c for c in PORTAO if c not in ids_novos]
    for linha in re.findall(r'^Rótulos:(.*)$', novas, re.M):
        rotulos_usados |= set(re.findall(r'`([a-z][a-z0-9-]*)`', linha))

    corpos = re.findall(r'<!-- corpo -->(.*?)<!-- /corpo -->', doc, re.S)
    falhas['corpos sem link'] = [i for i, c in enumerate(corpos, 1) if LINK not in c]
    falhas['corpos com N<k>'] = [i for i, c in enumerate(corpos, 1) if re.search(r'\bN\d+\b', c)]

    coms = re.findall(r'<!-- comentario -->\n?(.*?)<!-- /comentario -->', doc, re.S)
    falhas['comentarios sem marcador'] = [
        i for i, c in enumerate(coms, 1) if c.lstrip().split('\n', 1)[0].strip() != MARCADOR]

    falhas['rotulos inexistentes'] = sorted(rotulos_usados - existentes - NOVOS_ROTULOS)

    req = open(REQUISITOS, encoding='utf-8').read()
    essenciais = set(re.findall(r'^\| \*{0,2}(R(?:N)?F\d\d)\*{0,2} \|[^\n]*\| Essencial', req, re.M))
    cob = secao(doc, 'Cobertura dos Essenciais')
    cobertura = {}
    for m in re.finditer(r'^\| (R(?:N)?F\d\d) \|([^|]*)\| (implementado|issue|lacuna) \|([^|]*)\|', cob, re.M):
        cobertura[m.group(1)] = (m.group(3), m.group(4).strip())
    falhas['essenciais sem situação'] = sorted(essenciais - set(cobertura))

    vazia = []
    for rid, (situacao, ev) in cobertura.items():
        if not ev or ev == '—':
            vazia.append(rid)
        elif situacao == 'implementado' and not (
                re.search(r'[\w./-]+\.(dart|sh|md|yaml|sql)', ev) or re.search(r'#\d+', ev)
                or re.search(r'`(README\.md|LICENSE)`', ev)):
            vazia.append(rid)
        elif situacao == 'issue' and not re.search(r'#\d+', ev):
            vazia.append(rid)
        elif situacao == 'lacuna' and not re.search(r'N\d+', ev):
            vazia.append(rid)
    falhas['evidencia vazia'] = sorted(vazia)

    ruim = False
    for nome, casos in falhas.items():
        print(nome, casos)
        ruim = ruim or bool(casos)
    return 1 if ruim else 0


if __name__ == '__main__':
    sys.exit(main(*sys.argv[1:4]))
