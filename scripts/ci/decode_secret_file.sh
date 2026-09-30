#!/usr/bin/env bash
#
# Decodifica um secret do GitHub que guarda um arquivo em base64 (`base64 -w0 arquivo`).
#
#   --env VAR --kind service_account --temp-export NOME   # arquivo 0600 em $RUNNER_TEMP + NOME=<caminho> em $GITHUB_ENV
#   --env VAR --kind google_services  --to ARQUIVO [--package ID]
#   --cleanup-temp NOME                                   # apaga o arquivo de $NOME, só se sob $RUNNER_TEMP
#   --cleanup-file ARQUIVO                                # apaga ARQUIVO, só no CI (GITHUB_ACTIONS=true)
#
# Por que é um script e não YAML inline: o secret entra por `env:` do passo (nunca por
# `${{ }}` dentro de `run:`, que é injeção de script e pede um `echo` para vazar) e o
# comportamento fica testável (decode_secret_file_test.sh).
#
# Regras: NUNCA imprime o conteúdo (sem `set -x`, sem eco, erros genéricos); sem o secret
# (PR de fork) sai com 0 e não cria nada; com o secret inválido sai com 1; fora do CI não
# sobrescreve nem apaga arquivo que já existia (é o `google-services.json` de um dev).
set -euo pipefail
umask 077

uso() { echo 'uso: decode_secret_file.sh --env VAR --kind service_account|google_services (--temp-export NOME | --to ARQUIVO) [--package ID] | --cleanup-temp NOME | --cleanup-file ARQUIVO' >&2; exit 2; }

modo=decodificar; env_nome=''; tipo=''; temp_export=''; destino=''; pacote=''; alvo=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) [[ $# -ge 2 ]] || uso; env_nome="$2"; shift 2 ;;
    --kind) [[ $# -ge 2 ]] || uso; tipo="$2"; shift 2 ;;
    --temp-export) [[ $# -ge 2 ]] || uso; temp_export="$2"; shift 2 ;;
    --to) [[ $# -ge 2 ]] || uso; destino="$2"; shift 2 ;;
    --package) [[ $# -ge 2 ]] || uso; pacote="$2"; shift 2 ;;
    --cleanup-temp) [[ $# -ge 2 ]] || uso; modo=limpar_temp; alvo="$2"; shift 2 ;;
    --cleanup-file) [[ $# -ge 2 ]] || uso; modo=limpar_arquivo; alvo="$2"; shift 2 ;;
    *) uso ;;
  esac
done

if [[ "$modo" == limpar_temp ]]; then
  arquivo="${!alvo:-}"
  # Só apaga o que este script criou: sob $RUNNER_TEMP. Outro passo pode ter
  # redefinido a variável para um arquivo que não é nosso.
  if [[ -n "$arquivo" && -n "${RUNNER_TEMP:-}" && "$arquivo" == "$RUNNER_TEMP"/* ]]; then
    rm -f -- "$arquivo"
  fi
  exit 0
fi

if [[ "$modo" == limpar_arquivo ]]; then
  if [[ "${GITHUB_ACTIONS:-}" == true ]]; then
    rm -f -- "$alvo"
  else
    echo "aviso: --cleanup-file só age no CI (GITHUB_ACTIONS=true); $alvo foi mantido." >&2
  fi
  exit 0
fi

# -- decodificar -------------------------------------------------------------
[[ -n "$env_nome" && -n "$tipo" ]] || uso
[[ "$tipo" == service_account || "$tipo" == google_services ]] || uso
if [[ -n "$temp_export" && -n "$destino" ]] || [[ -z "$temp_export" && -z "$destino" ]]; then uso; fi

segredo="${!env_nome:-}"
if [[ -z "${segredo//[[:space:]]/}" ]]; then
  echo "::notice title=secret::$env_nome ausente (PR de fork ou secret não cadastrado): nada foi decodificado e o que depende dele fica desligado."
  exit 0
fi

if [[ -n "$destino" && -e "$destino" && "${GITHUB_ACTIONS:-}" != true ]]; then
  echo "::error title=secret::$destino já existe e isto não é o CI: não sobrescrevo o arquivo de um desenvolvedor."
  exit 1
fi

dir="${RUNNER_TEMP:-$(mktemp -d)}"
tmp="$(mktemp --suffix=.json "$dir/secret.XXXXXX")"
falhar() {
  rm -f -- "$tmp"
  echo "::error title=secret::$1"
  exit 1
}

# base64 do `base64 -w0`, do `base64` com quebra em 76 colunas, com CRLF ou espaço
# final: tudo que é espaço em branco sai antes de decodificar.
if ! printf '%s' "$segredo" | tr -d '[:space:]' | base64 -d >"$tmp" 2>/dev/null; then
  # Diagnóstico SEM valores: só tamanho, contagens e o formato geral. Sem ele, um secret
  # cadastrado errado (JSON em claro, base64url, truncado) é impossível de diagnosticar, já
  # que o GitHub o mascara no log.
  limpo="$(printf '%s' "$segredo" | tr -d '[:space:]')"
  fora="$(printf '%s' "$limpo" | tr -d 'A-Za-z0-9+/=' | wc -c | tr -d ' ')"
  dica=''
  [[ "$limpo" == \{* ]] && dica+=" O valor começa com '{': parece o JSON em claro, e não o base64 (use: base64 -w0 arquivo.json)."
  [[ "$limpo" == \"* || "$limpo" == \'* ]] && dica+=' O valor começa com aspas: cadastre-o sem aspas.'
  [[ "$limpo" == *[-_]* ]] && dica+=' Tem "-" ou "_": parece base64url; o secret usa o base64 padrão (base64 -w0).'
  falhar "$env_nome não é um base64 válido (tamanho=${#limpo}; resto=$(( ${#limpo} % 4 )) por 4; caracteres fora do alfabeto base64=$fora).$dica"
fi

# Só confirma a FORMA. Saída e erro descartados: um traceback do Python imprimiria o dado.
if ! python3 - "$tmp" "$tipo" "$pacote" >/dev/null 2>&1 <<'PY'
import json, sys
caminho, tipo, pacote = sys.argv[1:4]
d = json.load(open(caminho, encoding='utf-8'))
if tipo == 'service_account':
    ok = (isinstance(d, dict) and d.get('type') == 'service_account'
          and d.get('client_email') and d.get('private_key'))
else:  # google_services
    clientes = d.get('client') if isinstance(d, dict) else None
    ok = bool(isinstance(d, dict) and (d.get('project_info') or {}).get('project_id')
              and isinstance(clientes, list) and clientes)
    if ok and pacote:
        ok = any((((c.get('client_info') or {}).get('android_client_info') or {}).get('package_name') == pacote)
                 for c in clientes if isinstance(c, dict))
sys.exit(0 if ok else 1)
PY
then
  falhar "$env_nome decodificou, mas não tem a forma esperada de um $tipo${pacote:+ do pacote $pacote}."
fi

chmod 600 "$tmp"
if [[ -n "$destino" ]]; then
  mkdir -p "$(dirname "$destino")"
  mv -f -- "$tmp" "$destino"
  echo "::notice title=secret::$env_nome decodificado em $destino (conteúdo não impresso)."
else
  if [[ -n "${GITHUB_ENV:-}" ]]; then
    echo "$temp_export=$tmp" >>"$GITHUB_ENV"
  fi
  echo "::notice title=secret::$env_nome decodificado em $tmp ($temp_export definida para os próximos passos; conteúdo não impresso)."
fi
