<!--
SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# R-71 background-delivery findings

**Status:** pending five-week physical-device soak  
**Protocol:** `docs/02-design/02-healthkit-layer.md`, R-71  
**Operator / dates:** TODO  
**Raw journal / diary paths:** TODO

Do not infer a missing wake from app telemetry alone. The scripted daily diary
is the denominator, and no numeric freshness target is valid before this
protocol completes.

## Devices and installation

| Device | Model | OS build | Installation method | Debugger detached | Rebooted |
|---|---|---|---|---|---|
| REF-A | TODO | TODO | TestFlight / Xcode | TODO | TODO |
| REF-B | TODO | TODO | TestFlight / Xcode | TODO | TODO |

## Configuration log

| Config | Dates | BAR | Force-quit | LPM | Lock schedule | Complete |
|---|---|---|---|---|---|---|
| C1 | TODO | on | no | off | normal | TODO |
| C2 | TODO | off | no | off | normal | TODO |
| C3 | TODO | TODO | daily | off | normal | TODO |
| C4 | TODO | on | no | on | normal | TODO |
| C5 | TODO | on | no | off | overnight + two daytime hours | TODO |

## Daily diary

Keep raw events machine-readable. At minimum record device, configuration,
expected-write timestamp and class, matching wake timestamp (or `none`),
readable-store result, time-since-lock, battery, thermal state, process-start
to-query milliseconds, wake duration, and evidence path.

| Date | Device | Config | 09:00 walk | 13:00 body mass | 18:00 workout | Overnight sleep | Notes |
|---|---|---|---|---|---|---|---|
| TODO | TODO | TODO | TODO | TODO | TODO | TODO | TODO |

## Per-type inter-wake distributions

| Device | Config | Type | Expected writes | Readable wakes | Missing | p50 | p90 | p95 | max |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|
| TODO | TODO | TODO | TODO | TODO | TODO | TODO | TODO | TODO | TODO |

## Wake duration and launch timing

| Device | Config | Trigger | Samples | Metric | p10 | p50 | p90 | max |
|---|---|---|---:|---|---:|---:|---:|---:|
| TODO | TODO | observer / BG refresh / BG processing | TODO | wake duration ms | TODO | TODO | TODO | TODO |
| TODO | TODO | TODO | TODO | process start → first query ms | TODO | TODO | TODO | TODO |

## Lock-failure curve

| Device | Time-since-lock bucket | Probe attempts | Database inaccessible | Failure rate |
|---|---|---:|---:|---:|
| TODO | TODO | TODO | TODO | TODO |

## Configuration verdicts

| Config | Did automation survive? | Evidence | Product consequence |
|---|---|---|---|
| C1 | TODO | TODO | R-24 class distributions and freshness |
| C2 | TODO | TODO | R-63 / BAR detection |
| C3 | TODO | TODO | R-23 force-quit copy |
| C4 | TODO | TODO | Degradation copy |
| C5 | TODO | TODO | Protected-data retry / locked-phone copy |

## Gates

| Gate | Yes / no / inconclusive | Evidence | Decision |
|---|---|---|---|
| G1 descriptor observer receives background delivery | TODO | TODO | Descriptor / per-type topology; recheck R-73 |
| G2 weekly frequency is honored | TODO | TODO | Coverage cadence |
| G3 completion backoff reproduces and recovers | TODO | TODO | Completion discipline severity |

## Derived decisions

| Input | Measured result | Decision |
|---|---:|---|
| C1 readable-wake p90 by freshness class | TODO | Publish R-24 N values / remain provisional |
| Wake-duration p10 | TODO | Deadline budget TODO |
| C5 lock-failure curve | TODO | Retry and widget copy TODO |
| Per-type caps | TODO | Coverage matrix cadence TODO |
