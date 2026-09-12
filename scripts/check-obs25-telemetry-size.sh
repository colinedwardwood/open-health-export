#!/bin/sh
# SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail
cd "$(dirname "$0")/.."

limit_bytes=$((2 * 1024 * 1024))
work="${RUNNER_TEMP:-/tmp}/ohe-obs25-$$"
baseline_spec=".obs25-project-$$.yml"
mkdir -p "$work"
trap './scripts/generate-project.sh >/dev/null; rm -f "$baseline_spec"; rm -rf "$work"' EXIT

measure() {
  python3 - "$1" <<'PY'
import os
import sys

total = 0
for root, _, files in os.walk(sys.argv[1]):
    for name in files:
        path = os.path.join(root, name)
        if not os.path.islink(path):
            total += os.path.getsize(path)
print(total)
PY
}

build() {
  label="$1"
  shift
  xcodebuild \
    -project OpenHealthExporter.xcodeproj \
    -target ExporteriOS \
    -sdk iphoneos \
    -configuration Release \
    SYMROOT="$work/$label" \
    OBJROOT="$work/$label-obj" \
    CODE_SIGNING_ALLOWED=NO \
    "$@" \
    build >/dev/null
  measure "$work/$label/Release-iphoneos/OpenHealthExporter.app"
}

./scripts/generate-project.sh >/dev/null
with_telemetry="$(build with-telemetry)"

python3 - "$baseline_spec" <<'PY'
from pathlib import Path
import sys

source = Path("project.yml").read_text()
dependency = """      - package: open-health-exporter
        product: OTLPExport
"""
if source.count(dependency) != 1:
    raise SystemExit("OBS-25 baseline cannot identify the OTLPExport app dependency")
Path(sys.argv[1]).write_text(source.replace(dependency, ""))
PY
xcodegen generate --spec "$baseline_spec" >/dev/null
without_telemetry="$(
  build without-telemetry 'OTHER_SWIFT_FLAGS=$(inherited) -D OHE_OBS25_SIZE_BASELINE'
)"

delta=$((with_telemetry - without_telemetry))
printf \
  'OBS-25 with=%s without=%s delta=%s limit=%s\n' \
  "$with_telemetry" "$without_telemetry" "$delta" "$limit_bytes"
if [ "$delta" -gt "$limit_bytes" ]; then
  printf 'OBS-25 telemetry exceeds the 2 MiB uncompressed app budget\n' >&2
  exit 1
fi
