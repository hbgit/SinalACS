#!/usr/bin/env bash
# Teste hermético de scripts/qa/lib_rele.sh (porta_ocupada) e de que os três
# runners do relé a usam. Não precisa de emulador nem de Docker.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
# shellcheck disable=SC1091
source scripts/qa/lib_rele.sh
falhas=0
confere() { "$@" || { echo "FALHOU: $*"; falhas=$((falhas + 1)); }; }
nega() { if "$@"; then echo "FALHOU (esperava falso): $*"; falhas=$((falhas + 1)); fi; }

porta="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')"
nega porta_ocupada "$porta"

for endereco in 127.0.0.1 0.0.0.0 ::; do
  python3 -c '
import socket, sys, time
familia = socket.AF_INET6 if ":" in sys.argv[1] else socket.AF_INET
s = socket.socket(familia)
s.bind((sys.argv[1], int(sys.argv[2])))
s.listen()
time.sleep(30)' "$endereco" "$porta" 2>/dev/null &
  pid=$!
  for _ in $(seq 1 20); do porta_ocupada "$porta" && break; sleep 0.1; done
  if kill -0 "$pid" 2>/dev/null; then
    confere porta_ocupada "$porta"
  else
    echo "pulado: este host não consegue escutar em $endereco"
  fi
  kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
  for _ in $(seq 1 20); do porta_ocupada "$porta" || break; sleep 0.1; done
done

for f in acs_full_e2e.sh patient_full_e2e.sh push_e2e.sh; do
  nega grep -qF "grep -q '127.0.0.1:8765 '" "scripts/qa/$f"
  confere grep -q "porta_ocupada 8765" "scripts/qa/$f"
done

# `iniciar_rele` (onde existe) não pode chamar a si mesma e precisa ser chamada de fora:
# no push_e2e.sh ela era recursiva e nunca rodava, então a checagem de porta nunca valia.
for f in push_e2e.sh patient_full_e2e.sh; do
  arq="scripts/qa/$f"
  corpo="$(awk '/^[[:space:]]*iniciar_rele\(\) \{/{d=1;next} d&&/^[[:space:]]*\}/{d=0} d' "$arq")"
  chamada='^[[:space:]]*iniciar_rele[[:space:]]*$'
  nega grep -qE "$chamada" <<<"$corpo"
  total="$(grep -cE "$chamada" "$arq" || true)"; dentro="$(grep -cE "$chamada" <<<"$corpo" || true)"
  confere test $((total - dentro)) -ge 1
done

[[ "$falhas" -eq 0 ]] && echo "ok: lib_rele" || { echo "$falhas falha(s)"; exit 1; }
