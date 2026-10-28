#!/usr/bin/env bash
#
# Prova o append_audit_append_only.sh (#82) numa árvore de migrações
# temporária — nunca toca em backend/sinalacs_server/migrations. Sem Docker.
set -euo pipefail

aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$aqui/append_audit_append_only.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

falha() { echo "FALHOU: $*" >&2; exit 1; }

bloco="$tmp/bloco.sql"
printf -- '--\n-- APPEND-ONLY DA TRILHA DE AUDITORIA (#82, teste)\n--\nSELECT 1;\n' > "$bloco"

sql_minimo() {
  printf 'BEGIN;\nCREATE TABLE "t" ("id" bigint);\n\n--\n-- MIGRATION VERSION FOR sinalacs\n--\nINSERT INTO x VALUES (1);\n\nCOMMIT;\n'
}

# Duas versões; só a última (registry) deve mudar.
monta() {
  local m="$tmp/migrations"; rm -rf "$m"
  for v in 20260101000000000 20260202000000000; do
    mkdir -p "$m/$v"
    sql_minimo > "$m/$v/definition.sql"
    sql_minimo > "$m/$v/migration.sql"
  done
  printf '### AUTOMATICALLY GENERATED DO NOT MODIFY\n###\n20260101000000000\n20260202000000000\n' > "$m/migration_registry.txt"
}
roda() { "$script" --migrations-dir "$tmp/migrations" --bloco "$bloco" "$@"; }
ocorrencias() { grep -c 'APPEND-ONLY DA TRILHA DE AUDITORIA (#82' "$1" || true; }
ultima="$tmp/migrations/20260202000000000"
antiga="$tmp/migrations/20260101000000000"

# insere antes do marcador de versão
monta
saida="$(roda)"
[[ "$saida" == *"bloco inserido em 20260202000000000/definition.sql"* ]] || falha "saída inesperada: $saida"
[[ "$(ocorrencias "$ultima/definition.sql")" == 1 ]] || falha "o bloco não entrou uma vez no definition.sql"
bloco_l="$(grep -n 'APPEND-ONLY DA TRILHA' "$ultima/definition.sql" | cut -d: -f1)"
marca_l="$(grep -n '^-- MIGRATION VERSION FOR sinalacs' "$ultima/definition.sql" | cut -d: -f1)"
(( bloco_l < marca_l )) || falha "o bloco não ficou antes do marcador de versão"
grep -qxF 'SELECT 1;' "$ultima/definition.sql" || falha "o corpo do bloco não foi copiado"
tail -1 "$ultima/definition.sql" | grep -qxF 'COMMIT;' || falha "o COMMIT deixou de ser a última linha"

# é idempotente
saida="$(roda)"
[[ "$saida" == *"já presente em 20260202000000000"* ]] || falha "a segunda rodada não disse já presente: $saida"
[[ "$(ocorrencias "$ultima/definition.sql")" == 1 ]] || falha "a segunda rodada duplicou o bloco"

# não toca o migration.sql sem a flag; toca com --tambem-migration-sql
[[ "$(ocorrencias "$ultima/migration.sql")" == 0 ]] || falha "migration.sql mudou sem a flag"
roda --tambem-migration-sql >/dev/null
[[ "$(ocorrencias "$ultima/migration.sql")" == 1 ]] || falha "migration.sql não recebeu o bloco com a flag"

# usa a última versão do registry
[[ "$(ocorrencias "$antiga/definition.sql")" == 0 ]] || falha "a versão antiga foi alterada"

# recusa definition.sql sem o marcador
monta
printf 'BEGIN;\nCOMMIT;\n' > "$ultima/definition.sql"
cp "$ultima/definition.sql" "$tmp/antes.sql"
if roda >/dev/null 2>&1; then falha "aceitou definition.sql sem o marcador"; fi
cmp -s "$ultima/definition.sql" "$tmp/antes.sql" || falha "alterou o arquivo que recusou"

echo "OK — append_audit_append_only.sh: insere antes da versão, idempotente, só a última migração, recusa sem marcador"
