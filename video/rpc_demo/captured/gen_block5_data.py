#!/usr/bin/env python3
"""Converte a saída REAL capturada em video/rpc_demo/captured/*.txt no módulo
TypeScript que o bloco 5 renderiza.

Existe para que a cartela de terminal não possa divergir da execução: se alguém
mudar o texto em tela, tem de mudar a captura, e a captura vem de uma corrida
de verdade contra a stack. Os .txt ficam versionados junto para auditoria.
"""
import json, pathlib

here = pathlib.Path(__file__).parent
cycle = (here / 'cycle.txt').read_text().rstrip('\n').split('\n')
mqtt = (here / 'mqtt.txt').read_text().strip()

topic, _, payload = mqtt.partition(' ')
pretty = json.dumps(json.loads(payload), indent=2, ensure_ascii=False)

out = here.parent.parent / 'remotion' / 'src' / 'block5Data.ts'
out.write_text(
    "// GERADO por video/rpc_demo/captured/gen_block5_data.py — não editar à mão.\n"
    "// Fonte: video/rpc_demo/captured/{cycle,mqtt}.txt, saída de uma execução\n"
    "// real de bin/red_alert_cycle.dart contra a stack do docker compose.\n\n"
    f"export const cycleLines: string[] = {json.dumps(cycle, ensure_ascii=False, indent=2)};\n\n"
    f"export const mqttTopic = {json.dumps(topic, ensure_ascii=False)};\n\n"
    f"export const mqttPayload = {json.dumps(pretty, ensure_ascii=False)};\n"
)
print(f"gerado {out.relative_to(here.parent.parent.parent)} — {len(cycle)} linhas do ciclo")
