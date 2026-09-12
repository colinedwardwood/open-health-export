---
title: Complete bounded OTLP observability contracts
type: changed
---

- Emit bounded per-destination last-success and staleness gauges to the configured collector's OTLP/HTTP metrics endpoint.
- Remove the dedicated telemetry background task so telemetry never consumes an export wake budget.
- Keep runtime telemetry attributes inside explicit cardinality limits and map unknown values to `other`.
- Preserve useful diagnostic bundles when network, authorization, configuration, database, or journal subsystems are degraded.
- Gate telemetry serializer isolation and prove unprojected journal entries survive a process-level store reopen before delivery.
- Lint app and core sources so logging stays behind the reviewed `os.Logger` boundary, unreviewed public interpolation fails, and release plists cannot enable private log data.
- Split telemetry into its own app-linked product and add a Release iphoneos A/B
  build gate for its uncompressed `.app` payload delta. The initial measured
  contribution is 362,761 bytes against the 2 MiB OBS-25 ceiling; shipped
  binaries are also scanned for gRPC, SwiftNIO, SwiftProtobuf, and OTel SDK links.
