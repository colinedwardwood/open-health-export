---
title: Complete bounded OTLP observability contracts
type: changed
---

- Emit bounded per-destination last-success and staleness gauges to the configured collector's OTLP/HTTP metrics endpoint.
- Remove the dedicated telemetry background task so telemetry never consumes an export wake budget.
- Keep runtime telemetry attributes inside explicit cardinality limits and map unknown values to `other`.
- Preserve useful diagnostic bundles when network, authorization, configuration, database, or journal subsystems are degraded.
- Gate telemetry serializer isolation and prove unprojected journal entries survive a process-level store reopen before delivery.
