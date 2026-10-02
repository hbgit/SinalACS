#!/usr/bin/env python3
"""Confere a linha "**Contagem:**" de spec/validation_report.md contra a tabela de RF.

A linha foi escrita à mão e ficou para trás quando RF13 mudou de status; este
conferidor recalcula a partir das linhas `| RFnn | ... | **status** | ... |`.
Status fora da lista conhecida é erro (exit 2), não linha ignorada: ignorar
deixaria a contagem errada de novo, em silêncio. Linha de RF sem o status em
negrito também é erro (exit 2): ela sairia da contagem sem ninguém perceber.
"""
import pathlib
import re
import sys

ORDEM = ["backend", "backend + app", "app-only", "parcial", "ausente"]
LINHA_RF = re.compile(r"^\| RF\d+ \|[^|]*\| \*\*([^*]+)\*\* \|", re.M)
LINHA_QUALQUER_RF = re.compile(r"^\| RF\d+ \|.*$", re.M)
LINHA_CONTAGEM = re.compile(r"^\*\*Contagem:\*\* (.+)\.$", re.M)


def contar(texto):
    contagem = {chave: 0 for chave in ORDEM}
    for linha in LINHA_QUALQUER_RF.findall(texto):
        achado = LINHA_RF.match(linha)
        if achado is None:
            raise ValueError(f"linha de RF sem status em negrito: {linha[:60]!r}")
        status = achado.group(1)
        if status not in contagem:
            raise ValueError(f"status desconhecido na tabela de RF: {status!r}")
        contagem[status] += 1
    return contagem


def esperada(contagem):
    return " · ".join(f"{contagem[chave]} `{chave}`" for chave in ORDEM if contagem[chave])


def conferir(texto):
    declarada = LINHA_CONTAGEM.search(texto)
    if declarada is None:
        raise ValueError("sem linha '**Contagem:**'")
    return declarada.group(1), esperada(contar(texto))


if __name__ == "__main__":
    caminho = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "spec/validation_report.md")
    try:
        declarada_, esperada_ = conferir(caminho.read_text(encoding="utf-8"))
    except ValueError as erro:
        print(f"erro: {erro}", file=sys.stderr)
        sys.exit(2)
    if declarada_ != esperada_:
        print(
            f"erro: contagem desatualizada em {caminho}\n  declarada: {declarada_}\n  da tabela: {esperada_}",
            file=sys.stderr,
        )
        sys.exit(1)
    print("ok: contagem do validation_report confere")
