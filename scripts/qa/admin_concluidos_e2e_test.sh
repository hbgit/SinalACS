#!/usr/bin/env bash
# Confere que admin_concluidos_e2e.sh escolhe o aparelho por DEVICE, usa o serial
# em todo adb/flutter, semeia os 3 alertas do painel (opt-in), conversa com o
# teste pelas linhas marcadoras (reconhecer, concluir, concluir sem microárea),
# derruba a stack de e2e ao sair e termina nos asserts que só o banco responde —
# e que nem o `e2e.sh --full` nem a descoberta do `flutter test` alcançam esta
# jornada (ela troca a stack de dev pela de e2e).
# Sem Docker e sem aparelho: lê o texto dos scripts.
set -euo pipefail
cd "$(dirname "$0")/../.."
s=scripts/qa/admin_concluidos_e2e.sh
t=apps/admin/integration_test/admin_concluidos_e2e.dart
falhas=0
conferir() { if ! eval "$2"; then echo "FALHOU: $1" >&2; falhas=$((falhas+1)); fi; }

conferir 'o script existe e é bash válido' "[[ -f $s ]] && bash -n $s"
conferir 'DEVICE com padrão emulator-5554' "grep -qF 'dev=\"\${DEVICE:-emulator-5554}\"' $s"
conferir 'emulator-5554 só aparece no padrão' "[[ \$(grep -c 'emulator-5554' $s) -le 1 ]]"
conferir 'adb reverse do RPC usa \$dev' "grep -qF 'adb -s \"\$dev\" reverse tcp:8443 tcp:443' $s"
conferir 'adb reverse do relé usa \$dev' "grep -qF 'adb -s \"\$dev\" reverse tcp:8765 tcp:8765' $s"
conferir 'flutter test usa -d \$dev' "grep -qF -- '-d \"\$dev\"' $s"
conferir 'roda o e2e do alerta concluído pelo caminho' "grep -qF 'flutter test integration_test/admin_concluidos_e2e.dart' $s"
conferir 'relé com o manifesto das fixtures' "grep -qF 'E2E_FIXTURES_FILE=\"\$repo_root/.e2e/fixtures.json\" python3 scripts/qa/otp_relay.py' $s"
conferir 'cleanup derruba a stack de e2e' "grep -qF './scripts/qa/e2e_stack.sh down' $s"
conferir 'o manifesto sai antes do down' "grep -qF 'rm -f .e2e/fixtures.json' $s"
conferir 'recusa relé antigo na porta 8765' "grep -qF 'porta_ocupada 8765' $s"
conferir 'o teste tem sufixo _e2e e não é descoberto' "[[ -f $t ]] && ! ls apps/admin/integration_test/*_test.dart | grep -q concluidos"

# Seed: os 3 alertas do painel, o mesmo opt-in do admin_login_e2e.sh.
conferir 'seed dos alertas do painel é opt-in' "grep -qF 'E2E_SEED_ADMIN_ALERTS=1 ./scripts/qa/e2e_stack.sh seed' $s"
conferir 'os ids vêm do manifesto (adminAlertIds)' "grep -qF \"d['adminAlertIds'][0]\" $s && grep -qF \"d['adminAlertIds'][1]\" $s"
conferir 'o teste recebe os ids por dart-define' \
  "grep -qF -- '--dart-define=E2E_ALERTA_PENDENTE=' $s && grep -qF -- '--dart-define=E2E_ALERTA_RECONHECIDO=' $s"

# A conversa teste -> script: o teste pede, o script faz no banco.
conferir 'o teste pede o reconhecimento (linha marcadora)' "grep -qF \"print('E2E_RECONHECER \" $t"
conferir 'o script atende o reconhecimento' "grep -qF 'E2E_RECONHECER id=' $s && grep -qF \"status = 'acknowledged'\" $s"
conferir 'o teste pede a conclusão (linha marcadora)' "grep -qF \"print('E2E_CONCLUIR \" $t"
conferir 'o script atende a conclusão com resolvedAt' "grep -qF 'E2E_CONCLUIR id=' $s && grep -qF 'resolvedAt\\\" = NOW()' $s"
conferir 'o teste pede o concluído sem microárea' "grep -qF \"print('E2E_CONCLUIR_SEM_MICROAREA')\" $t"
conferir 'o script insere o concluído sem microárea' "grep -qF 'E2E_CONCLUIR_SEM_MICROAREA' $s && grep -qF 'concluir_sem_microarea()' $s && grep -qF \"NULL, NOW() - interval '30 minutes'\" $s"
conferir 'só UUID chega ao SQL das marcas' "grep -qF 'uuid_da_marca' $s && grep -qF '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' $s"
# A reprodução: o teste exige a linha "Concluídos" antes de qualquer transição.
conferir 'o teste exige a linha Concluídos (reprodução da #87)' "grep -qF \"'#87: o Painel não tem a linha \\\"Concluídos\\\"'\" $t"
# O Painel prova o pulso SEM troca de aba: as transições são pedidas com o
# Painel aberto, ANTES da primeira ida a Alertas.
conferir 'as transições saem antes da primeira ida a Alertas' \
  "[[ \$(grep -n \"print('E2E_CONCLUIR \" $t | head -1 | cut -d: -f1) -lt \$(grep -n \"_irPara(tester, const \\['Alertas'\\])\" $t | head -1 | cut -d: -f1) ]]"
conferir 'o teste imprime as evidências do Painel' "grep -qF \"print('E2E_PAINEL_RECONHECIDO \" $t && grep -qF \"print('E2E_PAINEL_CONCLUIDO \" $t"
conferir 'o script exige as evidências do Painel' "grep -qF 'for marca in E2E_PAINEL_RECONHECIDO E2E_PAINEL_CONCLUIDO' $s"
conferir 'o script exige a evidência de Alertas' "grep -qF \"grep -q 'E2E_ALERTAS_CONCLUIDO_OK'\" $s"
conferir 'o teste não usa pull-to-refresh' "! grep -qE 'RefreshIndicator|fling\\(' $t"
conferir 'o teste confere a soma com o cartão Vermelho (INV-03)' "grep -qF \"risk_counter_red\" $t"

# Os asserts finais: o que o teste no aparelho não alcança (banco de teste).
conferir 'assert dos dois concluídos' "grep -qF \"status = 'resolved'\\\"\" $s"
conferir 'assert do concluído sem microárea' "grep -qF 'microAreaId\\\" is null' $s"
conferir 'assert de que o pulso não grava read' "grep -qF \"'admin_pulse'\" $s"
conferir 'assert do outbox vazio para a jornada' "grep -qF 'from alert_outbox where' $s"
conferir 'assert da sessão de monitoramento' "grep -qF \"'monitoring_session_start'\" $s"
conferir 'cadeia de auditoria conferida' "grep -qF 'audit_chain_check.dart' $s"

if [[ "$falhas" -eq 0 ]]; then echo OK; else echo "$falhas falha(s)" >&2; exit 1; fi
