# QA Lead / Test Architect — Stage 1 Contribution

## Executive summary

This product has the worst testability profile I have worked on: the data source cannot be
populated programmatically in CI, the most important behaviours are OS-scheduled and take days
to observe, the destinations belong to other people, and the test fixtures are legally and
ethically radioactive. None of that is a reason not to build it. It is a reason to make
testability a Stage 2 design constraint rather than a Stage 4 problem.

Five things drive everything else in this contribution:

1. **HealthKit cannot be a dependency of the test suite.** It is unavailable on macOS entirely
   (`isHealthDataAvailable()` returns `false` on macOS 13+ [1][2]), and in the iOS Simulator the
   only way to get data in is a human clicking in the Health app — there is no scriptable
   population path, no sensor simulation, and no workout generation [3][4][5]. Therefore the
   entire export pipeline must be testable with HealthKit *not linked*. That is requirement
   QA-01 and it is the single most important thing this contribution asks of Stage 2.
2. **Read denial is indistinguishable from "no data".** HealthKit deliberately hides read
   authorization state; if the user denies read access, queries return only samples our own app
   wrote [6]. This is a correctness trap (we may report a successful empty export) *and* a test
   trap (a write-then-read test passes even when authorization was refused).
3. **"It still works after three weeks" is not verifiable before release.** Background delivery
   frequency is a ceiling, not a promise; `stepCount` is capped at hourly; nothing is delivered
   while the device is locked with a passcode [7][8][9]. We must therefore verify long-run
   delivery *in the field*, and the product must be designed to make its own failure visible
   (QA-14, QA-15) rather than silent.
4. **Exactly-once delivery to an arbitrary user REST endpoint is impossible.** The strongest
   guarantee we can test is at-least-once delivery plus a stable idempotency key. The PRD should
   say that out loud rather than implying "no duplicates".
5. **The synthetic corpus is the highest-leverage test asset in the project**, and its edge-case
   catalogue (§ Synthetic health data corpus) is where the real bugs live. If we build one thing
   well in Stage 3, build that.

CI economics are, unusually, in our favour: standard GitHub-hosted runners — including macOS —
are free for public repositories [10][11]. That freeness is the strongest argument for keeping
this repo permanently public, and it is worth quantifying: the same PR workload on a private
repo costs $0.062/min for macOS [10], roughly $0.93 per 15-minute job.

---

## The testability problem (verified constraints)

### HealthKit and the Simulator

| Claim | Status | Evidence |
|---|---|---|
| HealthKit data is unavailable on macOS. The framework compiles (macOS 13+) so multiplatform code builds, but there is no store and `isHealthDataAvailable()` returns `false`. | **Verified** | [1][2] |
| Same for iPadOS 16 and earlier. iPadOS 17+ has its own store. | **Verified** | [1][2] |
| Each of iPhone, Apple Watch, iPad has its own separate HealthKit store, synced by the system. Old data is periodically purged from Apple Watch; `earliestPermittedSampleDate()` tells you how far back that store goes. | **Verified** | [2] |
| The iOS Simulator *does* have a Health app, and some data can be added by hand through its UI (e.g. steps; ECG has a dedicated Simulator "Add Data" path; Health Records have three canned sample accounts). | **Verified** | [3][12][5] |
| There is no supported way to populate the Simulator's store programmatically or from the command line. Population is GUI-only, sample-by-sample. | **Verified by absence** — no such API or `simctl` subcommand is documented. Treat as an assumption pending a counterexample. | [3][5] |
| The Simulator does not generate sensor or workout data. Apple confirmed the WWDC demo was faked. | **Verified** | [4] |
| Some Simulator Health "Add Data" sheets are outright broken (breathing/sleep disturbance samples cannot be saved as of WWDC26). | **Verified** | [13] |
| HealthKit background delivery does not work in the Simulator; it requires physical hardware. | **Strong secondary source, not Apple's own words.** Treat as verified-in-practice. | [9] |
| Anything our own app writes is attributed to *our* app as the `HKSource`. We cannot forge a sample that appears to come from "Apple Watch" or a third-party app. | **Verified by design** — sources are assigned by HealthKit, not by the writer. | [6][2] |
| Some types cannot be written at all: ECG is read-only, and requesting *share* authorization for Apple-proprietary types such as `appleExerciseTime` / `appleStandHour` raises `NSInvalidArgumentException`. | **Verified** | [12][14] |
| Sample types have duration restrictions; Apple advises against samples ≥24 hours, and a sample violating a type's restrictions fails to save. | **Verified** | [15] |

**What this means.** The Simulator is useful for UI, layout, accessibility, localisation and
"does the app launch and not crash" — nothing more. It is *not* a source of realistic health
data, and any test that needs a realistic store needs either (a) a fake source behind our own
seam, or (b) a physical device with a real human's data on it, which we cannot check into git.
There is no third option.

### The rest of the problem

- **Background wake is non-deterministic by design.** `HKUpdateFrequency` is a maximum, not a
  schedule; the system throttles on battery level, background budget and "other undocumented
  factors"; `stepCount` is capped at once per hour even with `.immediate`; and nothing arrives
  while the device is locked with a passcode because the data is protected [7][8]. Failing to
  call the observer query's completion handler stops future deliveries entirely [9] — a bug
  class that only manifests as "it worked for a day and then stopped".
- **Anchored queries are insertion-ordered, not date-ordered.** A sample inserted today with a
  date three years ago arrives in the *next* delta batch. This means "did we export everything
  in date range X?" is not answerable from the anchor alone, and any date-windowed export logic
  will silently lose retroactive data unless designed otherwise.
- **Destinations are other people's software.** Home Assistant, MQTT brokers, Dropbox, Google
  Drive, iCloud Drive and arbitrary user REST endpoints all change without asking us. Some
  (iCloud Drive) have no local emulator of any kind.
- **Real health data cannot be a fixture.** Not the maintainers' own, either: it ends up in git
  history forever, in CI logs, and in every fork.
- **OSS reality.** No paid device farm, no guarantee any contributor owns an Apple Watch, and
  fork PRs cannot be given secrets — so no credentialed test can ever be a required PR check.

---

## Test strategy and pyramid

Two sets of proportions, because they disagree and the disagreement is the point.

| Layer | What it covers | Tooling | Runs where | % of test count | % of risk covered |
|---|---|---|---|---|---|
| **L1 Unit** | Transformation, serialisation (CSV/JSON/GPX), unit conversion, calendar/time-zone arithmetic, bucketing/aggregation, retry & backoff policy, redaction rules, payload construction, config parsing & migration, type registry | Swift Testing [16][17] | Any Mac; **also Linux** (cheap CI) | 55–60% | ~30% |
| **L2 Property / model-based** | The invariants in § Correctness properties: round-trip, idempotency, no-loss/no-dup under interruption, anchor monotonicity, determinism, redaction | Swift Testing + a property library (see QA-19) | Any Mac; also Linux | 5% | ~25% |
| **L3 Integration (in-process)** | Whole pipeline: fake HealthKit source → transform → persistence (temp dir) → fake destination. Fault injection, clock injection, kill-and-resume | Swift Testing | Any Mac; also Linux | 18–20% | ~20% |
| **L4 Contract / real doubles** | Real Mosquitto broker, real local HTTP server, real Home Assistant container, S3-compatible fake; schema validation of every emitted payload | Swift Testing + Homebrew Mosquitto (macOS) / containers (Linux) | Linux runner for containers; macOS for native | 8% | ~10% |
| **L5 UI (Simulator)** | Onboarding, permission-denied and empty states, config editing, error surfaces, accessibility audits, Dynamic Type, pseudo-locale and RTL | XCUITest (**must stay XCTest** [16][17][18]) | macOS runner, Simulator | 6–8% | ~5% |
| **L6 Device** | Real HealthKit store read, authorization sheets, background delivery, watchOS, performance baselines, memory ceiling under real OS limits | XCTest (+ `XCTMetric` — XCTest-only [16][17][18]) | Self-hosted Mac + physical iPhone/Watch, `workflow_dispatch` only | 2–3% | ~7% |
| **L7 Soak & field** | Multi-week delivery, silent-failure detection, energy, real-world source mix, upgrade-in-place | Manual protocol + TestFlight cohort + MetricKit [19][20] | Maintainer and beta devices | <1% (not automated) | ~3% **and the 3% that hurts most** |

**Framework split (verified, Xcode 26 / Swift 6.3).** Swift Testing is the default for L1–L4.
XCTest is retained *only* for UI automation (`XCUIApplication`), performance tests
(`XCTMetric`), and Objective-C exception handling — Apple has shipped no Swift Testing
equivalent for these [16][17][18]. Both coexist in one target; interop reporting is controlled
by `SWIFT_TESTING_XCTEST_INTEROP_MODE` [17][18].

### What we deliberately will not automate

Stated as policy so nobody wastes a month trying:

1. **Background wake timing.** We will not assert "delivered within N minutes". We will assert
   "given an observer callback, the export completes correctly and the anchor advances" — the
   part that is ours — and measure delivery latency distributions in the field.
2. **Multi-week continuity.** No CI job simulates three weeks. Covered by a scripted soak
   protocol and field telemetry.
3. **Apple's own permission UI.** We will assert that our app *requests* the right types and
   handles every returned state; we will not automate driving the system HealthKit sheet.
4. **Apple Watch data generation.** Impossible. Covered by fixtures modelled on Watch data plus
   a manual device pass.
5. **OAuth flows to Dropbox / Google Drive, and iCloud Drive semantics.** No emulators exist.
   Recorded-fixture tests for our HTTP layer plus a manual pre-release checklist.
6. **Energy/battery.** Not automatable to a gate. Manual protocol + field metrics.
7. **Anything requiring secrets on a fork PR.** Structurally impossible; those jobs are nightly
   or release-gated, never required checks.

---

## Testability constraints Stage 2 must honour

These are constraints, not designs. Stage 2 chooses *how*; if it declines any of these, the
corresponding part of the test strategy becomes impossible and I will say so at the Stage 2
review.

| # | Constraint | Why | How Stage 4 checks Stage 2 honoured it |
|---|---|---|---|
| C1 | HealthKit access sits behind a seam. No HealthKit type (`HKSample`, `HKQuantity`, `HKAnchor`, `HKUnit`, …) appears in the pipeline's own types or in any interface the pipeline consumes. | Otherwise nothing downstream is testable without a device. | The core package builds and its whole L1–L4 suite passes on **Linux**, where HealthKit does not exist. Binary check: HealthKit is not among the core package's linked frameworks. |
| C2 | The domain model is our own value types, constructible from a data file. | Fixtures must be authorable as text, reviewable in a PR, and generatable at volume. | A fixture file round-trips into the domain model with no HealthKit involvement. |
| C3 | Time is injected: no `Date()`, `Date.now`, `TimeZone.current`, `Calendar.current`, `Locale.current` in pipeline code. | Every DST/leap/boundary test needs to control the clock, zone and calendar. | Lint rule fails the build on direct use outside an explicit allowlist; the allowlist is reviewed. |
| C4 | All I/O — network, filesystem, keychain/secure storage, secure enclave, notification scheduling — is behind injected interfaces, and the HTTP layer's session configuration is injectable so tests can target `127.0.0.1`. | Contract tests and fault injection. | Integration tests run with zero real network egress; a network-egress assertion in CI fails if any test opens a non-loopback socket. |
| C5 | Export is resumable from a durable, versioned, **inspectable** checkpoint, and the checkpoint format is documented. | Kill/resume properties (P3, P5, P14) are otherwise unassertable. | Tests read and assert checkpoint contents directly; a format-version migration test exists. |
| C6 | Named fault-injection seams exist at: after-read, after-transform, before-write, after-write-before-ack, after-ack-before-anchor-advance, and during-anchor-persist. Enabled only in test builds. | The interruption invariants require killing at exactly these points. | A test enumerates all seams and asserts each is reachable; a release-build test asserts none are reachable. |
| C7 | Output is deterministic: identical input + config ⇒ byte-identical bytes, independent of dictionary ordering, hash seeds, locale and architecture. Record identity derives from data, not wall-clock or insertion order. | Snapshot testing, idempotency and diffability all depend on it. | P8: same fixture, 100 runs, arm64 + x86_64 ⇒ identical SHA-256. |
| C8 | Structured, stable telemetry event names and attributes (not free-text log strings) for every failure and lifecycle transition. | Tests must assert *why* something failed; field diagnosis needs the same. | Tests assert on event identifiers; a registry of event names is committed and diffed in PRs. |
| C9 | Per-destination durable state includes "last successful export" and "last failure with reason", exposed in the UI. | Silent failure is otherwise undetectable by the user *and* by us. See QA-14. | A UI test asserts the surface; an integration test asserts the state after each failure mode. |
| C10 | Anchors/cursors are persisted opaquely but with a version tag, and rejection of a stale anchor is handled without silently resetting to zero. | A silent anchor reset causes a full re-export — real user-visible harm (duplicate data, battery, quota). | P13: forced anchor invalidation produces a recoverable, user-visible state, never a silent full re-export. |
| C11 | Memory behaviour is streaming, not accumulate-then-write, for every format. | Background/extension memory limits are hard kills. | P12: peak footprint is O(1) in corpus size across the T0/T1/T2 tiers. |
| C12 | Test-only code (fake source, fault seams, fixture loader) is excluded from release builds at compile time. | It is otherwise an attack surface on health data. | Release binary is scanned for test-only symbols; the check is a release gate. |

---

## Synthetic health data corpus

### Requirements on shape

The corpus is a **seeded deterministic generator plus committed small fixtures**, not committed
bulk data. The generator, its seeds and its schema are the reviewable artifact; ten million rows
are not.

**Type coverage.** At least 60 distinct types across every structural family, because the
families behave differently and the bugs are per-family, not per-metric:

| Family | Must include | Note |
|---|---|---|
| Cumulative quantity | `stepCount`, `distanceWalkingRunning`, `distanceCycling`, `activeEnergyBurned`, `basalEnergyBurned`, `flightsClimbed`, `dietaryWater`, `appleStandTime` | Summable; overlap policy matters |
| Discrete quantity | `heartRate`, `restingHeartRate`, `heartRateVariabilitySDNN`, `bodyMass`, `bodyFatPercentage`, `height`, `bloodGlucose`, `oxygenSaturation`, `respiratoryRate`, `bodyTemperature`, `vo2Max`, `walkingHeartRateAverage` | Averaged, not summed |
| Category | `sleepAnalysis` (all stages: inBed, asleepCore/Deep/REM/Unspecified, awake), `mindfulSession`, `menstrualFlow`, `handwashingEvent`, `appleStandHour` | `appleStandHour` is read-only |
| Correlation | `bloodPressure` (systolic+diastolic), `food` (nutrition bundle) | Container semantics; children must not be saved separately [15] |
| Workout | `HKWorkout` across ≥15 activity types, with segments/laps, per-workout statistics, metadata, and routes | Routes drive GPX |
| Series | Heartbeat series; high-frequency quantity series | Different query API, different volume profile |
| Read-only / unsynthesisable | ECG, `appleExerciseTime`, `appleStandHour`, clinical/FHIR records | **Cannot be written** [12][14]; fixtures exist only in our own domain model, never via a HealthKit write |
| Characteristics | date of birth, biological sex, blood type, Fitzpatrick skin type, wheelchair use | Not samples; no anchor; no history |
| Activity summaries | Daily move/exercise/stand rings | Separate query type, not a sample |
| Newer/uncertain | Medications, state of mind, sleep/breathing disturbances | **Open question for the PM/domain specialist:** confirm the v1 list. The Simulator's disturbance entry sheet is currently broken [13] |

**Volume tiers.** Numbers, as demanded. These are engineering estimates with the arithmetic
shown so they can be falsified:

| Tier | Size | Span | Committed? | Purpose |
|---|---|---|---|---|
| **T0** | ≤ 200 samples | Days | Yes, hand-authored, human-readable | Unit tests; every edge case below has a T0 case |
| **T1 "large store"** | **10,000,000 samples, ≥60 types, ≥5 years, ≥6 sources** | 5 years | No — generated from a committed seed | The headline "large store" NFR case |
| **T2 "pathological"** | 50,000,000 samples, 15 years, one type holding 20M | 15 years | No — generated | Nightly/device-only; finds O(n²) and memory blowups |

*Derivation of T1 (assumption, falsifiable):* an active Apple Watch wearer generates roughly
105k/yr resting heart-rate samples (5-minute cadence), ~200k/yr workout heart rate (5-second
cadence, 45 min/day), ~36k/yr each for step, distance, active-energy and basal-energy buckets,
~9k/yr stand/exercise hours, ~15k/yr sleep stage segments, plus environmental audio exposure and
HRV — call it 600k–900k samples/year. Add one high-frequency third-party writer (a CGM at
5-minute cadence is 105k/yr; a running app writing per-second data is far more) and 5 years lands
at 3M–12M. **10M is the number the PRD should use.**

### Edge-case catalogue

Every row is a required fixture. Every row gets at least one test. IDs are stable so the PRD and
Stage 4 can reference them.

**Time, calendar and zones**

| ID | Case | Why it breaks things |
|---|---|---|
| FIX-T01 | DST spring-forward: sample at a local wall-clock time that does not exist (02:30 on transition day) | Naive `DateComponents` → nil date → crash or silent drop |
| FIX-T02 | DST fall-back: two distinct samples at the same local wall-clock time in the repeated hour | Dedup-by-local-time collapses them; daily buckets get 25 hours |
| FIX-T03 | Half-hour and 45-minute offsets: `Asia/Kathmandu` (+05:45), `Australia/Lord_Howe` (30-minute DST shift), `Pacific/Chatham` | Any code assuming whole-hour offsets |
| FIX-T04 | Southern-hemisphere DST (transition inside a calendar year, not at year edge) | Hard-coded northern assumptions |
| FIX-T05 | Historic zone-rule change: a sample from a year when the zone's rules differed | `TimeZone` offset must be resolved *at the sample instant* |
| FIX-T06 | Device changed time zone mid-workout (flight); `HKMetadataKeyTimeZone` disagrees with the device's current zone | Which zone do we export? Must be a documented rule, not an accident |
| FIX-T07 | Leap year: samples on 29 Feb, and 28 Feb→1 Mar in a non-leap year | Day arithmetic |
| FIX-T08 | "Leap second": we cannot generate one — Apple platforms use POSIX time and do not expose leap seconds. Instead: assert no code path assumes a day is 86,400 s or a minute is 60 s of wall clock | The real risk is the *assumption*, and that is testable |
| FIX-T09 | Zero-duration sample (`startDate == endDate`) and sub-millisecond duration | Division by duration → ∞/NaN; "instantaneous" vs "interval" formatting |
| FIX-T10 | `endDate < startDate` (should be impossible from HealthKit; may arrive from our own fixtures or a corrupt import) | Must reject with a diagnostic, never crash, never produce negative durations |
| FIX-T11 | Future-dated samples (device clock skew) and pre-1970 / year-0001 samples | Signed epoch handling; "since last export" logic |
| FIX-T12 | One sample spanning a day, week, month **and** DST boundary simultaneously | Bucket-splitting policy; splits must sum to the original (P10) |
| FIX-T13 | Workout crossing midnight, and crossing 31 Dec → 1 Jan | Per-day and per-year grouping |
| FIX-T14 | 26-hour sleep session and 30-hour "workout" from a third-party app | Apple discourages ≥24 h samples but they exist [15] |
| FIX-T15 | Non-Gregorian calendar and non-Sunday/Monday week start for *display* aggregation | Locale leakage into machine output (see P8) |

**Multi-source and duplication**

| ID | Case | Why it breaks things |
|---|---|---|
| FIX-S01 | Same metric, same instant, four sources: Apple Watch, iPhone, a Bluetooth scale, a third-party app | The canonical duplicate-data bug. Must never silently drop and never double-count |
| FIX-S02 | Same bundle identifier, two devices (same app on iPhone and iPad), differing `productType`/version | Source identity is not the bundle ID alone |
| FIX-S03 | Overlapping samples from a *single* source (Apple's own de-dup is per-source only) | Cumulative sums inflate |
| FIX-S04 | `HKSourceRevision` with missing/zeroed OS version and missing product type (old samples) | Optional-unwrap crashes; source keys that are nil |
| FIX-S05 | `device` nil, vs. partially populated (no hardware version, no local identifier), vs. two devices with identical names | Device-keyed grouping |
| FIX-S06 | A source app that has since been deleted from the phone | Attribution to a source we cannot resolve |
| FIX-S07 | Same logical history read from the iPhone store and the iPad store (each device has its own store [2]) | Two installs exporting to one destination must not double-write |
| FIX-S08 | Watch store where old data has been purged; `earliestPermittedSampleDate()` is recent | "Complete export" is store-relative, not absolute |

**Mutation and lifecycle**

| ID | Case | Why it breaks things |
|---|---|---|
| FIX-M01 | **Retroactively inserted historical sample**: inserted today, dated 3 years ago | Arrives in the *next* anchored batch, out of date order. Date-windowed logic loses it. The most important single fixture in this table |
| FIX-M02 | Deleted sample: `HKDeletedObject` carries only a UUID — no type, no date | Destination may not be able to express a deletion; behaviour must be documented (P7) |
| FIX-M03 | User edits a sample in the Health app (delete + insert, new UUID) | Produces a downstream duplicate unless identity is data-derived |
| FIX-M04 | A batch containing insertions and deletions of the *same* UUID | Ordering within a batch |
| FIX-M05 | Restore-from-backup: same logical samples, new UUIDs (assume UUIDs are **not** stable across restore) | Full re-export, or worse, half a re-export |
| FIX-M06 | Anchor rejected as stale/invalid by HealthKit after an OS upgrade | Must not silently reset to zero (C10) |
| FIX-M07 | 500,000 samples inserted in one batch (a third-party app back-filling years of history at once) | Batch size limits, memory, background time budget |

**Authorization**

| ID | Case | Why it breaks things |
|---|---|---|
| FIX-A01 | Read denied → queries return only samples our own app wrote; indistinguishable from empty [6] | We must never report "export complete, 0 samples" as success |
| FIX-A02 | Time-bound / limited authorization: user grants only recent history; `getEarliestAuthorizedSampleDate(for:)` is the *only* positively identifiable authorization state [6] | Must tell the user history is clipped |
| FIX-A03 | Authorization revoked mid-export | Partial batch, anchor must not advance |
| FIX-A04 | 40 of 60 requested types granted | Per-type degradation, not all-or-nothing failure |
| FIX-A05 | Our type registry accidentally requests *share* on a share-disallowed type (`appleExerciseTime`, ECG) → `NSInvalidArgumentException` [12][14] | A pure unit test over the registry catches this with no device |
| FIX-A06 | HealthKit restricted by MDM (`errorHealthDataRestricted`) [5] | Distinct user-facing message from "denied" |

**Units and numbers**

| ID | Case | Why it breaks things |
|---|---|---|
| FIX-U01 | kg ↔ lb ↔ st; km ↔ mi; kcal ↔ kJ; °C ↔ °F including negatives and the −40 crossover; mmol/L ↔ mg/dL for glucose (×18.0182); mmHg ↔ kPa; m/s ↔ min/km pace | Round-trip error accumulation; the pace conversion divides by speed |
| FIX-U02 | Speed of exactly 0 → pace | Division by zero → ∞ in output |
| FIX-U03 | Values requiring >15 significant digits; values that do not round-trip through `Double`; denormals | Silent precision loss in JSON/CSV |
| FIX-U04 | NaN, +∞, −∞ arriving from any path | Must be rejected with a diagnostic, not serialised as `nan` |
| FIX-U05 | Implausible extremes: HR 0 and 500, body mass 0 and 700 kg, 10⁹ steps in one sample, negative energy, glucose 0 | We are an exporter, not a validator — but we must not crash, and we must not silently clamp |
| FIX-U06 | Zero-valued sample that is *meaningful* (0 steps recorded) vs. absent data | Must be distinguishable in output |
| FIX-U07 | Cumulative sums that overflow `Float32` if any code path narrows | Type narrowing bugs |
| FIX-U08 | Locale with `,` as decimal separator and `.` as grouping separator, active during export | Machine output must be locale-invariant (P8); display must not be |

**Metadata, encoding and format**

| ID | Case | Why it breaks things |
|---|---|---|
| FIX-F01 | All optional metadata absent: no device, no `HKMetadataKeyWasUserEntered`, no time-zone key, no external UUID | Optional chaining and column presence in CSV |
| FIX-F02 | Metadata values of every supported kind: string, number, date, quantity, bool | Type-punning in serialisation |
| FIX-F03 | Hostile metadata content: commas, double quotes, single quotes, newlines, CR, tabs, NUL, 10 KB strings, emoji with combining marks and skin-tone modifiers, RTL override characters, unpaired surrogates | CSV quoting, JSON escaping, GPX XML escaping |
| FIX-F04 | **CSV injection**: metadata value beginning `=`, `+`, `-`, `@`, tab or CR | A security requirement as much as a correctness one — the file opens in Excel/Numbers |
| FIX-F05 | XML-hostile content in GPX: `]]>`, `<!--`, control characters illegal in XML 1.0 | Malformed GPX; downstream parser errors |
| FIX-F06 | Keys that collide after our own normalisation (e.g. two metadata keys differing only in case or in Unicode normal form) | Silent overwrite |
| FIX-F07 | GPX routes: 0 points, 1 point, 100,000 points; missing altitude/course/speed; horizontal accuracy of 3 km; coordinates at ±180°, at the poles, and exactly (0,0) | Null Island and antimeridian bugs |
| FIX-F08 | Exported enumerations must be stable machine identifiers, never localised display names | The export changes meaning when the user's language changes |
| FIX-F09 | A single JSON export exceeding 2 GB, and a CSV exceeding the row limit of common spreadsheet tools | Streaming, chunking, and honest documentation of limits |

**Volume, pathology and interruption**

| ID | Case | Why it breaks things |
|---|---|---|
| FIX-V01 | T1 (10M) and T2 (50M) stores | Memory, time, anchor batching |
| FIX-V02 | One type holding 20M samples | Pagination and per-query limits |
| FIX-V03 | 5,000 workouts each with a route | Nested query fan-out |
| FIX-V04 | Completely empty store (fresh device, every type zero) | Divide-by-count, empty-file vs no-file |
| FIX-V05 | One type's query errors while the rest succeed | Partial failure must be per-type, and the anchor for the healthy types must still advance |
| FIX-V06 | Process killed at every seam in C6: jetsam/OOM, watchdog, user force-quit, reboot mid-write, background time expiry | P3, P4, P14 |
| FIX-V07 | Destination returns HTTP 200 with a body indicating failure; 500 *after* committing; timeout after committing | The at-least-once problem. Requires an idempotency key |
| FIX-V08 | Disk full mid-write; iCloud Drive not signed in; target file replaced by another process mid-write; file on a read-only volume | Partial files must never be presented as complete |
| FIX-V09 | Network: flapping, captive portal returning HTML with 200, TLS interception with an untrusted root, IPv6-only, DNS failure, and a destination on a `.local` mDNS hostname | The `.local` case is the common self-hoster setup for Home Assistant and is a real source of failures |
| FIX-V10 | Destination that accepts the connection and then never responds (slow loris), and one that responds at 1 byte/second | Timeout policy; background time budget exhaustion |

### Corpus realism

The corpus is only useful if it resembles real stores. Committed fixtures cannot come from real
people. Proposal (QA-08): an **opt-in "characterise my store" tool** that emits *only aggregate
shape statistics* — sample counts per type, date range per type, source count and identity class,
sample-duration histograms, inter-sample-interval histograms, metadata-key frequency — and **no
values, no dates beyond month granularity, no identifiers**. Maintainers and volunteers run it
and paste the output into an issue; the generator is tuned to match. This is how we get realism
without ever handling health data.

---

## Destination test doubles and contract testing

| Destination | Double | Real-thing testing | Runs where |
|---|---|---|---|
| Arbitrary REST endpoint | **Scriptable local HTTP server** in-repo: programmable status, latency, body, headers, chunked/gzip, redirects, 401-then-200, `Retry-After`, connection reset mid-body, self-signed TLS, HTTP/2 and HTTP/1.1. Records every request for assertion. Must run on macOS **and Linux** with no container runtime. | Same server *is* the real thing for our purposes — the contract is HTTP | L4, every PR |
| MQTT | Ephemeral **real Mosquitto broker** — `brew install mosquitto` on macOS runners, container on Linux. No mock. | QoS 0/1/2, retained messages, last-will, persistent session with `clean_start=false`, TLS with a test CA, client-certificate auth, broker restart mid-publish, topic templating, 256-byte and 64 KB topics | L4, every PR (macOS via Homebrew; **Docker is not available on GitHub macOS runners** — see § CI reality) |
| Home Assistant | **Real HA in a container** on a Linux runner, at two pinned versions: current stable and oldest-supported | Long-lived access token; create entities via REST and via MQTT discovery; **read the entity back** and assert `unit_of_measurement`, `device_class`, `state_class` (statistics silently do not work without `state_class`) and `state` precision | L4, nightly + pre-release |
| S3-compatible object storage (if in scope) | MinIO container | Multipart upload, resume, 403 on expired credentials | L4, nightly |
| Dropbox / Google Drive | **No emulator exists.** Recorded-fixture (VCR-style) tests of our HTTP layer against captured interactions, with fixtures committed and reviewable | Nightly **canary** against a real account in a protected environment; manual pre-release checklist | L4 nightly (credentialed) + manual |
| iCloud Drive | **No emulator, no container, no Simulator fidelity.** | Device-only, manual, per release. Conflict resolution and "not signed in" cases explicitly on the manual checklist | L6/L7 manual |
| Calendar | `EKEventStore` behind the C4 seam; local calendar on a Simulator for L5 | Device-only for shared/CalDAV calendars | L3 + manual |
| Our own documented schema (companion server, HA integration) | **Machine-readable schema** (JSON Schema / OpenAPI) committed in-repo; every emitted payload validated against it in L1 | Consumers test against the same published schema — that is the contract | L1, every PR |

### Detecting that a real upstream has broken us, without shipping a broken release

1. **Canary jobs** (QA-22): a nightly workflow replays the same interactions against the *real*
   Home Assistant release channel, the real Mosquitto release, and the real cloud APIs. On
   divergence it opens or updates a single tracking issue and posts to the maintainer channel. It
   **must not** be a required PR check — it is credentialed and inherently flaky — but it **is** a
   release gate: no release ships if a canary has been red for more than 24 hours without a
   dispositioned explanation.
2. **Upstream version pinning with an explicit support policy**: the PRD declares which Home
   Assistant versions and broker versions are supported. Contract tests run against the oldest
   supported and current stable. Anything outside the declared window is documented as
   unsupported rather than silently broken.
3. **Schema-first for our own contract**: because consumers validate against a published schema,
   an accidental breaking change to our output fails our own L1 tests before it reaches anyone.
4. **Field detection** for what canaries cannot cover: per-destination failure counters and
   reason codes reported in the in-app diagnostics screen (C9), so a user's bug report contains
   the reason code rather than "it stopped working".

---

## Correctness properties and invariants

These are the invariants the PRD should assert. They are stated as properties over generated
inputs, verifiable with property-based and model-based testing at L2, and they require **no
device**. A single stateful model — commands `{insert, delete, retro-insert, export, kill,
resume, revoke-auth, change-time-zone, destination-fail, destination-timeout-after-commit}`
over a model of (store, anchor, destination) — checks most of them at once and is, in my
judgement, the highest-value test asset in the project.

| ID | Property | Precise statement | Notes |
|---|---|---|---|
| **P1** | Round-trip fidelity | For every format *f* with a declared lossless contract: `decode_f(encode_f(S)) ≡ S` for all sample sets *S*. For lossy formats, a projection π_f is **documented** and `π_f(decode_f(encode_f(S))) ≡ π_f(S)` | JSON is expected lossless; CSV and GPX are lossy. The lossiness table is a PRD deliverable, not an implementation detail |
| **P2** | Idempotency of re-export | Exporting the same scope twice yields byte-identical file output, and at a destination honouring idempotency keys leaves destination state unchanged: `apply(apply(D, E), E) = apply(D, E)` | Requires C7 (determinism) |
| **P3** | No loss under interruption | For every fault point *k* ∈ C6 seams: `delivered(run_killed_at(k) ⨟ resume) ⊇ scope(S)` | At-least-once. This is the guarantee we can actually make |
| **P4** | No duplication at the destination | For destinations supporting idempotency keys, each `(recordIdentity, destination)` appears with multiplicity exactly 1 after any kill/resume sequence. For append-only destinations, duplicates are possible **by construction** and must be (a) detectable via a stable record key and (b) documented | **We must not claim exactly-once against an arbitrary REST endpoint.** State the honest guarantee |
| **P5** | Monotonic anchor progression | The persisted anchor advances only after durable acknowledgement of every record in the batch. For all interleavings of (deliver, ack, persist, fail, kill): `implied_delivered(anchor) ⊆ acknowledged`, and the anchor never regresses across restart or app upgrade | The one property that, if violated, silently loses data forever |
| **P6** | Delta/full equivalence (completeness) | For any sequence of mutations and delta exports, `⋃ delta_i ≡ full_export(final_state)` over the same scope | The property that catches FIX-M01 (retroactive inserts) being missed |
| **P7** | Deletion propagation | Every `HKDeletedObject` in an anchored batch yields exactly one deletion record downstream, **or** exactly one "cannot represent deletion" diagnostic naming the destination | Never silently dropped |
| **P8** | Determinism and locale invariance | Same input + config ⇒ identical bytes across runs, process restarts, `arm64`/`x86_64`, and any `Locale`/`TimeZone`/`Calendar` set as system default | Catches dictionary ordering, hash seeding, and locale leakage into machine output |
| **P9** | Order independence | Aggregation and dedup results are independent of the order in which samples are supplied (where we claim so) | Catches accidental dependence on query result ordering |
| **P10** | Aggregation conservation | For cumulative types, `Σ bucket_totals = total(range)` modulo the documented overlap and split policy; where a sample is split across buckets, the parts sum to the original within the declared tolerance | Also catches double-counting across FIX-S01 |
| **P11** | Redaction / no-leak | For all sample sets containing canary values and all log levels below an explicit debug flag, no emitted log line, trace span, span attribute, metric label, crash breadcrumb, filename or notification body contains a health value or a sample identifier | Makes the security engineer's requirement executable. Uses a taint corpus of improbable canary values |
| **P12** | Bounded resource use | Peak resident memory is O(1) in corpus size and ≤ the declared ceiling, for every format, at T0/T1/T2 | Streaming, not accumulate-then-write |
| **P13** | State migration soundness | For every persisted-state version *v*: `load(save_v(x))` succeeds and preserves semantics; unreadable or forward-incompatible state produces a recoverable, user-visible error and **never** a silent reset to a zero anchor | A silent reset means a full re-export: duplicate data, battery, and possibly the user's API quota |
| **P14** | Crash consistency of on-disk state | After any single-point failure, persisted state equals either the pre-write or post-write value — never a torn intermediate, never zero-length | Verified with a fault-injecting filesystem layer |
| **P15** | Instant invariance under zone change | Changing the device time zone changes no exported UTC instant; only presentation changes | Catches storing wall-clock instead of instants |
| **P16** | No egress beyond configured destinations | For any configuration, the set of network endpoints contacted is exactly the configured destinations (plus explicitly declared OS services) | Testable at L3/L4 by asserting on the injected network layer; also a security requirement |

---

## Non-functional verification

### Performance

**Precondition on the architect (QA-24):** every performance NFR must be stated as
`(workload, device, OS version, metric, threshold, percentile)`. "Fast delta export" is
unverifiable; "a delta export of 10,000 samples to a local REST endpoint completes in ≤ 5 s at
p95 on an iPhone 13 running iOS 26" is. I will reject any NFR not in that form at the Stage 2
review, because it cannot be gated.

- **Device performance tests** use XCTest's `measure(metrics:)` with `XCTClockMetric`,
  `XCTCPUMetric`, `XCTMemoryMetric`, `XCTStorageMetric` and `XCTApplicationLaunchMetric` —
  XCTest-only, no Swift Testing equivalent [16][17][18].
- **Baselines are committed JSON, not Xcode's baseline mechanism.** Xcode stores baselines per
  device configuration in the project file, which is opaque to review and hostile to forks. We
  commit `median of N=7` figures per (device, OS, workload) and compare in a script. Gate:
  regression > 20% versus the committed baseline on the reference device fails the pre-release
  job; > 10% opens a warning annotation.
- **Simulator performance numbers are advisory only.** They are useful for catching a 10×
  algorithmic regression and useless for anything finer.

### Memory ceilings

- L2 property P12 (algorithmic: O(1) in corpus size) runs everywhere, including Linux, and is
  the primary defence.
- The *absolute* ceiling can only be verified on device, because the hard limit is imposed by the
  OS on background tasks and extensions. Device test: run T1 to a file destination and to a
  network destination, assert peak footprint below the declared ceiling.
- Field verification: MetricKit `applicationExitMetrics.backgroundExitData` —
  `cumulativeMemoryResourceLimitExitCount`, `cumulativeMemoryPressureExitCount`,
  `cumulativeAppWatchdogExitCount`, `cumulativeBackgroundTaskAssertionTimeoutExitCount` and
  `cumulativeSuspendedWithLockedFileExitCount` [19][20]. That last counter is worth calling out:
  it fires when the app is suspended while holding a SQLite or file lock [20], which is precisely
  the failure mode a mid-export suspension would produce. **Gate: zero non-normal background
  exits attributable to our export path across the beta cohort before a release advances.**

### Energy and battery

**This cannot be automated to a gate. Saying otherwise would be a lie.** What we will do:

1. A **manual energy protocol** executed once per release candidate and recorded in the release
   issue: fixed device, fixed starting charge, airplane-mode-off, fixed workload (T1 export ×3
   over 24 h), measured with Instruments' energy log on device and `powermetrics` on macOS.
   Numbers recorded, trend tracked release over release.
2. **Field metrics**: MetricKit CPU, cellular-condition, location-activity and application-time
   metrics [19], plus Xcode Organizer's energy metrics from the TestFlight and release cohorts.
3. **Design-time constraints instead of tests**: bounded work per background wake, no polling, no
   location use unless a route export demands it, network batching. These are Stage 2 constraints
   whose *presence* is checkable in review even when their effect is not measurable in CI.
4. Honest statement for the PRD: **battery impact is detected in the field, not in CI.** A
   battery regression is found by users and by Organizer data, and the mitigation is a fast
   rollback path (phased release), not a pre-release gate.

### Security requirements (making the security engineer's work verifiable)

| Security requirement | How it becomes a test |
|---|---|
| Secrets in Keychain with a stated accessibility class | Runtime assertion of the item's `kSecAttrAccessible*` attribute; device test for `...ThisDeviceOnly` semantics after restore |
| No secret ever in an export, a log, a trace, a crash report or a filename | P11 with a taint corpus; plus a `strings` scan of the release binary for canary values |
| TLS: no ATS exceptions except those enumerated and justified | CI check parses `Info.plist` and fails on undeclared exceptions |
| Certificate/CA behaviour is explicit | Negative test against a local MITM proxy with an untrusted root: connection must fail closed, with a distinguishable error surfaced to the user |
| No data written outside the app container | L3 assertion on the injected filesystem layer; device test enumerates the container after a run |
| Privacy manifest is accurate | CI check that `PrivacyInfo.xcprivacy` declares zero tracking domains and all required-reason API usage; any new dependency without a manifest fails the build |
| No unexpected network egress | P16 |
| Dependency and secret hygiene | CI gates below |

---

## Definition of Done and CI quality gates

### Definition of Done for a change

A change is done when **all** of these hold. This is a checklist in the PR template, not a vibe.

1. The requirement or issue is linked and its acceptance criterion is restated in the PR body.
2. Builds clean for every shipped platform with warnings-as-errors and Swift 6 strict
   concurrency. No new `@unchecked Sendable`, `@preconcurrency`, `nonisolated(unsafe)` or
   `@retroactive` conformance without a linked ADR.
3. New behaviour has a test **at the lowest layer that can catch it** (a UI test for a
   serialisation bug is not acceptable).
4. Bug fixes include a regression test that demonstrably fails before the fix. The PR states
   which test and that it was observed failing.
5. Public API is documented (DocC); user-visible changes have a CHANGELOG entry.
6. All new user-facing strings are in the string catalogue with translator comments; no
   hardcoded user-facing strings.
7. New or changed screens pass the automated accessibility audit and have been checked at the
   largest Dynamic Type size.
8. Data-format or persisted-state changes ship a migration **and** a migration test using
   committed fixtures from the previous released version.
9. New log/telemetry statements are reviewed against the redaction rules (P11).
10. No new dependency without a licence check, a maintenance assessment and an ADR.
11. If the change can only be validated on hardware, the device smoke checklist is completed and
    the result recorded in the PR by a human who names the device and OS version.

### CI tiers and gates

Structural constraint (QA-27): **every required check must pass for a pull request from a fork,
with no secrets and no self-hosted runner.** Otherwise external contribution is impossible.

| Tier | Trigger | Runner | Contents | Budget |
|---|---|---|---|---|
| **T0** | Every push | `ubuntu-latest` (cheap) | Core package build + L1 unit + L2 property tests **on Linux**; `swift format lint --strict --recursive` [21]; SwiftLint strict incl. `analyze` on changed files [22]; dependency audit (Dependabot alerts, Swift ecosystem [23][24][25]); licence allowlist check; secret scan (push protection + gitleaks); link/markdown lint; DocC build | ≤ 6 min |
| **T1** | Every PR (required checks) | one `macos-*` runner | Build all platform targets; L1–L4 tests on one Simulator (current iOS, iPhone); L5 key-screen UI + accessibility audits; Mosquitto via Homebrew for MQTT contract tests; coverage collection | ≤ 15 min, `cancel-in-progress` on force-push |
| **T2** | Merge queue + nightly | `macos-*` + `ubuntu-latest` | Full Simulator matrix (iOS current and current−1, iPadOS, macOS build+test, watchOS build+test); container contract tests (Home Assistant ×2 versions, MinIO) on Linux; full L5 accessibility + pseudo-locale + RTL screenshot sets; upstream canaries; mutation testing on critical modules (periodic) | ≤ 60 min |
| **T3** | `workflow_dispatch`, release tags, weekly | **self-hosted** Mac + physical iPhone + Apple Watch, protected environment | L6 device tests; real HealthKit read; background delivery observation; performance baselines; T2 corpus; energy protocol; TestFlight upload | Hours; never on fork PRs |

**Self-hosted runner security constraint (QA-28):** a self-hosted runner must never execute code
from a fork pull request. It runs only on `workflow_dispatch`, on tags, and on a protected
environment requiring maintainer approval. This is non-negotiable — the alternative is arbitrary
code execution on a machine holding signing keys and a real health store.

### Coverage policy — the honest view

**A single global coverage percentage is a bad gate for this product**, and I would rather say so
now than defend a number later. The reason is structural: the least coverable code (the HealthKit
adapter, background scheduling, platform glue, UI) is also the riskiest, so a global threshold
pushes contributors to write tests for trivially coverable code in order to move the number. That
is worse than no gate, because it costs effort and buys false confidence.

Policy instead:

1. **Measure and publish** coverage on every T1 run (`xcodebuild -enableCodeCoverage`, exported
   via `xcresulttool`), with a PR comment showing the delta. Visibility, not veto.
2. **Gate on designated critical modules** — transformation, serialisation, unit conversion,
   calendar arithmetic, anchor/checkpoint state machine, retry policy, redaction — at **≥ 90%
   line coverage**, and require **100% of the anchor state machine's transitions** to be
   exercised (an explicit transition-coverage assertion, not a line count).
3. **Gate on patch coverage**: ≥ 80% of *changed* lines covered, with an explicit,
   maintainer-approved waiver path for platform glue.
4. **Explicitly exclude from the number**: HealthKit adapter, SwiftUI view bodies, generated
   code. Excluding them is honest; including them and then gaming them is not.
5. **Mutation testing** on the critical modules on a periodic (not per-PR) schedule as a check on
   test *quality*, since coverage measures execution and not assertion.

### Flakiness policy

A flaky test is a bug against the person who wrote it. Any test that fails intermittently is
quarantined (tagged and skipped, with an issue) within one business day. Flake rate is tracked
across the last 20 nightly runs, and **a release does not ship with a flake rate above 1%** —
because a suite people do not trust is a suite people rerun until green, which is the same as
having no suite.

### Release and beta process

- Semantic versioning; release branch; signed, annotated tags; generated release notes from the
  CHANGELOG; reproducible-as-possible builds.
- **Beta via TestFlight** (verified limits [26][27][28]): up to **100 internal testers** (must be
  App Store Connect users, 30 devices each) and up to **10,000 external testers** by email or
  public link, with tester criteria and an enrolment cap settable on the link. The first build of
  each version for external testers requires **Beta App Review**. **Builds expire 90 days after
  upload** — no extensions.
- **The 90-day expiry sets our release cadence**: a beta must ship at least every 60 days or the
  external cohort silently loses the app. For an OSS project with volunteer maintainers, this is
  a real operational risk, and the PRD should state the cadence commitment.
- **Running an OSS beta cohort:** recruit via the repo, the release notes and the self-hoster
  communities (Home Assistant forum, r/homeassistant, r/selfhosted) using a public TestFlight
  link with criteria set. Publish, alongside the link, exactly what the beta build reports and
  what it does not — a beta cohort for a health app that is not explicit about telemetry will not
  recruit, and should not.
- **Contributors are not testers.** A documented, CI-verified *build from source* path (ad-hoc /
  personal-team signing, no App Store Connect access needed) is required, because most
  contributors will not and should not need to be added to an Apple team. QA-30.
- **Release gate checklist:** T0–T3 green; canaries green in the last 24 h; device smoke on ≥ 2
  iPhone classes and, if watchOS ships, one Watch; **upgrade test from the previous released
  version using a migrated real-shaped store**; energy protocol recorded; zero open P0/P1;
  localisation completeness at or above the declared threshold for shipped languages;
  accessibility audits clean; performance baselines within tolerance.
- **Phased release** on the App Store, with a 72-hour observation window on crash, hang and
  background-exit metrics before advancing, and a documented rollback decision owner.

---

## CI reality for OSS on Apple platforms (with current costs, cited)

### GitHub Actions

- **Standard GitHub-hosted runners are free for public repositories** — macOS included [10][11].
  This is the single most important economic fact for this project and the strongest argument for
  keeping the repo permanently public.
- **Larger runners are always billed, even on public repositories** [10]. So we use standard
  runners only.
- **If the repo were private**, macOS standard runners are **$0.062/min** — roughly 10× Linux at
  $0.006/min [10][29]. Included minutes are 2,000/month on Free and 3,000 on Pro/Team [10][29].
  Worked example: a 15-minute macOS PR job × 40 pushes/week ≈ 2,600 min/month ≈ **$161/month**,
  and a single run costs about **$0.93**. Free on a public repo; a real bill otherwise.
- **Concurrency, not price, is the practical constraint**: macOS jobs are capped at **5
  concurrent** on Free/Pro/Team plans. A wide macOS matrix will queue. Hence one macOS job on
  PRs and the matrix at night.
- **No Docker on GitHub-hosted macOS runners.** Nested virtualisation is unsupported —
  `kern.hv_support` is 0, so Docker Desktop, Colima and Apple's `container` all fail
  [30][31][32]. This is why MQTT contract tests use Homebrew Mosquitto natively on macOS, and why
  Home Assistant contract tests must run on a Linux runner against a Linux build of our core
  package. **That, in turn, is why constraint C1 (Linux-buildable core) is not a purity
  preference — it is what makes container-based contract testing affordable at all.**
- Cost-control practice regardless: `concurrency: cancel-in-progress`, a merge queue so macOS
  minutes are not burnt on every rebase, aggressive caching of SPM dependencies and DerivedData,
  and path filters so documentation-only PRs never touch a Mac.

### Xcode Cloud

- **25 compute hours/month included** with Apple Developer Program membership ($99/yr); then
  **100 h for $49.99/mo, 250 h for $99.99/mo, 1,000 h for $399.99/mo, 10,000 h for
  $3,999.99/mo** [33][34].
- 25 hours ≈ 100 fifteen-minute runs per month. That is nowhere near PR volume, but it is
  comfortable for the **release and TestFlight path**, which is exactly where Xcode Cloud earns
  its keep: it handles signing and App Store Connect distribution without us storing certificates
  in a CI secret store.
- **Recommendation:** Xcode Cloud for release/TestFlight workflows only, funded by the membership
  we need anyway. GitHub Actions for everything else.

### Self-hosted

- One Apple-silicon Mac mini as a self-hosted runner, with a physical iPhone and an Apple Watch
  attached, is the only realistic way to run L6. GitHub bills nothing for self-hosted minutes
  today [10]; note that an announced per-minute platform charge for self-hosted runners was
  postponed [35] — **treat future self-hosted pricing as uncertain**.
- Subject to the fork-PR prohibition in QA-28. Also needs: an auto-logging-in user account for
  Simulator and device access, unattended device unlock, and a documented recovery procedure for
  when the Watch inevitably falls off the network.

### What this setup cannot cover

Stated plainly for the PRD:

1. Any real HealthKit store, at all, in hosted CI.
2. Background wake and any multi-day behaviour.
3. watchOS on-wrist behaviour, and any behaviour requiring a Watch paired to an iPhone with real
   history.
4. Energy and thermals.
5. iCloud Drive, and OAuth flows to Dropbox/Google Drive.
6. Older hardware (A12/A13-class devices), where our performance NFRs are most likely to fail.
7. Locale/keyboard/region combinations at scale.
8. App Store review outcomes.
9. Multi-week soak.

**No affordable OSS device farm exists** for this workload. The honest answer is: one
maintainer-owned device set on a self-hosted runner, plus a **community device matrix** (QA-29) —
a scripted, copy-pasteable checklist that volunteers run on their own hardware, whose results are
recorded in a tracked file with device, OS version, date and outcome. It is not a substitute for
a device farm. It is what we have, and being explicit about that is better than implying coverage
we do not have.

---

## Accessibility and localisation verification

### Accessibility

- **Automated audits** (verified API): `performAccessibilityAudit(for:_:)` on `XCUIApplication`,
  available since Xcode 15 / iOS 17, covering audit types `contrast`, `elementDetection`,
  `hitRegion`, `sufficientElementDescription`, `dynamicType`, `textClipped` and `trait`. The test
  fails automatically when issues are found; false positives are suppressed via the issue-handler
  closure [36][37][38].
- **Coverage requirement**: every primary screen **in every state** — empty, loading, partial,
  error, permission-denied, permission-limited, first-run — not just the happy path. Empty and
  error states are where accessibility regressions hide, and this app has an unusual number of
  them.
- **Suppressions are code review**: every ignored audit issue must carry a comment and an issue
  link. An audit suite with a broad ignore closure is theatre.
- **Dynamic Type**: UI tests at content sizes up to AX5, plus Bold Text, Reduce Motion, Reduce
  Transparency, Increase Contrast, Differentiate Without Colour, and Dark Mode. `textClipped` and
  `hitRegion` audits catch most truncation and target-size failures mechanically.
- **Semi-automatable**: assert via the accessibility tree that every actionable element has a
  non-empty label that is not the same as its value, has the correct trait, and that
  `accessibilityElements` order matches reading order. This catches most VoiceOver defects
  without a human.
- **Manual, per release, recorded**: one full VoiceOver pass over the primary flows (onboarding,
  granting permission, configuring a destination, reading a failure). Plus one pass each for
  Switch Control, Full Keyboard Access and Voice Control on the primary flows only. State
  honestly in the PRD: the VoiceOver *experience* is not automatable; only its preconditions are.

### Localisation

- **String catalogues** (`.xcstrings`) as the single source; CI fails on any hardcoded
  user-facing string (lint rule) and on stale or missing entries for shipped languages.
- **Pseudolocalisation** in UI tests via launch arguments (`-AppleLanguages`, `-AppleLocale`):
  a double-length accented pseudo-locale to catch truncation, and a right-to-left pseudo-locale to
  catch layout that assumes LTR. This finds the majority of localisation defects with no
  translators involved and is therefore the highest-value localisation gate for an OSS project.
- **RTL**: a real RTL language (Arabic or Hebrew) in the T2 screenshot set, with the accessibility
  audit run in that locale.
- **Formatting split, asserted both ways** (this is the same invariant as P8, from the other
  side): *display* must respect locale for numbers, dates, units and measurement systems;
  *machine output* must be locale-invariant. Both directions get tests — a locale-formatted CSV
  is a data-corruption bug, and a hard-coded English date in the UI is a localisation bug.
- **Units**: display must respect the user's unit preferences; exported data uses declared
  canonical units with the unit named in the output. Test both.
- **Artifacts**: T2 publishes a screenshot matrix (locale × Dynamic Type size × light/dark) as
  CI artifacts, so any reviewer can eyeball it without a local build. Cheap, and unusually
  effective for a distributed volunteer project.
- **Completeness gate**: a language ships only when its catalogue is ≥ 95% translated for
  user-facing strings and its pseudo-locale and RTL tests pass. Partial translations are worse
  than English for a health app, because a half-translated permission explanation is a consent
  problem, not a polish problem.

---

## Requirements I own

| ID | Requirement | Priority | Rationale | How we verify |
|---|---|---|---|---|
| QA-01 | HealthKit access must be abstracted behind a seam such that the entire export pipeline is exercisable with the HealthKit framework not linked. | **Must** | HealthKit is absent on macOS [1][2] and unpopulatable in the Simulator [3][4][5]; without this, nothing downstream is testable in CI. | The core package and its L1–L4 suite build and pass on Linux; HealthKit does not appear in the core package's linked frameworks. |
| QA-02 | The pipeline's domain model must be project-owned value types constructible from committed text fixtures, with no HealthKit types crossing the seam. | **Must** | Fixtures must be reviewable in a PR and generatable at volume. | A fixture file loads into the domain model in a test with no HealthKit import; a compile-time check asserts no HealthKit symbol in the core module's public interface. |
| QA-03 | Clock, calendar, time zone and locale must be injected throughout the pipeline. | **Must** | Every time-related edge case (FIX-T01…T15) is otherwise unreachable. | Lint rule fails the build on direct use of `Date()`, `Calendar.current`, `TimeZone.current`, `Locale.current` outside a reviewed allowlist; DST and leap-year tests pass with a synthetic clock. |
| QA-04 | A synthetic fixture corpus must exist at three tiers: T0 ≤ 200 committed samples, T1 = 10,000,000 generated samples across ≥ 60 types over ≥ 5 years from ≥ 6 sources, T2 = 50,000,000 over 15 years. | **Must** | "Large store" must be a number to be falsifiable. | T1 generates reproducibly from a committed seed in ≤ 10 min on a reference Mac; the whole pipeline completes over T1 in a nightly job; T2 runs in the device/weekly tier. |
| QA-05 | Every edge case in the FIX-* catalogue must have at least one fixture and one test, and the catalogue must be a committed, versioned file. | **Must** | This catalogue is where the real bugs are; if it is prose in a PRD it will rot. | A test enumerates the catalogue file and fails if any ID has no corresponding test; coverage of the catalogue is reported in CI. |
| QA-06 | No real human health data may enter the repository, CI logs, CI artifacts, or issue attachments — including maintainers' own. | **Must** | Irreversible privacy harm; git history is forever. | Secret/PII scanning on every push; a documented incident procedure; fixture files carry a machine-checkable "synthetic" provenance header. |
| QA-07 | Exported output must be byte-deterministic for identical input and configuration, across runs, architectures and system locales. | **Must** | Prerequisite for idempotency (P2), snapshot testing and diffability. | P8: 100 runs on arm64 and x86_64 produce identical SHA-256 digests, with a hostile locale and time zone set. |
| QA-08 | An opt-in store-characterisation tool must emit only aggregate shape statistics (counts, ranges at month granularity, source classes, duration and interval histograms, metadata-key frequencies) with no values and no identifiers, to tune the generator against real-world shapes. | **Should** | The corpus is worthless if it does not resemble real stores; this is the only privacy-safe route to realism. | Output of the tool over the T1 corpus contains zero sample values and zero identifiers, asserted by a test with a taint corpus; at least two real-store characterisations recorded before v1. |
| QA-09 | Fixture provenance and licence must be explicit: every fixture is synthetic, generated by committed code, and carries the generator version and seed. | **Should** | Protects contributors and downstream forks. | CI check that every fixture file has a valid provenance header. |
| QA-10 | A scriptable local HTTP destination double must exist that runs on macOS and Linux without a container runtime, and can produce arbitrary status, latency, headers, body, TLS and connection-failure behaviour, while recording requests for assertion. | **Must** | Docker is unavailable on GitHub-hosted macOS runners [30][31][32]. | Contract tests for the REST destination pass on both `macos-*` and `ubuntu-latest` with no container runtime present. |
| QA-11 | MQTT behaviour must be tested against a real broker (not a mock), covering QoS 0/1/2, retained messages, last-will, persistent sessions, TLS with a test CA, client certificates, and broker restart mid-publish. | **Must** | MQTT semantics are the whole value of the destination; a mock would only test our own assumptions. | An ephemeral broker starts and stops within the test run on both macOS (Homebrew) and Linux (container); all listed cases have tests. |
| QA-12 | Home Assistant integration must be verified against a real Home Assistant instance at two pinned versions (current stable and oldest supported), asserting entity creation and the read-back values of `unit_of_measurement`, `device_class`, `state_class` and state precision. | **Must** | HA statistics silently fail without `state_class`; only a real instance reveals this. | Nightly container job creates entities and asserts read-back; the supported-version window is declared in the PRD and enforced by the test matrix. |
| QA-13 | Every payload we emit for a documented interface must validate against a committed machine-readable schema, and that schema is the published contract for third-party consumers. | **Must** | Gives consumers (companion server, HA integration) a testable contract and catches accidental breaking changes in L1. | Schema validation runs on every emitted payload in unit tests; a breaking schema change fails CI unless accompanied by a version bump and a migration note. |
| QA-14 | The product must expose per-destination "last successful export" and "last failure with reason code" as durable, user-visible state. | **Must** | Silent failure is the defining failure mode of this product class and is not detectable pre-release; this is the only way a user or a bug report can reveal it. | UI test asserts the surface in success, stale and failed states; integration tests assert the state after every simulated failure mode; the reason-code registry is committed. |
| QA-15 | The app must detect and surface its own staleness — "no successful export for longer than the configured interval × N" — without depending on a server. | **Must** | Background delivery is best-effort [7][8]; nothing else will tell the user their data stopped flowing. | Integration test with a synthetic clock: after N missed windows, the staleness state and user-facing notification are produced exactly once, and are cleared by a subsequent success. |
| QA-16 | Delivery semantics must be documented and tested as **at-least-once with a stable idempotency key**, not exactly-once. Where a destination cannot deduplicate, duplication is documented as possible. | **Must** | Exactly-once against an arbitrary REST endpoint is impossible; claiming it would be false. | P3 and P4 over all C6 fault points; the documented guarantee matches the tested behaviour, checked at review. |
| QA-17 | Persisted anchors and checkpoints must never be silently reset. Any anchor invalidation must produce a recoverable, user-visible state and an explicit user or policy decision before a full re-export. | **Must** | A silent reset re-exports years of data: duplicates downstream, battery, and potentially the user's paid API quota. | P13: forced invalidation and forced state corruption produce the user-visible state and no automatic full re-export. |
| QA-18 | Named fault-injection seams must exist at the six points in C6, enabled only in test builds. | **Must** | The interruption invariants are otherwise unassertable. | A test enumerates all seams and asserts each is reachable in a test build; a release-configuration test asserts none are reachable. |
| QA-19 | Properties P1–P16 must each be expressed as an executable property-based or model-based test, with shrinking, seed reporting on failure, and committed counterexample regression cases. | **Must** | These invariants are the product's correctness definition. | Each property maps to at least one named test; each historical counterexample is committed as a fixed-seed regression case; the property library choice is recorded in an ADR with a maintenance-risk assessment (candidates: PropertyBased [39], Exhaust [40], SwiftTestKit [41]; SwiftCheck is legacy). |
| QA-20 | The pipeline must be provably free of health-data leakage into logs, traces, metrics, crash breadcrumbs, filenames and notifications below an explicit debug flag. | **Must** | Resolves the brief's stated observability-versus-privacy tension with a test rather than a promise. | P11 with a canary taint corpus across all log levels; a `strings` scan of the release binary for canaries; a test asserting the debug flag cannot be enabled in a release build. |
| QA-21 | New unit and integration tests must use Swift Testing; XCTest is retained only for UI automation, `XCTMetric` performance tests and Objective-C exception handling. | **Should** | Matches Apple's current guidance and the actual API gaps [16][17][18]. | CI check rejects new `XCTestCase` subclasses outside the UI-test and performance-test targets; interop mode is set explicitly in the test plan. |
| QA-22 | Nightly canary jobs must exercise real upstream services (Home Assistant release channel, broker releases, cloud APIs) and open a tracking issue on divergence. Canaries are release gates, never required PR checks. | **Must** | The only way to learn that a third party broke us before our users do. | A deliberately induced divergence causes an issue to be filed within one nightly cycle; the release checklist blocks on a canary red for > 24 h. |
| QA-23 | Every performance NFR must be expressed as (workload, device, OS version, metric, threshold, percentile), and each must have a corresponding on-device measurement with a committed baseline. | **Must** | An NFR that is not a number on a named device cannot be gated. | Each NFR maps to a device test; pre-release job fails on > 20% regression against the committed baseline; NFRs without a mapped test are rejected at Stage 2 review. |
| QA-24 | Peak memory must be O(1) in corpus size for every export format, and below a declared absolute ceiling on device. | **Must** | Background execution memory limits are hard kills, and jetsam mid-export is a data-integrity event, not just a crash. | P12 at T0/T1/T2 in CI; device test asserts the absolute ceiling; field gate of zero memory-limit background exits in the beta cohort via MetricKit [19][20]. |
| QA-25 | Energy impact must be measured by a documented manual protocol once per release candidate and monitored in the field; it is explicitly **not** a CI gate. | **Should** | Automating an energy gate is not possible; pretending otherwise is worse than admitting it. | A recorded energy measurement exists in each release issue with device, workload and numbers; field CPU/energy metrics reviewed before a phased release advances. |
| QA-26 | Every primary screen, in every state including empty, error, permission-denied and permission-limited, must pass the automated accessibility audit; each suppressed issue must carry a justification and an issue link. | **Must** | Another specialist is writing accessibility requirements; they need a gate or they are aspirations. | `performAccessibilityAudit` [36][37][38] across the screen/state matrix in T1 (key screens) and T2 (all); a test counts suppressions and fails if any lacks a linked issue. |
| QA-27 | Localisation must be verified by a pseudo-locale (double-length, accented) run, an RTL run, a no-hardcoded-strings lint, and a catalogue-completeness check; a language ships only at ≥ 95% translated. | **Must** | Catches most localisation defects without translators; a half-translated consent screen is a consent defect. | T2 pseudo-locale and RTL UI tests pass with no clipping; lint fails on hardcoded user-facing strings; completeness check gates the shipped-language list. |
| QA-28 | Every required PR check must pass for a fork pull request with no secrets and no self-hosted runner. Self-hosted runners must never execute fork PR code; they run only on `workflow_dispatch`, tags, or a protected environment with maintainer approval. | **Must** | Otherwise external contribution is impossible, or the device runner holding signing keys and a real health store is an arbitrary-code-execution target. | A test fork PR passes all required checks; workflow configuration is asserted by a CI policy check (no `pull_request` trigger on self-hosted jobs). |
| QA-29 | A community device matrix must exist: a scripted, copy-pasteable manual checklist, with results recorded in a committed file including device, OS version, date and outcome. | **Should** | No affordable device farm exists for Apple platforms; volunteer coverage is the only alternative and must be structured to be worth anything. | The checklist exists, is executable by someone who is not a maintainer, and has ≥ 5 recorded results across ≥ 3 device classes before v1. |
| QA-30 | A build-from-source path must exist and be CI-verified, requiring no Apple Developer Program membership and no App Store Connect access. | **Must** | Contributors must be able to build and test without being added to an Apple team; it is also the fallback distribution channel for people who will not use TestFlight. | A CI job builds the app with ad-hoc/personal-team signing from a clean checkout following only the README; the job runs on every PR. |
| QA-31 | The release gate checklist (T0–T3 green, canaries green, device smoke, upgrade-from-previous-release test with a migrated store, energy record, zero P0/P1, localisation and accessibility gates, performance baselines) must be enforced as a checklist in the release issue template. | **Must** | Release discipline that lives in someone's head does not survive a volunteer project. | No release tag is created without a completed checklist; the checklist is part of the repo. |
| QA-32 | Flaky tests must be quarantined within one business day, and no release ships with a suite flake rate above 1% over the last 20 nightly runs. | **Should** | A suite people rerun until green is equivalent to no suite. | Flake rate computed from nightly history and published; quarantine issues tracked with an owner and an expiry. |
| QA-33 | Coverage is published for all code, gated at ≥ 90% line coverage on designated critical modules, 100% transition coverage on the anchor/checkpoint state machine, and ≥ 80% patch coverage on changed lines. No global-percentage gate. | **Should** | A global number in this codebase incentivises testing the wrong code; see § Coverage policy. | Coverage extracted per module from the result bundle; the critical-module list is committed and reviewed; the state-machine transition assertion is an explicit test. |
| QA-34 | Real-device HealthKit verification must be part of the release gate: a manual, scripted device pass on a store containing at least two years of real data from at least three sources, executed on named hardware and recorded. | **Must** | The only way to discover that our seam's assumptions about HealthKit are wrong. | A completed, signed-off device pass recorded in each release issue, naming device, OS and store characteristics. |
| QA-35 | Long-run delivery correctness must be verified by a soak protocol: ≥ 21 continuous days on a real device with a scripted daily diary, reconciling exported record counts against store counts at the end. | **Must** | "Still works after three weeks" cannot be unit tested and is the failure mode users care most about. | A completed soak record per minor release with a reconciliation result; any discrepancy is a P1 by definition. |
| QA-36 | We will not automate: background wake timing, multi-week continuity, Apple Watch data generation, Apple's permission UI, cloud-provider OAuth, iCloud Drive semantics, energy. Each is assigned a named alternative verification (manual protocol or field metric) recorded in the PRD. | **Must** | Naming what we will not do prevents both wasted effort and false confidence. | Each item in the list has a named owner and a named alternative; reviewed at every release. |
| QA-37 | Beta distribution runs through TestFlight with an internal group (maintainers) and an external public-link cohort with criteria set; a beta build must be published at least every 60 days. | **Should** | TestFlight builds expire at 90 days with no extension [26][27][28]; a lapsed cohort has to be rebuilt from scratch. | A build exists in the external group with > 30 days remaining at all times, checked by a scheduled job against App Store Connect. |
| QA-38 | No test-only code (fake source, fault seams, fixture loading, debug logging flag) may be present in a release build. | **Must** | It would be an attack surface on health data and a bypass of the redaction guarantees. | Release binary symbol scan in the release gate; a release-configuration test asserts the seams and the debug flag are unreachable. |
| QA-39 | Won't have (v1): a hosted device farm, automated energy gating, exactly-once delivery guarantees, automated verification against Dropbox/Google Drive/iCloud production services on every PR, automated VoiceOver experience validation. | **Won't** | Not affordable, not possible, or not honest. Recording them as explicit non-goals prevents them being assumed. | These appear in the PRD's non-goals section and in § What we deliberately will not automate. |

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Stage 2 does not honour the HealthKit seam (C1/QA-01), and HealthKit types leak into the pipeline. | Medium | **Critical** — the entire automated strategy collapses; we become a manual-testing project. | Make the Linux build of the core package a required CI check from the first commit, so a violation fails immediately rather than at Stage 4. Raise it as a blocking finding at the Stage 2 review. |
| Silent background failure ships and users lose weeks of data before anyone notices. | **High** | High | QA-14/QA-15 (in-app last-success and staleness detection), the soak protocol (QA-35), MetricKit background-exit monitoring [19][20], and a reason-code registry so bug reports are diagnosable. Accept that pre-release detection is impossible and invest in field detection. |
| The synthetic corpus does not resemble real stores; tests pass and real users' exports break. | **High** | High | QA-08 store characterisation to tune the generator; QA-34 real-device release gate; every field-reported defect becomes a new FIX-* fixture, permanently. |
| No maintainer-owned device runner materialises, so the L6 tier never runs. | Medium | High | QA-29 community device matrix as the fallback; make the absence explicit in the PRD rather than assuming hardware; scope v1 platforms to what can actually be validated. |
| Anchor/checkpoint bug causes silent data loss or a silent full re-export. | Medium | **Critical** — irreversible for the user's downstream data, and possibly expensive if their endpoint bills per request. | P5, P6, P13, P14 with model-based testing; 100% transition coverage on the state machine (QA-33); QA-17 forbidding silent resets. |
| An upstream (Home Assistant, broker, cloud API) changes and breaks us post-release. | Medium | Medium | QA-22 canaries; declared supported-version window; schema-first contract for our own interfaces. |
| GitHub's free macOS runner policy changes, or macOS queue times degrade to unusability. | Low–Medium | High | Keep the Linux tier able to run the majority of tests independently (which C1 already gives us); keep the macOS critical path to one job; Xcode Cloud's included 25 h/month as a fallback for the release path [33][34]. |
| Flaky device and UI tests erode trust; the suite gets ignored or disabled. | **High** | Medium | QA-32 quarantine policy with a hard SLA; keep the device tier small and high-signal; never make a flaky test a required check. |
| The property-testing dependency is a small, young, single-maintainer package — abandonment or supply-chain risk. | Medium | Medium | Choose in an ADR with an explicit maintenance assessment; keep the property *definitions* in our own code so the library is replaceable; vendor or pin by commit; Dependabot on the Swift ecosystem [23][24][25] — while noting Swift has no central registry, so advisory coverage is thinner than npm or pip [25]. |
| Test-only seams (fake source, fault injection) leak into a release build. | Low | **High** — a bypass around the health-data protections. | QA-38 symbol scan and release-configuration tests; compile-time exclusion, not runtime flags. |
| Coverage number becomes the goal; contributors test trivial code to move it. | Medium | Medium | QA-33: no global gate, critical-module gates, patch coverage, and periodic mutation testing to check assertion quality rather than execution. |
| watchOS is in scope but effectively unverifiable without a Watch, which most contributors lack. | **High** | Medium | Recommend the PM consider deferring watchOS from v1; if retained, scope it to the narrowest possible surface and state the verification gap in the PRD. |
| Contributor friction: if meaningful tests require a device, external contribution dies. | Medium | High | QA-28 (fork PRs pass all required checks without secrets or hardware) and QA-30 (build from source with no Apple team). These are the requirements that make the project actually open. |
| TestFlight cohort silently expires during a quiet period (90-day build expiry [26][27][28]). | Medium | Low–Medium | QA-37 scheduled check and a 60-day beta cadence commitment. |
| Governance: whoever holds the Apple Developer Program account is a single point of failure for signing, TestFlight and release. | Medium | High | Open question for the PM below; needs a named owner, a documented succession plan, and no unrecoverable secrets. |

---

## Hard constraints that limit the product

Verified platform facts that limit what the product can promise. These are not test-strategy
opinions; they are constraints on the PRD's claims.

1. **HealthKit does not exist on macOS.** `isHealthDataAvailable()` returns `false`; the framework
   links only so multiplatform code compiles [1][2]. A Mac app cannot read the user's Health data
   at all. Whatever the Mac companion does, it does with data that arrived over a transport — and
   that transport is where its tests live. Any PRD claim of "first-class macOS support" must mean
   something other than "reads HealthKit".
2. **The iOS Simulator cannot host a realistic HealthKit store.** Population is manual and GUI-only,
   no sensor or workout data is generated, some entry sheets are broken, and background delivery
   does not function [3][4][5][13][9]. The Simulator verifies UI, not data behaviour.
3. **We cannot forge sample provenance.** Anything we write is attributed to our own app; we can
   never produce a sample that HealthKit reports as coming from an Apple Watch or a third-party app
   [6][2]. Multi-source de-duplication behaviour (FIX-S01) is therefore only ever verified against
   *our* model of HealthKit, never against HealthKit itself, until a real device sees it.
4. **Some data cannot be written at all**, so it cannot be round-tripped through a real store: ECG
   is read-only, Apple-proprietary types such as `appleExerciseTime` and `appleStandHour` raise an
   exception on share authorization, and clinical records cannot be created [12][14][3].
5. **Read denial is invisible to us.** If the user denies read access, queries return only what our
   own app wrote — identical to an empty store [6]. We can *never* assert "we exported everything
   the user has". The strongest honest statement is "we exported everything HealthKit returned",
   and the UI must say so.
6. **Time-bound authorization exists**, and it is the only authorization state we can positively
   detect [6]. History may be clipped without the user remembering they clipped it.
7. **Anchored queries are insertion-ordered.** Completeness over a *date range* is not decidable
   from an anchor. Any "export everything since date D" promise is only sound if built on
   anchor-based delta plus an explicit reconciliation pass.
8. **Background delivery timing is not a contract.** Frequencies are ceilings, `stepCount` is capped
   hourly, delivery is throttled by battery and background budget, and nothing arrives while the
   device is locked with a passcode [7][8]. **The PRD must not contain a latency SLA.** The
   testable form is a measured distribution: "p50/p95 time from sample availability to export,
   measured in the field".
9. **Failing to call the observer completion handler stops all future delivery** [9] — so a single
   bug in error handling silently disables the product until reinstall. This raises the priority of
   QA-15 (self-detected staleness) from nice to essential.
10. **Exactly-once delivery to an arbitrary endpoint is impossible.** At-least-once plus an
    idempotency key is the ceiling.
11. **Leap seconds are not observable** on Apple platforms; the tested property is the absence of
    fixed-length-day assumptions, not the event itself.
12. **Apple Watch purges old data** [2], so the same logical history differs per store, and each
    device has its own store which syncs. "Complete export" is store-relative and device-relative.
13. **No Docker on GitHub-hosted macOS runners** [30][31][32]; container-based contract testing must
    run on Linux, which is only possible if the core package builds on Linux (C1).
14. **Fork PRs cannot have secrets**, so no credentialed test can ever be a required check.
15. **TestFlight builds expire after 90 days**, with no extension and no reactivation
    [26][27][28] — the beta cohort has a decay rate, and the release cadence must outrun it.
16. **No affordable device farm** exists for Apple platforms at OSS budgets. Device coverage is
    maintainer hardware plus volunteers, and the PRD should say that rather than implying a matrix.

---

## Open questions for the PM

1. **Who holds the Apple Developer Program membership and the App Store Connect account?** This
   gates TestFlight, signing, Xcode Cloud and release. It is also a single point of failure that
   needs a named owner and a succession plan. Blocks QA-37 and the release process entirely.
2. **Is the repository permanently public?** The entire CI budget rests on standard GitHub-hosted
   runners being free for public repositories [10][11]. If it might go private, the macOS
   line-item becomes roughly $161/month at the volume modelled above, and the strategy needs
   rework.
3. **Is there any hardware budget** — one Apple-silicon Mac mini, one iPhone, one Apple Watch? If
   no, the L6 device tier does not exist and the PRD must say the product is released without
   automated device verification.
4. **What delivery guarantee are we willing to put in the documentation?** At-least-once with
   idempotency keys, or best-effort? This determines both the design and half the property tests
   (QA-16), and it is a product decision, not a QA one.
5. **Which destinations are in the v1 support matrix, and what is the declared support policy**
   for third-party versions (which Home Assistant releases, which brokers)? This sizes the
   contract-test surface directly.
6. **Is "export completeness" a product promise?** If yes, we need a reconciliation feature — a
   periodic count-based self-audit comparing store counts to exported counts — which is a Stage 2
   design item, not something tests can add later. Given constraint 5 above, I recommend the
   promise be scoped to "everything HealthKit returned to us".
7. **Do we accept any opt-in diagnostics channel at all?** Without one, field detection of silent
   failure reduces to users filing issues, and the brief's stated privacy/observability tension
   resolves in favour of us being blind. My position: opt-in, local-first, with the redaction
   invariant P11 as the enforceable guarantee.
8. **Which platforms are genuinely v1?** Deferring watchOS removes the single largest untestable
   surface in the project. Deferring the Mac companion removes a target that cannot read HealthKit
   at all. Both are legitimate scope decisions; both materially change the risk profile.
9. **Minimum supported OS versions**, which set the Simulator matrix size and therefore the T2 CI
   cost.
10. **Localisation scope for v1** — how many languages, and who translates? The verification cost
    scales with the count, and a 60%-translated language is worse than English here.
11. **Should the app ship a fake/demo data mode in release builds?** It would help support and
    community testing enormously, and it widens the attack surface and contradicts QA-38. Needs a
    product decision.
12. **Confirm the metric-type list for v1**, particularly newer HealthKit areas (medications, state
    of mind, sleep/breathing disturbances). The domain specialist and I need the same list; the
    Simulator's entry path for at least one of these is currently broken [13].

---

## Sources

1. Apple Developer Documentation — `HKHealthStore.isHealthDataAvailable()`.
   https://developer.apple.com/documentation/healthkit/hkhealthstore/ishealthdataavailable()
2. Apple Developer Documentation — About the HealthKit framework (per-device stores, Watch data
   purging, `earliestPermittedSampleDate()`, macOS/iPadOS availability).
   https://developer.apple.com/documentation/healthkit/about-the-healthkit-framework
3. Apple Developer Documentation — Accessing sample data in the Simulator (Health Records sample
   accounts). https://developer.apple.com/documentation/healthkit/samples/accessing_sample_data_in_the_simulator
4. Apple Developer Forums — "Simulating a workout": Apple engineer confirms the Simulator does not
   generate workout data and the WWDC demo was faked.
   https://developer.apple.com/forums/thread/7339
5. Apple Developer Documentation — Setting up HealthKit (`errorHealthDataUnavailable`,
   `errorHealthDataRestricted`, required device capabilities).
   https://developer.apple.com/documentation/healthkit/setting-up-healthkit
6. Apple Developer Documentation — Authorizing access to health data (read denial indistinguishable
   from empty; time-bound authorization; `getEarliestAuthorizedSampleDate(for:)`).
   https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data
7. Apple Developer Forums — "Clarification on HealthKit Observer queries": Apple engineer confirms
   `HKUpdateFrequency` is not guaranteed, `stepCount` is capped hourly, and background budget
   affects delivery. https://developer.apple.com/forums/thread/823699
8. Stack Overflow — HealthKit background delivery when the device is locked (no delivery while
   locked with a passcode; delivery resumes on unlock).
   https://stackoverflow.com/questions/26375767/healthkit-background-delivery-when-app-is-not-running
9. "Background support for HealthKit in iOS" — background delivery requires physical hardware; the
   completion handler must always be called or future deliveries stop.
   https://medium.com/@raajveer/background-support-for-healthkit-in-ios-aaa0c05fb6e3
10. GitHub Docs — GitHub Actions billing (free for public repositories on standard runners; macOS
    $0.062/min; Linux $0.006/min; included minutes by plan; larger runners always billed).
    https://docs.github.com/en/billing/concepts/product-billing/github-actions
11. GitHub — 2026 pricing changes for GitHub Actions ("GitHub Actions will remain free for public
    repositories"). https://github.com/resources/insights/2026-pricing-changes-for-github-actions
12. Apple Developer Documentation — `HKElectrocardiogramType`: ECG samples are read-only; Simulator
    test data is added via Health ▸ Browse ▸ Heart ▸ ECG ▸ Add Data.
    https://developer.apple.com/documentation/healthkit/hkelectrocardiogramtype
13. Apple Developer Forums (WWDC26 Health & Fitness Q&A) — Simulator's breathing/sleep-disturbance
    sample creation sheet cannot be saved. https://developer.apple.com/forums/thread/833092
14. Requesting share authorization for Apple-proprietary types (`appleExerciseTime`) raises
    `NSInvalidArgumentException`: "Authorization to share the following types is disallowed".
    https://www.exchangetuts.com/swift-authorization-to-share-the-following-types-is-disallowed-hkquantitytypeidentifierappleexercisetime-1765558804167171
15. Apple Developer Documentation — Saving data to HealthKit (sample duration restrictions; avoid
    samples ≥ 24 hours; correlation children must not be saved separately).
    https://developer.apple.com/documentation/healthkit/saving-data-to-healthkit
16. Apple — WWDC26 session 267, "Migrate to Swift Testing": UI automation and performance testing
    APIs are XCTest-only; Objective-C exception tests must stay in Objective-C XCTest; incremental
    migration is the recommended strategy. https://developer.apple.com/videos/play/wwdc2026/267/
17. "Swift Testing vs XCTest — Migration Guide (2026)": `XCUIApplication` and `XCTMetric`
    (`XCTClockMetric`, `XCTMemoryMetric`, `XCTCPUMetric`) remain XCTest-only in Xcode 26.
    https://theswiftk.it.com/blog/swift-testing-vs-xctest-migration-guide-2026
18. "Swift Testing: The Framework Replacing XCTest, and What Stays In XCTest" — coexistence in one
    target; `SWIFT_TESTING_XCTEST_INTEROP_MODE`. https://blakecrosley.com/blog/swift-testing-vs-xctest
19. Monitoring app performance with MetricKit (payload structure; `applicationExitMetrics`;
    diagnostics). https://swiftwithmajid.com/2025/12/09/monitoring-app-performance-with-metrickit/
20. `MXBackgroundExitData` reference — `cumulativeMemoryResourceLimitExitCount`,
    `cumulativeAppWatchdogExitCount`, `cumulativeBackgroundTaskAssertionTimeoutExitCount`,
    `cumulativeSuspendedWithLockedFileExitCount` (suspension while holding a file/SQLite lock).
    https://docs.rs/objc2-metric-kit/latest/objc2_metric_kit/struct.MXBackgroundExitData.html
    (mirrors Apple's MetricKit documentation:
    https://developer.apple.com/documentation/metrickit/mxbackgroundexitdata)
21. swiftlang/swift-format — included in the Swift 6+ / Xcode 16+ toolchain, invoked as
    `swift format`; `swift format lint --strict`. https://github.com/swiftlang/swift-format
22. SwiftLint — rule-based linting plus opt-in `swiftlint analyze` using the type-checked AST.
    https://github.com/realm/SwiftLint
23. GitHub Changelog — Swift support for Dependabot updates (Aug 2023).
    https://github.blog/changelog/2023-08-01-swift-support-for-dependabot-updates/
24. GitHub Changelog — Dependabot supports Xcode projects using SwiftPM with `.xcodeproj`
    manifests (Mar 2026).
    https://github.blog/changelog/2026-03-31-dependabot-now-supports-xcode-projects-using-swiftpm-with-xcodeproj-manifests/
25. GitHub Docs — GitHub Advisory Database supported ecosystems: Swift is listed with
    "registry: N/A", i.e. no central registry, so advisory coverage is thinner than for npm or pip.
    https://docs.github.com/en/code-security/concepts/vulnerability-reporting-and-management/github-advisory-database
26. Apple — App Store Connect Help, TestFlight overview (100 internal testers, 10,000 external
    testers, Beta App Review on first build, 90-day build expiry).
    https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/
27. Apple — App Store Connect Help, Invite external testers (public links, tester criteria, tester
    limit 1–10,000).
    https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers
28. TestFlight access and limits summary (30 devices per tester; 90-day expiry with no extension;
    beta review submission limits). https://www.drizz.dev/post/testflight-access
29. Understanding GitHub Actions runner costs in 2026 — per-minute rates, included minutes,
    public-versus-private runner specs.
    https://stacktrack.com/posts/understanding-github-actions-runner-costs-in-2026/
30. GitHub Docs — GitHub-hosted runners reference: "Nested-virtualization is not supported due to
    the limitation of Apple's Virtualization Framework" (arm64 macOS runners).
    https://docs.github.com/en/actions/reference/runners/github-hosted-runners
31. actions/runner-images issue #13505 — request to support Hypervisor.framework on Apple silicon
    runners; GitHub confirms it remains unavailable.
    https://github.com/actions/runner-images/issues/13505
32. actions/runner-images issue #9460 — Docker/Colima cannot start on macOS arm64 runners
    (`HV_UNSUPPORTED`); recommendation is to use Linux agents.
    https://github.com/actions/runner-images/issues/9460
33. Apple — Xcode Cloud overview and pricing: 25 compute hours/month included with Apple Developer
    Program membership; 100 h US$49.99, 250 h US$99.99, 1,000 h US$399.99, 10,000 h US$3,999.99 per
    month. https://developer.apple.com/xcode-cloud/
34. Apple — Get started with Xcode Cloud (subscription plans; Account Holder manages upgrades).
    https://developer.apple.com/xcode-cloud/get-started/
35. GitHub Changelog — reduced pricing for GitHub-hosted runners (Jan 2026); note that the
    announced self-hosted platform charge was subsequently postponed, so future self-hosted
    pricing should be treated as uncertain.
    https://github.blog/changelog/2026-01-01-reduced-pricing-for-github-hosted-runners-usage/
36. Apple Developer Documentation — Performing accessibility audits for your app
    (`performAccessibilityAudit(for:_:)` fails the test automatically when issues are found).
    https://developer.apple.com/documentation/accessibility/performing-accessibility-audits-for-your-app
37. Apple — WWDC23 session 10035, "Perform accessibility audits for your app".
    https://developer.apple.com/videos/play/wwdc2023/10035/
38. `XCUIAccessibilityAuditType` cases in practice — `contrast`, `elementDetection`, `hitRegion`,
    `sufficientElementDescription`, `dynamicType`, `textClipped`, `trait`.
    https://augmentedcode.io/2024/02/26/performing-accessibility-audits-with-ui-tests-on-ios/
39. PropertyBased (x-sheep/swift-property-based) — property-based testing integrated with Swift
    Testing, with automatic shrinking and fixed-seed replay; Swift 6.2 / Xcode 26.
    https://github.com/x-sheep/swift-property-based
40. Exhaust — reflective-generator property testing with Swift Testing and XCTest integration,
    state-machine testing and coverage-guided fuzzing; requires Swift 6.3+ / Xcode 26+.
    https://github.com/nesevis/exhaust
41. SwiftTestKit — composable property-based, stateful, performance and temporal testing for Swift
    Testing and XCTest. https://github.com/swift-developer-tools/swift-test-kit

**Confidence notes.** Items 1–8, 10–12, 14–16, 21, 23–27, 30–34, 36–37 are Apple or GitHub primary
sources. Items 9, 13, 17–20, 22, 28–29, 35, 38–41 are secondary or community sources and are
flagged as such in the text where they carry weight. The claim that no programmatic Simulator
HealthKit population path exists is a verified *absence* rather than a positive citation, and I
would welcome a counterexample. The MetricKit API surface is evolving (a Swift-first
`MetricManager` is reported to supersede `MXMetricManager`); the *counters* cited in item 20 are
stable, but Stage 2 should confirm the current API shape.
