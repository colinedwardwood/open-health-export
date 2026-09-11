
# Open Health Exporter

An Apple Health exporter that tells you the truth about what it did.

This repository is in Stage 3 (implementation). Requirements: `docs/01-prd/PRD.md`.
Design: `docs/02-design/00-system-design.md`.

**Not a medical device.** This is not a medical device. It does not diagnose or treat anything.
Do not hide this app to watch someone else's health data.

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
./scripts/build-from-source.sh
```

That is the stranger-test path (QA-30): generate the project, then ad-hoc-sign the
simulator app and the Mac companion. It needs [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`) and no Apple Developer Program membership. The `.xcodeproj` is
generated and not committed.

A physical iPhone needs a free personal team in Xcode — the device SDK will not accept
ad-hoc identity, and HealthKit entitlements require a development certificate. Open
`OpenHealthExporter.xcodeproj`, pick your Personal Team, and run on the phone (REF-B or
iPhone XR) for a populated Health store. Acknowledge the locked-device disclosure before
Health permission.

Full-history backfill is user-initiated. On iOS 26 and later it uses the
system's continued-processing UI and can finish unattended. On iOS 18–25 it
requires foreground time; keep the app open.
First-run backfill exports aggregates only. Raw-history backfill is a separate
explicit action.

If this app disappears from the Home Screen, that is an iOS feature we cannot
prevent. Our binary has no stealth mode, alternate icons, or second name. Check
Settings → Apps → Hidden Apps, Screen Time, Battery, and App Store purchase
history. Apple's guide: <https://support.apple.com/guide/personal-safety/lock-or-hide-apps-on-your-iphone-ipsd0be4c185/web>.

On the wire, destinations receive **`ohe.wire/1` NDJSON** (see `docs/02-design/03-wire-format-spec.md`).
HTTPS and MQTT destinations show a confirmation card with the grouped certificate fingerprint
and a dry-run canary **before** Health data can move. An unacknowledged destination change
keeps a non-dismissible in-app banner until you acknowledge it.
HTTPS POSTs that file with `Idempotency-Key` and `Content-Type: application/x-ndjson; profile="ohe.wire/1"`.
A local-file destination also writes JSON, CSV, and Health Auto Export sidecars next to the
NDJSON. Those sidecars are convenience views of the same batch, not a second source of truth.

Deletion tombstones are **best-effort** because HealthKit provides no deletion
callback and iOS may not wake the app when a deletion occurs. A later
reconciliation sweep compares date-ranged HealthKit contents with the emitted
index and repairs missed deletions.

The sole built-in network host is the security advisory feed
`https://advisories.openhealthexporter.org/advisories/v1.json` (R-38). It is fetched only on a
user-visible foreground launch, never during export, and is disableable in the app. The GET
carries marketing major.minor in `User-Agent` and nothing else identifying. Block it at your
resolver if you do not want the fetch.

Freshness target: pending R-71 device evidence. The overdue alarm floor is
**6 hours**; this is not a delivery promise.

## Status

`seeking-maintainers` — v1 is not yet released and the project currently has one maintainer.
Minimum iOS 18.0. Mac companion is a notarised Developer ID app, not Mac App Store.

How to contribute: `CONTRIBUTING.md`. Vulnerabilities: `SECURITY.md`. Support limits:
`SUPPORT.md`. Conduct: `CODE_OF_CONDUCT.md`. Continuity: `CONTINUITY.md`.
