#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
# SPDX-License-Identifier: FSL-1.1-ALv2
# Mutation test for scan-release-artifacts.sh (#69): a clean fixture passes, and each
# injected hook string makes the scan fail. A scan that cannot fail proves nothing.
# Run from the repository root; needs macOS (PlistBuddy).
set -euo pipefail

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

make_bundle() {
  local plist="$1" binary="$2" name="$3"
  /usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $name" "$plist" >/dev/null
  for i in $(seq 1 200); do echo "benign string $i"; done > "$binary"
}

build_fixture() {
  local root="$1"
  rm -rf "$root"
  mkdir -p "$root/ios/App.app/PlugIns/W.appex" "$root/mac/App.app/Contents/MacOS"
  make_bundle "$root/ios/App.app/Info.plist" "$root/ios/App.app/App" App
  make_bundle "$root/ios/App.app/PlugIns/W.appex/Info.plist" "$root/ios/App.app/PlugIns/W.appex/W" W
  make_bundle "$root/mac/App.app/Contents/Info.plist" "$root/mac/App.app/Contents/MacOS/App" App
}

scan() { scripts/scan-release-artifacts.sh "$1/ios" "$1/mac" >/dev/null 2>&1; }

fixture="$scratch/fixture"
build_fixture "$fixture"
scan "$fixture" || { echo "clean fixture failed the scan" >&2; exit 1; }

for leak in OHE_SEED_ICLOUD_FOLDER OHE_NEW_UNLISTED_HOOK seedLocalExportForUITests "M0 harness"; do
  build_fixture "$fixture"
  echo "$leak" >> "$fixture/ios/App.app/App"
  if scan "$fixture"; then
    echo "scan did not fail when the binary contained: $leak" >&2
    exit 1
  fi
done

echo "scan-release-artifacts mutation test: ok"
