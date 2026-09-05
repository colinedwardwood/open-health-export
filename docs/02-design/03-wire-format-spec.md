# Wire Format Specification — Stage 2 design

**Stage:** 2 of 4 (System Design)
**Owner:** Data & Schema Engineer
**Status:** Draft for PM synthesis
**Date:** 2026-09-03
**Spec identifier:** `ohe.wire` — **`ohe.wire/1`**, version `1.0` (candidate; frozen at first public release)
**Spec licence:** CC0-1.0 (this document, the JSON Schemas, the metric catalogue and the conformance
fixtures). The app is AGPL-3.0 (D-01); the specification deliberately is not, so a third party can
implement a receiver with no licence question.

Traces: **R-02, R-03, R-05, R-06, R-07, R-10, R-12, R-84, R-89, R-115**, §5.3, AR-05/07/08/09/10/11/14/24/25/30/32,
HK-15/HK-16, MA-01/02/03/09.

---

## Executive summary

The wire format is the only artefact in this project that outlives the project. R-12 makes it a
versioned specification with a stability commitment independent of the app's release cycle, which
means it is the concrete form of our answer to RK-1 (maintainer abandonment): if we stop, a user's
data keeps arriving somewhere useful because somebody else can write a producer or a consumer against
a frozen, CC0, fixture-tested document.

Three things follow from that, and they shape every decision below.

**The correctness wedge is either in the schema or it does not exist.** Upsert-by-UUID (R-02),
tombstones (R-05), declared aggregation semantics (R-07) and honest time zone provenance (R-10) are
not implementation details that a receiver can add later. Either every sample carries
`HKObject.uuid` as a first-class field and the deletion stream is expressible, or the product's
central claim — "your destination matches Apple Health exactly" — is unverifiable. §"Field reference"
and §"Identity, idempotency and determinism" are therefore the load-bearing sections of this
document, not the encodings.

**Three properties that get conflated must stay separate.** Record identity (`uuid`), delivery
idempotency (`batchId`) and byte-determinism (RFC 8785 canonicalisation) answer three different
questions — *which health record is this*, *have I already processed this transmission*, and *does
the encoder produce the same bytes for the same input*. The Stage 1 adversarial review caught exactly
this conflation. §"Identity, idempotency and determinism" states each property, its scope, and four
specific errors that follow from mixing them.

**The Health Auto Export compatibility profile is a lossy export target, not a second native
format.** I researched the incumbent's actual payload from its Help Center and from the Go type
definitions in `apple-health-ingester`, the receiver most third parties build against. The finding
is unambiguous: HAE's metric datapoints carry **no stable identifier at all** — only workouts (v2)
and State of Mind entries have an `id` — and the format has **no way to express a deletion**. So the
compatibility profile cannot carry R-02 or R-05. It buys us day-one access to an existing receiver
ecosystem (the incumbent's real moat, per MA-03) at the price of the two properties that are our
reason to exist. §"Health Auto Export compatibility profile" states the loss in a table rather than
pretending the mapping is total, and recommends that the profile be gated behind an explicit
in-product acknowledgement so a user cannot silently choose the lossy path.

Also decided here, with reasoning: time is emitted as **RFC 3339 UTC instants plus a separate
integer offset and a time-zone provenance enum**, not as local-offset strings and not as epoch
integers; **CSV is declared non-convergent** and says so in the specification, because a CSV consumer
who loads only the samples file will never see a deletion; and the Home Assistant mapping declares
`state_class` per metric with explicit `null` device classes where Home Assistant has no matching
class, because R-89 exists precisely because a wrong or absent class fails silently.

---

## Design goals and non-goals

### Goals

| # | Goal | Why | Verified by |
|---|---|---|---|
| WF-G1 | Every sample carries `HKObject.uuid`; the destination contract is upsert by UUID | R-02, AR-05 | Replay a batch 10×, row count unchanged (fixture `replay-10x`) |
| WF-G2 | Deletion is expressible, and is terminal for a UUID | R-05, HK-16 | Fixture `tombstone-then-resend` |
| WF-G3 | Aggregates carry an idempotent bucket key and name the computation that produced them | R-06, R-07, AR-30 | Fixture `bucket-revision`; recompute-and-resend converges |
| WF-G4 | Time zone provenance is explicit and never fabricated | R-10, AR-08 | Fixture set covers all four `tzSource` values |
| WF-G5 | Units are canonical per metric and named in the payload, independent of locale | R-10, AR-11 | Encoder run under `de_DE`, `ar_EG`, `en_US` produces identical bytes |
| WF-G6 | One logical schema, three encodings, with the CSV loss stated | §5.3 | Fixture triples: same input → `.ndjson`, `.json`, `.csv/` |
| WF-G7 | Frozen v1: additive-only, with CI that fails on a breaking change | R-12 | Four CI gates, §"Versioning and stability policy" |
| WF-G8 | Byte-deterministic output given identical input | R-84 | Two encoder runs byte-compare |
| WF-G9 | A conforming receiver is definable and testable by a third party with no access to us | R-115, MA-03 | Conformance fixture set + expected-final-state assertions |

### Non-goals

| Non-goal | Why |
|---|---|
| Exactly-once delivery semantics | Not achievable over HTTP or MQTT without a two-phase protocol. R-03 commits us to **at-least-once with an idempotency key**, stated in the format, not to a claim we cannot keep |
| A self-describing / schema-less format | Receivers need a frozen contract, not reflection. Every field is declared |
| Round-tripping HealthKit exactly | We emit a projection. `HKMetadata` is carried as an opaque map but is not interpreted, and `HKQueryAnchor` is never emitted (it is our private checkpoint state, per R-86) |
| A query protocol | The format is one-way. No pagination cursors, no server-driven filtering. PC-4 forecloses the inverse direction anyway |
| Making the HAE profile lossless | Structurally impossible. Stated, not engineered around |
| Compression as part of the schema | gzip is a transport concern (NFR-16). The canonical bytes are the uncompressed bytes |
| Encryption or signing of payloads | The transport provides confidentiality (R-35). Payload signing is deliberately deferred; see Open Question 9 |
| Clinical records / FHIR | Out of scope per HK-08 and the PRD non-goals table. No record kind is reserved for them |

---

## Core data model

### Entities

```
Batch  ──1:1── BatchHeader
  │              (spec, version, exporterId, batchId, seq, emittedAt, reason, window)
  ├──0:n── Record
  │          ├── sample.quantity      ─┐
  │          ├── sample.category       │  identity = uuid
  │          ├── sample.correlation    │  (HKObject.uuid)
  │          ├── sample.stateOfMind    │
  │          ├── sample.audiogram      │
  │          ├── sample.ecg           ─┘        ──1:n── series.ecgVoltage
  │          ├── workout              (uuid)    ──1:n── series.workoutRoute
  │          │                                  ──1:n── series.workoutMetric
  │          │                                  ──1:n── series.heartbeat
  │          ├── medicationDose        (uuid)
  │          ├── characteristic        (no uuid — see below)
  │          ├── aggregate             identity = bucketKey
  │          └── tombstone             identity = uuid (terminal)
  └──1:1── BatchFooter
                 (counts, contentDigest, complete)
```

### Relationships and rules

1. **A batch is the unit of delivery.** It is bounded by NFR-16: ≤ 5,000 records or ≤ 4 MB
   uncompressed, whichever comes first. A batch is atomic from the receiver's point of view — it is
   accepted whole or rejected whole.
2. **A batch is homogeneous in `reason` but heterogeneous in record kind.** Samples, tombstones and
   aggregates may share a batch. Receivers must not assume a batch contains one kind.
3. **Child records reference their parent by `parentUuid`.** ECG voltage series, workout routes,
   workout metric series and heartbeat series are separate records so that a 15,360-point ECG or a
   15,000-point route streams in constant memory (NFR-05) instead of forcing a single enormous JSON
   object. A child record MAY arrive in a later batch than its parent. A receiver MUST accept a
   child whose parent it has not yet seen, and MUST NOT drop it.
4. **Series records are chunked.** Each carries `chunkIndex`, `chunkCount` and its own `uuid` derived
   deterministically from `(parentUuid, seriesKind, chunkIndex)` — a UUIDv5 — so a chunk is itself
   upsertable by UUID and a partially delivered series converges on retry.
5. **`characteristic` records have no `HKObject.uuid`** because `HKCharacteristicType` values are not
   samples. Their identity is `(exporterId, characteristicId)`. They are off by default (HK-30, R-66)
   and are re-emitted whole whenever observed to change.
6. **A tombstone is terminal for its UUID.** HealthKit does not reuse UUIDs; an edit in the Health
   app is a delete plus an insert with a *new* UUID (AR-05, HK-16). So a receiver that has seen a
   tombstone for a UUID must never resurrect that UUID, even if an older batch containing the sample
   arrives afterwards. This rule is what makes at-least-once delivery safe in the presence of
   deletions, and it is the single most commonly missed receiver requirement.
7. **Aggregates are not derived from samples at the sink.** They are a first-class parallel stream
   with their own identity (R-06). A sink may receive samples only, aggregates only, or both, and the
   two streams are permitted to disagree — see §"Aggregation records", "Statistics are not the sum of
   samples".
8. **Nothing in the format is ordered.** Records within a batch have a defined *serialisation* order
   (for determinism only) and batches carry a monotonic `seq` (for replay detection only). Neither is
   a delivery order guarantee, and receivers are forbidden from treating any timestamp we emit as an
   ordering or de-duplication key (AR-14).

### Time representation — the decision and the argument

R-10 requires "every record carries the originating time zone offset, and units are canonicalised
per metric with the canonical unit named in the payload". AR-08 adds that the time zone is usually
*unknown* and must never be silently substituted. The measured reality behind that (from the
open-wearables audit cited by the architect) is that regular quantity records essentially never carry
`HKMetadataKeyTimeZone`; Apple Watch sleep records almost always do; workouts do only when recorded
on a Watch.

**Decision: emit a UTC instant, plus a separate integer offset, plus a provenance enum.**

```json
{
  "start": "2026-03-29T00:47:00.000Z",
  "end":   "2026-03-29T00:47:00.000Z",
  "tzOffsetMinutes": 60,
  "tzId": "Europe/Berlin",
  "tzSource": "sampleMetadata"
}
```

- `start` / `end` — RFC 3339 with a literal `Z` and **exactly three** fractional-second digits.
- `tzOffsetMinutes` — signed integer, `null` when unknown. Local wall clock is reconstructible as
  `start + tzOffsetMinutes`.
- `tzId` — IANA identifier, present only when actually known.
- `tzSource` — closed enum: `sampleMetadata` | `inferred` | `deviceCurrent` | `unknown`.

**Why not RFC 3339 with a local offset (`2026-03-29T01:47:00+01:00`)?** It is the most common
suggestion and it is wrong for three reasons.

1. **It destroys lexicographic ordering.** With mixed offsets, string sort ≠ chronological sort. That
   matters concretely: NDJSON is meant to be `sort`-able, `grep`-able and appendable, and a CSV
   opened in a spreadsheet is sorted by string. A traveller's export would interleave incorrectly.
2. **It cannot express "we don't know".** An offset-bearing timestamp forces a claim. Writing
   `+01:00` because the phone is currently in Berlin is precisely the falsification of history that
   AR-08 forbids. Separating the instant from the offset lets `tzOffsetMinutes: null` be honest.
3. **It fights byte-determinism (R-84).** Two encoders that both "have the offset" can legitimately
   render `+01:00` and `+0100`, or normalise differently. One canonical rendering removes the
   question.

**Why not epoch integers?** Epoch milliseconds sort correctly and are compact, and I considered
emitting both. Rejected for v1 on these grounds: it doubles the timestamp bytes on the highest-volume
records for a benefit only the smallest receivers get; it is not human-inspectable, and this format
will be read by people debugging their own health data in a text editor; and it invites the epoch
field and the string field to drift apart in an implementation, which is a whole bug class for free.
Every receiver language in scope parses RFC 3339 `Z` natively — Go `time.RFC3339`, Python
`datetime.fromisoformat` (3.11+), JavaScript `Date.parse`, `jq`'s `fromdate` (which, notably, accepts
*only* the `Z` form), PostgreSQL `timestamptz`, InfluxDB line protocol via any client. Reserved for a
future additive minor: an optional `startEpochMs`. Adding it later is additive; removing it would
not be.

**Sub-millisecond data.** ECG sampling at 512 Hz has ~1.95 ms spacing, which millisecond timestamps
cannot represent without drift. ECG voltage points therefore do **not** carry timestamps at all: the
`series.ecgVoltage` record carries the parent's start instant, `samplingHz`, `startIndex`, and a flat
array of voltages. Point *n* occurs at `parent.start + (startIndex + n) / samplingHz`. This is both
exact and roughly 8× smaller than the incumbent's per-point timestamped objects.

**DST and the repeated hour.** Because we bucket and stamp on *instants*, the repeated 02:00–03:00
local hour in a fall-back transition is never ambiguous: two distinct UTC instants map to the same
wall clock, and both land in the correct bucket by interval containment. The wall clock is a
derived, lossy view, and the format says so.

### Units

One canonical unit per metric, frozen with the metric identifier for the life of the major version,
named in every record (`unit`), independent of the user's locale, of HealthKit's display preference
and of the user's in-app display override (R-65 governs display only, never the wire). Numbers use
`.` as the decimal separator and never use digit grouping (AR-11).

Canonical units are chosen to be (a) SI or the unambiguous clinical convention, (b) a member of Home
Assistant's accepted unit set for the mapped `device_class` wherever one exists, and (c) never
rendered with a locale-dependent glyph. `°C` is emitted as `degC` on the wire and mapped to `°C` in
the Home Assistant discovery payload — the wire stays ASCII, the integration layer does the
prettification.

---

## Field reference

Conventions: field names are `lowerCamelCase`. **R** = required (always present, never `null`).
**O** = optional (omitted entirely when unavailable — never emitted as `null` unless the table says
`null` is meaningful). **N** = nullable-and-required (always present; `null` carries the meaning "we
looked and do not know", which is distinct from omission).

### `batch.header` — first record of every batch

| Field | Type | Req | Semantics |
|---|---|---|---|
| `kind` | string | R | Literal `"batch.header"` |
| `spec` | string | R | Literal `"ohe.wire/1"`. This is the version discriminator a receiver keys on |
| `specVersion` | string | R | `"MAJOR.MINOR"`, e.g. `"1.0"`. Informational; MINOR is always additive |
| `batchId` | string | R | UUIDv7, minted once when the batch is durably persisted to the outbound queue (AR-03). **This is the idempotency key** (R-03) |
| `exporterId` | string | R | Stable per installation (AR-15). UUIDv4, generated on first launch, never derived from any device identifier |
| `seq` | integer | R | Monotonically increasing per `exporterId`, from 1. Never resets. Survives clock changes. Used for replay detection only, never for ordering health data (AR-14) |
| `emittedAt` | string | R | RFC 3339 UTC. Device clock — explicitly untrusted (AR-14, clock skew) |
| `reason` | string | R | Closed enum: `delta` \| `backfill` \| `reconcile` \| `manual` \| `reexportAfterEviction` \| `destinationTest`. Lets a receiver and a dashboard distinguish new data from a reconciliation sweep re-asserting old data |
| `producer` | object | R | `{ "name": string, "version": string }`. Product name and semver. Never a device model or serial |
| `mode` | string | R | Closed enum: `samples` \| `aggregates` \| `mixed` |
| `window` | object | O | `{ "start": rfc3339, "end": rfc3339 }` — the measurement-time window this batch claims to cover. Present for `backfill`, `reconcile`, `manual` |
| `completeThrough` | string | O | RFC 3339 UTC. "For the types listed in `types`, everything with a measurement time at or before this instant has been observed and emitted." This is the field that makes R-27's freshness signal expressible downstream |
| `types` | array&lt;string&gt; | O | Metric identifiers covered by `window` / `completeThrough` |
| `recordCount` | integer | R | Number of records between header and footer |
| `partOf` | object | O | `{ "groupId": uuid, "index": int, "count": int }` when one logical export is split across batches (NFR-16 batching) |

### Common fields — present on every non-envelope record

| Field | Type | Req | Semantics |
|---|---|---|---|
| `v` | integer | R | Major version, `1`. Repeated per record so a single NDJSON line is self-describing when grepped out of context |
| `kind` | string | R | Record kind (see §"Core data model") |
| `uuid` | string | R\* | `HKObject.uuid`, lowercase canonical UUID string. **The primary key.** \*Absent only on `characteristic` and `aggregate`, which declare their own identity |
| `observedAt` | string | R | RFC 3339 UTC — when *we* first saw this object. Distinct from the sample's own time. This is what makes late-arriving data visible (R-01, MA-01) |
| `batchSeq` | integer | R | The `seq` of the batch that carried this record. Denormalised deliberately: NDJSON lines survive being split from their header |

### `sample.quantity`

| Field | Type | Req | Semantics |
|---|---|---|---|
| `metricId` | string | R | Our stable identifier, e.g. `heart_rate`. Frozen once shipped |
| `hkIdentifier` | string | R | The raw HealthKit identifier, e.g. `HKQuantityTypeIdentifierHeartRate`. Present even for curated metrics so a receiver can bypass our taxonomy entirely |
| `semantics` | string | R | Closed enum: `curated` \| `unmapped`. `unmapped` is the AR-24 passthrough: raw identifier, raw value, raw unit, no semantic guarantee |
| `start` | string | R | RFC 3339 UTC, 3 fractional digits |
| `end` | string | R | Equal to `start` for instantaneous samples |
| `tzOffsetMinutes` | integer | N | Signed minutes, or `null` |
| `tzId` | string | O | IANA zone, only when genuinely known |
| `tzSource` | string | R | Closed enum: `sampleMetadata` \| `inferred` \| `deviceCurrent` \| `unknown`. MUST be `unknown` when `tzOffsetMinutes` is `null`. MUST NOT be `sampleMetadata` unless HealthKit metadata actually carried it |
| `value` | number | R | Finite IEEE-754 double. NaN and infinity are forbidden — see `quality` |
| `unit` | string | R | Canonical unit token from the catalogue, e.g. `count`, `bpm`, `kcal`, `km`, `degC`, `mmHg`, `mg/dL` |
| `count` | integer | O | Number of underlying HealthKit samples, when the sample is itself a HealthKit-side aggregate |
| `source` | object | O | `{ "name": string, "bundleId": string, "productType": string }` — the writing app. `bundleId` and `productType` may be absent |
| `device` | object | O | `{ "name": string, "manufacturer": string, "model": string, "hardwareVersion": string, "softwareVersion": string }`. Never a serial number |
| `wasUserEntered` | boolean | O | From `HKMetadataKeyWasUserEntered` |
| `metadata` | object | O | Remaining `HKMetadata` as a flat `string → (string\|number\|boolean)` map. **Opaque**: we neither interpret nor validate it. Keys are the raw HealthKit metadata keys |
| `quality` | string | O | Closed enum: `ok` \| `outOfRange` \| `unconvertible`. Present only when not `ok`; the record is still emitted with the raw value so nothing is silently dropped |

### `sample.category`

As `sample.quantity`, replacing `value` / `unit` with:

| Field | Type | Req | Semantics |
|---|---|---|---|
| `categoryValue` | integer | R | The raw `HKCategoryValue` integer. Stable across our releases and across OS versions in a way names are not |
| `categoryName` | string | R | Human-readable name from an **open** enum, e.g. `asleepDeep`, `awake`, `inBed`. Receivers MUST tolerate unknown members |
| `durationSeconds` | number | O | `end - start`, precomputed. Present for interval categories (sleep stages, mindful sessions) because every receiver computes it and half get DST wrong |

### `sample.correlation`

Blood pressure and food. Container over component samples.

| Field | Type | Req | Semantics |
|---|---|---|---|
| `correlationType` | string | R | Open enum: `bloodPressure` \| `food` |
| `components` | array | R | Array of objects, each `{ "uuid", "metricId", "hkIdentifier", "value", "unit" }`. The component UUIDs are the real `HKObject.uuid`s and are **also** emitted as standalone `sample.quantity` records |

Duplication is deliberate. A receiver that only understands quantity samples gets systolic and
diastolic as independent series; a receiver that understands correlations gets the pairing. Both are
upsertable by their own UUIDs, so the duplication is idempotent, not double-counting.

### `sample.stateOfMind`

| Field | Type | Req | Semantics |
|---|---|---|---|
| `kindOfEntry` | string | R | Closed enum: `dailyMood` \| `momentaryEmotion` |
| `valence` | number | R | −1.0 … 1.0 |
| `valenceClassification` | string | R | Open enum, 7 members: `veryUnpleasant` … `veryPleasant` |
| `labels` | array&lt;string&gt; | R | Open enum, 38 known members (HK). Sorted lexicographically for determinism. May be empty |
| `associations` | array&lt;string&gt; | R | Open enum. Sorted. May be empty |

### `sample.ecg`

| Field | Type | Req | Semantics |
|---|---|---|---|
| `classification` | string | R | Open enum: `sinusRhythm`, `atrialFibrillation`, `inconclusiveHighHeartRate`, `inconclusiveLowHeartRate`, `inconclusivePoorReading`, `inconclusiveOther`, `unrecognized` |
| `averageHeartRate` | number | O | bpm |
| `samplingHz` | number | R | Typically 512 |
| `voltageCount` | integer | R | Total points across all `series.ecgVoltage` chunks |
| `symptomsStatus` | string | O | Open enum: `notSet` \| `none` \| `present` |

**R-42 note.** `classification` is HealthKit's own field, reproduced verbatim. Nothing in this format
or in any conforming receiver may interpret it, threshold it, or alert on it. That prohibition is
part of the receiver contract.

### `series.ecgVoltage` / `series.heartbeat` / `series.workoutRoute` / `series.workoutMetric`

Common series fields:

| Field | Type | Req | Semantics |
|---|---|---|---|
| `parentUuid` | string | R | UUID of the owning `sample.ecg` or `workout` |
| `uuid` | string | R | UUIDv5 over `(parentUuid, kind, chunkIndex)` in the namespace `ohe.wire/1/series`. Deterministic, so a re-sent chunk upserts |
| `chunkIndex` | integer | R | 0-based |
| `chunkCount` | integer | O | Total chunks, when known at emit time |
| `startIndex` | integer | R | Index of the first point within the whole series |

`series.ecgVoltage` adds: `voltages` (array&lt;number&gt;, microvolts, `unit: "uV"`), `samplingHz`.

`series.heartbeat` adds: `intervalsMs` (array&lt;number&gt;, inter-beat intervals),
`precededByGap` (array&lt;boolean&gt;, same length).

`series.workoutRoute` adds `points`: array of
`{ "t": rfc3339, "lat": number, "lon": number, "altitudeM": number, "horizontalAccuracyM": number, "verticalAccuracyM": number, "speedMps": number, "speedAccuracyMps": number, "courseDeg": number, "courseAccuracyDeg": number }`.
Latitude/longitude are emitted at 7 decimal places (≈11 mm), which is well beyond Apple's documented
50 m route accuracy, so no precision is lost by the fixed rendering.

`series.workoutMetric` adds `metricId`, `unit`, and `points`: array of `{ "t", "value" }`.

### `workout`

| Field | Type | Req | Semantics |
|---|---|---|---|
| `activityType` | string | R | Open enum, HealthKit's 84 `HKWorkoutActivityType` cases in lowerCamel, e.g. `running`, `highIntensityIntervalTraining` |
| `activityTypeRaw` | integer | R | The raw enum integer, so a new OS-version activity type is never lost |
| `start`, `end`, `tzOffsetMinutes`, `tzId`, `tzSource` | | R/N | As `sample.quantity` |
| `durationSeconds` | number | R | HealthKit's own duration, which excludes paused intervals and is therefore **not** `end - start` |
| `isIndoor` | boolean | O | |
| `totals` | object | O | Map of `metricId → { "value", "unit", "statistic" }`. Each entry names the computation (R-07), e.g. `{"active_energy": {"value": 431.2, "unit": "kcal", "statistic": "sum"}}` |
| `events` | array | O | `{ "t", "type", "durationSeconds" }`; `type` is an open enum: `pause`, `resume`, `lap`, `segment`, `marker`, `motionPaused`, `motionResumed` |
| `hasRoute` | boolean | R | True if a `series.workoutRoute` exists, **whether or not it is included in this export**. Lets a receiver detect a route it was not sent |
| `seriesIncluded` | array&lt;string&gt; | R | Which series kinds are actually included, e.g. `["workoutRoute","workoutMetric"]`. May be empty |

### `medicationDose`

| Field | Type | Req | Semantics |
|---|---|---|---|
| `medicationName` | string | R | |
| `doseQuantity` | number | O | |
| `doseUnit` | string | O | |
| `status` | string | R | Open enum: `taken` \| `skipped` \| `notLogged` |
| `scheduledAt` | string | O | RFC 3339 UTC |

HK-29 warns that dose events are retro-logged, edited and re-persisted. This record kind therefore
relies on tombstones more heavily than any other, and the receiver contract's "tombstone is terminal"
rule matters most here.

### `sample.audiogram`

| Field | Type | Req | Semantics |
|---|---|---|---|
| `sensitivityPoints` | array | R | `{ "frequencyHz": number, "leftEarDbHL": number, "rightEarDbHL": number, "leftEarMasked": boolean, "rightEarMasked": boolean }`, sorted ascending by `frequencyHz`. Ear fields are individually optional |

### Types that deliberately have no bespoke record kind

Symptoms, cycle tracking, heart rate notifications (`highHeartRateEvent`, `lowHeartRateEvent`,
`irregularHeartRhythmEvent`), sleep apnea events, hypertension events, handwashing and toothbrushing
are all ordinary `HKCategoryType` samples and are emitted as `sample.category`. The incumbent gives
several of these bespoke top-level arrays with bespoke nested shapes; we do not, because they are not
bespoke in HealthKit and inventing structure that Apple did not create is how a format accumulates
special cases it can never remove under a freeze. A receiver that handles `sample.category` handles
all of them, including the ones Apple adds after v1 ships.

The one cost of that choice is that HAE's `heartRateNotifications` array — which carries the
triggering `threshold` and a window of surrounding heart-rate and HRV measurements — has no direct
equivalent. We emit the event as a category sample and the surrounding measurements as ordinary
quantity samples with their own UUIDs. That is more faithful to HealthKit and less convenient for a
receiver that wants the event pre-joined.

### `characteristic`

Off by default (R-66, HK-30). Emitted only for the types the user explicitly enabled.

| Field | Type | Req | Semantics |
|---|---|---|---|
| `characteristicId` | string | R | Closed enum: `biologicalSex`, `bloodType`, `dateOfBirth`, `fitzpatrickSkinType`, `wheelchairUse`, `activityMoveMode` |
| `value` | string | R | Normalised token, e.g. `female`, `aPositive`, `1998-04-17` |
| `reidentifying` | boolean | R | Always `true`. Present so a receiver or an operator can filter the class mechanically without a lookup table |

No `uuid`. Identity is `(exporterId, characteristicId)`; upsert on that pair.

### `aggregate`

See §"Aggregation records and bucket key construction" for the full treatment.

| Field | Type | Req | Semantics |
|---|---|---|---|
| `bucketKey` | string | R | The rendered, opaque-to-the-receiver primary key. Composition is frozen; see below |
| `metricId` | string | R | |
| `hkIdentifier` | string | R | |
| `statistic` | string | R | Closed enum: `sum` \| `mean` \| `min` \| `max` \| `count` \| `duration` \| `mostRecent` \| `weightedMean` |
| `computation` | string | R | Closed enum: `hkStatisticsCollectionQuery` \| `hkStatisticsQuery` \| `localSampleFold`. **This is R-07's field.** It names the mechanism, not just the statistic |
| `sourceScope` | string | R | Closed enum: `all` \| `preferred` \| `single`. `all` = HealthKit's multi-source de-duplicated result; `single` = one named source |
| `sourceName` | string | O | Present iff `sourceScope` is `single` |
| `granularity` | string | R | Closed enum, ISO 8601 durations: `PT1M`, `PT5M`, `PT15M`, `PT1H`, `P1D`, `P1W`, `P1M` |
| `bucketStart` | string | R | RFC 3339 UTC, inclusive |
| `bucketEnd` | string | R | RFC 3339 UTC, **exclusive** |
| `bucketDurationSeconds` | integer | R | Actual elapsed seconds. 82800 or 90000 for a `P1D` bucket across a DST transition |
| `tzId` | string | R | The IANA zone the bucket boundaries were computed in — user-selected per export configuration (AR-09) |
| `localStart` | string | R | Local wall clock without offset, e.g. `2026-03-29T00:00:00`. A derived convenience; `bucketStart` is normative |
| `value` | number | N | `null` is meaningful: the bucket exists and is empty (distinct from the bucket being absent, which means we have not computed it) |
| `unit` | string | R | |
| `sampleCount` | integer | R | Number of underlying samples folded in. `0` with `value: null` for an empty bucket |
| `state` | string | R | Closed enum: `open` \| `final` \| `revised` |
| `emitSeq` | integer | R | The `seq` of the batch that emitted this revision. The receiver's tiebreak token |
| `computedAt` | string | R | RFC 3339 UTC, device clock. Diagnostic only; never a tiebreak (AR-14) |
| `supersedes` | integer | O | The `emitSeq` this revision replaces, when known |

### `tombstone`

| Field | Type | Req | Semantics |
|---|---|---|---|
| `uuid` | string | R | The UUID of the object that no longer exists |
| `targetKind` | string | O | The record kind of the deleted object when known. HealthKit's `HKDeletedObject` does not always let us determine it |
| `metricId` | string | O | Known when the deletion came from a per-type anchored query, which is the normal case |
| `hkIdentifier` | string | O | |
| `reason` | string | R | Closed enum: `healthKitDeleted` \| `reconciliationAbsent` \| `authorizationRevoked`. The second is R-08's sweep detecting removal by absence; the third is R-44 |
| `bestEffort` | boolean | R | Always `true`. R-05 requires the format itself to state that deletion propagation is best-effort. A receiver reading only the wire spec learns this without reading our README |
| `metadata` | object | O | `HKDeletedObject.metadata`, when present |

### `run.receipt` — optional trailer

A projection of the R-20 journal entry for the run that produced this batch, emitted when the user
enables it per destination. It is the mechanism that lets a receiver reproduce R-21's honesty rule
rather than trusting a 2xx.

| Field | Type | Req | Semantics |
|---|---|---|---|
| `runId` | string | R | UUID |
| `trigger` | string | R | Closed enum: `observerQuery` \| `backgroundRefresh` \| `continuedProcessing` \| `appIntent` \| `foregroundManual` |
| `outcome` | string | R | Closed enum, exactly R-21's set: `success`, `successNothingDue`, `partial`, `unknownAck`, `failed`, `abandonedNoBudget`, `cancelledBySystem` |
| `samplesRead` | integer | R | |
| `samplesSent` | integer | R | |
| `errorClass` | string | O | Open enum |
| `phaseTimingsMs` | object | O | `string → integer` |

Contains no health values and no destination hostnames, so it is safe under R-51's allowlist.

### `batch.footer` — last record of every batch

| Field | Type | Req | Semantics |
|---|---|---|---|
| `kind` | string | R | `"batch.footer"` |
| `batchId` | string | R | Must equal the header's |
| `counts` | object | R | `recordKind → integer` |
| `contentDigest` | string | R | `"sha256:<hex>"` over the canonical bytes of every record line between header and footer, in serialisation order, each terminated by `\n`. **Integrity check only** — not an identity, not an idempotency key |
| `complete` | boolean | R | `false` if the producer knows it truncated (memory pressure, task expiry). A `false` here plus a 2xx is exactly the "succeeded but nothing arrived" failure the incumbent has, made visible |

---

## Encodings

One logical schema, three encodings. The **canonical form** — the one that `contentDigest` is computed
over and that R-84 constrains — is defined once and reused.

### Canonical form (normative)

Every JSON object in every encoding is serialised per **RFC 8785, JSON Canonicalization Scheme
(JCS)**:

- UTF-8, no BOM.
- Object members sorted by key, ascending, by UTF-16 code unit.
- No insignificant whitespace.
- Numbers serialised per ECMAScript `Number::toString`: the shortest decimal that round-trips to the
  same IEEE-754 double. `-0` normalises to `0`. NaN and ±Infinity are not representable and are
  forbidden by the schema.
- Strings escaped minimally per JSON; no `\uXXXX` escaping of characters that do not require it.

Adopting an existing standard rather than inventing "our canonical JSON" is deliberate: R-84's test
becomes "does our encoder agree with the JCS reference vectors", which is a solved problem with
third-party test suites, instead of a rule only we can check.

**Record serialisation order within a batch** (also normative, for R-84): ascending by the tuple

```
(kindRank, metricId ?? "", start ?? bucketStart ?? observedAt, uuid ?? bucketKey)
```

with `kindRank` a frozen integer per record kind (header 0; samples 10; series 20; workouts 30;
aggregates 40; tombstones 50; receipt 90; footer 99). Ties beyond `uuid` are impossible because
`uuid`/`bucketKey` are unique within a batch.

**Determinism inputs.** `batchId`, `emittedAt`, `observedAt`, `computedAt`, `seq` and `exporterId`
are *inputs* to the encoder, injected by the caller (R-81), never read from the ambient environment
inside it. Without this, byte-determinism is unachievable and R-84 is untestable. This is worth
stating in the specification, not just in our code, because a third-party producer that wants to
claim conformance needs the same discipline.

### NDJSON — native streaming form

- Media type `application/x-ndjson`; file extension `.ndjson`; gzip per NFR-16.
- One canonical JSON object per line, `\n` (LF) terminated, **including the last line**. No `\r`.
- Line 1 is `batch.header`; the last line is `batch.footer`.
- A file MAY contain multiple concatenated batches (header…footer, header…footer). This is what makes
  the local-file destination appendable.

```
{"batchId":"0192f3c1-...","completeThrough":"2026-03-29T09:00:00.000Z","emittedAt":"2026-03-29T09:00:04.000Z","exporterId":"6b1c...","kind":"batch.header","mode":"mixed","producer":{"name":"open-health-exporter","version":"1.0.0"},"reason":"delta","recordCount":3,"seq":4471,"spec":"ohe.wire/1","specVersion":"1.0","types":["heart_rate","step_count"]}
{"batchSeq":4471,"end":"2026-03-29T00:47:00.000Z","hkIdentifier":"HKQuantityTypeIdentifierHeartRate","kind":"sample.quantity","metricId":"heart_rate","observedAt":"2026-03-29T09:00:03.000Z","semantics":"curated","source":{"bundleId":"com.apple.health","name":"Apple Watch"},"start":"2026-03-29T00:47:00.000Z","tzOffsetMinutes":null,"tzSource":"unknown","unit":"bpm","uuid":"3f2a91c4-8d0e-4b77-9a15-2c6e4f8b0d31","v":1,"value":52}
{"batchSeq":4471,"bestEffort":true,"hkIdentifier":"HKQuantityTypeIdentifierStepCount","kind":"tombstone","metricId":"step_count","observedAt":"2026-03-29T09:00:03.000Z","reason":"healthKitDeleted","uuid":"a7d4e2b9-1c3f-4e88-b0aa-55d1e9c7f204","v":1}
{"batchId":"0192f3c1-...","complete":true,"contentDigest":"sha256:9f2c...","counts":{"sample.quantity":1,"tombstone":1},"kind":"batch.footer"}
```

Note in that example: the heart-rate sample carries `tzOffsetMinutes: null` and
`tzSource: "unknown"`. That is the honest, common case for a quantity sample and the format makes it
visible rather than fabricating `+01:00`.

### JSON — single document, for HTTP bodies

- Media type `application/json; profile="ohe.wire/1"`.
- Exactly the same records, in exactly the same order, wrapped:

```json
{
  "footer": { "batchId": "0192f3c1-…", "complete": true, "contentDigest": "sha256:9f2c…", "counts": { "sample.quantity": 1, "tombstone": 1 }, "kind": "batch.footer" },
  "header": { "batchId": "0192f3c1-…", "kind": "batch.header", "spec": "ohe.wire/1", "…": "…" },
  "records": [ { "…": "…" } ]
}
```

- The wrapper object is itself JCS-canonical, so `footer` sorts before `header` before `records`.
  Aesthetically odd; mechanically it means one canonicaliser serves both encodings.
- `contentDigest` is computed over the **NDJSON rendering** of `records`, not over the JSON document.
  One digest definition, encoding-independent — so a batch delivered as JSON over HTTP and archived
  as NDJSON to a file has the same digest, which is what makes cross-encoding fixture assertions
  possible.
- A `pretty` variant (2-space indent, one member per line, same member order) is defined and is also
  byte-deterministic. It is for human inspection and for the R-31 dry-run payload preview. It is not
  the canonical form and `contentDigest` is never computed over it.
- Hard bound: a JSON document is one batch. Never the whole store. This is the memory bomb AR flagged
  and NFR-05 forbids.

### CSV — flat and lossy, and the specification says so

RFC 4180: UTF-8 without BOM, `CRLF` line terminators, `"` quoting with `""` escaping, header row
always present with the exact frozen column list, `.` decimal separator, no digit grouping,
timestamps in the same RFC 3339 UTC form as JSON.

**One file per record kind**, not one flat table. Files are named
`ohe1-<kind>-<windowStart>-<windowEnd>.csv`, e.g. `ohe1-quantity-20260301-20260331.csv`, alongside a
`_meta.json` sidecar containing the batch header and footer verbatim.

| File | Columns |
|---|---|
| `ohe1-quantity` | `uuid, metricId, hkIdentifier, semantics, startUtc, endUtc, tzOffsetMinutes, tzId, tzSource, value, unit, count, sourceName, sourceBundleId, deviceName, wasUserEntered, quality, observedAt, exporterId, batchSeq` |
| `ohe1-category` | as above, with `categoryValue, categoryName, durationSeconds` replacing `value, unit, count` |
| `ohe1-aggregate` | `bucketKey, metricId, hkIdentifier, statistic, computation, sourceScope, sourceName, granularity, bucketStartUtc, bucketEndUtc, bucketDurationSeconds, tzId, localStart, value, unit, sampleCount, state, emitSeq, computedAt, exporterId` |
| `ohe1-tombstone` | `uuid, targetKind, metricId, hkIdentifier, reason, bestEffort, observedAt, exporterId, batchSeq` |
| `ohe1-workout` | `uuid, activityType, activityTypeRaw, startUtc, endUtc, tzOffsetMinutes, tzId, tzSource, durationSeconds, isIndoor, hasRoute, seriesIncluded, observedAt, exporterId, batchSeq` |
| `ohe1-workout-totals` | `workoutUuid, metricId, statistic, value, unit` |
| `ohe1-workout-route` | `workoutUuid, pointIndex, tUtc, lat, lon, altitudeM, horizontalAccuracyM, verticalAccuracyM, speedMps, courseDeg` |
| `ohe1-workout-series` | `workoutUuid, metricId, pointIndex, tUtc, value, unit` |
| `ohe1-ecg` | `uuid, startUtc, endUtc, classification, averageHeartRate, samplingHz, voltageCount, symptomsStatus, sourceName, observedAt` |
| `ohe1-ecg-voltage` | `ecgUuid, pointIndex, voltageUv` |
| `ohe1-correlation` | `uuid, correlationType, startUtc, endUtc, componentUuid, componentMetricId, value, unit` (one row per component) |
| `ohe1-state-of-mind` | `uuid, startUtc, endUtc, kindOfEntry, valence, valenceClassification, labels, associations, observedAt` |
| `ohe1-characteristic` | `exporterId, characteristicId, value, reidentifying, observedAt` |

**What CSV consumers lose — stated plainly:**

1. **Convergence.** This is the big one. A consumer who loads `ohe1-quantity` and ignores
   `ohe1-tombstone` will accumulate records the user deleted, forever, and will never know. CSV is
   therefore declared a **non-convergent encoding**: it can represent a correct snapshot but cannot
   represent correct incremental state unless the consumer explicitly joins the tombstone file. The
   spec says this; the app must say it too, in the destination-configuration UI.
2. **Nesting.** Every parent/child relationship becomes a foreign-key join the consumer must perform.
   Open `ohe1-workout.csv` in Numbers and the route is simply not there.
3. **`metadata`.** The opaque HealthKit metadata map is **dropped entirely**, not JSON-encoded into a
   cell. Reason: a JSON blob in a CSV cell is neither readable by a spreadsheet user nor reliably
   parseable by a naive reader, and quoting it correctly across dialects is a known interop hazard. A
   `metadataDropped` boolean column is **not** added either — it would be true on nearly every row
   and carry no information. The loss is documented once, here, and in `_meta.json` as
   `"csvDropsMetadata": true`.
4. **Array fields.** `labels`, `associations` and `seriesIncluded` are joined with `;` and sorted.
   Individual members may themselves never contain `;` — enforced by the catalogue.
5. **Null versus absent.** CSV has one empty cell for both. `tzOffsetMinutes` empty means "unknown";
   so does an absent `tzId`. The distinction our JSON preserves is gone.
6. **Version detection.** No in-band `spec` field per row. Version is signalled by the filename
   prefix `ohe1-` **and** by the exact header row, both of which are frozen for the life of v1. This
   is weaker than JSON's `spec` field and it is the reason CSV is not a supported input to the
   conformance suite's receiver tests.
7. **Batch identity.** `batchSeq` and `exporterId` are carried per row, but `batchId` is not — it
   lives only in `_meta.json`. So a CSV pipeline cannot implement delivery idempotency; it must rely
   on UUID upsert alone. That is sufficient for correctness and is the reason `uuid` is the first
   column of every sample file.

Numbers, dates and booleans are rendered identically to JSON (`true`/`false` lowercase, no locale),
so a `de_DE` device and an `en_US` device produce byte-identical CSV (AR-11's acceptance test).

---

## Aggregation records and bucket key construction

AR-10's finding is that aggregation is what users actually configure and that an aggregate bucket is
idempotent *by construction* — recompute and overwrite by key — where raw samples need UUID upsert
plus tombstones. R-06 promotes it to a first-class mode. The whole value of that depends on the key
being composed identically by every producer and every consumer, so the key is rendered by us and
declared opaque to them.

### Key composition (frozen for v1)

```
bucketKey = metricId
          | statistic
          | granularity
          | bucketStart (RFC 3339 UTC, 3 fractional digits)
          | tzId
          | sourceScope [ ":" sourceName ]
```

joined by U+007C `|`. Any `|` or `\` occurring inside a component is backslash-escaped. `sourceName`
is included **only** when `sourceScope` is `single`.

```
step_count|sum|P1D|2026-03-28T23:00:00.000Z|Europe/Berlin|all
heart_rate|mean|PT1H|2026-03-29T08:00:00.000Z|Europe/Berlin|single:Apple Watch
```

**What is deliberately *not* in the key:**

- **`exporterId`.** Including it would mean a user replacing their phone silently forks every bucket
  into a parallel series, and a designated-exporter change (AR-15) would produce two competing rows
  per day forever. Excluding it means the bucket converges across devices — at the cost that two
  *concurrently active* exporters writing aggregates to one sink will overwrite each other. That case
  is unsupported by design (AR-15: one designated exporter per destination), the app must prevent it,
  and the spec states the consequence rather than pretending the key solves it. `exporterId` is
  carried as an ordinary field for attribution.
- **`computedAt`.** Timestamps must never appear in idempotency keys (AR-13's "do not use timestamps
  in idempotency keys"). A recomputed bucket must produce the *same* key, which is the entire point.
- **`value`.** Obviously — a content-derived key would make every recomputation a new row.

### Bucket boundaries

Buckets are **half-open intervals `[bucketStart, bucketEnd)` on the UTC timeline**, whose boundaries
are computed by applying the `tzId` calendar. `PT*` granularities align to the UTC clock;
`P1D`/`P1W`/`P1M` align to local midnight in `tzId`. `P1W` starts on Monday (ISO 8601), not on the
locale's first day of week — a locale-dependent week boundary would break AR-11.

`tzId` is the **user-selected zone for the export configuration** (AR-09), not the device's current
zone and not the sample's zone. It is required, not optional: there is no such thing as a daily
bucket without a stated zone, and making it optional would invite implementers to default to UTC and
then explain to users why their step count resets at 01:00.

**DST.** A `P1D` bucket in `Europe/Berlin` on 2026-03-29 runs from `2026-03-28T23:00:00Z` to
`2026-03-29T22:00:00Z` — 82,800 seconds. The record carries `bucketDurationSeconds: 82800`, so a
consumer computing a rate (steps per hour) gets it right without knowing anything about DST. On the
fall-back day the value is 90,000. A sample landing in the repeated local hour is placed by UTC
interval containment and is therefore unambiguous.

**Time zone change mid-window.** If the user changes the configured `tzId`, previously emitted
buckets are **not** recomputed and not deleted. New buckets carry the new `tzId` and therefore a new
`bucketKey`. The old series simply ends. This is honest and it is visible; the alternative
(retroactive recomputation) would rewrite history and is forbidden.

### Bucket state, revision and partial buckets

| `state` | Meaning | Emitted when |
|---|---|---|
| `open` | `bucketEnd` is in the future, or the reconciliation window for this bucket has not closed. The value is a running partial | Same-day / same-hour export |
| `final` | The bucket is closed and, as far as we know, complete | `bucketEnd` has passed **and** the trailing reconciliation window (R-08, default 7 days) has passed |
| `revised` | A previously emitted bucket has been recomputed because a newly observed sample fell into it | R-01 / MA-01 — the wedge |

`state: "revised"` is the field that makes MA-01 observable. The incumbent's defect is that a
retroactively inserted sample never causes the historical day to be re-emitted; the fix is
worth nothing downstream unless the re-emission is distinguishable from a duplicate, which is what
`revised` plus an incremented `emitSeq` provides.

A `final` bucket may still be revised later. `final` means "we believe this is complete", never "this
will never change" — HealthKit gives us no basis for the second claim, and the format should not let
us make it.

**Convergence rule (receiver side):** for a given `bucketKey`, accept the incoming record if
`emitSeq >= stored.emitSeq`, else discard. Since `emitSeq` is monotonic per `exporterId` and
`exporterId` is not in the key, a receiver comparing across exporters is comparing incomparable
counters — which is exactly the unsupported two-exporter case above, and the receiver contract says
to log it rather than silently pick a winner.

### Statistics are not the sum of samples (R-07 / AR-30)

HealthKit's statistics queries de-duplicate overlapping data from multiple sources; naively summing
raw samples double-counts an iPhone and a Watch both counting steps. Two exports of the same metric —
one `samples`, one `aggregates` — will legitimately disagree, and users will file it as a bug.

The format's answer is the `computation` field. `hkStatisticsCollectionQuery` means Apple computed
it, multi-source de-duplicated, and the number will match the Health app. `localSampleFold` means we
folded the samples ourselves — necessary for metrics where no statistics query applies — and the
number may exceed the Health app's for a multi-source metric. Naming the mechanism per record is the
only way a user with a spreadsheet can settle the argument, and it is why `computation` is required
and not merely `statistic`.

The metric catalogue declares, per metric, `kind` (`cumulative` | `discrete` | `categorical` |
`structured`), the `allowedStatistics` set and the `defaultStatistic`. Requesting `sum` on a discrete
metric (a mean heart rate summed over a day) is a catalogue error, and the encoder rejects it rather
than emitting a nonsense number.

---

## Identity, idempotency and determinism

These are three different properties. Conflating them is the error the Stage 1 review caught, and it
is worth being blunt about what each one is *for*.

| | **Record identity** | **Delivery idempotency** | **Byte determinism** |
|---|---|---|---|
| Field | `uuid` (and `bucketKey` for aggregates) | `batchId` | none — a property of the encoder |
| Scope | One health record, forever | One transmission of one batch | One encoder invocation |
| Question answered | "Which health record is this?" | "Have I already processed this transmission?" | "Does the same input produce the same bytes?" |
| Source | `HKObject.uuid` — Apple's | UUIDv7 minted at enqueue — ours | RFC 8785 + declared ordering + injected clock |
| Stable across | Re-export, replay, reinstall, device change | Retries of the same batch. **Not** across recomputation | Machines, locales, OS versions, runs |
| Requirement | R-02, AR-05 | R-03, QA-16 | R-84, QA |
| Failure if absent | Duplicates or corruption at the sink | Wasted work; no correctness loss | Untestable output; unusable fixtures |

### How they relate

**Identity is sufficient for correctness. Idempotency is an optimisation. Determinism is a testing
property.** That ranking matters: if a receiver implements only upsert-by-UUID and ignores
`batchId` entirely, it is still correct. If it implements only `batchId` deduplication and appends
by row, it is broken. The conformance suite tests them in that order.

The relationship to R-03 is precise: we deliver at-least-once. Duplicate delivery is *expected*, not
exceptional (AR-03 makes duplicates permitted and gaps forbidden, deliberately asymmetric).
Convergence therefore has to come from identity, because `batchId` deduplication only helps for the
subset of duplicates that are literal retransmissions of the same batch — and the reconciliation
sweep (R-08) generates duplicates that are *not* retransmissions.

### Four errors to avoid, stated so a reviewer can check for them

1. **Using `contentDigest` as an idempotency key.** Two recomputed batches with identical content are
   legitimately distinct deliveries, and one delivery retried after a partial write must be
   re-processed. `contentDigest` detects truncation and corruption; that is all it is for.
2. **Deriving `batchId` from content.** Same failure from the other direction, plus it makes delivery
   identity depend on the serialiser, which drags an unrelated concern (determinism) into the
   delivery path.
3. **Assuming byte-equal output means "already sent".** Determinism is over *encoder inputs*, and
   `batchId`/`emittedAt`/`seq` are inputs. Two batches that are byte-equal are, by construction, the
   same batch. Two batches carrying the same samples are *not* byte-equal, because `seq` differs.
   Getting this backwards produces an exporter that silently skips a re-export after a queue eviction
   (R-09) — the exact scenario the gap record exists for.
4. **Assuming different bytes for the same `uuid` means the record changed.** It does not. Metadata
   may have been re-read, a device name may have been resolved, `observedAt` differs. The receiver
   upserts by `uuid` and takes the latest arrival; it must not diff payloads to decide whether to
   write.

### The determinism contract, precisely

Given: an identical ordered set of logical records, an identical metric catalogue version, an
identical destination configuration, and identical injected values for `batchId`, `seq`,
`exporterId`, `emittedAt`, `observedAt` and `computedAt` — the encoder produces byte-identical
output, on any machine, under any locale, on any supported OS version, in any of the three encodings.

That is the testable statement. It requires R-81's injected clock/calendar/locale, RFC 8785, the
declared record ordering, and the fixed timestamp precision. It does **not** require, and must not be
read as requiring, that two *runs of the app* over the same HealthKit store produce identical bytes —
they will not, because `seq`, `batchId` and `observedAt` legitimately differ. Writing the R-84 test
against the app rather than against the encoder would produce a test that can only be made to pass by
faking those fields, which would destroy the delivery-idempotency property. This is the concrete way
these three properties break each other when confused, so both the spec and the QA plan should say it.

---

## Versioning and stability policy

R-12: *"The export wire format is a versioned specification with its own stability commitment,
independent of the app's release cycle. Verify: spec plus machine-readable fixtures in-repo; CI fails
on a breaking change to a frozen version."*

### What "frozen v1" means

At first public release, `ohe.wire/1` is frozen. For the entire life of major version 1:

**Forbidden (breaking):**

| # | Change |
|---|---|
| B1 | Removing any field |
| B2 | Renaming any field |
| B3 | Changing a field's JSON type |
| B4 | Changing a field's canonical unit |
| B5 | Changing a field's semantics, including its null/absent distinction |
| B6 | Making an optional field required |
| B7 | Removing a member from any enum, open or closed |
| B8 | Adding a member to a **closed** enum |
| B9 | Changing the composition or escaping of `bucketKey` |
| B10 | Changing the canonical form, the record ordering, or timestamp precision |
| B11 | Changing a `metricId`, or a metric's declared `kind` or `canonicalUnit` |
| B12 | Changing the CSV column list or column order of any file |
| B13 | Tightening any validation rule |

**Permitted (additive):**

| # | Change |
|---|---|
| A1 | Adding a new optional field to an existing record kind |
| A2 | Adding a member to an **open** enum |
| A3 | Adding a new record kind |
| A4 | Adding a new `metricId` |
| A5 | Adding a new CSV file (never a column to an existing one) |
| A6 | Loosening a validation rule |
| A7 | Marking a field `deprecated` in the documentation. It continues to be emitted for all of v1 |

Additive changes increment MINOR (`1.0` → `1.1`). Records still say `v: 1`; the header still says
`spec: "ohe.wire/1"`. A v1.0 receiver reading a v1.3 payload must work, which is precisely what
gate 3 below tests.

### Open and closed enums

This is the mechanism that makes additive evolution possible, and it must be declared per enum
rather than assumed.

- **Closed** — the member set is frozen for the major. A receiver MAY reject an unknown member.
  Closed in v1: `kind`, `tzSource`, `semantics`, `reason` (batch), `reason` (tombstone), `mode`,
  `state`, `statistic`, `computation`, `sourceScope`, `granularity`, `outcome`, `trigger`,
  `kindOfEntry`, `characteristicId`, `quality`.
- **Open** — new members will be added within the major, typically because Apple added something. A
  receiver MUST tolerate an unknown member: store the string, do not crash, do not drop the record.
  Open in v1: `metricId`, `hkIdentifier`, `categoryName`, `activityType`, `correlationType`,
  `classification`, `valenceClassification`, `labels`, `associations`, `errorClass`, workout
  `events[].type`, medication `status`, `symptomsStatus`.

Every open-enum field is paired with a raw fallback where HealthKit provides one — `categoryValue`
alongside `categoryName`, `activityTypeRaw` alongside `activityType`, `hkIdentifier` alongside
`metricId` — so an unknown member never costs the receiver the underlying datum. That pairing is the
reason the taxonomy can be a community backlog (AR-24) without the wire format churning.

### Version negotiation and detection

| Transport | Mechanism |
|---|---|
| HTTPS | Producer sends `Content-Type: application/x-ndjson; profile="ohe.wire/1"`. A receiver MAY advertise support via `Accept: application/x-ndjson; profile="ohe.wire/1", application/json; profile="ohe.wire/1"` in a response to the R-31 canary handshake. **We do not implement content negotiation** — the version is chosen per destination in configuration and the header is a declaration, not a negotiation |
| MQTT | No negotiation exists. Version is in-band in the `batch.header` record, and additionally in the topic when the user opts into the versioned topic layout (`<base>/v1/...`) |
| File | In-band `spec` in line 1 |
| CSV | Filename prefix `ohe1-` plus the exact frozen header row, plus `_meta.json` |

The honest position: real negotiation is not achievable against a webhook, a file or a broker, so the
mechanism that actually matters is **per-destination version selection in configuration** plus an
in-band declaration. AR-07's commitment stands: any major remains selectable for at least 12 months
after its successor ships. Given R-12's "independent of the app's release cycle", I recommend
strengthening that to: **v1 remains emittable for at least 24 months after v2 ships, and the v1
specification document, JSON Schemas and fixtures remain in the repository permanently, including
after the project is archived.** That last clause is the R-12 / RK-1 insurance policy in concrete
form and costs nothing.

### Deprecation policy

1. A field is marked `deprecated` in the schema annotations and in this document, with a stated
   reason and a stated replacement.
2. It continues to be emitted, unchanged, for the entire life of the major version.
3. Its removal is announced in `CHANGELOG-wire.md` at the time of deprecation, with the earliest
   major version in which removal may occur.
4. Removal happens only at a major version boundary.

There is no deprecation path that shortens the life of a field within a major. That is the point of
freezing.

### CI enforcement — R-12's acceptance criterion

Four required checks, all of which must pass on a fork PR with no secrets and no self-hosted runner
(R-85), and all of which run on Linux with HealthKit unlinked (R-80).

| Gate | What it does | Fails on |
|---|---|---|
| **G1 — Fixture reproduction** | For every frozen fixture, run the current encoder over the committed logical input with the committed injected clock/ids, and byte-compare against the committed `.ndjson`, `.json` and `.csv` outputs | Any byte difference. This is simultaneously the R-84 determinism test and the frozen-format test |
| **G2 — Schema diff** | Structurally diff the current JSON Schema for `ohe.wire/1` against the schema committed at the freeze tag; classify each change against the B*/A* tables above | Any B-class change. Any A-class change without a MINOR bump |
| **G3 — Forward compatibility** | Run the *reference receiver pinned at v1.0* against fixtures produced by the *current* encoder | Any parse or ingest error. This is what proves additive changes really are additive |
| **G4 — Receiver conformance** | Run the current reference receiver against the adversarial fixture sequences and assert final state | Any divergence from `expected-state.json` |

G1 and G2 together are the direct implementation of R-12's "CI fails on a breaking change to a frozen
version". G3 is the one that catches the subtle case where a change is technically additive but
breaks a strict receiver — for example adding a member to an enum we forgot to declare open.

Committed at the freeze tag and never regenerated: `schema/ohe.wire/1/*.schema.json`,
`fixtures/ohe.wire/1/**`, `catalogue/ohe.wire/1/metrics.json`.

---

## Health Auto Export compatibility profile

MA-03 and MA-09 make the case: the incumbent's moat is not its app, it is roughly a dozen independent
receivers that already speak its JSON — `apple-health-ingester`, `health-auto-export-server`,
`hae-vault`, Klebb, HealthLog and others. Emitting a compatible payload starts our ecosystem at
parity instead of zero, for about 1.5 EW.

I researched the actual shape from HealthyApps' Help Center (the maintainer explicitly redirected the
GitHub wiki there in March 2026) and, more usefully, from the Go type definitions in
`apple-health-ingester`, which is the de facto reference implementation that third parties copy.

### Their shape (as documented, September 2026)

**Envelope.** A single JSON object, one array per data type:

```json
{
  "data": {
    "metrics": [], "workouts": [], "stateOfMind": [], "medications": [],
    "symptoms": [], "cycleTracking": [], "ecg": [], "heartRateNotifications": []
  }
}
```

**Metrics.** Metric names are `snake_case` renderings of the *UI label*, not of the HealthKit
identifier — `walking_running_distance`, `active_energy`, `weight_&_body_mass` (yes, with an
ampersand). Structure:

```json
{ "name": "step_count", "units": "count",
  "data": [ { "qty": 8500, "date": "2024-02-06 14:30:00 -0800", "source": "iPhone" } ] }
```

Several metrics have bespoke datapoint shapes: `blood_pressure` uses `systolic`/`diastolic`;
`heart_rate` uses capitalised `Min`/`Avg`/`Max`; `blood_glucose` adds `mealTime`;
`insulin_delivery` adds `reason`; `sexual_activity` uses three counting fields keyed by
human-readable strings including spaces (`"Protection Used"`).

**Sleep** has two mutually incompatible datapoint shapes under the same metric name, selected by an
app-side "Summarize Data" toggle that is not signalled in the payload. `apple-health-ingester` has to
*probe* — try `SleepAnalysis`, check whether `startDate`/`endDate` came out non-zero, fall back to
`AggregatedSleepAnalysis`, fall back again to a generic datapoint. Their aggregated shape also
changed field names at HAE v6.6.2 (`sleepSource`/`inBedSource` → `source`, plus new
`awake`/`core`/`deep`/`rem`) with no version marker.

**Timestamps** are `yyyy-MM-dd HH:mm:ss Z`, e.g. `2024-02-06 14:30:00 -0800`. Crucially this is
**locale-dependent**: `apple-health-ingester` carries five parse formats, because if the device's
*General → Date & Time → 24-Hour Time* setting is off the app emits `3:04:05 PM -0700`, and recent
iOS versions insert a **narrow no-break space (U+202F)** before the meridiem. `stateOfMind`, alone
among the record types, uses ISO 8601 `Z` instead.

**Workouts v2** carry `id` (a UUID string), `name`, `start`, `end`, `duration`, plus a large set of
optional `{qty, units}` objects and time-series arrays, plus a rich `route` array. Workouts v1 is a
different, simpler shape, selected by an app-side toggle, again not signalled in the payload.

**ECG** carries `start`, `end`, `classification`, `severity`, `averageHeartRate`,
`numberOfVoltageMeasurements`, `samplingFrequency`, `source`, and a `voltageMeasurements` array of
per-point `{date, voltage, units}` objects — roughly 15,360 timestamped objects for a 30-second
reading.

**Units follow the user's display preferences** — `mi` or `km`, `kcal` or `kJ`, `degF` or `degC` —
so the same metric changes unit between two users, and between one user before and after they change
a setting.

**Delivery metadata** is HTTP headers only: `automation-name`, `automation-id`,
`automation-aggregation`, `automation-period`, `session-id`, plus an optional `?target=NAME` query
parameter that receivers use as the person/device tag.

### Our compatibility profile

**Scope: emit-only, `metrics` and `workouts`, best-effort, explicitly lossy.** Configured
per-destination. Never the default. Requires an in-product acknowledgement of the loss before it can
be enabled (see Open Question 1).

| Decision | Choice | Reason |
|---|---|---|
| Envelope | Exact match: `{"data":{"metrics":[…],"workouts":[…]}}` | Non-negotiable; every receiver keys on it |
| Timestamp form | **Always** the 24-hour form with an ordinary space: `2026-03-29 01:47:00 +0100` | It is the intersection of all five formats every known receiver parses. We never emit the 12-hour or U+202F variants, so we are strictly easier to parse than the incumbent |
| Timestamp zone | Rendered in the configured export `tzId`, not UTC | Their format has no UTC convention and receivers bucket by the emitted local date |
| Workout version | v2 | v1 is legacy; v2 carries `id`, which is the only identity anywhere in their model |
| Sleep shape | Chosen by our aggregation mode and **declared in the destination UI**, matching whichever shape the user's receiver expects | We cannot signal it in the payload — their format has nowhere to put it |
| Units | Canonical by default, with an optional per-destination `unitProfile: canonical \| haeImperial \| haeMetric` | Existing dashboards may hard-code `mi`. Config is deterministic, so this does not compromise R-84 |
| Metric names | Hand-maintained mapping table, `metricId → haeName`, with a coverage matrix and a drift test | Their vocabulary is UI-label-derived and not derivable programmatically |
| Headers | We send `session-id` (= our `batchId`) and `automation-name` | Free compatibility; costs nothing |
| Tombstones | **Not emitted** | No representation exists |
| Conformance | The receiver contract **does not apply** to this profile | We must not claim R-02/R-05 hold on it |

### The fidelity loss, stated plainly

| Our concept | HAE representation | Loss | Consequence |
|---|---|---|---|
| `uuid` on every sample (R-02) | **None.** Metric datapoints have no identifier field of any kind | **Total** | Receivers key on `(metric, date[, source])`. Two samples at the same instant from the same source collide. Upsert-by-UUID is impossible; the sink converges only by natural-key luck |
| `tombstone` stream (R-05) | **None.** No deletion is expressible | **Total** | A deleted sample stays in the sink forever. The user's archive diverges from Apple Health and nothing detects it. This is the single largest loss |
| `computation` per aggregate (R-07) | None. `Min`/`Avg`/`Max` appear with no statement of method or window | **Total** | The R-07 claim cannot be made on this profile |
| `tzId` + `tzSource` (R-10) | Numeric offset only, embedded in the timestamp string | **Severe** | Our honest `tzSource: "unknown"` becomes an unlabelled offset. Historical local time is silently fabricated at the boundary |
| `spec` / `specVersion` (R-12) | None in-band. Version is an app-side toggle | **Total** | A receiver must sniff. Their own sleep shape changed at v6.6.2 with no marker; ours would too |
| `observedAt` (MA-01/AR-14) | None | **Total** | Late-arriving data is indistinguishable from new data downstream |
| `batchId` / idempotency (R-03) | `session-id` header, per request, not documented as stable across retries | **Severe** | No delivery idempotency. Combined with no UUID, replay safety rests entirely on the receiver's own natural-key dedup |
| `seq` monotonic counter (AR-14) | None | **Total** | Receivers cannot detect out-of-order or replayed deliveries |
| `exporterId` (AR-15) | `?target=` query param, user-typed free text | **Partial** | Workable, but not stable and not machine-generated |
| Canonical units (R-10/AR-11) | User-preference-dependent | **Severe** | Same metric, different unit, same user, different day. Mitigated by our `unitProfile: canonical` default |
| `bucketKey` / `state` / `revision` (R-06) | None | **Total** | A recomputed daily bucket is just another datapoint at the same date. Convergence depends entirely on the receiver's natural-key upsert |
| `quality`, `complete`, `contentDigest` | None | **Total** | A truncated payload is undetectable |
| Structured `metadata` | Absent for metrics; `metadata` object exists on workouts v2 | **Near-total** | |
| `null` vs absent | Fields simply omitted | **Total** | |
| `sample.correlation` pairing | `blood_pressure` datapoint pairs systolic/diastolic; nothing else pairs | **Partial** | Food correlations lost |
| ECG voltage encoding | Per-point timestamped objects | **Fidelity kept, size lost** | ~8× larger; a 30-second ECG is ~15,360 objects |
| `characteristic` | None | **Total** | Not a real loss — arguably a feature (HK-30) |

**The honest summary for the PM:** the compatibility profile buys ecosystem reach and buys nothing
else. It cannot carry the correctness wedge, because the two properties the wedge rests on — UUID
identity and deletion — have no representation in the target model. It should therefore be positioned
as *"speak to your existing dashboard"*, never as *"a supported way to hold a correct archive"*, and
the destination-configuration UI should say which of the two the user is choosing. A user who
configures only an HAE-profile destination and believes they have a complete, convergent copy of
their health record has been misled by us, and that is the failure mode this project exists to
eliminate.

**Maintenance liability.** This is someone else's undocumented, drift-prone product surface — their
own sleep shape changed field names mid-version and their own docs redirect twice. AR-25's
verification (round-trip through a real receiver) must run in CI as a nightly against pinned
container images of `apple-health-ingester` and `hae-vault`, not as a one-off at implementation time.

---

## Home Assistant mapping

R-89 exists because Home Assistant's long-term statistics **silently do nothing** without
`state_class`. A silent failure in the primary persona's primary destination, in the product built to
eliminate silent failure, is the most embarrassing bug available to us — so the mapping is part of
the wire specification's catalogue, not part of the integration code.

### The rules that actually bite

1. **No `state_class` ⇒ no long-term statistics, silently.** The entity works, the history graph
   works, and nothing is recorded in the statistics tables. Nothing warns.
2. **`state_class: measurement` is invalid for device classes `date`, `enum`, `energy`, `gas`,
   `monetary`, `timestamp`, `volume` and `water`.** So `device_class: energy` + `measurement` — the
   obvious-looking choice for "calories burned" — produces no statistics. Active energy must use
   `total` or `total_increasing`.
3. **A wrong `device_class` breaks unit validation.** Home Assistant validates the unit against the
   device class's accepted set. Assigning `device_class: humidity` to SpO₂ because both are `%` makes
   the entity error out or, worse, be silently converted.
4. **Many health units have no device class at all.** Heart rate, SpO₂, respiratory rate, VO₂max,
   HRV, step count. The correct value is `null`, and the catalogue records `null` explicitly so the
   absence is a decision rather than an omission.
5. **`unit_of_measurement` must never change for an existing entity.** Home Assistant drops or
   refuses statistics on a unit change. The catalogue's HA unit is therefore frozen alongside the
   canonical wire unit under the B4/B11 rules above.
6. **`device_class: enum` requires an `options` list and forbids `state_class`.**

### Catalogue mapping (curated set — the R-61 first-run ~24 plus close relatives)

| `metricId` | Canonical wire unit | HA `unit_of_measurement` | HA `device_class` | HA `state_class` | Notes |
|---|---|---|---|---|---|
| `step_count` | `count` | `steps` | `null` | `total_increasing` (running daily) / `total` + `last_reset` (closed bucket) | No device class exists |
| `walking_running_distance` | `km` | `km` | `distance` | `total_increasing` | HA converts to `mi` for imperial users |
| `cycling_distance` | `km` | `km` | `distance` | `total_increasing` | |
| `flights_climbed` | `count` | `flights` | `null` | `total_increasing` | |
| `active_energy` | `kcal` | `kcal` | `energy` | `total_increasing` | **Never `measurement`** — see rule 2. Appears in the Energy dashboard; see Open Question 6 |
| `basal_energy` | `kcal` | `kcal` | `energy` | `total_increasing` | |
| `exercise_time` | `min` | `min` | `duration` | `total_increasing` | |
| `stand_time` | `min` | `min` | `duration` | `total_increasing` | `apple_stand_hour` is a category type and maps to a separate `enum` entity |
| `heart_rate` | `bpm` | `bpm` | `null` | `measurement` | No device class |
| `resting_heart_rate` | `bpm` | `bpm` | `null` | `measurement` | |
| `walking_heart_rate_average` | `bpm` | `bpm` | `null` | `measurement` | |
| `heart_rate_variability_sdnn` | `ms` | `ms` | `duration` | `measurement` | `duration` accepts `ms`; semantically defensible |
| `vo2_max` | `mL/(kg·min)` | `mL/(kg·min)` | `null` | `measurement` | |
| `respiratory_rate` | `count/min` | `breaths/min` | `null` | `measurement` | `frequency` is Hz-based — wrong |
| `oxygen_saturation` | `%` | `%` | `null` | `measurement` | **Not** `humidity` or `battery` |
| `body_temperature` | `degC` | `°C` | `temperature` | `measurement` | HA converts to `°F` for imperial users |
| `basal_body_temperature` | `degC` | `°C` | `temperature` | `measurement` | |
| `blood_pressure_systolic` | `mmHg` | `mmHg` | `null` (recommended) | `measurement` | `pressure` accepts `mmHg` but exposes the entity to the user's pressure-unit preference (hPa). Settle empirically in R-89 |
| `blood_pressure_diastolic` | `mmHg` | `mmHg` | `null` (recommended) | `measurement` | |
| `blood_glucose` | `mg/dL` | `mg/dL` | `blood_glucose_concentration` | `measurement` | HA has a real class for this; it converts to `mmol/L` correctly |
| `body_mass` | `kg` | `kg` | `weight` | `measurement` | |
| `lean_body_mass` | `kg` | `kg` | `weight` | `measurement` | |
| `body_fat_percentage` | `%` | `%` | `null` | `measurement` | |
| `body_mass_index` | `count` | `null` | `null` | `measurement` | Dimensionless; omit the unit entirely |
| `height` | `m` | `cm` | `distance` | `measurement` | |
| `dietary_water` | `mL` | `mL` | `volume` | `total_increasing` | `volume` + `measurement` is invalid (rule 2) |
| `mindful_minutes` | `min` | `min` | `duration` | `total_increasing` | |
| `sleep_asleep_total` | `h` | `h` | `duration` | `total` + `last_reset` = `bucketStart` | Per-night bucket |
| `sleep_deep` / `sleep_core` / `sleep_rem` / `sleep_awake` | `h` | `h` | `duration` | `total` + `last_reset` | |
| `sleep_stage_current` | — | — | `enum` | **none** | `options` = the 7 `HKCategoryValueSleepAnalysis` names. `state_class` is forbidden with `enum` |
| `environmental_audio_exposure` | `dBASPL` | `dBA` | `sound_pressure` | `measurement` | HA's `sound_pressure` accepts only `dB` and `dBA`; HealthKit's unit is A-weighted, so `dBA` |
| `last_successful_export` | — | — | `timestamp` | **none** | R-27's signal. Must be an RFC 3339 string HA can parse to an aware datetime |
| `time_since_last_success` | `s` | `s` | `duration` | `measurement` | The alertable form of R-27 |
| *(passthrough, `semantics: "unmapped"`)* | raw HK unit | raw | `null` | **none** | No `state_class`, deliberately. We will not guess statistics semantics for a type we have not curated, and a wrong guess produces silently wrong long-term statistics — worse than none |

The `state_class` choice for cumulative daily metrics depends on what we push, and the catalogue
declares both because both modes exist:

- **Running daily total** (`state: "open"` aggregate, value grows through the day, resets at local
  midnight) → `total_increasing`. HA interprets a decrease as a new meter cycle, which is exactly
  right for a midnight reset.
- **Closed daily bucket** (`state: "final"`, one value stamped at bucket end) → `total` with
  `last_reset` set to `bucketStart`. This is HA's documented pattern for a value that resets per
  period.
- **Raw samples pushed as they arrive** → not suitable for cumulative metrics at all. Push aggregates.
  The catalogue marks cumulative metrics as `haRequiresAggregate: true` and the Home Assistant
  destination refuses to enable a raw-sample export of them, with an explanation. That refusal is the
  R-89 lesson encoded as a product behaviour rather than a documentation note.

### MQTT discovery payload generation

D-04 puts MQTT in v1. Home Assistant over MQTT is the better path than the REST preset, for a reason
worth stating: entities created by `POST /api/states/<entity_id>` are not backed by a config entry
and are not restored across a Home Assistant restart, whereas retained MQTT discovery messages
recreate the entities automatically. R-89's contract test should confirm this on both pinned HA
versions before we recommend one over the other in the docs.

**Topic layout.**

```
<base>/v1/status                                  (availability)
<base>/v1/state/<metricId>/<statistic>/<granularity>   (state)
homeassistant/device/<exporterId>/config          (discovery, retained)
```

**Discovery.** Use HA's device-based discovery so one retained message declares every enabled entity
and they group under a single device. One `components` entry per enabled
`(metricId, statistic, granularity)`:

```json
{
  "dev": { "identifiers": ["ohe_6b1c2d3e"], "name": "iPhone Health Export",
           "manufacturer": "open-health-exporter", "model": "iPhone", "sw_version": "1.0.0" },
  "o":   { "name": "open-health-exporter", "sw_version": "1.0.0",
           "support_url": "https://…" },
  "cmps": {
    "step_count_sum_p1d": {
      "p": "sensor",
      "name": "Steps today",
      "unique_id": "ohe_6b1c2d3e_step_count_sum_P1D",
      "object_id": "ohe_steps_today",
      "state_topic": "ohe/6b1c2d3e/v1/state/step_count/sum/P1D",
      "value_template": "{{ value_json.value }}",
      "json_attributes_topic": "ohe/6b1c2d3e/v1/state/step_count/sum/P1D",
      "json_attributes_template": "{{ {'bucket_start': value_json.bucketStart, 'bucket_end': value_json.bucketEnd, 'tz': value_json.tzId, 'sample_count': value_json.sampleCount, 'state': value_json.state, 'computation': value_json.computation} | tojson }}",
      "unit_of_measurement": "steps",
      "state_class": "total_increasing",
      "suggested_display_precision": 0,
      "availability_topic": "ohe/6b1c2d3e/v1/status"
    },
    "heart_rate_mean_pt1h": {
      "p": "sensor",
      "name": "Heart rate (hourly mean)",
      "unique_id": "ohe_6b1c2d3e_heart_rate_mean_PT1H",
      "state_topic": "ohe/6b1c2d3e/v1/state/heart_rate/mean/PT1H",
      "value_template": "{{ value_json.value }}",
      "unit_of_measurement": "bpm",
      "state_class": "measurement",
      "suggested_display_precision": 0
    }
  }
}
```

Generation rules, all mechanical from the catalogue:

| Discovery field | Source |
|---|---|
| `unique_id` | `ohe_<exporterId8>_<metricId>_<statistic>_<granularity>` — stable forever, so entity identity survives reinstall |
| `unit_of_measurement` | Catalogue `haUnit`. Omitted entirely when `null` (BMI) |
| `device_class` | Catalogue `haDeviceClass`. **Omitted when `null`** — never guessed |
| `state_class` | Catalogue `haStateClass`. Omitted only where the catalogue says none (enum, timestamp, passthrough) |
| `options` | Required when `device_class: enum`; from the catalogue's category value list |
| `last_reset_value_template` | Emitted only for `state_class: total` with a per-period reset: `{{ value_json.bucketStart }}` |
| `expire_after` | **Default absent.** If enabled, ≥ 3× the R-24 freshness target N — otherwise PC-2's opportunistic scheduling makes every entity flap to `unavailable` and the user blames us for Apple's ceiling (RK-4) |
| `qos` | 1. QoS 0 cannot confirm delivery and R-25 requires the destination test to report `Sent, unconfirmed` in that case |

**Retention.** Discovery messages are retained (they must be, or entities vanish on HA restart).
**State messages are not retained by default**, and this is a privacy decision, not an oversight:
a retained state topic leaves the user's most recent health values sitting on the broker
indefinitely, readable by anything with subscribe rights, including after the user removes the
destination. Retention is a per-destination opt-in that names that consequence. The cost of the
default is that entities show `unknown` until the next export after an HA restart, which is a visible,
explicable state rather than a silent leak.

**Availability.** We cannot hold an MQTT connection (PC-2, iOS background model), so there is no
meaningful Last Will and Testament and no `birth`/`will` availability semantics. The `status` topic
is published `online` at the start of each export run and is *retained*, carrying no health data. The
real freshness signal is the `time_since_last_success` sensor (R-27), which is what a user should
alert on, and the documentation must say so rather than letting people build alerts on entity
availability.

**Removal.** Disabling a metric publishes an empty retained payload to its discovery component, which
is HA's documented removal mechanism. Deleting the destination publishes an empty payload to
`homeassistant/device/<exporterId>/config`. This must happen as part of R-43's "delete all" so that
we do not leave orphaned health entities in someone's Home Assistant after the user has asked us to
erase everything.

---

## The conforming receiver contract

This is what makes R-115's reference receiver and any third-party implementation interoperable, and
it is what the conformance fixtures test against. RFC 2119 keywords.

A receiver claiming **`ohe.wire/1` conformance** MUST implement everything in the MUST list. A
receiver may additionally claim **`ohe.wire/1 + convergent`** if it also passes the adversarial
sequence fixtures.

### MUST

| # | Requirement |
|---|---|
| C1 | Key sample storage on `uuid` and apply **upsert** semantics: an incoming record with a known `uuid` replaces the stored record in full |
| C2 | Key aggregate storage on `bucketKey` and apply upsert, accepting the incoming record when `emitSeq >= stored.emitSeq` |
| C3 | Treat a `tombstone` as **terminal** for its `uuid`: record the deletion, and never re-create that `uuid` from any subsequently arriving record. A receiver that hard-deletes the row and forgets the `uuid` fails this and will resurrect deleted health data on the next retry |
| C4 | Accept duplicate delivery of any batch, and of any record, without changing final state |
| C5 | Accept batches in any order. Never use `start`, `end`, `observedAt`, `emittedAt` or `computedAt` as an ordering, watermark or de-duplication key |
| C6 | Accept unknown **optional** fields on any record kind and either store or ignore them, never error |
| C7 | Accept unknown members of **open** enums; store the raw string and continue. Use the paired raw field (`categoryValue`, `activityTypeRaw`, `hkIdentifier`) where one exists |
| C8 | Persist `unit` with every value and never assume a unit from `metricId` |
| C9 | Persist `tzOffsetMinutes` and `tzSource` verbatim. **Never** infer a time zone, never substitute the receiver's own zone, and never present a local time when `tzSource` is `unknown` without marking it as derived |
| C10 | Accept a batch containing zero records |
| C11 | Accept a child record (`series.*`) whose `parentUuid` has not been seen, and retain it |
| C12 | Return a 2xx status **only after the batch is durably persisted.** A 2xx before durability makes at-least-once meaningless and turns R-21's accounting into a lie |
| C13 | Reject a batch whose `batch.footer.contentDigest` does not match the received records, with a 4xx and a body naming the mismatch |
| C14 | Not interpret, diagnose, screen, threshold-alert on, or recommend clinical action from any field, in particular `sample.ecg.classification` (R-42) |

### SHOULD

| # | Requirement |
|---|---|
| C15 | De-duplicate on `batchId` as an optimisation, retaining seen ids for at least 7 days |
| C16 | Return a receipt body (below) so the producer can implement R-21 honestly |
| C17 | Log, rather than silently resolve, an aggregate `bucketKey` collision between two different `exporterId`s — that is the unsupported AR-15 configuration and the user needs to know |
| C18 | Expose `state` and `computation` on aggregates to the end user, so a discrepancy against the Health app is explicable |
| C19 | Treat `batch.footer.complete: false` as a partial delivery and surface it |
| C20 | Support gzip request bodies (NFR-16) |

### MAY

| # | Requirement |
|---|---|
| C21 | Reject unknown members of **closed** enums with a 4xx naming the field |
| C22 | Enforce a maximum body size, returning 413. Producers handle 413 by halving the batch |
| C23 | Store `metadata` opaquely or discard it |

### Receipt body

```json
{
  "spec": "ohe.wire/1",
  "batchId": "0192f3c1-…",
  "accepted": 1998,
  "rejected": 2,
  "duplicate": 0,
  "rejects": [
    { "index": 17, "uuid": "…", "reason": "unknownClosedEnumMember", "field": "tzSource" }
  ]
}
```

This is the field that closes the honesty loop end to end. R-21 forbids recording a run as `success`
when acknowledged samples are fewer than samples read; without a receipt, "acknowledged" can only
mean "the server said 200", which is exactly the incumbent's "Succeeded but nothing arrived" failure
mode (MA gap 2). With it, the producer can record `partial` and name the cause. It is a SHOULD rather
than a MUST because a plain webhook — including Home Assistant's — cannot produce it, and making it a
MUST would exclude the primary persona's own destination. Where the receipt is absent the run outcome
is `unknownAck`, never `success`.

---

## Conformance fixture set design

R-12's acceptance criterion is "spec plus **machine-readable fixtures** in-repo; CI fails on a
breaking change to a frozen version". The fixtures are the executable form of the specification, and
they serve two different audiences: our encoder (G1/G2) and third-party receivers (G3/G4).

### Layout

```
fixtures/ohe.wire/1/
  <fixture-id>/
    meta.yaml            # frozen-at version, injected batchId/seq/exporterId/clock, description,
                         # traces: [R-02, AR-08, …]
    input.json           # logical records, hand-authored or generated from a committed seed
    expected.ndjson      # byte-exact canonical output
    expected.json        # byte-exact canonical output
    expected.pretty.json # byte-exact pretty output
    expected.csv/        # one file per record kind, byte-exact
    expected-state.json  # for receiver fixtures: final state after applying the whole sequence
  _sequences/
    <sequence-id>/
      steps.yaml         # ordered list of fixture-ids with delivery instructions
      expected-state.json
```

`meta.yaml` carrying `traces:` means every requirement in §6.1 of the PRD can be shown to have at
least one fixture, mechanically, and a coverage report is generated rather than asserted.

### Encoder fixtures — categories

| Category | Fixtures |
|---|---|
| Structural | Empty batch; single sample; one of every record kind; maximum-size batch; multi-batch file |
| Time | DST spring-forward and fall-back in `Europe/Berlin` and `America/Santiago` (southern-hemisphere, opposite direction); a sample inside the repeated hour; leap day 2028-02-29; a zone with a non-hour offset (`Asia/Kathmandu`, +05:45); a historical offset change (`Europe/Moscow` 2014); `tzOffsetMinutes: null` with `tzSource: unknown` |
| Units | Every canonical unit at a boundary value; a value requiring shortest-round-trip disambiguation (`0.1 + 0.2`); a very large and a very small magnitude; `-0` normalisation |
| Locale | The same input encoded under `de_DE`, `ar_EG` (Eastern Arabic digits), `en_US`, `tr_TR` (dotted/dotless i, which breaks naive lowercasing of enum names) — all byte-identical |
| Identity | Duplicate `uuid` within a batch (must be rejected by the encoder); tombstone and sample for the same `uuid` in one batch |
| Aggregation | Open bucket; final bucket; revised bucket with `supersedes`; empty bucket (`value: null`, `sampleCount: 0`); a `P1D` bucket of 82,800 and of 90,000 seconds; `sourceScope: single` with a `sourceName` containing `|` (escaping) |
| Structured types | ECG with 15,360 voltages across chunk boundaries; a 15,000-point workout route across chunks; a heartbeat series with gaps; blood-pressure correlation; State of Mind with empty and with maximal `labels` |
| Passthrough | An `unmapped` sample with a raw `hkIdentifier` we have never curated |
| Hostile strings | Source name containing emoji, RTL text, a newline, a `"`, a `,`, a `;`, 4,096 characters; a metadata key colliding with a first-class field name |
| Nulls | Every `N`-typed field at `null`; every `O`-typed field absent |

### Receiver conformance sequences

Black-box: feed the sequence to a receiver over its real ingest path, then read its final state and
compare. This is what a third party runs to claim conformance, and what G4 runs against our reference
receiver.

| Sequence | Tests |
|---|---|
| `replay-10x` | The same batch delivered ten times. Final row count unchanged. **R-02's acceptance criterion, verbatim** |
| `reverse-order` | Batches delivered newest-first. Final state identical to in-order (C5) |
| `tombstone-then-resend` | Sample → tombstone → the *original batch again*. The record must stay deleted (C3). **This is the sequence most naive receivers fail** |
| `edit-as-delete-insert` | Sample A → tombstone A + sample B (new uuid). Final state: exactly one live record. Mirrors HK-16 |
| `interleaved-tombstone` | Tombstone arrives in an earlier batch than the sample it deletes |
| `bucket-revision` | Open → final → revised, with a lower-`emitSeq` duplicate injected between. C2 |
| `bucket-recompute` | Recompute and resend a bucket unchanged. Row count and value unchanged. **R-06's acceptance criterion** |
| `late-arriving-backfill` | A sample dated 30 days in the past, then the revised aggregate for that day. **R-01 / MA-01's acceptance criterion** |
| `orphan-child` | `series.workoutRoute` before its `workout`. C11 |
| `partial-batch` | `complete: false` in the footer. C19 |
| `corrupt-digest` | A mutated record with an unchanged digest. Must be rejected (C13) |
| `unknown-additive` | A payload from a hypothetical v1.9 with three unknown optional fields, a new open-enum member and a new record kind. Must ingest cleanly. **This is G3** |
| `two-exporters` | The same `bucketKey` from two `exporterId`s. Must not crash; must log (C17) |

### Generation and freezing

Tier-1 fixtures (~200 samples, per R-82) are committed verbatim. The 10M-sample tier is generated
reproducibly from a committed seed and is **not** committed; its digest is. A fixture, once frozen at
a release tag, is immutable: a defect found in a fixture is fixed by adding a new fixture and marking
the old one `superseded`, never by editing it, because editing it would silently weaken G1.

Fixtures contain no real health data. They are synthetic (R-114), which is also why they can be
CC0-licensed and why a third party can run the conformance suite without us shipping anything
sensitive.

---

## Open questions for the PM

1. **Do we ship the HAE compatibility profile at all, given it cannot carry R-02 or R-05?** My
   recommendation: yes, because MA-03's adoption argument is the strongest one available and RK-8 is
   real — but gated behind an explicit one-time acknowledgement screen naming the two losses, and
   never as a user's only destination without a warning. The alternative reading is that shipping a
   profile which structurally violates our central claim undermines the positioning more than the
   ecosystem access is worth. This is a product-identity decision, not a schema one.

2. **`unitProfile` for the HAE profile: allow `haeImperial`/`haeMetric`, or force `canonical`?**
   Allowing it maximises drop-in compatibility with existing dashboards; forcing canonical maximises
   consistency and is one fewer configuration axis to test. I lean to allowing it with `canonical` as
   the default, but it adds a matrix dimension to the AR-25 round-trip test.

3. **Retained MQTT state messages: default off (privacy) or default on (usability)?** Default off
   means entities read `unknown` after a Home Assistant restart until the next opportunistic export,
   which under PC-2 could be an hour. Default on leaves the user's latest health values on the broker
   indefinitely. I recommend off, but it is a direct trade of primary-persona experience against the
   privacy posture and the owner should choose.

4. **Confirm `exporterId` is excluded from `bucketKey`.** Excluding it makes device replacement
   seamless and makes concurrent dual-exporter aggregate export an unsupported configuration the app
   must prevent. Including it makes dual-export safe but forks every series on device change. I
   recommend excluding, consistent with AR-15.

5. **Is the receiver receipt body a MUST or a SHOULD?** As a MUST it makes R-21 fully honest but
   excludes Home Assistant's own webhook and every plain HTTP endpoint — i.e. the primary persona's
   destination. I have specified SHOULD, with `unknownAck` as the outcome when it is absent. Confirm
   that R-21's `unknownAck` outcome is acceptable as the normal case for webhook destinations, because
   it will be.

6. **`device_class: energy` for active/basal energy.** It is the technically correct class and it
   gives correct unit conversion, but it makes calorie sensors selectable in Home Assistant's Energy
   dashboard, which is confusing. `null` avoids that and loses conversion. R-89's contract test can
   settle the behaviour; the choice is a UX one.

7. **Do `characteristic` records ship in v1 at all?** HK-30 and R-66 make them off by default and
   flagged as re-identifying. Given they are five static values that materially raise the
   re-identification risk of an otherwise pseudonymous dataset, there is a defensible position that
   they should not be in the wire format at all in v1. I have specified them with a mandatory
   `reidentifying: true` marker, but I would accept cutting them.

8. **CSV tombstones: emit them knowing most consumers will not read them?** I have specified emitting
   them in a separate file and declaring CSV non-convergent. The alternative — refusing to emit
   tombstones in CSV — would be more honest still but leaves a user who exports only CSV with no path
   to a correct archive at all. Confirm the current choice.

9. **Payload signing.** Deferred in this draft. The R-31 destination-verification feature pins the
   *server*; nothing authenticates the *payload*. For a self-hoster ingesting from an app on an
   untrusted network segment with a plain-HTTP opt-in (R-35), a detached signature over
   `contentDigest` would be cheap and additive. Is it in scope for v1, or explicitly v1.1?

10. **Does the CC0 dedication cover the conformance fixtures and the metric catalogue JSON?** I have
    assumed yes on all three (spec, schemas, fixtures, catalogue), since a receiver author needs all
    of them and licence friction on the fixtures would defeat the purpose. This needs to be recorded
    alongside D-01/D-02 rather than assumed, and it interacts with the DCO assertion text.

11. **The `haRequiresAggregate` refusal.** I have specified that the Home Assistant destination
    *refuses* to enable raw-sample export of cumulative metrics, because pushing raw samples produces
    silently wrong long-term statistics. That is a product behaviour derived from a schema fact.
    Confirm the refusal is acceptable, or whether it should be a warning the user can override.

12. **Spec repository location.** R-12 says the format's stability commitment is independent of the
    app's release cycle. Does the spec, schema, catalogue and fixture set live in the app repository
    (simpler, one CI) or in a separate repository with its own release tags (genuinely independent,
    survivable if the app repo is archived)? I lean to a separate repository for exactly the RK-1
    reason, but it doubles the release mechanics.

---

## Sources

Apple / HealthKit — via the Stage 1 contributions, primarily `02-healthkit-platform-expert.md`
(local SDK inspection of `iPhoneOS26.5.sdk`) and `03-principal-architect.md`.

Health Auto Export — the incumbent's shape:

1. HealthyApps Help Center, *JSON Export Format* (overview; the `data` envelope and its eight arrays) — <https://help.healthyapps.dev/en/health-auto-export/export-format>
2. HealthyApps Help Center, *Health Metrics — JSON Export Format* (last updated 23 Aug 2026; snake_case naming, `{name, units, data[]}`, and the bespoke shapes for blood pressure, heart rate, sleep, blood glucose, sexual activity, handwashing, toothbrushing, insulin delivery; the note that `source` may be omitted on iOS 27+) — <https://help.healthyapps.dev/en/health-auto-export/export-format/health-metrics>
3. HealthyApps Help Center, *Workouts — JSON Export Format* (v1 vs v2; `id`, `start`, `end`, `duration`; `{qty, units}` objects; time-series arrays; the v2 route point fields) — <https://help.healthyapps.dev/en/health-auto-export/export-format/workouts>
4. HealthyApps Help Center, *ECG — JSON Export Format* (`voltageMeasurements` as per-point timestamped objects; 512 Hz; classification enum) — <https://help.healthyapps.dev/en/health-auto-export/export-format/ecg>
5. HealthyApps Help Center, *State of Mind — JSON Export Format* (last updated 26 Aug 2026; note it uses ISO 8601 `Z` while every other record type uses `yyyy-MM-dd HH:mm:ss Z`) — <https://help.healthyapps.dev/en/health-auto-export/export-format/state-of-mind>
6. HealthyApps Help Center, *Heart Rate Notifications — JSON Export Format* (the nested `timestamp.interval` structure) — <https://help.healthyapps.dev/en/health-auto-export/export-format/heart-rate-notifications>
7. HealthyApps Help Center, *Sync Apple Health Data to REST API* (Export Version 1/2 toggle; Summarize Data toggle; Batch Requests; the `automation-name` / `automation-id` / `automation-aggregation` / `automation-period` / `session-id` headers; `multipart/form-data` for CSV) — <https://help.healthyapps.dev/en/health-auto-export/automations/rest-api>
8. HealthyApps Help Center, *Sync Apple Health Data to MQTT* (JSON only; single configured topic; no discovery) — <https://help.healthyapps.dev/en/health-auto-export/automations/mqtt>
9. GitHub issue `Lybron/health-auto-export#47`, *Extend JSON format documentation with JSON schema* — closed Mar 2026: "I've added more detailed info to the Help Center… this is more likely to be kept up to date." Evidence that no machine-readable schema exists and that the wiki is stale — <https://github.com/Lybron/health-auto-export/issues/47>
10. GitHub issue `Lybron/health-auto-export#39`, *Update documentation on Workout V2* — the v1 vs v2 route-point difference, reported by a user reverse-engineering it — <https://github.com/Lybron/health-auto-export/issues/39>

OSS receivers built against that format:

11. `irvinlim/apple-health-ingester` — `pkg/healthautoexport/types.go`. The most precise available description of the wire format, including the five accepted timestamp layouts (24-hour, 12-hour, and two U+202F narrow-no-break-space variants) and the probe-based disambiguation of `SleepAnalysis` vs `AggregatedSleepAnalysis` — <https://github.com/irvinlim/apple-health-ingester/blob/master/pkg/healthautoexport/types.go>
12. `irvinlim/apple-health-ingester` README — InfluxDB measurement naming (`<metric>_<unit>`), `?target=` tagging, backend URLs — <https://github.com/irvinlim/apple-health-ingester>
13. `mrkhachaturov/hae-vault` — `POST /api/ingest`, 50 MB body cap, SQLite tables `metrics`/`sleep`/`workouts`/`sync_log`, and the natural-key row shape `{ts, date, qty, min, avg, max, units, source, target}` — <https://github.com/mrkhachaturov/hae-vault>
14. `HealthyApps/health-auto-export-server` — the incumbent's own OSS Node + Grafana companion — <https://github.com/HealthyApps/health-auto-export-server>
15. Ladvien, *Building a Health Data Pipeline — iOS Auto Export to FastAPI & PostgreSQL* — an independent receiver's Postgres schema, confirming that receivers shard by datapoint shape (`quantity_timestamp`, `heart_rate`, `blood_pressure`, `sleep_analysis`) because the format has no discriminator — <https://ladvien.com/syncing-apple-health-kit-data-postgres/>
16. cleverdevil, *Taking Control of my Personal Health Data* — an early independent transcription of the envelope, and an NDJSON flattening of it, corroborating the `2021-01-20 00:00:00 -0800` timestamp form — <https://cleverdevil.io/2021/taking-control-of-my-personal-health-data>

Home Assistant:

17. Home Assistant Developer Docs, *Sensor entity* — the `device_class` table with accepted units per class; the three state classes; the rule that `measurement` statistics exclude device classes `date`, `enum`, `energy`, `gas`, `monetary`, `timestamp`, `volume`, `water`; the `total` vs `total_increasing` vs `last_reset` decision guidance — <https://developers.home-assistant.io/docs/core/entity/sensor/>
18. Home Assistant, *MQTT Sensor integration* — `state_class`, `last_reset_value_template`, `expire_after`, `json_attributes_topic`, `suggested_display_precision`, `unique_id` requirement under device-based discovery — <https://www.home-assistant.io/integrations/sensor.mqtt/>
19. Home Assistant, *MQTT integration* — discovery topic grammar `<discovery_prefix>/<component>/[<node_id>/]<object_id>/config`, device-based discovery at `homeassistant/device/<object_id>/config` with a `cmps` map, and the `migrate_discovery` migration path — <https://www.home-assistant.io/integrations/mqtt/>

Standards:

20. RFC 8785, *JSON Canonicalization Scheme (JCS)* — the normative canonical form for §"Encodings" and for `contentDigest` — <https://www.rfc-editor.org/rfc/rfc8785>
21. RFC 3339, *Date and Time on the Internet: Timestamps* — <https://www.rfc-editor.org/rfc/rfc3339>
22. RFC 4180, *Common Format and MIME Type for CSV Files* — <https://www.rfc-editor.org/rfc/rfc4180>
23. RFC 2119 / RFC 8174 — requirement keywords used in §"The conforming receiver contract"
24. RFC 9562, *UUIDs* — UUIDv7 for `batchId` (time-ordered, useful for receiver-side retention windows), UUIDv5 for deterministic series chunk identifiers — <https://www.rfc-editor.org/rfc/rfc9562>
