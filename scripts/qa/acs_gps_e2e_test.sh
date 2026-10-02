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
  *"dumpsys window"*) [[ "${FAKE_DIALOGO:-0}" == 1 ]] && echo "mCurrentFocus=Window{1 u0 com.google.android.permissioncontroller/x.GrantPermissionsActivity}" ;;
  *"dumpsys package"*) [[ "${FAKE_FIXADA:-0}" == 1 ]] && echo "android.permission.ACCESS_FINE_LOCATION: granted=false, flags=[ USER_SET|USER_FIXED ]" ;;
esac
exit 0
FIM
cat >"$tmp/bin/flutter" <<'FIM'
#!/usr/bin/env bash
echo "flutter $*" >>"$FAKE_LOG"
case "$1" in
  build) [[ "${FAKE_BUILD_FALHA:-0}" == 1 ]] && { echo "ERRO-FALSO-DO-GRADLE: sem espaço" >&2; exit 1; } ;;
  drive) [[ "${FAKE_DRIVE_FALHA:-0}" == 1 ]] && exit 1 ;;
esac
exit 0
FIM
chmod +x "$tmp/bin/"*

falhas=0
caso() { # caso <nome> [VAR=valor ...] -- [args do script]
  nome=$1; shift
  envs=(); while [[ $# -gt 0 && $1 != -- ]]; do envs+=("$1"); shift; done; shift
  : >"$FAKE_LOG"
  saida="$(env PATH="$tmp/bin:$PATH" MQTT_ACS_PASSWORD=x "${envs[@]}" ./scripts/qa/acs_gps_e2e.sh "$@" 2>&1)"; codigo=$?
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

[[ "$falhas" -eq 0 ]] && echo "ok: acs_gps_e2e" || { echo "$falhas falha(s)"; exit 1; }
