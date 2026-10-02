#!/usr/bin/env bash
# Teste hermético de scripts/qa/acs_gps_e2e.sh: adb e flutter FALSOS no PATH.
# Não precisa de emulador, de Docker nem do .env (a senha vai pelo ambiente).
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin"
export FAKE_LOG="$tmp/chamadas.log"

cat >"$tmp/bin/adb" <<'FIM'
#!/usr/bin/env bash
echo "adb $*" >>"$FAKE_LOG"
case "$*" in
  *get-state*) echo device ;;
  *"pm list packages"*) [[ "${FAKE_INSTALADO:-0}" == 1 ]] && echo "package:br.com.prismrr.sinalacs.acs" ;;
  *uiautomator*)
    if [[ "${FAKE_DIALOGO_TOQUES:-0}" == 1 ]]; then
      n="$(cat "$FAKE_LOG.dumps" 2>/dev/null || echo 0)"
      if [[ -z "${FAKE_DIALOGO_LIMITE:-}" || "$n" -lt "$FAKE_DIALOGO_LIMITE" ]]; then
        echo $((n + 1)) >"$FAKE_LOG.dumps"
        echo '<node resource-id="com.android.permissioncontroller:id/permission_deny_button" bounds="[0,0][10,10]" />'
      fi
    fi ;;
  *"dumpsys window"*) [[ "${FAKE_DIALOGO:-0}" == 1 ]] && echo "mCurrentFocus=Window{1 u0 com.google.android.permissioncontroller/x.GrantPermissionsActivity}" ;;
esac
exit 0
FIM
cat >"$tmp/bin/flutter" <<'FIM'
#!/usr/bin/env bash
echo "flutter $*" >>"$FAKE_LOG"
case "$1" in
  build) [[ "${FAKE_BUILD_FALHA:-0}" == 1 ]] && { echo "ERRO-FALSO-DO-GRADLE: sem espaço" >&2; exit 1; } ;;
  drive) [[ "${FAKE_DRIVE_FALHA:-0}" == 1 ]] && exit 1
         [[ "${FAKE_DRIVE_TRAVA:-0}" == 1 ]] && sleep 30
         [[ -n "${FAKE_DRIVE_DEMORA:-}" ]] && sleep "$FAKE_DRIVE_DEMORA" ;;
esac
exit 0
FIM
chmod +x "$tmp/bin/"*

falhas=0
caso() { # caso <nome> [VAR=valor ...] -- [args do script]
  nome=$1; shift
  envs=(); while [[ $# -gt 0 && $1 != -- ]]; do envs+=("$1"); shift; done; shift
  : >"$FAKE_LOG"; rm -rf "$tmp/t" "$FAKE_LOG.dumps"; mkdir "$tmp/t"
  saida="$(env PATH="$tmp/bin:$PATH" TMPDIR="$tmp/t" GPS_E2E_INTERVALO=0.1 MQTT_ACS_PASSWORD=x "${envs[@]}" ./scripts/qa/acs_gps_e2e.sh "$@" 2>&1)"; codigo=$?
}
verifica() { eval "$1" || { echo "FALHOU [$nome]: $1"; echo "$saida" | tail -4; falhas=$((falhas + 1)); }; }
conta() { grep -c "$1" "$FAKE_LOG" || true; }

caso guarda FAKE_INSTALADO=1 --
verifica '[[ $codigo -eq 3 ]]'
verifica 'grep -q "APAGA" <<<"$saida"'
verifica '[[ $(conta uninstall) -eq 0 ]]'
verifica '[[ $(conta "^flutter build") -eq 0 ]]'

caso build_falha FAKE_BUILD_FALHA=1 --
verifica '[[ $codigo -ne 0 ]]'
verifica 'grep -q "o build do APK falhou" <<<"$saida"'
verifica 'grep -q "ERRO-FALSO-DO-GRADLE" <<<"$saida"'
verifica '[[ $(conta "install -r") -eq 0 ]]'

caso reinstalar FAKE_INSTALADO=1 -- --reinstalar
verifica '[[ $codigo -eq 0 ]]'
verifica '[[ $(conta uninstall) -eq 2 ]]'   # antes de instalar e ao sair

caso drive_falha FAKE_DRIVE_FALHA=1 --
verifica '[[ $codigo -ne 0 ]]'
verifica '[[ $(conta uninstall) -eq 1 ]]'   # o app de teste não fica para a próxima rodada

caso ok --
verifica '[[ $codigo -eq 0 ]]'
verifica 'grep -q "fix de GPS não verificado" <<<"$saida"'

caso argumento_invalido -- --nao-existe
verifica '[[ $codigo -eq 2 ]]'

caso dialogo FAKE_DIALOGO=1 --
verifica '[[ $codigo -ne 0 ]]'
verifica 'grep -q "diálogo de permissão" <<<"$saida"'

caso sem_permissao --  --sem-permissao
verifica '[[ $codigo -eq 0 ]]'
verifica '[[ $(conta "pm revoke") -eq 2 ]]'
verifica 'grep -q "^flutter build .*EXPECT_PERMISSION=denied_forever" "$FAKE_LOG"'   # o define vale só no build
verifica '! grep "^flutter drive" "$FAKE_LOG" | grep -q EXPECT_PERMISSION'          # o drive não o repete
verifica '[[ $(conta "^flutter drive") -eq 1 ]]'   # uma rodada só: o teste fixa a negação sozinho
verifica '[[ -z "$(ls -A "$tmp/t")" ]]'            # nenhum temporário sobra

caso toques_ok FAKE_DIALOGO_TOQUES=1 FAKE_DIALOGO_LIMITE=2 FAKE_DRIVE_DEMORA=2 -- --sem-permissao
verifica '[[ $codigo -eq 0 ]]'
verifica '[[ $(conta "input tap") -eq 2 ]]'        # exatamente o teto: passa

caso toques_demais FAKE_DIALOGO_TOQUES=1 FAKE_DRIVE_DEMORA=2 -- --sem-permissao
verifica '[[ $codigo -eq 1 ]]'
verifica '[[ $(conta "input tap") -gt 2 ]]'        # o caminho de >2 foi exercitado de verdade
verifica 'grep -q "mais de 2 vezes" <<<"$saida"'
verifica '[[ -z "$(ls -A "$tmp/t")" ]]'

nome=interrompido; : >"$FAKE_LOG"; rm -rf "$tmp/t" "$FAKE_LOG.dumps"; mkdir "$tmp/t"
env PATH="$tmp/bin:$PATH" TMPDIR="$tmp/t" GPS_E2E_INTERVALO=0.1 MQTT_ACS_PASSWORD=x \
  FAKE_DIALOGO_TOQUES=1 FAKE_DRIVE_DEMORA=5 ./scripts/qa/acs_gps_e2e.sh --sem-permissao >/dev/null 2>&1 &
pid=$!; sleep 2; kill -TERM "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; saida=""; codigo=$?
verifica '[[ -z "$(ls -A "$tmp/t")" ]]'            # nem o arquivo de toques vaza
verifica '[[ $(conta uninstall) -ge 1 ]]'          # e o app de teste é removido

caso drive_trava FAKE_DRIVE_TRAVA=1 GPS_E2E_TIMEOUT=1 --
verifica '[[ $codigo -eq 124 ]]'
verifica 'grep -q "excedeu" <<<"$saida"'
verifica '[[ $(conta uninstall) -eq 1 ]]'   # e o app de teste não fica instalado

[[ "$falhas" -eq 0 ]] && echo "ok: acs_gps_e2e" || { echo "$falhas falha(s)"; exit 1; }
