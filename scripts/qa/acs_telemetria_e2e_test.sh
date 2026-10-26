#!/usr/bin/env bash
# Confere a estrutura de acs_telemetria_e2e.sh (#83): limpa sempre (trap) e
# sempre despausa o Traefik, recusa relé antigo na 8765, corta e devolve o
# backend pelas linhas marcadoras do teste, e termina nas consultas ao banco de
# teste e no relatório do telemetry_report.dart. Também confere que a
# descoberta do `flutter test` não alcança o teste (sufixo `_e2e`). Sem Docker e
# sem aparelho: lê o texto.
set -euo pipefail
cd "$(dirname "$0")/../.."
s=scripts/qa/acs_telemetria_e2e.sh
t=apps/acs/integration_test/telemetry_e2e.dart
falhas=0
conferir() { if ! eval "$2"; then echo "FALHOU: $1" >&2; falhas=$((falhas+1)); fi; }

conferir 'o script existe e é bash válido' "[[ -f $s ]] && bash -n $s"
conferir 'o teste tem sufixo _e2e (fora da descoberta)' "[[ -f $t ]]"
conferir 'o teste tem teto de 8 min' "grep -qF '@Timeout(Duration(minutes: 8))' $t"
conferir 'trap cleanup EXIT' "grep -qF 'trap cleanup EXIT' $s"
conferir 'o cleanup despausa o Traefik' \
  "awk '/^cleanup\\(\\)/,/^}/' $s | grep -qF 'docker unpause sinalacs-traefik'"
conferir 'o manifesto sai antes do down' \
  "awk '/^cleanup\\(\\)/,/^}/' $s | grep -n -e 'rm -f .e2e/fixtures.json' -e 'e2e_stack.sh down' | head -1 | grep -qF 'fixtures.json'"
conferir 'recusa relé antigo na porta 8765' "grep -qF 'porta_ocupada 8765' $s"
conferir 'MQTT fora do alcance do aparelho (reserva HTTP)' "grep -qF 'reverse --remove tcp:8883' $s"
conferir 'nunca abre o reverse do broker' "! grep -qE 'reverse tcp:8883' $s"
for marca in E2E_CORTAR_BACKEND E2E_RESTAURAR_BACKEND; do
  conferir "o teste imprime $marca" "grep -qF \"print('$marca\" $t"
  conferir "o script reage a $marca" "grep -qF \"grep -q '$marca'\" $s"
done
conferir 'o corte pausa o Traefik' "grep -qF 'docker pause sinalacs-traefik' $s"
conferir 'o script exige E2E_TELEMETRIA_OK' "grep -qF 'E2E_TELEMETRIA_OK' $s && grep -qF \"print('E2E_TELEMETRIA_OK\" $t"
conferir 'assert: contagem por eventName' "grep -qF 'FROM telemetry_events GROUP BY 1' $s"
# O SQL vai entre aspas duplas no script: as aspas dos identificadores aparecem escapadas.
conferir 'assert: sem eventId duplicado' "grep -qF 'count(*) = count(DISTINCT' $s"
conferir 'assert: UUID do paciente nunca cru' "grep -qF 'patientPseudonym' $s && grep -qF 'payload LIKE' $s"
conferir 'assert: visita ligada ao alerta' "grep -qF \"='visit_registered' AND\" $s && grep -qF 'alerta_id' $s"
conferir 'roda o telemetry_report.dart no banco de e2e' \
  "grep -qF 'bin/telemetry_report.dart --from' $s && grep -qF 'SERVERPOD_DATABASE_NAME=sinalacs_e2e' $s"
for chave in eventualSyncRate interruptedAttempts alertLinkedVisits perAttemptSuccessRate medianAckLatencyMs; do
  conferir "o relatório confere $chave" "grep -qF '$chave' $s"
done

if [[ $falhas -gt 0 ]]; then echo "$falhas conferência(s) falharam" >&2; exit 1; fi
echo OK
