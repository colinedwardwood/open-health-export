# Stage 3/4 scope audit

Audit date: 2026-09-11.

This file separates repository-complete engineering work from evidence that cannot be produced honestly without hardware, elapsed time, external accounts, another maintainer, publication, or legal review. “Repository complete” does not mean release-ready.

## Repository-complete controls

- Health destinations default to zero selected types; type and date scopes are canonical state and are checked before enablement and export (SEC-16, R-62).
- Destination tests, pinning, connect-time address-class checks, typed public-address confirmation, and explicit MQTT QoS/LWT exclusions are enforced on real transport paths (R-25, R-31, R-32, SEC-09–SEC-15).
- The optional foreground privacy gate fails closed without entering background export or delivery paths; stored credentials have no reveal path (SEC-29, SEC-65).
- Managed state uses the Class C Data Protection floor, payload directories use Class B, SQLite opens with its explicit protection flag, and managed storage is excluded from backup (SEC-30, SEC-32, ADR-0002).
- Destructive wipe covers every app credential service, pairing and signing identities, queued/delivered managed payloads, destination sidecars, logs, snapshots, and preferences. The Mac companion deletes only receipt-ledger-owned archives and documents manual login-keychain cleanup (R-43, SEC-69).
- General pasteboard APIs are prohibited by repository policy across app and source targets (SEC-44).
- Diagnostic, telemetry, and notification redaction use closed schemas and canaries. OTLP is opt-in, HTTP+protobuf only, cardinality-bounded, and has no dedicated background schedule (R-26, R-27, OBS-07, OBS-14, OBS-17–OBS-25).
- T1 generation and pipeline validation cover all ten million records. The full quantity stream is passed through bounded `ExportRun` pages with exact parsed/submitted accounting and a 100 MiB Linux RSS gate. T2 generation covers fifty million deterministic pathological records (R-82, QA-04, QA-19, QA-24).
- Release policy checks cover localization completeness, pseudo/RTL UI suites, privacy manifests and egress inventory, sponsor gating, release issue evidence, flake reporting, focused coverage, and explicit state-transition test evidence (QA-26–QA-33, R-107–R-110).
- Credential-free `.tributary` configuration documents reject unknown/secret fields and can only produce disabled, test-required drafts after exact typed confirmation (R-67, SEC-18).

## Pending automated run

The manually dispatched `nightly-volume` run is the first remote execution of the new full T1 `ExportRun` and Linux RSS gate. Its result is CI evidence, not physical-device evidence. A failure must be fixed before this item is treated as verified.

## External-only release gates

- R-70, R-71 and R-73: named-device HealthKit throughput, background-delivery behavior, cold background launch, and the five-week wake study.
- R-87 / QA-34: signed real-device pass over at least two years and three sources.
- R-88 / QA-35: twenty-one continuous days of soak plus final reconciliation.
- R-33 / SEC-30: real encrypted Finder/iCloud backup and restore inspection.
- R-77–R-79, QA-23–QA-25, OBS-20 and OBS-32: on-device energy, memory, launch, and overhead measurements.
- Manual VoiceOver, locked-device notification/widget, app-switcher snapshot, Hide-and-Require-Face-ID, and other SPIKE-COERCE observations.
- App Store Connect/TestFlight declarations, DSA trader status, review notes, beta cadence, phased release, and notarized distribution.
- Independent clean release build and continuity review. D-10 explicitly rejects
  maintainer recruitment; R-105a/R-105b are not pursued.
- Legal opinions, HIPAA/CRA role determinations, and trademark/name clearance.
- HACS default-list acceptance, Grafana community publication, and real community-device/store-characterisation rows.
- Live advisory-host logging/retention verification and a physical-device release-rehearsal advisory.

Synthetic fixtures, simulator results, templates, and source review must never be substituted for those gates.

## Explicitly deferred Should work

- Signed QR configuration import awaits decisions on signing authority, trust bootstrap, rotation, revocation, and ownership. The credential-free file contract remains available.
- iCloud Keychain synchronization remains absent; credentials stay non-synchronizing and device-only.
- Full OpenTelemetry child-span instrumentation, watchOS network telemetry, and community catalogue publication remain deferred. None weakens the default-zero telemetry or health-export correctness contracts.
- HACS publication is post-v1 work; no listing is claimed.
