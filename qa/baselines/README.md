<!--
SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Performance baselines

`m0-host-permitted-launch.json` is the committed automated baseline for the
host-only R-73 permitted-operation proxy. It measures cold process start,
SQLite open, schema-version comparison, indexed anchor reads, and query-token
construction. It deliberately does not claim to measure HealthKit or iOS
background launch behavior.

Run the comparison on the labelled performance Mac:

```sh
scripts/check-performance-baseline.sh
```

The comparison uses nearest-rank p90 and exits nonzero only when the candidate
is **more than 20% slower** than the baseline. The candidate and comparison are
JSON so the pre-release workflow can retain both as evidence.

To refresh the baseline after an intentional performance change, run the
release-built harness for 100 launches on the same labelled runner, review the
environment and all samples, and replace the file. Never copy device names,
OS versions, or measurements into this directory without actually running the
corresponding protocol.

This automated subset does not close R-70, R-71, R-73, or R-91. Their physical
device evidence belongs in the findings documents under
`docs/02-design/spikes/`.
