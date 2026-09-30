#!/usr/bin/env bash
# Testes de decode_secret_file.sh. Sem framework: cada caso roda o script num ambiente
# novo e afirma sobre o que saiu e o que ficou em disco. As credenciais são FALSAS.
set -uo pipefail
cd "$(dirname "$0")/../.."
script="$PWD/scripts/ci/decode_secret_file.sh"
# Cada asserção que falha acrescenta uma linha ao marcador (funciona dentro de subshell).
marcador="$(mktemp)"
raiz="$(mktemp -d)"
trap 'rm -rf "$raiz" "$marcador"' EXIT
FAKE_KEY='FAKE-PRIVATE-KEY-NOT-REAL-0123456789'
PACOTE='br.com.exemplo.app'

sa_json() {
  printf '{"type":"service_account","project_id":"p","client_email":"x@p.iam.gserviceaccount.com","private_key":"%s"}' "$FAKE_KEY"
}
gs_json() {  # $1 = pacote (padrão $PACOTE)
  printf '{"project_info":{"project_id":"fake-proj","api-key-fake":"%s"},"client":[{"client_info":{"android_client_info":{"package_name":"%s"}}}]}' "$FAKE_KEY" "${1:-$PACOTE}"
}

novo_ambiente() {
  T="$(mktemp -d "$raiz/caso.XXXXXX")"   # limpo por inteiro no EXIT (um trap RETURN apagaria já ao sair daqui)
  export RUNNER_TEMP="$T/runner_tmp" GITHUB_ENV="$T/github_env"
  mkdir -p "$RUNNER_TEMP"; : >"$GITHUB_ENV"
  unset GOOGLE_APPLICATION_CREDENTIALS FCM_SECRET GS_SECRET GITHUB_ACTIONS
  DEST="$T/ws/apps/patient/android/app/google-services.json"
}

# $1 descrição; resto: comando de teste (avaliado)
afirma() {
  local desc="$1"; shift
  if eval "$*"; then echo "ok: $desc"; else echo "FALHOU: $desc"; echo x >>"$marcador"; fi
}

sa()  { "$script" --env FCM_SECRET --kind service_account --temp-export GOOGLE_APPLICATION_CREDENTIALS "$@"; }
gs()  { "$script" --env GS_SECRET --kind google_services --to "$DEST" "$@"; }
vazio_em() { [[ -z "$(ls -A "$1" 2>/dev/null)" ]]; }

t_sem_secret_termina_bem_e_nao_cria_nada() {
  novo_ambiente
  out="$(sa 2>&1)"; rc=$?
  afirma "sa sem secret: exit 0 com ::notice" '[[ $rc -eq 0 ]] && grep -q "^::notice" <<<"$out"'
  afirma "sa sem secret: GITHUB_ENV intacto e nenhum arquivo" '[[ ! -s "$GITHUB_ENV" ]] && vazio_em "$RUNNER_TEMP"'
  export GS_SECRET=$' \n\t '
  out="$(gs 2>&1)"; rc=$?
  afirma "gs só de espaços conta como ausente: exit 0, nenhum arquivo" '[[ $rc -eq 0 && ! -e "$DEST" ]]'
}

t_service_account_uma_linha() {
  novo_ambiente
  export FCM_SECRET="$(sa_json | base64 -w0)"
  out="$(sa 2>&1)"; rc=$?
  arq="$(sed -n 's/^GOOGLE_APPLICATION_CREDENTIALS=//p' "$GITHUB_ENV")"
  afirma "sa uma linha: exit 0" '[[ $rc -eq 0 ]]'
  afirma "sa uma linha: arquivo sob RUNNER_TEMP, conteúdo idêntico, modo 600" '[[ -f "$arq" && "$arq" == "$RUNNER_TEMP"/* && "$(cat "$arq")" == "$(sa_json)" && "$(stat -c %a "$arq")" == 600 ]]'
  afirma "sa uma linha: exatamente uma linha em GITHUB_ENV" '[[ "$(wc -l <"$GITHUB_ENV")" -eq 1 ]]'
  afirma "sa uma linha: NADA do conteúdo na saída" '! grep -q "$FAKE_KEY" <<<"$out" && ! grep -q "service_account" <<<"$out"'
}

t_service_account_quebrado_com_crlf() {
  novo_ambiente
  export FCM_SECRET="$(sa_json | base64 | sed 's/$/\r/')  "   # quebra a cada 76 colunas + CRLF + espaços
  out="$(sa 2>&1)"; rc=$?
  arq="$(sed -n 's/^GOOGLE_APPLICATION_CREDENTIALS=//p' "$GITHUB_ENV")"
  afirma "sa quebrado+CRLF: exit 0 e conteúdo idêntico" '[[ $rc -eq 0 && "$(cat "$arq")" == "$(sa_json)" ]]'
}

t_preserva_o_que_ja_estava_em_github_env() {
  novo_ambiente
  echo 'OUTRA=1' >"$GITHUB_ENV"
  export FCM_SECRET="$(sa_json | base64 -w0)"
  sa >/dev/null 2>&1
  afirma "anexa, não sobrescreve" 'grep -qx "OUTRA=1" "$GITHUB_ENV" && grep -q "^GOOGLE_APPLICATION_CREDENTIALS=" "$GITHUB_ENV"'
}

t_service_account_invalido_nao_vaza() {
  novo_ambiente
  for invalido in \
      'isto nao e base64 !!!' \
      "$(printf 'isto nao e json %s' "$FAKE_KEY" | base64 -w0)" \
      "$(printf '{"type":"authorized_user","client_email":"a","private_key":"%s"}' "$FAKE_KEY" | base64 -w0)" \
      "$(printf '{"type":"service_account","client_email":"a"}' | base64 -w0)" \
      "$(printf '[1,2,3]' | base64 -w0)" \
      "$(gs_json | base64 -w0)"; do
    export FCM_SECRET="$invalido"
    out="$(sa 2>&1)"; rc=$?
    afirma "sa inválido (${invalido:0:10}…): exit 1 com ::error" '[[ $rc -eq 1 ]] && grep -q "^::error" <<<"$out"'
    afirma "sa inválido: nada do conteúdo vaza e nenhum traceback do Python" '! grep -q "$FAKE_KEY" <<<"$out" && ! grep -q "isto nao e" <<<"$out" && ! grep -q "Traceback" <<<"$out"'
    afirma "sa inválido: não deixa arquivo nem variável" 'vazio_em "$RUNNER_TEMP" && [[ ! -s "$GITHUB_ENV" ]]'
  done
}

t_google_services_grava_no_destino() {
  novo_ambiente
  export GS_SECRET="$(gs_json | base64 -w0)"
  out="$(gs --package "$PACOTE" 2>&1)"; rc=$?
  afirma "gs: exit 0, arquivo no destino com conteúdo idêntico e modo 600" '[[ $rc -eq 0 && "$(cat "$DEST")" == "$(gs_json)" && "$(stat -c %a "$DEST")" == 600 ]]'
  afirma "gs: não exporta variável e não deixa temporário" '[[ ! -s "$GITHUB_ENV" ]] && vazio_em "$RUNNER_TEMP"'
  afirma "gs: nada do conteúdo na saída" '! grep -q "$FAKE_KEY" <<<"$out" && ! grep -q "fake-proj" <<<"$out"'
}

t_google_services_invalido() {
  novo_ambiente
  for invalido in \
      "$(gs_json 'br.com.OUTRO.app' | base64 -w0)" \
      "$(printf '{"project_info":{"project_id":"x"},"client":[]}' | base64 -w0)" \
      "$(printf '{"client":[{"client_info":{"android_client_info":{"package_name":"%s"}}}]}' "$PACOTE" | base64 -w0)" \
      "$(sa_json | base64 -w0)" \
      'isto nao e base64 !!!'; do
    export GS_SECRET="$invalido"
    out="$(gs --package "$PACOTE" 2>&1)"; rc=$?
    afirma "gs inválido (${invalido:0:10}…): exit 1 e nada gravado" '[[ $rc -eq 1 && ! -e "$DEST" ]] && grep -q "^::error" <<<"$out"'
    afirma "gs inválido: nada do conteúdo vaza" '! grep -q "$FAKE_KEY" <<<"$out" && ! grep -q "fake-proj" <<<"$out"'
  done
}

t_nao_sobrescreve_fora_do_ci() {
  novo_ambiente
  mkdir -p "$(dirname "$DEST")"; echo 'DO-DEV' >"$DEST"
  export GS_SECRET="$(gs_json | base64 -w0)"
  out="$(gs 2>&1)"; rc=$?
  afirma "fora do CI: recusa sobrescrever e preserva o arquivo do dev" '[[ $rc -eq 1 && "$(cat "$DEST")" == "DO-DEV" ]]'
  out="$(GITHUB_ACTIONS=true gs 2>&1)"; rc=$?
  afirma "no CI: sobrescreve" '[[ $rc -eq 0 && "$(cat "$DEST")" == "$(gs_json)" ]]'
}

t_cleanup_temp_apaga_so_sob_runner_temp() {
  novo_ambiente
  export FCM_SECRET="$(sa_json | base64 -w0)"
  sa >/dev/null 2>&1
  export GOOGLE_APPLICATION_CREDENTIALS="$(sed -n 's/^GOOGLE_APPLICATION_CREDENTIALS=//p' "$GITHUB_ENV")"
  "$script" --cleanup-temp GOOGLE_APPLICATION_CREDENTIALS; rc=$?
  afirma "cleanup-temp: exit 0 e arquivo removido" '[[ $rc -eq 0 && ! -e "$GOOGLE_APPLICATION_CREDENTIALS" ]]'
  alheio="$T/alheio.json"; echo x >"$alheio"
  GOOGLE_APPLICATION_CREDENTIALS="$alheio" "$script" --cleanup-temp GOOGLE_APPLICATION_CREDENTIALS
  afirma "cleanup-temp: não apaga arquivo fora do RUNNER_TEMP" '[[ -e "$alheio" ]]'
  unset GOOGLE_APPLICATION_CREDENTIALS
  "$script" --cleanup-temp GOOGLE_APPLICATION_CREDENTIALS; rc=$?
  afirma "cleanup-temp sem variável: exit 0" '[[ $rc -eq 0 ]]'
}

t_cleanup_file_so_no_ci() {
  novo_ambiente
  mkdir -p "$(dirname "$DEST")"; echo 'DO-DEV' >"$DEST"
  "$script" --cleanup-file "$DEST"; rc=$?
  afirma "cleanup-file fora do CI: exit 0 e NÃO apaga" '[[ $rc -eq 0 && -e "$DEST" ]]'
  GITHUB_ACTIONS=true "$script" --cleanup-file "$DEST"; rc=$?
  afirma "cleanup-file no CI: apaga" '[[ $rc -eq 0 && ! -e "$DEST" ]]'
  GITHUB_ACTIONS=true "$script" --cleanup-file "$DEST"; rc=$?
  afirma "cleanup-file de arquivo inexistente: exit 0" '[[ $rc -eq 0 ]]'
}

t_uso_incorreto() {
  novo_ambiente
  "$script" --kind service_account --temp-export X >/dev/null 2>&1; rc=$?
  afirma "sem --env: exit 2" '[[ $rc -eq 2 ]]'
  "$script" --env A --kind service_account >/dev/null 2>&1; rc=$?
  afirma "sem destino: exit 2" '[[ $rc -eq 2 ]]'
  "$script" --env A --kind service_account --temp-export X --to /tmp/y >/dev/null 2>&1; rc=$?
  afirma "os dois destinos: exit 2" '[[ $rc -eq 2 ]]'
  "$script" --env A --kind outro --temp-export X >/dev/null 2>&1; rc=$?
  afirma "kind desconhecido: exit 2" '[[ $rc -eq 2 ]]'
}

t_nao_usa_set_x() {
  afirma "o script não liga set -x (vazaria o secret no log)" '! grep -Eq "^[[:space:]]*set [-+a-z]*x|set -o xtrace" "$script"'
}

t_sem_secret_termina_bem_e_nao_cria_nada
t_service_account_uma_linha
t_service_account_quebrado_com_crlf
t_preserva_o_que_ja_estava_em_github_env
t_service_account_invalido_nao_vaza
t_google_services_grava_no_destino
t_google_services_invalido
t_nao_sobrescreve_fora_do_ci
t_cleanup_temp_apaga_so_sob_runner_temp
t_cleanup_file_so_no_ci
t_uso_incorreto
t_nao_usa_set_x

n="$(wc -l <"$marcador")"
echo; [[ "$n" -eq 0 ]] && echo "OK — decode_secret_file.sh" || { echo "$n asserção(ões) falharam"; exit 1; }
