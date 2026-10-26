# Diagnóstico do push e2e quando o aviso não chega à bandeja (issue #103).
# Uso: source "$(dirname "${BASH_SOURCE[0]}")/lib_push_diag.sh"
#
# Os artefatos da CI são públicos: tudo o que a coleta grava passa por diag_redigir e depois por
# diag_verificar_limpo, que APAGA o arquivo se ainda achar um segredo (fail-closed).
# PUSH_DIAG_SEGREDOS: um literal por linha (token FCM, project_id, project_number). Nunca impresso.

# Marcas medidas no AVD igual ao da CI (docs/superpowers/plans/2026-10-26-issue-103-assinaturas.md).
# "service received new intent" NÃO serve: também sai no onNewToken do registro.
DIAG_MARCA_RECEBIDA='FirebaseMessaging: Logging to scion event=_nr'
DIAG_MARCA_POSTADA='NotificationListener: received notification posted event - br.com.prismrr.sinalacs.patient'
DIAG_CMD_CONEXAO_FCM='dumpsys activity service com.google.android.gms/.gcm.GcmService'
DIAG_REGEX_TOKEN='[A-Za-z0-9_-]{11,}:APA91[A-Za-z0-9_-]{30,}'

# stdin -> stdout: troca cada literal de PUSH_DIAG_SEGREDOS por <redigido> e o formato de token FCM
# por <token-fcm>. Literal por index() e não por sed: o segredo pode ter caracteres especiais.
diag_redigir() {
  awk -v segredos="${PUSH_DIAG_SEGREDOS:-}" '
    BEGIN { n = split(segredos, s, "\n") }
    {
      for (i = 1; i <= n; i++) {
        if (s[i] == "") continue
        saida = ""; resto = $0
        while ((p = index(resto, s[i])) > 0) {
          saida = saida substr(resto, 1, p - 1) "<redigido>"
          resto = substr(resto, p + length(s[i]))
        }
        $0 = saida resto
      }
      print
    }' | sed -E "s/$DIAG_REGEX_TOKEN/<token-fcm>/g"
}

# 0 se o arquivo está limpo. Senão o apaga, deixa <arquivo>.REMOVIDO com o motivo (sem o segredo)
# e retorna 1.
diag_verificar_limpo() {
  local arq="$1" motivo=""
  [[ -f "$arq" ]] || return 0
  if grep -q 'APA91' "$arq"; then
    motivo='algo no formato de token FCM'
  elif [[ -n "${PUSH_DIAG_SEGREDOS:-}" ]] && grep -qF -f <(grep -v '^$' <<<"$PUSH_DIAG_SEGREDOS") "$arq"; then
    motivo='literal de PUSH_DIAG_SEGREDOS'
  fi
  [[ -z "$motivo" ]] && return 0
  rm -f "$arq"
  echo "removido antes da publicação: ainda continha $motivo depois da redação" >"$arq.REMOVIDO"
  return 1
}

# Só os NotificationRecord cujo cabeçalho é do pacote $2 (um registro vai de uma linha
# "NotificationRecord(" até a próxima).
diag_bloco_do_app() {
  awk -v alvo="pkg=$2 " '/NotificationRecord\(/ { dentro = index($0, alvo) > 0 } dentro' "$1"
}

# Imprime um de: exibida_encontrada | exibida_nao_encontrada | chegou_nao_exibida | nao_chegou.
# "encontrada" = o que a busca de na_bandeja (grep -A30 "pkg=$app" no push_e2e.sh) acharia.
diag_classificar() {
  local dump="$1" logcat="$2" pkg="$3" texto="$4"
  if diag_bloco_do_app "$dump" "$pkg" | grep -qF -- "$texto"; then
    if grep -A30 "pkg=$pkg" "$dump" | grep -qF -- "$texto"; then
      echo exibida_encontrada
    else
      echo exibida_nao_encontrada
    fi
  elif grep -qF -- "$DIAG_MARCA_RECEBIDA" "$logcat" 2>/dev/null; then
    echo chegou_nao_exibida
  else
    echo nao_chegou
  fi
}

# ---- coleta no aparelho -------------------------------------------------------------------------
# Usa $dev e $app de quem faz o source. Nada vai para PUSH_DIAG_DIR no caminho verde: o logcat, o
# estado pré-envio e a linha do tempo ficam num diretório temporário até diag_falhar copiá-los.
# Cada adb da coleta tem timeout (DIAG_TIMEOUT_ADB, padrão 20 s) e nunca derruba quem chamou.
diag_tmp=""
diag_logcat_pid=""
diag_t_envio=""
# Linhas do logcat já lidas no envio: o buffer (restaurado com o snapshot do AVD) traz marcas de
# rodadas anteriores, e só o que vem depois do envio diz se ESTA mensagem chegou.
diag_logcat_corte=0

_diag_adb() { timeout "${DIAG_TIMEOUT_ADB:-20}" adb -s "$dev" "$@" 2>/dev/null; }

diag_iniciar() { diag_tmp="$(mktemp -d)"; : >"$diag_tmp/linha_do_tempo.txt"; }

diag_encerrar() {
  [[ -n "$diag_logcat_pid" ]] && { kill "$diag_logcat_pid" 2>/dev/null || true; }
  diag_logcat_pid=""
  [[ -n "$diag_tmp" ]] && rm -rf "$diag_tmp"
  diag_tmp=""
  return 0
}

diag_marca() { # $1 = evento; "envio" também zera o relógio da chegada tardia
  echo "$(date +%s.%N) $1" >>"$diag_tmp/linha_do_tempo.txt"
  if [[ "$1" == envio ]]; then
    diag_t_envio="$(date +%s)"
    diag_logcat_corte="$(wc -l <"$diag_tmp/logcat_bruto" 2>/dev/null || echo 0)"
  fi
  return 0
}

diag_iniciar_logcat() {
  _diag_adb logcat -G 16M >/dev/null || true
  _diag_adb shell setprop log.tag.FirebaseMessaging VERBOSE >/dev/null || true
  adb -s "$dev" logcat -v threadtime >"$diag_tmp/logcat_bruto" 2>/dev/null &
  diag_logcat_pid=$!
}

_diag_conexao_fcm() { # status atual + fim do histórico (Received/Successful broadcast = chegou ao GMS)
  local saida
  saida="$(_diag_adb shell "$DIAG_CMD_CONEXAO_FCM" || true)"
  grep -E 'Is client connected|connectTime=|Heartbeat: alarm|Reconnect Scheduler' <<<"$saida" | head -8
  grep -E 'net=[0-9-]+: ' <<<"$saida" | tail -20
  return 0
}

diag_estado_pre_envio() {
  {
    echo "== $(date -u +%FT%TZ)"
    echo "== permissão e estado do pacote"
    _diag_adb shell dumpsys package "$app" | grep -E 'POST_NOTIFICATIONS|stopped=' | sed 's/flags=.*//'
    echo "bucket=$(_diag_adb shell am get-standby-bucket "$app")"
    _diag_adb shell pm list packages "$app"
    echo "== atividade em foco"
    _diag_adb shell dumpsys activity activities | grep -E 'topResumedActivity|mResumedActivity' | head -2
    echo "== doze"
    _diag_adb shell dumpsys deviceidle | grep -E 'mState=|mLightState=' | head -2
    echo "== conexão FCM (GMS): connectTime maior que o uptime = conexão restaurada do snapshot"
    echo "uptime_s=$(_diag_adb shell cat /proc/uptime | cut -d' ' -f1)"
    _diag_conexao_fcm
    echo "== imagem"
    echo "fingerprint=$(_diag_adb shell getprop ro.build.fingerprint)"
    echo "gms=$(_diag_adb shell dumpsys package com.google.android.gms | grep -m1 versionName)"
    echo "AVD_CACHE_KEY=${AVD_CACHE_KEY:-} AVD_CACHE_HIT=${AVD_CACHE_HIT:-}"
  } >"$diag_tmp/estado_pre_envio.txt" 2>&1 || true
}

_diag_publicar() { # $1 = arquivo de destino; stdin = conteúdo bruto
  diag_redigir >"$1"
  diag_verificar_limpo "$1" || true
}

diag_coletar() { # $1 = texto esperado na bandeja; $2 = rótulo (subdiretório)
  local d="$PUSH_DIAG_DIR/$2" dump="$diag_tmp/dump_$2" pid filtro
  mkdir -p "$d"
  _diag_adb shell dumpsys notification --noredact >"$dump" || true
  _diag_publicar "$d/dumpsys_notification.txt" <"$dump"
  grep -A60 "AppSettings: $app" "$dump" | _diag_publicar "$d/canais_do_app.txt"
  _diag_conexao_fcm | _diag_publicar "$d/conexao_fcm.txt"
  pid="$(_diag_adb shell pidof "$app" | tr -d '\r')"
  filtro="FirebaseMessaging|FCM|GCM|NotificationService|NotificationListener|com\.google\.android\.gms|$app"
  [[ -n "$pid" ]] && filtro="$filtro| $pid "
  grep -E "$filtro" "$diag_tmp/logcat_bruto" 2>/dev/null | _diag_publicar "$d/logcat_filtrado.txt"
  tail -200 "${PUSH_DIAG_HOLD_LOG:-/tmp/push_e2e_hold.txt}" 2>/dev/null | _diag_publicar "$d/hold_tail.txt"
  tail -n +$(( diag_logcat_corte + 1 )) "$diag_tmp/logcat_bruto" >"$diag_tmp/logcat_pos_envio" 2>/dev/null || true
  diag_classificar "$dump" "$diag_tmp/logcat_pos_envio" "$app" "$1" >"$d/classificacao.txt"
  _diag_publicar "$PUSH_DIAG_DIR/estado_pre_envio.txt" <"$diag_tmp/estado_pre_envio.txt"
  _diag_publicar "$PUSH_DIAG_DIR/linha_do_tempo.txt" <"$diag_tmp/linha_do_tempo.txt"
  return 0
}

# SÓ diagnóstico: se o texto aparecer depois da falha, o script sai com 1 do mesmo jeito.
diag_observar_tardia() { # $1 = texto; $2 = segundos
  local fim=$(( SECONDS + $2 )) dump res=nunca
  while (( SECONDS < fim )); do
    dump="$(_diag_adb shell dumpsys notification --noredact || true)"
    if grep -A30 "pkg=$app" <<<"$dump" | grep -qF -- "$1"; then
      res=$(( $(date +%s) - ${diag_t_envio:-$(date +%s)} )); break
    fi
    sleep 1
  done
  echo "chegada_tardia=$res" >"$PUSH_DIAG_DIR/chegada_tardia.txt"
}

diag_falhar() { # $1 = texto esperado; $2 = mensagem. Coleta, observa, coleta de novo e sai com 1.
  { diag_coletar "$1" na_falha
    diag_observar_tardia "$1" "${PUSH_DIAG_TARDIA_S:-180}"
    diag_coletar "$1" apos_observacao; } || true
  echo "FALHOU: $2"
  echo "diagnóstico em $PUSH_DIAG_DIR: na falha=$(cat "$PUSH_DIAG_DIR/na_falha/classificacao.txt" 2>/dev/null)," \
    "$(cat "$PUSH_DIAG_DIR/chegada_tardia.txt" 2>/dev/null)"
  diag_encerrar
  exit 1
}

# A entrega pelo FCM leva de 1 a dezenas de segundos: espera o texto aparecer em vez de
# dormir um tempo fixo (um `sleep` curto é uma corrida com a rede do emulador).
na_bandeja() { # $1 = texto que deve estar na bandeja do app; $2 = espera máxima em s (padrão 45)
  local _ dump
  for _ in $(seq 1 "${2:-45}"); do
    # Captura antes de filtrar: `grep -q` fecha o pipe no 1º achado, e sob `pipefail` o
    # SIGPIPE do `grep -A` viraria um "não achou" falso.
    dump="$(adb -s "$dev" shell dumpsys notification --noredact 2>/dev/null || true)"
    grep -A30 "pkg=$app" <<<"$dump" | grep -q "$1" && return 0
    sleep 1
  done
  return 1
}
