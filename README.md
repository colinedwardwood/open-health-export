
# Open Health Exporter

An Apple Health exporter that tells you the truth about what it did.

This repository is in Stage 3 (implementation). Requirements: `docs/01-prd/PRD.md`.
Design: `docs/02-design/00-system-design.md`.

**Not a medical device.** This is not a medical device. It does not diagnose or treat anything.
Do not hide this app to watch someone else's health data.

## Licence

AGPL-3.0 with an additional permission under §7 for App Store distribution. See `LICENSE`
and `COPYING`. Third-party and system-library attribution is generated into `NOTICE` and
shown in the in-app Acknowledgements screen. Contributions require DCO sign-off
(`git commit -s`).

You can read the exact source of any released version, verify that every artifact we publish
came from that source, and build a working app yourself from a clean machine.
You cannot verify that the App Store binary matches, because Apple re-signs and encrypts
App Store binaries before delivering them. If bit-for-bit verification matters to you, build
from source — and that path is tested on every release precisely so that it works.

## Build

Toolchain: Swift 6.3.3. The core package builds on Linux.

```
swift test
swift run policycheck
```

HealthKit is confined to `Sources/HealthKitSource`. The Linux job fails if core imports it.
To complete a synthetic simulator export without Health access, follow the
[demo quickstart](docs/03-implementation/demo-quickstart.md).

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
NDJSON. Native `ohe.wire/1` is the archive. The HAE sidecar is a compatibility export —
correctness claims do not apply — and never arms freshness, overdue, or monitoring surfaces.

Deletion tombstones are **best-effort** because HealthKit provides no deletion
callback and iOS may not wake the app when a deletion occurs. A later
reconciliation sweep compares date-ranged HealthKit contents with the emitted
index and repairs missed deletions.

iOS also provides no authorization-revocation callback. The app checks selected
types at every foreground launch and background wake; when it observes a revocation,
it disables and purges that type. Until the next execution, exposure is bounded by
the queue's seven-day TTL and size cap. Access can be revoked in iOS Health settings.

The sole built-in network host is the security advisory feed
`https://advisories.openhealthexporter.org/advisories/v1.json` (R-38). It is fetched only on a
user-visible foreground launch, never during export, and is disableable in the app. The GET
carries marketing major.minor in `User-Agent` and nothing else identifying. Block it at your
resolver if you do not want the fetch.
Plain HTTP on the LAN is allowed only through `NSAllowsLocalNetworking`. Any
`NSAllowsArbitraryLoads` key in an app Info.plist fails `policycheck`.

Every new destination starts with zero Health types and cannot export until you choose its
types and date range. **Use Core Daily** explicitly applies the 27 named routine families
(quantities plus sleep, mindful sessions, and workouts) to the destination being edited.
Sensitive types and blood glucose are in the picker, not in that preset. The data browser
filter **Only types with data** is on by default.

Store characterisation (QA-08, opt-in, no Health values):

```
swift run characterise path/to/export.ndjson
```

The JSON is counts, month ranges, source classes, and histograms. It must not contain sample
values or identifiers. Paste it into an issue if you volunteer a real store; two recorded
stores are still required before v1 claims corpus realism.

Freshness target N is per class A–D. Each class is pending R-71 device evidence until that
device has ≥14 days and ≥100 samples in the class; then N is that device's measured p95.
The overdue alarm floor is **6 hours**; this is not a delivery promise.

## Status

`seeking-maintainers` — v1 is not yet released and the project currently has one maintainer.
<!-- maintenance-status: seeking-maintainers -->

| Supported platform | Minimum / toolchain | Release support |
|---|---|---|
| iOS | 18.0 | Planned v1; no App Store release yet |
| macOS companion | 15.0 | Notarised Developer ID app; not Mac App Store |
| Linux core | Swift 6.3.3 | Package build and tests only |

How to contribute: `CONTRIBUTING.md`. Vulnerabilities: `SECURITY.md`. Support limits:
`SUPPORT.md`. Conduct: `CODE_OF_CONDUCT.md`. Continuity: `CONTINUITY.md`.
Version streams: `VERSIONING.md`. What R-108 claims: `PROVENANCE.md`. Runtime licences:
`dependencies/policy.md`. App Store listing copy (not submitted): `store/en/`.
Privacy and outward data flows: `PRIVACY.md` and `compliance/egress-inventory.json`.
Secure-development and vulnerability governance: `CYBERSECURITY.md`. The project's explicit
covered-entity stop condition—not a claim of HIPAA status or legal review—is documented in
`compliance/HIPAA-CONTEXT.md`.
Monitoring signal and failure taxonomy: `docs/03-implementation/r27-failure-taxonomy.md`.
Uninstall and complete data-removal steps: `docs/03-implementation/uninstall-and-data-removal.md`.
Repository-complete work and external release gates: `docs/03-implementation/final-scope-audit.md`.
Volunteer device runs: `qa/community-device-matrix/CHECKLIST.md`. Energy measurement
(not a CI gate): `qa/energy-protocol.md`.
Reference receiver and Grafana lab stack: `receiver/README.md` (`docker compose up` from
`receiver/`). Grafana community-catalogue upload is not part of this repository.
