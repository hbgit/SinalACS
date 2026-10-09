#!/usr/bin/env bash
# Confere que admin_acs_gestao_e2e.sh escolhe o aparelho por DEVICE, usa o serial
# em todo adb/flutter, roda o teste certo com o manifesto do relé e termina nos
# asserts que só o banco responde — e que nem o `e2e.sh --full` nem a descoberta
# do `flutter test` alcançam esta jornada (ela troca a stack de dev pela de e2e).
# Sem Docker e sem aparelho: lê o texto dos scripts.
set -euo pipefail
cd "$(dirname "$0")/../.."
s=scripts/qa/admin_acs_gestao_e2e.sh
t=apps/admin/integration_test/admin_acs_gestao_e2e.dart
falhas=0
conferir() { if ! eval "$2"; then echo "FALHOU: $1" >&2; falhas=$((falhas+1)); fi; }

conferir 'DEVICE com padrão emulator-5554' "grep -qF 'dev=\"\${DEVICE:-emulator-5554}\"' $s"
conferir 'emulator-5554 só aparece no padrão' "[[ \$(grep -c 'emulator-5554' $s) -le 1 ]]"
conferir 'adb reverse do RPC usa \$dev' "grep -qF 'adb -s \"\$dev\" reverse tcp:8443 tcp:443' $s"
conferir 'adb reverse do relé usa \$dev' "grep -qF 'adb -s \"\$dev\" reverse tcp:8765 tcp:8765' $s"
conferir 'flutter test usa -d \$dev' "grep -qF -- '-d \"\$dev\"' $s"
conferir 'roda o e2e da gestão pelo caminho' "grep -qF 'flutter test integration_test/admin_acs_gestao_e2e.dart' $s"
conferir 'relé com o manifesto das fixtures' "grep -qF 'E2E_FIXTURES_FILE=\"\$repo_root/.e2e/fixtures.json\" python3 scripts/qa/otp_relay.py' $s"
conferir 'cleanup derruba a stack de e2e' "grep -qF './scripts/qa/e2e_stack.sh down' $s"
conferir 'o manifesto sai antes do down' "grep -qF 'rm -f .e2e/fixtures.json' $s"
# O bloco novo do manifesto tem senha e código de ativação: os runners que
# compilam o manifesto no APK (`--dart-define`, visível em `ps`) têm de tirá-lo
# como já tiram `acs`/`acsB`/`staff` — senão a credencial do coordenador viaja
# junto com o app dos testes de paciente/ACS.
conferir 'os runners tiram o bloco do coordenador do dart-define' \
  "for f in scripts/qa/acs_full_e2e.sh scripts/qa/patient_full_e2e.sh scripts/qa/push_e2e.sh; do grep -qF \"d.pop('coordinator',None)\" \$f || exit 1; done"

# Os asserts finais: o que o teste no aparelho não alcança (banco de teste).
conferir 'assert do ACS desativado ao fim' "grep -qF 'select active::text from acs where' $s"
conferir 'assert dos refresh tokens revogados' "grep -qF 'from acs_refresh_tokens t join users u' $s"
conferir 'assert da MFA redefinida (colunas totp*)' "grep -qF 'from user_credentials uc join users u' $s && grep -qF 'totpEnabledAt' $s && grep -qF 'totpSecretEncrypted' $s"
conferir 'assert do código de ativação emitido' "grep -qF 'activationCodeHash' $s && grep -qF 'from staff_accounts where' $s"
conferir 'assert da auditoria das escritas' "grep -qF \"('admin_acs','admin_staff')\" $s && grep -qF \"'mfa_reset'\" $s"
# A linha marcadora é a única ponte aparelho → host para o nome e a matrícula
# que os asserts usam: sem ela (ou sem o parse) o script não tem o que consultar.
conferir 'o teste imprime a linha marcadora' "grep -qF 'E2E_ACS_CRIADO matricula=' $t"
conferir 'o script lê a linha marcadora' "grep -qF \"grep -o 'E2E_ACS_CRIADO .*'\" $s"

# Descoberta: `flutter test integration_test` só pega `*_test.dart`, e o
# `e2e.sh --full` roda a bateria inteira do admin (o smoke hermético, sobre o
# mock). O arquivo desta jornada tem de continuar fora dos dois: ela troca a
# stack de desenvolvimento pela de e2e e precisa de fixtures e relé.
conferir 'o arquivo do e2e existe e não é descoberto (sufixo _e2e.dart)' "[[ -f $t ]] && [[ $t != *_test.dart ]]"
conferir 'e2e.sh --full não aponta para o e2e da gestão' "! grep -q 'admin_acs_gestao_e2e' scripts/qa/e2e.sh"
conferir 'e2e.sh --full roda só o smoke do admin' "grep -qF 'flutter test integration_test/admin_mobile_smoke_test.dart -d emulator-5554' scripts/qa/e2e.sh"

[[ $falhas -eq 0 ]] && echo ok || exit 1
