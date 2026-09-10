#!/usr/bin/env bash
# QA-22: compare declared HA/Mosquitto pins to current upstream stables.
# Never a required PR check. A divergence fails this job and opens one tracking issue.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
pins_file="${root}/spec/v1.0.0/fixtures/ha-ci/versions.json"
simulate="${SIMULATE_DIVERGENCE:-0}"
dry_run="${DRY_RUN:-0}"
failed=0

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
  if [ "${dry_run}" = "1" ]; then
    printf 'dry-run would open issue: %s\n' "${title}"
    return 0
  fi
  local existing
  existing="$(
    python3 - "${title}" <<'PY'
import json, subprocess, sys
title = sys.argv[1]
raw = subprocess.check_output(
    ["gh", "issue", "list", "--state", "open", "--limit", "50",
     "--search", "QA-22 canary:", "--json", "number,title"],
    text=True,
)
for issue in json.loads(raw):
    if issue.get("title") == title:
        print(issue["number"])
        break
PY
  )"
  if [ -n "${existing}" ]; then
    printf 'tracking issue already open: #%s\n' "${existing}"
    return 0
  fi
  gh issue create --title "${title}" --body "${body}"
}

if [ -n "${REPORT_SERVICE:-}" ]; then
  open_or_reuse_issue \
    "QA-22 canary: ${REPORT_SERVICE} ${REPORT_VERSION:-unknown} contract failed" \
    "The nightly contract against ${REPORT_SERVICE} ${REPORT_VERSION:-unknown} failed.

${REPORT_DETAILS:-See the linked workflow run for details.}

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
    "QA-22 canary: Home Assistant stable is ${ha_latest}, pin is ${current}" \
    "$(cat <<EOF
The nightly upstream canary found a Home Assistant stable release that does not match the declared pin.

- Declared \`currentStable\`: \`${current}\`
- Declared \`oldestInWindow\`: \`${oldest}\`
- Latest non-prerelease on [home-assistant/core](https://github.com/home-assistant/core/releases): \`${ha_latest}\`

Bump \`spec/v1.0.0/fixtures/ha-ci/versions.json\` and \`.github/workflows/container-contracts.yml\` after verifying R-89 contracts, or accept this as an open canary until the window is updated.

This job is a release gate (QA-22), not a required pull-request check.
EOF
)"
fi

if [ "${mqtt_latest}" != "${mosquitto_pin}" ]; then
  failed=1
  open_or_reuse_issue \
    "QA-22 canary: Mosquitto stable is ${mqtt_latest}, pin is ${mosquitto_pin}" \
    "$(cat <<EOF
The nightly upstream canary found a Mosquitto release that does not match the declared pin.

- Declared \`mosquittoTag\`: \`${mosquitto_pin}\`
- Latest non-prerelease on [eclipse/mosquitto](https://github.com/eclipse/mosquitto/releases): \`${mqtt_latest}\`

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
