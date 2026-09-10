#!/usr/bin/env bash
# QA-22: compare declared HA/Mosquitto pins to current upstream stables.
# Never a required PR check. A divergence fails this job and opens one tracking issue.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
pins_file="${root}/spec/v1.0.0/fixtures/ha-ci/versions.json"
simulate="${SIMULATE_DIVERGENCE:-0}"
failed=0
run_url="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-unknown}/actions/runs/${GITHUB_RUN_ID:-unknown}"
commit="${GITHUB_SHA:-$(git -C "${root}" rev-parse HEAD)}"

normalize() {
  local value="$1"
  value="${value#v}"
  printf '%s' "${value}"
}

latest_non_prerelease() {
  local repo="$1"
  local from_releases
  from_releases="$(
    gh api "repos/${repo}/releases?per_page=30" \
      --jq '[.[] | select(.draft == false and .prerelease == false)][0].tag_name // empty'
  )"
  if [ -n "${from_releases}" ]; then
    printf '%s' "${from_releases}"
    return 0
  fi
  gh api "repos/${repo}/tags?per_page=30" \
    --jq '[.[].name | select(test("(?i)rc|beta|alpha") | not)][0] // empty'
}

open_or_reuse_issue() {
  local title="$1"
  local body="$2"
  local existing
  existing="$(
    gh issue list \
      --state open \
      --limit 100 \
      --search '"QA-22 canary:" in:title' \
      --json number,title \
      --template '{{range .}}{{printf "%v\t%s\n" .number .title}}{{end}}' |
      while IFS=$'\t' read -r number candidate; do
        if [ "${candidate}" = "${title}" ]; then
          printf '%s' "${number}"
          break
        fi
      done
  )"
  if [ -n "${existing}" ]; then
    gh issue comment "${existing}" --body "${body}"
    printf 'updated tracking issue: #%s\n' "${existing}"
    return 0
  fi
  gh issue create --title "${title}" --body "${body}"
}

if [ -n "${REPORT_SERVICE:-}" ]; then
  open_or_reuse_issue \
    "QA-22 canary: ${REPORT_SERVICE} contract divergence" \
    "The nightly contract against ${REPORT_SERVICE} ${REPORT_VERSION:-unknown} failed.

${REPORT_DETAILS:-See the linked workflow run for details.}

- Expected proof: latest-stable startup and contract succeed
- Observed proof: startup or contract failed
- Workflow run: ${run_url}
- Commit: \`${commit}\`

This job is a release gate (QA-22), not a required pull-request check."
  exit 0
fi

current="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["currentStable"])' "${pins_file}")"
oldest="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["oldestInWindow"])' "${pins_file}")"
mosquitto_pin="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["mosquittoTag"])' "${pins_file}")"

ha_latest="$(normalize "$(latest_non_prerelease home-assistant/core)")"
mqtt_latest="$(normalize "$(latest_non_prerelease eclipse/mosquitto)")"

if [ "${simulate}" = "1" ]; then
  current="0.0.0-simulated-pin"
  mosquitto_pin="0.0.0-simulated-pin"
fi

printf 'home-assistant pin=%s oldest=%s latest=%s\n' "${current}" "${oldest}" "${ha_latest}"
printf 'mosquitto pin=%s latest=%s\n' "${mosquitto_pin}" "${mqtt_latest}"

if [ -z "${ha_latest}" ]; then
  printf 'failed to read Home Assistant latest stable\n' >&2
  exit 1
fi
if [ -z "${mqtt_latest}" ]; then
  printf 'failed to read Mosquitto latest stable\n' >&2
  exit 1
fi

if [ "${ha_latest}" != "${current}" ]; then
  failed=1
  open_or_reuse_issue \
    "QA-22 canary: Home Assistant release divergence" \
    "$(cat <<EOF
The nightly upstream canary found a Home Assistant stable release that does not match the declared pin.

- Expected proof (\`currentStable\`): \`${current}\`
- Observed proof (latest non-prerelease): \`${ha_latest}\`
- Declared \`oldestInWindow\`: \`${oldest}\`
- Workflow run: ${run_url}
- Commit: \`${commit}\`

Bump \`spec/v1.0.0/fixtures/ha-ci/versions.json\` and \`.github/workflows/container-contracts.yml\` after verifying R-89 contracts, or accept this as an open canary until the window is updated.

This job is a release gate (QA-22), not a required pull-request check.
EOF
)"
fi

if [ "${mqtt_latest}" != "${mosquitto_pin}" ]; then
  failed=1
  open_or_reuse_issue \
    "QA-22 canary: Mosquitto release divergence" \
    "$(cat <<EOF
The nightly upstream canary found a Mosquitto release that does not match the declared pin.

- Expected proof (\`mosquittoTag\`): \`${mosquitto_pin}\`
- Observed proof (latest non-prerelease): \`${mqtt_latest}\`
- Workflow run: ${run_url}
- Commit: \`${commit}\`

Bump the pin in \`spec/v1.0.0/fixtures/ha-ci/versions.json\` and \`.github/workflows/container-contracts.yml\` after verifying R-90 contracts.

This job is a release gate (QA-22), not a required pull-request check.
EOF
)"
fi

if [ "${failed}" -ne 0 ]; then
  printf 'upstream canary red\n' >&2
  exit 1
fi

printf 'upstream canary green\n'
