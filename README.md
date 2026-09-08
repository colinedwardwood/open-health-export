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

Validate the committed conformance sequence with the reference receiver:

```
swift run receiver -- spec/v1.0.0/fixtures/receiver-sequence.ndjson
```

The command prints the converged final state. The receiver tolerates additive record kinds and
fields while applying quantity upserts and tombstones.

iOS harness (M0 / R-70):

```
./scripts/generate-project.sh
open OpenHealthExporter.xcodeproj
```

Requires [XcodeGen](https://github.com/yonaskolb/XcodeGen). The `.xcodeproj` is generated and
not committed. Run on a physical iPhone (REF-B or iPhone XR) for a populated Health store.
Acknowledge the locked-device disclosure before Health permission.

If this app disappears from the Home Screen, that is an iOS feature we cannot
prevent. Our binary has no stealth mode, alternate icons, or second name. Check
Settings → Apps → Hidden Apps, Screen Time, Battery, and App Store purchase
history. Apple's guide: <https://support.apple.com/guide/personal-safety/lock-or-hide-apps-on-your-iphone-ipsd0be4c185/web>.

On the wire, destinations receive **`ohe.wire/1` NDJSON** (see `docs/02-design/03-wire-format-spec.md`).
HTTPS POSTs that file with `Idempotency-Key` and `Content-Type: application/x-ndjson; profile="ohe.wire/1"`.
JSON document, CSV, and the Health Auto Export profile are specified but not emitted yet.

The sole built-in network host is the security advisory feed
`https://advisories.openhealthexporter.org/advisories/v1.json` (R-38). It is fetched only on a
user-visible foreground launch, never during export, and is disableable in the app. The GET
carries marketing major.minor in `User-Agent` and nothing else identifying. Block it at your
resolver if you do not want the fetch.

## Status

`maintained` — v1 not yet released. Minimum iOS 18.0. Mac companion is a notarised Developer ID
app, not Mac App Store.
