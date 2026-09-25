#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Prints the xcodebuild setting overrides that stamp a build (#32):
#   CURRENT_PROJECT_VERSION = number of commits reachable from HEAD
#   OHE_SOURCE_COMMIT       = full HEAD commit, with -dirty for uncommitted changes
# The commit count only grows along main, so App Store build numbers stay monotonic.
# See VERSIONING.md for the hotfix rule.
#
# --optional prints nothing, and succeeds, when there is no full git history to count
# (a source tarball or a shallow CI checkout): that build stays unstamped, which
# check-built-versions.sh reports. Release builds call it without --optional.
set -euo pipefail
cd "$(dirname "$0")/.."

optional=false
[[ "${1:-}" == "--optional" ]] && optional=true
if ! git rev-parse --git-dir >/dev/null 2>&1 \
  || [[ "$(git rev-parse --is-shallow-repository)" == "true" ]]; then
  $optional && exit 0
  echo "version-settings: needs a full git clone; the build number is the commit count" >&2
  exit 1
fi
build="$(git rev-list --count HEAD)"
commit="$(git rev-parse HEAD)"
if ! git diff --quiet HEAD --; then
  commit="${commit}-dirty"
fi
printf 'CURRENT_PROJECT_VERSION=%s\nOHE_SOURCE_COMMIT=%s\n' "$build" "$commit"
