#!/usr/bin/env bash
# Confere que admin_login_e2e.sh escolhe o aparelho por DEVICE e usa o serial em
# todo adb/flutter. Sem Docker, sem aparelho: lê o texto do script.
set -euo pipefail
cd "$(dirname "$0")/../.."
s=scripts/qa/admin_login_e2e.sh
falhas=0
conferir() { if ! eval "$2"; then echo "FALHOU: $1" >&2; falhas=$((falhas+1)); fi; }

conferir 'DEVICE com padrão emulator-5554' "grep -qF 'dev=\"\${DEVICE:-emulator-5554}\"' $s"
conferir 'emulator-5554 só aparece no padrão' "[[ \$(grep -c 'emulator-5554' $s) -le 1 ]]"
conferir 'adb reverse usa \$dev' "grep -qF 'adb -s \"\$dev\" reverse tcp:8443 tcp:443' $s"
conferir 'flutter test usa -d \$dev' "grep -qF -- '-d \"\$dev\"' $s"
[[ $falhas -eq 0 ]] && echo ok || exit 1
