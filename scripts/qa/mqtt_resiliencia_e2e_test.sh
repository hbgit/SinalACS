#!/usr/bin/env bash
# Confere que mqtt_resiliencia_e2e.sh (issue #56) roda por padrão só os
# cenários realistas do broker (base, B e C), deixa a pausa do backend (A,
# diagnóstico) atrás de --com-pausa-do-backend, recusa argumento desconhecido
# com exit 2 antes de tocar no Docker, cria o alerta DURANTE a interrupção,
# afirma RestartCount 0 + StartedAt, outbox publicado e entrega pelo broker,
# sempre devolve a stack e não imprime coluna protegida nem senha no argv (o broker
# não tem senha desde a #94).
# Sem Docker e sem aparelho: lê o texto do script (e executa só o parsing).
set -euo pipefail
cd "$(dirname "$0")/../.."
s=scripts/qa/mqtt_resiliencia_e2e.sh
falhas=0
conferir() { if ! eval "$2"; then echo "FALHOU: $1" >&2; falhas=$((falhas+1)); fi; }
# Corpo de uma função do script (da linha `nome() {` até a `}` da coluna 0).
corpo() { awk -v n="$1" '$0 ~ "^"n"\\(\\)" {f=1} f {print} f && /^}/ {exit}' "$s"; }

conferir 'o script existe e é bash válido' "[[ -f $s ]] && bash -n $s"

# Flags: a pausa do backend é opt-in; nada além dela é aceito.
conferir 'a pausa do backend vem desligada' "grep -qxF 'com_pausa_do_backend=false' $s"
conferir 'só --com-pausa-do-backend a liga' "grep -qF -- '--com-pausa-do-backend) com_pausa_do_backend=true ;;' $s"
conferir 'o cenário A só roda com a flag' \
  "grep -qxF 'if [[ \"\$com_pausa_do_backend\" == true ]]; then cenario_A; fi' $s && [[ \$(grep -cE '^[[:space:]]*cenario_A\$|cenario_A;' $s) -eq 1 ]]"
conferir 'base, B e C rodam por padrão' "grep -qx 'cenario_base' $s && grep -qx 'cenario_B' $s && grep -qx 'cenario_C' $s"
conferir 'sem os modos posicionais antigos (A|B|C|todos)' "! grep -qE '^[[:space:]]*(A|B|C|todos)\\)' $s"
conferir 'o cabeçalho documenta A como diagnóstico' "grep -qF 'DIAGNÓSTICO, desligado por padrão' $s"
# Executado de verdade: o parsing vem antes de qualquer docker/e2e_stack.
saida="$(bash $s --nao-existe 2>&1)" && rc=0 || rc=$?
conferir 'argumento desconhecido sai com 2' "[[ $rc -eq 2 ]]"
conferir 'e diz qual argumento' "[[ \"\$saida\" == *'argumento desconhecido: --nao-existe'* ]]"
saida="$(bash $s B 2>&1)" && rc=0 || rc=$?
conferir 'o antigo posicional B também é recusado com 2' "[[ $rc -eq 2 ]]"
conferir 'o parsing vem antes de subir a stack' \
  "[[ \$(grep -n 'argumento desconhecido' $s | head -1 | cut -d: -f1) -lt \$(grep -n './scripts/qa/e2e_stack.sh up' $s | head -1 | cut -d: -f1) ]]"

# O alerta nasce DURANTE a interrupção, pelo login real do paciente da fixture.
conferir 'o alerta reaproveita o live_check do paciente com o manifesto' \
  "grep -qF 'E2E_FIXTURES_FILE=\"\$repo_root/.e2e/fixtures.json\" dart run tool/live_check.dart' $s"
conferir 'respeita os 60 s entre OTPs do mesmo paciente' "grep -qxF 'INTERVALO_OTP=65' $s"
conferir 'B: alerta entre o stop e o start do broker' \
  "corpo cenario_B | awk '/docker stop/{a=NR} /criar_alerta B/{b=NR} /docker start/{c=NR} END{exit !(a && b && c && a<b && b<c)}'"
conferir 'C: os dois alertas entre o disconnect e o connect' \
  "corpo cenario_C | awk '/network disconnect/{a=NR} /criar_alerta C_INICIO/{b=NR} /criar_alerta C_FIM/{c=NR} /network connect/{d=NR} END{exit !(a && b && c && d && a<b && b<c && c<d)}'"
conferir 'C religa o broker com os aliases do Compose' "corpo cenario_C | grep -qF 'docker network connect --alias mosquitto --alias \"\$BROKER\"'"

# As três afirmações por alerta.
conferir '(a) RestartCount e StartedAt no estado do backend' "grep -qF '{{.State.Running}} {{.State.StartedAt}} rc={{.RestartCount}}' $s"
conferir '(a) exige RestartCount 0 e o mesmo estado' "corpo conferir | grep -qF '\"\$depois\" != *\" rc=0\"' && corpo conferir | grep -qF '\"\$depois\" != \"\$antes\"'"
conferir '(b) outbox publicado por contagem' "grep -qF 'from alert_outbox where \\\"alertId\\\" = '\\''\$id'\\'' and \\\"publishedAt\\\" is not null' $s"
conferir '(c) entrega conferida no broker pelo alert_id, no registro do assinante' "corpo recebido_no_broker | grep -qF 'entregas_de' && corpo entregas_de | grep -qF 'grep -F'"
conferir '(c) um assinante persistente QoS 1 com id fixo' "corpo iniciar_assinante | grep -qF 'mqtt_sub -c -i \"\$SUB_ID\" -q 1 -t \"\$topico\" -E' && corpo iniciar_assinante | grep -qF -- '-c -i \$SUB_ID -q 1 -t \$topico -F '\''%p'\'''"
conferir '(c) o assinante nasce antes de qualquer alerta' \
  "[[ \$(grep -n '^iniciar_assinante\$' $s | head -1 | cut -d: -f1) -lt \$(grep -n '^cenario_base\$' $s | head -1 | cut -d: -f1) ]]"
conferir '(c) o assinante registra só hora e alert_id (nunca o payload)' \
  "corpo iniciar_assinante | grep -F 'echo ' | grep -F '>> \$SUB_LOG' | grep -qF 'date +%s' && [[ \$(corpo iniciar_assinante | grep -c 'echo \"') -eq 1 ]]"
conferir '(c) nenhuma consulta consome com -C 1' "! grep -qE 'mosquitto_sub.* -C 1|mqtt_sub.* -C 1' $s"
conferir '(c) o B relança o assinante depois do docker start' \
  "corpo cenario_B | awk '/docker start/{a=NR} /iniciar_assinante/{b=NR} END{exit !(a && b && a<b)}'"
conferir '(c) duplicata é reportada, não é falha' "grep -qF 'entregas=\$ENTREGAS' $s && grep -qF 'duplicata, não falha' $s"
conferir '(c) o cleanup para o assinante e apaga o registro' "corpo cleanup | grep -qF 'parar_assinante' && corpo cleanup | grep -qF '\$SUB_LOG'"
conferir 'publicado sem entrega é apontado como H5' "grep -qF 'lacuna H5' $s"
conferir 'qualquer falha sai com código != 0' "grep -qF 'FALHOU: \${falhas[*]}' $s && grep -qxF '  exit 1' $s"

# Privacidade: só contagens/booleanos do banco, nenhuma senha, log sanitizado.
conferir 'nenhuma coluna protegida no SQL' "! grep -E 'select[^\"]*(payload|lastError|patientId|locationHash|cpf)' $s"
conferir 'sem senha no broker (#94): folha backend da CA de aparelhos, nenhum -u/-P/-o' \
  "grep -qF -- '--cert /mosquitto/devices/backend.crt' $s && ! grep -qE 'mosquitto_sub[^|]* -(P|u|o) ' $s && ! grep -qF 'MQTT_BACKEND_PASSWORD' $s"
conferir 'o código OTP é tirado dos logs guardados' "grep -qF 'código de acesso: <otp>' $s"

# Restauração: sempre, e sem destruir nada.
conferir 'o cleanup despausa, religa e reinicia o broker' \
  "corpo cleanup | grep -qF 'docker unpause \"\$BACK\"' && corpo cleanup | grep -qF 'docker network connect' && corpo cleanup | grep -qF 'docker start \"\$BROKER\"'"
conferir 'o cleanup derruba a stack de e2e e volta a de desenvolvimento' \
  "corpo cleanup | grep -qF './scripts/qa/e2e_stack.sh down' && corpo cleanup | grep -qF 'docker compose up -d'"
conferir 'o manifesto sai antes do down' \
  "corpo cleanup | awk '/rm -f .e2e.fixtures.json/{a=NR} /e2e_stack.sh down/{b=NR} END{exit !(a && b && a<b)}'"
conferir 'trap no EXIT' "grep -qxF 'trap cleanup EXIT' $s"
conferir 'nunca docker compose down nem apaga volume' "! grep -qE 'docker compose down|rm -rf pg_data|volume rm|down -v' $s"
conferir 'recusa relé antigo na porta 8765' "grep -qF 'porta_ocupada 8765' $s"

# Fora da CI: não é job nem é chamado por outro runner.
conferir 'a CI não roda o script' "! grep -q 'mqtt_resiliencia_e2e' .github/workflows/ci.yml"

[[ $falhas -eq 0 ]] && echo ok || exit 1
