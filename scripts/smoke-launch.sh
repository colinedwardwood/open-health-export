#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# #37: launches a built app the way a new install does: a fresh simulator, no launch
# arguments, no environment, no UI-test hooks, one attempt. It fails if the app is
# not running after each launch, if a crash report appears, or if the app logs a
# storage error. The UI suite cannot catch this class of bug because every case
# overrides the defaults.
#
#   scripts/smoke-launch.sh path/to/App.app [device type, default "iPhone 17 Pro"]
set -euo pipefail
app="${1:?usage: scripts/smoke-launch.sh path/to/App.app [device]}"
device_type="${2:-iPhone 17 Pro}"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")"
process="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Info.plist")"
settle="${OHE_SMOKE_SETTLE_SECONDS:-20}"

udid="$(xcrun simctl create "ohe-smoke-$$" "$device_type")"
trap 'xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true; xcrun simctl delete "$udid" >/dev/null 2>&1 || true' EXIT
xcrun simctl boot "$udid"
xcrun simctl bootstatus "$udid" >/dev/null
xcrun simctl install "$udid" "$app"

reports="$HOME/Library/Logs/DiagnosticReports"
mkdir -p "$reports"
marker="$(mktemp)"
failures=0

running() {
  xcrun simctl spawn "$udid" launchctl list | grep -F "$bundle_id" | grep -Eq '^[0-9]+'
}

check() {
  local step="$1"
  sleep "$settle"
  if ! running; then
    echo "smoke-launch: $step: $bundle_id is not running" >&2
    failures=$((failures + 1))
  fi
  local crash
  crash="$(find "$reports" -name "${process}*.ips" -newer "$marker" | head -1)"
  if [[ -n "$crash" ]]; then
    echo "smoke-launch: $step: crash report $crash" >&2
    grep -m3 -E '"exception"|reason|Terminating' "$crash" >&2 || true
    failures=$((failures + 1))
  fi
  local errors
  errors="$(xcrun simctl spawn "$udid" log show --last "$((settle + 10))s" --style compact \
    --predicate "process == \"$process\" AND messageType == error" 2>/dev/null \
    | grep -E 'database is locked|StorageError|duplicate column|NSGenericException' || true)"
  if [[ -n "$errors" ]]; then
    echo "smoke-launch: $step: storage or runtime errors in the log:" >&2
    echo "$errors" | head -5 >&2
    failures=$((failures + 1))
  fi
  echo "smoke-launch: $step: checked"
  touch "$marker"
}

xcrun simctl launch "$udid" "$bundle_id" >/dev/null
check "fresh install"
xcrun simctl terminate "$udid" "$bundle_id" >/dev/null 2>&1 || true
xcrun simctl launch "$udid" "$bundle_id" >/dev/null
check "relaunch"
xcrun simctl launch "$udid" com.apple.Preferences >/dev/null
sleep 3
xcrun simctl launch "$udid" "$bundle_id" >/dev/null
check "return from background"

rm -f "$marker"
if [[ $failures -gt 0 ]]; then
  echo "smoke-launch: $failures failure(s)" >&2
  exit 1
fi
echo "smoke-launch: $bundle_id survived a clean install, a relaunch and a return from background"
