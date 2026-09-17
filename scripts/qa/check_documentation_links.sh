#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
failed=0

while IFS= read -r file; do
  source_dir="$(dirname "$file")"
  while IFS= read -r target; do
    target="${target%%#*}"
    [[ -z "$target" || "$target" == http://* || "$target" == https://* ]] && continue
    [[ "$target" == mailto:* || "$target" == *issues* || "$target" == graphify-out/wiki ]] && continue
    [[ "$target" == /* ]] && continue
    [[ "$file" == "$repo_root/PROGRESS.md" ]] && continue
    link_path="$source_dir/$target"
    case "$target" in
      apps/*|backend/*|docs/*|spec/*|scripts/*|video/*|.github/*|README.md|CLAUDE.md|AGENTS.md|PROGRESS.md|CONTRIBUTING.md|docker-compose.yml)
        link_path="$repo_root/$target"
        ;;
    esac
    if [[ ! -e "$link_path" ]]; then
      printf 'link local ausente: %s (%s)\n' "$target" "${file#$repo_root/}" >&2
      failed=1
    fi
  done < <(rg -o '\[[^]]+\]\([^)]*\)' "$file" | sed -E 's/.*\]\(([^)]*)\)/\1/')
done < <(
  find "$repo_root" \
    -path "$repo_root/.git" -prune -o \
    -path "$repo_root/.superpowers" -prune -o \
    -path "$repo_root/pg_data" -prune -o \
    -path '*/node_modules' -prune -o \
    -type f \( -name '*.md' -o -name '*.markdown' \) -print
)

exit "$failed"
