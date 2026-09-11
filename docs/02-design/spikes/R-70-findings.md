<!--
SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# R-70 HealthKit throughput findings

**Status:** pending physical-device measurement  
**Protocol:** `docs/02-design/02-healthkit-layer.md`, R-70  
**Operator / date:** TODO  
**Raw evidence paths:** TODO

Do not replace `TODO` with estimates. Paste the harness exports and retain the
raw CSV beside this document.

## Devices and controlled conditions

| Run | Device / model | OS build | Store | Battery | LPM | Airplane | Brightness | Install |
|---|---|---|---|---:|---|---|---:|---|
| TODO | TODO | TODO | S1 / S2 / S3 | TODO | off | on | 50% | TODO |

## Store census and seeding

| Store | Type | Samples | Date span | Distinct sources | Seed samples/s |
|---|---|---:|---|---:|---:|
| TODO | TODO | TODO | TODO | TODO | n/a / TODO |

## Thermal log

| Measurement | Repetition | Before | After | Kept / discarded |
|---|---:|---|---|---|
| TODO | TODO | nominal / fair / serious / critical | TODO | TODO |

Discard and repeat any run whose thermal state exceeds `fair`.

## M1–M9 results

Use one row per workload variant. Report five repetitions plus nearest-rank
p50, p90, and max. Do not collapse page size, bucket interval, date span, type,
or store condition into notes.

| ID | Device | Store | Workload variant | Unit | Repetitions | p50 | p90 | max | Evidence |
|---|---|---|---|---|---|---:|---:|---:|---|
| M1 | TODO | TODO | page size TODO | samples/s | TODO | TODO | TODO | TODO | TODO |
| M2 | TODO | TODO | page size TODO | samples/s | TODO | TODO | TODO | TODO | TODO |
| M3 | TODO | TODO | page size TODO | samples/s | TODO | TODO | TODO | TODO | TODO |
| M4 | TODO | TODO | page size TODO | MB phys_footprint | TODO | TODO | TODO | TODO | TODO |
| M5 | TODO | TODO | interval / years TODO | ms and MB | TODO | TODO | TODO | TODO | TODO |
| M6 | TODO | TODO | type TODO | samples/s | TODO | TODO | TODO | TODO | TODO |
| M7 | TODO | TODO | detail type TODO | records/s | TODO | TODO | TODO | TODO | TODO |
| M8 | TODO | TODO | foreground / BG task | ms | TODO | TODO | TODO | TODO | TODO |
| M9 | TODO | S1 | multi-source 90-day divergence | percent | TODO | TODO | TODO | TODO | TODO |

## Decisions

| Result | Observed number | Decision / owner |
|---|---:|---|
| M3 REF-B p90 | TODO | Hold / re-baseline R-72, R-74, R-75, R-78 |
| M1 saturation point | TODO | Production page size TODO |
| M2 seam overhead | TODO | Keep representation / change representation |
| M4 at chosen page size | TODO | R-74 hold / defect |
| M5 cost shape | TODO | Keep / change 2,048 bucket window |
| M7 detail/plain ratio | TODO | Opt-in policy TODO |
| M8 REF-B p90 | TODO | R-73 hold / investigate / renegotiate |
| M9 divergence | TODO | R-07 / AR-30 consequence TODO |

## Mandatory NFR disposition

| NFR | Hold / at risk / void | Measured number and evidence |
|---|---|---|
| R-72 | TODO | TODO |
| R-73 | TODO | TODO |
| R-74 | TODO | TODO |
| R-75 | TODO | TODO |
