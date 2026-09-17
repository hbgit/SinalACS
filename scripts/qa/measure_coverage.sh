#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
artifact_root="${1:-$repo_root/build/qa/coverage}"
if [[ "$artifact_root" != /* ]]; then
  artifact_root="$repo_root/$artifact_root"
fi

mkdir -p "$artifact_root"

coverage_summary() {
  local lcov_file="$1"
  awk -F: '
    /^LF:/ {found += $2}
    /^LH:/ {hit += $2}
    END {
      percent = found == 0 ? 0 : (hit / found) * 100
      printf "linhas=%d cobertas=%d cobertura=%.2f%%\n", found, hit, percent
    }
  ' "$lcov_file"
}

run_backend() {
  local out_dir="$artifact_root/backend"
  mkdir -p "$out_dir"
  pushd "$repo_root/backend/sinalacs_server" >/dev/null
  dart pub get >/dev/null
  dart pub global activate coverage >/dev/null
  dart test --coverage=coverage
  dart pub global run coverage:format_coverage \
    --package=. \
    --report-on=lib \
    --lcov \
    -i coverage \
    -o "$out_dir/lcov.info"
  coverage_summary "$out_dir/lcov.info" > "$out_dir/summary.txt"
  popd >/dev/null
}

run_flutter_app() {
  local app_dir="$1"
  local app_name="$2"
  local out_dir="$artifact_root/$app_name"
  mkdir -p "$out_dir"
  pushd "$repo_root/$app_dir" >/dev/null
  flutter pub get >/dev/null
  flutter test --coverage
  cp coverage/lcov.info "$out_dir/lcov.info"
  coverage_summary "$out_dir/lcov.info" > "$out_dir/summary.txt"
  popd >/dev/null
}

run_backend
run_flutter_app apps/patient patient
run_flutter_app apps/acs acs
run_flutter_app apps/admin admin

{
  echo 'backend:'
  cat "$artifact_root/backend/summary.txt"
  echo 'patient:'
  cat "$artifact_root/patient/summary.txt"
  echo 'acs:'
  cat "$artifact_root/acs/summary.txt"
  echo 'admin:'
  cat "$artifact_root/admin/summary.txt"
} | tee "$artifact_root/summary.txt"