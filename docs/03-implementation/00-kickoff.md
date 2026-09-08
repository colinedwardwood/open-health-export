# Stage 3 kickoff

**Opened:** 2026-09-03 after Stage 2 approval.

M0 first: R-70/R-71/R-73 harnesses. R-71 diary can start on-device before the harness exists.

Wedge (M1–M6): engine, journal, watchdog, local-file sink. MQTT, companion, HACS after M6.

First commit in this repo: Linux-buildable L0–L4 targets, `RunOutcome.derive`, thin SQLite
wrapper, import policy check, no HealthKit in core.

Now in tree: `ExportRun`, `LocalFileSink`, `HealthKitSampleSource` (Darwin-only; conversion
inside the query callback), `HealthKitThroughput.measure` for R-70. iOS M0 harness:
`./scripts/generate-project.sh` then open `OpenHealthExporter.xcodeproj`. Run R-70 on REF-B or
the XR (simulator stores are often empty). Local-file payloads are `ohe.wire/1` NDJSON
(header / records / footer). HTTPS POST of that file is in tree (`HTTPSSink` / `NetEgress`). R-31 verification core:
`DestinationSetup` + `VerifiedDestination` (export path no longer takes a raw sink). First-party
MQTT 3.1.1 publish-only is a separate `SinkMQTT` product (not `ExportCore`). Companion frames
and `CompanionSink` are in `ExportCore`.

Local-network egress: `NetEgress.ByteStream` is the sink-facing port and `NWByteStream` is the
package's only `NWConnection` — MQTT and the companion both ride it through pipe adapters. TLS
pins are enforced inside the handshake verify block (zero application bytes on mismatch), with
peer SPKI from `SPKIDigest` over the leaf certificate DER. The companion side dials a Bonjour
`_ohx-recv._tcp` name with a TLS 1.3 PSK; discovery is not authorization, only an exact match on
the paired name is dialable. Pairing material (`PairingSecret`, QR payload, Crockford
confirmation code) is in `CompanionWire`, and `CompanionPSK` in `SinkCompanion` is the only
bridge from a scanned secret to handshake material. Trust changes now leave `DestinationSetup`
as drained `TrustEvent`s mapped to prose-free `UserNotice`s (R-40/R-41).

`wirefuzz` fuzzes the companion and MQTT decoders on Linux in CI (three seeds, one
time-derived). It found and we fixed two non-canonical acceptances in the companion decoder;
decoded frames now re-encode byte-for-byte, which the protocol's digest de-duplication depends
on.

The Mac companion app is in `Apps/Companion-macOS`: folder picker, iCloud warning, pairing
QR plus selectable payload, receive window. After the phone's HELLO the Mac shows the same
SAS the phone computed from the QR. The iOS harness pastes that payload, shows the SAS, and
can push one page over TLS 1.3 PSK to the exact Bonjour name captured at pairing. Pairing
survives a closed receive window: PSK in Keychain, names in a JSON sidecar with no secret.
The phone can scan the QR (VisionKit) or paste. MQTT has a Darwin loopback-TCP test: a test-only
`NWListener` broker plus `NWByteStream`, not a packaged mosquitto.

Error-class registry, HAE loss-gated encoder, MQTT retain-off, Keychain data-protection ACL (no
biometry), and `os.Logger` are in tree. MQTTS is a pinned `NWByteStream` dial; loopback TLS
covers the handshake without a packaged broker. Home Assistant MQTT discovery is generated from the
catalogue (no guessed `device_class`; retain only for config and `online` status). The iOS harness
asks for camera permission before scanning and always keeps paste as a fallback.

**Physical phone (owner):** on the XR / REF-B, scan the Mac QR, confirm the SAS matches after HELLO,
export one page, then forget pairing and pair again. Simulator has no camera and often an empty
Health store.

The catalogue has 26 curated quantity types, including activity totals, cardiac
measurements, temperatures, body composition, hydration and blood pressure.
HA state JSON is encoded separately from discovery and is not eligible for retain.
Blood glucose is canonical `mg/dL` and uses HA's real
`blood_glucose_concentration` class; metrics without a real class still omit it.

Committed payloads are now durable queue rows in the same transaction as cursor advancement.
`PendingDeliveryRunner` replays only the oldest queued batch per sink invocation after a process
restart; only a receipt covering every expected record removes it.

Each live or replayed transport call durably records an egress attempt before calling the sink and
one terminal attempt outcome afterwards. Failed attempts remain pending; empty reads produce no
egress ledger row.

Retry/circuit-breaking is a pure one-result transition: exponential full jitter (15 s / 6 h),
`Retry-After` capped at 24 h, five transient failures or three unknown acknowledgements to open,
and a free foreground real-batch half-open probe. It contains no in-wake retry loop.

The watchdog has no invented default N before R-71. Local p95 becomes eligible after 100 samples
spanning 14 days; the alarm threshold is `clamp(2 × p95, 6 h, 48 h)`.

SQLite metadata defaults to Darwin Class C file protection, WAL + `synchronous=FULL`, and a 4 MB
journal/recovery budget.

R-83's six fault locations are reachable in debug builds. SQLite tests prove faults through the
commit boundary either roll back both cursor and batch or leave a replayable batch; post-write
replay remains idempotent. Release builds omit the injector surface.

R-82 tier zero is a committed 200-record canonical NDJSON corpus generated from seed 1. Linux CI
regenerates it and checks byte identity plus SHA-256.

R-09 enqueue now evicts oldest pending batches inside the same transaction that admits the new
one, down toward a 230 MiB watermark, and records `queue_eviction:<bytes>` gaps. Victim files
are unlinked after COMMIT. R-86 cursor rows are `OHEC` envelopes; corrupt or newer formats fail
closed. Policycheck bans ambient clocks in `Sources/` except CoreTemporal and HealthKitSource.
A DCO workflow requires `Signed-off-by` on every commit.

Successful delta commits now upsert one `emitted_index` row per sample UUID in the
same transaction as the cursor (R-08 write path).

Census rows accumulate across pages with an XOR digest; tombstones decrement the
census and drop the UUID from `emitted_index` when known. Unknown deletions journal
`deletion_undatable`. `ReconcileCompare` classifies cell mismatches and absence
tombstones.

`ReconcilePlanner` turns a cell compare into concrete repairs for a day, including
absence tombstones from the emitted index. Dirty days can be cleared after a drain.
The local export path runs the HealthKit-backed trailing seven-day sweep after
each metric delta without advancing its anchored cursor.

Dirty days can feed `AggregateDrain.planDay` for a localSampleFold P1D bucket with
a stable `bucketKey`. Aggregates encode on the wire. `ExportRun` now drains those
buckets into the same NDJSON batch as the delta page and clears the dirty days on
commit. App-created runs supply `HealthKitStatisticsSource`, so cumulative
catalogue metrics use HealthKit's de-duplicated canonical daily totals.

Journal rows carry trigger and sample tallies. `WakeLedger` is an append-only
wake file; `WakeAttribution` splits overdue scheduling from execution. Store
wipe empties SQLite/memory tables and unlinks pending payloads after COMMIT.

Pending batches are indexed by metric. `TypePurge` drops that type's queue,
writes a ledger row, and disables further export for it on an observed
grant→denied transition or an explicit stop — never on an empty read (R-60).
The 60-second clock starts at observation. A two-tap explicit-stop UI is wired;
HealthKit observation at every wake remains open.
New pending rows also carry a creation epoch. Foreground launch enforces the
ratified seven-day TTL transactionally, records gap and ledger evidence,
unlinks bytes after commit, re-seals the head and posts classified user copy.
Legacy rows with no trustworthy epoch are not guessed expired.

`ReconcileSweep` applies the seven-day trailing plan from fixture (or later
HealthKit) date-ranged observations and enqueues repairs without moving the
cursor. `HealthKitDayObservationSource` now provides the date-ranged, throwaway-
anchor adapter. `HealthKitStatisticsSource` produces canonical P1D totals for
the catalogue's cumulative exception list. `AggregateResolver` selects those
statistics for cumulative metrics, never silently substitutes a local fold,
and leaves the dirty day queued when no statistics source is available.

Egress entries are now a SHA-256 chain with sequence, previous hash, canonical
fields, byte count, and wall time. Delivery attempts and outcomes are separately
sealed; verification detects edits and reordering. Delete-all starts a successor
chain with a genesis marker naming the destroyed count and prior head.
Ledger-head identity can be sealed with `HashLedgerSeal` (and a Keychain-backed
secret on Darwin). Shipping iOS runs now seal the verified head with a
non-exportable Secure Enclave P-256 key after the terminal transaction; the
simulator uses the same P-256 signature path with a software key. The ledger UI
distinguishes chain damage, head mismatch, a missing seal, and changed identity.
`DestructiveWipe` destroys supplied credential stores and the signing identity,
writes the successor wipe-genesis entry, then seals it with a fresh identity.

All three app bundles carry `PrivacyInfo.xcprivacy` with zero tracking domains
and zero collected-data declarations. `policycheck` parses those manifests and
rejects remote Swift packages and binary targets, making the static R-36/R-52
claims required CI gates rather than release notes.

The diagnostic core now emits a sorted UTF-8 `ohe.diagnostic/1` document,
bounded to 200 runs and 200 KiB. Run fields are emitted by the per-sink
redaction manifest; raw run IDs and free-form detail never enter the bundle.
`DiagnosticPreviewGate` exposes no share payload until full-content review.
The iOS harness now builds a redacted bundle, shows the JSON, and only then
exposes Share. Its journal input uses an independent read-only SQLite
connection, runs `integrity_check`, and degrades to bounded row salvage with
an explicit skipped-row count.

R-25 now has a named-step destination test. Local folder write/read/confirm
must pass (or MQTT QoS 0 report `sentUnconfirmed`) before `enable`. A failed
test cannot enable. HTTPS/HA tests cover TLS, pin mismatch, 401, bearer
redaction, and entity attribute readback. Companion canary round-trips on the
loopback broker. Export runs write a JSON `DestinationStatusSnapshot` the
widget and watchdog can read without SQLite. The iOS app and small/medium
WidgetKit extension share versioned, per-destination snapshots through an App
Group. Timelines precompute stale/overdue transitions without inventing an
R-71 threshold, and every status uses a distinct glyph and text label with no
health values. Small, medium, accessory-rectangular and accessory-circular
families show unacknowledged destination changes until explicit acknowledgement.

The harness's fixed `Where your data goes` section renders those same
destination snapshots and provides an egress-ledger view. Opening the ledger
verifies the SHA-256 chain first and shows an explicit warning on a broken
sequence; the visible rows are bounded to the latest 50 attempts. Launch also
checks ledger integrity. Local archive enablement walks `DestinationSetup`
through a real-path canary (R-25) and drains trust events into R-40 notices
without repeating them on later launches. Unacknowledged destination changes
can be cleared from that screen. The screen documents Apple's Hidden Apps
recovery path (R-41). Two-tap controls stop one metric (R-44 explicit stop)
and run `DestructiveWipe` (R-43). Companion export follows the same
test-before-enable rule using its protocol canary; forgetting a pairing removes
the passing report and records a blocked trust-loss change.

R-27's local monitoring surface writes an atomic `status.json` beside the
archive after every run, including failures and nothing-due outcomes. The
versioned, value-free record carries freshness, confirmed acknowledgement,
counts, attribution and error class. The failure taxonomy and `jq` example are
published in `r27-failure-taxonomy.md`; thresholds remain absent until R-71.
The `Last successful export` App Intent exposes the same value-free fields as
typed per-destination entities to Shortcuts without opening the app or using
the network.

