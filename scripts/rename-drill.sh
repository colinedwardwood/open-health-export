#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# #35 rename drill: swap the identifier root in Brand.xcconfig, and only there, for
# a nonsense one; build the iOS app (with its widget) and the Mac companion; then
# prove the built bundles never mention the real root. Anything that does is an
# identifier hard-coded outside Brand.xcconfig.
#
# Accepted exceptions: the advisory host (#65 moves it); the frozen spec `$id`, which
# is not compiled into any binary; and the synthetic demo sources
# `org.openhealthexporter.synthetic.*`, which the frozen tier-0 fixture records. None
# of them is the identifier root this drill guards.
set -euo pipefail
root_dir="$(cd "$(dirname "$0")/.." && pwd)"
real_root="$(sed -n 's/^PRODUCT_BUNDLE_IDENTIFIER_ROOT = //p' "$root_dir/Brand.xcconfig")"
drill_root="org.renamedrill.zz"
work="$(mktemp -d)"
trap 'git -C "$root_dir" worktree remove --force "$work/tree" >/dev/null 2>&1 || true; rm -rf "$work"' EXIT

git -C "$root_dir" worktree add --detach "$work/tree" HEAD >/dev/null
# Carry uncommitted edits so the drill tests what is on disk.
git -C "$root_dir" diff HEAD | git -C "$work/tree" apply --allow-empty
git -C "$root_dir" ls-files --others --exclude-standard -z \
  | (cd "$root_dir" && xargs -0 -I{} rsync -R "{}" "$work/tree/")
cd "$work/tree"
sed -i '' "s/^PRODUCT_BUNDLE_IDENTIFIER_ROOT = .*/PRODUCT_BUNDLE_IDENTIFIER_ROOT = $drill_root/" Brand.xcconfig
./scripts/generate-project.sh >/dev/null
for build in "-scheme ExporteriOS -sdk iphonesimulator" "-scheme CompanionMac -sdk macosx"; do
  # shellcheck disable=SC2086
  xcodebuild -project OpenHealthExporter.xcodeproj $build -configuration Release \
    -derivedDataPath "$work/dd" SYMROOT="$work/dd/Build/Products" \
    CODE_SIGNING_ALLOWED=NO build >"$work/build.log" 2>&1 \
    || { grep -E 'error:|BUILD FAILED' "$work/build.log" | head -20; exit 1; }
done

status=0
bundles=0
while IFS= read -r -d '' bundle; do
  bundles=$((bundles + 1))
  if grep -r -a -l -F "$real_root" "$bundle" >/dev/null; then
    echo "rename-drill: $bundle still contains $real_root:" >&2
    grep -r -a -l -F "$real_root" "$bundle" >&2
    status=1
  fi
  if ! grep -r -a -q -F "$drill_root" "$bundle"; then
    echo "rename-drill: $bundle never picked up the drill root" >&2
    status=1
  fi
done < <(find "$work/dd/Build/Products" -maxdepth 2 -name '*.app' -print0)
if [[ $bundles -lt 2 ]]; then
  echo "rename-drill: expected the iOS app and the Mac companion, found $bundles bundle(s)" >&2
  status=1
fi
[[ $status -eq 0 ]] && echo "rename-drill: no bundle mentions $real_root outside Brand.xcconfig"
exit $status
