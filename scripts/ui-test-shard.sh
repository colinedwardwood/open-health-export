#!/usr/bin/env bash
# Prints the -only-testing arguments for one shard of the XCUITest suite.
#
# The list is derived from the test source rather than maintained by hand, so a new
# case cannot be silently left out of every shard — which would be a test that stopped
# running while CI stayed green.
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  echo "usage: $0 <shard-index-from-zero> <shard-count>" >&2
  exit 2
fi

index="$1"
count="$2"
source_file="Tests/ExporterUITests/ExporterUITests.swift"
target="ExporteriOSUITests"
suite="ExporterUITests"

if [[ ! -f "$source_file" ]]; then
  echo "UI test source not found: $source_file" >&2
  exit 1
fi

# bash 3.2 ships on macOS runners, so no mapfile.
cases=()
while IFS= read -r case_name; do
  cases+=("$case_name")
done < <(sed -n 's/^[[:space:]]*func \(test[A-Za-z0-9_]*\)().*/\1/p' "$source_file" | sort)

if [[ "${#cases[@]}" -eq 0 ]]; then
  echo "No test cases found in $source_file" >&2
  exit 1
fi

selected=0
for i in "${!cases[@]}"; do
  if [[ $((i % count)) -eq "$index" ]]; then
    printf -- '-only-testing:%s/%s/%s\n' "$target" "$suite" "${cases[$i]}"
    selected=$((selected + 1))
  fi
done

if [[ "$selected" -eq 0 ]]; then
  echo "Shard $index of $count selected no cases from ${#cases[@]}" >&2
  exit 1
fi
