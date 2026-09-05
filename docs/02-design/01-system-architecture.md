# System Architecture — Stage 2

**Stage:** 2 of 4 (System Design)
**Author:** Principal Software Architect
**Status:** Draft for PM synthesis and adversarial review
**Date:** 2026-09-03
**Designs to:** `docs/01-prd/PRD.md` **v1.0 (APPROVED)**, `docs/adr/0001-licence-agpl-3.0-with-app-store-permission.md`
**Toolchain:** macOS 26.6, Xcode 26.6, Swift 6.3.3, strict concurrency. Minimum OS **iOS 18.0** (D-05). Licence **AGPL-3.0 + §7 app-store permission** (D-01, D-02).

> **Stage discipline.** This document contains structure, contracts, data flow, state machines
> and trade-offs. Swift appears only as protocol and type sketches where a signature makes a
> contract precise. There is no production code here and none should be written from this
> document until the M0 exit criteria are met.

---

## Executive summary

The PRD's wedge is a claim about *knowledge*: not "we export your health data" but "we can tell
you, truthfully and specifically, what we exported and what we did not." Every structural
decision below follows from the observation that such a claim can only be made by a system whose
invariants are **enforced by its type and transaction boundaries rather than by its authors'
discipline**, because the authors are one to two volunteers over twenty-plus months and
discipline does not survive that.

Five decisions carry the design.

1. **One engine, five sinks, and the sink contract is narrow enough to be a conformance suite**
   (AR-02). A sink receives a *file handle plus an idempotency key* and returns a *classified
   outcome*. It holds no cursor, no retry state, no credentials and no persistence of its own.
   The Mac companion is a capability flag on that contract, not a special case.
2. **The write-ahead anchor invariant (R-04) is made structural.** There is no API that persists
   a HealthKit anchor. `CursorAdvance` is only accepted as a field of a batch-commit transaction,
   the transaction closure is *synchronous* so it contains no suspension point, and R-21's run
   outcome is a derived function of a tally rather than a value any code path can assign.
   Convention-based invariants are the failure mode that produces silent data loss; we remove the
   opportunity rather than police it.
3. **Completeness is audited by a bounded artefact: a permanent per-(metric, day) census digest**
   plus a UUID-level index only inside the reconciliation window. This is how R-08 composes with
   anchors without a 4.3-million-row index, how R-05 gets its guaranteed-convergence path
   (deletion by absence), how R-88's soak reconciles at day 21, and what the R-69 data browser
   shows the user. One data structure, four requirements.
4. **A HealthKit-free, Linux-buildable core of fourteen targets** with a committed dependency
   adjacency manifest enforced in CI (R-80). Acyclicity is proved by level assignment; what needs
   enforcing is not cycles — SPM refuses those — but the *absence of forbidden edges*. The
   HealthKit seam converts `HKSample` to owned value types inside the query callback, before the
   continuation resumes, so no non-`Sendable` HealthKit object ever crosses an isolation boundary.
5. **SQLite behind a `StateStore` port, via a first-party thin wrapper**, chosen over GRDB,
   SwiftData and Core Data primarily because R-80 makes Linux a required check from the first
   commit and secondarily because AR-27's dependency budget is already spent on MQTT. What we
   give up is named in §7 and the reversal trigger is stated.

Two things I want on the record before the PM synthesises. First, the sequencing in §7.1 of the
PRD is honoured literally: M0 is the R-70/R-71 spikes and nothing else that matters, and the
wedge (engine, journal, watchdog, local-file destination) completes at M6 with ~57 of ~87 EW
consumed, before MQTT, the companion or HACS begin. Second, **D-05's iOS 18.0 floor costs a
second full-history execution path**, because `BGContinuedProcessingTask` is iOS 26+. The PRD
anticipated this ("easy to lower only if Stage 2 avoids version-specific assumptions, which it
will not by default"). It is designed for in §5 as a two-implementation port and priced at ~1.5 EW
inside M4. It is not free and nobody should discover it in Stage 3.

Seven approved requirements cannot be built as written. They are in §11 with proposed amendments.
The most important is **R-44**: iOS provides no callback when a user revokes a HealthKit read
authorisation, so a 60-second purge deadline measured from revocation is not implementable by any
design. It is implementable measured from *observation*, and the amendment says so.

---

## Design principles and how they trace to the PRD

| # | Principle | Traces to | What it forbids |
|---|---|---|---|
| **DP-1** | **One engine, many sinks.** Exactly one correctness engine; destinations are adapters behind one contract with a conformance suite | AR-02, §5.2, §7.1 ("75% is the engine") | Per-destination cursors, per-destination retry, per-destination "just this once" special cases |
| **DP-2** | **The core does not know HealthKit exists.** The core package compiles, links and passes its whole suite on Linux with HealthKit absent | R-80, C-13, QA-01/C1 | Any HealthKit type in a pipeline signature, fixture, or the core's public interface |
| **DP-3** | **Invariants are types, not rules.** If a document says "always do X in the same transaction as Y", the design provides no way to do X alone | R-04, R-09, R-21, R-86 | `setAnchor(_:)`, `outcome = .success`, `evict(batch)` without a gap record |
| **DP-4** | **Gaps forbidden, duplicates permitted.** The asymmetry is load-bearing and appears in every retry, resume and reconcile decision | R-02, R-03, R-04, AR-03 | Any design that trades a possible duplicate for a possible gap |
| **DP-5** | **Nothing is O(store size).** Memory, and where achievable disk, are O(1) or O(window) in the number of samples | R-74, R-75, NFR-14, P12 | Materialising a result set, an in-memory dirty-bucket set, a full-history UUID index |
| **DP-6** | **Every failure has a name in a committed registry.** The error class is the primary key that joins the journal, the ledger, the user copy and the R-21 outcome | R-20, R-21, R-22, R-27 | `catch { return .failed }`, unlabelled `Error`, user copy written at the call site |
| **DP-7** | **Determinism is a build gate, not an aspiration** | R-84, R-12, P8 | Dictionary iteration order in output, ambient locale, ambient time zone, ambient clock |
| **DP-8** | **Honesty is a data structure.** Journal, egress ledger and day-census are three views of one append-only discipline; the UI reads them, it does not compute a parallel truth | R-20, R-21, R-30, R-69 | A UI-only status derived from anything other than durable state |
| **DP-9** | **No hidden durable state.** Every persisted structure is renderable in-product and in the diagnostic bundle | R-41, R-26, R-69, R-86 | Opaque binary state with no inspector; a store format only a maintainer with a debugger can read |
| **DP-10** | **Build the irretrievable thing first.** Sequencing is a design output: the parts that cannot be retrofitted precede the parts that can be bought later with a preset | §7.1, RK-1, RK-12 | Starting on MQTT, the companion or HACS before the wedge is internally shippable |
| **DP-11** | **The background launch path is a budget, not a codebase.** Cold headless launch to first HealthKit query touches no UI, no view model and no parsed manifest | R-73, NFR-02, C-03 | Dependency-graph construction at launch; JSON catalogue parsing at launch |
| **DP-12** | **We operate no servers, so we pin nothing and we trust nothing by default.** All trust is established by an explicit user act and recorded | R-31, R-32, R-35, R-40, R-41, RK-11 | A shipped destination, a shipped pin set, a default-on network path |

Where a principle conflicts with another, DP-3 and DP-4 win. That ordering is deliberate: the
product's reason to exist is a correctness claim, and a correctness claim that rests on care is
worth less than one that rests on structure.

---

## System decomposition

### Naming constraint

**D-06 is unresolved**, and no product name may be committed to code, listing or docs before
formal clearance. Every target, package, bundle identifier, Keychain access group, URL scheme,
Bonjour service type and wire-spec `producer` field below is therefore **descriptive and
neutral**, and a single `ProductIdentity` constant in `AppComposition` holds the human-facing
strings. This is not free: the Keychain access group and the App Group container identifier are
*migrations*, not renames, so if clearance lands after M2 the rename costs a keychain-item and
container migration path. See §12 Q1.

### Packages

Four SPM packages, in one repository, with deliberately different dependency budgets.

| Package | Platforms | Third-party deps | Why it is separate |
|---|---|---|---|
| **`ExportCore`** | macOS, iOS, **Linux** | **Zero** | R-80 requires it to build and test on Linux. Zero dependencies keeps `Package.resolved` empty, which keeps R-85 (fork PRs green with no secrets) and C-13 (no Docker on macOS runners) cheap |
| **`PlatformAdapters`** | macOS, iOS | Zero | The Apple seam. Everything that imports HealthKit, Security, Network, BackgroundTasks, UserNotifications, MetricKit |
| **`SinkMQTTPackage`** | macOS, iOS, Linux | `mqtt-nio` (+ 4 transitive SwiftNIO packages) | Quarantines D-04's one admitted non-Apple runtime dependency so it never appears in `ExportCore`'s resolution graph. Also makes the dependency review (D-04's condition) a review of one manifest |
| **`AppSurfaces`** | macOS, iOS | Zero | SwiftUI feature modules, widget, App Intents. Kept out of `ExportCore` so DP-11's launch budget is structurally defensible |

### Target graph

Levels are assigned so that **every edge runs from a strictly higher level to a strictly lower
level**. A directed graph admitting such a level function has no cycles: any cycle would require
an edge from a level to itself or upward. This is the acyclicity proof, and it is checkable
mechanically (§3.4), which matters more than the proof.

```
L9  iOSApp ── StatusWidget ── MacCompanionApp                       (Xcode targets, not SPM)
      │            │                 │
L8  AppComposition ─────────────────┘
      │
L7  DesignSystem  FeatureOnboarding  FeatureTypeSelection  FeatureDestinations
                  FeatureRunHistory  FeatureDataBrowser    FeatureDiagnostics
                  AppIntentsSurface  StatusWidgetKit
      │
L6  SinkLocalFile   SinkHTTP   SinkMQTT   SinkCompanion   CompanionReceiver   TelemetryOTLP
      │
L5  HealthKitSource   SecureStoreKeychain   FileWriteKit   PlatformRuntime
      │
L4  CorrectnessEngine   Watchdog   DiagnosticBundle
      │
L3  StorageSQLite   RunJournal
      │
L2  WireFormat   RequestTemplate   CompanionWire   Redaction
      │
L1  EnginePorts   MetricCatalog
      │
L0  CoreDomain   CoreTemporal
```

`ExportCore` is **L0–L4** plus test support. `PlatformAdapters` is L5 plus L6 minus MQTT.
`SinkMQTTPackage` is L6's `SinkMQTT`. `AppSurfaces` is L7–L8.

The single most important edge in the graph is one that **does not exist**: `CorrectnessEngine`
does not depend on `StorageSQLite`. It depends on the `StateStore` protocol in `EnginePorts`.
`AppComposition` is the only target that knows both. That absent edge is what makes the engine
Linux-testable, fault-injectable and store-swappable, and it is the first thing a reviewer should
check has not rotted.

### Per-target responsibilities

**L0 — pure values, no I/O, no ambient environment**

| Target | Responsibility | Serves |
|---|---|---|
| `CoreDomain` | Every `Sendable` domain value: `SampleRecord`, `TombstoneRecord`, `AggregateRecord`, `RecordKey`, `MetricID`, `CanonicalUnit`, `TimeZoneSource`, `BatchID`, `RunID`, `InstallationID`, `RunOutcome`, `ErrorClass`, `SensitivityClass`. Codable conformances and canonical encodings. No behaviour beyond value semantics | R-02, R-10, R-21, R-84, AR-08, AR-11, AR-14 |
| `CoreTemporal` | The *only* place `Calendar`, `TimeZone` and `Locale` are constructed. Injected `Clock`. Day/week/month bucket algebra over an explicit IANA zone, DST-transition-safe, leap-safe. Declared tz-database version | R-10, R-81, AR-09, P15, P8 |

**L1 — declarations and seams**

| Target | Responsibility | Serves |
|---|---|---|
| `EnginePorts` | The whole abstraction surface as protocols plus their DTOs: `SampleSource`, `StatisticsSource`, `DestinationSink`, `StateStore`, `StateTransaction`, `SecretResolver`, `NotificationScheduler`, `NetworkPathMonitorPort`, `LongRunTaskHost`, `FaultSeam`. No implementations, ever | R-80, AR-02, QA-01/C4 |
| `MetricCatalog` | Per-metric declarations as **generated Swift constant tables** (not a parsed manifest — DP-11): canonical unit, aggregation style (cumulative/discrete; sum/mean/min/max), canonical aggregation provider, value sanity bounds, category enum decoding, sensitivity class, curated-vs-passthrough marker, OS availability. Coverage matrix generation | R-07, R-10, R-61, R-66, AR-24, AR-30, HK-03 |

**L2 — encodings and policies**

| Target | Responsibility | Serves |
|---|---|---|
| `WireFormat` | The versioned wire specification: NDJSON (native, streaming), JSON (bounded batches), CSV (RFC 4180), HAE compatibility profile. Canonical deterministic serialisation. Schema envelope and version gate. JSON Schema emission | R-12, R-84, AR-07, AR-25, QA-13 |
| `RequestTemplate` | The closed, non-Turing-complete substitution grammar for the HTTPS destination: named placeholders, a fixed formatting directive set, no conditionals, no loops, no evaluation. Secret references are *handles*, never values | AR-21, AR-18, C-07 (2.5.2) |
| `CompanionWire` | The Mac companion frame codec and its state machine, as pure value types. Linux-buildable and fuzzable, so the companion protocol is testable with no second device | §6, R-84 |
| `Redaction` | Allowlist-based field permission (a field is absent unless permitted), the canary corpus, `Redactable` conformances | R-51, R-26, P11 |

**L3 — durable state**

| Target | Responsibility | Serves |
|---|---|---|
| `StorageSQLite` | The concrete `StateStore`: schema, migrations (`user_version`), one transaction idiom, WAL configuration, row integrity checks, an injected open policy so Apple platforms can add Data Protection open flags. Hand-written SQL, no ORM | R-04, R-86, SEC-32, P13, P14 |
| `RunJournal` | Run journal and egress ledger: append-only semantics, per-phase timings, tally accumulation, `RunOutcome` derivation, ledger entry construction. Redaction applied at write, not at read | R-20, R-21, R-22, R-30 |

**L4 — the engine**

| Target | Responsibility | Serves |
|---|---|---|
| `CorrectnessEngine` | Every pipeline stage; the run and batch state machines as pure reducers; cursor algebra (anchor + high-water mark + epoch); the day-census ledger; the reconciliation planner; the aggregate dirty-bucket drain; queue admission control and eviction policy; backoff, jitter and circuit breaking | R-01…R-11, R-86, AR-03…AR-14 |
| `Watchdog` | Staleness policy and the escalation state machine as a pure function of journal state and the injected clock; notification scheduling requests; widget timeline entries | R-23, R-24, R-27 |
| `DiagnosticBundle` | Bundle assembly from journal + ledger + checkpoint envelope through `Redaction`; the bounded, fully-renderable document R-26 requires | R-26, R-51 |

**L5 — the Apple seam**

| Target | Responsibility | Serves |
|---|---|---|
| `HealthKitSource` | The **only** target importing HealthKit, with `@preconcurrency import HealthKit`. Anchored object queries, observer queries, background delivery, per-object read authorisation (iOS 26+ medications), `HKStatisticsCollectionQuery`. Converts to `CoreDomain` values *inside the query callback*. Implements `SampleSource` and `StatisticsSource` | R-80, R-01, R-02, R-05, R-07, R-60, R-62, HK-10…HK-12, HK-15 |
| `SecureStoreKeychain` | `SecretResolver` over the Keychain at `AfterFirstUnlockThisDeviceOnly`, `synchronizable = false`; the Secure-Enclave-wrapped data key for at-rest payload encryption; the delete-all enumeration | R-33, R-43, SEC-33, SEC-34, SEC-72 |
| `FileWriteKit` | Atomic write-and-rename, Data Protection class application, backup exclusion, security-scoped bookmark lifecycle and staleness refresh, gzip streaming. Used by **both** the phone's local-file sink and the Mac receiver — one writer, not two | R-09, SEC-30, SEC-32, §6 |
| `PlatformRuntime` | `BGAppRefreshTask` / `BGProcessingTask` / `BGContinuedProcessingTask` hosting behind `LongRunTaskHost`; `UNUserNotificationCenter`; MetricKit background-exit ingestion; `os.Logger` adapter preserving `%{private}`/`%{public}`; `NWPathMonitor`; the minimal launch path | R-11, R-23, R-40, R-50, R-73, R-77, AR-17, AR-31 |

**L6 — sinks**

`SinkLocalFile`, `SinkHTTP` (plus the Home Assistant preset), `SinkMQTT`, `SinkCompanion`,
`CompanionReceiver` (macOS receive side), `TelemetryOTLP` (R-53/R-54, isolated so §6.4's "if v1
must shed scope, we cut OTLP" is a one-line package edit).

**L7–L9 — app surfaces**

`DesignSystem` (WCAG 2.2 AA tokens, Dynamic Type, never-colour-alone status vocabulary — R-64);
feature modules for onboarding/disclosure (R-63), type selection (R-61, R-62, R-66), destinations
(R-25, R-31, R-35, R-40, R-41), run history (R-20, R-21, R-22), the data browser (R-69),
diagnostics (R-26); `AppIntentsSurface` (R-68, AR-23); `StatusWidgetKit` (§5.1 Must, R-23's
notification-denied fallback); `AppComposition` as the only target that constructs concrete
adapters. `MacCompanionApp` depends on `CompanionReceiver`, `FileWriteKit`, `RunJournal` and
`DesignSystem` — and, by a CI assertion, **not** on `HealthKitSource` (AR-01).

**Test support** (`ExportCore`, Linux-clean, excluded from release builds at compile time — QA-38)

`TestSupport` (fixture loader with provenance headers, in-memory `StateStore`, deterministic fake
`SampleSource`, fault-seam driver, model-based test harness), `SinkConformance` (§6's obligation
suite), `HTTPDouble` (QA-10: scriptable HTTP destination double, macOS and Linux, no container
runtime), `CorpusGen` (executable, R-82's three tiers from a committed seed), `SchemaTool`
(executable, JSON Schema and coverage matrix emission).

### Enforcing the graph

SPM already refuses cycles; that is not the risk. The risk is a *permitted* edge that destroys
DP-2 — someone adds `import HealthKit` to `CorrectnessEngine` to fix one thing quickly. Four CI
gates, all required checks from M0:

1. **Linux build and test of `ExportCore`** (R-80). The only proof that matters. Required on
   fork PRs with no secrets and no self-hosted runner (R-85).
2. **Adjacency manifest diff.** A committed `docs/02-design/target-graph.json` listing every
   permitted edge and every target's level; a test parses `swift package dump-package` and fails
   on any edge not in the manifest or any edge that does not descend a level.
3. **Import allowlist.** Per-target permitted `import` set. `HealthKit`, `SwiftUI`, `UIKit`,
   `Network`, `Security`, `BackgroundTasks`, `CoreData`, `SwiftData` are denied in L0–L4;
   `HealthKit` is permitted in exactly one target.
4. **Linked-framework assertion** on the core test binary, and a symbol scan asserting that
   `HealthKitSource`'s converted output types appear in the engine while no `HK*` symbol does.

---

## The correctness engine

This is 42 of the ~87 EW and the product's reason to exist. It is specified here as three things:
a pipeline, two durable state machines, and a set of structural enforcements.

### 4.1 Pipeline stages

Ten stages. The six R-83 fault-injection seams are named at their stage boundaries using QA's C6
vocabulary exactly, because those names are in the requirement.

| # | Stage | Input → Output | Seam after | Notes |
|---|---|---|---|---|
| 1 | **Admit** | `RunTrigger` → `RunPlan` | — | Acquires the durable run lease. Resolves scope: which metrics, which mode (`delta` \| `backfill` \| `reconcile` \| `manual`), which destinations. Opens the journal run with the trigger (R-20, R-22) |
| 2 | **Read** | `RunPlan`, `Cursor` → `SamplePage` + `CursorAdvance` | `afterRead` | One `HKAnchoredObjectQuery` page per pull, `limit` bounded. Demand-driven: the next page is not requested until the previous batch has committed (§5's back-pressure) |
| 3 | **Normalise** | `SamplePage` → `[SampleRecord]`, `[TombstoneRecord]` | `afterTransform` | Canonical unit, `timeZone` + `timeZoneSource`, `observedAt`, batch sequence, sanity bounds, sensitivity gate. **Record identity is established here and cannot be omitted** (§4.4) |
| 4 | **Mark** | records → dirty bucket set | — | Every sample's time range marks the aggregate buckets it touches, **in the store**, not in memory. This is the mechanism of R-01: a sample dated 30 days ago dirties that day's bucket regardless of when we observed it |
| 5 | **Aggregate** | dirty buckets → `[AggregateRecord]` | — | Drains `aggregate_dirty` in date order, in bounded chunks. Per metric, the catalogue names the canonical provider: `hkStatistics` (source-de-duplicating, R-07) or `ownSum`. The record states which produced it |
| 6 | **Encode** | records → `PayloadHandle` | — | Streams canonical bytes to a queue file. Deterministic (R-84). Batch bound: `min(5 000 records, 4 MB uncompressed)` (NFR-16). gzip streaming. Digest computed while writing |
| 7 | **Commit** | `PendingBatch` + `CursorAdvance` → durable | `beforeWrite`, `afterWrite` | **One `BEGIN IMMEDIATE` transaction, no suspension point inside it.** Batch row, per-destination fan-out rows, cursor advance, day-census update, journal event. Either all of it or none of it |
| 8 | **Deliver** | `OutboundBatch` → `DeliveryOutcome` | `afterWriteBeforeAck` | Engine-owned backoff with jitter, per-destination circuit breaker, terminal failed state (AR-13). One `deliver` call is at most one transport attempt |
| 9 | **Settle batch** | `DeliveryOutcome` → receipt | `afterAckBeforeAnchorAdvance` | Receipt recorded; the queue entry and its payload file are released only when every enabled destination for that batch is terminal |
| 10 | **Settle run** | `RunTally` → `RunOutcome` | `duringAnchorPersist` | Outcome **derived**, never assigned (§4.4). Watchdog notification rescheduled on success (R-23) |

The **reconcile** mode replaces stages 2–5 with a date-ranged census comparison (§4.3) and rejoins
at stage 6, so repairs travel the same commit and delivery path as everything else. There is no
second pipeline.

Note the ordering consequence: **the cursor advances at stage 7, before delivery.** That is the
write-ahead invariant. It means the anchor represents "durably enqueued", never "delivered", and
it means seam `afterAckBeforeAnchorAdvance` is safe by construction rather than by test — see
§11 (R-83) for the amendment that keeps the seam and restates its assertion.

### 4.2 The durable state machines

**Run machine.** One row in `run`, with `phase` and `phaseEnteredAt` giving R-20's per-phase
timings for free.

```
planned ──▶ reading ──▶ committing ──▶ delivering ──▶ settling ──▶ settled(RunOutcome)
   │           │            │              │             │
   └───────────┴────────────┴──────────────┴─────────────┴──▶ interrupted
                                                                  │
                                        (next launch reconstructs)│
                                                                  ▼
                                          resumed  or  settled(.abandoned_no_budget)
                                                       settled(.cancelled_by_system)
```

`interrupted` is not written by the interrupted process — it cannot be, that is the point. It is
*inferred* at the next launch from a `run` row whose phase is non-terminal and whose lease has
expired. Attribution is then R-22's job: if no `run` row was ever opened in the expected window,
the failure was `schedule.neverWoken` (the OS did not wake us); if a row exists in a non-terminal
phase, we ran and failed, and MetricKit's background-exit data names how.

**Batch machine.** One row in `batch`, plus one row per `(batch, destination)` in `delivery`.

```
                        ┌──────────────▶ acked(destination) ────────┐
pending ──▶ inflight ───┼──────────────▶ unconfirmed(destination) ──┼──▶ (all terminal) ──▶ released
   │                    ├──────────────▶ failed(destination, class)─┤
   │                    └──────────────▶ blocked(user action) ──────┘
   │                                              ▲
   └──▶ evicted(gapRecordID)  ── legal only from pending/failed, oldest-first,
                                 and only in the same transaction that writes the gap record
```

`unconfirmed` is a first-class terminal state, not a flavour of success. It exists because R-25
requires `Sent, unconfirmed` for MQTT QoS 0, and it propagates into `RunOutcome.unknown_ack`.
The honesty requirement is carried by the type system from the sink boundary to the journal.

**Cursor state**, per metric type — the heart of R-04 and R-08 composing:

| Column | Meaning | Invariant |
|---|---|---|
| `anchorBlob` | Opaque archived `HKQueryAnchor` | Advances only within an epoch, only via `CursorAdvance`, only inside a batch commit |
| `anchorEpoch` | Monotone counter | Increments **only** alongside a persisted `AnchorResetDecision` naming actor (`user` \| `policy`) and reason |
| `dateHighWaterMark` | Max sample `endDate` durably committed | Never decreases. The auditable claim: *every sample with `endDate ≤ HWM` that existed when we read has been committed* |
| `lastReconciledThrough` | Trailing edge of verified history | Advances only on a clean census comparison |
| `rowCRC` | CRC over the row's canonical encoding | Checked on load; mismatch raises `storage.checkpointIntegrity` and **never** resets to zero (R-86) |

### 4.3 Completeness auditing: the day-census ledger

R-08 asks for a date high-water mark plus a bounded reconciliation sweep, and G-1 is measured by
"zero discrepancy on the R-88 soak protocol." A full-history UUID index would answer it exactly
and costs ~170 MB at REF-STORE-XL, against NFR-14's 60 MB ceiling for app plus state. So:

**Permanent, O(metrics × days):**

```
day_census(metricID, dayKeyUTC, sampleCount, uuidDigest, valueDigest,
           exportedThrough, lastVerifiedAt)
```

`uuidDigest` is the XOR-fold of `SHA-256(uuid)` over the samples in that day bucket;
`valueDigest` the same fold over the canonical encoding of `(uuid, start, end, value, unit)`.
Both are **order-independent** (so they are computable streaming, in any query order, satisfying
P9 and DP-5) and both are O(1) per sample to maintain.

**Windowed, O(window):**

```
sent_index(uuid PRIMARY KEY, metricID, dayKeyUTC, batchID)   -- pruned to the reconcile window
```

This gives four capabilities from one structure:

- **Bounded sweep (R-08, default trailing 7 days).** Re-query by date predicate, recompute the
  census over the window, diff. UUID-level detail is available inside the window, so repairs are
  precise: missing UUIDs are re-emitted, and UUIDs in `sent_index` but absent from HealthKit are
  emitted as tombstones. *This is R-05's guaranteed-convergence path — deletion by absence — and
  it is why R-05 can honestly document background-delivery tombstones as best-effort.*
- **Full reconcile (R-08, user-triggerable).** Outside the window we hold only digests, so
  detection is exact at **day granularity** and repair is "re-emit the day." Idempotent under
  R-02's upsert-by-UUID, so re-emitting a day is safe and cheap. Exact detection, bounded state.
- **Anchor-invalidation recovery.** A restore-from-backup or HealthKit re-sync invalidates the
  anchor; the epoch increments with a recorded decision, and the census tells us which days need
  re-verification rather than triggering a full re-export (R-86, P13).
- **The soak's terminus and the user's verification surface.** R-88's day-21 reconciliation of
  exported counts against store counts *is* a census comparison. R-69's data browser renders the
  same rows: "this day, this metric, 1 284 samples, exported, verified 3 hours ago." The user
  checks our number against the Health app's number, which is the wedge's own claim made visible.

### 4.4 Structural enforcement of the invariants

Four requirements are enforced by the shape of the API rather than by review.

**R-04 — write-ahead cursor discipline.** There is no function that persists an anchor.

```swift
// EnginePorts
public protocol StateStore: Sendable {
    /// The only mutating entry point. The body is SYNCHRONOUS: a transaction
    /// cannot contain a suspension point, therefore actor reentrancy cannot tear it.
    func transact<T: Sendable>(
        _ body: @Sendable (borrowing StateTransaction) throws -> T
    ) async throws -> T
}

public struct StateTransaction: ~Copyable {
    /// A cursor may ONLY advance as a field of a batch commit.
    public func commitBatch(_ batch: PendingBatch, advancing: CursorAdvance) throws
    /// Eviction may ONLY occur alongside the gap record it creates (R-09).
    public func evict(_ batchID: BatchID, recording: GapRecord) throws
    public func recordDelivery(_ receipt: DeliveryReceipt) throws
    public func appendJournal(_ event: RunEvent) throws
    public func appendLedger(_ entry: EgressEntry) throws
    // There is no setAnchor. There is no setHighWaterMark. There is no
    // evict(_:). They are not private — they do not exist.
}

/// Constructible only by the Read stage, only alongside the page it describes.
public struct CursorAdvance: Sendable {
    public let metric: MetricID
    public let epoch: UInt32
    let anchorBlob: Data          // module-internal
    let observedThrough: Date     // module-internal
    init(page: SamplePage) { ... } // the only initialiser
}
```

An epoch change requires a different type, `CursorReset`, which `commitBatch` does not accept and
which `StorageSQLite` refuses without a persisted `AnchorResetDecision` row. R-86's "anchors never
silently reset" therefore has no code path to violate.

**R-21 — a run is never recorded as success if acknowledged < read.** The outcome is derived.

```swift
public enum RunOutcome: String, Sendable, CaseIterable {
    case success, success_nothing_due, partial, unknown_ack
    case failed, abandoned_no_budget, cancelled_by_system

    /// The only way to obtain a RunOutcome. There is no public initialiser
    /// and the cases are not constructible from outside this function's module.
    public static func derive(from tally: RunTally) -> RunOutcome
}
```

`RunTally` accumulates per-destination `read`, `committed`, `acked`, `unconfirmed`, `failed`
counters and the terminal error classes. `derive` is a pure total function with 100% branch
coverage as a release gate (QA-33). No call site can type `.success`.

**R-02 — upsert-by-UUID identity.** Identity is established at the HealthKit boundary and is
non-optional, so a record cannot exist without it.

```swift
public enum RecordKey: Hashable, Sendable {
    case sample(uuid: UUID, metric: MetricID)
    case tombstone(uuid: UUID, metric: MetricID)
    case aggregate(metric: MetricID, zone: IANAZoneID,
                   granularity: BucketGranularity, bucketStartUTC: Date)
}

public struct SampleRecord: Sendable, Hashable {
    public let key: RecordKey          // no default, no optional
    public let observedAt: Date        // when WE saw it (AR-14)
    public let sequence: UInt64        // per-installation monotone (AR-14)
    // ...
}
```

`WireFormat` cannot encode a record without a `RecordKey`; the schema marks it required; the
schema gate (R-12) fails CI if it ever becomes optional. `HealthKitSource` builds `SampleRecord`
from `HKObject.uuid` inside the query callback, which is also where the `HKSample` dies (§5.2).

**R-09 — the gap record.** `evict` takes the `GapRecord` as a parameter. The one place the product
deliberately loses health data cannot lose it quietly.

---

## Concurrency and back-pressure model

Swift 6 strict concurrency, `-strict-concurrency=complete`, no `@unchecked Sendable` in
`ExportCore` (CI-asserted), exactly one `@preconcurrency import`.

### 5.1 Actors and executors

| Component | Isolation | Executor | Why |
|---|---|---|---|
| `ExportCoordinator` | `actor` | Cooperative pool | Owns run admission and the run reducer. Holds no framework objects |
| `StorageSQLite` | `actor` with a **custom `SerialExecutor`** over a dedicated `DispatchSerialQueue` | Dedicated thread | SQLite gets one thread for its lifetime, and — decisively — **`fsync` must not block the cooperative pool.** `synchronous=FULL` means every commit blocks on disk; doing that on a cooperative thread starves the pool and will show up as mysterious latency under load |
| `HealthStoreActor` | `actor` | Cooperative pool | `HKHealthStore` is not `Sendable`; confining it to one actor is the cheapest correct answer. Its methods return *already-converted* value types |
| Each sink | `Sendable` conformer, typically `actor` | Its own choice | `DestinationSink` is `Sendable` with `async` members. `SinkHTTP` delegates to a background `URLSession`; `SinkMQTT` lives on a NIO `EventLoop`; `SinkCompanion` owns one `NWConnection` |
| `WatchdogActor` | `actor` | Cooperative pool | Reads journal state, schedules/cancels notifications |
| View models | `@MainActor` | Main | Consume `AsyncStream<RunProgress>` of `Sendable` snapshots. No shared mutable state with the engine |
| Launch path | non-isolated, synchronous where possible | Whatever launched us | DP-11: open the store, install observer queries, issue the first query. ≤ 400 ms at REF-B (R-73) |

Domain types are `Sendable` by construction: structs and enums of value types, `Hashable` where
they are keys, no reference types anywhere in `CoreDomain`. `PayloadHandle` is a `Sendable` value
(URL, byte count, digest) rather than `Data`, which is the same decision that gives us O(1) memory
(§5.3) — one choice, two properties.

### 5.2 The HealthKit seam

The known Swift 6 problem is that `HKSample` and friends are non-`Sendable` classes, so resuming a
continuation with a query result is a data-race diagnostic. The community answer is
`@preconcurrency import HealthKit` plus conversion at the boundary. That is necessary but not
sufficient, because `@preconcurrency` silences the diagnostic without making the code correct.

The rule that makes it correct: **conversion happens inside the query's own callback closure,
before the continuation resumes.** The continuation's type parameter is a `Sendable` value type,
so no HealthKit object is ever captured across an isolation boundary — the suppression is
load-bearing for exactly one line and the safety is real, not asserted.

```swift
// HealthKitSource — the only @preconcurrency import in the codebase
func nextPage(for metric: MetricID, cursor: Cursor, limit: Int) async throws -> SamplePage {
    try await withCheckedThrowingContinuation { continuation in
        let query = HKAnchoredObjectQuery(type: …, predicate: nil,
                                          anchor: cursor.anchor, limit: limit) {
            _, added, deleted, newAnchor, error in
            // Conversion happens HERE, synchronously, inside HealthKit's callback.
            // A `SamplePage` is Sendable; no HKSample crosses the boundary.
            continuation.resume(with: SamplePage.make(added, deleted, newAnchor, error,
                                                      metric, catalogue))
        }
        store.execute(query)
    }
}
```

Two seam-specific hazards, designed for:

- **Observer-query completion handlers must be called on every path** (HK-11); three failures and
  HealthKit stops delivering permanently. The handler is a `@Sendable` closure wrapped in a
  `CompletionGuard` value with `deinit`-based assertion in debug and a `defer`-called invocation in
  release, plus a static check that every exit path calls it.
- **`HKErrorDatabaseInaccessible` (device locked, C-02) is not an error** (HK-12). It maps to
  `ErrorClass.source.deviceLocked`, does **not** advance the cursor, does **not** raise a user
  alarm, and settles the run as `success_nothing_due` with the lock reason recorded. Getting this
  wrong produces either false alarms every night or a silent anchor advance past unread data.

### 5.3 Reentrancy discipline

Actor reentrancy is what eats pipelines of this shape: an `await` inside a state transition lets a
second task observe half-applied state. Five rules, in priority order:

1. **No suspension point inside an invariant window.** `StateStore.transact`'s body is
   synchronous. A transaction physically cannot interleave with another task.
2. **Transitions are pure reducers.** `(State, Event) -> (State, [Effect])`. The actor applies the
   new state in one synchronous step, then executes effects. Reentrancy cannot observe a partial
   transition because there is no partial transition.
3. **One run at a time, enforced durably.** A `run_lease(owner, expiresAt)` row, not an in-memory
   flag — because a background wake is a *new process*, and because an observer wake, a
   `BGProcessingTask` and an App Intent (R-68) can genuinely overlap in one process.
4. **No unstructured `Task { }` in the engine.** Everything is `withTaskGroup` / `async let`, so
   background-time expiry arrives as cancellation and cannot orphan work.
5. **Cancellation checkpoints, never rolls back.** On `CancellationError`, committed batches stay
   committed and the run settles `cancelled_by_system`. Rolling back committed work to "clean up"
   would violate DP-4 by converting a duplicate into a gap.

### 5.4 Back-pressure and O(1) memory (R-74)

R-74 requires ≤ 100 MB RSS with streaming, O(1) in store size, at REF-B. Five mechanisms:

- **Demand-driven read.** `SamplePageStream` is an `AsyncSequence` whose `next()` *issues* the
  next `HKAnchoredObjectQuery`. It is not an `AsyncStream` with a buffer. The next page is not
  requested until the previous batch has committed, so the source cannot outrun the sink. This is
  the back-pressure: the pipeline's depth is one page.
- **Encode-to-file, never encode-to-memory.** Stage 6 streams canonical bytes through a gzip
  writer into a queue file, computing the digest as it goes. Peak = one page of records + one write
  buffer + the gzip window.
- **Payloads are handles.** Delivery hands `SinkHTTP` a file URL for a background `URLSession`
  upload task; the OS streams it and we hold nothing. `SinkMQTT` and `SinkCompanion` read with a
  fixed buffer. `SinkLocalFile` renames. No sink ever receives `Data` for a whole batch.
- **Dirty buckets live in the store.** A five-year backfill can dirty ~1 800 day-buckets × 40
  metrics; holding that set in memory is O(store). `aggregate_dirty` is a table, drained in
  date-ordered chunks. O(1) memory, O(dirty) disk.
- **Queue admission control before eviction.** When the 256 MB cap (R-09, D-11) is approached, the
  **read stage stalls first** — bounded, journalled, user-visible — and eviction happens only when
  stalling has not helped and new data is arriving. D-11 chose oldest-first eviction; it did not
  choose whether back-pressure precedes it. I am choosing that it does, because a stall is
  recoverable and an eviction is a permanent gap. *Rejected alternative:* evict immediately on cap,
  which is simpler and keeps freshness during a long outage at the cost of losing the oldest data
  sooner. See §12 Q4.

### 5.5 Long-running work, and the cost of the iOS 18 floor

R-11 (full-history backfill, Should), R-75 and R-78 need tens of minutes of execution that must
not come from a system-scheduled background task. `BGContinuedProcessingTask` is exactly right and
is **iOS 26+**, while D-05 sets the floor at **iOS 18.0**. So `LongRunTaskHost` has two
implementations, availability-gated at composition:

| Implementation | Floor | Mechanism | Consequence |
|---|---|---|---|
| `ContinuedProcessingHost` | iOS 26 | `BGContinuedProcessingTaskRequest`, system progress UI, system cancellation | The good path. User-initiated, survives backgrounding, runs to completion |
| `ForegroundKeepAliveHost` | iOS 18 | Foreground execution with in-app progress and an explicit "keep the screen on" affordance, plus `BGProcessingTask` resumption of the checkpointed run | The worse path. Backgrounding suspends it; resumption is opportunistic; the honest UI copy is "keep this screen open" |

Both satisfy R-78's prohibition on system-scheduled initiation. Both resume from the same
checkpoint, because resumability is the engine's property, not the host's. Cost: ~1.5 EW, absorbed
in M4. This is the concrete price of D-05 and it should be visible in the plan, not discovered.

---

## The destination sink contract

AR-02 requires exactly one engine with every destination behind a single internal contract, no
per-destination cursors and no per-destination retry state. The contract below is deliberately
narrow enough that a conformance suite can be written against it — and that suite is the release
gate for any new destination, including community-contributed ones.

### 6.1 The contract

```swift
public protocol DestinationSink: Sendable {
    static var capabilities: SinkCapabilities { get }

    /// R-25/R-31: exercise the real path, credential and payload. Reports per step.
    /// A destination cannot be enabled until this returns .ready.
    func prepare(_ context: SinkContext) async -> SinkReadiness

    /// At most ONE transport attempt. Never throws: every failure is a classified outcome.
    func deliver(_ batch: OutboundBatch, _ context: SinkContext) async -> DeliveryOutcome

    func teardown(_ context: SinkContext) async
}

public struct OutboundBatch: Sendable {
    public let batchID: BatchID              // ULID, per-installation monotone
    public let idempotencyKey: IdempotencyKey // stable across attempts; content-derived
    public let payload: PayloadHandle         // file URL + byteCount + SHA-256 — never Data
    public let format: WireFormatID
    public let schemaVersion: SchemaVersion
    public let keys: RecordKeySummary         // counts by kind; UUID range digest
    public let attempt: Int                   // engine-owned; informational only
    public let deadline: ContinuousClock.Instant
}

public enum DeliveryOutcome: Sendable {
    case acknowledged(DeliveryReceipt)
    case acceptedUnconfirmed(DeliveryReceipt)          // R-25 "Sent, unconfirmed"
    case retryable(ErrorClass, retryAfter: Duration?)
    case rejectedPermanent(ErrorClass, detail: RedactedString)
    case blockedPendingUserAction(BlockReason)          // R-31 identity change, R-35 opt-in, stale bookmark
}

public struct SinkCapabilities: Sendable {
    public let supportedFormats: Set<WireFormatID>
    public let maxPayloadBytes: Int
    public let confirmsDelivery: Bool        // false ⇒ .acknowledged is unreachable
    public let supportsIdempotencyKey: Bool
    public let tombstoneSupport: TombstoneSupport   // .native | .asRecord | .unsupported
    public let requiresForeground: Bool      // engine will not schedule from a background wake
    public let supportsResume: Bool
    public let transportSecurity: TransportSecurityClass  // ledger field, R-30/R-35
    public let respectsMeteredNetworkPolicy: Bool
}

/// Everything a sink is allowed to touch. Note what is absent: no StateStore,
/// no journal, no cursor, no credential values, no clock.
public struct SinkContext: Sendable {
    public let destinationID: DestinationID
    public let configuration: DestinationConfiguration   // secrets by handle only (AR-18)
    public let secrets: any SecretResolver               // resolve at use, never retain
    public let scratch: any SinkScratch                  // namespaced, versioned, wiped on reconfigure
    public let allowlist: HostAllowlist                  // R-32
    public let networkPolicy: NetworkPolicy              // AR-31 metered-network rules
    public let faults: any FaultSeam                     // test builds only
}
```

`SinkScratch` is the pressure valve that keeps AR-02 honest. Sinks *do* sometimes need a little
durable state — an MQTT session identifier, a pinned SPKI hash, a resume offset. Rather than
pretend otherwise and watch it be smuggled into `UserDefaults`, the contract provides a
store-owned, namespaced, versioned, engine-wipeable key-value space with an explicit prohibition:
**scratch may not contain anything from which a cursor or a retry schedule could be reconstructed**,
and the conformance suite asserts a sink still behaves correctly after its scratch is destroyed.

### 6.2 Conformance obligations

Eighteen named obligations, each one test in `SinkConformance`, each one a release gate for the
destination. Sinks that are Linux-buildable run the suite on Linux; the rest run it on device.

| ID | Obligation | Enforces |
|---|---|---|
| **O1** | Redelivering the same `idempotencyKey` leaves observable sink state unchanged | R-02, R-03, P2 |
| **O2** | No durable write outside `SinkScratch`. Correct behaviour survives scratch destruction | AR-02 |
| **O3** | One `deliver` call performs at most one transport attempt; no internal retry loop | AR-02, AR-13 |
| **O4** | Outcome classification is total: every injected fault maps to a non-`acknowledged` outcome with a registered `ErrorClass` | DP-6, R-21 |
| **O5** | `capabilities.confirmsDelivery == false` ⇒ `.acknowledged` is never returned | R-25, R-03 |
| **O6** | Payload byte-identity: the digest observed at the far end equals `payload.digest` | R-84, R-12 |
| **O7** | `deadline` is honoured; expiry returns `.retryable`, not a hang | R-73, AR-13 |
| **O8** | Secrets are resolved at point of use and appear in no log, error, scratch or payload (canary corpus) | AR-18, R-51, R-33 |
| **O9** | Zero egress to any host not in `context.allowlist` | R-32, R-37, P16 |
| **O10** | Tombstones are delivered natively, as records, or refused with an explicit "cannot represent deletion" diagnostic naming the destination — never silently dropped | R-05, P7 |
| **O11** | `prepare` failure blocks enablement; the per-step report names the failing step | R-25 |
| **O12** | A changed transport identity returns `.blockedPendingUserAction` and halts, showing old and new fingerprints | R-31, RK-7 |
| **O13** | Payloads exceeding `maxPayloadBytes` are rejected at `prepare`-time capability negotiation, not truncated at delivery | NFR-16 |
| **O14** | Delivery result is independent of batch arrival order | P9, AR-14 |
| **O15** | One sink instance observes serialised batches even while the engine fans out to N destinations concurrently | §5.1 |
| **O16** | Every attempt yields exactly one ledger entry carrying destination, transport security class, counts and outcome | R-30 |
| **O17** | Peak RSS during delivery of a `maxPayloadBytes` payload is bounded and independent of payload size | R-74, P12 |
| **O18** | With the metered-network policy disabled, zero bytes over a constrained or expensive path | AR-31 |

### 6.3 How the five sinks satisfy it

| Sink | `confirmsDelivery` | Ack semantics | Idempotency mechanism | `requiresForeground` | Honest limitation |
|---|---|---|---|---|---|
| **Local file** (R-09, 1.5 EW) | `true` | `fsync` + atomic rename to a name containing the idempotency key | Rename is idempotent: an existing target name means already-delivered, return the receipt | `false` | Security-scoped bookmarks go stale across OS upgrades → `.blockedPendingUserAction(.staleBookmark)`, which is a user-visible re-pick, not a silent stop |
| **Generic HTTPS** (R-31, R-35) | `true` | 2xx | `Idempotency-Key` header plus per-record `RecordKey` in the payload; **the receiver may ignore both**, hence R-03's at-least-once documented in the wire spec | `false` | We cannot make an arbitrary endpoint deduplicate. The contract says at-least-once and the wire spec says it in the same words |
| **Home Assistant preset** (R-89) | `true` | 2xx from `/api/states/…` or the webhook, plus a read-back assertion in `prepare` verifying `unit_of_measurement`, `device_class`, `state_class` and precision | Entity ID is derived deterministically from `RecordKey`; HA's state model is last-write-wins per entity, which is upsert | `false` | HA statistics silently fail without `state_class`; the read-back in `prepare` is the only thing that catches it, which is why R-89 tests two pinned versions against a real instance |
| **MQTT** (R-90, D-04) | **QoS 0: `false`; QoS 1/2: `true`** | PUBACK / PUBCOMP | Topic derived from `RecordKey`; retained messages give a converging last-value; QoS 1 duplicates are expected and safe under upsert | `false` | QoS 0 can only ever return `.acceptedUnconfirmed`, which surfaces as `Sent, unconfirmed` (R-25) and `unknown_ack` (R-21). We do not launder it into success |
| **Mac companion** (§7) | `true` | `RECEIPT(batchID, digest)` after the receiver has `fsync`ed and renamed | `OFFER` for an already-received `batchID` returns the stored `RECEIPT` immediately | **`true`** | Both ends must be running and on the same network. The engine will not schedule it from a background wake; the batch waits in the same queue as everything else |

The last column of that table is the argument that AR-02 survived contact with reality: the
companion's genuine peculiarity (it needs both ends live) is expressed as **one boolean in a
capability struct**, consumed by the engine's scheduler, rather than as a branch anywhere in the
pipeline. That is the test of whether a contract is real.

---

## Persistence design

### 7.1 What must be stored

| Datum | Volume | Access pattern | Sensitivity (SEC classes) |
|---|---|---|---|
| Queue metadata + per-destination fan-out | ~10⁴ rows | Indexed: oldest pending, by destination, by state | A3 (metadata) |
| Payload blobs | up to 256 MB (R-09) | Sequential write once, sequential read N times, delete | **A1 (health values)** |
| Cursors (anchor blob, HWM, epoch, CRC) | ~200 rows | Point read/write inside the commit transaction | A3 |
| Day-census ledger | metrics × days ≈ 40 × 3 650 ≈ 1.5 × 10⁵ | Upsert by (metric, day); range scan for reconcile | A3 (counts and digests, no values) |
| `sent_index` (windowed) | ~1.4 × 10⁵ | Point lookup by UUID; range prune | A3 |
| Run journal + egress ledger | ~10⁴ rows/year | Append; range scan by time; render in UI | A3 (destination hostnames) |
| Gap records | tens | Append; render | A3 |
| Destination configuration (non-secret) | tens | Read at run start | A3 |
| Secrets: tokens, MQTT credentials, companion PSK, payload data key | tens | Read at point of use | **A2** |
| Security-scoped bookmarks | tens | Read at run start; refresh on stale | A3 |
| UI preferences | tens | — | Non-sensitive only (SEC-31 forbids A1/A2/A3 in `UserDefaults`) |

### 7.2 Options assessed

| Option | Linux (R-80/C-13) | Crash safety (P14) | R-84 determinism | R-86 inspectable versioned checkpoints | Migration (P13) | Data Protection (SEC-32, C-02) | Dependency (AR-27) | Verdict |
|---|---|---|---|---|---|---|---|---|
| **SwiftData** | **No** — Darwin only | Opaque; no control of journal mode or `fsync` policy | Irrelevant (not an output format) but no control of on-disk layout | **No** — opaque store, no textual inspection | Declarative; field debugging of a failed migration is poor | Per-store class not directly settable | Zero | **Reject.** Fails R-80 outright. Also fails R-86's spirit and gives us no lever on the one property (durability ordering) the whole design rests on |
| **Core Data** | **No** — no `swift-corelibs-coredata` | Mature, but the WAL and journal are Apple's, not ours | — | **No** | Mature but heavyweight | Settable on the store file; WAL handling is Apple's | Zero | **Reject.** Fails R-80. Twenty years of correctness we cannot use in the environment R-80 makes a required check from commit one |
| **Flat files** (append-only log + JSON manifests) | Yes | Excellent for append; poor for multi-structure atomicity | Excellent | **Excellent** | Trivial | Directly settable | Zero | **Reject as the primary store, adopt for payloads.** Oldest-first eviction, per-destination fan-out, UUID point lookups and census upserts across one atomic boundary means writing a database badly. **But payload blobs are files** — they must be, for background `URLSession` and O(1) memory |
| **SQLite via GRDB** (MIT) | Supported, but secondary to Darwin | Excellent; battle-tested WAL, `DatabaseQueue` serial model maps cleanly onto our actor | Fine | Yes (`sqlite3` CLI, plus our envelope) | Built-in migrator — a genuine saving | Needs custom open flags; reachable via configuration hooks | **One** (would be #2 of 3, after MQTT) | **Reject, with regret and a reversal trigger.** The migrator and the hardened edge cases are worth ~1–1.5 EW. But R-80 makes Linux a *required check from the first commit*, and betting the core's storage on a package whose Linux support is a secondary target is a schedule risk in the first milestone that matters |
| **SQLite via a first-party thin wrapper** over system `libsqlite3` | **Yes** — present on both Darwin and Linux (`libsqlite3-dev`) | Ours to get right: WAL + `synchronous=FULL` + `BEGIN IMMEDIATE` | Fine | **Yes** — `sqlite3` CLI, in-app inspector, checkpoint envelope | Hand-written, `user_version`-gated, forward-incompatible versions fail loudly | **Directly settable**: `SQLITE_OPEN_FILEPROTECTION_COMPLETEUNLESSOPEN` at open | **Zero** | **Chosen** |

### 7.3 The choice, and what we give up

**Chosen: one SQLite database behind the `StateStore` port, accessed through a first-party wrapper
of roughly 1 200 lines, with payload blobs as separate files.**

The reasoning, in the order the constraints bind:

1. **R-80 dominates.** Linux CI is a required check from the first commit. The storage layer is on
   the critical path of the engine's tests. A dependency whose Linux support is secondary is a
   first-milestone risk on the one thing the PRD says must not be retrofitted.
2. **The SQL surface is deliberately tiny.** Ten tables, one transaction idiom
   (`BEGIN IMMEDIATE … COMMIT`), no ORM, no query builder, no observation. We need exactly one
   hard thing from SQLite — atomic multi-table commit with a durable fsync — and it is the thing
   SQLite is best at.
3. **The dependency budget is already spent.** AR-27 caps non-Apple runtime dependencies at three
   with an ADR each; D-04 spends one on `mqtt-nio` and its four transitive SwiftNIO packages.
   Spending a second on storage in a project whose premise is auditability is a bad trade when the
   alternative is 1 200 reviewable lines.
4. **Data Protection needs the open call.** `SQLITE_OPEN_FILEPROTECTION_COMPLETEUNLESSOPEN` at
   `sqlite3_open_v2` time, applied to the database and to `-wal` and `-shm`, is what makes C-02 and
   SEC-32 hold for a background wake that must record a delivery ack while the device is locked.
   Owning the open call means this is a line of code rather than a configuration archaeology
   exercise. The open policy is injected, so `ExportCore` stays Linux-clean.

**What we give up, stated plainly:**

- **GRDB's migrator, record mapping and `ValueObservation`.** We hand-write migrations and drive UI
  updates from our own change notifications. ~1–1.5 EW, and a class of bug we now own.
- **Battle-tested edge-case handling.** GRDB has absorbed years of real-world SQLite pathologies —
  busy timeouts, interrupted transactions, WAL checkpoint starvation, `SQLITE_FULL` mid-transaction.
  We will meet those ourselves. Mitigation: P14 crash-consistency property tests with a
  fault-injecting file layer, and the R-83 seams exercising kill-at-every-point.
- **A first-party storage layer is now a permanent maintenance obligation** on the correctness
  critical path, in a project whose top-rated risk is maintainer abandonment (RK-1). This is the
  strongest argument against my own choice and I want it recorded as such.
- **No SQLCipher, no encrypted database.** Journal and ledger rows — metric names, counts,
  timestamps, **destination hostnames** — are protected by Data Protection alone. Payload blobs get
  independent application-layer AEAD with a Secure-Enclave-wrapped key from the Keychain (SEC-72),
  because that is where the health values are. The security engineer flagged ledger hostnames as
  sensitive; under this design they are protected at file-protection level and not at
  application level. That is a real residual and it belongs in the Stage 2 threat review.

**Reversal trigger, stated now so it is not a judgement call later:** if the wrapper exceeds 3 EW,
or if P14 fails repeatedly on WAL semantics, or if Linux and Darwin SQLite behaviour diverges in a
way we cannot pin, we adopt GRDB behind the unchanged `StateStore` port. The port is what makes
that a contained change, and preserving that option is part of why the port exists.

### 7.4 Determinism and encryption, reconciled

R-84 requires byte-determinism. SEC-72 requires AEAD at rest, which is nondeterministic by nonce.
These do not conflict once the boundary is named: **determinism is asserted on the canonical bytes
handed to the sink** (`PayloadHandle.digest` is computed pre-wrap and is what O6 checks), never on
the at-rest representation. The wrap is a storage concern below the wire contract. Stated because
a reasonable engineer reading both requirements will otherwise conclude they are contradictory.

### 7.5 R-86's inspectable versioned checkpoint

A `CheckpointEnvelope` — a versioned, human-readable JSON document, emitted on demand, rendered
in-app (DP-9) and included in the diagnostic bundle after redaction:

```
{ "envelopeVersion": 1, "schemaVersion": "1.0.0", "storeUserVersion": 7,
  "installationID": "…", "generatedAt": "…", "tzdataVersion": "2026b",
  "cursors": [ { "metric": "stepCount", "anchorDigest": "sha256:…", "anchorEpoch": 3,
                 "dateHighWaterMark": "2026-09-02T23:41:07Z",
                 "lastReconciledThrough": "2026-08-27T00:00:00Z" } ],
  "queue": { "depth": 12, "bytes": 4_193_204, "oldestPending": "…" },
  "census": { "metrics": 41, "days": 1_982, "unverifiedDays": 3 },
  "gaps": [] }
```

The anchor blob itself is opaque by nature (it is Apple's), so the envelope carries its **digest**
— enough to prove it changed or did not, without pretending to inspect it. Corrupting a cursor row
or the envelope raises `storage.checkpointIntegrity` with a user-facing choice (re-verify by
reconcile / explicit full re-export) and **never** a silent reset. That is the whole of R-86 and it
is the difference between "anchors never silently reset" being a property and being a promise.

---

## The Mac companion

I classified this **Won't at 5 EW** in Stage 1, the adversarial reviewer independently recommended
cutting it, and D-14 restored it. Designed honestly means: designed properly, and with the cut line
named.

### 8.1 What it is and is not

macOS cannot read HealthKit (PC-1, C-01, **verified**). The Mac is therefore a **destination**, and
`MacCompanionApp` is CI-asserted not to depend on `HealthKitSource` (AR-01). It receives batches
pushed from the iPhone over the local network and writes them to a user-chosen folder using
`FileWriteKit` — the same writer the phone's local-file sink uses. One writer, two hosts.

Its only genuine justification is friction: R-115's reference receiver already delivers the same
capability at higher setup cost (Docker, a container, a port). The companion is the
zero-configuration path for P2 and P4, who will not run a container. That is a real product
argument and it is also a thin one, which is why §10 places it at M9 and §12 Q6 asks the question
once more before it is built.

### 8.2 Transport: three options, one choice

**Multipeer Connectivity** — what `health-md` uses, and it is worth knowing why. MC collapses
discovery, encryption and transport into one API and works over peer-to-peer Wi-Fi and Bluetooth
with **no shared network at all**, which is genuinely valuable for "my Mac is right there in a
hotel room." For a small team it is the cheapest thing that works.

We reject it, for four reasons that compound:

1. **Peer identity is a display name.** `MCSession` in `.required` encryption mode uses per-session
   identities; there is no durable pairing primitive, so "is this the Mac I approved?" is answered
   by the user reading a string. Against RK-11 and R-31, an attacker's Mac advertising
   "Colin's MacBook Pro" defeats the control. This is disqualifying on its own.
2. **No acked, resumable, chunked semantics.** `sendResource` reports progress but its failure model
   is coarse and there is no protocol-level per-chunk acknowledgement. O1, O6, O13 and `supportsResume`
   cannot be satisfied honestly.
3. **Both apps must be foregrounded and the API is long-unmaintained**, with well-documented
   flakiness that we would be diagnosing on other people's networks with no telemetry (R-37).
4. **It fights the contract.** Making MC satisfy §6 means reimplementing framing, acking and
   resumption on top of it — which is most of the work of doing it properly, on a worse foundation.

**Plain HTTPS to a Mac-run receiver.** Already works today via `SinkHTTP` plus R-115. Rejected as
*the companion* because it requires the user to obtain a certificate or accept R-35's plaintext
opt-in, which is precisely the friction the companion exists to remove. Retained as the documented
fallback and as the reason the companion is cuttable.

**Chosen: Bonjour discovery + Network framework TLS 1.3 with a pairing-established pre-shared key.**

| Aspect | Design |
|---|---|
| **Who listens** | The **Mac** (`NWListener`). The iPhone connects outward. R-34 (no listening socket on iOS) holds by construction, and the security check is trivially satisfiable |
| **Discovery** | `NWBrowser` on the phone for a functionally neutral service type (`_ohx-recv._tcp`), advertised by the Mac **only while the user has the receive window open** and **only after at least one pairing exists**. Manual IP entry as the fallback, as `health-md` also offers |
| **Credential** | 256-bit PSK generated on the Mac at pairing, consumed by `sec_protocol_options_add_pre_shared_key`. TLS 1.3 PSK gives **mutual authentication** and forward secrecy with no CA, no certificate rotation and no pin-on-first-use ambiguity |
| **Transfer** | QR code rendered by the Mac, scanned by the phone — reusing R-67's QR configuration path and UX's mandated review screen. Never over the network, never by copy-paste of a long secret |
| **Confirmation** | A six-digit code derived from the TLS key exporter shown on **both** screens after the first handshake. Cheap, and it defeats a QR photographed over a shoulder |
| **Storage** | PSK in the Keychain at `AfterFirstUnlockThisDeviceOnly`, `synchronizable = false`, referenced by `SecretHandle` (R-33, AR-18). Removed by R-43's delete-all |
| **Alternative retained** | Self-signed P-256 identities with SPKI exchange at pairing. Strictly more flexible (multi-device, rotation) and strictly more machinery. The migration path if the companion ever serves more than one Mac |

**SEC-04 tension, stated rather than glossed.** SEC-04 (a Stage 2 design constraint, not promoted)
requires "no Bonjour/mDNS advertisement of any health-related service," verified by "no
`NSBonjourServices` advertisement in shipped `Info.plist`." On iOS, `NSBonjourServices` is required
to **browse**, not only to advertise, so no design that discovers a Mac can satisfy that criterion
literally. The design satisfies the *intent* — the iOS app advertises nothing, the service name
names no health concept, and the Mac advertises only while a window is open and a pairing exists —
and §11 proposes the amended criterion.

### 8.3 Pairing and trust state machine

```
unpaired ──(user opens receive window on Mac)──▶ pairing(nonce, PSK, QR displayed)
   ▲                                                        │
   │                                              (phone scans, handshakes)
   │                                                        ▼
   │                                        awaitingConfirmation(sasCode shown both ends)
   │                                                        │
   │                                              (user confirms on phone)
   │                                                        ▼
   ├──────────(user unpairs, R-41: always reachable)──── paired(pskHandle, peerDigest, name)
   │                                                        │
   └──────(PSK rejected / peer digest changed)────── suspended(reason) ──▶ .blockedPendingUserAction
```

A companion is a **destination**, so pairing and re-pointing fire R-40's local notification, appear
in the R-30 ledger with `transportSecurity = .tls13PSK`, appear in the destination list, and can
never be hidden (R-41). Establishing trust is an egress event and is recorded as one.

### 8.4 Wire protocol, and why it is not a special case

`CompanionWire` (L2, Linux-buildable, fuzzable) defines length-prefixed frames:

```
HELLO(protocolVersion, installationID, capabilities)
OFFER(batchID, idempotencyKey, format, schemaVersion, byteCount, digest)
  → RESUME(fromChunk) | RECEIPT(batchID, digest) | REJECT(errorClass, detail)
CHUNK(seq, bytes)  → CHUNK_ACK(seq)
COMMIT(digest)     → RECEIPT(batchID, digest) | REJECT(errorClass, detail)
```

Two properties make this a conforming sink rather than an exception. **`OFFER` for an already-
received `batchID` returns the stored `RECEIPT` immediately** — that is O1 (idempotent redelivery)
implemented in the protocol rather than in the sink. And **`RESUME(fromChunk)` after a dropped
connection** is `supportsResume = true` with no engine involvement, because the engine's contract
already treats a `.retryable` outcome as "call `deliver` again with the same batch."

Frames map one-to-one onto `DeliveryOutcome`: `RECEIPT → .acknowledged`, `REJECT(retryable) →
.retryable`, `REJECT(permanent) → .rejectedPermanent`, pairing loss →
`.blockedPendingUserAction(.pairingLost)`. `SinkCompanion` is roughly 200 lines of adapter over
`CompanionWire` plus one `NWConnection`. Because `CompanionWire` is a pure value-typed codec in the
Linux-clean core, **the companion protocol is testable — and fuzzable — with no second device**,
which is the difference between 5 EW and 8.

**AGPL §13 note** (carried from ADR-0001): the receiver is network-interactive. Operator and user
are the same person, so §13 is inert, but the companion's About screen will carry the source offer
anyway, because the assumption stops holding the moment anyone runs the receiver for someone else.

---

## Cross-cutting: error taxonomy and how failures become PRD outcomes

DP-6 makes the error class the join key across the journal (R-20), the ledger (R-30), the user copy
(R-22, R-60) and the derived run outcome (R-21). It is a **committed, versioned registry** —
`ErrorClass` is a closed enum in `CoreDomain` with a companion manifest carrying, per case: the
user copy key, retryability, whether it blocks destination enablement, its ledger classification,
whether it is a schedule failure or an execution failure, and whether it is a P1 under R-88. A test
asserts the enum and the manifest are in bijection.

### 9.1 The families

| Family | Representative cases | Notes |
|---|---|---|
| `source.*` | `deviceLocked`, `authorizationMissing`, `anchorInvalidated`, `readTimeout`, `hkInternal`, `observerHandlerLost` | `deviceLocked` is an **expected outcome**, not an error (C-02, HK-12). `authorizationMissing` must never generate copy asserting denial (R-60) |
| `schedule.*` | `neverWoken`, `wakeBudgetExpired`, `forceQuitObserved`, `backgroundRefreshDisabled`, `lowPowerModeDeferred` | The R-22 family. Attributed by absence of a run row, or by MetricKit background-exit data. **Distinct user copy from `execute` failures** |
| `transform.*` | `unmappedType`, `unitConversionUnavailable`, `sanityBoundViolation`, `categoryDecodeUnknown` | `timeZoneUnknown` is deliberately *not* here: it is a field value (`TimeZoneSource.unknown`), not a failure (AR-08) |
| `storage.*` | `queueFull`, `diskFull`, `checkpointIntegrity`, `migrationForwardIncompatible`, `torn` | `queueFull` triggers back-pressure then eviction-with-gap-record (§5.4) |
| `transport.*` | `dns`, `tlsHandshake`, `tlsIdentityChanged`, `plainTextNotPermitted`, `hostNotAllowlisted`, `timeout`, `http4xx(code)`, `http5xx(code)`, `brokerRefused`, `pairingLost`, `staleBookmark`, `meteredNetworkRefused` | `tlsIdentityChanged` is a **halt**, not a retry (R-31). `hostNotAllowlisted` should be unreachable and is therefore a defect signal (R-32) |
| `policy.*` | `verificationRequired`, `destinationDisabled`, `userCancelled`, `authorizationRevoked`, `sensitiveTypeNotOptedIn` | `verificationRequired` is what blocks enablement before R-25's test passes |

### 9.2 How outcomes are derived

`RunOutcome.derive(from:)` is a pure total function. Its whole specification:

| Condition on `RunTally` | `RunOutcome` | User-facing surface |
|---|---|---|
| No run row for the expected window | `failed` with `schedule.neverWoken` | R-22 copy: "iOS has not woken the app since …" — **never** "export failed" |
| `read == 0` and no error | `success_nothing_due` | "Nothing new to export" |
| `read == 0`, `source.deviceLocked` present | `success_nothing_due` + lock reason recorded | "The device was locked, so Health data could not be read" (C-02, R-63) |
| For every destination: `acked == committed == read`, no `unconfirmed` | `success` | Watchdog notification rescheduled; widget age reset |
| Any `unconfirmed > 0`, no failures | `unknown_ack` | "Sent, unconfirmed" per destination (R-25) |
| Some destination terminal-failed, at least one acked | `partial` | Per-destination status; R-21 forbids calling this success |
| All destinations terminal-failed | `failed` + dominant `ErrorClass` | Escalation chain (R-23) |
| Cancelled by background-time expiry | `abandoned_no_budget` | R-22 copy distinguishing budget from failure |
| Cancelled by the system or the user | `cancelled_by_system` | Neutral copy; committed work retained |

The invariant R-21 asks for — never `success` when `acked < read` — is the fourth row's guard, and
it is the only row that produces `success`. There is no other path.

### 9.3 Escalation (R-23) and its permission-denied degradation

The escalation is a pure function of journal state and the clock, evaluated in three independent
places so that no single permission can silence it:

1. **In-app indicator** — always available, computed on view appearance from durable state.
2. **Local notification** — scheduled at `lastSuccess + N` (R-24's N, derived from the R-71
   measurement) and **cancelled-and-rescheduled on every success**, so silence itself becomes the
   event. Requires permission.
3. **Status widget** — §5.1 Must precisely because it is rung 2's fallback. Its timeline is
   computed from `lastSuccess` and needs no permission and no background execution.

R-23's acceptance criterion requires the escalation to surface with zero background execution
granted **and again with notifications denied**; rungs 1 and 3 are what make that satisfiable, and
neither depends on the engine having run.

---

## Milestones and sequencing

Constraints honoured: §7.1's two sequencing rules (measurement spikes first of all; wedge before
MQTT, companion and HACS), and R-91's requirement that every NFR maps to a test or a recorded
device protocol. Total **87 EW**, matching §7.1's baseline; the M0 exit criterion is an explicit
re-baseline, because §7.1 instructs it and because the estimate has no contingency.

| # | Milestone | EW | Cum. | Exit criteria (PRD requirement IDs) |
|---|---|---|---|---|
| **M0** | **Measurement and skeleton** | 3 | 3 | **R-70** findings published (HealthKit read throughput at REF-A/REF-B against ≥ 1 M samples). **R-71** findings published (which types cap hourly; delivery with Background App Refresh off; observer wake duration) and **R-24's N derived from it**. **R-100** licence at commit 1. **R-101** DCO CI rejecting an unsigned commit. **R-80** Linux CI green and a required check on an empty core. **R-85** a fork PR with no secrets goes green. Target graph, adjacency manifest and import allowlist gates live. §7.1 **re-baseline published** |
| **M1** | **Domain, catalogue, wire format** | 8 | 11 | **R-12** spec plus machine-readable fixtures committed; CI fails on a breaking change to a frozen version. **R-84** two runs byte-identical; 100 runs on arm64 and x86_64 under hostile locale and time zone produce one digest (per §11's amendment). **R-10** DST-transition, leap-year and unit-boundary fixtures pass; a sample in the repeated hour lands in the correct bucket. **R-81** lint gate on ambient `Date()`/`Calendar.current`/`TimeZone.current`/`Locale.current`. **R-07** catalogue declares aggregation semantics for ~40 families with marked passthrough for the rest. **R-82** tier-1 generates reproducibly from a committed seed in ≤ 10 min |
| **M2** | **Persistence and the write-ahead engine** | 12 | 23 | **R-04** fault injection at all six **R-83** seams: kill the process at every step, assert zero gaps. **R-86** corrupt a checkpoint → explicit failure, no silent full re-export; anchor reset requires a recorded decision. **R-09** fill-the-queue test: gap record accurate, re-export succeeds, back-pressure precedes eviction. **R-83** six seams enumerable in test builds, unreachable in release builds. P5, P13, P14 pass. Checkpoint envelope renders |
| **M3** | **HealthKit seam, delta pipeline, local file, journal** | 10 | 33 | **R-80** core suite passes on Linux with HealthKit unlinked; linked-framework check confirms absence. **R-02** add, edit and delete a sample; destination final state matches HealthKit; replay a batch 10× with unchanged row count. **R-01** a sample dated 30 days back re-emits that day's aggregate; sleep with evening start and morning write time spans the full session. **R-20/R-21/R-22** kill-and-relaunch leaves the journal intact; every forced failure mode names its cause and is not `success`; scheduling and execution failures are distinct outcomes. **R-25** a bogus host fails the test and the destination cannot be saved. First on-device baselines for **R-72**, **R-73**, **R-74** |
| **M4** | **Reconciliation, aggregation, backfill** | 10 | 43 | **R-08** restore-from-backup and deliberate anchor-corruption tests: reconcile detects and repairs. **R-06** recompute and resend a bucket; converges at the sink. **R-07** our aggregates compared against `HKStatisticsCollectionQuery` for a multi-source metric on a real device, divergence documented. **R-05** delete-only-change test documenting observed behaviour including the no-callback case. **R-11** backfill of a seeded 5-year store completes and resumes across a mid-run kill without duplication or skip, on **both** `LongRunTaskHost` implementations. **R-75**, **R-78** measured |
| **M5** | **Honesty surfaces** | 9 | 52 | **R-23** soak with export deliberately broken: escalation surfaces within N with zero background execution granted, **and again with notifications denied**. **R-24** N appears in-product and in the README with the R-71 findings cited. **R-26** automated assertion that no share affordance is reachable without passing the preview; a maintainer diagnoses a seeded failure from the bundle alone; canary test finds no values, tokens or hostnames. **R-69** a user compares a browsed value against an exported record. **R-27** signal emitted and documented; an alert constructible without R-113/R-115. **R-64** automated accessibility audit plus a manual VoiceOver pass of the critical flows. **R-60/R-61/R-62/R-63/R-65/R-66** |
| **M6** | **Security and anti-coercion hardening** | 5 | **57** | **R-30** ledger entry for every run, immutable. **R-31** all four parts present; a changed certificate halts export pending explicit re-approval. **R-32** network capture with a host removed shows zero traffic to it across a full cycle. **R-33** a real device backup contains no credential material. **R-40** notification fires on destination creation and on re-point. **R-41** prohibition recorded and gated at feature review. **R-43** post-action Keychain enumeration returns zero items. **R-44** timed purge (as amended, §11). **R-36/R-37/R-51/R-52** CI gates green. ⇒ **THE WEDGE IS INTERNALLY SHIPPABLE** |
| **M7** | **HTTPS, request template, HA preset** | 6 | 63 | **R-89** nightly job against a real Home Assistant at two pinned versions asserts entity creation and read-back of `unit_of_measurement`, `device_class`, `state_class` and precision; the supported window is declared and enforced by the matrix. **R-35** self-hoster path works only via the named opt-in, logged and visible. **AR-21** grammar review plus a binary symbol audit for dynamic dispatch on remote input. §6.2 conformance suite green for local-file and HTTPS |
| **M8** | **MQTT** | 4 | 67 | **R-90** integration test against an ephemeral broker in CI on macOS and Linux. QoS 0/1/2, retained messages, last will, persistent sessions, TLS with a test CA, client certificates, broker restart mid-publish. QoS 0 yields `Sent, unconfirmed` and `unknown_ack`, never success (**R-25**, **R-21**). D-04's recorded dependency review filed: licence, maintenance health, supply-chain provenance. Conformance suite green |
| **M9** | **Mac companion** | 5 | 72 | Pairing via QR plus the derived confirmation code; PSK in the Keychain per **R-33**. **R-34** static and runtime check: no listener bound on iOS. **AR-01** CI assertion that the macOS target links no HealthKit read path. Conformance suite green **including O1 idempotent re-offer and resume-after-drop**. **R-30** ledger entries with `tls13PSK`. **R-40** on pairing and re-pairing. `CompanionWire` fuzzed on Linux |
| **M10** | **Ecosystem** | 8 | 80 | **R-115** `docker compose up` plus quickstart puts real data on a Grafana panel in under 10 minutes, timed by a non-maintainer on a clean machine (**G-4**). **R-116** listed in HACS; HACS Action and hassfest pass on `main`. **AR-25** our output round-trips through `health-auto-export-server` and its dashboards populate. **R-114** a new engineer on a clean simulator produces a complete export in under 10 minutes. **R-68** an export runs from a Shortcut and appears in the journal |
| **M11** | **Compliance, governance, release engineering** | 3 | 83 | **R-109** medical-device declaration visible before submission; "not a medical device" in first-run, About, README and landing page. **R-111** DSA trader status declared against the legal entity (D-13). **R-105a** both maintainers have tagged a source release; **R-105b** both appear in App Store Connect release history (D-03). **R-106** `CONTINUITY.md` reviewed by someone outside the project. **R-107** machine-readable maintenance status and OS matrix. **R-108** a non-maintainer builds from a tag using only the README. **R-110** feature-flag audit shows no sponsor-gated capability. **R-112** written opinion on file. **R-113** denylist check over published copy, zero matches |
| **M12** | **Soak, device gate, submission** | 4 | **87** | **R-88** ≥ 21 continuous days on a real device with a scripted daily diary; exported record counts reconcile against store counts with **zero discrepancy** (any discrepancy is a P1 by definition) — the day-census comparison of §4.3. **R-87** signed-off device pass on ≥ 2 years of real data from ≥ 3 sources, naming device, OS and store characteristics. **R-91** every NFR mapped to a device test or a named recorded protocol (§11); pre-release job fails on > 20% regression. App Review dry run with **HK-31** notes and a working demo endpoint |

**The §7.1 gate is M6.** At 57 EW — 66% of the budget — the correctness engine, journal, watchdog
and local-file destination are complete, verified and internally shippable, and every subsequent
milestone is additive. If capacity collapses at any point after M6, what exists is the product the
PRD says the wedge is. If capacity collapses before M6, what exists is nothing, which is why the
ordering is not negotiable and why M8, M9 and M10 are last in that order.

---

## Requirements I cannot design as written

Seven. Each with a proposed amendment, offered now because this is the last cheap opportunity.

### 11.1 R-44 — the 60-second purge deadline is not implementable *(highest severity)*

**As written:** "Revoking HealthKit authorisation for a type purges that type's queued payloads
within 60 seconds. Verify: timed test."

**Why not:** iOS provides no notification, callback or observable state change when a user revokes
a read authorisation in Settings or the Health app. `getRequestStatusForAuthorization` reports
whether a *request* would prompt, not the current read authorisation, and read authorisation is
deliberately opaque — that is the same platform property R-60 exists to accommodate. We cannot
detect revocation, so we cannot start a 60-second clock. The requirement is not merely hard; there
is no design that satisfies it.

**Proposed amendment:** *"Within 60 seconds of the app observing that read authorisation for a type
has been revoked — observation occurring at every foreground launch and every background wake —
that type's queued payloads are purged, an entry is written to the R-30 ledger, and the type is
disabled with a user-visible reason. The app additionally offers an explicit per-type 'stop and
purge' action reachable in two taps (R-41), and states in-product that iOS provides no revocation
callback. Verify: timed test from observation, plus a UI test of the explicit action."*

### 11.2 R-84 — cross-platform byte-determinism is not achievable for calendar-dependent output

**As written:** "Output is byte-deterministic given identical input. Verify: two runs over
identical input produce identical bytes." QA's P8 strengthens this to identical SHA-256 across
arm64 and x86_64 under a hostile locale.

**Why not:** Any output carrying a local-time bucket boundary (R-10, AR-09) depends on the
time-zone database. Darwin Foundation and swift-corelibs-foundation do not ship the same tzdata
version, and tzdata changes several times a year. A digest computed on `ubuntu-latest` and one
computed on `macos-26` will diverge for any zone with a transition rule change between their
tzdata versions — legitimately, and without any bug in our code.

**Proposed amendment:** *"Output is byte-deterministic given identical input, configuration and a
declared time-zone database version, which is recorded in the checkpoint envelope and in every
export manifest. Verify: (a) 100 runs on arm64 and on x86_64 under hostile locale and time zone
produce one digest per platform; (b) cross-platform digest equality is asserted for the fixture
subset expressed in UTC and fixed-offset zones; (c) a CI gate fails when the host tzdata version
differs from the recorded one, so a divergence is a visible event rather than a flake."*
Rejected alternative: vendor a pinned tz table — one more dependency and ~2 EW to defend a property
no consumer has asked for.

### 11.3 R-80 vs R-07 — the canonical aggregate for some metrics is only obtainable from HealthKit

**As written:** R-80 requires the whole export pipeline to run with HealthKit not linked and the
core's tests to pass on Linux. R-07 requires per-metric canonical aggregation semantics, and its
verification compares against `HKStatisticsCollectionQuery`.

**Why not both, unqualified:** HealthKit's statistics queries de-duplicate overlapping samples from
multiple sources using an algorithm Apple does not document. For a multi-source cumulative metric
such as `stepCount`, the *canonical* aggregate therefore cannot be computed in a HealthKit-free
core. Either the core computes a different (and knowingly divergent) number, or that metric's
canonical aggregation lives behind the seam and is unverifiable on Linux.

**Proposed amendment:** *"R-80's Linux coverage extends to the whole pipeline with a committed
exception list: metrics whose canonical aggregation provider is `hkStatistics` are exercised on
Linux with a recorded reference vector rather than a live computation, and their canonical
correctness is gated by R-87's device pass instead. The exception list is generated from
`MetricCatalog`, is asserted non-growing without an ADR, and every aggregate record already names
the computation that produced it."* This also settles §12 Q3.

### 11.4 R-91 vs R-77 and R-79 — two NFRs have no mappable automated test

**As written:** "Every performance NFR is expressed as (workload, device, OS, metric, threshold,
percentile) with a committed on-device baseline. NFRs without a mapped test are rejected at Stage 2
review."

**Why not:** R-77 (≤ 1.0% battery per 24 h, mean) and R-79 (≤ 2% of the wake budget consumed by
telemetry, p90) have no API that produces a gateable measurement in CI. MetricKit delivers daily
aggregates from real devices, opportunistically, with no simulator equivalent and no percentile
control. As written, R-91 rejects two of its own NFRs at this review.

**Proposed amendment:** *"Each NFR maps to an automated device test **or** to a named, scripted,
recorded device protocol executed per release (the R-87 pattern). R-77 and R-79 map to the latter,
with MetricKit `cumulativeCPUTime` and Xcode Energy Log as the instruments and the protocol
committed in-repo."*

### 11.5 R-83 — two of the six seam names presuppose an ordering the design deliberately inverts

**As written:** six named seams, including `afterAckBeforeAnchorAdvance`.

**Why not:** R-04's write-ahead discipline advances the cursor at commit, *before* delivery. So
there is no window between ack and anchor advance in which data can be lost — the seam exists but
its original assertion ("no data lost") is trivially true, while the interesting assertion has
moved to "a batch acked but not released is redelivered, and redelivery is safe."

**Proposed amendment:** *keep all six names (they are contractual) and restate two assertions:
`afterAckBeforeAnchorAdvance` asserts that a kill between acknowledgement and queue release causes
redelivery with no duplication at an upserting sink and no gap; `duringAnchorPersist` asserts that
a kill inside the commit transaction leaves the cursor at its pre-write value with the batch absent
(P14: never a torn intermediate).*

### 11.6 R-26 — "full contents rendered on screen" is unbounded as written

**As written:** "Its full contents are rendered on screen to read and scroll before any share
affordance is reachable."

**Why not:** The journal grows without bound. A bundle covering a year is tens of megabytes, and
"render all of it, and the user must scroll it" is not a viable interaction for that size — the
practical effect would be an engineer quietly capping it, which is exactly the erosion RK-5
predicts.

**Proposed amendment:** *"The diagnostic bundle is bounded by construction — the last 30 runs by
default, matching G-2's window, user-adjustable — and every byte that will be shared is rendered in
a scrollable viewer whose end must be reached before the share affordance becomes reachable. The
canary test and the automated 'no share without preview' assertion are unchanged."*

### 11.7 SEC-04's verification criterion cannot be met by any discovering design *(design-input, not a PRD requirement)*

Recorded here because it is a Stage 2 input the PRD carried forward wholesale (§13), and a Stage 3
engineer reading it literally will delete Bonjour discovery. On iOS, `NSBonjourServices` is required
to **browse**. **Proposed criterion:** *"The iOS app advertises no Bonjour service (mDNS capture
shows no advertisement from the device); its `NSBonjourServices` declaration is browse-only and
names no health concept; the macOS receiver advertises only while the receive window is open and
only after at least one pairing exists."*

---

## Open questions for the PM

1. **Neutral identifiers under D-06.** May v1 ship with descriptive, product-name-free target,
   bundle, Keychain-access-group and Bonjour identifiers, with human-facing strings in one constant?
   The Keychain access group and App Group container are **migrations**, not renames, so if
   clearance lands after M2 there is a real cost. I need a yes/no before M0 closes.
2. **Storage choice.** Do you accept a first-party SQLite wrapper over GRDB (§7.3), given the
   dependency budget and the reversal trigger? This is the decision I am least certain of, and it
   is the one that puts a permanent maintenance obligation on the correctness critical path in a
   project whose top risk is abandonment.
3. **Aggregation canonicality.** For multi-source cumulative metrics, is HealthKit's de-duplicated
   statistic the canonical export (with our own sum optionally emitted as a second, separately
   labelled series at roughly double the aggregate payload volume), or do we emit exactly one
   number? This determines the size of §11.3's exception list.
4. **Queue-full ordering.** D-11 chose oldest-first eviction but not whether back-pressure precedes
   it. I have chosen stall-then-evict (§5.4). Confirm, or choose evict-immediately, which keeps
   freshness during a long outage at the cost of losing old data sooner.
5. **Designated exporter (AR-15, not promoted).** iPad ships on the same binary (§5.1) and both
   devices have readable stores. Upsert-by-UUID makes raw overlap harmless; **aggregate mode is not
   protected** — two devices compute different daily totals from different subsets and overwrite
   each other. Do we ship the designated-exporter constraint in v1 (~1 EW, inside M4) or document
   the flapping? I recommend shipping it; it is the cheapest form of a bug report we would
   otherwise be unable to diagnose without telemetry.
6. **The companion, asked once more and then dropped.** M9's 5 EW buys a zero-configuration path
   that R-115's receiver already provides at higher friction. If anything slips before M9, is the
   companion the thing that gives way? I will not raise it again after your answer.
7. **R-38's signing key.** Under D-03's organisation enrolment, who holds the advisory feed's
   signing key, and what is the rotation and compromise plan? The endpoint must be printed in the UI
   and README from M0, so the answer shapes an artefact early.
8. **CC0 over someone else's schema.** ADR-0001 puts the wire spec and fixtures under CC0-1.0. The
   HAE compatibility profile (AR-25) documents a third party's undocumented product surface. Confirm
   the R-112 opinion covers publishing a CC0 mapping document of it, or scope the profile's
   fixtures out of CC0.

---

## ADRs I propose

Titles and one-line decisions. The PM commissions; I will write any of them.

| # | Title | Decision |
|---|---|---|
| **ADR-0002** | Target graph and the HealthKit-free core boundary | A fourteen-target Linux-buildable core, a committed adjacency manifest and an import allowlist, all enforced as required CI checks from commit one (R-80). |
| **ADR-0003** | Write-ahead cursor discipline enforced by type | No API persists an anchor; `CursorAdvance` is accepted only as a field of a batch-commit transaction, and epoch changes require a recorded decision (R-04, R-86). |
| **ADR-0004** | Bounded completeness auditing via a day-census digest | Completeness is audited by a permanent per-(metric, day) order-independent digest plus a UUID index confined to the reconciliation window (R-08, R-05, R-88). |
| **ADR-0005** | SQLite via a first-party thin wrapper | SwiftData and Core Data rejected on R-80; GRDB rejected on Linux-support risk and the AR-27 dependency budget, with a named reversal trigger behind the `StateStore` port (R-80, R-86). |
| **ADR-0006** | Transactions contain no suspension point, and storage owns a serial executor | The transaction closure is synchronous so actor reentrancy cannot tear an invariant, and `fsync` never runs on the cooperative thread pool. |
| **ADR-0007** | The destination sink contract and its eighteen conformance obligations | Sinks hold no cursor, no retry state and no credentials; `SinkScratch` is the only durable surface and correctness must survive its destruction (AR-02, AR-18). |
| **ADR-0008** | Payloads are file handles, not bytes | One decision delivers O(1) memory, background-session upload and a uniform contract across all five sinks (R-74, HK-18). |
| **ADR-0009** | Mac companion transport | Bonjour discovery plus TLS 1.3 PSK established by QR pairing with a key-exporter confirmation code; Multipeer Connectivity rejected on durable peer identity and resumable-transfer grounds (R-31, R-34, RK-11). |
| **ADR-0010** | Determinism scope and the declared tz-database version | Byte-determinism is per-platform plus a declared tzdata version, with cross-platform equality asserted only for offset-stable fixtures (R-84 as amended). |
| **ADR-0011** | The error-class registry, and outcomes as derived values | `ErrorClass` is a committed versioned registry in bijection with a manifest, and `RunOutcome` has no public initialiser (R-21, R-22, DP-6). |
| **ADR-0012** | `os.Logger` only; OTLP isolated in its own target | No `swift-log` facade, preserving `%{private}`/`%{public}`; OTLP export lives in one leaf target so §6.4's "cut OTLP first" is a one-line package edit (R-50, R-53). |
| **ADR-0013** | Two long-run execution hosts, and the price of the iOS 18.0 floor | `LongRunTaskHost` has an iOS 26 `BGContinuedProcessingTask` implementation and an iOS 18 foreground implementation; the ~1.5 EW cost is attributed to D-05 (R-11, R-78). |
| **ADR-0014** | Queue admission control: back-pressure before eviction | A stall is recoverable and an eviction is a permanent gap, so reads stall before the oldest batch is evicted with its gap record (R-09, D-11). |

---

## Appendix A — Requirement coverage map

Where each PRD requirement is designed. Requirements not listed are UX, governance, marketing or
compliance obligations with no structural consequence for this document.

| Requirement | Section |
|---|---|
| R-01 measurement-time watermark | §4.1 stage 4 (Mark), §4.3 |
| R-02 upsert-by-UUID identity | §4.4, §6.1 (`RecordKey`), §6.3 |
| R-03 at-least-once with idempotency key | §6.1, §6.3 (HTTPS row) |
| R-04 write-ahead anchors | §4.1 stage 7, §4.4, ADR-0003 |
| R-05 best-effort tombstones | §4.3 (deletion by absence), §6.2 O10 |
| R-06 aggregation as a first-class mode | §4.1 stages 4–5 |
| R-07 declared aggregation semantics | §3.3 (`MetricCatalog`), §11.3 |
| R-08 high-water mark and reconciliation | §4.2, §4.3 |
| R-09 bounded queue and gap record | §4.4, §5.4 |
| R-10 time zone, DST, canonical units | §3.3 (`CoreTemporal`), §11.2 |
| R-11 resumable full-history backfill | §5.5 |
| R-12 versioned wire specification | §3.3 (`WireFormat`) |
| R-20/R-21/R-22 journal and outcomes | §4.2, §9.2 |
| R-23/R-24 escalation and freshness target | §9.3, §10 M0/M5 |
| R-25 destination verification | §6.1 (`prepare`), §6.2 O11 |
| R-26 diagnostic bundle | §3.3 (`DiagnosticBundle`), §11.6 |
| R-27 consumable staleness signal | §9.3 |
| R-30 egress ledger | §6.2 O16, §7.1 |
| R-31 verification, pinning, halt-on-change | §6.1 (`.blockedPendingUserAction`), §6.2 O12 |
| R-32 host allowlist | §6.1 (`SinkContext.allowlist`), §6.2 O9 |
| R-33 credential storage | §3.3 (`SecureStoreKeychain`), §7.1 |
| R-34 no listening socket on iOS | §8.2 (the Mac listens) |
| R-35 plaintext opt-in | §6.1, §9.1 (`transport.plainTextNotPermitted`) |
| R-36/R-37 no SDKs, no outbound telemetry | §3.2 (package dependency budgets) |
| R-40/R-41 anti-coercion controls | §8.3, DP-9, DP-12 |
| R-43/R-44 delete-all and revocation purge | §3.3, §11.1 |
| R-50 `os.Logger` | §3.3 (`PlatformRuntime`), ADR-0012 |
| R-51 allowlist redaction | §3.3 (`Redaction`), §6.2 O8 |
| R-53/R-54 OTLP | §3.3 (`TelemetryOTLP`), ADR-0012 |
| R-69 data browser | §4.3 (census as the verification surface) |
| R-72…R-79 NFRs | §5.4, §5.5, §10, §11.4 |
| R-80 HealthKit seam and Linux CI | §3.4, §5.2, §11.3 |
| R-81 injected clock and calendar | §3.3 (`CoreTemporal`) |
| R-82 synthetic corpus | §3.3 (`CorpusGen`) |
| R-83 six fault-injection seams | §4.1, §11.5 |
| R-84 byte-determinism | §7.4, §11.2 |
| R-85 fork PRs green | §3.2, §3.4 |
| R-86 inspectable versioned checkpoints | §4.2, §7.5 |
| R-87/R-88 device gate and soak | §4.3, §10 M12 |
| R-89/R-90 HA and MQTT contract tests | §6.3, §10 M7/M8 |
| R-91 NFR form | §11.4 |
| AR-01 asymmetric platform roles | §3.3, §8.1 |
| AR-02 one engine, one sink contract | §6 |
| AR-13 backoff and circuit breaking | §4.1 stage 8 |
| AR-15 designated exporter | §12 Q5 |
| AR-18 credentials by handle | §6.1 (`SinkContext.secrets`), §6.2 O8 |
| AR-21 closed template grammar | §3.3 (`RequestTemplate`) |
| AR-24 curated families plus passthrough | §3.3 (`MetricCatalog`) |
| AR-27 dependency budget | §3.2, §7.2 |
| AR-31 metered networks off by default | §6.1 (`NetworkPolicy`), §6.2 O18 |
