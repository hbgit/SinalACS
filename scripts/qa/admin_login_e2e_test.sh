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
# #41: o painel já lê do backend real; o cabeçalho não pode dizer o contrário, e
# o e2e.sh --full roda do admin só o smoke hermético (o fluxo com backend real
# troca a stack e fica neste script).
conferir 'cabeçalho não diz que o painel segue no mock' "! grep -q 'seguem no MockAdminDataSource' $s"
conferir 'e2e.sh --full roda só o smoke do admin' "grep -qF 'flutter test integration_test/admin_mobile_smoke_test.dart -d emulator-5554' scripts/qa/e2e.sh"
conferir 'e2e.sh aponta para o e2e do admin com backend real' "grep -qF 'scripts/qa/admin_login_e2e.sh' scripts/qa/e2e.sh"

[[ $falhas -eq 0 ]] && echo ok || exit 1
