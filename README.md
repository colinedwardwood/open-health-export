# Open Health Exporter

An Apple Health exporter that tells you the truth about what it did.

This repository is in Stage 3 (implementation). Requirements: `docs/01-prd/PRD.md`.
Design: `docs/02-design/00-system-design.md`.

**Not a medical device.** Do not hide this app to watch someone else's health data.

## Licence

AGPL-3.0 with an additional permission under §7 for App Store distribution. See `LICENSE`
and `COPYING`. Contributions require DCO sign-off (`git commit -s`).

## Build

Toolchain: Swift 6.3.3. The core package builds on Linux.

```
swift test
swift run policycheck
```

HealthKit is confined to `Sources/HealthKitSource`. The Linux job fails if core imports it.

iOS harness (M0 / R-70):

```
./scripts/generate-project.sh
open OpenHealthExporter.xcodeproj
```

Requires [XcodeGen](https://github.com/yonaskolb/XcodeGen). The `.xcodeproj` is generated and
not committed. Run on a physical iPhone (REF-B or iPhone XR) for a populated Health store.
Acknowledge the locked-device disclosure before Health permission.

On the wire, destinations receive **`ohe.wire/1` NDJSON** (see `docs/02-design/03-wire-format-spec.md`).
HTTPS POSTs that file with `Idempotency-Key` and `Content-Type: application/x-ndjson; profile="ohe.wire/1"`.
JSON document, CSV, and the Health Auto Export profile are specified but not emitted yet.

## Status

`maintained` — v1 not yet released. Minimum iOS 18.0. Mac companion is a notarised Developer ID
app, not Mac App Store.
