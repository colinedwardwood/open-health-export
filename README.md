# Open Health Exporter

An Apple Health exporter that tells you the truth about what it did.

It exists because silent failure is the usual failure in this category: an export
stops, or reports success while delivering nothing, and nobody notices for weeks.
This project is for one person moving **their own** Apple Health data to
destinations they control — with a documented wire format, a visible run outcome,
and an overdue signal when delivery has been quiet too long.

It remains open source so you can read the code that touches health data, check
the published contracts, and build the app yourself. Transparency, auditability,
and the ability to inspect behaviour are product advantages. Open source does not
by itself make software secure; the security posture is the combination of those
inspectable controls, default-off egress, and the limits described below.

This is an owner-directed commercial product intended for paid distribution. It
is not a community-maintained project, and this repository does not recruit
maintainers. Source stays public; product direction stays with the owner.

**This is not a medical device. It does not diagnose or treat anything.** Do not
hide this app to watch someone else's health data.

## Who it is for

Typical jobs:

- Land chosen metrics in **Home Assistant** or another MQTT consumer, and notice
  when the pipeline goes quiet.
- Keep a durable archive of your own samples in a stable, documented format
  (`ohe.wire/1` NDJSON), including a user-initiated full-history backfill.
- POST that same archive to an HTTPS receiver you run (or use the reference
  receiver in this repository).
- Pair an iPhone to the **Mac companion** over the local network and receive
  files on the Mac. The Mac cannot read HealthKit; it is a receiver and pairing
  surface, not an exporter.
- Take a one-shot local-file archive (Files.app) without standing up a server.

It is not for exporting another person's data, for clinical or research
completeness claims, or for pretty charts. Apple Health already charts; this app
is about honest delivery.

## Status

`pre-release` — v1 is not released. There is no App Store listing yet. Marketing
version **0.1.0** currently emits wire profile `ohe.wire/1` from `spec/v1.0.0`
(in progress until freeze). See `spec/compatibility.json` and `VERSIONING.md`.

<!-- maintenance-status: maintained -->

| Platform | Minimum / toolchain | Release support |
|---|---|---|
| iOS (iPhone and iPad) | 18.0 | Planned v1 commercial App Store release; not submitted |
| macOS companion | 15.0 | Intended as a notarised Developer ID app, not Mac App Store; notarisation is an external gate and is not done |
| Linux core | Swift 6.3.3 | Package build and tests only |

This repository is in **Stage 3 (implementation)**. Requirements:
[`docs/01-prd/PRD.md`](docs/01-prd/PRD.md). Design:
[`docs/02-design/00-system-design.md`](docs/02-design/00-system-design.md).
Repository-complete engineering is separated from hardware, elapsed-time, store,
legal, and publication gates in
[`docs/03-implementation/final-scope-audit.md`](docs/03-implementation/final-scope-audit.md).
Do not read “in the tree” as “release-ready.”

Freshness target N is per class A–D. Each class stays pending R-71 device
evidence until that device has ≥14 days and ≥100 samples in the class; then N is
that device's measured p95. The overdue alarm floor is **6 hours**; that is not a
delivery promise. Two recorded real-store characterisations are still required
before v1 claims corpus realism.

## What is in this repository

| Path | Role |
|---|---|
| `Sources/` | Swift package: correctness engine, sinks, wire format, catalogue. HealthKit stays in `Sources/HealthKitSource` (Darwin only). |
| `Apps/Exporter-iOS`, `Apps/StatusWidget` | iOS exporter and status widget |
| `Apps/Companion-macOS` | Local-network companion receiver |
| `spec/v1.0.0/` | Wire schema, catalogue, and synthetic fixtures |
| `Tools/` | `policycheck`, `receiver`, `characterise`, corpus and contract helpers |
| `receiver/` | Reference receiver plus a loopback Grafana lab stack |
| `docs/` | PRD, design, and implementation notes |
| `store/en/` | App Store listing copy (**not submitted**) |
| `compliance/` | Egress inventory, covered-entity stop-condition note, privacy-label candidate |

The `.xcodeproj` is generated and not committed.

## Destinations and outputs

On the wire, destinations receive **`ohe.wire/1` NDJSON**. Schema and semantics:
[`docs/02-design/03-wire-format-spec.md`](docs/02-design/03-wire-format-spec.md).

Supported sinks in this tree:

- **Local folder** — native NDJSON is the archive. The same destination also
  writes JSON, CSV, and Health Auto Export sidecars. The HAE sidecar is a
  compatibility export: correctness claims do not apply to it, and it never arms
  freshness, overdue, or monitoring surfaces.
- **HTTPS** — POST of that NDJSON file with `Idempotency-Key` and
  `Content-Type: application/x-ndjson; profile="ohe.wire/1"`.
- **MQTT 3.1.1** (publish-only) — including Home Assistant discovery generated
  from the catalogue. HACS default-list publication is not part of this
  repository and is not claimed.
- **Mac companion** — Bonjour discovery of a paired name, then TLS 1.2 PSK on Network.framework.
  Discovery is not authorization.

HTTPS and MQTT destinations show a confirmation card with the grouped certificate
fingerprint and a dry-run canary **before** Health data can move. An
unacknowledged destination change keeps a non-dismissible in-app banner until you
acknowledge it.

Every new destination starts with **zero Health types** and cannot export until
you choose its types and date range. **Use Core Daily** applies the 27 named
routine families (quantities plus sleep, mindful sessions, and workouts) to the
destination being edited. Sensitive types and blood glucose are in the picker,
not in that preset. The data-browser filter **Only types with data** is on by
default.

Optional **OTLP** is off by default. When enabled it sends redacted operational
events to an endpoint you configure — no Health values, and not telemetry
received by this project.

Grafana: `docker compose up` from `receiver/` runs a lab dashboard on loopback.
Grafana community-catalogue upload is not part of this repository.

## Privacy and security

Designed without accounts, advertising, analytics, crash reporting, or a
developer-operated Health-data service. Authoritative egress:
[`PRIVACY.md`](PRIVACY.md) and
[`compliance/egress-inventory.json`](compliance/egress-inventory.json).

The sole built-in network host is the security advisory feed
`https://advisories.openhealthexporter.org/advisories/v1.json`. It is fetched only
on a user-visible foreground launch, never during export, and is disableable in
the app. The GET carries marketing major.minor in `User-Agent` and nothing else
identifying. Block it at your resolver if you do not want the fetch. Plain HTTP
on the LAN is allowed only through `NSAllowsLocalNetworking`. Any
`NSAllowsArbitraryLoads` key in an app Info.plist fails `policycheck`.

Deletion tombstones are **best-effort** because HealthKit provides no deletion
callback and iOS may not wake the app when a deletion occurs. A later
reconciliation sweep compares date-ranged HealthKit contents with the emitted
index and repairs missed deletions.

iOS also provides no authorization-revocation callback. The app checks selected
types at every foreground launch and background wake; when it observes a
revocation, it disables and purges that type. Until the next execution, exposure
is bounded by the queue's seven-day TTL and size cap. Access can be revoked in
iOS Health settings.

If this app disappears from the Home Screen, that is an iOS feature this project
cannot prevent. The binary has no stealth mode, alternate icons, or second name.
Check Settings → Apps → Hidden Apps, Screen Time, Battery, and App Store purchase
history. Apple's guide:
<https://support.apple.com/guide/personal-safety/lock-or-hide-apps-on-your-iphone-ipsd0be4c185/web>.

The project is not a HIPAA covered entity and does not claim business-associate
status. The explicit stop condition is
[`compliance/HIPAA-CONTEXT.md`](compliance/HIPAA-CONTEXT.md).

## Licence and source

AGPL-3.0 with an additional permission under §7 for App Store distribution. See
[`LICENSE`](LICENSE) and [`COPYING`](COPYING). Documentation under `docs/` is
CC BY 4.0 unless a file says otherwise. The wire spec and its fixtures under
`spec/` are CC0-1.0. Third-party and system-library attribution is generated into
[`NOTICE`](NOTICE) and shown in the in-app Acknowledgements screen.

You can read the exact source of any released version, verify that every artifact
this project publishes came from that source, and build a working app yourself
from a clean machine. You cannot verify that the App Store binary matches,
because Apple re-signs and encrypts App Store binaries before delivering them.
If bit-for-bit verification matters to you, build from source — that path is
tested on every release precisely so that it works. Until the first GitHub
release exists, auditable source is the git history on `main`. What R-108 claims:
[`PROVENANCE.md`](PROVENANCE.md).

## Getting started

Toolchain: **Swift 6.3.3**. The core package builds on Linux. HealthKit is
confined to `Sources/HealthKitSource`; `policycheck` fails the Linux job if core
imports it.

```sh
swift test
swift run policycheck
```

Validate the committed conformance sequence with the reference receiver:

```sh
swift run receiver -- spec/v1.0.0/fixtures/receiver-sequence.ndjson
```

The command prints the converged final state. The receiver tolerates additive
record kinds and fields while applying quantity upserts and tombstones. Lab stack:

```sh
cd receiver && docker compose up
```

To complete a synthetic simulator export without Health access, follow the
[demo quickstart](docs/03-implementation/demo-quickstart.md).

Build the iOS simulator app and Mac companion from a clean checkout: generate
the project, then ad-hoc-sign both. Needs
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) and
no Apple Developer Program membership.

```sh
./scripts/build-from-source.sh
```

A physical iPhone needs a free personal team in Xcode — the device SDK will not
accept ad-hoc identity, and HealthKit entitlements require a development
certificate. Open `OpenHealthExporter.xcodeproj`, pick your Personal Team, and
run on the phone (REF-B or iPhone XR) for a populated Health store. Acknowledge
the locked-device disclosure before Health permission.

Full-history backfill is user-initiated. On iOS 26 and later it uses the
system's continued-processing UI and can finish unattended. On iOS 18–25 it
requires foreground time; keep the app open. First-run backfill exports
aggregates only. Raw-history backfill is a separate explicit action.

Store characterisation (QA-08, opt-in, no Health values):

```sh
swift run characterise path/to/export.ndjson
```

The JSON is counts, month ranges, source classes, and histograms. It must not
contain sample values or identifiers.

Uninstall and complete data-removal steps:
[`docs/03-implementation/uninstall-and-data-removal.md`](docs/03-implementation/uninstall-and-data-removal.md).

## Commercial availability

The intended paid distribution is the iOS app on the App Store, with a Developer
ID Mac companion. Listing copy lives in `store/en/` and has **not** been
submitted. There is no TestFlight, no published price, and no in-app purchase
surface in this tree. Build-from-source remains available under the licence
whether or not a store build exists.

## Support, bugs, and security

Support is best-effort. There is no SLA and no chat. Limits:
[`SUPPORT.md`](SUPPORT.md). Conduct: [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md).

Use GitHub Issues for bugs in the app, exporter, or wire format. **Do not paste
real HealthKit values**, tokens, private hostnames, or crash logs that contain
them.

Vulnerabilities: [`SECURITY.md`](SECURITY.md) — private report via the GitHub
Security Advisories tab. Do not file security issues in the public tracker.
Secure-development policy (engineering practice, not a CRA or legal claim):
[`CYBERSECURITY.md`](CYBERSECURITY.md).

## Further reading

- Repository participation policy (this project does not recruit maintainers):
  [`CONTRIBUTING.md`](CONTRIBUTING.md)
- Optional device-evidence protocol:
  [`qa/community-device-matrix/CHECKLIST.md`](qa/community-device-matrix/CHECKLIST.md)
- Energy measurement protocol (not a CI gate):
  [`qa/energy-protocol.md`](qa/energy-protocol.md)
- Runtime licences: [`dependencies/policy.md`](dependencies/policy.md)
- Monitoring signal and failure taxonomy:
  [`docs/03-implementation/r27-failure-taxonomy.md`](docs/03-implementation/r27-failure-taxonomy.md)
- Reference receiver: [`receiver/README.md`](receiver/README.md)
