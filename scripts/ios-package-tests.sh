#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# #38: runs the package test suites on an iOS simulator, so code behind
# `#if os(iOS)` is compiled and exercised. `swift test` only ever sees macOS and
# Linux, which is how an iOS-only crash in the HTTP transport stayed green.
#
# xcodebuild picks a generated .xcodeproj over Package.swift, and the package's own
# scheme also builds the command-line tools, which use Process and cannot build for
# iOS. So this runs from a symlinked mirror with no project and a scheme holding
# only the test bundles.
#
#   scripts/ios-package-tests.sh [device type, default "iPhone 17 Pro"]
set -euo pipefail
root_dir="$(cd "$(dirname "$0")/.." && pwd)"
device_type="${1:-iPhone 17 Pro}"
work="$(mktemp -d)"
udid=""
cleanup() {
  if [[ -n "$udid" ]]; then
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
    xcrun simctl delete "$udid" >/dev/null 2>&1 || true
  fi
  rm -rf "$work"
}
trap cleanup EXIT

mirror="$work/package"
mkdir -p "$mirror"
for entry in "$root_dir"/* "$root_dir"/.[!.]*; do
  name="$(basename "$entry")"
  case "$name" in
    *.xcodeproj | *.xcworkspace | .build | .build-* | build | .swiftpm | .git) continue ;;
  esac
  ln -s "$entry" "$mirror/$name"
done

reference() {
  cat <<XML
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "$1"
               BuildableName = "$1"
               BlueprintName = "$1"
               ReferencedContainer = "container:">
            </BuildableReference>
XML
}
schemes="$mirror/.swiftpm/xcode/xcshareddata/xcschemes"
mkdir -p "$schemes"
{
  cat <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "2600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
   </BuildAction>
   <TestAction buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
XML
  for bundle in ExportCoreTests HealthKitSourceTests; do
    echo '         <TestableReference skipped = "NO">'
    reference "$bundle"
    echo '         </TestableReference>'
  done
  cat <<'XML'
      </Testables>
   </TestAction>
</Scheme>
XML
} >"$schemes/PackageTests-iOS.xcscheme"

udid="$(xcrun simctl create "ohe-package-tests-$$" "$device_type")"
xcrun simctl boot "$udid"
xcrun simctl bootstatus "$udid" >/dev/null
cd "$mirror"
xcodebuild test \
  -scheme PackageTests-iOS \
  -destination "id=$udid" \
  -derivedDataPath "$work/dd" \
  CODE_SIGNING_ALLOWED=NO
