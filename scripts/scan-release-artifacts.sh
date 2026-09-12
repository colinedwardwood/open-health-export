#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  echo "usage: $0 <ios-products-directory> <macos-products-directory>" >&2
  exit 2
fi

ios_products="$1"
macos_products="$2"
canary_source="Sources/Redaction/Canary.swift"

for path in "$ios_products" "$macos_products" "$canary_source"; do
  if [[ ! -e "$path" ]]; then
    echo "Release artifact scan input does not exist: $path" >&2
    exit 1
  fi
done

shopt -s nullglob
ios_apps=("$ios_products"/*.app)
if [[ "${#ios_apps[@]}" -ne 1 ]]; then
  echo "Expected exactly one iOS app in $ios_products; found ${#ios_apps[@]}" >&2
  exit 1
fi

widget_extensions=("${ios_apps[0]}"/PlugIns/*.appex)
if [[ "${#widget_extensions[@]}" -ne 1 ]]; then
  echo "Expected exactly one widget extension in ${ios_apps[0]}/PlugIns; found ${#widget_extensions[@]}" >&2
  exit 1
fi

macos_apps=("$macos_products"/*.app)
if [[ "${#macos_apps[@]}" -ne 1 ]]; then
  echo "Expected exactly one macOS app in $macos_products; found ${#macos_apps[@]}" >&2
  exit 1
fi

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# Read the names in RedactionCanary.tokens and resolve their values from the declarations
# in the same Swift source. The release gate therefore follows corpus changes automatically
# instead of maintaining a second hand-copied canary list.
python3 - "$canary_source" > "$scratch/canaries" <<'PY'
import re
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text()
marker = "public static let tokens: [String] = ["
if source.count(marker) != 1:
    raise SystemExit("Expected exactly one RedactionCanary.tokens declaration")

declarations, remainder = source.split(marker, 1)
token_body = remainder.split("]", 1)[0]
values = dict(re.findall(r'public static let (\w+) = "([^"]+)"', declarations))
names = re.findall(r"^\s*(\w+),\s*$", token_body, re.MULTILINE)
if not names:
    raise SystemExit("RedactionCanary.tokens contains no canaries")

for name in names:
    if name not in values:
        raise SystemExit(f"Canary {name!r} is not a direct string declaration")
    print(values[name])
PY

cat > "$scratch/fault-seams" <<'EOF'
ExportFaultLocation
ExportFaultInjector
NoExportFaults
afterRead
afterTransform
afterEnqueueBeforeDestinationWrite
afterDestinationWriteBeforeAck
afterAckBeforeRelease
duringAnchorPersist
OHE_PROCESS_EXIT_SEAM
EOF

bundle_executable() {
  local bundle="$1"
  local platform="$2"
  local plist executable binary

  if [[ "$platform" == "macos" ]]; then
    plist="$bundle/Contents/Info.plist"
    executable="$(
      /usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$plist"
    )"
    binary="$bundle/Contents/MacOS/$executable"
  else
    plist="$bundle/Info.plist"
    executable="$(
      /usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$plist"
    )"
    binary="$bundle/$executable"
  fi

  if [[ ! -f "$binary" ]]; then
    echo "Bundle executable does not exist: $binary" >&2
    exit 1
  fi

  # QA-20's release-only assertion: private-data debug logging may not be enabled
  # in any shipped bundle. Enabling DEBUG is independently caught by the seam scan.
  if /usr/libexec/PlistBuddy -c "Print :OSLogPreferences:Enable-Private-Data" "$plist" >/dev/null 2>&1; then
    echo "Release bundle enables private-data debug logging: $plist" >&2
    exit 1
  fi

  printf '%s\n' "$binary"
}

binaries=(
  "$(bundle_executable "${ios_apps[0]}" ios)"
  "$(bundle_executable "${widget_extensions[0]}" ios)"
  "$(bundle_executable "${macos_apps[0]}" macos)"
)

if [[ "${#binaries[@]}" -eq 0 ]]; then
  echo "Release artifact scan found zero binaries" >&2
  exit 1
fi

cat "$scratch/fault-seams" "$scratch/canaries" > "$scratch/forbidden"
found=0
for binary in "${binaries[@]}"; do
  echo "Scanning release binary: $binary"
  if otool -L "$binary" | grep -Ei 'grpc|swift[_-]?nio|NIOPosix|SwiftProtobuf|OpenTelemetry'; then
    echo "OBS-25: release binary links a forbidden telemetry transport dependency: $binary" >&2
    found=1
  fi
  if nm -u "$binary" | grep -Ei 'grpc|swift[_-]?nio|NIOPosix|SwiftProtobuf|OpenTelemetry'; then
    echo "OBS-25: release binary imports a forbidden telemetry transport symbol: $binary" >&2
    found=1
  fi
  if otool -L "$binary" | grep -F "StoreKit.framework"; then
    echo "R-110: release binary links StoreKit: $binary" >&2
    found=1
  fi
  if nm -u "$binary" | grep -E 'StoreKit|SK(Product|Payment|Receipt|Transaction)'; then
    echo "R-110: release binary imports StoreKit symbols: $binary" >&2
    found=1
  fi
  strings "$binary" > "$scratch/strings"
  # A gate that reads nothing passes everything. Any real Mach-O carries far more
  # than this, so an empty or truncated read is a broken scan, not a clean binary.
  extracted="$(wc -l < "$scratch/strings")"
  if [[ "$extracted" -lt 100 ]]; then
    echo "Release artifact scan read only $extracted strings from $binary" >&2
    exit 1
  fi
  while IFS= read -r forbidden; do
    if grep -F -- "$forbidden" "$scratch/strings"; then
      echo "Forbidden release string leaked into $binary: $forbidden" >&2
      found=1
    fi
  done < "$scratch/forbidden"
done

if [[ "$found" -ne 0 ]]; then
  exit 1
fi

echo "Release artifact scan passed: scanned ${#binaries[@]} binaries"
