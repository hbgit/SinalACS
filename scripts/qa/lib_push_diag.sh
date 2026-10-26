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
