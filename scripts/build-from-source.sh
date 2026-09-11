#!/bin/sh
# SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
# SPDX-License-Identifier: AGPL-3.0-or-later
# QA-30 / R-108: the stranger-test build. No paid Apple Developer Program, no App
# Store Connect, and no flags that skip signing.
#
# The device SDK refuses ad-hoc identity on iOS 26, and the HealthKit entitlement
# needs a development certificate. A physical phone is therefore signed in Xcode
# with a free personal team. This script is the path that CI and a clean laptop
# can run: simulator SDK plus the Mac companion, both with ad-hoc identity.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/generate-project.sh
xcodebuild \
  -project OpenHealthExporter.xcodeproj \
  -scheme ExporteriOS \
  -sdk iphonesimulator \
  -configuration Debug \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=YES \
  DEVELOPMENT_TEAM= \
  build
xcodebuild \
  -project OpenHealthExporter.xcodeproj \
  -target CompanionMac \
  -sdk macosx \
  -configuration Debug \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=YES \
  DEVELOPMENT_TEAM= \
  build
