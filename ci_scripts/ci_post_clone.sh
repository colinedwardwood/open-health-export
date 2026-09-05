#!/bin/sh
set -euo pipefail
# Xcode Cloud / laptop / Actions: one generator entry point.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate
elif command -v brew >/dev/null 2>&1; then
  brew install xcodegen
  xcodegen generate
else
  echo "xcodegen is required to materialise the iOS project" >&2
  exit 1
fi
