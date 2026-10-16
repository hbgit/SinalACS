#!/usr/bin/env python3
"""Confere o relatório de lacunas do PRD contra os IDs de spec/PRD_system.md.

Todo ID que aparece na primeira célula de uma tabela do PRD (RFnn, RNFnn,
INV-nn, LGPD-RFnn, Mn.n, Hn, Rn) precisa de exatamente uma linha no
relatório. ID citado em prosa não conta: "não confundir com LGPD-RF19" não
cria requisito. Linha malformada (coluna a mais ou a menos, status sem
negrito ou fora da lista, ID duplicado) é exit 2, não linha ignorada:
ignorar tiraria o requisito da conta sem ninguém perceber.

Com --final, a-verificar é erro, entregue/parcial exigem evidência e
parcial/ausente/externo exigem "o que falta".
"""
import pathlib
import re
import sys

RELATORIO = "docs/auditoria-prd/2026-10-15-lacunas-prd.md"
STATUS = ["entregue", "parcial", "ausente", "fora-do-mvp", "externo", "a-verificar"]
ID = r"(?:RF\d{2}|RNF\d{2}|INV-\d{2}|LGPD-RF\d{2}|M\d\.\d|H\d|R\d)"
ID_NO_PRD = re.compile(rf"^\| \*{{0,2}}({ID})\b", re.M)
LINHA_RELATORIO = re.compile(rf"^\| ({ID}) \|(.*)$", re.M)
STATUS_NEGRITO = re.compile(r"\*\*([^*]+)\*\*")


class Malformado(Exception):
    pass


def ids_do_prd(texto):
    return set(ID_NO_PRD.findall(texto))


def linhas_do_relatorio(texto):
    linhas = {}
    for m in LINHA_RELATORIO.finditer(texto):
        ident = m.group(1)
        corpo = m.group(2).rstrip()
        if not corpo.endswith("|"):
            raise Malformado(f"{ident}: linha não termina em '|'")
        celulas = [c.strip() for c in corpo[:-1].split("|")]
        if len(celulas) != 4:
            raise Malformado(f"{ident}: esperava 5 colunas, achei {len(celulas) + 1}")
        _, status, evidencia, falta = celulas
        negrito = STATUS_NEGRITO.fullmatch(status)
        if not negrito:
            raise Malformado(f"{ident}: status sem negrito: {status!r}")
        if negrito.group(1) not in STATUS:
            raise Malformado(f"{ident}: status desconhecido: {negrito.group(1)!r}")
        if ident in linhas:
            raise Malformado(f"{ident}: linha duplicada")
        linhas[ident] = (negrito.group(1), evidencia, falta)
    return linhas


def conferir(prd, relatorio, final=False):
    ids = ids_do_prd(prd)
    linhas = linhas_do_relatorio(relatorio)
    erros = [f"{i}: está no PRD e falta no relatório" for i in sorted(ids - linhas.keys())]
    erros += [f"{i}: está no relatório e não existe no PRD" for i in sorted(linhas.keys() - ids)]
    if final:
        for ident, (status, evidencia, falta) in sorted(linhas.items()):
            if status == "a-verificar":
                erros.append(f"{ident}: ainda a-verificar")
            if status in ("entregue", "parcial") and not evidencia:
                erros.append(f"{ident}: {status} sem evidência")
            if status in ("parcial", "ausente", "externo") and not falta:
                erros.append(f"{ident}: {status} sem o que falta")
    return erros


def main(argv):
    final = "--final" in argv
    if [a for a in argv if a != "--final"]:
        print("uso: cobertura_prd.py [--final]", file=sys.stderr)
        return 2
    raiz = pathlib.Path(__file__).resolve().parents[2]
    prd = (raiz / "spec/PRD_system.md").read_text(encoding="utf-8")
    relatorio = (raiz / RELATORIO).read_text(encoding="utf-8")
    try:
        erros = conferir(prd, relatorio, final)
    except Malformado as erro:
        print(f"relatório malformado: {erro}", file=sys.stderr)
        return 2
    for erro in erros:
        print(erro, file=sys.stderr)
    if erros:
        return 1
    print(f"cobertura do PRD: {len(ids_do_prd(prd))} IDs, ok")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
