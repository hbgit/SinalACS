#!/usr/bin/env bash
#
# Refresh token do ACS amarrado ao Keystore, provado no emulador-5554 (API 30+)
# com o app de verdade, a stack de DESENVOLVIMENTO (docker compose up) e o ACS
# do seed (matrícula ACS-001, senha DEV_ACS_PASSWORD do .env).
#
#   ./scripts/qa/acs_keystore_bound_e2e.sh --pin 1111 [--reinstalar] [--preparar]
#                                          [--nova-digital] [--remover-bloqueio]
#
# Pré-requisitos no emulador: PIN definido e SÓ a digital 1 cadastrada (a 2 é a
# "digital errada"). `--preparar` faz isso sozinho: define o PIN se não houver
# e cadastra a digital 1 pelo Configurações, tocando o sensor com
# `adb emu finger touch 1`.
#
# Casos sempre rodados (cada um com `am force-stop` = partida a frio):
#   1. com token guardado, o diálogo do BiometricPrompt (systemui) aparece ANTES
#      do painel, e o painel não está na tela;
#   2. a digital 1 abre o painel (o token só sai do cofre com o CryptoObject);
#   3. a digital 2 não abre; cancelar volta ao login SEM o aviso de sessão
#      expirada, o blob continua no cofre e a partida seguinte entra com a 1;
#   4. revisor: o app vai ao segundo plano com o desbloqueio aberto (e antes
#      dele abrir); ao voltar, nada fica preso ("Retomando a sessão…" some, o
#      botão de login está habilitado), o blob continua, e a partida seguinte
#      entra com a digital 1.
# Opcionais (mexem no aparelho):
#   --nova-digital      cadastra a digital 2 e abre a frio. Com PIN aceito no
#                       prompt (API 30+, BIOMETRIC_STRONG|DEVICE_CREDENTIAL), o
#                       Keystore NÃO invalida a chave: o prompt abre e a digital
#                       antiga entra. O caso exige só que não haja laço de prompt
#                       e informa qual dos dois desfechos houve. Ao fim a
#                       digital 2 fica cadastrada: rode --preparar depois de
#                       apagá-la à mão (Configurações > Segurança).
#   --remover-bloqueio  remove o PIN (o Android apaga as chaves com autenticação
#                       e as digitais), abre a frio (login sem prompt), põe o PIN
#                       de volta e abre a frio: "Sua sessão expirou. Entre
#                       novamente.", sem prompt, blob apagado. As digitais se
#                       perdem: rode --preparar antes da próxima execução.
#
# Nunca imprime o token nem o blob: só a presença da chave no SharedPreferences.
# A senha do ACS vai ao `input text` pela entrada do `adb shell`, não pelo argv
# do host. Aborta (exit 3) se o app já está instalado: reinstalar APAGA a fila
# offline (SQLCipher) e as chaves do Keystore do app de desenvolvimento.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
export PATH="$PATH:$HOME/Android/Sdk/platform-tools:$HOME/flutter/bin"
if [[ -f .env ]]; then set -a; source .env; set +a; fi
: "${DEV_ACS_PASSWORD:?rode ./scripts/dev/bootstrap_env.sh (DEV_ACS_PASSWORD ausente no .env)}"

dev=emulator-5554
pkg=br.com.prismrr.sinalacs.acs
prefs=shared_prefs/sinalacs_keystore_vault.xml
alias=acs_refresh_token
pin=""
reinstalar=0; preparar=0; nova_digital=0; remover_bloqueio=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pin) pin="${2:?--pin exige um valor}"; shift 2 ;;
    --reinstalar) reinstalar=1; shift ;;
    --preparar) preparar=1; shift ;;
    --nova-digital) nova_digital=1; shift ;;
    --remover-bloqueio) remover_bloqueio=1; shift ;;
    *) echo "argumento desconhecido: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$pin" ]] || { echo 'erro: informe o PIN do emulador com --pin (o Configurações pede ao cadastrar digital).' >&2; exit 2; }
adb -s "$dev" get-state >/dev/null 2>&1 || { echo "emulador $dev não encontrado (adb devices)"; exit 4; }
sdk="$(adb -s "$dev" shell getprop ro.build.version.sdk | tr -d '\r')"
[[ "$sdk" -ge 30 ]] || { echo "erro: API $sdk; este roteiro cobre só API 30+ (CryptoObject com PIN)." >&2; exit 4; }
[[ "$(curl -sk -o /dev/null -w '%{http_code}' https://localhost/ || true)" != 000 ]] \
  || { echo 'erro: a stack de desenvolvimento não responde em https://localhost/ (docker compose up -d).' >&2; exit 4; }

sh_() { adb -s "$dev" shell "$@" | tr -d '\r'; }
xml="$(mktemp)"
instalamos=0
sem_bloqueio=0   # 1 entre o `locksettings clear` e o `set-pin` do --remover-bloqueio
limpar() {
  rm -f "$xml"
  # Falhou com o bloqueio removido: devolve o PIN para não deixar o emulador sem tela travada.
  if [[ "$sem_bloqueio" -eq 1 ]]; then adb -s "$dev" shell locksettings set-pin "$pin" >/dev/null 2>&1 || true; fi
  adb -s "$dev" shell svc power stayon false >/dev/null 2>&1 || true
  if [[ "$instalamos" -eq 1 ]]; then adb -s "$dev" uninstall "$pkg" >/dev/null 2>&1 || true; fi
}
trap limpar EXIT
falha() { echo "FALHOU — $*" >&2; exit 1; }

# --- tela -------------------------------------------------------------------
dump() { sh_ uiautomator dump /sdcard/sinalacs_ui.xml >/dev/null 2>&1 || true; sh_ cat /sdcard/sinalacs_ui.xml >"$xml"; }
tem() { dump; grep -qE "$1" "$xml"; }            # regex sobre o XML inteiro
# Centro do primeiro nó cujo text/content-desc/hint casa com o regex.
centro() {
  python3 - "$1" "$xml" <<'PY'
import re, sys
pat = re.compile(sys.argv[1], re.I)
for n in re.findall(r'<node [^>]*>', open(sys.argv[2], encoding='utf-8').read()):
    attrs = dict(re.findall(r'([\w-]+)="([^"]*)"', n))
    if any(pat.search(attrs.get(k, '')) for k in ('text', 'content-desc', 'hint')):
        a, b, c, d = map(int, re.findall(r'\d+', attrs['bounds']))
        print((a + c) // 2, (b + d) // 2)
        break
PY
}
tocar() { dump; local xy; xy="$(centro "$1")"; [[ -n "$xy" ]] || return 1; sh_ input tap $xy; }
esperar() { # <regex> <segundos>
  local fim=$((SECONDS + $2))
  while (( SECONDS < fim )); do tem "$1" && return 0; sleep 0.5; done
  return 1
}
PROMPT='biometric_prompt_constraint_layout'
PAINEL='Painel operacional'
LOGIN='Entrar com credenciais'
AVISO='Sua sessão expirou'

# Diálogos que não são do app (localização do Google Play Services).
fechar_dialogos() {
  local i
  for i in 1 2 3; do
    tem 'com.google.android.gms|permissioncontroller' || return 0
    tocar '^(No thanks|Não, obrigado|While using the app|Durante o uso do app)$' || return 0
    sleep 1
  done
}
abrir_a_frio() {
  sh_ am force-stop "$pkg"
  sh_ monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
}
blob_presente() { sh_ run-as "$pkg" cat "$prefs" 2>/dev/null | grep -q "name=\"$alias\""; }
painel_aberto() { esperar "$PAINEL" 15 || { fechar_dialogos; esperar "$PAINEL" 5; }; }
desbloquear_tela() {
  sh_ svc power stayon true >/dev/null
  sh_ input keyevent 224 >/dev/null # WAKEUP
  if sh_ dumpsys window | grep -q 'mIsShowing=true'; then
    sh_ wm dismiss-keyguard >/dev/null 2>&1 || true; sleep 1
    printf 'input text %s\ninput keyevent 66\nexit\n' "$pin" | adb -s "$dev" shell >/dev/null
    sleep 1
  fi
}
num_digitais() { sh_ dumpsys fingerprint | grep -o '"count":[0-9]*' | head -1 | cut -d: -f2; }

# Cadastra a digital <id> pelo Configurações (só sensor virtual do emulador).
cadastrar_digital() {
  sh_ am force-stop com.android.settings # senão o intent só traz a tarefa antiga à frente
  sh_ am start -a android.settings.FINGERPRINT_ENROLL >/dev/null
  esperar 'password_entry|PIN' 10 || falha 'o cadastro de digital não pediu o PIN'
  printf 'input text %s\ninput keyevent 66\nexit\n' "$pin" | adb -s "$dev" shell >/dev/null
  esperar 'I AGREE|ACEITO|MORE|MAIS' 10 || falha 'o cadastro de digital não abriu'
  local i
  for i in 1 2 3 4 5; do tocar '^(MORE|MAIS)$' || break; sleep 1; done
  tocar '^(I AGREE|ACEITO|CONCORDO)$' || falha 'botão de aceite do cadastro não encontrado'
  esperar 'Touch the sensor|Toque no sensor|sensor' 10 || true
  for i in $(seq 1 15); do
    adb -s "$dev" emu finger touch "$1" >/dev/null
    sleep 1.2
    tem 'Fingerprint added|Impressão digital adicionada' && break
  done
  tem 'Fingerprint added|Impressão digital adicionada' || falha "a digital $1 não foi cadastrada"
  tocar '^(DONE|CONCLUÍDO|OK)$' || true
}

# --- preparo do aparelho ----------------------------------------------------
desbloquear_tela
if [[ "$preparar" -eq 1 ]]; then
  if [[ "$(sh_ locksettings get-disabled)" == true ]] || sh_ locksettings verify | grep -q 'successfully'; then
    sh_ locksettings set-pin "$pin" >/dev/null
  fi
  [[ "$(num_digitais)" -ge 1 ]] || cadastrar_digital 1
  sh_ input keyevent 3
fi
sh_ locksettings verify --old "$pin" | grep -q successfully || falha "o PIN informado não confere com o do emulador"
[[ "$(num_digitais)" -eq 1 ]] \
  || falha "o emulador precisa de exatamente 1 digital (a 1); tem $(num_digitais). Use --preparar (e apague as outras à mão)."

# --- app --------------------------------------------------------------------
instalado() { sh_ pm list packages "$pkg" | grep -q "^package:$pkg\$"; }
if instalado && [[ "$reinstalar" -eq 0 ]]; then
  echo "erro: $pkg já está instalado em $dev; reinstalar APAGA a fila offline e as chaves do Keystore." >&2
  echo "      Se for só o app de teste de uma execução anterior, rode com --reinstalar." >&2
  exit 3
fi
build_log="$(mktemp)"
if ! ./scripts/dev/run_acs.sh --build >"$build_log" 2>&1; then
  echo 'erro: o build do APK falhou. Últimas linhas:' >&2; tail -n 30 "$build_log" >&2; rm -f "$build_log"; exit 1
fi
rm -f "$build_log"
if instalado; then adb -s "$dev" uninstall "$pkg" >/dev/null 2>&1 || true; fi
adb -s "$dev" install -r apps/acs/build/app/outputs/flutter-apk/app-debug.apk >/dev/null
instalamos=1
# Permissão em runtime concedida antes: o diálogo do sistema não cobre o painel.
sh_ pm grant "$pkg" android.permission.ACCESS_FINE_LOCATION >/dev/null 2>&1 || true
sh_ pm grant "$pkg" android.permission.ACCESS_COARSE_LOCATION >/dev/null 2>&1 || true

echo '== login completo (matrícula + senha) sela o refresh token no cofre'
abrir_a_frio
esperar "$LOGIN" 20 || falha 'a tela de login não apareceu'
tem "$PROMPT" && falha 'prompt biométrico sem token guardado'
tocar 'Matrícula' || falha 'campo matrícula não encontrado'; sleep 0.3
sh_ input text ACS-001
tocar 'Senha de acesso' || falha 'campo senha não encontrado'; sleep 0.3
printf 'input text %s\nexit\n' "$DEV_ACS_PASSWORD" | adb -s "$dev" shell >/dev/null
sh_ input keyevent 111 # fecha o teclado
tocar "$LOGIN" || falha 'botão de login não encontrado'
painel_aberto || falha 'o painel não abriu depois do login'
blob_presente || falha 'o login não deixou blob no cofre (o token ficou só em RAM?)'
echo '  OK — painel aberto e blob no cofre'

echo '== caso 1: partida a frio pede o prompt do cofre antes do painel'
abrir_a_frio
esperar "$PROMPT" 15 || falha 'o BiometricPrompt não apareceu na partida a frio'
tem "$PAINEL" && falha 'o painel está na tela junto com o prompt'
echo '  OK — prompt do sistema aberto, painel ausente'

echo '== caso 2: a digital cadastrada abre o painel'
adb -s "$dev" emu finger touch 1 >/dev/null
painel_aberto || falha 'a digital 1 não abriu o painel'
echo '  OK — painel aberto com a digital 1'

echo '== caso 3: digital errada não entra; cancelar mantém o token'
abrir_a_frio
esperar "$PROMPT" 15 || falha 'o prompt não apareceu'
adb -s "$dev" emu finger touch 2 >/dev/null
sleep 2
tem "$PAINEL" && falha 'a digital 2 (não cadastrada) abriu o painel'
tem "$PROMPT" || falha 'o prompt fechou sozinho depois da digital errada'
sh_ input keyevent 4 # voltar = cancelar
esperar "$LOGIN" 10 || falha 'cancelar não voltou ao login'
tem "$AVISO" && falha 'cancelar mostrou "sessão expirou" (o token não devia ter sido apagado)'
blob_presente || falha 'cancelar apagou o blob'
abrir_a_frio
esperar "$PROMPT" 15 || falha 'a segunda partida não pediu o prompt'
adb -s "$dev" emu finger touch 1 >/dev/null
painel_aberto || falha 'a segunda tentativa (digital 1) não entrou'
echo '  OK — digital 2 recusada, cancelar mantém o blob, segunda partida entra'

echo '== caso 4 (revisor): segundo plano com o desbloqueio aberto'
for quando in prompt-aberto antes-do-prompt; do
  abrir_a_frio
  if [[ "$quando" == prompt-aberto ]]; then
    esperar "$PROMPT" 15 || falha 'o prompt não apareceu'
  else
    sleep 0.8
  fi
  sh_ input keyevent 3 # HOME
  sleep 3
  sh_ monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  sleep 3
  # Ou o prompt segue/reabre (dá para tentar), ou o login está livre.
  if tem "$PROMPT"; then
    adb -s "$dev" emu finger touch 1 >/dev/null
    painel_aberto || falha "($quando) o prompt na volta não abriu o painel"
    echo "  $quando: o prompt seguiu aberto na volta e a digital 1 entrou"
    continue
  fi
  esperar "$LOGIN" 10 || falha "($quando) a volta não mostrou nem prompt nem login"
  tem 'Retomando a sessão' && falha "($quando) 'Retomando a sessão…' ficou preso"
  grep -o '<node[^>]*Entrar com credenciais[^>]*>' "$xml" | grep -q 'enabled="true"' \
    || falha "($quando) o botão de login ficou desabilitado (retomada presa)"
  blob_presente || falha "($quando) o blob foi apagado"
  abrir_a_frio
  esperar "$PROMPT" 15 || falha "($quando) a partida seguinte não pediu o prompt"
  adb -s "$dev" emu finger touch 1 >/dev/null
  painel_aberto || falha "($quando) a partida seguinte não entrou"
  echo "  $quando: voltou ao login livre, blob mantido, a partida seguinte entrou"
done
echo '  OK — nada travou'

if [[ "$nova_digital" -eq 1 ]]; then
  echo '== opcional: nova digital cadastrada'
  sh_ am force-stop "$pkg"
  cadastrar_digital 2
  abrir_a_frio
  if esperar "$PROMPT" 10; then
    adb -s "$dev" emu finger touch 1 >/dev/null
    painel_aberto || falha 'nova digital: prompt abriu mas a digital antiga não entrou (laço?)'
    echo '  OBSERVADO — chave NÃO invalidada pela nova digital (PIN aceito no prompt); a digital antiga entra'
  else
    esperar "$AVISO" 5 || falha 'nova digital: nem prompt nem o aviso de sessão expirada'
    blob_presente && falha 'nova digital: aviso mostrado mas o blob ficou'
    echo '  OBSERVADO — chave invalidada: login completo com o aviso, sem prompt'
  fi
fi

if [[ "$remover_bloqueio" -eq 1 ]]; then
  echo '== opcional: remover o bloqueio de tela invalida a chave'
  sh_ am force-stop "$pkg"
  sh_ locksettings clear --old "$pin" >/dev/null
  sem_bloqueio=1
  abrir_a_frio
  esperar "$LOGIN" 15 || falha 'sem bloqueio: o login não apareceu'
  tem "$PROMPT" && falha 'sem bloqueio: abriu prompt'
  sh_ locksettings set-pin "$pin" >/dev/null
  sem_bloqueio=0
  abrir_a_frio
  esperar "$AVISO" 15 || falha 'PIN novo: o aviso "Sua sessão expirou" não apareceu'
  tem "$PROMPT" && falha 'PIN novo: abriu prompt (laço)'
  blob_presente && falha 'PIN novo: o blob morto ficou no cofre'
  echo '  OK — chave apagada pelo Android: aviso, sem prompt, blob removido (digitais perdidas: rode --preparar)'
fi

echo 'OK — refresh token do ACS amarrado ao Keystore no emulador'
