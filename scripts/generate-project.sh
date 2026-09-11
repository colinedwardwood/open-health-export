#!/bin/sh
# SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "Install XcodeGen (brew install xcodegen), then re-run." >&2
  exit 1
fi
xcodegen generate
echo "Wrote OpenHealthExporter.xcodeproj"
