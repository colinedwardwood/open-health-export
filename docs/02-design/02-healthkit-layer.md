# HealthKit Integration Layer — Stage 2

**Stage:** 2 of 4 (System Design)
**Author:** HealthKit Integration Architect
**Status:** Draft for PM synthesis and adversarial review
**Date:** 2026-09-03
**Owns:** R-01, R-05, R-08, R-10, R-62, R-69, R-70, R-71; constraints C-01…C-07
**Inputs:** PRD v1.0 (APPROVED); `contributions/02-healthkit-platform-expert.md` (35 `HK-`);
`contributions/03-principal-architect.md` (`AR-03`…`AR-11`, `AR-30`, NFR-02…NFR-13)

> **Verification note.** Every claim in this document tagged **[SDK]** was checked by me against
> the installed iOS SDK on 2026-09-03: `iPhoneOS26.5.sdk` (`xcrun --sdk iphoneos --show-sdk-path`),
> under Xcode 26.6 with Swift 6.3.3, reading both the Objective-C headers at
> `…/HealthKit.framework/Headers/` and the Swift overlay interface at
> `…/HealthKit.framework/Modules/HealthKit.swiftmodule/arm64e-apple-ios.swiftinterface`.
> The `.swiftinterface` matters: several claims Stage 1 made from the ObjC headers are
> materially different in the Swift surface we will actually use, and two of those differences
> change the design. Claims tagged **[R]** are reported behaviour I could not verify in the SDK
> and have routed into R-70 or R-71 rather than designed against. Claims tagged **[I]** are my
> judgement.
>
> Minimum deployment target is **iOS 18.0 (D-05)**, not the architect's recommended iOS 26.
> Everything below is availability-checked against 18.0, and every iOS-26-only capability is
> named as such with its 18.0 fallback. This is a live cost the PRD accepted and Stage 2 pays.

---

## Executive summary

Six things in this document are load-bearing. The rest is detail that follows from them.

**1. The seam is a paged pull protocol over project-owned value types, and the anchor is opaque
bytes.** `HealthSource` exposes page-at-a-time `AsyncSequence`s of `Sendable`, `Codable` domain
values. No `HK*` type crosses it — including `HKQueryAnchor`, which crosses as an
`AnchorToken` (versioned opaque `Data` the core never interprets). The core package imports
nothing but Foundation, builds on Linux, and its tests run against a fixture-backed fake that
reads the *same* NDJSON domain encoding the real adapter emits. This is the decision everything
else rests on and I have designed it to be cheap to hold: the adapter is the only place in the
codebase that may say `import HealthKit`, enforced by a CI source scan.

**2. Anchors prove progress; only date-ranged sweeps prove coverage.** This inversion is the
answer to R-01. `HKQueryAnchor` orders by write sequence, so it can never certify that any
interval of *measurement* time is complete. So the per-type measurement-time watermark
(`completeThrough`) does not advance on anchored delivery at all. It advances only when a
bounded, date-predicated enumeration positively covers a closed interval. Anchored delivery
carries the raw samples (upsert-safe by UUID) and, separately, *dirties* every aggregate bucket
its samples touch, however old. That dirty-bucket ledger is the mechanism that makes R-01's
"re-emit a 30-day-old window" a normal operation rather than a special case.

**3. `HKDeletedObject` carries a UUID and nothing datable.** **[SDK]** Verified in
`HKDeletedObject.h`: the object exposes `UUID` and a `metadata` dictionary whose documented
available keys are exactly `HKMetadataKeySyncIdentifier` and `HKMetadataKeySyncVersion`. There
is no date, no type, no value. Consequently a deletion cannot be attributed to an aggregate
bucket without our own `uuid → (type, day)` index, and that index cannot be unbounded on a
5–20M-sample store. It is date-bounded with an explicit, journalled fallback. This is the
single most under-appreciated cost in R-05 and R-08 and I have priced it rather than hidden it.

**4. Every quantity metric aggregates through `HKStatistics*`, never through sample summation.**
**[SDK]** `HKQuantityType.aggregationStyle` returns one of `cumulative`,
`discreteArithmetic`, `discreteTemporallyWeighted`, `discreteEquivalentContinuousLevel`, and
`HKStatistics.h` states that mixing a discrete option with a cumulative type (or the reverse)
**throws**. We cannot reimplement temporally-weighted or equivalent-continuous-level averaging
faithfully, and we should not try. The catalogue therefore derives its legal option set from the
SDK at build time and a test asserts agreement across all 120 quantity types. Category types
(sleep, mindfulness, stand hours) have no statistics API and take a declared interval-union
path with an explicit multi-source resolution rule.

**5. The 400ms headless-launch ceiling (R-73) is a design constraint on the boot path, not a
tuning exercise.** It forces: a build-time-compiled metric catalogue (no JSON parsing at
launch), a single indexed row read to decide whether there is work, a free lock short-circuit
before any HealthKit call, and a wake ledger appended to a preallocated file as the very first
statement of every process start. That last one is also the mechanism for R-22: because *every*
launch leaves a trace before it can fail, the absence of a trace is positive evidence that the
OS never woke us.

**6. R-70 and R-71 are specified here as runnable protocols with named decision consequences,
and R-71 must start first.** R-70 is 3–4 engineer-days of work. R-71 is one engineer-day of
harness plus **five calendar weeks** of soak on two devices. R-71's calendar length, not its
effort, is why it is the first thing anyone does on this project. Four NFRs and R-24's
freshness number are void until both land.

The two places I am least comfortable: the deletion-dating index (item 3), whose cost I have
bounded but not eliminated; and the assumption that a descriptor-based multi-type
`HKObserverQuery` receives background deliveries, which I could not verify in the SDK and have
made an explicit gate in R-71.

---

## The seam

### What the seam has to survive

R-80 says the whole export pipeline builds and tests with HealthKit not linked, and the core
passes its tests on Linux, with Linux CI a required check from commit one. C-13 explains why
this is not merely nice: GitHub-hosted macOS runners have no Docker, so every container-based
contract test in the project (R-89's Home Assistant matrix, R-90's MQTT broker, R-115's
reference receiver) depends on the core running on Linux. The seam is not a testing nicety.
It is the thing that makes most of the test strategy possible at all.

### Package topology

```
Sources/
  HealthCore/            Linux + Apple. Foundation only. Domain types, catalogue,
                         watermark and sweep logic, dirty-bucket ledger, serialisers,
                         the HealthSource protocol. NO platform imports of any kind.
  HealthFixtureSource/   Linux + Apple. The fake. Reads NDJSON domain fixtures.
  HealthKitAdapter/      Apple only. The ONLY target permitted to `import HealthKit`.
                         Entire contents wrapped in `#if canImport(HealthKit)`, so it
                         compiles to an empty module on Linux and `swift build` succeeds.
  ExportPipeline/        Linux + Apple. Depends on HealthCore only.
  App/ Widget/ Intents/  Apple only.
```

Two CI gates make this real rather than aspirational:

- **Gate A (source scan).** A test in `HealthCoreTests` walks `Sources/HealthCore` and
  `Sources/ExportPipeline` and fails on any occurrence of `import HealthKit`, `import UIKit`,
  `import BackgroundTasks`, `import Security`, or `import os`. Cheap, unambiguous, runs on
  Linux, catches the failure mode where someone adds a platform import inside an `#if` and
  nobody notices for three months.
- **Gate B (Linux build).** `swift build && swift test` in a pinned `swift:6.3-noble`
  container, required on every PR including forks (R-85 — no secrets, no self-hosted runner).

### Foundation-on-Linux hazards the core must avoid

These are the things that pass on macOS and fail or drift on Linux, and they are the reason
the core's API surface is narrower than it looks like it needs to be. **[I]**, from the shape of
swift-corelibs-Foundation:

| Hazard | Rule for `HealthCore` |
|---|---|
| `NSPredicate` is not usable as a general query language | Predicates never cross the seam. The core expresses a query as a `DateInterval` plus a `TypeKey`; the adapter builds the `NSPredicate` |
| `NSKeyedArchiver` / `NSSecureCoding` | Never used in the core. `HKQueryAnchor` archiving happens inside the adapter; the core sees `Data` |
| `Calendar` / `TimeZone` need host tzdata | All calendar arithmetic goes through an injected `CalendarProvider` (R-81). Deterministic DST tests use a **project-owned zone-rule fixture**, so they do not depend on the container's tzdata |
| `NumberFormatter`, `DateFormatter`, `String(format:)` are locale- and libc-sensitive | Banned in the core. Numbers render via `Double.description` (Swift's own shortest-round-trip algorithm, not libc's `printf`), timestamps via a hand-rolled fixed ISO 8601 writer |
| `Decimal` behaviour differs | Not used. Values are `Double`; the wire spec says so and the sanity-range check in the catalogue is the guard |
| `JSONEncoder` key ordering | `.sortedKeys, .withoutEscapingSlashes` — both available on Linux, and together with the above they are what makes R-84's byte-determinism hold cross-platform |

### The domain types

All are `Sendable`, `Hashable`, `Codable`, and have no reference semantics. Their `Codable`
representation *is* the fixture format, which is how R-82's corpus, the fake, and the adapter's
recorded-device captures all speak one language.

```swift
// Identity ------------------------------------------------------------------
public struct SampleID: Sendable, Hashable, Codable { public let uuid: UUID }

/// The raw HealthKit identifier string for types that have one
/// (e.g. "HKQuantityTypeIdentifierStepCount"), plus project-owned synthetic keys for the
/// ~10 types that have no string identifier ("oh.workout", "oh.workoutRoute",
/// "oh.electrocardiogram", "oh.audiogram", "oh.stateOfMind", "oh.activitySummary", …).
public struct TypeKey: Sendable, Hashable, Codable, RawRepresentable { public let rawValue: String }

/// Stable across catalogue versions. Usually 1:1 with TypeKey; not always
/// (sleepAnalysis fans out to several metrics: asleepDuration, inBedDuration, …).
public struct MetricKey: Sendable, Hashable, Codable, RawRepresentable { public let rawValue: String }

// Time ----------------------------------------------------------------------
public struct Instant: Sendable, Hashable, Codable {          // absolute, no zone
    public let secondsSinceEpoch: Double
}

public enum ZoneSource: String, Sendable, Codable {
    case sampleMetadata      // HKMetadataKeyTimeZone was present  [SDK: an IANA name string]
    case workoutInferred     // derived from the workout's own metadata
    case bucketConfigured    // the user's configured export zone (aggregates only)
    case unknown             // we do not know. We never guess. (AR-08)
}

public struct ZoneStamp: Sendable, Hashable, Codable {
    public let source: ZoneSource
    public let ianaID: String?          // nil unless source == .sampleMetadata / .bucketConfigured
    public let offsetSeconds: Int?      // computed AT the sample's instant; nil when source == .unknown
}

public struct Span: Sendable, Hashable, Codable {
    public let start: Instant
    public let end: Instant
    public let hasUndeterminedDuration: Bool   // [SDK] HKSample.hasUndeterminedDuration, iOS 14.3+
}

// Values --------------------------------------------------------------------
/// A canonical-unit measurement. The unit token is OURS, never HKUnit.unitString (see
/// "Time, time zones and units"). Conversion happens exactly once, in the adapter.
public struct Measure: Sendable, Hashable, Codable {
    public let value: Double
    public let unit: CanonicalUnit          // e.g. .count, .countPerMinute, .kilocalorie, .fraction
}

public enum AggregationStyle: String, Sendable, Codable {
    case cumulative, discreteArithmetic, discreteTemporallyWeighted, discreteEquivalentContinuousLevel
}   // [SDK] mirrors HKQuantityAggregationStyle exactly, including the three iOS-13 additions

// Provenance ----------------------------------------------------------------
public struct Provenance: Sendable, Hashable, Codable {
    public let sourceBundleID: String       // [SDK] HKSource.bundleIdentifier
    public let sourceName: String
    public let sourceVersion: String?       // [SDK] HKSourceRevision.version
    public let productType: String?         // [SDK] HKSourceRevision.productType, e.g. "Watch6,1"
    public let osVersion: String?           // [SDK] HKSourceRevision.operatingSystemVersion
    public let deviceHardware: DeviceStamp? // [SDK] HKObject.device
    public let wasUserEntered: Bool         // [SDK] HKMetadataKeyWasUserEntered
}

// The sample ----------------------------------------------------------------
public struct DomainSample: Sendable, Hashable, Codable {
    public let id: SampleID                 // [SDK] HKObject.uuid — the idempotency key (R-02)
    public let typeKey: TypeKey
    public let span: Span
    public let zone: ZoneStamp
    public let provenance: Provenance
    public let payload: Payload
    public let metadata: [String: MetadataValue]   // allowlisted keys only, see R-51

    public enum Payload: Sendable, Hashable, Codable {
        case quantity(Measure, style: AggregationStyle, seriesCount: Int)   // [SDK] HKQuantitySample.count
        case quantityAggregate(min: Measure, avg: Measure, max: Measure,
                               mostRecent: Measure?, sum: Measure?)         // HKDiscrete/CumulativeQuantitySeriesSample
        case category(value: Int, valueName: String?)                       // [SDK] HKCategorySample.value
        case workout(WorkoutBody)
        case correlationLink(members: [SampleID], correlationType: TypeKey)
        case structured(StructuredBody)     // ECG header, audiogram, state-of-mind, vision Rx
        case seriesHeader(SeriesKind, pointCount: Int?)   // route / heartbeat / quantity series
    }
}

// Deletion ------------------------------------------------------------------
/// [SDK] HKDeletedObject exposes UUID + metadata restricted to HKMetadataKeySyncIdentifier
/// and HKMetadataKeySyncVersion. There is NO date and NO type on the object. `typeKey` below
/// is knowledge from the query that produced it, not from the object.
public struct DomainDeletion: Sendable, Hashable, Codable {
    public let id: SampleID
    public let typeKey: TypeKey
    public let syncIdentifier: String?
    public let syncVersion: Int?
}

// Cursor --------------------------------------------------------------------
/// Opaque to the core. `format` is bumped whenever the adapter's encoding changes so a
/// stale token fails loudly rather than silently (R-86).
public struct AnchorToken: Sendable, Hashable, Codable {
    public let format: Int
    public let bytes: Data
}
```

Two deliberate choices worth defending.

**`TypeKey` is the raw HealthKit identifier string.** It could have been a project-owned enum.
It is not, because HK-03 requires the coverage matrix to be generated by enumerating the SDK and
to fail CI on any unhandled new type (`hypertensionEvent` arrived in iOS 26.2 **[SDK]**). A
closed enum in the core would need a source-generation step to stay in sync and would make
passthrough (AR-24) awkward. A string key with a catalogue lookup keeps the core ignorant of
the SDK's shape while keeping the identifiers exact.

**`AnchorToken` is opaque bytes, not a sequence number.** The temptation is to model the anchor
as an `Int` because the pre-iOS-9 API did. **[SDK]** `HKQueryAnchor` is a class conforming to
`NSSecureCoding` with a single `+anchorFromValue:` constructor and no accessor; its internal
state is not a scalar we may assume anything about. Making it opaque means the core's
watermark logic can never accidentally compare, order, or arithmetic on it — which is exactly
the mistake R-01 exists to prevent.

### The protocol

```swift
public protocol HealthSource: Sendable {

    // Capability and authorisation ------------------------------------------
    func availability() async -> SourceAvailability             // .available / .unsupportedDevice / .restricted / .guestUserMode
    func requestStatus(for grant: FeatureGrant) async throws -> GrantRequestStatus
    func requestReadAuthorization(for grant: FeatureGrant) async throws -> GrantRequestStatus
    func requestPerObjectAuthorization(for grant: FeatureGrant) async throws -> GrantRequestStatus

    // Delta: "what changed since this token" --------------------------------
    /// Ordered by HealthKit's write sequence. Each page carries the token that
    /// supersedes the previous one. Memory is O(pageLimit), never O(store).
    func changes(for typeKey: TypeKey,
                 since token: AnchorToken?,
                 pageLimit: Int) -> ChangePages

    // Coverage: "positively enumerate this closed interval" ------------------
    /// The ONLY operation that may advance a measurement-time watermark.
    /// Also the read path for backfill (R-11), reconciliation (R-08) and the browser (R-69).
    func enumerate(typeKey: TypeKey,
                   over interval: DateInterval,
                   pageLimit: Int) -> SamplePages

    // Aggregates -------------------------------------------------------------
    func statistics(metric: MetricKey,
                    over interval: DateInterval,
                    bucket: BucketSpec,
                    request: StatisticsRequest) async throws -> [StatisticsBucket]

    // Detail fan-out: route points, ECG voltages, heartbeats, quantity series --
    func detail(_ request: DetailRequest) -> DetailPages

    // Change notification -----------------------------------------------------
    func observations(for types: Set<TypeKey>) -> AsyncStream<ObservationEvent>
    func setBackgroundDelivery(_ enabled: Bool,
                               for types: Set<TypeKey>,
                               frequency: DeliveryCadence) async throws
}

public struct ChangePage: Sendable {
    public let added: [DomainSample]
    public let deleted: [DomainDeletion]
    public let tokenAfter: AnchorToken
    public let isFinalPage: Bool
}
public typealias ChangePages = any AsyncSequence<ChangePage, any Error> & Sendable
```

`ObservationEvent` carries the set of `TypeKey`s that changed and a `CompletionReceipt`. The
receipt is the seam's answer to HK-11's three-strike rule: it is a non-`Codable`, non-`Sendable`-
escaping token whose `deinit` traps in debug builds if it was never acknowledged, so "forgot to
call the completion handler on the error path" is a test failure rather than a field report
three weeks later.

### The fake

`FixtureHealthSource` is not a mock with expectations. It is a second, complete implementation
of the same contract over a directory of NDJSON files:

```
fixtures/<corpus-name>/
  manifest.json                    corpus id, seed, generator version, declared invariants
  types/<TypeKey>.ndjson           DomainSample per line, in *write* order
  deletions/<TypeKey>.ndjson       DomainDeletion per line, with a writeSeq field
  zones.json                       project-owned zone rules for the DST fixtures
```

The fake's `AnchorToken` is a JSON `{writeSeq: Int}` in the `bytes` field, which makes anchor
behaviour — including the pathological cases — *scriptable*:

| Fixture scenario | How the fake produces it | What it proves |
|---|---|---|
| Retro-dated insert | a line whose `span.start` is 30 days before the previous line's, at a higher `writeSeq` | R-01's re-emission |
| Edit as delete-then-add | a `DomainDeletion` and a new `DomainSample` with a *different* `SampleID` at the same `writeSeq` | R-02, AR-05 |
| Delete of a sample we never saw | a deletion whose UUID is absent from the corpus | the undatable-deletion path |
| Anchor reset | a `resetAt: writeSeq` marker in the manifest; the fake then serves from 0 again with a fresh `format` | R-08's restore case, R-86 |
| Anchor corruption | the test hands the fake a token with a wrong `format` | explicit failure, not silent full re-export |
| Locked store | manifest declares a `lockedWindows` list of intervals; calls inside one throw `SourceError.storeInaccessible` | C-02, HK-12 |
| Three-strike backoff | the fake stops delivering observations after N unacknowledged receipts | HK-11 |

Every one of those runs on Linux in milliseconds. That is the payoff: the correctness engine —
the 42 engineer-weeks the PRD prices at half of v1 — is testable without a device, without a
simulator, and on a fork PR with no secrets.

### Fixture format is not wire format

Stated once, because conflating them would be an attractive shortcut and a bad one. The
**fixture format** is the serialised `DomainSample` — the *input* to the pipeline, versioned by
the core's `fixtureSchema`. The **wire format** (R-12) is the *output*, versioned independently
with its own stability commitment and its own frozen-fixture CI gate. They will diverge:
the wire format has to carry `observedAt`, batch sequence, exporter instance and schema version
(AR-07, AR-14), none of which are properties of a HealthKit sample. Two schemas, two version
lines, one conversion between them that is itself a tested pure function in the core.

---

## Query strategy by type class

Three SDK findings shape this table, all **[SDK]** from `arm64e-apple-ios.swiftinterface`:

1. **`HKSampleQueryDescriptor.result(for:)` returns `[Sample]`** — a materialised array with no
   streaming form. It is therefore **banned for bulk work**: a limitless sample query over a
   high-cardinality type is exactly the memory bomb R-74 forbids. It is permitted only where
   the result is provably small (`limit ≤ 500`, e.g. the browser's page).
2. **`HKAnchoredObjectQueryDescriptor` has both a one-shot `result(for:)` and a streaming
   `results(for:)`** (iOS 15.4+), and takes `limit: Int?`. The one-shot with an explicit limit
   is our paging primitive everywhere, including for date-ranged enumeration.
3. **`HKObjectQueryNoLimit == 0`** in `HKSampleQuery.h`. In the ObjC API a literal `0` means
   *unlimited*, and in the Swift descriptor `limit: nil` means the same. Both are banned by a
   lint rule. This is a one-character mistake with an out-of-memory consequence.

| Type class | Delta path | Coverage / bulk path | Aggregate path | Notes and limits |
|---|---|---|---|---|
| Quantity, high-cardinality (heartRate, HRV, activeEnergy, stepCount, distance*) | `HKAnchoredObjectQueryDescriptor` per type, `limit = P`, one-shot per page | Same descriptor with a `predicateForSamples(withStart:end:options:.strictStartDate)` and a **throwaway** anchor started at `nil` | `HKStatisticsCollectionQueryDescriptor`, always | The throwaway sweep anchor is never persisted as the delta anchor — see ADR-4. Sweep and delta anchors are different objects with different predicate scopes |
| Quantity, low-cardinality (bodyMass, vo2Max, bloodGlucose) | anchored, `P = 1024` | same | `HKStatisticsCollectionQueryDescriptor` | `mostRecent` option is available from iOS 13 **[SDK]** and is the right statistic for most of these |
| Quantity series (`HKCumulativeQuantitySeriesSample`, `count > 1` **[SDK]**) | anchored — the *parent* sample only | same | statistics (unchanged; HealthKit already accounts for the series) | Point-level expansion via `HKQuantitySeriesSampleQueryDescriptor` (a true `AsyncSequence` **[SDK]**) is **opt-in per type**, off by default. One walk of a year of series-expanded step data is a volume event, not a feature |
| Category, interval-valued (sleepAnalysis, mindfulSession, appleStandHour) | anchored, `P = 512` | anchored + date predicate | **no statistics API exists** — derived, interval-union, see Aggregation | The multi-source overlap problem is entirely ours here. Sleep is the metric the PRD names as the wedge (§1) and it is the one with no HealthKit help |
| Category, event-valued (~45 symptom flags, sleepApneaEvent, hypertensionEvent (iOS 26.2)) | anchored, `P = 512` | anchored + date predicate | count-per-bucket, declared | Availability-gate `hypertensionEvent` — it does not exist below iOS 26.2 **[SDK]** |
| Correlation (`bloodPressure`, `food`) | anchored on the **component** types, not the correlation type | same | statistics on components | The correlation is emitted as a `correlationLink` payload carrying member `SampleID`s. Anchoring the correlation type *as well* would double-deliver the components, since **[SDK]** `HKCorrelation.objects` returns the same `HKSample`s that the component queries return. Named as ADR-6 |
| Workout | anchored on `HKWorkoutType`, `P = 128` | anchored + date predicate | roll-up from workout bodies | **[SDK]** `HKWorkout.allStatistics` (iOS 16+) and `statisticsForType:` give per-workout energy/distance with **zero extra queries**, and the older `totalEnergyBurned`/`totalSwimmingStrokeCount`/`totalFlightsClimbed` are `API_DEPRECATED` as of iOS 18. Use `allStatistics`. `workoutActivities` (iOS 16+) carries multi-sport segments |
| Workout route | discovered per workout via `predicateForObjects(from:)`, then `HKWorkoutRouteQueryDescriptor` | same | none | **[SDK]** `.results(for:)` is an `AsyncSequence<CLLocation>` — genuinely streaming, so a 15k-point ride is O(1) memory. Off by default; enabling it is a per-destination volume decision |
| Heartbeat series | anchored on the series sample | — | none | **[SDK]** `HKHeartbeatSeriesQueryDescriptor.Results` streams `(timeIntervalSinceStart, precededByGap)`. Opt-in |
| ECG | anchored on the ECG type → header only | anchored + date predicate | none | **[SDK]** header carries `numberOfVoltageMeasurements`, `samplingFrequency`, `classification`, `averageHeartRate`, `symptomsStatus`. Voltages need a second streaming query per sample (`HKElectrocardiogramQueryDescriptor`), ~30s at high rate each. **Default: header only.** Voltage export is opt-in with an explicit size warning |
| Audiogram | anchored | anchored + date predicate | none | **[SDK]** `sensitivityPoints` is capped at 30 points and is inline on the sample — no fan-out needed |
| State of Mind (iOS 18) | anchored | anchored + date predicate | valence mean, declared | Structured payload (valence, classification, 38 labels, associations). Does not fit a scalar schema; `structured` payload case exists for exactly this |
| Scored assessments (GAD-7, PHQ-9, iOS 18) | anchored | anchored + date predicate | none | Sensitive class (R-66): individual opt-in, never in a preset |
| Activity summary | **no anchor exists** | `HKActivitySummaryQueryDescriptor` over a date range | it *is* an aggregate | Treated as a recompute-trailing-window metric, never as a delta stream. The trailing window is the reconciliation window `W` |
| Characteristics (6) | no query, no anchor | read on demand | none | Off by default and flagged re-identifying (HK-30). Read once per session, cached, never in the delta pipeline |
| Medications / dose events (iOS 26) | anchored on dose events | anchored + date predicate | count-per-bucket | Entire feature behind `if #available(iOS 26.0, *)` given D-05. **[SDK]** `HKObjectType.requiresPerObjectAuthorization()` (iOS 16+) is the catalogue's discriminator. Apple's own warning that dose events are retro-logged and re-persisted on edit **[R]** makes this the worst case for R-01 and a deliberate v1.1 candidate |
| Vision prescriptions | anchored | — | none | Per-object authorisation. Low value for our personas; recommend passthrough-only |
| Clinical records | — | — | — | Out of scope (HK-08). Entitlement absent from the shipping build, asserted in CI |

### Anchor management

One anchor per `(TypeKey, predicateScope)`. `predicateScope` is a hash of the predicate the
adapter built, and it is stored beside the token. Two rules follow, and both exist because an
anchor's meaning is silently redefined by its predicate:

- A persisted delta anchor is only ever reused with `predicateScope == .unfiltered`. If the
  user's configuration would narrow the predicate (a date floor, a source filter), we do not
  narrow the query — we filter in the pipeline. Narrowing the HealthKit predicate would make
  the anchor mean something different and there is no way to detect that after the fact.
- Sweep anchors are ephemeral, live only for the duration of one sweep cell, and are never
  written to the durable store. A test asserts the store never contains a token whose
  `predicateScope != .unfiltered`.

Anchor advance obeys AR-03/R-04 without exception: the token is written in the same SQLite
transaction that persists the outbound batch and the dirty-bucket entries. There is no code
path that writes a token alone.

### Memory discipline (R-74: ≤100 MB RSS, O(1) in store size)

- **Page size `P` is a per-type-class constant chosen from R-70's M1/M4 curves**, not guessed.
  Starting values pending measurement: 2048 for high-cardinality quantity, 512 for category,
  128 for workout.
- One page resident at a time. The page's `HKSample` objects are converted to `DomainSample`
  and released before the next page is requested — inside an explicit `autoreleasepool` per
  page, because these are ObjC-bridged objects and ARC's release timing without one is not
  something to rely on in a tight loop.
- Serialisation is a streaming write to the outbound queue file. Nothing accumulates a
  `[DomainSample]` across pages. The pipeline's fold state is counters and digests — fixed size.
- Statistics queries are bounded by *bucket* count, not sample count, but 10 years of hourly
  buckets is 87,600 `HKStatistics` objects in one collection. The catalogue caps buckets per
  query at 2,048 and the aggregate engine windows the request. Measured by R-70's M5.
- `HKObjectQueryNoLimit` / `limit: nil` is banned by lint (see above).

---

## Delta correctness

### The wedge, stated precisely

R-01 requires the incremental watermark to key on **measurement** time. HealthKit's only delta
primitive keys on **write** sequence. These are not merely different orderings; they are
different *kinds* of fact:

- An anchor answers: *"have I seen every write up to here?"* It is monotone, total, and cheap.
- A measurement-time watermark answers: *"do I hold every sample whose measurement interval
  falls before time T?"* HealthKit will never tell us this, because a write arriving tomorrow
  can falsify it retroactively.

The incumbent's defect, which the PRD's §1 identifies as our wedge, is that it treats the first
as if it were the second. So the mechanism is an inversion:

> **Anchored delivery advances the anchor and never the watermark. Only a positive, date-ranged
> enumeration advances the watermark.**

Restated as an invariant the tests can assert: `completeThrough` is only ever assigned a value
`T` immediately after an `enumerate(typeKey:over:)` call that covered `[previousCompleteThrough,
T]` to completion without error.

### Per-type cursor

```swift
public struct TypeCursor: Sendable, Codable {
    public var anchor: AnchorToken?
    public var predicateScope: PredicateScope     // always .unfiltered for a persisted anchor
    public var completeThrough: Instant           // measurement-time high-water mark (R-08)
    public var observedFloor: Instant?            // earliest measurement time ever seen
    public var generation: Int                    // bumped on anchor invalidation
    public var lastSweepCompletedAt: Instant?
    public var lastAttemptAt: Instant?
    public var consecutiveFailures: Int
}
```

`generation` is carried in every emitted record. A sink that sees a generation bump knows,
without being told, that it is about to receive a re-assertion of history rather than new data.

### What happens when a retro-dated sample arrives

An anchored page yields a sample whose `span` starts before `completeThrough`. Three things
happen and one thing deliberately does not:

1. The raw sample is emitted as normal. It is upsert-safe by `SampleID` (R-02), so no special
   handling is needed on the raw stream at all. This is the whole reason AR-05 is worth its cost.
2. Every aggregate bucket the sample's `span` intersects is marked dirty, at every configured
   granularity, for every destination configured for aggregate export.
3. `observedFloor` is lowered if the sample predates it, which is how the UI can honestly say
   "we now hold data back to 2019-03-11".
4. **`completeThrough` does not move.** Not forward — an old sample proves nothing about the
   present. Not backward — we still believe our coverage of the interval, and the
   dirty-bucket entry is the repair. Rewinding the watermark on every retro-dated sample would
   turn a normal Apple Watch sync into a full re-sweep.

### The dirty-bucket ledger

```
dirty_bucket(destination_id, metric_key, granularity, bucket_start_utc)  PRIMARY KEY
    reason        enum: retro_insert | deletion | reconcile | catalogue_upgrade | user_request
    first_marked  instant
```

Coalescing is free because the primary key is the bucket identity — a thousand retro-dated
heart-rate samples in one sync produce one dirty row per touched day. Rows are inserted in the
same transaction as the anchor advance and deleted only when the recomputed bucket has been
durably enqueued. The table is bounded in the pathological case by
`destinations × metrics × granularities × days-touched`; a 5-year backfill with daily and
hourly granularity across 40 metrics and 2 destinations is ~7M rows, so **the ledger is
suppressed during backfill and a single `backfillComplete` marker triggers a bulk
aggregate pass instead**. That is a real edge and it needs stating rather than discovering.

The sleep case is the one to keep in mind while reading the above. A session with
`start = 22:47 Tue`, `end = 06:31 Wed`, written at `07:05 Wed`, in a configured zone of
Europe/Berlin, dirties: Tuesday daily, Wednesday daily, and nine hourly buckets. The PRD's R-01
verify clause ("the exported night spans the full session") is satisfied by the raw stream
directly; the aggregate correctness is satisfied by these eleven dirty rows.

### Deletions, and the fact they cannot be dated

**[SDK]** `HKDeletedObject` has `UUID` and a `metadata` dictionary documented as retaining only
`HKMetadataKeySyncIdentifier` and `HKMetadataKeySyncVersion`. No date. No type. This has three
consequences that together are the real cost of R-05:

**(a) The tombstone itself is fine.** We know the type from the query that produced the
deletion, we have the UUID, and R-02's contract is upsert-by-UUID with a tombstone stream keyed
the same way. The raw stream converges.

**(b) The aggregate cannot be repaired without knowing which bucket to dirty.** So we need an
`emitted_index`:

```
emitted_index(uuid BLOB PRIMARY KEY)
    type_ord   INTEGER   -- ordinal into the catalogue, 2 bytes
    day_ord    INTEGER   -- days since epoch, 2 bytes
    digest     INTEGER   -- 64-bit value digest, for reconciliation
```

**(c) That index cannot be unbounded.** At ~40 bytes per row including B-tree overhead, a
20M-sample store is ~800 MB against NFR-14's 60 MB installed footprint. So it is
**date-bounded**: the trailing `H` days (default 400) for all types, plus *unbounded* retention
for low-cardinality high-value types (workout, sleepAnalysis, bodyMass, bloodPressure,
bloodGlucose, ECG) whose lifetime row count is in the tens of thousands. Sizing at REF-DELTA
(20k samples/day): 400 × 20k × 40 B ≈ **320 MB**. Still too large, so `H` is derived, not
fixed: the index is capped at **48 MB** and evicts oldest-day-first, publishing the resulting
horizon in the UI ("deletions older than 2025-11-02 cannot be attributed to a day").

When a deletion's UUID is outside the horizon:

- the tombstone is still emitted (the raw stream stays correct);
- the aggregate cannot be repaired precisely, so we record a journal event
  `deletion_undatable{type, uuid}` and mark the type's aggregate stream
  `verifiedThrough = min(verifiedThrough, indexHorizon)`;
- the next full reconcile (user-triggerable, R-08) repairs it by absence.

This is an honest, bounded loss of *precision*, never of data, and it is exactly the kind of
thing R-05's "documented as such, in the wire spec and in the UI" clause exists for. I would
rather the PM see the number than discover it in Stage 3.

`HKMetadataKeySyncIdentifier`, where present, gives a second dating route (the writing app's own
stable key), so third-party writers who set it get precise deletion handling for free. Apple's
own Health app does not set it in general **[R]**, so we cannot rely on it.

### The reconciliation sweep (R-08)

**What it queries.** For each enabled type and each `(type, local-day)` cell in the window
`W` (default trailing 7 days, per AR-04), a paged enumeration:
`HKAnchoredObjectQueryDescriptor(predicates: [.sample(type:, predicate: predicateForSamples(withStart: dayStartUTC, end: dayEndUTC, options: [.strictStartDate]))], anchor: nil, limit: P)`,
iterated page by page with the returned throwaway anchor. This gives O(P) memory enumeration of
an arbitrary closed interval, which `HKSampleQueryDescriptor` cannot do **[SDK]**.

**How it detects a gap.** Per cell it folds a **census** — a fixed-size value computed from
domain values, so the comparator lives in the core and is Linux-testable:

```swift
public struct CellCensus: Sendable, Hashable, Codable {
    public let count: Int
    public let digestXor: UInt64      // XOR-fold of per-sample digests: order-independent
    public let digestSum: UInt64      // wrapping sum: catches transposition XOR misses
    public let earliest: Instant
    public let latest: Instant
}
```

The per-sample digest is a SipHash of `(uuid, span.start, span.end, canonicalValueBits,
sourceBundleID)` — deliberately *including* the canonical value so that a metadata-only change
is invisible and a value change is not, and deliberately *excluding* `observedAt` so it is
stable across runs. Comparing the store's census against our own recorded census for the same
cell yields four outcomes:

| Store vs ours | Meaning | Repair |
|---|---|---|
| `count` greater | Additions we never saw. The anchor lied, or a wake was missed | Re-emit the whole cell; dirty its buckets |
| `count` smaller | Deletions we never saw — the R-05 failure mode | Emit tombstones for the set difference, computed from `emitted_index`; dirty its buckets |
| Equal counts, differing digests | Value change without a UUID change, or our own encoding bug | Re-emit the cell; raise `reconcile_digest_mismatch` — this one is a P1 signal, not a routine repair |
| Identical | Cell verified | Advance `completeThrough` past the cell |

**What it costs.** Bounded by samples in `W`, never by store size. At REF-DELTA that is
7 × 20k ≈ 140k samples, which at the *assumed* 1,600 samples/s is ~90 seconds — three times the
`BGAppRefreshTask` budget. So the sweep **never runs in an app-refresh wake**. It runs:
(i) on foreground launch when `now − lastSweepCompletedAt > sweepInterval`, chunked and
yielding to the UI; (ii) opportunistically in a `BGProcessingTask` when charging and idle;
(iii) on explicit user request (the R-08 full reconcile). Each `(type, day)` cell is an
independent transaction and therefore a checkpoint, satisfying NFR-13.

The real cost number is R-70's to supply. If measured throughput is 400 samples/s on REF-B, a
7-day sweep is six minutes of foreground work and `W` must shrink or the default must become
opportunistic-only. That is one of R-70's named decision consequences.

### After a restore, reinstall, or anchor invalidation

HealthKit does not tell us an anchor became meaningless. Three detectors, in order of
reliability:

**1. Device-binding mismatch (the good one).** At first run we generate a random
`deviceBinding` UUID, store it in the Keychain at `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
with `NSKeyChainAttrSynchronizable = false` (which R-33 already requires for credentials), and
mirror it in the app container's database. Container state restores from a backup; a
`ThisDeviceOnly` Keychain item does not. So at launch:

| Container binding | Keychain binding | Conclusion |
|---|---|---|
| absent | absent | fresh install |
| present | equal | normal launch |
| present | absent or different | **restored onto a device, or the Keychain was reset. Anchors are suspect** |

**2. Token decode failure or `format` mismatch.** Explicit, loud failure — never a silent reset
(R-86, QA). The journal records `anchor_undecodable` and the type enters the staged-reconcile
path below.

**3. Replay detection (the behavioural backstop).** If an anchored page returns samples of
which ≥90% are already present in `emitted_index` with matching digests, the anchor probably
reset to zero. Raise `anchor_replay_suspected`. This is heuristic and is a signal, not a trigger.

**What we do about it.** Never a silent full re-export, and never a silent watermark reset:

- `generation += 1`, `anchor = nil`, `completeThrough` **unchanged** — we still believe our
  historical coverage and the sweep will prove or disprove it.
- Schedule a **staged reconcile** with a geometrically widening window: 7 days, then 30, 90,
  365, then all-history, each stage a separate resumable job, driven by available budget and
  showing user-visible progress ("verifying your history — 2025 onward checked").
- Re-anchoring from `nil` streams the whole store. Every sample is upsert-safe, so this costs
  bandwidth and battery, not correctness. To bound the bandwidth, the `emitted_index` digest
  acts as a **local suppression filter**: a re-delivered sample whose digest matches an indexed
  row is counted, journalled and *not* re-transmitted. Within the index horizon this makes a
  restore nearly free on the wire; beyond it, we re-emit and say so.
- The journal records `anchor_invalidated{reason}` and R-22's attribution keeps this distinct
  from an execution failure, because it is neither — it is a correctness *event* that we
  detected and handled, and the UI should say so with something closer to pride than apology.

---

## Aggregation and the metric catalogue

### Why the path assignment is the whole problem

AR-30 and R-07 both circle the same fact: `HKStatistics*` de-duplicates overlapping data from
multiple sources, and naive sample summation does not. A user with an iPhone and an Apple Watch
both counting steps will get one number from the Health app and a larger one from summing our
raw NDJSON. The PRD's verify clause for R-07 asks us to compare against
`HKStatisticsCollectionQuery` on a real device and document any divergence.

One honesty note before the design. The de-duplication behaviour is **[R]**, not **[SDK]**:
`HKStatistics.h` documents *what* each option computes and that `separateBySource` exists, but
it does not state that the combined (non-separated) figure de-duplicates overlapping sources.
I am designing as if it does, because the behaviour is consistently reported and because the
`separateBySource` option only makes sense if the default is *not* a plain per-source sum — but
I have routed the confirmation into R-70's measurement M9 rather than asserting it. That
measurement is also, conveniently, the exact evidence AR-30's verify clause demands.

### The catalogue

```swift
public struct MetricDescriptor: Sendable, Codable, Hashable {
    public let metricKey: MetricKey
    public let typeKey: TypeKey
    public let family: MetricFamily             // the ~40 curated families of AR-24
    public let coverage: Coverage               // .curated | .passthrough
    public let canonicalUnit: CanonicalUnit     // our token, never HKUnit.unitString
    public let style: AggregationStyle          // mirrors HKQuantityAggregationStyle
    public let path: AggregationPath
    public let computations: [ComputationSpec]  // what we emit per bucket, each self-naming
    public let legalGranularities: Set<Granularity>
    public let sanityRange: ClosedRange<Double>?
    public let sensitivity: SensitivityClass    // .ordinary | .reidentifying | .restricted (R-66)
    public let minimumOS: OSVersion             // e.g. iOS 26.2 for hypertensionEvent
}

public enum AggregationPath: String, Sendable, Codable {
    case healthKitStatistics    // every HKQuantityType, without exception
    case intervalUnion          // category interval types: sleep, mindfulness, stand hours
    case eventCount             // category event types
    case workoutRollup          // from HKWorkout.allStatistics
    case none                   // series, structured, characteristics — raw only
}

public struct ComputationSpec: Sendable, Codable, Hashable {
    public let id: ComputationID    // e.g. "hk.statistics.cumulativeSum.v1"
    public let statistic: Statistic // .sum .mean .min .max .mostRecent .duration .unionDuration .count
    public let separateBySource: Bool
}
```

Every emitted aggregate record carries its `ComputationID`, its `separateBySource` flag, the
contributing source bundle IDs, the bucket zone ID, and the bucket's absolute UTC bounds. R-07's
"each record names its computation" is that field, and it is what turns a support conversation
from an argument into a lookup.

### Path assignment, and why it is not negotiable per metric

**Every `HKQuantityType` takes `.healthKitStatistics`.** Not "most". Every one. Three reasons,
two of them **[SDK]**:

1. `HKStatistics.h` states plainly that specifying a discrete option on a cumulative type — or
   a cumulative option on a discrete type — **throws an exception**. So the legal option set is
   a function of `HKQuantityType.aggregationStyle` **[SDK]**, and the catalogue must derive it
   rather than declare it. A startup/CI test enumerates all 120 quantity identifiers, reads each
   type's `aggregationStyle`, and asserts the catalogue's `computations` are legal for it. That
   test is also HK-03's coverage-matrix generator, so it earns its keep twice.
2. Two of the four styles are **not reimplementable from samples**.
   `discreteTemporallyWeighted` averages by integrating over time, and
   `discreteEquivalentContinuousLevel` computes an IEC 61672-1 equivalent continuous sound level
   **[SDK: `HKQuantityAggregationStyle.h`]**. Audio exposure metrics use the latter. A naive
   arithmetic mean of decibel samples is not merely different, it is *wrong in a way that
   sounds plausible*, which is the worst kind of wrong for a correctness product.
3. It is the only path that gives us multi-source de-duplication for free, which is the
   divergence users would otherwise report.

**Category interval types take `.intervalUnion`,** because HealthKit offers no statistics API
for them and we have no choice. The multi-source resolution rule is therefore ours to specify
and to defend:

1. Collect all samples of the type intersecting the bucket, grouped by value class (for sleep:
   `inBed`, `awake`, `asleepCore`, `asleepDeep`, `asleepREM`, `asleepUnspecified`).
2. Within a value class, take the **union of intervals**, never the sum of durations. Two
   sources reporting the same 40 minutes of deep sleep contribute 40 minutes, not 80.
3. Across value classes, resolve overlap by source priority: (a) the user's designated exporter
   source for that metric if set; else (b) the source whose `productType` **[SDK:
   `HKSourceRevision.productType`]** matches `Watch*`; else (c) the source contributing the
   longest total interval in the bucket; ties broken deterministically by `sourceBundleID` then
   `SampleID`, so R-84's byte-determinism holds.
4. The bucket declares `computation: "oh.intervalUnion.v1"`, `overlapDetected: Bool`,
   `sourcesConsidered: [bundleID]`, `sourceChosen: bundleID`. If a user disagrees with our sleep
   number, that record tells them exactly why in one line.

**Workouts take `.workoutRollup`,** reading `HKWorkout.allStatistics` **[SDK, iOS 16+]** so the
per-workout energy and distance figures are HealthKit's own computation rather than ours. Note
`totalEnergyBurned` and friends are `API_DEPRECATED` as of iOS 18 **[SDK]** — using them would
be both wrong and about to break.

**Series, structured and characteristic types take `.none`.** There is no defensible aggregate
of an ECG or a state-of-mind label, and inventing one would edge toward R-42's interpretation
prohibition.

### Idempotent bucket keys (R-06)

```
bucketKey = base32( truncate128( SHA-256(
    wireSchemaMajor ‖ metricKey ‖ granularity ‖ bucketZoneID ‖ bucketStartUTCSeconds
)))
```

Deliberately **excluded** from the key: `ComputationID`, catalogue version, exporter instance
ID, and any timestamp of ours.

- Excluding `ComputationID` means a catalogue semantics fix *corrects history in place* on the
  next recompute, rather than orphaning the old row beside a new one. For an archive product
  that is the right outcome, and it is literally what R-06's verify clause asks for
  ("recompute and resend a bucket; assert convergence"). The cost is that a sink cannot see the
  correction as an insert; the mitigation is that the record body carries `computationID`,
  `catalogueVersion` and `computedAt`, and the R-30 ledger plus the journal record that a
  catalogue upgrade caused a mass re-emission. The user is told; the row converges.
- Excluding the exporter instance means two devices converge on one row rather than flapping
  between two. AR-15's designated-exporter rule is what prevents them fighting over the value;
  the body carries `exporterInstanceID` so a sink *can* detect contention if it wants to.

### Preventing a user-visible divergence from the Health app

Three mechanisms, in increasing order of how much I like them:

1. **Self-describing records.** Every aggregate names its computation, zone, bucket bounds and
   sources. A divergence becomes explainable from the payload alone, without a support thread.
2. **A documented divergence taxonomy in the wire spec** — a named section, not a footnote:
   (i) the Health app renders locale-converted units, we emit canonical ones; (ii) the Health
   app's day boundary follows the device's *current* zone, ours follows the configured IANA zone
   (AR-09), so a travel week legitimately differs; (iii) **summing our raw NDJSON gives a larger
   number than our own daily aggregate for any multi-source metric**, because the aggregate is
   de-duplicated and the raw stream is not — this is the one that will generate issues, and it
   needs to be stated in the wire spec, in the README, and in the browser; (iv)
   `separateBySource` sums re-introduce double counting *by design*.
3. **The parity probe in the data browser (R-69).** For a selected metric and day the browser
   shows, side by side: our exported bucket value; a freshly computed `HKStatistics` value; the
   raw sample count; the contributing sources; and one line of plain-language explanation of
   any difference. This is R-69's "compare a browsed value against the exported record" clause
   satisfied literally, it is AR-30's acceptance evidence generated on demand on any user's
   device, and it converts the product's largest support-cost risk into a feature that
   demonstrates the wedge. If one thing in this document survives review unchanged, I would
   like it to be this.

### The data browser's read path (R-69)

The browser reads **live HealthKit**, not our emitted copy. Reading our own copy would make it
a mirror of our bugs and worthless for verification.

- `enumerate(typeKey:over:pageLimit: 200)` with a day or week window, newest first.
- Each row is overlaid, by `SampleID` lookup into `emitted_index`, with one of four states:
  `exported`, `pending`, `tombstoned`, `not selected for export`. That overlay is the honest
  answer to "did this leave my device?" and it needs no network.
- Rows outside the index horizon show `unknown — older than the verification window`, which is
  the same honesty the deletion path requires.
- A type the user has not enabled is not browsable, because browsing it would require an
  authorisation request untied to an enabled feature (C-07, R-62). The browser offers the
  enable affordance instead.
- Zero results always state both causes (R-60) and never assert denial.

---

## Background orchestration

### The 400ms boot path (R-73)

R-73 is ≤400ms p90 on REF-B from headless launch to first HealthKit query. The
`BGAppRefreshTask` budget is roughly 30 seconds **[R]**, so 8 seconds of dependency-graph
construction would burn 27% of it before any work. Four design consequences:

1. **The metric catalogue is compiled at build time** into a static, ordinal-indexed table in
   the binary — not parsed from JSON, not decoded from a plist, not built by registering 200
   descriptors at startup. Catalogue lookup at launch is an array index.
2. **`HeadlessBootstrap` is a hand-written, ~10-line construction path** with no dependency
   container, no SwiftUI, no `@main` App body evaluation on the background path. It builds
   exactly: the wake-ledger file handle, an `os.Logger`, the SQLite handle (WAL, lazy), the
   `HKHealthStore`, and the observer registration.
3. **The work decision is one indexed row read.** A `wake_plan` table holds a single row per
   type with `(due_at, pending_batches)`; deciding "is there work" is one index scan, not a
   traversal of cursors.
4. **Observer queries are installed in `application(_:didFinishLaunchingWithOptions:)`**
   before anything else (HK-10), because HealthKit delivers to queries that already exist.

R-73 is measured, not assumed: it is R-70's measurement M8, run under a real
`BGAppRefreshTask` on REF-B.

### The wake decision tree

```
process starts (any trigger)
│
├─ [0]  append WakeLedger{pid, trigger, monotonic t0} to preallocated file   ← ALWAYS, FIRST
│       (this is R-22's mechanism: every run leaves a trace before it can fail)
│
├─ [1]  isHealthDataAvailable()?                       ── false → journal unsupported_device; exit
│
├─ [2]  UIApplication.isProtectedDataAvailable == false?
│         │  free signal, no HealthKit call. FALSE is reliable evidence of inaccessibility;
│         │  TRUE is not proof of accessibility, because C-02's class is Protected Unless Open
│         │  with a 10-minute relinquish, not Complete Protection.
│         └─ false → journal deferred_device_locked; register protectedDataDidBecomeAvailable;
│                    ack the observer receipt; exit   (cost: ~0 ms)
│
├─ [3]  what changed?
│         observer wake  → ObservationEvent.types (the descriptor initialiser hands us the
│                          changed sample-type set directly  [SDK])
│         BGAppRefresh   → wake_plan rows where due_at <= now, ∪ pending outbound batches
│         both empty     → journal success_nothing_due; exit   (target < 1 s)
│
├─ [4]  lock probe: one anchored query, limit 1, cheapest due type
│         HKErrorDatabaseInaccessible → as [2]. Anchors untouched. NOT an error to the user.
│         HKErrorHealthDataRestricted → journal restricted_by_policy; surface once
│         HKErrorNotPermissibleForGuestUserMode  [SDK, iOS 18+] → journal; surface once
│
├─ [5]  deadline := t0 + budget           budget = R-71-measured p10 wake duration × 0.8
│       for each due type, cheapest-first:
│           page → convert → enqueue + advance anchor + mark dirty buckets   (ONE transaction)
│           if deadline.remaining < oneMorePageEstimate: break
│
├─ [6]  hand the queue to a background URLSession (survives suspension and termination)
│
└─ [7]  journal the outcome from R-21's enumerated set; ack the observer receipt
        (a `defer` on a CompletionOnce box; debug builds trap if it was never acked — HK-11)
```

Two things this tree deliberately never does in a wake: run the reconciliation sweep, and run a
backfill. Both are `BGProcessingTask` or foreground work (NFR-11, R-78).

### Budget discipline

The deadline is an injected value (`Deadline`), not a constant, and not read from the ambient
clock inside the pipeline (R-81). Every loop in the pipeline takes it and checks
`remaining > estimatedCostOfNextUnit`. On exhaustion: checkpoint at the last completed page,
journal `abandoned_no_budget` — which is one of R-21's enumerated outcomes and is **not**
`success` — and acknowledge the receipt so the three-strike counter does not advance.

The budget constant itself comes from R-71: we currently assume 25 of ~30 seconds, and nobody
has published the wake duration granted to an `HKObserverQuery` background launch (the Stage 1
expert flagged this as unverified and I could find nothing in the SDK to change that). If R-71
measures a p10 of 12 seconds, page sizes and checkpoint granularity change. Designing against
an unmeasured 25 would be the same class of error as the incumbent's write-time watermark.

### Device lock (C-02)

C-02's evidence, which the PRD upheld against the adversarial reviewer, is that the HealthKit
store is Data Protection class **Protected Unless Open** and access is relinquished **10 minutes
after lock**, returning on next unlock. **[SDK]** `HKErrorDatabaseInaccessible` is documented in
`HKDefines.h` as "Protected health data is inaccessible because the device is locked."

Behaviour, per HK-12: this is an **expected, non-error outcome**. No anchor advances. No batch
is enqueued. No alarm surfaces. The journal records `deferred_device_locked`, we register for
`protectedDataDidBecomeAvailable`, and we acknowledge the observer receipt so HealthKit does not
count a strike against us. The user-facing surface says nothing at all unless the deferral
persists past the freshness window, at which point R-23's escalation explains *the lock*, not a
failure — because the failure is Apple's ceiling and RK-4 says users will blame us for it
unless we name it first (R-63 requires this disclosure before the first permission prompt).

There is a subtlety worth flagging for the reviewer: the 10-minute relinquish means a wake
arriving 3 minutes after lock may succeed while one arriving 12 minutes after lock fails. So the
lock-failure rate is not a property of "phone locked" but of "phone locked for how long", which
makes it a *measurable distribution* rather than a binary — and R-71's configuration C5 is
designed to measure it.

### R-22: "the OS never woke us" vs "we ran and failed"

The wake ledger at step [0] is the mechanism, and its ordering is the whole trick. Because every
process start appends a ledger row *before any code that can fail*, the record is complete by
construction:

| Evidence | Attribution | Outcome (R-21) | User-facing copy |
|---|---|---|---|
| No ledger row covering the gap | The OS did not start us | `scheduling_gap` | "iOS hasn't run a background update since <time>. This is normal when the phone is locked, in Low Power Mode, or if the app was force-quit." |
| Ledger row, no journal run row | We started and died before journalling — a crash | `unknown_ack` | "An update started but didn't finish. Details in the diagnostic bundle." |
| Ledger row + journal row, outcome ≠ success | We ran and failed | the recorded outcome | The specific cause, never a generic failure |
| Ledger row + `deferred_device_locked` | We ran, correctly did nothing | `success_nothing_due` (deferred variant) | "Waiting for you to unlock your phone." |

Two assertible facts strengthen the first row, and both are worth using because they are
*facts*, unlike read denial: `UIApplication.backgroundRefreshStatus` tells us Background App
Refresh is off, and its being off is legitimate to state. We cannot detect force-quit **[R]**,
so that stays in the "this is normal when…" list rather than being claimed.

The ledger is append-only to a preallocated file, not a SQL insert, precisely because it sits
inside the 400ms budget.

### Background delivery registration

`enableBackgroundDelivery(for:frequency:)` is per `HKObjectType` **[SDK]**, requires the
`com.apple.developer.healthkit.background-delivery` entitlement (HK-09), and takes an
`HKUpdateFrequency` of `immediate | hourly | daily | weekly` **[SDK]** — note `weekly` exists
and is rarely mentioned; it is the right choice for low-churn types like `bodyMass`, and using
it rather than `.immediate` everywhere is free politeness to the system's budget.

The observer itself: **[SDK]** `HKObserverQuery` has an `initWithQueryDescriptors:updateHandler:`
form (iOS 15+) whose handler receives `NSSet<HKSampleType *> *sampleTypesAdded` and a single
completion handler. One multi-type observer with one receipt is strictly better than N observers
with N receipts for HK-11's three-strike risk, and it hands us step [3]'s changed-type set for
free. **But I could not verify in the SDK that background delivery routes to a
descriptor-based observer** — the documentation I have is about the single-type form. This is
a named gate in R-71 (G1). If it fails, the fallback is one observer per enabled type with a
receipt fan-in, which costs registration time in the 400ms budget and raises the three-strike
surface. I would rather find out in week one than in Stage 3.

---

## Measurement spikes R-70 and R-71

Both are specified as protocols someone who is not me can run. Both produce a committed findings
document. Both name, per result, the decision it changes — because a measurement that changes no
decision is not worth a device-week.

**Sequencing.** R-71 is one engineer-day of harness and **five calendar weeks** of soak.
R-70 is 3–4 engineer-days plus up to two days of store seeding. Therefore: build and start
R-71's harness on day one, then run R-70 while R-71's soak elapses. Any other ordering wastes a
month. This is the sequencing recommendation the PRD's §7.1 asked Stage 2 to make.

### R-70 — HealthKit read throughput and the seam's cost

**Artefact.** `spikes/HKThroughput` — a standalone Xcode project with no dependency on product
code, so it is runnable before the product exists and cannot be invalidated by product churn.
Committed to the repo. Its results CSVs are committed too.

**Devices.** REF-A iPhone 15 Pro, REF-B iPhone 11 (the iOS 26 floor). Both on the same iOS 26.x
point release, named in the output.

**Controlled conditions**, all recorded per run: battery ≥80% (Apple DTS's own testing
recommendation **[R]**), Low Power Mode off, Airplane Mode **on** (isolates HealthKit read cost
from network), screen brightness 50%, app in foreground, `ProcessInfo.thermalState` logged before
and after every repetition, run discarded and repeated if thermal state exceeds `.fair`.

**Store conditions.**
- **S1** — the tester's own real store, characterised by a census run first (samples per type,
  date span, distinct source count).
- **S2** — a seeded store from the R-82 Tier-2 corpus. Seeding is via `HKHealthStore.save`, which
  is itself slow; the protocol requires measuring and reporting seed throughput, and permits
  reducing the target from 10M to 1M samples if projected seed time exceeds 6 hours. Report which
  was used.
- **S3** — a store with the target types empty (control, isolates fixed query overhead).

**Measurements.** Five repetitions each; report p50, p90 and max.

| # | Measures | Why |
|---|---|---|
| M1 | Anchored-page delivery rate vs page size `P ∈ {256, 1024, 5120, 10240, 51200}`, `heartRate`, raw `HKSample` delivery only, no conversion | The base number NFR-03 assumed at 1,600/s and never measured |
| M2 | M1 plus conversion to `DomainSample` | **The seam's cost as a percentage.** The number that decides whether the seam is affordable as designed |
| M3 | M2 plus NDJSON + gzip to disk | End-to-end samples/s — the figure R-72 and R-75 actually depend on |
| M4 | Peak `phys_footprint` (from `task_vm_info`, **not** `resident_size`) at each `P` | R-74's ≤100 MB, and it sets the production page size |
| M5 | `HKStatisticsCollectionQueryDescriptor`, daily and hourly buckets, over 1y / 5y / 10y: wall clock and peak footprint | Whether the aggregate path needs windowing, and at what bucket count |
| M6 | `sleepAnalysis` (category) and `HKWorkoutType` + `allStatistics` throughput | Different cost shape; sleep is the wedge metric |
| M7 | Detail fan-out: per-ECG voltage fetch, per-workout route fetch (locations/s), per-series-sample expansion | Whether these can ever be on by default |
| M8 | Cold process start → first sample delivered, under (a) foreground launch, (b) a real `BGAppRefreshTask` on REF-B | **This is R-73's rehearsal.** 400 ms p90 is either reachable or it is not |
| M9 | For a metric with ≥2 real sources (`stepCount` on a phone + watch user), 90 days of daily totals computed both ways: `HKStatisticsCollectionQuery` vs raw sample summation. Report the divergence distribution and the maximum single-day divergence | Confirms or refutes the de-duplication assumption; **this is AR-30's and R-07's acceptance evidence** |

**Output.** `docs/02-design/spikes/R-70-findings.md`: device and OS identifiers, store census,
thermal log, the raw CSVs, the nine result tables, and a mandatory closing table
"NFRs affected: R-72 / R-73 / R-74 / R-75 — hold / at risk / void, with the number".

**Decisions each result changes.**

| Result | Decision it changes |
|---|---|
| M3 p90 ≥ 1,600/s on REF-B | NFR-03 holds; R-72, R-74, R-75, R-78 stand as written |
| M3 p90 in 400–1,600/s | R-75's 30-minute backfill is not reachable. PM chooses: raise the ceiling, cap the default backfill horizon (e.g. 2 years, with an explicit "export everything" affordance), or make first-run backfill aggregate-only. **This is a product decision, not an engineering one** |
| M3 p90 < 400/s | Full-history export changes shape entirely. RK-2 has fired. Re-baseline §7.1 |
| M1 flattens above some `P` | Production page size = the smallest `P` that saturates, because smaller `P` improves R-74's peak and NFR-13's checkpoint granularity. Free win, but only visible from the curve |
| M2 overhead ≤ 25% | The seam ships as designed |
| M2 overhead > 25% | Keep the protocol, change the representation: `DomainSample.metadata` becomes lazily decoded rather than eagerly built, and provenance is interned by source rather than copied per sample. The protocol does not change, so R-80 is unaffected — this is the specific reason the seam is a protocol over values rather than a conversion function |
| M4 exceeds 100 MB at the chosen `P` | Page size drops until it does not. If it cannot, streaming serialisation has a defect and it is a bug, not a tuning problem |
| M5 shows super-linear cost in bucket count | The aggregate engine windows statistics queries; the cap moves from the guessed 2,048 |
| M7 shows route/ECG cost > 10× a plain sample | These stay opt-in permanently and the UI warns with a real number |
| M8 p90 > 400 ms | R-73 is missed. Investigate in order: SQLite open, catalogue load, observer registration. If irreducible, R-73's threshold is renegotiated with evidence rather than quietly missed |
| M9 divergence ≈ 0 | The de-duplication assumption is wrong or the store is single-source. Re-run on a genuinely multi-source store before concluding |
| M9 divergence material | The wire spec's divergence section is mandatory, the browser's parity probe is mandatory, and raw records gain a `deduplicated: false` hint |

### R-71 — Background-delivery reality

**Artefact.** `spikes/HKBackgroundReality` — a minimal app that installs observers, appends one
row per wake to a local journal, and displays the journal. No export, no network, so nothing
else can be blamed for a missing wake.

**Installation matters.** Background delivery does not work in the Simulator **[R]**, and
delivery behaviour differs with a debugger attached. Install via TestFlight, or via Xcode
followed by a physical disconnect and a device reboot. Record which.

**Devices.** REF-A and REF-B, run in parallel, same iOS point release.

**Duration.** Five configurations × 7 days each = **five calendar weeks**, on two devices
simultaneously. Tester effort is ~10 minutes/day.

**Ground truth.** A scripted daily diary the tester performs at fixed times, so that write
events are known rather than inferred: 09:00 a 15-minute walk with the watch; 13:00 a manual
body-mass entry in the Health app; 18:00 a recorded workout; overnight sleep tracked. The diary
is the denominator for "did a wake arrive for this write".

**Configurations**, one week each, both devices:

| # | Configuration | Question it answers |
|---|---|---|
| C1 | Baseline: Background App Refresh on, Low Power off, never force-quit | The honest freshness distribution — R-24's `N` |
| C2 | **Background App Refresh OFF** | HK-32(b), explicitly unverified in Stage 1. Does HealthKit background delivery survive it? |
| C3 | Force-quit at the start of each day, no relaunch | Confirms C-04 empirically, and sizes the copy in R-23's escalation |
| C4 | Low Power Mode on | Degradation shape |
| C5 | Device deliberately locked overnight and for two fixed daytime hours | C-02's failure *rate as a function of time-since-lock*, given the 10-minute relinquish |

**Per-wake record.** Timestamp; trigger class (observer / `BGAppRefreshTask` / `BGProcessingTask`);
the `sampleTypesAdded` set; whether a limit-1 probe read succeeded or returned
`HKErrorDatabaseInaccessible`; `ProcessInfo.thermalState`; battery level; **milliseconds from
process start to first query issued**; **total wake duration until the completion handler was
called** (the harness deliberately burns time in 1-second increments until the system suspends
it, on one instrumented type only, to find the ceiling).

**Types instrumented** — enough to answer the cap question without instrumenting 210:
`stepCount` (Apple documents an hourly cap on iOS **[R]**), `heartRate`, `sleepAnalysis`,
`activeEnergyBurned`, `bodyMass`, `HKWorkoutType`, and two of the ten documented `.immediate`
event types.

**Gates** (things that change the design, not just the numbers):

- **G1.** Does a descriptor-based multi-type `HKObserverQuery` receive background deliveries?
  If no → one observer per type, with the registration cost charged against R-73.
- **G2.** Is `HKUpdateFrequency.weekly` honoured, or silently treated as `hourly`?
- **G3.** Does an unacknowledged completion handler reproduce the documented three-strike
  backoff, and does it recover? Induce it deliberately in the final two days of C1.

**Output.** `docs/02-design/spikes/R-71-findings.md`: per-type inter-wake interval
distributions; the wake-duration distribution (a number nobody appears to have published);
lock-failure rate vs time-since-lock; a per-configuration "did automation survive" verdict; and
the three gate answers.

**Decisions each result changes.**

| Result | Decision it changes |
|---|---|
| C1's p90 of (sample written → wake with a readable store) | **This is R-24's `N`**, rounded up, published with its conditioning clause. Without it there is no defensible freshness target and R-23's watchdog has no threshold |
| Wake-duration p10 | The `Deadline` budget constant, and through it the page size and checkpoint granularity. Currently a guess of 25 s |
| C2 = delivery survives BAR off | The R-63 disclosure and R-23's copy drop a caveat |
| C2 = delivery stops | The app must detect `backgroundRefreshStatus != .available` — an assertible fact — and say so prominently. This becomes a first-run check |
| C5's lock-failure curve | Whether `protectedDataDidBecomeAvailable` retry is sufficient or the widget needs explicit locked-phone copy; and whether the 10-minute relinquish is observable |
| Observed per-type caps | The published coverage matrix gains an "expected wake cadence" column — a genuinely novel artefact, since Apple documents this only for `stepCount` |
| G1 = no | Observer topology changes; R-73's budget is re-checked |
| G3 = does not recover | HK-11's completion discipline escalates from "tested" to "fatal in debug, alarmed in release" |

---

## Authorisation model

### Per-feature grants (R-62, HK-05, C-07)

C-07 records that requesting types not tied to a visible feature is the most-reported HealthKit
rejection cause. The mechanism, not merely the policy:

```swift
public struct FeatureGrant: Sendable, Hashable, Codable {
    public let id: FeatureID          // "sleep", "activity", "vitals", "workouts", "body", …
    public let displayName: String
    public let rationale: String      // shown BEFORE the sheet, distinct from the purpose string
    public let types: Set<TypeKey>    // typically 3–12
    public let sensitivity: SensitivityClass
}
```

Three enforcements:

- `requestReadAuthorization` takes a `FeatureGrant`, not a type set. There is no overload that
  takes a bare set, so there is no code path that can request everything.
- A test asserts `⋃ allGrants.types ≠ allSDKTypes` and that every grant's types are reachable
  from a UI surface that displays the grant's `displayName`.
- Restricted-sensitivity grants (R-66: reproductive, mental health, sexual activity) are
  excluded from every preset and from bulk-select, and require individual opt-in (D-07).

R-63's disclosure — locked-device and best-effort-scheduling reality — precedes the *first*
authorisation request in the flow, and the test asserts the ordering.

### Read denial is unobservable, and the type system says so

Apple guarantees read denial is indistinguishable from absent data (R-60, HK-28). The core
therefore has no `denied` case to accidentally use:

```swift
public enum ReadCoverage: Sendable, Codable {
    case observed(count: Int)
    case emptyIndistinguishable(EmptyReason)   // .noDataOrNotAuthorized — one case, deliberately
}
```

All zero-result copy comes from one file, and a CI denylist check rejects any string in the app
matching `/you (denied|declined|refused)|permission (was )?denied|access denied/i` in a
health-read context. R-60 becomes a build gate rather than a code-review habit, which is what
RK-5 says is necessary for an observability-adjacent requirement to survive Stage 3.

### What we *can* assert: request status

**[SDK]** `getRequestStatusForAuthorizationToShareTypes:readTypes:completion:` exists on
`HKHealthStore`. It returns whether presenting the sheet *would* prompt. That is a fact about
the request state, not a claim about denial, and it is assertible:

| `getRequestStatus` for a grant | What we may say | Action |
|---|---|---|
| `.unnecessary` | Nothing. Proceed | Normal operation |
| `.shouldRequest` | "Health needs your permission again for <feature>." | Offer the request; if this is a *change* from `.unnecessary`, treat as revocation → R-44 purge |
| `.unknown` | Nothing definitive | Retry next activation; do not surface |

We poll it once per foreground activation and once per background wake, per grant — one cheap
call per grant, and we already have grants because of R-62. When a grant flips from
`.unnecessary` to `.shouldRequest` and we need to know *which* type, we binary-search within the
grant: log₂(12) ≈ 4 extra calls, run only on a flip.

Note the asymmetry this creates and be honest about it in the UI: we can detect that the
*authorisation state changed*, we cannot detect that a *read returned nothing because of a
denial*. Those are different sentences and the copy must use the right one.

### Revocation purge within 60 seconds (R-44)

Trigger: a grant flips to `.shouldRequest`, or the user disables a feature in-app. Within one
transaction:

1. Delete queued outbound payloads containing samples of that grant's types. Because the
   outbound queue is chunked per (destination, type-group) rather than mixed, this is a file
   delete plus an index update, not a rewrite — a queue-layout decision made specifically to
   make R-44 cheap.
2. Delete `emitted_index` rows for those types (they are inference surface for data we may no
   longer read).
3. Clear those types' cursors, set `generation += 1` so a later re-grant re-verifies rather
   than resuming from a stale anchor.
4. Journal `authorization_revoked{featureID}` and write an R-30 ledger entry.
5. Disable background delivery for those types.

The 60-second budget is met because the check runs at activation and every step is a bounded
delete. A timed test asserts it (R-44's verify clause), and it runs on Linux against the fake
because none of the five steps is a HealthKit call.

### Per-object authorisation (medications, vision prescriptions)

**[SDK]** `HKObjectType.requiresPerObjectAuthorization()` (iOS 16+) is the discriminator, and
`requestPerObjectReadAuthorizationForType:predicate:completion:` is the request. Design notes:
new medications are authorised by the user *inside the Health app*, without our involvement, so
coverage for these types is **partial by construction**. Every payload for a per-object type
carries `coverage: "partial-by-design"` and the browser says so in words. Given D-05's iOS 18
floor the entire medications feature is behind `if #available(iOS 26.0, *)`, and I recommend it
as v1.1 — Apple's own warning that dose events are retro-logged and re-persisted on edit **[R]**
makes it the single worst case for R-01, and it deserves its own test corpus rather than a
corner of the first release.

### Write authorisation: none

HK-06. `NSHealthUpdateUsageDescription` is absent from `Info.plist`, no `requestAuthorization(toShare:)`
call site exists, and CI asserts both. This also makes ECG's read-only nature a non-issue for us.

---

## Time, time zones and units

### The three timestamps every record carries

1. `startUTC`, `endUTC` — absolute instants, ISO 8601 with `Z`, written by a fixed formatter.
2. `zone` — a `ZoneStamp` (see the seam). **[SDK]** `HKMetadataKeyTimeZone`'s documented value
   type is "an NSString compatible with NSTimeZone's `+timeZoneWithName:`" — that is, an **IANA
   name**, not an offset. So when present we emit both the name and the offset *computed at the
   sample's own instant*, which is the only correct way to get the offset for a historical
   sample in a zone whose rules have changed.
3. `observedAt` — when *we* saw it (AR-14), plus a per-installation monotonic batch sequence.
   The wire spec forbids destinations from ordering or de-duplicating by any of our timestamps.

The architect's measured finding stands and is designed around: regular records essentially
never carry `HKMetadataKeyTimeZone`; Apple Watch sleep records almost always do; workouts do
only when recorded on a watch. So `zoneSource: .unknown` with **no offset field at all** is the
common case, and it is correct. We never substitute the device's current zone — a user who was
in Tokyo did not take those steps in Berlin. `ZoneSource.bucketConfigured` exists only for
aggregate buckets, where the zone is a stated input rather than an inference.

### Bucketing, DST and the repeated hour (R-10)

- The bucket zone is a **user-selected IANA zone per export configuration** (AR-09), shown in
  the UI, defaulting to the device zone at configuration time and never silently changing
  afterwards.
- Bucket boundaries come from `Calendar.dateInterval(of:for:)` in that zone, via the injected
  `CalendarProvider`. This gives correct 23- and 25-hour days without special-casing.
- **The bucket key is the absolute UTC start, never the local wall-clock label.** On a
  fall-back day the local label `01:00` occurs twice; keying on the label would collide the two
  hours and silently sum them. Keying on the instant does not. The local label is decoration and
  is always rendered with its offset attached, so `2026-10-25T01:00:00+02:00` and
  `2026-10-25T01:00:00+01:00` are visibly distinct.
- Fixtures, all in the core and all on Linux: Europe/Berlin 2026-10-25 (fall back: 25 hours, 25
  hourly buckets, two distinct `01:00` buckets, a sample in each); Europe/Berlin 2026-03-29
  (spring forward: 23 hours, 23 hourly buckets, no `02:00` bucket); a zone with a historical
  rule change (Pacific/Apia) to prove offset-at-instant rather than offset-now; 2028-02-29 for
  leap year. These use the project-owned zone-rule fixture, not the host tzdata, so they are
  deterministic in any container.
- Leap seconds are not representable in `Date`; stated in the wire spec as a known limit.

### Units: convert exactly once, never chain

The rule that eliminates a whole class of defects: **`HKQuantity.doubleValue(for:)` is called
exactly once per value, in the adapter, with the catalogue's canonical unit. A converted value
is never converted again.** Everything downstream sees `Measure(value:unit:)` in canonical
units, and the unit token is ours.

**[SDK]**-verified hazards and the rules that follow:

| Hazard | Verified detail | Rule |
|---|---|---|
| Blood glucose mg/dL ↔ mmol/L | `HKUnit.h` defines `HKUnitMolarMassBloodGlucose (180.15588000005408)` and `+moleUnitWithMolarMass:` | Canonical is **mg/dL**. The molar mass is a physical approximation, so a mg/dL → mmol/L → mg/dL round trip is not bit-stable. Convert once, from the `HKQuantity`, and let the consumer convert if they want mmol/L |
| Temperature | `degreeCelsiusUnit`, `degreeFahrenheitUnit`, `kelvinUnit` all exist | Affine, not linear. Canonical **°C**. We never average across units ourselves — the statistics path computes in HealthKit's space and we read the result once in °C. We never emit a temperature *difference*, which is a different dimension |
| Compound units | `-unitDividedByUnit:` builds them; `unitString` is a formatted string | **Never emit `HKUnit.unitString` verbatim.** The catalogue declares our own token (`"mL/kg·min"`, `"count/min"`) and a test asserts our token constructs a compatible `HKUnit` and round-trips a known fixture value |
| Percent vs fraction | HealthKit's `%` is `0.0–1.0` | Canonical is **`fraction`**, emitted as `0.0–1.0`, with the unit token saying so. The HAE-compatibility profile converts to 0–100 because that is what the incumbent emits — and that conversion lives in the profile, not in the core |
| Incompatible unit | `HKQuantity.isCompatibleWithUnit:` and `HKQuantityType.isCompatibleWithUnit:` both exist | Guard **every** conversion. A mismatch is a catalogue bug: `fatalError` in debug, and in release a `metric_unit_mismatch` journal event plus skipping the sample. **Never a silent zero** — a zero is a plausible health value and would corrupt an aggregate invisibly |
| Locale | — | `preferredUnitsForQuantityTypes:` exists **[SDK]** and is used **only** for UI display (R-65). Machine output is never locale-formatted: `.` decimal separator via `Double.description`, ISO 8601 with offset, UTF-8, RFC 4180 CSV (AR-11). CI runs the export suite under `de_DE`, `ar_EG`, `en_US` and byte-compares |

---

## Failure modes and their PRD outcome mapping

`Outcome` values are drawn from R-21's enumerated set: `success`, `success_nothing_due`,
`partial`, `unknown_ack`, `failed`, `abandoned_no_budget`, `cancelled_by_system`.

| Condition | Detection | Anchor / watermark action | Outcome | User surface | PRD |
|---|---|---|---|---|---|
| Device locked | `isProtectedDataAvailable == false`, or `HKErrorDatabaseInaccessible` on the probe | Neither advances | `success_nothing_due` (deferred) | Silent until the freshness window lapses, then "waiting for unlock" | C-02, HK-12, R-21 |
| Store restricted by MDM | `HKErrorHealthDataRestricted` **[SDK]** | Neither | `failed` | Once, explaining it is a device policy | HK-34 |
| Guest User mode | `HKErrorNotPermissibleForGuestUserMode` **[SDK, iOS 18+]** | Neither | `failed` | Once | — |
| Read returns empty | — | Anchor advances (there was genuinely nothing) | `success_nothing_due` | "No data in this period. This can also mean Health isn't sharing this type — open Health to check." **Never** a denial claim | R-60, HK-28 |
| Authorisation revoked | grant flips to `.shouldRequest` | Cursors cleared, `generation += 1` | `failed` for that grant | "Health needs your permission again for <feature>" | R-44, R-62 |
| Observer three-strike backoff | delivery stops; detected by `expectedWakeBy` lapse with no ledger rows | Untouched | `scheduling_gap` | R-23 escalation; diagnostic bundle names the receipt history | HK-11 |
| Anchor token undecodable | decode throws or `format` mismatch | Anchor cleared, watermark **kept**, staged reconcile scheduled | `partial` | "Verifying your history" with progress | R-86, R-08 |
| Restore / reinstall detected | Keychain vs container device binding | As above | `partial` | As above | R-08 |
| Anchor replay suspected | ≥90% of a page already in `emitted_index` with matching digests | Suppression filter engages; sweep scheduled | `partial` | As above | R-08 |
| Deadline exhausted mid-run | injected `Deadline` | Advances only for completed pages | `abandoned_no_budget` | Only if repeated | R-21, NFR-13 |
| Outbound queue at 256 MB | queue accounting | Anchor still advances (the batch was persisted, then evicted) | `partial` | Persisted gap record naming the date range, one-tap re-export | R-09, D-11 |
| Deletion outside index horizon | UUID absent from `emitted_index` | Tombstone emitted; `verifiedThrough` clamped | `partial` | Browser shows "older than the verification window" | R-05 |
| Reconcile count mismatch | census comparison | Cell re-emitted; buckets dirtied | `success` (repair is normal) | Journal only, unless repeated | R-08 |
| Reconcile digest mismatch | census comparison | Cell re-emitted | `partial` + `reconcile_digest_mismatch` | Surfaced — this is a **P1 signal** under R-88 | R-08, R-88 |
| Unit incompatible with catalogue | `isCompatibleWithUnit:` guard | Sample skipped, not zeroed | `partial` | Diagnostic bundle | R-10 |
| New SDK type unhandled | HK-03 enumeration test | — | build failure | — | HK-03 |
| Force-quit | undetectable **[R]** | — | `scheduling_gap` | Listed among normal causes; never claimed | C-04, R-22 |
| Background App Refresh off | `backgroundRefreshStatus` — assertible | — | `scheduling_gap` | Stated plainly, because this one we *can* prove | R-22 |
| Sample count read < acknowledged at sink | pipeline accounting | — | never `success` | Per R-21 | R-21 |

---

## Open questions for the PM

1. **The deletion-dating index costs 48 MB and buys a bounded horizon (~400 days at low volume,
   far less at REF-DELTA).** Beyond it, deletions are emitted as tombstones but cannot be
   attributed to an aggregate bucket until a full reconcile. Do you accept that trade, or should
   the cap rise (at the expense of NFR-14's 60 MB installed footprint), or should the horizon be
   user-configurable with the cost shown? This is the one place where R-05's "best-effort" is
   quantified, and it deserves your signature rather than mine.

2. **Bucket keys exclude `computationID`, so a catalogue semantics fix rewrites history in
   place.** I believe that is right for an archive and it is what R-06's verify clause asks for,
   but it means a sink cannot distinguish "corrected" from "recomputed identically" without
   comparing bodies. The alternative — including `computationID` in the key — leaves orphaned
   rows at every catalogue upgrade. Confirm the choice.

3. **Medications (iOS 26, per-object auth) as v1.1 rather than v1.** They are behind an
   availability gate anyway given D-05, their coverage is partial by construction, and Apple's
   own guidance says dose events are retro-logged and re-persisted on edit — the worst case for
   R-01. I recommend deferring. Confirm.

4. **ECG voltages, workout routes, heartbeat series and quantity-series expansion default to
   OFF.** Each is a per-sample fan-out query whose cost scales with sample count, not query
   count (Stage 1 constraint 10). R-70's M7 will price them. Do you want them presented as
   advanced options with a size estimate, or omitted from v1 entirely?

5. **R-71 needs two devices for five calendar weeks and ~10 minutes of tester time per day, and
   it must start before anything else is built.** Is that resourced? If only one device is
   available, we lose the REF-A/REF-B comparison and R-24's `N` becomes device-specific. This is
   the PRD's own "spikes first" sequencing constraint made concrete, and it has a name attached
   to it or it will not happen.

6. **If R-70 shows throughput between 400 and 1,600 samples/s**, the 30-minute backfill target
   (R-75) is unreachable and the choice is: raise the ceiling, cap the default backfill horizon,
   or make first-run backfill aggregate-only with raw backfill as an explicit user action.
   I would like your preference recorded *now*, before the measurement, so the result does not
   become a negotiation.

7. **Interval-union sleep aggregation resolves multi-source overlap by a rule we invented**
   (designated source → Apple Watch → longest coverage → deterministic tie-break). HealthKit
   offers nothing here. Users comparing against the Health app's sleep figures may disagree with
   us and both of us will be defensible. Do you want the browser's parity probe to cover sleep
   explicitly, even though there is no `HKStatistics` value to compare against and the
   comparison must be against a raw-sample breakdown instead?

---

## ADRs I propose

| # | Decision | Consequence if reversed later |
|---|---|---|
| **ADR-HK-1** | **The seam is a paged pull protocol over project-owned `Codable` value types. No `HK*` type crosses it, including `HKQueryAnchor`, which crosses as opaque versioned bytes.** The `HealthKitAdapter` target is the only place permitted to `import HealthKit`, enforced by a CI source scan and a required Linux build from commit one | Catastrophic. R-80 fails, C-13 makes container-based contract testing impossible, and the correctness engine becomes device-only-testable. This is the one that cannot be retrofitted |
| **ADR-HK-2** | **Anchors advance on delivery; measurement-time watermarks advance only on positive date-ranged enumeration.** No code path may assign `completeThrough` from an anchored result | The R-01 defect returns — which is the incumbent's defect and the product's entire reason to exist |
| **ADR-HK-3** | **Retro-dated arrival dirties aggregate buckets; it never rewinds the watermark.** The dirty-bucket ledger is written in the same transaction as the anchor advance | Either a full re-sweep on every watch sync (unusable), or silently stale aggregates (R-01 violated) |
| **ADR-HK-4** | **Sweep anchors are ephemeral and predicate-scoped; persisted delta anchors are always unfiltered.** A persisted token whose `predicateScope != .unfiltered` is a test failure | Silent data skipping. An anchor reused under a narrowed predicate means something different and nothing detects it |
| **ADR-HK-5** | **Every `HKQuantityType` aggregates through `HKStatistics*`. Sample summation is never an aggregation path for a quantity type.** The catalogue derives its legal option set from `HKQuantityType.aggregationStyle` at build time | Double-counted multi-source metrics, and silently wrong audio-exposure and temporally-weighted averages that look plausible |
| **ADR-HK-6** | **Correlations are anchored on their component types, not the correlation type.** The correlation is emitted as a link record | Double delivery of every blood-pressure and nutrition component |
| **ADR-HK-7** | **A date-bounded `emitted_index` (`uuid → type, day, digest`), capped at 48 MB with oldest-day eviction, is a required component.** Deletions outside the horizon are emitted as tombstones and journalled `deletion_undatable` | R-05's aggregate repair and R-08's census comparison both become impossible. This is a real cost and it should be a recorded decision, not an implementation detail discovered in Stage 3 |
| **ADR-HK-8** | **A wake-ledger row is appended to a preallocated file as the first statement of every process start, before any code that can fail** | R-22's distinction between "the OS never woke us" and "we ran and failed" loses its evidential basis and becomes an inference |
| **ADR-HK-9** | **The metric catalogue is compiled into the binary at build time; it is never parsed at launch.** Nor is any dependency container constructed on the headless path | R-73's 400 ms is unreachable, and 27% of the wake budget is spent before work begins |
| **ADR-HK-10** | **Units are converted exactly once, in the adapter, via `doubleValue(for:)` into a catalogue-declared canonical unit expressed as a project-owned token. `HKUnit.unitString` is never emitted. `isCompatibleWith` guards every conversion, and a mismatch skips rather than zeroes** | Chained-conversion drift, unstable unit strings across OS releases, and silent zeros indistinguishable from real health values |
| **ADR-HK-11** | **Aggregate bucket keys hash `(wireSchemaMajor, metricKey, granularity, zoneID, bucketStartUTC)` and exclude computation and exporter identity.** Bucket start is the absolute UTC instant, never a local wall-clock label | DST fall-back hours collide and sum; or every catalogue upgrade orphans history; or two devices flap |
| **ADR-HK-12** | **The core has no `denied` case for a read.** `ReadCoverage` offers only `observed` and `emptyIndistinguishable`, and a CI denylist rejects denial-asserting copy | R-60 degrades to a code-review habit, which RK-5 says will erode |

---

*Ends. SDK claims marked **[SDK]** were verified on 2026-09-03 against `iPhoneOS26.5.sdk`
under Xcode 26.6 / Swift 6.3.3, reading both the Objective-C headers and the Swift overlay
`.swiftinterface`. Where the Swift surface differs materially from the headers — most
consequentially that `HKSampleQueryDescriptor` returns a materialised array while
`HKAnchoredObjectQueryDescriptor` pages — the Swift surface is what this design targets, because
it is what we will compile against.*
