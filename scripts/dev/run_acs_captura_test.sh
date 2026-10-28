#!/usr/bin/env bash
#
# `run_acs.sh --captura` só acrescenta a propriedade do Gradle ao build de debug;
# e, desde a #94, o wrapper não exige nem repassa senha do broker (o aparelho se
# autentica pelo próprio certificado).
# Hermético: copia o script para uma árvore temporária (o `repo_root` dele vem do
# próprio caminho), com `.env`, `apps/acs` e um `flutter` falso que só grava os
# argumentos. Não precisa de Docker, de emulador nem de SDK.
set -euo pipefail
aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
falha() { echo "FALHOU: $*" >&2; exit 1; }

mkdir -p "$tmp/scripts/dev" "$tmp/apps/acs" "$tmp/bin"
cp "$aqui/run_acs.sh" "$tmp/scripts/dev/run_acs.sh"
# .env sem MQTT_ACS_PASSWORD: um .env gerado depois da #94 não tem a variável.
echo 'GOOGLE_MAPS_API_KEY=' >"$tmp/.env"
# O flutter falso guarda os argumentos e uma cópia do arquivo de --dart-define
# (o wrapper o apaga no trap, assim que o flutter volta).
cat >"$tmp/bin/flutter" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" >"$tmp/args"
for a in "\$@"; do
  case "\$a" in --dart-define-from-file=*) cp "\${a#--dart-define-from-file=}" "$tmp/defines" ;; esac
done
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

echo "== sem senha do broker: só host e broker vão no --dart-define =="
grep -q '"SINALACS_HOST"' "$tmp/defines" || falha "SINALACS_HOST não foi: $(cat "$tmp/defines")"
grep -q '"SINALACS_MQTT_HOST"' "$tmp/defines" || falha "SINALACS_MQTT_HOST não foi: $(cat "$tmp/defines")"
grep -q 'SINALACS_MQTT_USER\|SINALACS_MQTT_PASSWORD' "$tmp/defines" && falha "o wrapper ainda repassa usuário/senha do broker: $(cat "$tmp/defines")"
grep -qi 'senha' "$tmp/saida" && falha "o wrapper ainda fala em senha do broker: $(cat "$tmp/saida")"

echo "OK — run_acs.sh --captura só acrescenta a propriedade quando pedido; sem senha do broker"
