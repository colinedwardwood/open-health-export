<!--
SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# R-73 launch-latency findings

**Status:** pending physical-device measurement  
**Protocol:** at least 100 cold background launches per device  
**Raw signpost export paths:** TODO

The host result in `qa/baselines/` is a regression proxy only. Do not paste it
into the device rows below or use it to claim the 400 ms threshold.

## Required dimensions

| Requirement | Workload | Device | OS | Metric | Threshold | Percentile |
|---|---|---|---|---|---|---|
| R-73 | Headless background launch → first HealthKit query | REF-B | iOS 26 build TODO | wall clock ms | ≤400 ms | p90 |
| R-73 | Same, threshold-setting run | REF-C | iOS 18 build TODO | wall clock ms | measured at M0 | p90 |

## Run conditions

| Device | Model | OS build | App build | Install | Battery | LPM | Thermal | Launches kept / discarded |
|---|---|---|---|---|---:|---|---|---|
| REF-B | TODO | TODO | TODO | TODO | TODO | TODO | TODO | TODO |
| REF-C | TODO | TODO | TODO | TODO | TODO | TODO | TODO | TODO |

## Results

| Device | Samples | p50 ms | p90 ms | max ms | Threshold | Margin | Evidence |
|---|---:|---:|---:|---:|---:|---:|---|
| REF-B | TODO (≥100) | TODO | TODO | TODO | 400 | TODO | TODO |
| REF-C | TODO (≥100) | TODO | TODO | TODO | set from measurement | n/a | TODO |

## Permitted-operation breakdown

| Device | Process + dyld | HKHealthStore init | SQLite open / recovery | Anchor read | Query construct / dispatch |
|---|---:|---:|---:|---:|---:|
| REF-B p90 ms | TODO | TODO | TODO | TODO | TODO |
| REF-C p90 ms | TODO | TODO | TODO | TODO | TODO |

## Disposition

- REF-B R-73: TODO — pass / fail.
- REF-C threshold adopted: TODO ms p90.
- If REF-B fails, investigation evidence in order: SQLite open, catalogue
  load, observer registration: TODO.
- R-91 baseline status and release protocol mapping: TODO.
