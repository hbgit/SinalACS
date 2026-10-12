#!/usr/bin/env bash
# Confere que admin_alertas_escalonar_e2e.sh escolhe o aparelho por DEVICE, usa o
# serial em todo adb/flutter, semeia o alerta vencido só com o opt-in, conversa
# com o teste pelas linhas marcadoras (inserir o alerta novo, cortar o backend),
# devolve o backend mesmo se falhar no meio e termina nos asserts que só o banco
# responde — e que nem o `e2e.sh --full` nem a descoberta do `flutter test`
# alcançam esta jornada (ela troca a stack de dev pela de e2e).
# Sem Docker e sem aparelho: lê o texto dos scripts.
set -euo pipefail
cd "$(dirname "$0")/../.."
s=scripts/qa/admin_alertas_escalonar_e2e.sh
t=apps/admin/integration_test/admin_alertas_escalonar_e2e.dart
falhas=0
conferir() { if ! eval "$2"; then echo "FALHOU: $1" >&2; falhas=$((falhas+1)); fi; }

conferir 'o script existe e é bash válido' "[[ -f $s ]] && bash -n $s"
conferir 'DEVICE com padrão emulator-5554' "grep -qF 'dev=\"\${DEVICE:-emulator-5554}\"' $s"
conferir 'emulator-5554 só aparece no padrão' "[[ \$(grep -c 'emulator-5554' $s) -le 1 ]]"
conferir 'adb reverse do RPC usa \$dev' "grep -qF 'adb -s \"\$dev\" reverse tcp:8443 tcp:443' $s"
conferir 'adb reverse do relé usa \$dev' "grep -qF 'adb -s \"\$dev\" reverse tcp:8765 tcp:8765' $s"
conferir 'flutter test usa -d \$dev' "grep -qF -- '-d \"\$dev\"' $s"
conferir 'roda o e2e do escalonamento pelo caminho' "grep -qF 'flutter test integration_test/admin_alertas_escalonar_e2e.dart' $s"
conferir 'relé com o manifesto das fixtures' "grep -qF 'E2E_FIXTURES_FILE=\"\$repo_root/.e2e/fixtures.json\" python3 scripts/qa/otp_relay.py' $s"
conferir 'cleanup derruba a stack de e2e' "grep -qF './scripts/qa/e2e_stack.sh down' $s"
conferir 'o manifesto sai antes do down' "grep -qF 'rm -f .e2e/fixtures.json' $s"
conferir 'recusa relé antigo na porta 8765' "grep -qF 'porta_ocupada 8765' $s"

# Seed: o alerta vencido é opt-in deste script e de nenhum outro runner.
conferir 'seed do escalonamento é opt-in só neste script' \
  "grep -qF 'E2E_SEED_ALERT_ESCALATION=1 ./scripts/qa/e2e_stack.sh seed' $s && ! grep -lF 'E2E_SEED_ALERT_ESCALATION=1' scripts/qa/*.sh | grep -v -e admin_alertas_escalonar_e2e.sh -e admin_alertas_escalonar_e2e_test.sh"
# O prazo curto vale só na stack de e2e; a de desenvolvimento segue com 300 s.
conferir 'stack de e2e com prazo de 30 s' "grep -qF 'RED_ALERT_ESCALATION_SECONDS: \"30\"' docker-compose.e2e.yml"
conferir 'stack de dev mantém o padrão de 300 s' "grep -qF 'RED_ALERT_ESCALATION_SECONDS: \"\${RED_ALERT_ESCALATION_SECONDS:-300}\"' docker-compose.yml"

# A conversa teste -> script: o teste pede, o script faz no host.
conferir 'o teste pede o alerta novo (linha marcadora)' "grep -qF \"print('E2E_DISPARAR_ALERTA \" $t"
conferir 'o script atende o pedido do alerta novo' "grep -qF 'E2E_DISPARAR_ALERTA' $s"
conferir 'o teste pede o corte do backend (linha marcadora)' "grep -qF \"print('E2E_CORTAR_BACKEND \" $t"
conferir 'o script atende o pedido de corte' "grep -qF 'E2E_CORTAR_BACKEND' $s"
# O Painel prova o pulso SEM troca de aba: o pedido do alerta novo sai com o
# Painel aberto, ANTES da primeira ida a Alertas (trocar de aba remonta a tela e
# relê, o que não provaria nada), e o script exige a linha de evidência.
conferir 'o pedido do alerta novo sai antes da primeira ida a Alertas' \
  "[[ \$(grep -n \"print('E2E_DISPARAR_ALERTA \" $t | head -1 | cut -d: -f1) -lt \$(grep -n \"_irPara(tester, const \\['Alertas'\\])\" $t | head -1 | cut -d: -f1) ]]"
conferir 'o teste imprime a evidência do Painel (E2E_PAINEL_ATUALIZOU)' "grep -qF \"print('E2E_PAINEL_ATUALIZOU \" $t"
conferir 'o script exige a evidência do Painel' "grep -qF \"grep -q 'E2E_PAINEL_ATUALIZOU atraso_ms='\" $s"
conferir 'corte de 120 s no teste e no padrão do script' \
  "grep -qF 'const _segundosDeCorte = 120;' $t && grep -qF '[[ -n \"\$segundos\" ]] || segundos=120' $s"
# O alerta novo nasce no futuro pelo freshLead da fixture (20 s): a janela "no
# prazo" tem de ser maior que um pulso.
conferir 'alerta novo com triggeredAt 20 s à frente (freshLead)' \
  "grep -qF \"NOW() + interval '20 seconds'\" $s && grep -qF 'freshLead = Duration(seconds: 20)' backend/sinalacs_server/lib/src/infrastructure/testing/e2e_fixtures.dart"
conferir 'o corte é pausar o backend e devolvê-lo' "grep -qF 'docker pause sinalacs-serverpod' $s && grep -qF 'docker unpause sinalacs-serverpod' $s"
conferir 'o cleanup despausa o backend antes do down' \
  "awk '/^cleanup\\(\\)/,/^}/' $s | grep -qF 'docker unpause sinalacs-serverpod'"
conferir 'o teste recebe os ids dos alertas por dart-define' \
  "grep -qF -- '--dart-define=E2E_ALERTA_VENCIDO=' $s && grep -qF -- '--dart-define=E2E_ALERTA_NOVO=' $s"

# "Sem atualização manual": o teste nunca mexe nos filtros nem puxa a lista.
conferir 'o teste não toca nos filtros da lista' "! grep -qE 'alerts_(status|micro_area)_filter' $t"
conferir 'o teste não usa pull-to-refresh' "! grep -qE 'RefreshIndicator|fling\\(' $t"
conferir 'o teste reescalona por RPC direto' "grep -qF 'client.admin.escalateAlert(' $t && grep -qF 'alreadyEscalated' $t"

# Os asserts finais: o que o teste no aparelho não alcança (banco de teste).
conferir 'assert da linha escalated:no_ack_timeout' "grep -qF \"'escalated:no_ack_timeout'\" $s"
conferir 'assert da linha already_escalated:no_ack_timeout' "grep -qF \"'already_escalated:no_ack_timeout'\" $s"
conferir 'o resultado auditado é o do serviço' \
  "grep -qF \"'already_escalated' : 'escalated'\" backend/sinalacs_server/lib/src/application/admin/alert_escalation_service.dart && grep -qF \"'no_ack_timeout'\" backend/sinalacs_server/lib/src/application/admin/alert_escalation_service.dart"
conferir 'assert do alerta pendente escalonado pelo coordenador' "grep -qF 'escalatedBy' $s && grep -qF \"status = 'pending'\" $s"
conferir 'assert da sessão de monitoramento' "grep -qF \"'monitoring_session_start'\" $s"
conferir 'assert do teto de leituras (o pulso não grava read)' "grep -qF 'teto_leituras=' $s"
conferir 'tetos de leitura por recurso' \
  "for r in 'teto admin_indicators 4' 'teto admin_alerts 9' 'teto admin_micro_areas 3' 'teto admin_audit_logs 0' 'teto_leituras=16'; do grep -qF \"\$r\" $s || exit 1; done"
conferir 'nenhuma linha read do pulso' "grep -qF 'nenhuma linha read do pulso' $s && grep -qF \"'admin_pulse'\" $s"
# A recusa do pulso grava `read`/`admin_pulse`/`denied` (AdminScopeResolver):
# a contagem só exclui recusas se o SQL disser isso, como o comentário diz.
conferir 'a contagem de read do pulso exclui as recusas' "grep -F \"'admin_pulse' and\" $s | grep -qF \"<> 'denied'\""
conferir 'confere a cadeia de auditoria' "grep -qF 'audit_chain_check.dart' $s"

# Regressão offline: opcional e desligada por padrão.
conferir 'flag --com-regressao-offline roda a jornada offline do ACS' \
  "grep -qF -- '--com-regressao-offline) regressao_offline=true' $s && grep -qF './scripts/qa/acs_full_e2e.sh' $s"
conferir 'a regressão offline é desligada por padrão' "grep -qF 'regressao_offline=false' $s"
conferir 'argumento desconhecido é recusado' "grep -qF 'argumento desconhecido' $s"

# Descoberta: `flutter test integration_test` só pega `*_test.dart`, e o
# `e2e.sh --full` roda só o smoke hermético do admin.
conferir 'o arquivo do e2e existe e não é descoberto (sufixo _e2e.dart)' "[[ -f $t ]] && [[ $t != *_test.dart ]]"
conferir 'e2e.sh --full não roda o e2e do escalonamento' "! grep -q 'flutter test integration_test/admin_alertas_escalonar_e2e' scripts/qa/e2e.sh"
conferir 'e2e.sh aponta para este script' "grep -qF 'scripts/qa/admin_alertas_escalonar_e2e.sh' scripts/qa/e2e.sh"

[[ $falhas -eq 0 ]] && echo ok || exit 1
