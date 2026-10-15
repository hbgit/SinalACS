#!/usr/bin/env bash
# Confere que admin_titular_e2e.sh escolhe o aparelho por DEVICE, usa o serial em
# todo adb/flutter, semeia só com o opt-in e confere os efeitos no banco. Sem Docker,
# sem aparelho: lê o texto do script.
set -euo pipefail
cd "$(dirname "$0")/../.."
s=scripts/qa/admin_titular_e2e.sh
falhas=0
conferir() { if ! eval "$2"; then echo "FALHOU: $1" >&2; falhas=$((falhas+1)); fi; }

conferir 'DEVICE com padrão emulator-5554' "grep -qF 'dev=\"\${DEVICE:-emulator-5554}\"' $s"
conferir 'emulator-5554 só aparece no padrão' "[[ \$(grep -c 'emulator-5554' $s) -le 1 ]]"
conferir 'adb reverse usa \$dev' "grep -qF 'adb -s \"\$dev\" reverse tcp:8443 tcp:443' $s"
conferir 'flutter test usa -d \$dev' "grep -qF -- '-d \"\$dev\"' $s"
conferir 'seed dos pedidos é opt-in só neste script' "grep -qF 'E2E_SEED_DATA_REQUESTS=1' $s && ! grep -rqF 'E2E_SEED_DATA_REQUESTS=1' scripts/qa/admin_login_e2e.sh scripts/qa/patient_full_e2e.sh"
conferir 'manifesto apagado na limpeza' "grep -qF 'rm -f .e2e/fixtures.json' $s"
conferir 'confere a cadeia de auditoria' "grep -qF 'audit_chain_check.dart' $s"
conferir 'confere que o texto do titular não está nos logs' "grep -qF 'E2E-NOTA' $s"
conferir 'e2e.sh aponta para este script' "grep -qF 'scripts/qa/admin_titular_e2e.sh' scripts/qa/e2e.sh"

[[ $falhas -eq 0 ]] && echo ok || exit 1
