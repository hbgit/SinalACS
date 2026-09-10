#!/usr/bin/env bash
# Fase Discover da skill ui-demo: nunca gravar sem antes ver o que está na tela.
#
# Percorre manualmente as telas dos dois apps e, a cada parada, despeja a
# hierarquia de UI e uma captura. Do dump saem as coordenadas de toque que os
# scripts de gravação usam — sem isso os `input tap` seriam chute.
#
# Uso:  ./discover.sh <nome-da-tela>
#       ./discover.sh patient-login
#       ./discover.sh acs-dashboard

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[ $# -eq 1 ] || die "uso: $0 <nome-da-tela>"
NAME="$1"
OUT="$VIDEO_DIR/out/discover"
mkdir -p "$OUT"

require_device

info "despejando hierarquia de UI"
"$ADB" shell uiautomator dump /sdcard/window_dump.xml >/dev/null
"$ADB" pull /sdcard/window_dump.xml "$OUT/$NAME.xml" >/dev/null
"$ADB" shell rm -f /sdcard/window_dump.xml

screenshot "$NAME" "$OUT/$NAME.png"

echo
echo "Elementos clicáveis com texto (use o centro do bounds como coordenada de toque):"
python3 - "$OUT/$NAME.xml" <<'PY'
import re, sys, xml.etree.ElementTree as ET

tree = ET.parse(sys.argv[1])
for node in tree.iter('node'):
    text = (node.get('text') or '').strip()
    desc = (node.get('content-desc') or '').strip()
    rid  = (node.get('resource-id') or '').strip()
    cls  = (node.get('class') or '').strip()
    label = text or desc or rid
    # Campos de texto VAZIOS não têm text/desc/resource-id na árvore de
    # semântica do Flutter e sumiriam da lista — justamente os campos que
    # precisamos tocar para preencher.
    if not label and 'EditText' in cls:
        label = f'<{cls.rsplit(".", 1)[-1]} vazio>'
    if not label:
        continue
    m = re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', node.get('bounds') or '')
    if not m:
        continue
    x1, y1, x2, y2 = map(int, m.groups())
    cx, cy = (x1 + x2) // 2, (y1 + y2) // 2
    mark = '*' if node.get('clickable') == 'true' else ' '
    print(f'  {mark} {cx:>5},{cy:<5}  {label[:60]}')
PY

echo
echo "  (* = clicável)  XML e PNG em video/out/discover/$NAME.*"
echo "  Anote as coordenadas em video/capture/coords.env antes de gravar."
