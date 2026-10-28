#!/usr/bin/env bash
# Confere que acs_ack_concluido_e2e.sh (#86) monta o aparelho B como a #80
# (broker fora do alcance, alerta por SQL sem outbox), conclui o alerta no
# banco a pedido do teste, apaga o manifesto antes do down e termina nos
# asserts que só o banco responde — e que a descoberta do `flutter test` não
# alcança o teste (sufixo `_e2e`). Sem Docker e sem aparelho: lê o texto.
set -euo pipefail
cd "$(dirname "$0")/../.."
s=scripts/qa/acs_ack_concluido_e2e.sh
t=apps/acs/integration_test/ack_after_resolved_e2e.dart
falhas=0
conferir() { if ! eval "$2"; then echo "FALHOU: $1" >&2; falhas=$((falhas+1)); fi; }

conferir 'o script existe e é bash válido' "[[ -f $s ]] && bash -n $s"
conferir 'o teste tem sufixo _e2e (fora da descoberta)' "[[ -f $t ]]"
conferir 'o script roda esse teste' "grep -qF 'integration_test/ack_after_resolved_e2e.dart' $s"
conferir 'DEVICE com padrão emulator-5554' "grep -qF 'dev=\"\${DEVICE:-emulator-5554}\"' $s"
conferir 'remove o reverse do broker' "grep -qF 'reverse --remove tcp:8883' $s"
conferir 'nunca abre o reverse do broker' "! grep -qE 'reverse tcp:8883' $s"
conferir 'o insert não toca no outbox' "! grep -qiE 'insert into alert_outbox' $s"
conferir 'o aparelho A conclui no banco' "grep -qF \"update alerts set status = 'resolved'\" $s"
conferir 'o manifesto sai antes do down' \
  "awk '/^cleanup\\(\\)/,/^}/' $s | grep -n -e 'rm -f .e2e/fixtures.json' -e 'e2e_stack.sh down' | head -1 | grep -qF 'fixtures.json'"
conferir 'recusa relé antigo na porta 8765' "grep -qF 'porta_ocupada 8765' $s"
for marca in E2E_DISPARAR_ALERTA E2E_CONCLUIR_NO_APARELHO_A; do
  conferir "o teste pede $marca" "grep -qF \"print('$marca \" $t"
  conferir "o script atende $marca" "grep -qF '$marca id=' $s"
done
for marca in E2E_ACK_CONCLUIDO_OK E2E_SEGUE_CONCLUIDO_OK; do
  conferir "o teste imprime $marca" "grep -qF \"print('$marca\" $t"
  conferir "o script exige $marca" "grep -qF '$marca' $s"
done
conferir 'assert: alerta segue resolved' "grep -qF 'select status from alerts' $s"
conferir 'assert: uma linha ack_already_resolved' "grep -qF \"result = 'ack_already_resolved'\" $s"
conferir 'assert: nenhuma linha acknowledged' "grep -qF \"result = 'acknowledged'\" $s"
conferir 'assert: nada no alert_outbox' "grep -qF 'from alert_outbox' $s"

if [[ $falhas -gt 0 ]]; then echo "$falhas conferência(s) falharam" >&2; exit 1; fi
echo OK
