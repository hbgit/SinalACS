#!/usr/bin/env bash
#
# `run_acs.sh --captura` só acrescenta a propriedade do Gradle ao build de debug.
# Hermético: copia o script para uma árvore temporária (o `repo_root` dele vem do
# próprio caminho), com `.env`, `apps/acs` e um `flutter` falso que só grava os
# argumentos. Não precisa de Docker, de emulador nem de SDK.
set -euo pipefail
aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
falha() { echo "FALHOU: $*" >&2; exit 1; }

mkdir -p "$tmp/scripts/dev" "$tmp/apps/acs" "$tmp/bin"
cp "$aqui/run_acs.sh" "$tmp/scripts/dev/run_acs.sh"
echo 'MQTT_ACS_PASSWORD=senha-sintetica-de-teste' >"$tmp/.env"
cat >"$tmp/bin/flutter" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" >"$tmp/args"
EOF
chmod +x "$tmp/bin/flutter" "$tmp/scripts/dev/run_acs.sh"

roda() { (cd "$tmp" && PATH="$tmp/bin:$PATH" ./scripts/dev/run_acs.sh --build --skip-ca "$@" >"$tmp/saida" 2>&1) || falha "o wrapper falhou: $(cat "$tmp/saida")"; }

echo "== com --captura: a propriedade chega ao flutter e há aviso =="
rm -f "$tmp/args"; roda --captura
grep -qx -- '-Psinalacs.allowScreenCapture=true' "$tmp/args" || falha "a propriedade não chegou ao flutter: $(cat "$tmp/args")"
grep -qx -- '--captura' "$tmp/args" && falha "a flag --captura vazou para o flutter"
grep -q 'captura de tela' "$tmp/saida" || falha "faltou o aviso de que o APK é só para demonstração"

echo "== sem --captura: a propriedade NÃO vai =="
rm -f "$tmp/args"; roda
grep -q 'allowScreenCapture' "$tmp/args" && falha "sem --captura a propriedade não pode ir"

echo "OK — run_acs.sh --captura só acrescenta a propriedade quando pedido"
