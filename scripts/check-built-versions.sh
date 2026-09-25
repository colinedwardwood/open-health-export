#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Checks a built iOS app (#32): the app and every embedded extension carry the same
# version and build, and the source commit was stamped. App Store Connect rejects an
# extension whose version differs from its app (ITMS-90473).
set -euo pipefail
app="${1:?usage: scripts/check-built-versions.sh path/to/App.app}"

read_key() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Info.plist" 2>/dev/null || true; }

version="$(read_key "$app" CFBundleShortVersionString)"
build="$(read_key "$app" CFBundleVersion)"
commit="$(read_key "$app" OHESourceCommit)"
status=0
if [[ -z "$version" || -z "$build" || "$version" == *'$('* || "$build" == *'$('* ]]; then
  echo "check-built-versions: $app has no resolved version/build ($version/$build)" >&2
  status=1
fi
if [[ -z "$commit" || "$commit" == "unspecified" ]]; then
  echo "check-built-versions: $app source commit is '${commit:-missing}'" >&2
  status=1
fi
shopt -s nullglob
for appex in "$app"/PlugIns/*.appex; do
  ext_version="$(read_key "$appex" CFBundleShortVersionString)"
  ext_build="$(read_key "$appex" CFBundleVersion)"
  if [[ "$ext_version" != "$version" || "$ext_build" != "$build" ]]; then
    echo "check-built-versions: $(basename "$appex") is $ext_version ($ext_build), app is $version ($build)" >&2
    status=1
  fi
done
[[ $status -eq 0 ]] && echo "check-built-versions: $version ($build) at $commit"
exit $status
