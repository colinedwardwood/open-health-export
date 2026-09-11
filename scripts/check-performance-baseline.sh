#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

set -euo pipefail

baseline="${1:-qa/baselines/m0-host-permitted-launch.json}"
candidate="${2:-${RUNNER_TEMP:-/tmp}/m0-host-permitted-launch-candidate.json}"
comparison="${3:-${RUNNER_TEMP:-/tmp}/m0-host-permitted-launch-comparison.json}"
iterations="${OHE_PERFORMANCE_ITERATIONS:-100}"

swift build -c release --product m0harness
binary="$(swift build -c release --show-bin-path)/m0harness"

"$binary" verify
"$binary" benchmark-launch \
  --iterations "$iterations" \
  --output "$candidate"
"$binary" compare \
  --baseline "$baseline" \
  --candidate "$candidate" \
  --failure-threshold-percent 20 \
  --output "$comparison"

echo "Candidate: $candidate"
echo "Comparison: $comparison"
