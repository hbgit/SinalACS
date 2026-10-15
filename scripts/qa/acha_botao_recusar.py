#!/usr/bin/env python3
"""Lê o XML do `uiautomator dump` na ENTRADA PADRÃO e imprime "x y": o centro do botão
"Não permitir" do diálogo de permissão do sistema (nada, se ele não estiver na tela).

Entrada por stdin, não por argv: um dump grande estoura o limite de um único argumento
(E2BIG), o que matava em silêncio o tocador de scripts/qa/acs_gps_e2e.sh.
"""
import re
import sys

IDS = ("permission_deny_and_dont_ask_again_button", "permission_deny_button")


def achar(xml):
    for rid in IDS:
        m = re.search(
            r'resource-id="com\.android\.permissioncontroller:id/%s"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"' % rid,
            xml,
        )
        if m:
            x1, y1, x2, y2 = map(int, m.groups())
            return (x1 + x2) // 2, (y1 + y2) // 2
    return None


if __name__ == "__main__":
    ponto = achar(sys.stdin.read())
    if ponto:
        print(*ponto)
