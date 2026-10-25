#!/usr/bin/env bash
#
# Recoloca o append-only da trilha de auditoria (#82) na última migração.
#
# O Serverpod instala um banco novo só pelo definition.sql da última migração
# e o `serverpod create-migration` reescreve esse arquivo a partir dos modelos,
# sem o trigger. Rode este script depois de TODA migração nova; o
# audit_schema_test.dart falha se esquecer. Idempotente.
#
# uso: append_audit_append_only.sh [--migrations-dir DIR] [--bloco ARQ] [--tambem-migration-sql]
set -euo pipefail

raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
migracoes="$raiz/backend/sinalacs_server/migrations"
bloco="$raiz/backend/sinalacs_server/database/audit_append_only.sql"
tambem_migration=0

while (($#)); do
  case "$1" in
    --migrations-dir) migracoes="$2"; shift 2 ;;
    --bloco) bloco="$2"; shift 2 ;;
    --tambem-migration-sql) tambem_migration=1; shift ;;
    *) echo "uso: $0 [--migrations-dir DIR] [--bloco ARQ] [--tambem-migration-sql]" >&2; exit 2 ;;
  esac
done

marcador_bloco='-- APPEND-ONLY DA TRILHA DE AUDITORIA (#82'
marcador_versao='-- MIGRATION VERSION FOR sinalacs'

[[ -f "$bloco" ]] || { echo "erro: bloco $bloco não existe" >&2; exit 1; }
versao="$(grep -v '^#' "$migracoes/migration_registry.txt" | sed '/^[[:space:]]*$/d' | tail -1)"
[[ -n "$versao" ]] || { echo "erro: migration_registry.txt sem versão" >&2; exit 1; }

inserir() {
  local arq="$migracoes/$versao/$1"
  [[ -f "$arq" ]] || { echo "erro: $arq não existe" >&2; exit 1; }
  if grep -qF -- "$marcador_bloco" "$arq"; then
    echo "já presente em $versao/$1"
    return
  fi
  # Âncora: o `--` que abre o cabeçalho da versão. Nunca acrescentar no fim,
  # depois do COMMIT.
  grep -qxF -- "$marcador_versao" "$arq" || {
    echo "erro: $versao/$1 sem a linha '$marcador_versao'; nada alterado" >&2
    exit 1
  }
  local tmp="$arq.tmp"
  awk -v bloco="$bloco" -v marca="$marcador_versao" '
    { linhas[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) {
        if (!feito && linhas[i] == "--" && linhas[i + 1] == marca) {
          while ((getline l < bloco) > 0) print l
          print ""
          feito = 1
        }
        print linhas[i]
      }
    }' "$arq" > "$tmp"
  mv "$tmp" "$arq"
  echo "bloco inserido em $versao/$1"
}

inserir definition.sql
if ((tambem_migration)); then inserir migration.sql; fi
