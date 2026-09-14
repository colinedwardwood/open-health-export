#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
# SPDX-License-Identifier: AGPL-3.0-or-later
# Prints the UDID of the simulator the XCUITest suite runs on, for one device family.
#
# Picking whichever device the runner happens to list first makes the accessibility
# audits unreproducible: contrast findings depend on where content lands relative to
# the navigation and tab bars, so two iPhones of different sizes disagree about the
# same commit. The model is therefore named here, and an image that no longer carries
# it fails loudly instead of silently auditing a different screen.
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  echo "usage: $0 <iPhone|iPad>" >&2
  exit 2
fi

family="$1"

case "$family" in
  iPhone) models=("iPhone 17 Pro" "iPhone 17" "iPhone 16 Pro") ;;
  iPad) models=("iPad Pro 11-inch (M5)" "iPad Pro 11-inch (M4)" "iPad Air 11-inch (M3)") ;;
  *)
    echo "unknown device family: $family" >&2
    exit 2
    ;;
esac

devices="$(xcrun simctl list devices available -j)"

for model in "${models[@]}"; do
  udid="$(
    MODEL="$model" python3 -c '
import json, os, sys
model = os.environ["MODEL"]
devices = json.load(sys.stdin)["devices"]
# Newest runtime first, so a pinned model resolves the same way on an image that
# still carries an older runtime alongside the current one.
for runtime in sorted(devices, reverse=True):
    for device in devices[runtime]:
        if device["name"] == model:
            print(device["udid"])
            sys.exit(0)
' <<<"$devices"
  )"
  if [[ -n "$udid" ]]; then
    echo "Using pinned $family simulator: $model ($udid)" >&2
    echo "$udid"
    exit 0
  fi
done

echo "None of the pinned $family simulators are installed: ${models[*]}" >&2
echo "Installed $family devices:" >&2
FAMILY="$family" python3 -c '
import json, os, sys
family = os.environ["FAMILY"]
devices = json.load(sys.stdin)["devices"]
for runtime in sorted(devices, reverse=True):
    for device in devices[runtime]:
        if family in device["name"]:
            print(f"  {device[\"name\"]} ({runtime})")
' <<<"$devices" >&2
exit 1
