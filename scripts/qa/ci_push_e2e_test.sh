#!/usr/bin/env bash
# ci_push_e2e.sh: pula sem credenciais; com elas, instala a chave e chama o push e2e.
set -uo pipefail
cd "$(dirname "$0")/../.."
orig="$PWD/scripts/qa/ci_push_e2e.sh"
repo="$PWD"
raiz="$(mktemp -d)"; trap 'rm -rf "$raiz"' EXIT
marcador="$raiz/falhas"; : >"$marcador"
afirma() { if eval "$2"; then echo "ok: $1"; else echo "FALHOU: $1"; echo x >>"$marcador"; fi; }

nova_arvore() {
  R="$raiz/repo.$RANDOM"; mkdir -p "$R/scripts/qa" "$R/apps/patient/android/app"
  cp "$orig" "$R/scripts/qa/ci_push_e2e.sh"
  cat >"$R/stub_push.sh" <<'STUB'
#!/usr/bin/env bash
echo "chamado" >>"$(dirname "$0")/chamadas"
[[ -f infra/docker/gorush/credentials/fcm-service-account.json ]] && stat -c %a infra/docker/gorush/credentials/fcm-service-account.json >"$(dirname "$0")/modo_da_chave"
echo "${GORUSH_UID:-}:${GORUSH_GID:-}" >"$(dirname "$0")/uid_gid"
exit "${STUB_RC:-0}"
STUB
  chmod +x "$R/stub_push.sh" "$R/scripts/qa/ci_push_e2e.sh"
  echo '{"chave":"FAKE"}' >"$raiz/chave.json"
  unset GOOGLE_APPLICATION_CREDENTIALS STUB_RC
  export PUSH_E2E_SCRIPT="$R/stub_push.sh"
}
roda() { "$R/scripts/qa/ci_push_e2e.sh" 2>&1; }

nova_arvore
out="$(roda)"; rc=$?
afirma "sem variável e sem google-services: pula (exit 0, ::notice, stub não chamado)" '[[ $rc -eq 0 ]] && grep -q "^::notice" <<<"$out" && [[ ! -e "$R/chamadas" ]]'

nova_arvore
export GOOGLE_APPLICATION_CREDENTIALS="$raiz/chave.json"
out="$(roda)"; rc=$?
afirma "com a chave mas sem google-services.json: pula" '[[ $rc -eq 0 && ! -e "$R/chamadas" && ! -e "$R/infra" ]]'

nova_arvore
echo '{}' >"$R/apps/patient/android/app/google-services.json"
out="$(roda)"; rc=$?
afirma "com google-services.json mas sem a chave: pula" '[[ $rc -eq 0 && ! -e "$R/chamadas" ]]'

nova_arvore
export GOOGLE_APPLICATION_CREDENTIALS="$raiz/inexistente.json"
echo '{}' >"$R/apps/patient/android/app/google-services.json"
out="$(roda)"; rc=$?
afirma "variável apontando para arquivo inexistente: pula" '[[ $rc -eq 0 && ! -e "$R/chamadas" ]]'

nova_arvore
export GOOGLE_APPLICATION_CREDENTIALS="$raiz/chave.json"
echo '{}' >"$R/apps/patient/android/app/google-services.json"
out="$(roda)"; rc=$?
cofre="$R/infra/docker/gorush/credentials/fcm-service-account.json"
afirma "com os dois: instala a chave idêntica em 0600" '[[ "$(cat "$cofre")" == "$(cat "$raiz/chave.json")" && "$(cat "$R/modo_da_chave")" == 600 ]]'
afirma "com os dois: chama o push e2e uma vez" '[[ "$(wc -l <"$R/chamadas")" -eq 1 ]]'
afirma "o container do Gorush roda com o uid/gid do host (a chave 0600 é do usuário do runner)" '[[ "$(cat "$R/uid_gid")" == "$(id -u):$(id -g)" ]]'
afirma "o docker-compose.yml usa GORUSH_UID/GORUSH_GID no serviço gorush" 'sed -n "/^  gorush:/,/^  serverpod:/p" "$repo/docker-compose.yml" | grep -q "GORUSH_UID" && sed -n "/^  gorush:/,/^  serverpod:/p" "$repo/docker-compose.yml" | grep -q "GORUSH_GID"'
afirma "a saída não imprime o conteúdo da chave" '! grep -q "FAKE" <<<"$out"'

nova_arvore
export GOOGLE_APPLICATION_CREDENTIALS="$raiz/chave.json" STUB_RC=7
echo '{}' >"$R/apps/patient/android/app/google-services.json"
out="$(roda)"; rc=$?
afirma "o exit do push e2e é propagado (7)" '[[ $rc -eq 7 ]]'

# ---- M3: uma falha do `docker compose down` no trap não pode trocar o código de saída ----------
stub="$raiz/stub_bin"; mkdir -p "$stub"; printf '#!/bin/sh\nexit 1\n' >"$stub/docker"; chmod +x "$stub/docker"
linha_trap="$(grep '^trap ' "$repo/scripts/qa/run_android_e2e.sh")"
PATH="$stub:$PATH" bash -c "set -e; $linha_trap; exit 7"; rc=$?
afirma "M3 o trap de down que falha preserva o exit do script (7)" '[[ $rc -eq 7 ]]'
PATH="$stub:$PATH" bash -c "set -e; $linha_trap; exit 0"; rc=$?
afirma "M3 o trap de down que falha não transforma sucesso em falha" '[[ $rc -eq 0 ]]'

# ---- M8: o cabeçalho do push_e2e.sh não pode mais dizer que NÃO roda na CI ----------------------
afirma "M8 o cabeçalho do push_e2e.sh não afirma 'NÃO roda na CI'" '! sed -n 1,25p "$repo/scripts/qa/push_e2e.sh" | grep -q "NÃO roda na CI"'

# ---- M9: no CI o log é público — o project_id não pode ser impresso ------------------------------
guarda="$raiz/guarda.py"
sed -n "/^python3 - <<'PYEOF'/,/^PYEOF/p" "$repo/scripts/qa/push_e2e.sh" | sed '1d;$d' >"$guarda"
mkdir -p "$raiz/g/infra/docker/gorush/credentials" "$raiz/g/apps/patient/android/app"
echo '{"type":"service_account","project_id":"proj-secreto-123","client_email":"x@y","private_key":"k"}' >"$raiz/g/infra/docker/gorush/credentials/fcm-service-account.json"
echo '{"project_info":{"project_id":"proj-secreto-123"},"client":[{"client_info":{"android_client_info":{"package_name":"br.com.prismrr.sinalacs.patient"}}}]}' >"$raiz/g/apps/patient/android/app/google-services.json"
out_ci="$(cd "$raiz/g" && GITHUB_ACTIONS=true python3 "$guarda" 2>&1)"; rc_ci=$?
out_local="$(cd "$raiz/g" && env -u GITHUB_ACTIONS python3 "$guarda" 2>&1)"
afirma "M9 a guarda roda com chaves válidas (exit 0)" '[[ $rc_ci -eq 0 ]]'
afirma "M9 no CI o project_id não é impresso" '! grep -q "proj-secreto-123" <<<"$out_ci" && grep -q "chave ok" <<<"$out_ci"'
afirma "M9 fora do CI o project_id continua aparecendo (útil ao dev)" 'grep -q "proj-secreto-123" <<<"$out_local"'

# ---- M10: parar o push e2e tem de matar o `flutter test` (neto do subshell), não só o subshell --
fn="$(sed -n '/^parar_arvore()/,/^}/p' "$repo/scripts/qa/push_e2e.sh")"
afirma "M10 push_e2e.sh define parar_arvore e liga o controle de jobs (set -m)" '[[ -n "$fn" ]] && grep -q "^set -m" "$repo/scripts/qa/push_e2e.sh"'
marca="$raiz/neto.pid"
bash -c "set -m; $fn
( sh -c 'echo \$\$ >$marca; exec sleep 300' & wait ) &
hold=\$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s $marca ] && break; sleep 0.2; done
parar_arvore \$hold
sleep 0.5" 2>/dev/null
neto="$(cat "$marca" 2>/dev/null || echo 0)"
afirma "M10 o neto (flutter test) morre junto" '[[ "$neto" != 0 ]] && ! kill -0 "$neto" 2>/dev/null'
kill "$neto" 2>/dev/null || true

# ---- #103: diagnóstico do push (redação, recorte do bloco do app e classificação) ---------------
fx="$repo/scripts/qa/fixtures/push_diag"
app_pkg=br.com.prismrr.sinalacs.patient
diag() { bash -c "source '$repo/scripts/qa/lib_push_diag.sh'; $1" 2>&1; }
token_falso="abcDEF12345:APA91$(printf 'b%.0s' $(seq 1 140))"

out="$(printf 'antes %s depois\n' "$token_falso" | diag diag_redigir)"
afirma "#103 redação: token fictício no formato FCM vira <token-fcm>" '! grep -q APA91 <<<"$out" && grep -q "antes <token-fcm> depois" <<<"$out"'
out="$(printf 'projeto proj-secreto-123 aqui\n' | PUSH_DIAG_SEGREDOS=$'outro.segredo\nproj-secreto-123' diag diag_redigir)"
afirma "#103 redação: literal de PUSH_DIAG_SEGREDOS (project_id) vira <redigido>" '! grep -q proj-secreto-123 <<<"$out" && grep -q "projeto <redigido> aqui" <<<"$out"'
sujo="$raiz/sujo.txt"; printf 'linha %s\n' "$token_falso" >"$sujo"
diag "diag_verificar_limpo '$sujo'" >/dev/null; rc=$?
afirma "#103 verificação fail-closed: arquivo com APA91 é apagado e deixa .REMOVIDO sem o token" '[[ $rc -ne 0 && ! -e "$sujo" && -s "$sujo.REMOVIDO" ]] && ! grep -q APA91 "$sujo.REMOVIDO"'
limpo="$raiz/limpo.txt"; echo 'nada aqui' >"$limpo"
diag "diag_verificar_limpo '$limpo'" >/dev/null; rc=$?
afirma "#103 verificação: arquivo limpo fica e retorna 0" '[[ $rc -eq 0 && -s "$limpo" && ! -e "$limpo.REMOVIDO" ]]'

out="$(diag "diag_bloco_do_app '$fx/dump_dois_pacotes.txt' $app_pkg")"
afirma "#103 bloco: dump de dois pacotes devolve só o bloco do app" 'grep -q "Outro aviso" <<<"$out" && ! grep -q "SinalACS e2e" <<<"$out" && ! grep -q "com.exemplo.outro" <<<"$out"'

classe() { diag "diag_classificar '$fx/$1' '$fx/$2' $app_pkg '$3'"; }
afirma "#103 classificar: título a 25 linhas = exibida_encontrada" '[[ "$(classe dump_um_app.txt logcat_recebida.txt "SinalACS e2e")" == exibida_encontrada ]]'
afirma "#103 classificar: título a 45 linhas = exibida_nao_encontrada" '[[ "$(classe dump_titulo_longe.txt logcat_recebida.txt "SinalACS e2e")" == exibida_nao_encontrada ]]'
afirma "#103 classificar: dump sem o app + logcat com a marca = chegou_nao_exibida" '[[ "$(classe dump_dois_pacotes.txt logcat_recebida.txt "Aviso inexistente")" == chegou_nao_exibida ]]'
afirma "#103 classificar: dump sem o app + logcat vazio = nao_chegou" '[[ "$(classe dump_dois_pacotes.txt logcat_vazio.txt "Aviso inexistente")" == nao_chegou ]]'
afirma "#103 classificar: título só em outro pacote não conta como exibida" '[[ "$(classe dump_dois_pacotes.txt logcat_vazio.txt "SinalACS e2e")" == nao_chegou ]]'

# ---- #103: coleta na falha (adb stub) -------------------------------------------------------------
# O stub responde de fixtures. STUB_ADB_MODO: ok | falha (sai 1) | pendura (dorme 300 s).
# STUB_ADB_TARDIA=N: a partir da N-ésima chamada de `dumpsys notification` o título aparece.
sb="$raiz/stub_adb"; mkdir -p "$sb"
cat >"$sb/adb" <<STUB
#!/usr/bin/env bash
case "\${STUB_ADB_MODO:-ok}" in falha) exit 1 ;; pendura) exec sleep 300 ;; esac
args="\$*"
case "\$args" in
  *"dumpsys notification"*)
    n=\$(( \$(cat "$sb/n_dump" 2>/dev/null || echo 0) + 1 )); echo \$n >"$sb/n_dump"
    if [[ -n "\${STUB_ADB_TARDIA:-}" && \$n -ge \$STUB_ADB_TARDIA ]]; then cat "$fx/dump_um_app.txt"
    else cat "$fx/dump_dois_pacotes.txt"; fi
    echo "  token vazado no dump: $token_falso proj-falso-987" ;;
  *"logcat -v"*)
    echo "10-26 15:00:00.000 1 1 D FirebaseMessaging: Logging to scion event=_nr (de uma rodada anterior)"
    while [[ ! -e "$sb/enviado" ]]; do sleep 0.1; done
    [[ "\${STUB_LOGCAT:-}" == antigo ]] || cat "$fx/logcat_recebida.txt"
    echo "10-26 D FirebaseMessaging: token $token_falso" ;;
  *"svc wifi enable"*) touch "$sb/religada" ;;
  *"svc "*) echo "\$args" >>"$sb/svc" ;;
  *GcmService*)
    # STUB_FCM=nova: depois de religar a rede, a conexão é refeita (connectTime 00:01).
    # Sem isso a conexão é a zumbi da falha real: "connected" com 09:59 de idade.
    if [[ "\${STUB_FCM:-}" == nova && -e "$sb/religada" ]]; then idade=00:01; else idade=09:59; fi
    printf '    connectTime=%s/00:00\n    Heartbeat: alarm(00:31 initial: 600s)\n    Is client connected: true\n' "\$idade"
    for i in \$(seq 1 30); do echo "    17:45.\$i net=1: Received $app_pkg 0:\$i"; done ;;
  *) echo "stub: \$args proj-falso-987" ;;
esac
STUB
chmod +x "$sb/adb"
roda_falha() { # $1 = diretório de saída; demais variáveis vêm do ambiente
  rm -f "$sb/n_dump" "$sb/enviado"
  PATH="$sb:$PATH" PUSH_DIAG_DIR="$1" PUSH_DIAG_TARDIA_S="${TARDIA:-3}" timeout 120 bash -c "
    set -euo pipefail
    source '$repo/scripts/qa/lib_push_diag.sh'
    dev=emulator-5554; app=$app_pkg
    PUSH_DIAG_SEGREDOS=\$'$token_falso\nproj-falso-987'
    diag_iniciar
    diag_iniciar_logcat
    diag_estado_pre_envio
    diag_marca envio; touch '$sb/enviado'; sleep 0.5
    { [[ -z \"\${PRIMEIRA:-}\" ]] && na_bandeja 'SinalACS e2e' 1; } || diag_falhar 'SinalACS e2e' 'título não está na bandeja'
    echo 'não devia chegar aqui'
  " 2>&1
}

d1="$raiz/diag1"; out="$(STUB_ADB_TARDIA=3 roda_falha "$d1")"; rc=$?
afirma "#103 diag_falhar sai com 1 mesmo quando a observação tardia acha o texto" '[[ $rc -eq 1 ]] && grep -q "FALHOU: título não está na bandeja" <<<"$out" && ! grep -q "não devia" <<<"$out"'
afirma "#103 a observação tardia registra a chegada em segundos após o envio" 'grep -qE "^chegada_tardia=[0-9]+$" "$d1/chegada_tardia.txt"'
afirma "#103 a coleta separa o estado na falha do estado após a observação" '[[ "$(cat "$d1/na_falha/classificacao.txt")" == chegou_nao_exibida && "$(cat "$d1/apos_observacao/classificacao.txt")" == exibida_encontrada ]]'
afirma "#103 a coleta grava dumpsys, logcat filtrado, estado pré-envio, conexão FCM e linha do tempo" '[[ -s "$d1/na_falha/dumpsys_notification.txt" && -s "$d1/na_falha/logcat_filtrado.txt" && -s "$d1/estado_pre_envio.txt" && -s "$d1/na_falha/conexao_fcm.txt" && -s "$d1/linha_do_tempo.txt" ]]'
afirma "#103 o estado da conexão FCM traz o status E o fim do histórico" 'grep -q "^uptime_s=" "$d1/estado_pre_envio.txt" && grep -q "Is client connected: true" "$d1/estado_pre_envio.txt" && grep -q "Heartbeat: alarm" "$d1/na_falha/conexao_fcm.txt" && grep -q "Received $app_pkg 0:30" "$d1/na_falha/conexao_fcm.txt"'
afirma "#103 nenhum arquivo de PUSH_DIAG_DIR contém o token do stub, APA91 nem o project_id" '! grep -rqE "APA91|proj-falso-987" "$d1"'

d2="$raiz/diag2"; out="$(STUB_ADB_MODO=falha roda_falha "$d2")"; rc=$?
afirma "#103 coleta com adb que falha (exit 1) preserva o exit 1 e não pendura" '[[ $rc -eq 1 ]] && grep -q "FALHOU: título" <<<"$out" && grep -q "^chegada_tardia=nunca$" "$d2/chegada_tardia.txt"'

# PRIMEIRA=1 pula o na_bandeja: o adb dele não tem timeout (anterior à #103); o que se testa é a coleta.
d3="$raiz/diag3"; inicio=$SECONDS
out="$(STUB_ADB_MODO=pendura DIAG_TIMEOUT_ADB=1 TARDIA=2 PRIMEIRA=1 roda_falha "$d3")"; rc=$?
afirma "#103 coleta com adb que pendura respeita o timeout por chamada" '[[ $rc -eq 1 ]] && (( SECONDS - inicio < 60 ))'

d5="$raiz/diag5"; out="$(STUB_LOGCAT=antigo roda_falha "$d5")"
afirma "#103 marca _nr ANTERIOR ao envio (buffer restaurado do snapshot) não conta como recebida" '[[ "$(cat "$d5/na_falha/classificacao.txt")" == nao_chegou ]]'

d4="$raiz/diag4"; rm -f "$sb/n_dump"; touch "$sb/enviado"
PATH="$sb:$PATH" PUSH_DIAG_DIR="$d4" STUB_ADB_TARDIA=1 bash -c "
  set -euo pipefail; source '$repo/scripts/qa/lib_push_diag.sh'; dev=emulator-5554; app=$app_pkg
  diag_iniciar; diag_iniciar_logcat; diag_estado_pre_envio; diag_marca envio
  na_bandeja 'SinalACS e2e' 2 || diag_falhar 'SinalACS e2e' x; diag_encerrar" >/dev/null 2>&1; rc=$?
afirma "#103 caminho feliz não chama diag_coletar nem cria PUSH_DIAG_DIR" '[[ $rc -eq 0 && ! -e "$d4" ]] && ! grep -qE "^[^#]*diag_coletar" "$repo/scripts/qa/push_e2e.sh"'
afirma "#103 push_e2e.sh não imprime PUSH_DIAG_SEGREDOS" '! grep -nE "(echo|printf)[^#]*PUSH_DIAG_SEGREDOS" "$repo/scripts/qa/push_e2e.sh"'
afirma "#103 push_e2e.sh usa diag_falhar nas esperas da bandeja (nenhum na_bandeja termina em echo FALHOU)" '! grep -E "^na_bandeja .*\|\| \{ echo .FALHOU" "$repo/scripts/qa/push_e2e.sh" && grep -qE "^na_bandeja .*diag_falhar" "$repo/scripts/qa/push_e2e.sh"'

# ---- #103 A-MCS: conexão FCM nova antes do envio ---------------------------------------------------
conexao() { # $1 = espera máxima; imprime a saída e deixa o rc em $sb/rc
  rm -f "$sb/religada" "$sb/svc"
  PATH="$sb:$PATH" PUSH_DIAG_DIR="$2" timeout 60 bash -c "
    set -euo pipefail; source '$repo/scripts/qa/lib_push_diag.sh'; dev=emulator-5554; app=$app_pkg
    PUSH_DIAG_SEGREDOS=\$'$token_falso\nproj-falso-987'
    diag_iniciar; garantir_conexao_fcm $1; diag_marca envio; echo 'enviado'
    cat \"\$diag_tmp/linha_do_tempo.txt\"" 2>&1
}
d6="$raiz/diag6"; out="$(STUB_FCM=nova conexao 10 "$d6")"; rc=$?
afirma "#103 envio espera a conexão FCM nova (rede religada e connectTime menor que o tempo desde a religação)" '[[ $rc -eq 0 ]] && grep -q "^enviado$" <<<"$out" && grep -q "svc wifi disable" "$sb/svc" && grep -qE "conexao_fcm_nova$" <<<"$out"'
d7="$raiz/diag7"; inicio=$SECONDS; out="$(conexao 3 "$d7")"; rc=$?
afirma "#103 conexão que não se renova falha com mensagem própria antes do envio" '[[ $rc -eq 1 ]] && grep -q "FALHOU: GMS sem conexão nova com o FCM" <<<"$out" && ! grep -q "^enviado$" <<<"$out" && (( SECONDS - inicio < 30 ))'
afirma "#103 a falha de conexão deixa o estado do GMS no diagnóstico, sem segredos" 'grep -q "connectTime=09:59" "$d7/sem_conexao_fcm.txt" && ! grep -rqE "APA91|proj-falso-987" "$d7"'
afirma "#103 push_e2e.sh garante a conexão FCM nova antes de cada envio" 'awk "/^[[:space:]]*garantir_conexao_fcm/ {g=1} /diag_marca envio/ { if (!g) bad=1; g=0; n++ } END { exit !(n >= 3 && !bad) }" "$repo/scripts/qa/push_e2e.sh"'

# ---- #103: o app precisa seguir instalado (hold) até o fim da espera da bandeja ------------------
hold() { PATH="$sb:$PATH" PUSH_DIAG_DIR="$raiz/diag_hold" bash -c "
  set -euo pipefail; source '$repo/scripts/qa/lib_push_diag.sh'; dev=emulator-5554; app=$app_pkg
  diag_iniciar; push_hold_fim=\$(( \$(date +%s) + $1 )); exigir_hold $2; echo enviado" 2>&1; }
out="$(hold 100 60)"; rc=$?
afirma "#103 hold com folga para a espera deixa enviar" '[[ $rc -eq 0 ]] && grep -q "^enviado$" <<<"$out"'
out="$(hold 30 60)"; rc=$?
afirma "#103 hold que acaba antes da espera falha com mensagem própria, antes do envio" '[[ $rc -eq 1 ]] && grep -q "FALHOU: o hold do app acaba" <<<"$out" && ! grep -q "^enviado$" <<<"$out"'
afirma "#103 push_e2e.sh confere o hold antes de cada envio" 'awk "/^[[:space:]]*exigir_hold/ {h=1} /diag_marca envio/ { if (!h) bad=1; h=0; n++ } END { exit !(n >= 3 && !bad) }" "$repo/scripts/qa/push_e2e.sh"'

n="$(wc -l <"$marcador")"
echo; [[ "$n" -eq 0 ]] && echo "OK — ci_push_e2e.sh" || { echo "$n asserção(ões) falharam"; exit 1; }
