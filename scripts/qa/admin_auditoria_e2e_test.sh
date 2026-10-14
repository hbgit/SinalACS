#!/usr/bin/env bash
# Confere que admin_auditoria_e2e.sh escolhe o aparelho por DEVICE, usa o serial
# em todo adb/flutter, semeia a trilha só com o opt-in, conversa com o teste
# pela linha marcadora (adulterar a linha pedida), adultera SÓ no banco de e2e,
# derruba a stack e apaga o manifesto mesmo se falhar no meio e termina nos
# asserts que só o banco e o verificador CLI respondem — e que nem o
# `e2e.sh --full` nem a descoberta do `flutter test` alcançam esta jornada.
# Sem Docker e sem aparelho: lê o texto dos scripts.
set -euo pipefail
cd "$(dirname "$0")/../.."
s=scripts/qa/admin_auditoria_e2e.sh
t=apps/admin/integration_test/admin_auditoria_e2e.dart
seed=backend/sinalacs_server/bin/seed_e2e_fixtures.dart
falhas=0
conferir() { if ! eval "$2"; then echo "FALHOU: $1" >&2; falhas=$((falhas+1)); fi; }

conferir 'o script existe e é bash válido' "[[ -f $s ]] && bash -n $s"
conferir 'DEVICE com padrão emulator-5554' "grep -qF 'dev=\"\${DEVICE:-emulator-5554}\"' $s"
conferir 'emulator-5554 só aparece no padrão' "[[ \$(grep -c 'emulator-5554' $s) -le 2 ]] && [[ \$(grep -v '^#' $s | grep -c 'emulator-5554') -eq 1 ]]"
conferir 'adb reverse do RPC usa \$dev' "grep -qF 'adb -s \"\$dev\" reverse tcp:8443 tcp:443' $s"
conferir 'adb reverse do relé usa \$dev' "grep -qF 'adb -s \"\$dev\" reverse tcp:8765 tcp:8765' $s"
conferir 'flutter test usa -d \$dev' "grep -qF -- '-d \"\$dev\"' $s"
conferir 'roda o e2e da auditoria pelo caminho' "grep -qF 'flutter test integration_test/admin_auditoria_e2e.dart' $s"
conferir 'relé com o manifesto das fixtures' "grep -qF 'E2E_FIXTURES_FILE=\"\$repo_root/.e2e/fixtures.json\" python3 scripts/qa/otp_relay.py' $s"
conferir 'recusa relé antigo na porta 8765' "grep -qF 'porta_ocupada 8765' $s"
conferir 'cleanup derruba a stack de e2e' "awk '/^cleanup\\(\\)/,/^}/' $s | grep -qF './scripts/qa/e2e_stack.sh down'"
conferir 'cleanup apaga o manifesto antes do down' \
  "awk '/^cleanup\\(\\)/,/^}/' $s | grep -nF -e 'rm -f .e2e/fixtures.json' -e 'e2e_stack.sh down' | head -1 | grep -qF 'rm -f .e2e/fixtures.json'"
conferir 'cleanup no trap EXIT' "grep -qF 'trap cleanup EXIT' $s"

# Seed: a trilha é opt-in deste script e de nenhum outro runner.
conferir 'seed da trilha é opt-in só neste script' \
  "grep -qF 'E2E_SEED_AUDIT_TRAIL=1 ./scripts/qa/e2e_stack.sh seed' $s && ! grep -lF 'E2E_SEED_AUDIT_TRAIL=1' scripts/qa/*.sh | grep -v -e admin_auditoria_e2e.sh -e admin_auditoria_e2e_test.sh"
conferir 'o seed só semeia a trilha com o opt-in' "grep -qF \"env['E2E_SEED_AUDIT_TRAIL'] == '1'\" $seed"
conferir 'o seed encadeia com a AuditChain do servidor' "grep -qF 'chain.computeEntryHash(' $seed && grep -qF 'AuditChain.genesisHash' $seed"
conferir 'o seed tem duas linhas com o mesmo timestamp' "grep -qF 'seq == 31 ? anterior!' $seed"
conferir 'o seed tem uma linha escalated:no_ack_timeout' "grep -qF \"'escalated:no_ack_timeout'\" $seed"
conferir 'o seed semeia mais de uma página (50)' "grep -qE '^const _linhasDaTrilha = ([5-9][1-9]|[6-9][0-9]|[1-9][0-9]{2,});' $seed"

# A conversa teste -> script: as linhas marcadoras casam dos dois lados.
for m in E2E_CADEIA_INTEGRA E2E_FILTROS_OK E2E_ADULTERACAO_DETECTADA E2E_EXPORT_FEITO E2E_COORDENADOR_OK E2E_FIM; do
  conferir "o teste imprime $m" "grep -qF \"print('$m\" $t"
  conferir "o script exige $m" "grep -qF '$m' $s"
done
conferir 'o teste pede a adulteração (linha marcadora)' "grep -qF \"print('E2E_ADULTERAR sequence=\" $t"
conferir 'o script atende o pedido de adulteração' "grep -qF \"grep -q 'E2E_ADULTERAR sequence='\" $s"
conferir 'o teste registra o caminho da área de transferência' "grep -qF \"print('E2E_CLIPBOARD caminho=\" $t && grep -qF 'E2E_CLIPBOARD caminho=' $s"
conferir 'o teste lê de volta a área de transferência' "grep -qF 'Clipboard.getData(' $t && grep -qF 'sha256.convert(' $t"
conferir 'o teste confere as nove colunas' \
  "grep -qF \"'sequence,timestamp_utc,autor,papel_autor,acao,recurso,rotulo_recurso,resultado,selo'\" $t"
conferir 'o teste espera o cache de 60 s da verificação' "grep -qF '_cacheDaVerificacao' $t"
conferir 'o coordenador tenta exportar por RPC e é recusado' \
  "grep -qF 'client.admin.exportAuditLogs(' $t && grep -qF 'AlertPermissionException' $t"
conferir 'o teste recebe as contagens por dart-define' \
  "for d in E2E_AUDIT_ROWS E2E_AUDIT_EXPORT_ROWS E2E_AUDIT_ACS_ROWS E2E_AUDIT_PERIOD_ROWS E2E_AUDIT_PERIOD_FIRST E2E_AUDIT_PERIOD_LAST E2E_AUDIT_TAMPER_SEQUENCE; do grep -qF -- \"--dart-define=\$d=\" $s && grep -qF \"'\$d'\" $t || exit 1; done"

# Adulteração: só no banco de e2e, sempre pelo e2e_stack.sh (container
# sinalacs-postgres-test, banco sinalacs_e2e) — nunca no Postgres de dev.
conferir 'o sql do script passa pelo e2e_stack.sh' "grep -qF 'sql() { ./scripts/qa/e2e_stack.sh psql \"\$1\"; }' $s"
conferir 'nenhum docker compose/exec no postgres de dev' "! grep -q 'docker compose.*sinalacs-postgres[^-]' $s && ! grep -q 'docker exec.*sinalacs-postgres[^-]' $s && ! grep -q 'sinalacs-postgres\\b[^-]' $s"
conferir 'o e2e_stack.sh fala com o sinalacs_e2e no postgres-test' \
  "grep -qF 'db=sinalacs_e2e' scripts/qa/e2e_stack.sh && grep -qF 'docker exec -e PGPASSWORD sinalacs-postgres-test psql' scripts/qa/e2e_stack.sh"
p_adulterar='update audit_logs set result = '"'"'x'"'"' where sequence = $n'
conferir 'a adulteração é um UPDATE da linha pedida' 'grep -qF "$p_adulterar" $s'
conferir 'a adulteração confere a sequence pedida contra o manifesto' "grep -qF '[[ \"\$n\" == \"\$alvo\" ]]' $s"

# Os asserts finais: o que o teste no aparelho não alcança.
conferir 'assert da linha export/success ligada a audit_exports' \
  "grep -qF 'uma linha export/success gravada no teste' $s && grep -qF 'left join audit_exports e on e.id = l.\\\"resourceId\\\"' $s"
conferir 'assert da recusa export/denied do coordenador' "grep -qF \"'admin_audit_export' and result = 'denied'\" $s"
conferir 'assert do filtersJson só com chaves de filtro' "grep -qF 'filtersJson só com chaves de filtro' $s"
conferir 'CLI deve falhar (exit 1) com a cadeia adulterada' "grep -qF '[[ \"\$codigo\" == 1 ]]' $s"
p_restaurar='update audit_logs set result = '"'"'$original'"'"' where sequence = $alvo'
p_passa='[[ "$codigo" == 0 ]]'
conferir 'CLI deve passar (exit 0) depois de restaurar' \
  'grep -qF "$p_restaurar" $s && [[ $(grep -cF "$p_passa" $s) -ge 2 ]]'
conferir 'o verificador é o bin/audit_chain_check.dart contra o sinalacs_e2e' \
  "grep -qF 'dart run bin/audit_chain_check.dart' $s && grep -qF 'SERVERPOD_DATABASE_NAME=sinalacs_e2e' $s"

# Descoberta: `flutter test integration_test` só pega `*_test.dart`, e o
# `e2e.sh --full` roda só o smoke hermético do admin.
conferir 'o arquivo do e2e existe e não é descoberto (sufixo _e2e.dart)' "[[ -f $t ]] && [[ $t != *_test.dart ]]"
conferir 'e2e.sh --full não roda o e2e da auditoria' "! grep -q 'flutter test integration_test/admin_auditoria_e2e' scripts/qa/e2e.sh"
conferir 'e2e.sh aponta para este script' "grep -qF 'scripts/qa/admin_auditoria_e2e.sh' scripts/qa/e2e.sh"

[[ $falhas -eq 0 ]] && echo ok || exit 1
