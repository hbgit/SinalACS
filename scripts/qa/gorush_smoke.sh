#!/usr/bin/env bash
# Sobe um Gorush descartável com a chave em $GORUSH_SMOKE_CREDENTIALS (diretório com
# fcm-service-account.json), posta UM push para um token FALSO e grava a resposta
# (status + corpo) em $1. Serve para observar o formato REAL que o GorushClient
# precisa entender. Nunca imprime a chave; o token é falso, então nada é entregue.
set -euo pipefail
out="${1:?uso: gorush_smoke.sh <arquivo-de-saida.json>}"
cred="${GORUSH_SMOKE_CREDENTIALS:?defina GORUSH_SMOKE_CREDENTIALS}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
name="gorush-smoke-$$"
trap 'docker rm -f "$name" >/dev/null 2>&1 || true' EXIT
docker run -d --name "$name" -p 127.0.0.1:18088:8088 \
  -v "$repo_root/infra/docker/gorush/config.yml:/config.yml:ro" \
  -v "$cred:/credentials:ro" appleboy/gorush:1.22.0 -c /config.yml >/dev/null
for _ in $(seq 1 20); do
  curl -fsS -m 2 http://127.0.0.1:18088/healthz >/dev/null 2>&1 && break
  sleep 1
done
curl -fsS -m 2 http://127.0.0.1:18088/healthz >/dev/null || {
  docker logs "$name" 2>&1 | tail -20 >&2
  echo 'erro: o Gorush não ficou saudável' >&2
  exit 1
}
token="$(python3 -c "print('x' * 152)")"
status=$(curl -sS -m 30 -o "/tmp/gorush_body.$$" -w '%{http_code}' -X POST http://127.0.0.1:18088/api/push \
  -H 'Content-Type: application/json' \
  -d "{\"notifications\":[{\"tokens\":[\"$token\"],\"platform\":2,\"title\":\"t\",\"message\":\"m\"}]}")
python3 - "$status" "/tmp/gorush_body.$$" "$out" <<'PYEOF'
import json, sys
status, body_path, out = int(sys.argv[1]), sys.argv[2], sys.argv[3]
raw = open(body_path).read()
try:
    body = json.loads(raw)
except Exception:
    body = raw
json.dump({"status": status, "body": body}, open(out, "w"), indent=2, ensure_ascii=False)
PYEOF
rm -f "/tmp/gorush_body.$$"
