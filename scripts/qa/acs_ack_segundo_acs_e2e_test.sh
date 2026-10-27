#!/usr/bin/env bash
# Confere que acs_ack_segundo_acs_e2e.sh (#88) monta o aparelho como o SEGUNDO
# ACS da fixture, com a mesma anatomia da #86 (broker fora do alcance, alerta
# por SQL sem outbox e SEM acsId), confirma o alerta no banco como o ACS A a
# pedido do teste, apaga o manifesto antes do down e termina nos asserts que
# só o banco responde (acsId segue o A, entrega do B, trilha do B) — e que a
# descoberta do `flutter test` não alcança o teste (sufixo `_e2e`). Sem Docker
# e sem aparelho: lê o texto.
set -euo pipefail
cd "$(dirname "$0")/../.."
s=scripts/qa/acs_ack_segundo_acs_e2e.sh
t=apps/acs/integration_test/ack_by_second_acs_e2e.dart
falhas=0
conferir() { if ! eval "$2"; then echo "FALHOU: $1" >&2; falhas=$((falhas+1)); fi; }

conferir 'o script existe e é bash válido' "[[ -f $s ]] && bash -n $s"
conferir 'o teste tem sufixo _e2e (fora da descoberta)' "[[ -f $t ]]"
conferir 'o script roda esse teste' "grep -qF 'integration_test/ack_by_second_acs_e2e.dart' $s"
conferir 'o teste entra como o segundo ACS' "grep -qF 'secondAcsCredentialFromRelay()' $t"
conferir 'DEVICE com padrão emulator-5554' "grep -qF 'dev=\"\${DEVICE:-emulator-5554}\"' $s"
conferir 'remove o reverse do broker' "grep -qF 'reverse --remove tcp:8883' $s"
conferir 'nunca abre o reverse do broker' "! grep -qE 'reverse tcp:8883' $s"
conferir 'o insert não toca no outbox' "! grep -qiE 'insert into alert_outbox' $s"
conferir 'o insert vai sem acsId' "grep -qF \"'\\\$main_id', NULL, '\\\$area_id'\" $s"
conferir 'o aparelho A confirma no banco' "grep -qF \"update alerts set status = 'acknowledged'\" $s"
conferir 'o aparelho A registra a própria entrega' "grep -qF 'insert into alert_deliveries' $s"
conferir 'as senhas não vão no argv (manifesto sem credenciais)' "grep -qF \"d.pop('acsB',None)\" $s"
conferir 'o manifesto sai antes do down' \
  "awk '/^cleanup\\(\\)/,/^}/' $s | grep -n -e 'rm -f .e2e/fixtures.json' -e 'e2e_stack.sh down' | head -1 | grep -qF 'fixtures.json'"
conferir 'recusa relé antigo na porta 8765' "grep -qF 'porta_ocupada 8765' $s"
for marca in E2E_DISPARAR_ALERTA E2E_CONFIRMAR_NO_APARELHO_A; do
  conferir "o teste pede $marca" "grep -qF \"print('$marca \" $t"
  conferir "o script atende $marca" "grep -qF '$marca id=' $s"
done
conferir 'o teste imprime E2E_ACK_B_OK' "grep -qF \"print('E2E_ACK_B_OK\" $t"
conferir 'o script exige E2E_ACK_B_OK' "grep -qF 'E2E_ACK_B_OK' $s"
conferir 'assert: acsId segue o A' "grep -qE 'select .+acsId.+ from alerts' $s"
conferir 'assert: acknowledgedAt não mudou' "grep -qE 'select .+acknowledgedAt.+ from alerts' $s"
conferir 'assert: a entrega do B existe' "grep -qE 'from alert_deliveries .+acsId.+ = .+acs_b_id' $s"
conferir 'assert: uma linha ack_already_acknowledged do B' "grep -qE \"result = 'ack_already_acknowledged' and .+userId.+ = .+acs_b_id\" $s"
conferir 'assert: nenhuma linha acknowledged' "grep -qF \"result = 'acknowledged'\" $s"
conferir 'assert: nada no alert_outbox' "grep -qF 'from alert_outbox' $s"

if [[ $falhas -gt 0 ]]; then echo "$falhas conferência(s) falharam" >&2; exit 1; fi
echo OK
