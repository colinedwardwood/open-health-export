#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# R-84 / QA-07: 100-run byte-determinism gate over UTC and fixed-offset fixtures.
#
# Regenerates the committed T0 corpus (tzOffsetMinutes = 0) under a hostile
# locale and a POSIX fixed-offset TZ, hashes each run, byte-compares against
# the committed file, and schema-checks the stream with pipelinecheck.
# Host tzdata pins are the existing policycheck gate (A-8 / criterion c).
#
# Hosted GitHub Actions currently supplies Linux x86_64 (ubuntu-latest),
# Linux arm64 (ubuntu-24.04-arm), and macOS arm64 (macos-26). This script
# reports `uname -s` / `uname -m` and does not claim Darwin x86_64: GitHub
# no longer hosts Intel macOS runners.

set -euo pipefail

usage() {
  cat <<'EOF'
usage: scripts/check-r84-determinism.sh [--self-test] [--runs N]

  --self-test   Check committed UTC/fixed-offset digests, G1 offset, tzdata
                pins, and hosted-runner claims. Does not build Swift tools.
  --runs N      Repeat corpus generation N times (default 100, or
                OHE_DETERMINISM_RUNS).
EOF
}

ohe_repo_root() {
  local here
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  printf '%s\n' "$here"
}

ohe_sha256_file() {
  local path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "$path" | awk '{print $1}'
  else
    shasum -a 256 -- "$path" | awk '{print $1}'
  fi
}

ohe_committed_t0_digest() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["fixtures"]["tier0.ndjson"]["sha256"])' "$1"
}

ohe_committed_g1_digest() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["fixtures"]["g1"]["sha256"])' "$1"
}

ohe_g1_offsets_are_fixed() {
  python3 - "$1" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
for sample in doc["samples"]:
    if int(sample["tzOffsetMinutes"]) != 0:
        sys.exit(1)
PY
}

ohe_workflow_is_fork_safe() {
  local workflow="$1"
  if grep -E 'pull_request_target|macos-13|self-hosted' "$workflow" >/dev/null; then
    echo "determinism workflow must stay fork-safe and must not claim retired Intel macOS runners" >&2
    return 1
  fi
  grep -F 'permissions:' "$workflow" >/dev/null
  grep -F 'contents: read' "$workflow" >/dev/null
  grep -F 'ubuntu-latest' "$workflow" >/dev/null
  grep -F 'ubuntu-24.04-arm' "$workflow" >/dev/null
  grep -F 'macos-26' "$workflow" >/dev/null
  grep -F 'actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683' "$workflow" >/dev/null
  grep -F 'swift-actions/setup-swift@d8e84bc3a450686a95474d7d6fa4a3301498debc' "$workflow" >/dev/null
}

ohe_self_test() {
  local root="$1"
  local spec="$root/spec/v1.0.0/README.md"
  local t0="$root/spec/v1.0.0/fixtures/tier0.ndjson"
  local g1_ndjson="$root/spec/v1.0.0/fixtures/g1/expected.ndjson"
  local g1_input="$root/spec/v1.0.0/fixtures/g1/logical-input.json"
  local workflow="$root/.github/workflows/r84-determinism.yml"
  local expected_t0 expected_g1 observed_t0 observed_g1

  expected_t0="$(ohe_committed_t0_digest "$spec")"
  expected_g1="$(ohe_committed_g1_digest "$spec")"
  observed_t0="$(ohe_sha256_file "$t0")"
  observed_g1="$(ohe_sha256_file "$g1_ndjson")"

  if [[ "$expected_t0" != "$observed_t0" ]]; then
    echo "T0 committed digest drifted: README $expected_t0 file $observed_t0" >&2
    return 1
  fi
  if [[ "$expected_g1" != "$observed_g1" ]]; then
    echo "G1 committed digest drifted: README $expected_g1 file $observed_g1" >&2
    return 1
  fi
  if ! ohe_g1_offsets_are_fixed "$g1_input"; then
    echo "G1 logical input is not UTC/fixed-offset (tzOffsetMinutes must be 0)" >&2
    return 1
  fi
  test -s "$root/spec/v1.0.0/fixtures/host-tzdata-linux.txt"
  test -s "$root/spec/v1.0.0/fixtures/host-tzdata-darwin.txt"
  test -s "$root/spec/v1.0.0/fixtures/tz-database-version.txt"
  ohe_workflow_is_fork_safe "$workflow"
  echo "r84-determinism self-test: ok t0=$expected_t0 g1=$expected_g1"
}

ohe_build_tools() {
  swift build --product corpusgen
  swift build --product pipelinecheck
}

ohe_run_gate() {
  local root="$1"
  local runs="$2"
  local spec="$root/spec/v1.0.0/README.md"
  local t0="$root/spec/v1.0.0/fixtures/tier0.ndjson"
  local expected work bin corpusgen pipelinecheck
  local i got

  expected="$(ohe_committed_t0_digest "$spec")"
  work="$(mktemp -d "${TMPDIR:-/tmp}/ohe-r84.XXXXXX")"
  trap "rm -rf '$work'" RETURN

  echo "r84-determinism: os=$(uname -s) arch=$(uname -m) runs=$runs tz=${TZ:-} lc=${LC_ALL:-}"
  echo "r84-determinism: hosted claim is Linux x86_64, Linux arm64, macOS arm64; not Darwin x86_64"

  if [[ "${OHE_DETERMINISM_SKIP_POLICYCHECK:-0}" != "1" ]]; then
    swift run policycheck
  fi

  ohe_build_tools
  bin="$(swift build --show-bin-path)"
  corpusgen="$bin/corpusgen"
  pipelinecheck="$bin/pipelinecheck"

  for i in $(seq 1 "$runs"); do
    "$corpusgen" --seed 1 --count 200 > "$work/t0.ndjson"
    got="$(ohe_sha256_file "$work/t0.ndjson")"
    if [[ "$got" != "$expected" ]]; then
      echo "run $i/$runs digest $got != committed $expected" >&2
      return 1
    fi
    if ! cmp -s "$t0" "$work/t0.ndjson"; then
      echo "run $i/$runs bytes drifted from spec/v1.0.0/fixtures/tier0.ndjson" >&2
      return 1
    fi
    "$pipelinecheck" < "$work/t0.ndjson" >/dev/null
  done

  echo "r84-determinism: $runs identical UTC/fixed-offset T0 digests $expected"
}

main() {
  local root runs mode=gate
  root="$(ohe_repo_root)"
  cd "$root"
  runs="${OHE_DETERMINISM_RUNS:-100}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --self-test) mode=self-test; shift ;;
      --runs)
        runs="$2"
        shift 2
        ;;
      -h|--help) usage; return 0 ;;
      *) usage >&2; return 2 ;;
    esac
  done

  export TZ="${OHE_DETERMINISM_TZ:-Etc/GMT+5}"
  export LC_ALL="${OHE_DETERMINISM_LC_ALL:-C}"
  export LANG="$LC_ALL"
  export LC_CTYPE="$LC_ALL"
  export LC_NUMERIC="$LC_ALL"
  export LC_TIME="$LC_ALL"

  case "$mode" in
    self-test) ohe_self_test "$root" ;;
    *) ohe_run_gate "$root" "$runs" ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
