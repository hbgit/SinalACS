#!/usr/bin/env bash
# O guarda do workflow precisa pegar as regressões das credenciais do FCM e do emulador.
set -uo pipefail
cd "$(dirname "$0")/../.."
orig=.github/workflows/ci.yml
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
marcador="$tmp/falhas"; : >"$marcador"

roda() { CI_WORKFLOW_PATH="$1" ./scripts/qa/ci_invariants.sh 2>&1; }
afirma() { if eval "$2"; then echo "ok: $1"; else echo "FALHOU: $1"; echo x >>"$marcador"; fi; }

# mutação: $1 nome, $2 expressão python em `t` (o texto do ci.yml) que devolve o novo texto
muta() {
  local nome="$1" codigo="$2" alvo="$tmp/$1.yml"
  python3 - "$orig" "$alvo" <<PY
import sys
t = open(sys.argv[1], encoding='utf-8').read()
novo = (lambda t: $codigo)(t)
assert novo != t, 'a mutação não mudou nada (o texto esperado mudou no ci.yml?)'
open(sys.argv[2], 'w', encoding='utf-8').write(novo)
PY
  out="$(roda "$alvo")"; rc=$?
  afirma "$nome: o guarda reprova" '[[ $rc -ne 0 ]]'
  afirma "$nome: a falha cita o FCM" 'grep -q "FCM" <<<"$out"'
}

out="$(roda "$orig")"; rc=$?
afirma "workflow intacto passa" '[[ $rc -eq 0 ]]'

muta fcm_sem_env_do_passo \
  "t.replace('          FCM_CREDENTIALS_BASE64: \${{ secrets.FCM_CREDENTIALS_BASE64 }}\n', '', 1)"
muta gs_sem_env_do_passo \
  "t.replace('          GOOGLE_SERVICES_JSON_BASE64: \${{ secrets.GOOGLE_SERVICES_JSON_BASE64 }}\n', '', 1)"
muta fcm_dentro_do_run \
  "t.replace('--env FCM_CREDENTIALS_BASE64', '--env X_\${{ secrets.FCM_CREDENTIALS_BASE64 }}', 1)"
muta gs_dentro_do_run \
  "t.replace('--env GOOGLE_SERVICES_JSON_BASE64', '--env X_\${{ secrets.GOOGLE_SERVICES_JSON_BASE64 }}', 1)"
muta fcm_no_env_do_job \
  "t.replace('      GOOGLE_MAPS_API_KEY: \${{ secrets.GOOGLE_MAPS_API_KEY }}\n', '      GOOGLE_MAPS_API_KEY: \${{ secrets.GOOGLE_MAPS_API_KEY }}\n      FCM_CREDENTIALS_BASE64: \${{ secrets.FCM_CREDENTIALS_BASE64 }}\n', 1)"
muta gs_no_env_do_job \
  "t.replace('      GOOGLE_MAPS_API_KEY: \${{ secrets.GOOGLE_MAPS_API_KEY }}\n', '      GOOGLE_MAPS_API_KEY: \${{ secrets.GOOGLE_MAPS_API_KEY }}\n      GOOGLE_SERVICES_JSON_BASE64: \${{ secrets.GOOGLE_SERVICES_JSON_BASE64 }}\n', 1)"
muta limpeza_sem_always \
  "t.replace('        if: always()\n        run: |\n          ./scripts/ci/decode_secret_file.sh --cleanup-temp', '        run: |\n          ./scripts/ci/decode_secret_file.sh --cleanup-temp', 1)"
muta limpeza_sem_google_services \
  "t.replace('--cleanup-file apps/patient/android/app/google-services.json', 'true', 1)"
muta limpeza_sem_chave_do_gorush \
  "t.replace('--cleanup-file infra/docker/gorush/credentials/fcm-service-account.json', 'true', 1)"
muta decodifica_depois_do_e2e \
  "(lambda m: t.replace(m.group(0), '', 1).replace('      # Apaga as credenciais mesmo se o E2E falhar', m.group(0) + '      # Apaga as credenciais mesmo se o E2E falhar', 1))(__import__('re').search(r'      # Credenciais do FCM para o push e2e.*?(?=      - name: E2E no emulador Android)', t, __import__('re').S))"
muta limpeza_antes_do_e2e \
  "(lambda m: t.replace(m.group(0), '', 1).replace('      - name: E2E no emulador Android\n', m.group(0) + '      - name: E2E no emulador Android\n', 1))(__import__('re').search(r'      # Apaga as credenciais mesmo se o E2E falhar.*?(?=      - name: Remove pg_data)', t, __import__('re').S))"
muta passo_do_e2e_renomeado \
  "t.replace('      - name: E2E no emulador Android\n', '      - name: Android E2E\n', 1)"
muta secret_no_env_do_workflow \
  "t.replace('\njobs:\n', '\nenv:\n  VAZA: \${{ secrets.FCM_CREDENTIALS_BASE64 }}\njobs:\n', 1)"
muta secret_em_with_de_acao \
  "t.replace('          name: android-e2e-metrics\n', '          name: android-e2e-metrics\n          token: \${{ secrets.GOOGLE_SERVICES_JSON_BASE64 }}\n', 1)"
muta secret_por_tojson \
  "t.replace('          name: android-e2e-metrics\n', '          name: android-e2e-metrics\n          token: \${{ toJSON(secrets) }}\n', 1)"
muta secret_por_colchetes \
  "t.replace('          name: android-e2e-metrics\n', '          name: android-e2e-metrics\n          token: \${{ secrets[\'FCM_CREDENTIALS_BASE64\'] }}\n', 1)"
muta secret_no_env_de_outro_passo \
  "t.replace('      - name: Remove pg_data/ do workspace\n', '      - name: Remove pg_data/ do workspace\n        env:\n          OUTRO: \${{ secrets.GOOGLE_SERVICES_JSON_BASE64 }}\n', 1)"
muta credencial_em_disco_durante_acao_de_terceiros \
  "t.replace('      - name: E2E no emulador Android\n', '      - uses: actions/setup-java@v6\n      - name: E2E no emulador Android\n', 1)"
muta emulador_sem_play_services \
  "t.replace('          target: google_apis\n', '', 1)"
muta cache_do_avd_sem_o_target \
  "t.replace('avd-36-google_apis-x86_64-pixel_7-ubuntu-24.04', 'avd-36-x86_64-pixel_7-ubuntu-24.04', 1)"

n="$(wc -l <"$marcador")"
echo; [[ "$n" -eq 0 ]] && echo "OK — invariantes das credenciais do FCM" || { echo "$n asserção(ões) falharam"; exit 1; }
