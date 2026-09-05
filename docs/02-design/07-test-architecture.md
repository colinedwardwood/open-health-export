# Test Architecture — Stage 2

**Author:** QA Lead / Test Architect
**Stage:** 2 of 4 (System Design)
**Owns:** R-80 … R-91, and the verification method for every other requirement in the PRD
**Status:** Draft for PM synthesis and adversarial review
**Date:** 2026-09-03

---

## Executive summary

Stage 1 gave me the one thing I asked for: **R-80**, a core that builds and tests on Linux with
HealthKit not linked. Everything in this document is downstream of it, and the two scope
additions since Stage 1 — MQTT (D-04) and the Mac companion receiver (D-14) — were both, in
different ways, attacks on it. I came into this stage expecting to file them as Blockers.

**I am withdrawing all four of my pre-emptive Blockers, because the designs got there first.**
MQTT is quarantined in its own Linux-building package that never enters the core's resolution
graph. The Mac companion's session protocol is `CompanionWire`, a pure value-typed codec at L2
of the core — Linux-buildable and fuzzable, which is exactly the layering the transport needed
and which the architect reached independently. The Mac listens and the phone connects outward,
so R-34 holds by construction. R-81's ambient-time allowlist is one target, declared up front.
R-51's redaction is manifest-driven — the serialisers iterate the allowlist and never the record
— which is stronger than the type-level barrier I was going to demand. §2.2 lists the cleared
rows, because a clean audit row is information too.

What is left is sharper for being fewer, and **only one Blocker remains — which is a schedule,
not a design defect.** R-91 cannot be met at Stage 2 exit on any timeline shorter than five
weeks, because R-71 is one engineer-day of harness plus five calendar weeks of soak, and four
NFR thresholds plus R-24's freshness target N all depend on its result (TA-02). Of the
design-level findings, the one that matters most is **R-89's assertion, still insufficient in
every design that touches it** (TA-03), because it is where good work stops just short of the
goal; and the one most likely to be dismissed as cosmetic is **Local Network permission denial
having no enumerated outcome and no distinct copy** (TA-01), which reproduces in the newest
destination precisely the ambiguity R-22 and R-60 exist to forbid — and unlike HealthKit
denial, this one is positively detectable, so we have no excuse.

Four things changed my Stage 1 position, and one of them is a correction to my own work.

**The architect defeated my determinism property, correctly.** Darwin Foundation and
swift-corelibs-foundation do not ship the same tzdata version, and tzdata changes several times a
year, so my Stage 1 P8 — identical SHA-256 across `arm64` and `x86_64` under a hostile locale —
is false for any zone whose rules changed between the two, with no bug in our code. P8 is
restated as per-platform determinism plus a declared tz-database version, with cross-platform
equality asserted only over UTC and fixed-offset fixtures and a CI gate on tzdata drift. That is
the best catch anyone made against my Stage 1 contribution and I have adopted it verbatim.

**Exit tests make the interruption invariants real, but only off-device.** Swift Testing's
`#expect(processExitsWith:)` (ST-0008, implemented in Swift 6.2; capture lists via ST-0012 in
Swift 6.3) spawns a real child process and asserts its termination. It is supported on macOS,
Linux, FreeBSD, OpenBSD and Windows, and is **not available on iOS/tvOS/watchOS runtime
targets** [1][2][3]. So the six fault-injection seams of R-83 can be exercised as genuine
process kills — the strongest possible form of the R-04 anchor-durability test — but only where
the pipeline runs as a host executable. That is a second, independent argument for R-80, and it
also means the anchor-durability invariant is *never* exercised as a real process kill on a real
device. I declare that gap in §11 rather than hiding it.

**R-89's acceptance criterion admits a false green, and the designs inherited it.** The PRD
requires read-back of `unit_of_measurement`, `device_class`, `state_class` and precision. The
wire-format design gives the best account of Home Assistant's rules I have seen anywhere and
encodes them in the metric catalogue rather than in integration code, which is right. But
asserting that `state_class` is *present* is necessary and not sufficient: the failure we guard
against is that long-term statistics are silently not generated, and the only assertion that
catches it is that a **statistics row exists** after a recorder statistics cycle. Different API,
different wait, ~12-minute job. Findings **TA-03** and **TA-04**.

**R-88's "any discrepancy is a P1 by definition" is unsatisfiable as written**, because R-09
deliberately evicts data (with a gap record) and R-05 makes deletion propagation explicitly
best-effort. Two Musts guarantee that a 21-day soak can produce a discrepancy while the product
behaves exactly as specified. R-88 needs to say *unexplained* discrepancy, with the three
explanation classes in §8.1.5. Finding **TA-06** — a defect in my own promoted requirement,
cheaper to fix now than to argue about on soak day 12. The reliability design independently
reached the neighbouring point and added a better one than I had: measure the **duplicate** rate
against ≤ 0.1% alongside zero loss, because a design that achieves zero loss by duplicating
everything is passing the wrong test.

**The corpus must never be a file.** T1 is 10,000,000 samples and T2 is 50,000,000. As NDJSON at
~200 bytes/record those are roughly 2 GB and 10 GB, which do not fit comfortably on a hosted
runner and cannot be moved between jobs. The generator is therefore a **counter-based
(index-addressable) pseudo-random stream**, not a stateful PRNG writing a file: sample *i* is
computable from `(seed, streamID, i)` alone. That buys reproducibility independent of iteration
order, free parallelism, resumability, O(1) random access to any single sample for a failing
counterexample, and cross-architecture determinism — which R-84 requires anyway. §4.

Finally, scope contracted in one helpful direction that Stage 1 did not anticipate. Dropbox,
Google Drive, iCloud Drive, Calendar, S3, GPX/FIT/TCX and watchOS are all now non-goals. The
destination surface is five sinks, four of which are testable without credentials, and the
untestable-cloud-OAuth section of my Stage 1 contribution is simply deleted. The Mac companion
replaces all of it as the single hard transport problem, and it is a better problem: it is ours,
so we can design it to be testable. §6.

---

## Audit: Stage 2 designs against the §6.6 testability constraints

### 2.1 What I audited

Seven design documents, read 2026-09-03:

| Document | §6.6 relevance | Verdict |
|---|---|---|
| `01-system-architecture.md` | R-80, R-81, R-83, R-84, R-86, and the Mac companion transport | **Honours §6.6 structurally.** See §2.2 |
| `02-healthkit-layer.md` | The seam itself, R-70, R-71, R-91's basis | Seam is correct; the spikes are designed but not run (TA-02) |
| `03-wire-format-spec.md` | R-84, R-12, R-89 | Best treatment of R-89's *rules* in the set; the *assertion* is still insufficient (TA-03, TA-04) |
| `05-observability-design.md` | R-51, R-26, R-20, R-21, R-22 | **Exceeds** what I asked for on redaction (TA-09) |
| `06-interaction-design.md` | R-26's preview gate, R-40/R-41 surfaces, R-60 copy | No §6.6 violation found |
| `08-reliability-design.md` | R-83, R-86, R-88, R-91 | Independently reached several of my conclusions; seam count needs adjudication (TA-08) |
| `09-build-and-release.md` | R-85, R-82's generator, CI topology | Fork path and Linux tier correct |
| `04-security-design.md` | R-33, R-36, R-37, R-43, R-51's canary, R-31's four elements, R-30, QA-38 | **Exceeds** what I specified on canary verification (§2.2). Landed last; audited |

**Severity scale.** *Blocker* — cannot be accepted; a §6.6 Must becomes unverifiable and cannot be
retrofitted. *Major* — verifiable only at disproportionate cost, or a Must's acceptance criterion
is unsound as written. *Minor* — a gap Stage 3 can close cheaply.

### 2.2 Cleared — the constraints the designs honour

Stated because a clean audit row is information, and because three of these were the findings I
had drafted pre-emptively as Blockers and can now withdraw. My other two pre-emptive Blockers
are cleared elsewhere: the security design's absence, by its arrival (§2.1); and R-84's
determinism boundary, by the architect's `tzdata` amendment, which I accept in §2.4.

| Constraint | How it is honoured | Withdrawn pre-emptive finding |
|---|---|---|
| **R-80** | Four packages; `ExportCore` (L0–L4) is macOS/iOS/**Linux** with **zero** third-party dependencies. `HealthKitSource` is the single target importing HealthKit. Enforced by four required checks from M0: Linux build+test, a committed adjacency manifest diffed against `swift package dump-package`, a per-target import allowlist denying `HealthKit`/`Network`/`Security`/`SwiftData` in L0–L4, and a linked-framework and `HK*` symbol assertion. The absent `CorrectnessEngine → StorageSQLite` edge is exactly the seam I needed | — |
| **R-80 vs MQTT** | `SinkMQTTPackage` quarantines `mqtt-nio` + SwiftNIO in a separate package that never enters `ExportCore`'s resolution graph, and it builds on Linux. The dependency policy makes "does it build and test on Linux?" the first admission question | I had this as a **Blocker**. Withdrawn |
| **R-80 vs the Mac companion** | `CompanionWire` at L2 is a pure value-typed frame codec and state machine, Linux-buildable and fuzzable, with `SinkCompanion` as ~200 lines of `NWConnection` adapter above it. This is precisely the Layer A / Layer B split §6.3 needs, arrived at independently | I had this as a **Blocker**. Withdrawn |
| **R-34 and the listener** | The **Mac** listens (`NWListener`); the iPhone connects outward. `MacCompanionApp` is CI-asserted not to depend on `HealthKitSource`. R-34 holds by construction rather than by a symbol grep | I had the shared-target collision as a **Major**. Withdrawn |
| **R-31 for the companion** | TLS 1.3 with a 256-bit PSK established by QR pairing, plus a six-digit confirmation code derived from the TLS key exporter shown on both screens. Mutual authentication, forward secrecy, no CA, no pin-on-first-use ambiguity. Multipeer Connectivity rejected explicitly *because* peer identity is a display name — the RK-11 argument I was going to make | I had "no durable peer identity" as a **Major**. Withdrawn; the design is stronger than my proposal |
| **R-81** | `CoreTemporal` is declared the **only** place `Calendar`, `TimeZone` and `Locale` are constructed, with an injected `Clock`. This is the single-adapter allowlist I asked for, designed up front rather than discovered | I had "allowlist will grow reactively" as a **Major**. Withdrawn |
| **R-82** | `Tools/corpusgen` is a shipped, Linux-buildable, seed-reproducible executable, CC0-licensed, also serving R-114's demo bundle | — |
| **R-51** | Emission is **manifest-driven**: the bundle and OTLP serialisers iterate the allowlist manifest, never the record (ADR-OBS-08). Default-deny is a structural property, not a review practice. Every metric attribute value comes from a compile-time-closed enumeration | I had "call-site redaction is a denylist with extra steps" as a **Major**. Withdrawn — this is better than I specified. Residual in TA-09 |
| **R-85** | Linux core build+test is a required check needing no secrets and passing on fork PRs; branch protection lists every required check and "every required check passes on a fork PR" is an audited release item | — |
| **R-86** | Checkpoint golden files, corruption tests asserting explicit failure, `anchor_invalidated` as a journalled event, and ADR-0003's write-ahead cursor discipline: no API persists an anchor; `CursorAdvance` is accepted only as a field of a batch-commit transaction | — |
| **The differential test** | `FileWriteKit` is used by **both** the phone's local-file sink and the Mac receiver — "one writer, two hosts." This is what makes §6.3's byte-identical differential test possible, and it was designed for that reason | — |
| **R-51's canary, beyond spec** | The security design adds two tiers I did not ask for and should have. **Sink coverage is asserted, not assumed**: every sink is registered with the canary harness and adding one without registering fails the build. And **Tier 3 proves the canary can still go red** — a mutant suite reintroduces each leak class in turn and asserts the canary test *fails*, failing the build with "the canary test no longer detects [X]" if a mutant survives. "A green canary proves nothing on its own; a green canary plus a red mutant suite proves the thing we care about." Both are required checks | I had "the canary is theatre" as a **Major**. Withdrawn — this is the answer to it |
| **R-33's backup test** | Turned from an aspiration into a procedure: seed a canary credential, a canary queued payload and a canary log line; take an encrypted local backup; walk the tree **including the manifest database**; assert zero hits. Plus a restore-to-second-device leg | — |
| **R-30 versus R-43** | Resolved elegantly via threat T-51: delete-all writes a genesis marker into the new ledger recording *N entries destroyed at time T*, so a coercer can destroy the evidence but not destroy it *silently*. The honest property is tamper-evidence, not immutability, and the design says so rather than letting "immutable" reach the README | I had this conflict as a **Minor**. Withdrawn |
| **R-83's release absence** | The canary handshake's own removal is treated as a fault-injection seam under R-83, "present in test builds only, absent from release builds" — the seam discipline applied to a security control, which is more than I asked for | — |

**All four of my pre-emptive Blockers are withdrawn, and no design-defect Blocker remains.** The
designers reached these conclusions from the other direction, independently, which is exactly
the outcome §6.6 was written to produce: the seams are in the design because they were designed
in, not because I audited them in afterwards. That is worth saying plainly, because the failure
mode I rated Critical in Stage 1 — "Stage 2 does not honour the HealthKit seam and the whole
automated strategy collapses" — did not happen.

The one Blocker that remains (TA-02) is not a design defect at all. It is a schedule: R-91
cannot be met until a five-week measurement elapses.

### 2.3 Findings

| ID | Finding | Owner | Severity |
|---|---|---|---|
| **TA-01** | **Local Network permission denial has no enumerated outcome and no distinct copy, so the Mac companion reproduces exactly the ambiguity R-22 and R-60 exist to forbid.** The security design knows the privilege binds on both ends and that Settings exposes the grant state; the UX design declares `NSLocalNetworkUsageDescription` and knows the prompt is triggered by outbound traffic rather than by an API. But the user-facing copy for the failure is *"Couldn't find your Mac on this network… Both devices need to be on the same network, the Mac needs to be awake, and Tributary needs to be running on it"* — which is the copy for three causes and is silently also the copy for a fourth: the user, or a coercer, revoked Local Network access in Settings. Denial is *positively detectable* here, unlike HealthKit read denial, so we have no excuse. Needs a distinct member of R-21's enumerated outcome set, distinct copy, and a row in the error-class registry. Without it the product's flagship honesty claim has a hole in its newest destination, and FIX-A07 has nothing to assert against | Observability engineer, UX designer, architect | **Major** |
| **TA-02** | **R-91 has no valid baselines, and R-71 cannot complete inside a near-term Stage 2 close.** The HealthKit design specifies R-70 and R-71 properly — runnable protocols with named decision consequences and a decision table (M3 p90 ≥ 1,600/s ⇒ NFRs stand; 400–1,600/s ⇒ R-75's 30-minute backfill is unreachable and the PM chooses). That is exactly what I wanted. But they are **designed, not executed**, and R-71 is one engineer-day of harness plus **five calendar weeks** of soak on two devices. So: four NFR thresholds remain provisional, R-24's freshness target N cannot be stated, and R-79's wake-budget denominator is an assumption. **R-91 is not satisfiable at Stage 2 exit on any schedule that closes sooner than five weeks from R-71's harness landing.** I will not sign it off as met; I will sign it off as *mapped, pending measurement*, if the PM records a named re-baseline gate. | PM, HealthKit architect | **Blocker** |
| **TA-03** | **R-89's assertion is insufficient in every design that touches it, and this is my sharpest remaining finding.** The wire-format spec gives the best account of the *rules* I have seen anywhere — no `state_class` ⇒ no statistics silently; `measurement` invalid with `device_class` in {`date`, `enum`, `energy`, `gas`, `monetary`, `timestamp`, `volume`, `water`}, so active energy must be `total_increasing`; `enum` forbids `state_class`; `unit_of_measurement` must never change for an existing entity — and encodes all of it in the catalogue rather than in integration code, which is right. The reliability design lists the R-89 test as "read-back of `unit_of_measurement`, `device_class`, `state_class`, precision, at two pinned versions". **Neither asserts that a statistics row exists.** All of rungs 1–3 pass happily on a metric whose long-term statistics never materialise, which is the exact failure R-89 was written to prevent. The assertion must be: push two states separated in time, force or await a recorder statistics cycle, then read `recorder/statistics_during_period` and assert a non-empty result with the `sum`/`mean` semantics the catalogue declares. See §6.2. | Schema engineer, architect | **Major** |
| **TA-04** | **The R-89 suite must be generated from the metric catalogue, one case per row.** The wire spec's HA mapping is ~30 rows of individually falsifiable, version-dependent claims: that `duration` accepts `ms` for HRV, that `sound_pressure` accepts only `dB`/`dBA`, that `blood_glucose_concentration` exists and converts correctly, that `pressure` accepts `mmHg` but exposes the entity to the user's pressure-unit preference, that BMI must omit the unit entirely. Hand-written tests will cover five of these and the other twenty-five will be assumed. Requirement: the contract suite is **generated from `MetricCatalog`**, so a catalogue row added without HA validation fails the build, and `null` device classes and `haRequiresAggregate` are asserted as *absences* — an omitted attribute is a claim too. | Schema engineer, QA (me) | **Major** |
| **TA-05** | **No design declares the supported Home Assistant version window.** Both the wire spec and the reliability design say "two pinned versions"; neither says which, and no requirement owns the policy. HA ships monthly on CalVer (first Wednesday), with weekly patch releases and a Supervisor-enforced ~24-release horizon [4][5][6], so an undeclared window rots inside two months and the job gets disabled. Proposed policy, needing a named owner: **current stable back to current stable − 11 releases (≈12 months)**, matrix pinning both ends, with a calendar-driven bump issue on the first Thursday of each month. | PM | **Major** |
| **TA-06** | **R-88 conflicts with R-09 and R-05, and the reliability design independently reached the same place.** "Any discrepancy is a P1 by definition" cannot hold when R-09 deliberately evicts an oldest-first window and R-05 makes tombstone propagation best-effort: a correctly-behaving product can fail its own soak gate. The reliability design says the end-of-soak reconciliation "must account for each one individually, not merely net to zero" — which is the right instinct and does not go far enough, because netting to zero is not the failure mode; being *told* a discrepancy is a P1 when it is a disclosed loss is. Fix: R-88 reads *unexplained* discrepancy, with three explanation classes (§8.1.5). I also adopt the reliability design's second assertion in full: measure the **duplicate** rate against ≤ 0.1% alongside zero loss, because "a design that achieves zero loss by duplicating everything is passing the wrong test" — a sharper statement of my P4 than I had written. | QA (me), PM | **Major** |
| **TA-07** | **The R-26 bundle bound makes the soak diary conditional, and nobody has noticed.** The architect correctly bounds the diagnostic bundle to the last 30 runs (§11.6) — unbounded rendering was never viable and the amendment is right. But the reliability design's own Q1 observes that in a store-and-forward pipeline most runs legitimately end `partial`, i.e. runs are frequent. If run frequency exceeds 30/day, a once-daily bundle capture no longer covers 24 hours, the soak diary acquires silent holes, and R-88's day-level bisection — the thing that turns "we lost 41 `heartRate` samples" into "day 12, run 3" — stops working. Requirement: the bundle window is **the greater of 30 runs or 24 hours**, or the soak uses a test-build time-windowed journal export. Costs nothing now; costs the soak on day 12. | Architect, observability engineer | **Major** |
| **TA-08** | **The seam count needs adjudication, and the answer is that R-83 does not change.** The reliability design asks for seven injectors (`KillAt` over 17 enumerated death points, `AckOracle`, `QueuePressure`, `StoreLocked`, `WakeBudget`, `SinkBehaviour`, `ClockSkew`) and suggests the PM either raise R-83's count or have me fold one in. **Neither is necessary.** R-83's six are pipeline *locations*; six of those seven are injection *vocabulary*, which §7 already treats as orthogonal to location, and `KillAt`'s 17 death points are the six locations at finer grain. I adopt the whole vocabulary — it is better than mine, particularly `WakeBudget` and `ClockSkew` — and keep six names. Condition on the architect: confirm the 17 death points partition onto the six named seams, and that none falls outside them. | Architect, reliability designer | **Minor** |
| **TA-09** | **The diagnostic bundle's log section is the one surface where P12 can still fail.** The observability design's manifest-driven emission (ADR-OBS-08 — serialisers iterate the allowlist, never the record) is stronger than the type-level barrier I was going to demand, and it converts default-deny into a structural property. It also states honestly that free-form log text cannot be allowlist-governed by definition, and gives it three defences. Residual consequence for me: **P12 splits into P12a and P12b.** P12a covers allowlist-governed surfaces and is structurally provable; P12b covers log text and is canary-only, best-effort. The release gate must treat the log section as off-by-default and must not report P12b's pass as evidence for P12a's guarantee. | QA (me) | **Minor** |
| **TA-10** | **R-80's aggregation exception list (architect §11.3) is accepted, with three conditions.** HealthKit's statistics queries de-duplicate multi-source overlap by an algorithm Apple does not document, so the canonical aggregate for those metrics genuinely cannot be computed in a HealthKit-free core. Accepting the exception list is correct. Conditions: (a) the list is asserted non-growing without an ADR — the architect already commits to this; (b) every recorded reference vector carries the device model, OS build and capture date, because an undocumented algorithm can change under us and a stale vector is worse than no vector; (c) **R-87's device pass re-captures and diffs the vectors every release**, so an Apple-side change becomes a visible event rather than a silent divergence between our number and the Health app's. Without (c) the exception list is a permanent blind spot on the wedge's own metric. | Architect, QA (me) | **Minor** |
| **TA-11** | **R-12's frozen-fixture gate cannot apply to the HAE profile as it does to our own spec.** Health Auto Export's format is not ours and is not specified by its author, so our compatibility is an observation, not a contract. Freezing it needs captured golden fixtures with a dated provenance note, and the public claim must be "compatible with the HAE payload shape as observed on *date*", never "conformant". The architect's §12 Q8 raises the adjacent licensing question (a CC0 mapping document of a third party's product surface); this is the verification half of the same problem. | Schema engineer | **Minor** |
| **TA-12** | **R-82's acceptance criterion is ambiguous and names no reference hardware.** "Tier 1 generates reproducibly from a committed seed in ≤10 min on a reference Mac" — under the PRD's own ordering "Tier 1" reads as the ~200 committed samples, for which a 10-minute budget is meaningless; under my naming it is the 10,000,000 tier, which is the real constraint. And §7 names REF-A and REF-B iPhones but no reference Mac, so the threshold has no device. Fix: adopt T0/T1/T2 explicitly (§4.1), bind the budget to T1 = 10M, name a reference Mac. My own requirement, my own defect. | QA (me), PM | **Minor** |
| **TA-13** | **Exit tests do not run on iOS, so anchor durability is never process-killed on device.** ST-0008 is unsupported on iOS/tvOS/watchOS runtime targets [1][3], so R-04's "kill the process at every pipeline step" is a host-target test over the Linux/macOS build. Real-device equivalents — jetsam, watchdog, force-quit, reboot mid-write — are observable but not scriptable, and move to R-87 and R-88 as scripted human perturbations. A genuine coverage gap, declared in §12 rather than papered over. It is also the strongest available argument for the architect's target graph: any pipeline code reachable *only* on Apple platforms is code whose crash-consistency is never machine-verified, which is one more reason the absent `CorrectnessEngine → StorageSQLite` edge matters. | Architect, QA (me) | **Minor** |

### 2.4 Amendments the designers proposed to my requirements — my disposition

The architect's §11 lists seven requirements he cannot design as written. Six touch requirements I
own or verify. Dispositioning them is my job, not the PM's, so here it is.

| Amendment | Disposition | Note |
|---|---|---|
| **§11.2 — R-84 is not achievable cross-platform for calendar-dependent output** | **Accepted, and it corrects my own work** | Darwin Foundation and swift-corelibs-foundation do not ship the same tzdata version, and tzdata changes several times a year, so a digest computed on `ubuntu-latest` and one on `macos-26` will legitimately diverge for any zone whose rules changed between them. **My Stage 1 P8 — "100 runs on arm64 and x86_64 produce identical SHA-256 under a hostile locale" — is wrong as written**, and no amount of care in our code fixes it. I adopt the amendment verbatim: per-platform determinism plus a declared tz-database version recorded in the checkpoint envelope and every export manifest; cross-platform digest equality asserted only for the fixture subset expressed in UTC and fixed offsets; a CI gate failing when the host tzdata version differs from the recorded one, so divergence is an event rather than a flake. §5.1's P8 is restated accordingly. This is the best catch anyone made against my Stage 1 contribution |
| **§11.5 — two seam names presuppose an ordering the design inverts** | **Accepted** | R-04's write-ahead discipline advances the cursor at commit, *before* delivery, so there is no ack-to-anchor window in which data can be lost and FI-05's original assertion is trivially true. The interesting assertion moves to "a batch acked but not released is redelivered, and redelivery is safe." Keep all six names — they are contractual — and restate two assertions. §7's FI-05 and FI-06 rows are updated |
| **§11.4 — R-91 rejects two of its own NFRs (R-77, R-79)** | **Accepted** | Independently identical to my §9.3 conclusion. Each NFR maps to an automated device test **or** to a named, scripted, recorded device protocol on the R-87 pattern. R-77 and R-79 take the latter |
| **§11.3 — R-80 versus R-07's canonical aggregate** | **Accepted with the three conditions in TA-10** | |
| **§11.1 — R-44's 60-second purge is not implementable** | **Accepted** | iOS provides no revocation callback and read authorisation is deliberately opaque — the same platform property R-60 exists to accommodate. The clock must start at *observation*. Verification consequence, which the amendment does not state: there must also be a test that observation actually occurs at **every** foreground launch and background wake, because the amendment's honesty depends entirely on the observation cadence. FIX-A03 is restated to that form |
| **§11.6 — R-26's "full contents rendered" is unbounded** | **Accepted, with TA-07's addition** | Bounding to the last 30 runs is right; it must also cover ≥ 24 hours or the soak diary breaks |
| **§11.7 — SEC-04's Bonjour criterion** | **Accepted** | On iOS `NSBonjourServices` is required to *browse*, so no design that discovers a Mac satisfies the literal criterion. The security design received it and reaches the same place |

The security engineer separately lists six requirements he cannot secure as written. Two are
verification-method changes I own and adopt:

| Amendment | Disposition |
|---|---|
| **R-32's acceptance criterion** — "network capture shows zero traffic to it" will fail on OS-initiated DNS, OCSP/CRL and Certificate Transparency traffic we neither cause nor can suppress | **Accepted.** Restated as zero **application-initiated** connections, with OS-initiated resolution and certificate-validation traffic enumerated and excluded **by name** in the harness. An unnamed exclusion list would hollow the test out, so the names are committed and reviewed |
| **R-50 versus MQTTNIO** — if the library route is taken, `swift-log` enters the graph and R-50's criterion ("no `swift-log` dependency in the app target") fails | **Accepted as a T0 gate change.** The dependency and licence gate must distinguish *linked* from *used*: assert no first-party code logs through a `swift-log` facade, rather than asserting the package is absent from the resolved graph. The current check would go red on a correct implementation, which is the worst kind of gate |
| **R-44, R-41, R-40, R-30's "immutable"** | Product/security wording, not mine. I note only that R-40's proposed addition of "and with notifications denied" to its acceptance criterion mirrors R-23 and I support it, because it is the same test harness either way |

### 2.5 The audit instrument — R-80 … R-91 against Stage 2 designs

Run this against each design document. "Proof artifact" is what I need to see in the document
(Stage 2) or in the repository (Stage 3) to clear the row.

| Req | The design decision that satisfies it | Proof artifact | Severity if absent |
|---|---|---|---|
| **R-80** | Core is a SwiftPM library with no Apple-framework dependency, in a package that declares Linux platform support. HealthKit, Network.framework, Bonjour, Keychain, `UIDevice`, `os.Logger` all sit behind ports with platform-conditional conformances in separate targets. | Package/target dependency diagram showing no arrow from core to any Apple framework; a named required CI check building and testing core on `ubuntu-latest`. | **Blocker** |
| **R-81** | One `Clock`/`CalendarSystem`/`TimeZoneResolver`/`LocaleProvider` port set, injected at the pipeline root. Named allowlist of ambient-time call sites (§2.2, cleared). | The port protocols; the allowlist with one entry per justification; the lint rule's scope. | **Blocker** |
| **R-82** | Domain value types constructible from text, no HealthKit types crossing the seam; corpus generated as an index-addressable stream, not a file. | The domain model's dependency-free declaration; the generator's interface (`sample(at:)`, not `next()`). | **Blocker** |
| **R-83** | Six named seams at real transaction boundaries, gated by a SwiftPM **package trait** (or equivalent compile-time gate), with an empty no-op conformance in release. | Seam names mapped onto the pipeline diagram; the compile-time exclusion mechanism; FI-05 shown inside R-04's transaction. | **Blocker** |
| **R-84** | Declared deterministic core per format, with the non-deterministic envelope enumerated (§2.4, per the architect's §11.2 amendment). Record identity data-derived. No dictionary iteration, no locale-dependent formatting, no `Double` transcendentals in serialisation. | The per-format determinism boundary table. | **Major** |
| **R-85** | No required check needs a secret. Container images pulled from an unauthenticated public registry (TA: not Docker Hub anonymous — see §9). | Workflow tiering table showing which checks are required and that none reference `secrets.*`. | **Blocker** |
| **R-86** | Versioned, documented, inspectable checkpoint with an explicit failure mode on unreadable state; fields classified for PHI. | Checkpoint schema with version tag and field classification; the stale-anchor handling path. | **Major** |
| **R-87** | Nothing required of the designs except that the device pass is possible: a build configuration that runs the real HealthKit adapter against a real store while emitting the journal in a form the script can read. | Named device build configuration; the journal's export path. | **Minor** |
| **R-88** | R-20 journal is machine-readable and complete enough to reconstruct a daily diary; R-08's date high-water marks are queryable per type per day. | Journal record schema; the per-type/per-day count query. | **Major** |
| **R-89** | HA preset emits `unit_of_measurement`, `device_class`, `state_class` and a declared precision per metric, driven by the metric catalogue (R-07), not hardcoded per destination. | The catalogue's HA attribute mapping; the declared version window. | **Major** |
| **R-90** | MQTT publish path behind a portable transport port (§2.2, cleared); QoS, retain, topic template and session semantics are configuration, not code paths. | Transport port; the QoS-to-outcome mapping (R-25's `Sent, unconfirmed`). | **Blocker** |
| **R-91** | Every NFR has a defined *workload*, and the workload is an artifact the harness can invoke — not a prose description. | Workload definitions as named corpus slices + destination configurations; R-70/R-71 findings (TA-02). | **Blocker** |

---

## Test architecture

Seven layers. The proportions are stated twice on purpose: share of test *count* and share of
*risk* covered, because they disagree and the disagreement is how you know where to spend
effort. L7 is under 1% of the count and carries the failures that define the product category.

| Layer | Covers | Tooling | Runs where | % count | % risk |
|---|---|---|---|---|---|
| **L1 Unit** | Transform, serialisation (NDJSON/JSON/CSV/HAE profile), unit canonicalisation, calendar and time-zone arithmetic, bucket-key derivation, aggregation semantics per metric (R-07), retry/backoff policy, redaction rules, request-template evaluation, config parse and migration, metric catalogue, R-25 outcome mapping | Swift Testing | `ubuntu-latest` **and** macOS | 52–56% | ~28% |
| **L2 Property / model-based** | The fifteen invariants in §5. One stateful model over (store, anchor, checkpoint, queue, destination) drives most of them | Swift Testing + a property library (ADR required — see §5.4) | `ubuntu-latest` **and** macOS | 6–8% | ~26% |
| **L3 Integration, in-process** | Whole pipeline: fake source → transform → real temp-dir persistence → destination double. Fault injection at all six seams, injected clock, kill-and-resume via exit tests | Swift Testing + `#expect(processExitsWith:)` | `ubuntu-latest` **and** macOS | 16–18% | ~18% |
| **L4 Contract / real doubles** | Real Mosquitto broker; in-repo scriptable HTTP server; real Home Assistant containers ×2 versions with statistics read-back; Mac companion loopback transport (two real processes, real Bonjour/TLS, one host); schema validation of every emitted payload; OTLP collector | Swift Testing; containers on Linux, Homebrew Mosquitto on macOS | Linux for containers; macOS for Network.framework and Homebrew | 10–12% | ~12% |
| **L5 UI, Simulator** | Onboarding order (R-63 before the permission prompt), permission-denied and empty states, R-26's preview-before-share gate, destination config, R-40 notification surfaces, data browser (R-69), widget, accessibility audits, Dynamic Type, pseudo-locale, RTL | **XCUITest — must remain XCTest** [7][8] | macOS runner, Simulator | 6–7% | ~5% |
| **L6 Device** | Real HealthKit read, authorisation sheets, background delivery observation, R-91 NFR baselines, R-33 backup test, two-device Mac companion transport, T2 corpus, R-87 release pass | XCTest + `XCTMetric` (XCTest-only [7][8]); shell harness for the NFR runs | Self-hosted Mac + physical iPhones, `workflow_dispatch` and tags only | 2–3% | ~8% |
| **L7 Soak and field** | R-88 21-day soak, R-23 escalation in the wild, energy (R-77/R-78), upgrade-in-place, real source mix, MetricKit background-exit counters | Scripted human protocol + TestFlight cohort + MetricKit | Maintainer and beta devices | <1% | ~3%, and the 3% that hurts most |

### 3.1 Swift Testing vs XCTest, per layer, with justification

| Layer | Framework | Why |
|---|---|---|
| L1, L2, L3, L4 | **Swift Testing** | Parameterised tests over the FIX-* catalogue are first-class, which matters because the catalogue is ~90 rows and I want one test function per *case class*, not per case. Traits give the tiering (`.tags(.linuxSafe)`, `.tags(.container)`) that the CI tiers select on. `Issue.record(_:severity:)` (Swift 6.3 / Xcode 26.4) lets a corpus-realism divergence be a warning rather than a failure, which §4.4 needs. Exit tests (ST-0008/ST-0012) are the mechanism for L3's kill-and-resume, and they run on Linux [1][2][3]. |
| L5 | **XCTest, mandatory** | `XCUIApplication` and `performAccessibilityAudit(for:_:)` have no Swift Testing equivalent in Xcode 26 [7][8]. Not a choice. |
| L6 | **XCTest for `XCTMetric`; a shell harness for everything else** | `XCTClockMetric`, `XCTMemoryMetric`, `XCTCPUMetric`, `XCTStorageMetric`, `XCTApplicationLaunchMetric` are XCTest-only [7][8]. But I am **not** using Xcode's baseline mechanism (§8.2), so most of R-91 is a harness that runs a workload and writes JSON, and only R-73 and R-76 (launch metrics) genuinely need `XCTMetric`. |
| L7 | Not a framework | A protocol executed by a human, plus scripts. §8 and §7 make it executable by a stranger. |

Both frameworks coexist in one package; `SWIFT_TESTING_XCTEST_INTEROP_MODE` is set explicitly in
the test plan so interop reporting is deterministic rather than incidental [9]. A CI policy check
rejects any new `XCTestCase` subclass outside the UI-test and metric-test targets.

### 3.2 What is deliberately not automated

Stated as policy so nobody spends a month on it, with a named alternative for each. This is
R-91-adjacent discipline applied to the test strategy itself: an unautomatable thing with no
named alternative is an unowned risk.

| Not automated | Why | Named alternative |
|---|---|---|
| Background wake **timing** | `HKUpdateFrequency` is a ceiling; delivery is throttled by battery, budget and lock state (C-02, C-03). No assertion of the form "delivered within N minutes" is sound | R-71 measures the distribution; the soak measures it again in the field; we assert only *our* half — given a callback, the export completes correctly and the anchor advances |
| Multi-week continuity | No CI job simulates 21 days | R-88 soak |
| Apple's HealthKit permission UI | Driving the system sheet is unsupported and brittle | Assert we *request* the right types and handle every returned state; R-87 device pass drives the sheet by hand |
| Apple Watch data generation | Impossible — we cannot forge `HKSource` | Corpus fixtures modelled on Watch shapes; R-87 requires ≥3 real sources |
| Energy as a **gate** | See §8.4. Tethered measurement perturbs the thing being measured | Folded into R-88 (R-77) plus a short untethered protocol (R-78); Xcode Organizer for the fleet |
| Mac companion over **real Wi-Fi**, AWDL, roaming, Mac sleep/wake | Needs two physical devices and a radio | L4 loopback covers the framework glue; L6 two-device covers the rest; §11 lists what neither covers |
| iOS process kill at a seam (jetsam, watchdog, force-quit) | Exit tests are unavailable on iOS [1][3] | L3 exit tests on the host build; scripted perturbations in R-87 and R-88 |
| HA versions outside the declared window | Unbounded matrix against a monthly release train [4] | Declared window (TA-05) + a nightly canary against current stable |
| VoiceOver *experience* | Only its preconditions are machine-checkable | Automated audit for preconditions; one manual pass per release, recorded (R-64) |
| Anything needing a secret on a fork PR | Structurally impossible (R-85) | Nightly/release-gated jobs, never required checks |

---

## Synthetic corpus design

### 4.1 Three tiers

Naming fixed here to resolve TA-12. **T0/T1/T2** are the tier names; R-82's ≤10-minute budget
binds to **T1**.

| Tier | Size | Span | Types | Sources | Committed? | Purpose | Where it runs |
|---|---|---|---|---|---|---|---|
| **T0** | ≤ 200 samples | days | all families represented | ≥ 6 | **Yes** — hand-authored, human-readable, reviewable in a PR | Unit tests. Every FIX-* case has a T0 instance | T0 CI tier, every push |
| **T1** | **10,000,000** | **≥ 5 years** | **≥ 60** | **≥ 6** | No — generated from a committed seed | The headline "large store". End-to-end pipeline, memory, aggregation, anchor batching | Nightly (Linux); device weekly |
| **T2** | **50,000,000** | 15 years, one type holding 20M | ≥ 60 | ≥ 8 | No — generated | Pathological. Finds O(n²), memory blowups, pagination bugs | Weekly / device tier only |

T0 is the only tier that exists as files. Every fixture file carries a provenance header
(`synthetic: true`, generator version, seed, tier) and CI rejects a fixture without one — this is
the machine-checkable half of "no real human health data ever enters the repository", which
remains an absolute rule including maintainers' own data.

### 4.2 The generator

**Index-addressable, not sequential.** The generator is a pure function
`sample(seed, streamID, index) -> DomainSample`, built on a counter-based PRNG (a keyed
integer hash — SplitMix64/Philox class), never a stateful `RandomNumberGenerator`. Consequences,
all of which the strategy needs:

- **Reproducible independent of iteration order**, so parallel test workers and a resumed nightly
  job produce the same corpus. A stateful PRNG would not.
- **O(1) random access.** When a property test shrinks to "sample 7,431,902 of stream 12 breaks
  bucketing", the regression test is that one index, and it costs microseconds. This is what makes
  §5's shrinking strategy affordable at 10M scale.
- **No file, no disk, no artifact passing.** T1/T2 stream through the pipeline. As NDJSON they
  would be ~2 GB and ~10 GB, which does not fit the hosted-runner disk budget and cannot be
  cached between jobs.
- **Cross-architecture determinism**, satisfying R-84 for the corpus itself. Integer arithmetic
  and fixed-point distribution shaping only; no `Double` transcendentals, whose last bits are not
  guaranteed identical across `arm64` and `x86_64`.

**Structure.** One *stream* per (source, type) pair, each with its own `streamID`, so a
"source" is a coherent set of streams with a shared `HKSourceRevision`-shaped identity, a
cadence and an availability window. Realism comes from composing streams, not from one clever
function: an Apple Watch stream mix, an iPhone stream mix, a CGM at 5-minute cadence, a
Bluetooth scale at irregular human cadence, a third-party running app writing per-second
workout data, and a manual-entry stream with sparse, user-entered samples and missing metadata.

**Per-stream cadence model.** Inter-sample intervals are drawn from a per-type distribution with
explicit gap injection: device-not-worn windows, charging windows, sleep windows, travel windows
(time-zone change), a two-week holiday with no data, and a device-upgrade discontinuity where the
source revision changes mid-history. The gaps are the point. A corpus with uniform cadence tests
nothing about the reconciliation sweep (R-08), and "no data" versus "data we failed to read" is
the distinction the whole product exists to get right.

**Volume derivation** (unchanged from Stage 1, restated so it stays falsifiable): an active Watch
wearer generates roughly 105k/yr resting-HR samples at 5-minute cadence, ~200k/yr workout HR at
5-second cadence, ~36k/yr each for step/distance/active-energy/basal-energy buckets, ~9k/yr
stand and exercise hours, ~15k/yr sleep-stage segments, plus environmental audio exposure and
HRV — 600k–900k samples/year. One high-frequency third-party writer (a CGM at 5-minute cadence
is 105k/yr) puts 5 years at 3M–12M. T1 = 10M sits inside that range.

**Type coverage: ≥ 60 across every structural family**, because the bugs are per-family, not
per-metric.

| Family | Must include | Testing note |
|---|---|---|
| Cumulative quantity | `stepCount`, `distanceWalkingRunning`, `distanceCycling`, `activeEnergyBurned`, `basalEnergyBurned`, `flightsClimbed`, `dietaryWater`, `appleStandTime` | Summable; the overlap policy of R-07 is exercised here |
| Discrete quantity | `heartRate`, `restingHeartRate`, `heartRateVariabilitySDNN`, `bodyMass`, `bodyFatPercentage`, `height`, `bloodGlucose`, `oxygenSaturation`, `respiratoryRate`, `bodyTemperature`, `vo2Max`, `walkingHeartRateAverage` | Mean/min/max, never sum |
| Category | `sleepAnalysis` (every stage), `mindfulSession`, `menstrualFlow`, `handwashingEvent`, `appleStandHour` | `sleepAnalysis` is the R-01 case and the metric users care most about |
| Correlation | `bloodPressure`, `food` | Container semantics; children never independent |
| Workout | ≥ 15 activity types, with segments, laps, per-workout statistics, metadata | Routes are data we may carry even though GPX export is a non-goal |
| Series | Heartbeat series, high-frequency quantity series | Different API, different volume profile |
| Read-only / unsynthesisable | ECG, `appleExerciseTime`, `appleStandHour`, clinical records | Exist **only** in our domain model, never via a HealthKit write |
| Characteristics | DOB, biological sex, blood type, Fitzpatrick type, wheelchair use | Not samples; no anchor; no history |
| Activity summaries | Daily move/exercise/stand rings | Separate query type |
| Sensitive class | reproductive, mental health, sexual activity, clinical | Needed to test R-66's exclusion from presets and bulk-select |

The sensitive-class row is a testability requirement, not a coverage boast: R-66 says bulk-select
must never include a sensitive type, and that assertion needs sensitive types in the corpus.

### 4.3 Edge-case catalogue

The catalogue is a **committed, versioned file**, and a meta-test enumerates it and fails if any
ID has no corresponding test. Prose in a design document rots; a file that breaks the build does
not. IDs are stable so Stage 4 and the PRD can cite them. Reclassified from Stage 1: the GPX/XML
rows are removed (GPX is now a non-goal) and Mac-transport rows are added.

**Time, calendar, zones (FIX-T)** — R-10, R-81

| ID | Case | What it breaks |
|---|---|---|
| T01 | DST spring-forward: a local wall-clock time that does not exist (02:30 on transition day) | `DateComponents` → nil → crash or silent drop |
| T02 | **DST fall-back: two distinct samples at the same local wall-clock time in the repeated hour** | Dedup-by-local-time collapses them; the daily bucket has 25 hours. R-10's named case |
| T03 | Half-hour and 45-minute offsets: `Asia/Kathmandu` (+05:45), `Australia/Lord_Howe` (30-min DST shift), `Pacific/Chatham` | Whole-hour offset assumptions |
| T04 | Southern-hemisphere DST — transition mid-calendar-year | Northern-hemisphere assumptions |
| T05 | Historic zone-rule change: a sample from a year when the zone's rules differed | Offset must resolve *at the sample instant*, not now |
| T06 | Time zone changed mid-workout (flight); sample time-zone metadata disagrees with the device's current zone | R-10 requires the originating offset on every record — which one, by documented rule |
| T07 | Leap year: 29 Feb, and 28 Feb → 1 Mar in a non-leap year | Day arithmetic |
| T08 | No leap-second generation is possible (POSIX time); instead assert no code path assumes 86,400 s/day or 60 s/minute | The assumption is the bug, and it is testable |
| T09 | **Zero-duration sample** (`start == end`) and sub-millisecond duration | Division by duration → ∞/NaN; instantaneous vs interval semantics |
| T10 | `end < start` — impossible from HealthKit, reachable from a corrupt import | Must reject with a diagnostic; never negative durations |
| T11 | Future-dated (clock skew) and pre-1970 / year-0001 samples | Signed epoch handling; "since last export" |
| T12 | One sample spanning day, week, month **and** a DST boundary at once | Bucket splitting; parts must sum to the original (P10) |
| T13 | Workout crossing midnight, and 31 Dec → 1 Jan | Per-day and per-year grouping |
| T14 | 26-hour sleep session; 30-hour third-party "workout" | Apple discourages ≥24 h samples; they exist anyway |
| T15 | Non-Gregorian calendar and non-Sunday/Monday week start for display aggregation | Locale leakage into machine output (P8) |

**Multi-source and duplication (FIX-S)** — R-02, R-07

| ID | Case | What it breaks |
|---|---|---|
| S01 | **Same metric, same instant, four sources**: Watch, iPhone, Bluetooth scale, third-party app | The canonical duplicate bug. Never silently drop, never double-count |
| S02 | Same bundle ID, two devices (iPhone + iPad), differing product type/version | Source identity is not the bundle ID |
| S03 | **Overlapping samples from a single source** (Apple's de-dup is per-source only) | Cumulative sums inflate |
| S04 | Source revision with zeroed OS version and missing product type (old samples) | Optional-unwrap crashes; nil source keys |
| S05 | Device nil vs partially populated vs two devices with identical names | Device-keyed grouping |
| S06 | Source app since deleted from the phone | Unresolvable attribution |
| S07 | Same logical history read from an iPhone store and an iPad store | Two installs, one destination, must not double-write |
| S08 | Watch store with purged history; earliest-permitted date is recent | "Complete" is store-relative |

**Mutation and lifecycle (FIX-M)** — R-01, R-02, R-05, R-08, R-86

| ID | Case | What it breaks |
|---|---|---|
| M01 | **Retroactively inserted historical sample** — inserted today, dated 3 years ago | Arrives in the *next* anchored batch, out of date order. R-01's whole reason for existing. **The single most important fixture in this document** |
| M02 | Deleted sample: the deleted-object record carries only a UUID — no type, no date | The destination may not be able to express it; R-05's best-effort behaviour must be *documented and observed*, never silently dropped |
| M03 | User edits a sample in Health (delete + insert, new UUID) | Downstream duplicate unless identity is data-derived |
| M04 | One batch containing an insert and a delete of the *same* UUID | Intra-batch ordering |
| M05 | Restore-from-backup: same logical samples, new UUIDs | Full re-export, or worse, half a re-export |
| M06 | Anchor rejected as stale after an OS upgrade | R-86: explicit failure, never a silent reset |
| M07 | 500,000 samples inserted in one batch (a third-party app backfilling years at once) | Batch limits, memory, background budget, R-09 eviction |
| M08 | Deliberate checkpoint corruption: truncated, bit-flipped, forward-version, zero-length | R-86's named case |

**Authorisation (FIX-A)** — R-60, R-62, R-44

| ID | Case | What it breaks |
|---|---|---|
| A01 | **Read denied → queries return only what we wrote; indistinguishable from empty** | R-60. We must never call this success, and never claim denial |
| A02 | Time-bound authorisation — the only positively detectable auth state | The user must be told history is clipped |
| A03 | Authorisation revoked mid-export | Partial batch; anchor must not advance; R-44's 60-second purge |
| A04 | 40 of 60 requested types granted | Per-type degradation, not all-or-nothing |
| A05 | Registry accidentally requests *share* on a share-disallowed type | A pure unit test over the catalogue catches an exception-at-runtime bug with no device |
| A06 | HealthKit restricted by MDM | Distinct message from "denied" |
| A07 | **Local Network permission denied or revoked** (Mac companion) | TA-10. Must not present as "no peers found" |

**Units and numbers (FIX-U)** — R-10, R-65

| ID | Case | What it breaks |
|---|---|---|
| U01 | kg↔lb↔st; km↔mi; kcal↔kJ; °C↔°F including negatives and the −40 crossover; mmol/L↔mg/dL (×18.0182); mmHg↔kPa; m/s↔min/km | Round-trip accumulation; pace divides by speed |
| U02 | Speed exactly 0 → pace | Division by zero |
| U03 | Values needing >15 significant digits; values that do not round-trip through `Double`; denormals | Silent precision loss in JSON/CSV — and R-89's precision read-back |
| U04 | NaN, ±∞ from any path | Rejected with a diagnostic, never serialised |
| U05 | **Implausible extremes**: HR 0 and 500, mass 0 and 700 kg, 10⁹ steps in one sample, negative energy, glucose 0 | We are an exporter, not a validator: never crash, never silently clamp, and per R-42 never interpret |
| U06 | A *meaningful* zero (0 steps recorded) vs absent data | Must be distinguishable in output |
| U07 | Cumulative sums that overflow if any path narrows to 32-bit | Type-narrowing bugs |
| U08 | Locale with `,` decimal separator active during export | Machine output locale-invariant (P8); display not |

**Metadata, encoding, format (FIX-F)** — R-12, R-84

| ID | Case | What it breaks |
|---|---|---|
| F01 | **All optional metadata absent**: no device, no user-entered flag, no time-zone key, no external UUID | Optional chaining; CSV column presence |
| F02 | Metadata of every supported kind: string, number, date, quantity, bool | Type-punning in serialisation |
| F03 | Hostile metadata content: commas, quotes, newlines, CR, tabs, NUL, 10 KB strings, emoji with combining marks and skin-tone modifiers, RTL overrides, unpaired surrogates | CSV quoting, JSON escaping |
| F04 | **CSV injection**: a value beginning `=`, `+`, `-`, `@`, tab or CR | A security requirement as much as a correctness one — the file opens in Excel |
| F05 | Keys colliding after our normalisation (case, Unicode normal form) | Silent overwrite |
| F06 | Exported enumerations must be stable machine identifiers, never localised display names | The export changes meaning with the user's language |
| F07 | A single JSON export exceeding 2 GB; a CSV exceeding common spreadsheet row limits | Streaming, chunking, honest documented limits |
| F08 | **Request-template evaluation with hostile sample data**: a metadata value that closes a JSON string, injects a header, or alters the URL path | R-31's template is a mini-DSL; DSLs are where injection lives. A security contract test, not just a format test |

**Volume, pathology, interruption (FIX-V)** — R-04, R-09, R-74

| ID | Case | What it breaks |
|---|---|---|
| V01 | T1 (10M) and T2 (50M) | Memory, time, anchor batching |
| V02 | One type holding 20M samples | Pagination, per-query limits |
| V03 | 5,000 workouts each with a route | Nested query fan-out |
| V04 | Completely empty store, every type zero | Divide-by-count; empty file vs no file |
| V05 | One type's query errors while the rest succeed | Partial failure must be per-type; healthy anchors still advance |
| V06 | **Process killed at every one of the six seams** | R-04, R-83. Exit tests, host targets only (TA-13) |
| V07 | Destination returns 200 with a failure body; 500 *after* committing; timeout after committing | The at-least-once problem; R-03's honest guarantee |
| V08 | Disk full mid-write; target file replaced by another process mid-write; read-only volume; security-scoped URL revoked mid-write | Partial files must never be presented as complete |
| V09 | Network: flapping, captive portal returning HTML with 200, TLS interception with an untrusted root, IPv6-only, DNS failure, **a `.local` mDNS destination** | The `.local` case is the standard self-hoster HA setup and a real source of failures |
| V10 | Destination that accepts and never responds; one that responds at 1 byte/second | Timeout policy; background budget exhaustion |
| V11 | **R-09 queue fill to 256 MB and oldest-first eviction** | The gap record's date range must be exactly right — see TA-06 |

**Mac companion transport (FIX-P)** — new in Stage 2

| ID | Case | What it breaks |
|---|---|---|
| P01 | Peer disappears mid-transfer (Mac sleeps, Wi-Fi drops) | Resume from checkpoint, no duplication |
| P02 | Two Macs advertising the same service name | R-31's pinned identity must disambiguate, not the name (§2.2, cleared) |
| P03 | Pinned peer key changes | Halt pending explicit re-approval (R-31) |
| P04 | Receiver's target folder becomes unwritable mid-transfer | Partial file never presented as complete |
| P05 | Adversarial channel: reorder, duplicate, truncate, delay, corrupt, half-close | The session state machine, exhaustively, at L2 |
| P06 | iPhone locks mid-transfer (C-02 interacts: HealthKit reads start failing 10 min after lock) | Distinct outcome from a transport failure |
| P07 | Clock skew between iPhone and Mac | Nothing in the record may depend on the receiver's clock |

### 4.4 How realistic does it have to be, and how would I know it is not

Realism is not a virtue in itself; the corpus needs to be realistic **in the dimensions the
code branches on**. Those are: samples per type per day, inter-sample interval distribution
(including gaps), source cardinality per type per day, sample duration distribution, overlap
rate between sources, metadata-key presence rate, and retroactive-insertion rate. It does *not*
need realistic *values* — R-42 forbids us interpreting them and no code path branches on whether
a heart rate is plausible, except FIX-U05, which deliberately uses implausible ones.

**How we get realism without ever touching health data.** A **store-characterisation tool**
(promoted from Stage 1's QA-08) that emits only aggregate shape statistics: counts per type,
date ranges at month granularity, source count and identity *class*, duration histograms,
inter-sample-interval histograms, metadata-key frequencies, overlap rates. No values, no
identifiers, no dates finer than a month. Maintainers and volunteers run it and paste the output
into an issue. The tool's own output is subject to R-51's canary test — a taint corpus of
improbable canary values must not survive characterisation.

**Four falsification signals — how we learn the corpus is not realistic enough:**

1. **The corpus-miss ledger.** Every field-reported defect is triaged with one mandatory
   question: *would the corpus have caught this?* If no, a FIX-* row is added **and the miss is
   recorded**. The metric is misses per release. If it is not declining release over release,
   the generator is not converging on reality and the characterisation loop is not working. This
   is the primary signal because it is the only one measured against actual user harm.
2. **Shape divergence against characterisations.** For each characterised real store, compute a
   histogram distance (KS statistic per dimension) between it and the generated corpus. Declare
   a target per dimension; exceeding it records a warning (`Issue.record(_:severity:)`), not a
   failure, because a single unusual real store should not break the build. Three consecutive
   characterisations diverging in the same dimension is a generator bug.
3. **R-07's aggregate divergence.** R-07 already requires comparing our aggregates against
   `HKStatisticsCollectionQuery` for a multi-source metric on a real device. If we agree on the
   corpus and disagree on device, the corpus is unrealistic in a specific, nameable dimension —
   almost certainly multi-source overlap (FIX-S01/S03). This is the sharpest signal available
   because it localises the unrealism.
4. **The R-87 device pass finding rate.** If the scripted device pass finds defects the whole
   automated suite missed, at a rate that is not falling, the corpus is the prime suspect. Track
   it per release.

Target, stated so it can be missed: **by v1.0, no more than one corpus miss per release, and
zero in the two releases before 1.0.** Below two characterised real stores, I will state in the
release notes that corpus realism is unvalidated.

---

## Property-based tests and invariants

### 5.1 The properties

Fifteen properties. They are the product's correctness definition and they need no device. P1–P8
are the ones the PM's brief names; the rest are the ones that make those eight sound.

| ID | Property | Precise statement |
|---|---|---|
| **P1** | **Round-trip fidelity** | For every format *f* with a declared lossless contract, `decode_f(encode_f(S)) ≡ S` for all sample sets *S*. For lossy formats a projection π_f is **documented** and `π_f(decode_f(encode_f(S))) ≡ π_f(S)`. NDJSON and JSON are expected lossless; CSV and the HAE profile are lossy. The lossiness table is a schema deliverable, not an implementation detail |
| **P2** | **Idempotency of re-export** | Exporting the same scope twice yields byte-identical output over the deterministic core (§2.4), and at a destination honouring idempotency keys, `apply(apply(D, E), E) = apply(D, E)`. R-06's bucket recomputation is the aggregate case |
| **P3** | **No loss under interruption** | For every seam *k* ∈ {FI-01…FI-06} and every kill mode, `delivered(run_killed_at(k) ⨟ resume) ⊇ scope(S)`. At-least-once — the guarantee R-03 actually makes |
| **P4** | **No duplication at the destination** | For destinations supporting upsert-by-UUID (R-02), each `(recordIdentity, destination)` has multiplicity exactly 1 after any kill/resume sequence. For append-only destinations duplicates are possible **by construction** and must be (a) detectable via a stable key and (b) documented. We do not claim exactly-once |
| **P5** | **Monotonic anchor progression** | The persisted anchor advances only in the same durable transaction that persists the outbound batch (R-04). For all interleavings of (deliver, ack, persist, fail, kill): `implied_delivered(anchor) ⊆ acknowledged`, and the anchor never regresses across restart or app upgrade. **The one property that, if violated, silently loses data forever** |
| **P6** | **Delta/full equivalence** | For any sequence of mutations and delta exports, `⋃ delta_i ≡ full_export(final_state)` over the same scope. This is the property that catches FIX-M01 — retroactive inserts being missed — which is the incumbent's defining bug and our stated wedge |
| **P7** | **Deletion propagation** | Every deleted-object record in an anchored batch yields exactly one deletion record downstream **or** exactly one recorded "cannot represent deletion" diagnostic naming the destination. Never silently dropped. R-05's best-effort status is a property about *recording*, not about delivery |
| **P8** | **Determinism and locale invariance** | **Restated per the architect's §11.2 amendment, which defeated my Stage 1 formulation.** Same input + config + *declared tz-database version* ⇒ identical bytes over the deterministic core, across runs, process restarts and any `Locale`/`TimeZone`/`Calendar` set as system default — **per platform**. Cross-platform digest equality (`arm64` Darwin versus `x86_64`/`arm64` Linux) is asserted only over the fixture subset expressed in UTC and fixed offsets, because Darwin Foundation and swift-corelibs-foundation ship different tzdata versions and tzdata changes several times a year. A CI gate fails when the host tzdata version differs from the recorded one, so divergence is a visible event rather than a flake. Still catches dictionary ordering, hash seeding and locale leakage — which is what the property was for |
| **P9** | **Order independence** | Aggregation and de-duplication results are independent of the order samples are supplied, wherever we claim so. Catches accidental dependence on query result ordering — which matters because anchored queries are insertion-ordered |
| **P10** | **Aggregation conservation** | For cumulative types, `Σ bucket_totals = total(range)` modulo the documented overlap and split policy; where a sample splits across buckets the parts sum to the original within a declared tolerance. Also catches double-counting across FIX-S01 |
| **P11** | **Bucket-key stability under recomputation** | For any bucket *b*, `bucketKey(b)` is a pure function of (metric, canonical unit, aggregation semantics, window start instant, window length, scope) and of nothing else — not of insertion order, not of the set of samples present, not of when the computation ran. Recomputing *b* after new samples arrive in it yields the same key and therefore an upsert, not an insert. R-06's convergence criterion |
| **P12** | **Redaction / no-leak** | For all sample sets containing canary values and all log levels below an explicit debug flag, no emitted log line, trace span, span attribute, metric label, crash breadcrumb, filename, notification body, diagnostic bundle **or checkpoint** contains a health value or a sample identifier. Makes R-51 executable; the checkpoint is added because R-86 requires it to be inspectable |
| **P13** | **Bounded resource use** | Peak resident memory is O(1) in corpus size and ≤ the declared ceiling, for every format, at T0/T1/T2. R-74's algorithmic half |
| **P14** | **State migration soundness** | For every persisted-state version *v*, `load(save_v(x))` succeeds and preserves semantics; unreadable or forward-incompatible state produces a recoverable, user-visible error and **never** a silent reset to a zero anchor. R-86 |
| **P15** | **Crash consistency of on-disk state** | After any single-point failure, persisted state equals either the pre-write or the post-write value — never torn, never zero-length. Verified with a fault-injecting filesystem port |

Two supporting properties carried from Stage 1 and still required: **instant invariance under
zone change** (changing the device time zone changes no exported UTC instant; only presentation
changes) and **no egress beyond configured destinations** (R-32/R-37 — the set of endpoints
contacted is exactly the configured destinations plus R-38's advisory endpoint).

### 5.2 The stateful model

Most of P3–P7, P11, P14 and P15 fall out of **one** model-based test, which is why it is the
highest-value single test asset in the project. Model state is
`(store, perTypeAnchor, dateHighWaterMark, checkpoint, queue, destinationState, clock, authGrants)`.

Commands: `insert`, `retroInsert(daysAgo:)`, `edit`, `delete`, `export`, `reconcileSweep`,
`fullReconcile`, `kill(seam:)`, `resume`, `revokeAuth(type:)`, `grantAuth(type:)`,
`changeTimeZone`, `advanceClock`, `destinationFail(class:)`, `destinationTimeoutAfterCommit`,
`destination200WithFailureBody`, `fillQueue`, `corruptCheckpoint(mode:)`, `upgradeStateVersion`,
`peerDisappears` (Mac companion).

After every command the model asserts the invariants that must hold at rest, and after every
`export ⨟ resume` sequence it asserts P3–P7. The model is deliberately a *simple* reference
implementation of the specification — a dictionary keyed by UUID plus a per-type watermark — so
that a divergence between model and implementation is a real disagreement about the spec rather
than two copies of the same bug.

### 5.3 Generators and shrinking

**Generators.** Not uniform random, which would almost never produce the interesting case. Each
generator is a weighted composition:

| Generator | Composition |
|---|---|
| `anySample` | 40% typical (drawn from the T1 stream model), 40% **catalogue-biased** (drawn from the FIX-* catalogue), 20% adversarial (boundary values, absent metadata, hostile strings) |
| `anyInstant` | Weighted towards DST transitions, leap days, midnight, month/year boundaries, and the epoch — the boundaries, not the interior |
| `anyTimeZone` | Weighted towards `Asia/Kathmandu`, `Australia/Lord_Howe`, `Pacific/Chatham`, `America/Santiago`, and zones with historic rule changes |
| `anySourceMix` | Weighted towards 1, 2 and 4 concurrent sources with a controlled overlap rate; source revisions include the zeroed/missing case |
| `anyCommandSequence` | Length-biased short (most bugs are in 3–7 command sequences), with `kill`/`resume` pairs injected at a controlled rate and `retroInsert` over-represented relative to reality because it is the wedge |
| `anyDestinationBehaviour` | Weighted towards the V07/V09/V10 failure shapes, not towards success |

Over-representing the interesting cases is a deliberate trade: it finds bugs faster and it means
the pass rate is not an estimate of field reliability. It is not one, and I will not present it
as one.

**Shrinking.** Three-stage, because naive shrinking on a 10M-sample corpus is useless:

1. **Shrink the command sequence first, not the data.** Delta-debugging over the command list:
   remove commands, then merge adjacent ones, then simplify parameters. A 40-command failure
   almost always reduces to 3–5, and the command sequence is what a human reads.
2. **Then shrink the sample set**, exploiting index-addressability (§4.2): bisect the contributing
   stream indices, then shrink individual samples field-by-field towards a canonical minimum
   (metadata removed, duration zeroed, single source, UTC, epoch-adjacent instant). Because any
   sample is addressable by index, this does not require materialising the corpus.
3. **Then shrink the fault schedule**: reduce to the single seam and single kill mode that still
   reproduces.

**Seed and counterexample policy.** Every failure reports the seed, the shrunk command sequence
and the contributing sample indices, and every shrunk counterexample is **committed as a
fixed-seed regression test with a FIX-* ID**. The property suite is therefore monotonically
strengthening, and a property run is fast on the committed corner cases and slow only in the
randomised budget. Per-PR budget is small (fixed iteration count, ~30 s per property); the
nightly budget is large; the shrink-and-commit loop is what turns a lucky nightly failure into a
permanent per-PR check.

### 5.4 Library choice

An ADR is required, with an explicit maintenance-risk assessment, because every candidate is a
small, young package and this dependency sits under the project's correctness definition.
Candidates: `swift-property-based`, `Exhaust` (which also offers state-machine testing and
coverage-guided fuzzing, and requires Swift 6.3+), `swift-test-kit`. SwiftCheck is legacy.

**The mitigation matters more than the choice.** The property *definitions*, the generators, the
model and the shrinkers live in **our** code behind a thin `PropertyRunner` port, so the library
supplies iteration, seeding and reporting only. If it is abandoned we replace roughly 200 lines,
not the suite. Pin by commit, not by range. Note that Swift has no central package registry, so
advisory coverage for Swift dependencies is thinner than for npm or pip [10] — the dependency
review D-04 requires for MQTT should cover this one too.

---

## Destination doubles and contract tests

Five sinks. Scope contracted usefully since Stage 1: Dropbox, Google Drive, iCloud Drive,
Calendar and S3 are all non-goals now, so the "no emulator exists" section is gone. Four of the
five are testable with no credentials, which is what makes R-85 achievable.

| Sink | Double | The real thing | Where | Fork-safe? |
|---|---|---|---|---|
| **Local file** (document picker) | Injected filesystem port with fault injection (V08) | A temp directory — for our purposes the contract *is* the filesystem | L1/L3, Linux + macOS | Yes |
| **Generic HTTPS POST** + request template | **In-repo scriptable HTTP server** (SwiftNIO, no container): programmable status, latency, body, headers, chunked, gzip, redirects, 401-then-200, `Retry-After`, reset mid-body, self-signed TLS, HTTP/1.1 and HTTP/2, slow-loris. Records every request for assertion | The server *is* the real thing; the contract is HTTP. Plus golden-file tests over the template DSL and FIX-F08's injection cases | L4, Linux + macOS | Yes |
| **Home Assistant** (HTTPS preset) | None — real HA only | **Real HA container at two pinned versions**, with statistics read-back (§6.2) | L4, Linux runner | Yes, via public registry mirror |
| **MQTT** | None — real broker only | **Real Mosquitto**: QoS 0/1/2, retained, last-will, persistent session with `clean_start=false`, TLS with a test CA, client certificates, broker restart mid-publish, topic templating, 256-byte and 64 KB topics | L4; container on Linux, Homebrew on macOS (C-13) | Yes |
| **Mac companion** | Three-layer split — §6.3 | Loopback on one Mac (L4); two devices (L6) | L4 macOS + L6 | L4 yes; L6 never |
| **Our own wire spec** | Committed JSON Schema; every emitted payload validated in L1. Consumers validate against the same published schema — that *is* the contract (R-12) | Frozen fixtures per format version; CI fails on a breaking change to a frozen version | L1, every push | Yes |

### 6.1 Container topology

One `docker compose` project per HA version leg, on `ubuntu-latest`:

```
ubuntu-latest
├── ohe-harness            (Linux executable built from the core package — the SUT)
│                           drives the pipeline over a corpus slice → HTTPS/MQTT
├── homeassistant          (pinned tag; /config pre-seeded — see below)
├── mosquitto              (pinned tag; TLS test CA mounted)
└── otel-collector         (nightly only, for R-53's OTLP contract)
```

`ohe-harness` is the reason R-80 is load-bearing rather than aesthetic: the system under test
must run as a Linux process in this compose network, because C-13 means there is no Docker on
the macOS runner and therefore no way to put a real HA next to an iOS build.

**HA onboarding is the fiddly part and must be a committed fixture.** A fresh HA container
demands interactive onboarding, which cannot be scripted reliably across versions. The design is
a committed, versioned `ha-config/` directory per supported version containing
`configuration.yaml` (recorder with a short `commit_interval`, MQTT integration configured,
HTTP API enabled), and pre-seeded `.storage/auth`, `.storage/auth_provider.homeassistant` and
`.storage/onboarding` with a long-lived access token minted offline. Without this, every monthly
HA release breaks the job in an opaque way and the job gets disabled — which is precisely how
R-89 dies quietly.

**Registry and fork safety.** Docker Hub's anonymous limit is 100 pulls per 6 hours per IPv4
address or IPv6 /64 subnet, shared across everyone behind that address [11][12]; authenticating
a personal account raises it only to 200/6h and requires a secret, which R-85 forbids on a
required check. GitHub-hosted runner IP ranges have historically been prioritised by agreement
with Docker, but that is not a documented guarantee and I will not build a required check on it.
**Design: mirror the pinned HA, Mosquitto and collector images into the project's own container
registry as public packages, and pull from there.** Public packages need no authentication at
all, so a fork PR pulls them with no secret and no rate limit. A weekly job refreshes the mirror
against the upstream pinned tags. (Publishing a public package is a visibility decision — it is
an open question for the PM in §12, though it follows naturally from the repository being public
under AGPL-3.0.)

### 6.2 R-89 in detail — the assertion that actually catches the bug

R-89 exists because HA's long-term statistics silently do not work without `state_class`, and a
silent failure in the primary persona's primary destination, in the product built to eliminate
silent failure, is the most embarrassing bug available to us. So the test must assert the thing
we actually care about.

**Assertion ladder, weakest to strongest:**

1. Entity exists: `GET /api/states/<entity_id>` returns 200.
2. Attributes are correct: `attributes.unit_of_measurement`, `attributes.device_class`,
   `attributes.state_class` match the metric catalogue's declaration for that metric.
3. State precision survives the round trip: the `state` string parses to the exported value
   within the declared precision — this is where FIX-U03 pays off, and where a float formatted
   at the wrong precision is caught.
4. **A statistics row exists.** Push two states separated in time, wait for or force a recorder
   statistics cycle, then read `recorder/statistics_during_period` over the WebSocket API and
   assert a non-empty result with the expected `sum`/`mean` semantics for the metric's declared
   aggregation (R-07). **Only rung 4 catches the failure R-89 was written for.** Rungs 1–3 pass
   happily on a metric whose statistics never materialise.

Statistics cycles run on a fixed interval, so this leg has an unavoidable wait; budget ~12
minutes for the job and use a short recorder `commit_interval` to reduce the rest. That cost is
why the tiering in §9 runs the *current stable* leg per-PR and the *oldest-supported* leg
nightly, rather than both on the fast path.

**The suite is generated from the catalogue, not hand-written (TA-04 and TA-03).** The wire-format design
puts the HA mapping in the metric catalogue rather than in integration code, which is the right
call and makes this possible: the contract suite enumerates `MetricCatalog` and emits one case per
`(metricId, statistic, granularity)`, so a catalogue row added without HA validation fails the
build. Three assertion classes, because two of them are easy to forget:

- **Presence** — `unit_of_measurement`, `device_class`, `state_class`, `suggested_display_precision`
  match the catalogue.
- **Absence** — where the catalogue says `null`, the attribute is *omitted*, not empty. An omitted
  attribute is a claim: `device_class: null` for heart rate, SpO₂, VO₂max and step count is a
  decision the catalogue records deliberately, and emitting `humidity` for SpO₂ because both are
  `%` is the bug that assertion prevents.
- **Invalid-combination rejection** — the catalogue's own rules are asserted against the live
  instance, not trusted: `state_class: measurement` with `device_class` in {`date`, `enum`,
  `energy`, `gas`, `monetary`, `timestamp`, `volume`, `water`} must be shown to produce no
  statistics, and `enum` with any `state_class` must be shown to be rejected. These are the rows
  most likely to change between HA versions, which is exactly why the two-version matrix exists.

Two further things the R-89 job should settle empirically, both raised by the wire-format design
and both currently marked "recommended" rather than measured: whether `device_class: pressure`
for blood pressure exposes the entity to the user's hPa preference (in which case `null` is
correct), and whether REST-created entities really do fail to survive an HA restart while
retained MQTT discovery entities recreate themselves. The second determines which path the
documentation recommends to the primary persona, so it should be a test result, not a belief.

**Version window (TA-05).** HA releases monthly on CalVer, first Wednesday, with weekly patch
releases; the Supervisor treats Core older than roughly 24 releases as unsupported and
recommends upgrading in increments of no more than 6 releases [4][5][6]. Declared policy, to be
adopted by the PM and published in the README: **supported window = current stable back to
current stable − 11 releases (≈12 months)**, with the matrix pinning current stable and the
oldest in-window release. A calendar-driven job opens a "bump the HA matrix" issue on the first
Thursday of each month. Twelve months is chosen over 24 because 24 doubles the fixture
maintenance for the long tail of installs the self-hoster persona least resembles.

### 6.3 The Mac transport problem

This is the hardest thing to test in v1 and the honest answer is that it is tested in three
places, none of which is sufficient alone.

**Layer A — session protocol, pure Swift, in the core. Linux-testable.** Framing, the pairing
and canary handshake (R-31), chunking, offsets, resume, acknowledgement, idempotency keys, and
the ordering rules, expressed as a state machine consuming and producing `[UInt8]` with no
framework. Tested by wiring **two instances of the state machine to each other in-process
through an adversarial channel** that reorders, drops, duplicates, truncates, delays, corrupts
and half-closes (FIX-P05), driven by the L2 property runner. This is where P3, P4, P5 and P11
are established for this destination, and it runs on `ubuntu-latest` in the T0 tier for free.
**If the design does not have this layer, the Mac companion's interruption behaviour is never
verified** — which is why §2.2 clears the finding I had drafted.

**Layer B — real transport, loopback, one Mac. macOS-runner-testable.** Two real processes on the
same host: the receiver advertises via `NWListener` over Bonjour, the sender discovers via
`NWBrowser` and connects over the link-local interface with real TLS and the real pinned-key
handshake. This covers what Layer A cannot: framework glue, the Bonjour resolution path,
certificate/PSK negotiation, backpressure under a real `NWConnection`. It needs no second
device, no Docker, and no secret — so it runs on a hosted macOS runner as a required check. It
does **not** cover AWDL, real radio behaviour, roaming, sleep/wake, or the Local Network
permission prompt.

**Layer C — two devices, self-hosted only.** A physical iPhone and the runner Mac on the same
Wi-Fi. Covers: Local Network permission grant, denial and revocation (FIX-A07/TA-01); Mac sleep
and wake mid-transfer (P01); iPhone screen-lock mid-transfer, which interacts with C-02 because
HealthKit reads begin failing 10 minutes after lock while the transport stays up (P06);
Wi-Fi roaming; two Macs advertising the same name (P02); clock skew (P07). Weekly and
pre-release, never on a fork PR.

**And the test that makes all of it cheap.** Because the Mac companion writes files with the
*same* core serialiser as the local-file destination, and because R-84 requires byte
determinism, there is a **differential test**: export the same corpus slice to (a) the local-file
destination and (b) through the Mac companion transport to the receiver's folder, then assert the
two byte streams are identical. That single assertion covers the entire transport end-to-end
without a second device, and it fails loudly if anyone re-implements serialisation on the
receiver side — which is the most likely way this destination diverges. It requires that the
receiver reuse the core writer rather than reconstructing records, which is a design constraint
the architect should be told about now rather than after 5 EW of work.

---

## Fault injection seams

Six seams (R-83), named here, which R-83 requires and the PRD omitted. Names are stable identifiers; the architect must
confirm each is a real, reachable boundary and place FI-05 inside R-04's durable transaction.

| ID | Location | What it injects | Establishes |
|---|---|---|---|
| **FI-01** | After the source adapter returns a batch, before transform | Error by class (`databaseInaccessible` per C-02, `authRevoked`, `restricted`, generic), empty batch, oversized batch (FIX-M07), delay, hang, process exit | Per-type partial failure (V05); anchor must not advance (P5); C-02 handling |
| **FI-02** | After domain→wire transform, before the outbound batch is persisted | Serialisation error, memory-pressure signal, delay, process exit | No half-transformed batch reaches the queue; P15 |
| **FI-03** | After the batch is durably enqueued, before the destination write begins | Queue-full (drives R-09 eviction and the gap record), process exit, delay | R-09's gap-record accuracy (V11); resume finds the batch (P3) |
| **FI-04** | After bytes are written to the destination, before the acknowledgement is observed | Timeout, connection reset, 200-with-failure-body, 500-after-commit, process exit | The at-least-once case (V07); `unknown_ack` outcome in R-21's enumeration |
| **FI-05** | **After acknowledgement, before the batch is released and the cursor is observable** | Process exit, power-loss simulation, delay | **Restated per the architect's §11.5.** Because ADR-0003's write-ahead discipline advances the cursor *at commit, before delivery*, there is no ack-to-anchor window in which data can be lost, so the original "no data lost" assertion is trivially true. The assertion that matters is: **a batch acknowledged but not released is redelivered, and redelivery is safe** — no duplication at an upserting sink (R-02), no gap. The name stays because it is contractual |
| **FI-06** | Inside the commit transaction (checkpoint/cursor persistence) | Torn write (write *n* bytes then abort), bit-flip, truncation, zero-length, forward-version write, disk-full, process exit mid-`fsync` | **Restated per §11.5.** A kill inside the commit transaction leaves the cursor at its pre-write value with the batch absent — never a torn intermediate (P15), plus P14 and R-86's explicit-failure requirement (FIX-M08) |

**Vocabulary is orthogonal to location**, and I am adopting the reliability design's vocabulary in
preference to my own because it is better. Each seam accepts any of `{throw(errorClass),
delay(duration), hang, exit(signal), corrupt(mode), truncate(bytes), memoryPressure}` plus the
named injectors that design specifies: `AckOracle(script)` for lost, duplicate, late and
partial-acceptance acknowledgements; `QueuePressure(bytes)` so R-09 eviction is deterministic
rather than incidental; `StoreLocked` for `HKErrorDatabaseInaccessible` on demand (C-02);
`WakeBudget(ms)` to shorten the wake so expiration handlers and checkpoints are exercised on
**every** run rather than rarely; `SinkBehaviour(script)` for per-sink latency, error class and
breaker state; and `ClockSkew(delta)` for a device clock moved backwards, asserting no timestamp
is load-bearing.

Six locations × that vocabulary is the actual test matrix, not six tests — which resolves TA-08.
The reliability design's `KillAt(point)` enumerates 17 death points; those are the six named
locations at finer grain, and the architect owes me a confirmation that they partition onto the
six with none left outside. **R-83's count does not need to change.** Torn writes at FI-06 are
realised through the injected filesystem port rather than the seam, because tearing is a property
of the write, not of the call site.

**Kill mechanism.** `exit(signal)` is realised with Swift Testing's
`#expect(processExitsWith:)`: the child process runs the pipeline to the seam and dies there,
the parent then runs recovery and asserts the invariants. Available on macOS and Linux, not on
iOS [1][2][3] — hence TA-13, and hence L3 running on host targets.

**Absent from release builds — compile-time, not runtime.** The seams are calls on a `Seams`
generic parameter whose production conformance is an empty struct with `@inline(__always)`
no-op methods, so release builds contain no seam code at all, and the seam-configuration types
live in a target gated by a **SwiftPM package trait** that only the test product enables. Two
gates verify it: a test in release configuration asserting no seam is reachable, and a release
gate scanning the shipped binary for seam symbols. Runtime flags are not acceptable here —
R-38's threat model and RK-6 make a runtime-toggleable bypass of the redaction and export path
an attack surface on health data, and QA-38's reasoning stands unchanged.

---

## Soak protocol and the device release gate

Both written to be executed by someone who is not me. Where a step needs judgement, the
judgement is reduced to a decision table.

### 8.1 R-88 — the 21-day soak

**Hardware required.** Non-negotiable list, because the protocol is meaningless without it:

| Item | Requirement | Why |
|---|---|---|
| Soak device | 1 × REF-A class iPhone, **in daily personal use**, with a store holding ≥2 years of real data from ≥3 sources | R-87's store characteristics. A test-bench phone in a drawer generates no data, never locks and unlocks realistically, and never travels — it tests nothing R-88 exists to test |
| Second device (optional, recommended) | 1 × REF-B class iPhone, second destination configuration | Isolates device-specific findings; without it, one finding is one data point |
| Receiver host | An always-on Mac mini or Linux box on the same network, running the reference receiver, a Mosquitto broker and a Home Assistant instance | The three real destinations. Must be always-on: a receiver that sleeps produces discrepancies that are the receiver's fault and burn a day of triage each time |
| Mac companion target | The receiver host, if it is a Mac | Exercises the Mac companion for 21 days, which nothing else does |
| Independent oracle | The soak device itself, via Health → profile → **Export All Health Data** | §8.1.4. This is the leg that makes reconciliation trustworthy |

**Configuration at day 0.** All five destinations enabled. Type selection: the R-61 curated
default (~24 types) plus at least one sensitive type individually opted in (R-66) plus at least
one high-volume type. Notifications **granted** on the primary device and **denied** on the
second if there is one, because R-23's escalation-with-notifications-denied path is otherwise
never exercised for 21 days. Record the app version, OS version, device model, store
characteristics from the characterisation tool, and the R-09 queue cap.

**The daily diary — generated, not typed.** The diary must not depend on a human remembering
things, so the journal (R-20) is the source of truth and the human's job is transport.

- **Human, ~2 minutes/day, at a consistent time:** open the app, tap Export Diagnostics, read
  the R-26 preview (which the human must pass through by design — R-26 makes the preview
  mandatory before any share affordance, and that is correct), share the bundle to a watched
  folder on the receiver host.
- **Hard dependency, per TA-07:** the bundle window must cover **the greater of 30 runs or 24
  hours**. The architect's bound of "last 30 runs" is correct for the interaction, but if run
  frequency exceeds 30/day — plausible in a store-and-forward pipeline where most runs end
  `partial` — a once-daily capture stops covering the day, the diary acquires silent holes, and
  the day-level bisection in §8.1.5 stops working. If that bound cannot move, the soak instead
  uses a test-build time-windowed journal export and the protocol says so.
- **Script, on the receiver host:** ingests the bundle and appends one row per day to
  `soak/<run-id>/diary.csv`: date, app version, OS build, runs attempted, runs by R-21 outcome
  class, samples read / sent / acknowledged per destination, anchor and date-high-water-mark per
  type, R-09 queue depth and any gap records created, R-23 escalation state, freshness age at
  sample time, MetricKit background-exit counters, battery percentage and charge cycles since
  the previous entry. Nothing in this row requires a judgement call.
- **Script also emits a daily gate:** red if no successful run in the last R-24 freshness window
  without a recorded explanation, or if a new gap record appeared, or if any non-normal
  background exit is attributable to the export path. A red day is triaged that day, not at the
  end — a 21-day run that fails on day 2 and is discovered on day 21 costs three weeks.

**Scripted perturbations.** Fixed schedule so runs are comparable across releases, and so the
soak tests the failure modes rather than waiting for them:

| Day | Perturbation | Expected |
|---|---|---|
| 3 | Force-quit the app; leave it quit 24 h | C-04: all background activity stops. R-22 attributes this as scheduling failure, not execution failure. R-23 escalates. Day-4 diary shows the widget's last-success age growing |
| 5 | Airplane mode 6 h | Queue grows, no data lost, recovery on restore |
| 7 | Retroactively insert a sample dated 3 years ago (via a third-party app or Health) | **R-01. The next run re-emits that day's aggregate.** The single most important perturbation |
| 9 | Revoke one type's authorisation | R-44: queued payloads for that type purged within 60 s. R-60: no false denial claim |
| 11 | Break one destination (change its port on the receiver) | R-21 outcome is `failed`, not `success`. R-23 escalates. Other destinations unaffected |
| 13 | Restore the destination | Recovery without duplication (P4) |
| 15 | Travel or manually change time zone; cross a DST boundary if the calendar allows | R-10, FIX-T02/T06 |
| 17 | Delete a sample in Health | R-05 best-effort tombstone, and whichever behaviour occurs is **recorded** (P7) |
| 19 | Fill the queue to the 256 MB cap (bulk import) | R-09 eviction, gap record with an accurate date range (V11) |
| 21 | Nothing — clean final day | Final state is not perturbation-contaminated |

**8.1.4 Final reconciliation — three legs, and the third is what makes it honest.**

1. **App-side counts.** Per type, per day, from R-08's date high-water marks and the journal.
2. **Destination-side counts.** Per type, per day, queried from each of the five destinations by
   a script on the receiver host.
3. **Independent oracle.** Health app → profile → **Export All Health Data**, producing
   `export.zip` containing `export.xml` (plus `export_cda.xml`, workout routes and ECG records).
   Still available in iOS 18 and iOS 26 [13][14]; expect minutes and a file of 200 MB–2 GB on a
   large store. A committed streaming parser counts records per type per day.

Leg 3 is not optional. **Without it, reconciliation compares our count to our count**, and the
whole exercise is self-referential: an app that systematically misses a class of sample reports
perfect agreement between its own watermark and its own destination. Apple's own export is the
only independent view of the store available to us. Note its own limits honestly — it is
all-or-nothing, it can fail or time out on very large stores, and it is a different code path
inside Health with its own quirks — so a leg-3-only discrepancy is investigated before it is
believed.

**8.1.5 Triage — a decision table, not judgement.**

| Observation | Classification | Action |
|---|---|---|
| Legs 1, 2 and 3 agree per type per day | Pass | Record the run; publish counts in the release issue |
| Discrepancy fully accounted for by a matching R-09 gap record (date range and type align) | **Explained** — not a discrepancy (TA-06) | Assert the gap record's range is *exactly* right. A gap record that over- or under-states the loss **is a P1** |
| Discrepancy accounted for by a recorded R-05 deletion-without-callback | **Explained** | Confirm P7 recorded a diagnostic naming the destination |
| Discrepancy accounted for by a recorded C-02 locked-device window with a subsequent successful catch-up | **Explained** | Confirm the catch-up actually happened |
| Legs 1 and 2 agree, leg 3 differs | Suspect the oracle first | Re-run the Health export; check the parser against T0; if it persists, it is a **P1** — it means we are systematically missing a class of sample |
| Leg 1 and leg 2 differ | **P1** | Bisect by day using the diary; identify the run; reproduce as a new FIX-* fixture; the fixture is the fix's regression test |
| Any unexplained discrepancy of any size | **P1 by definition** (R-88) | Release blocked |

Bisection is the reason the diary is per-day and machine-generated. With it, "we lost 41 samples
of `heartRate`" becomes "on day 12, run 3, which had outcome `unknown_ack`" in one query.
Without it, it becomes three weeks of nothing.

**Cadence.** One completed soak record per minor release (R-88). At 21 days plus triage, a soak
is roughly a calendar month, which means the release cadence cannot be faster than that — worth
saying out loud to the PM, and it interacts with the 90-day TestFlight build expiry noted in
§9.4.

### 8.2 R-87 — the device release gate

A scripted pass, executed on named hardware, recorded in the release issue with a signature. Not
exploratory testing: a checklist with expected results, so that a different person running it
next release produces a comparable artifact.

**Hardware and store preconditions:** REF-A and REF-B class devices; ≥2 years of real data from
≥3 named sources; the store's characterisation output attached to the release issue.

**Sections, each with expected results:** first-run flow including R-63's disclosure *before* the
permission prompt; per-feature authorisation (R-62) with one type denied and R-60's copy checked;
the R-69 data browser compared against the Health app for three values, which is the wedge's own
verification surface and the one thing only a human can do; each of the five destinations
configured and R-25's real-path test observed, including the MQTT QoS-0 `Sent, unconfirmed`
result; R-40's notification on adding and on re-pointing a destination; R-31's four elements
present, with a deliberately changed certificate halting export; R-26's bundle exported and a
seeded failure diagnosed *from the bundle alone* by a second person; R-41 confirmed by attempting
to hide a destination and failing; R-07's aggregate compared against
`HKStatisticsCollectionQuery` for one multi-source metric, with any divergence documented; R-33
verified by taking an actual device backup and searching it for credential material; R-43 run,
then the Keychain enumerated by access group and the container inspected; the widget's
last-success age in plain language; a full VoiceOver pass of onboarding, destination
configuration and reading a failure.

**Recorded artifact:** device model, OS build, store characteristics, app build, date, the
operator's name, per-section pass/fail, and every divergence as a filed issue. A section marked
pass with no recorded numbers is not a pass.

---

## NFR verification harness

### 9.1 Every NFR as a six-tuple

R-91's form, with the harness column added. R-70 and R-71 are measurement spikes with no
threshold, and per TA-02 the four asterisked rows have thresholds that rest on an unvalidated
~1,600 samples/s read-throughput assumption and must be re-baselined after R-70 lands.

| ID | Workload | Device | OS | Metric | Threshold | Pctl | Harness | N |
|---|---|---|---|---|---|---|---|---|
| R-70 | Sequential anchored read, 100k samples, mixed types | REF-A, REF-B | iOS 26 | samples/s | published finding | — | Device spike; **gates the four rows below** | 10 |
| R-71 | Observer-query background delivery observed over 14 days | REF-A, REF-B | iOS 26 | findings doc: per-type cap, survival with Background App Refresh off, wake duration | published finding | — | Field instrumentation; feeds R-24's N | continuous |
| R-72* | Delta export of 10,000 samples (T1 slice) → local file and → HTTPS | REF-A / REF-B | iOS 26 | wall clock | ≤ 8 s / ≤ 15 s | p90 | Device harness | 20 |
| R-73* | Headless background launch to first HealthKit query | REF-B | iOS 26 | wall clock | ≤ 400 ms | p90 | `XCTApplicationLaunchMetric` + a journal phase timing | 20 |
| R-74 | Full backfill over T1 | REF-B | iOS 26 | peak RSS | ≤ 100 MB, O(1) in store size | max | Device harness + P13 algorithmically in CI | 5 |
| R-75* | Full backfill, 5 years of typical Watch history (T1) | REF-B | iOS 26 | wall clock | ≤ 30 min, resumable | p90 | Device harness, weekly tier | 20 → see §9.2 |
| R-76 | Cold start to interactive | REF-B | iOS 26 | wall clock | ≤ 1,200 ms | p90 | `XCTApplicationLaunchMetric` | 20 |
| R-77 | Steady state, 5 destinations, normal daily use | REF-A | iOS 26 | % battery / 24 h | ≤ 1.0% | mean | **Folded into the R-88 soak** — §9.3 | 21 days |
| R-78 | One full backfill, foreground-initiated | REF-A | iOS 26 | % battery / run | ≤ 12% | mean | Short untethered protocol — §9.3 | 3 |
| R-79* | Wake budget consumed by telemetry (OTLP enabled) | REF-B | iOS 26 | % of wake budget | ≤ 2% | p90 | Journal phase timings against the measured budget | 20 |

R-73 matters more than R-76: the background refresh budget is roughly 30 seconds, so 8 seconds
of graph construction burns 27% of it before any work happens. The harness must measure it as a
*journal phase timing*, not just as a launch metric, so the number is attributable to a phase.

### 9.2 The honest problem with p90

**p90 of N=7 is the maximum of 7.** §7 states p90 for R-72, R-73, R-75, R-76 and R-79, so the
harness runs **N=20** in-session for those, which puts the 18th-of-20 order statistic at the
threshold with a defensible estimate. Where N=20 is infeasible — R-75 at 30 minutes per
iteration is 10 hours — the harness runs N=5, reports the **maximum** and labels it *"conservative
upper bound on p90, N=5"* in the baseline file. Labelling it honestly costs nothing; calling the
max of 5 a p90 would be exactly the kind of unfalsifiable number R-91 exists to prevent.

### 9.3 Energy — R-77 and R-78, the hardest to automate

The central difficulty: **tethered measurement perturbs the measurement.** A device on USB is
charging, so Instruments' energy log and `powermetrics` give you CPU, GPU, network and wake
*proxies* but not battery drain. Untethered measurement gives you real drain and a coarse
instrument.

The design decision that makes R-77 tractable: **fold it into the soak.** R-77 is "% per 24 h,
mean" and R-88 already puts a real device in real untethered use for 21 days. So:

- The soak diary already records battery percentage and charge cycles daily (§8.1). Add the
  app's own per-wake accounting — CPU time, wake count, bytes transferred, samples processed —
  from the journal, which R-20 requires anyway.
- Attribute drain with the OS's own per-app battery accounting (Settings → Battery → usage by
  app), read daily as part of the diary. Coarse, but it is Apple's number and it is the number a
  user would quote in a bug report.
- **Calibrate a proxy model once**, during a release rehearsal: run a fixed workload tethered
  (collecting CPU/wake/network proxies via `xctrace`) and untethered (collecting drain), and fit
  drain against the proxies. Thereafter, per-PR regressions in the *proxies* — CPU time per
  1,000 samples, wakes per run, bytes per sample — are the fast signal, and they are measurable
  in CI. The proxies are gated; the energy number is not.
- 21 days at N=1 device gives a mean with real variance from real use. Report the mean **and the
  day-to-day standard deviation**, because that is what makes the next bullet possible.

R-78 gets a separate short protocol: charge to 100%, disable other apps' background refresh,
note battery percentage, run one full foreground-initiated backfill (R-78 explicitly forbids
initiating it from a system-scheduled background task), note percentage again. N=3, report mean.

**And the honest limit on the >20% regression gate.** R-91 mandates a >20% regression gate
against a committed baseline. For wall-clock and memory NFRs that is sound at N=20. For R-77 and
R-78 the measurement uncertainty from real-world use plausibly exceeds 20%, which would make the
gate fire on noise and then get disabled — the worst outcome. Policy: **gate only when the
measurement's confidence interval excludes baseline + 20%.** Otherwise it is a warning with a
named human decision recorded in the release issue. Where the confidence interval is wider than
the gate, say so in the release notes rather than reporting a number that cannot support the
conclusion.

### 9.4 Baselines

**Committed JSON, not Xcode's baseline mechanism.** Xcode stores baselines per device
configuration inside the project file, which is opaque to review and hostile to forks — a
contributor's fork inherits baselines for hardware they do not own. Instead one file per
(device, OS, workload) recording: the six-tuple, N, every raw measurement, the derived
statistic, the device's model identifier and OS build, the app build and commit, the corpus seed
and slice, and the date. Reviewable in a PR, diffable, and forks can read it without owning the
hardware.

The comparison is a script: >20% worse than baseline fails the pre-release job (subject to §9.3's
confidence-interval rule), >10% raises a warning annotation. Simulator numbers are **advisory
only** — useful for catching a 10× algorithmic regression, useless for anything finer — and are
never written to a baseline file.

---

## CI topology

### 10.1 Verified cost and limit facts

| Fact | Value | Source |
|---|---|---|
| Standard GitHub-hosted runners, **including macOS**, on public repositories | **Free**, on any plan, explicitly reaffirmed in the 2026 pricing change | [15][16] |
| Larger runners | **Always billed**, even on public repositories | [15][17] |
| Private-repo rates (from 1 Jan 2026, after a ~40% cut) | macOS 3/4-core `actions_macos` **$0.062/min**; Linux 2-core x64 **$0.006/min**; Linux 2-core arm64 $0.005; Linux 1-core slim $0.002; Windows 2-core $0.010 | [15][17] |
| Included private-repo minutes | 2,000/mo Free; 3,000 Pro and Team; 50,000 Enterprise Cloud | [15][18] |
| macOS **concurrency** sub-limit | **5 concurrent macOS jobs** on Free/Pro/Team (50 Enterprise), account-wide; excess queues | [15][19] |
| Self-hosted runner charge | A $0.002/min platform charge was announced 16 Dec 2025 for 1 Mar 2026 and **postponed indefinitely** within 48 hours; not in effect. GitHub called it postponed, not cancelled | [20][16] |
| No Docker on GitHub-hosted macOS runners | Nested virtualisation unsupported (Apple Virtualization Framework limitation) — this is C-13 | [19] |
| Docker Hub anonymous pulls | 100 per 6 h per IPv4 or IPv6 /64 subnet, shared behind an address; authenticated Personal 200/6 h | [11][12] |
| Job minute rounding | Each job rounded up to the whole minute | [17] |

**The economics.** The repository is public under AGPL-3.0 (D-01), so T0–T2 cost **$0**. If it
ever went private, the modelled load below is roughly **$150–170/month** on macOS alone, and the
strategy would need rework. That makes "the repository stays public" a CI architecture decision,
not just a licensing one — worth recording as such. Self-hosted is $0 from GitHub today, but the
postponed charge means **future self-hosted pricing must be treated as uncertain**; at the T3
volume below, a $0.002/min charge would be a few dollars a month, so this is a monitoring item
rather than a risk.

**Concurrency, not price, is the real constraint.** Five concurrent macOS jobs account-wide
means a wide macOS matrix queues behind itself. Hence: exactly one macOS job on the PR path, and
the matrix at night.

### 10.2 Tiers

| Tier | Trigger | Runner | Contents | Budget | Fork-safe (R-85) |
|---|---|---|---|---|---|
| **T0** | Every push | `ubuntu-latest` | Core build, Swift 6 strict concurrency, warnings-as-errors; **L1 + L2 (short budget) + L3 on Linux**; exit-test seam suite (R-83); R-84 determinism (same input twice, plus hostile locale and time zone); R-80 assertion (no Apple framework in the core's dependency graph); R-81 lint (ambient clock/calendar/zone/locale ban with the reviewed allowlist); R-51 redaction canary; schema validation of frozen fixtures (R-12); seam enumeration and release-config unreachability; FIX-catalogue completeness meta-test; `swift format lint --strict`; SwiftLint strict; DCO check (R-101); licence allowlist (R-36); secret and PII scan; DocC build; markdown/link lint | **≤ 6 min** | **Yes** |
| **T1** | Every PR — **required** | 1 × `macos-*` | Build every target (iOS, iPadOS, macOS companion, widget); L1–L3 on one Simulator (iOS current); L5 key screens with accessibility audits; **MQTT contract via Homebrew Mosquitto** (C-13); **Mac companion Layer B loopback transport**; the local-file/HTTPS differential test; coverage collection | **≤ 15 min**, `cancel-in-progress` | **Yes** |
| **T1b** | Every PR — **required** | `ubuntu-latest` | **R-89 leg 1: real Home Assistant at current stable, with statistics read-back** (§6.2); **R-90: real Mosquitto**; scriptable HTTP server contract suite; request-template injection suite (FIX-F08). Images from the public registry mirror — no secret | **≤ 14 min** | **Yes** |
| **T2** | Merge queue + nightly | `ubuntu-latest` + `macos-*` | **T1 corpus (10M) end-to-end on Linux**; long property budgets with high iteration counts and fresh seeds; **R-89 leg 2: oldest in-window HA version**; full Simulator matrix (iOS 18.0 floor and current, iPadOS); full L5 accessibility across the screen × state matrix; pseudo-locale and RTL screenshot sets; OTLP collector contract (R-53); upstream canaries (HA current stable and beta channel, Mosquitto latest); mutation testing on critical modules (weekly, not nightly) | ≤ 60 min | Yes, but not required checks |
| **T3** | `workflow_dispatch`, tags, weekly | **Self-hosted** Mac + physical iPhones, protected environment | R-87 device pass harness; **R-91 NFR baselines on REF-A and REF-B**; T2 corpus (50M); **Mac companion Layer C two-device**; R-33 backup test; R-78 energy protocol; TestFlight upload | hours | **Never on fork PRs** |
| **T4** | Continuous, human | Maintainer devices | R-88 soak; R-77 energy; TestFlight cohort; MetricKit background-exit review | 21 days | n/a |

**Why R-89 and R-90 moved onto the PR path.** In Stage 1 I put container contract tests nightly.
I am changing that: they are free on Linux, they need no secrets, and R-89's failure mode is the
single most embarrassing bug available to us. The compromise that keeps the fast path fast is
that only the *current stable* HA leg is per-PR; the oldest in-window leg is nightly. Total
required-check wall time stays ≈15 min because T0, T1 and T1b run in parallel.

**Self-hosted runner security (unchanged and non-negotiable).** A self-hosted runner must never
execute code from a fork pull request. It runs only on `workflow_dispatch`, on tags, and in a
protected environment requiring maintainer approval — enforced by a CI policy check that fails
if any self-hosted job carries a `pull_request` trigger. The alternative is arbitrary code
execution on a machine holding signing keys and a real health store.

**Cost hygiene regardless of price:** `concurrency: cancel-in-progress`; a merge queue so macOS
minutes are not burnt on every rebase; aggressive SPM and DerivedData caching; path filters so a
documentation-only PR never touches a Mac.

### 10.3 The fork path (R-85)

A fork PR runs T0, T1 and T1b, and every required check is in those three. No secret is
referenced by any required check. The container images come from the public registry mirror, so
no registry credential and no Docker Hub rate limit. **This is verified by an actual fork PR
going green, re-verified each release**, not by inspecting workflow files — R-85's acceptance
criterion is a green fork PR and nothing weaker counts.

Also required for genuine openness (and the thing most projects get wrong): a **build-from-source
path** needing no Apple Developer Program membership and no App Store Connect access, verified
by a CI job that builds from a clean checkout following only the README. Contributors must be
able to build and test without being added to an Apple team. It doubles as R-108's reproducibility
check.

### 10.4 Release engineering notes that bear on scheduling

TestFlight builds **expire 90 days after upload** with no extension, so an external cohort
silently loses the app unless a beta ships at least every 60 days. Combined with R-88's ~1-month
soak cycle, the release cadence is bounded below by the soak and above by the TestFlight expiry,
which is a tight corridor for a small team and worth the PM's attention. A scheduled job checks
the external group's remaining validity and warns below 30 days.

---

## Definition of Done and quality gates

### 11.1 Definition of Done

A checklist in the PR template, not a vibe.

1. The requirement is linked and its acceptance criterion restated in the PR body.
2. Builds clean for every shipped platform, warnings-as-errors, Swift 6 strict concurrency. No
   new `@unchecked Sendable`, `@preconcurrency`, `nonisolated(unsafe)` or `@retroactive`
   conformance without a linked ADR.
3. New behaviour has a test **at the lowest layer that can catch it**. A UI test for a
   serialisation bug is not acceptable.
4. Bug fixes include a regression test that demonstrably failed before the fix, and the PR states
   that it was observed failing.
5. **If the change touches a §6.6 seam** — the HealthKit port, the clock ports, the transport
   ports, a fault seam, the checkpoint format, the corpus generator — the PR states which R-80…
   R-91 row it affects and why the row still holds.
6. Data-format or persisted-state changes ship a migration **and** a migration test using
   committed fixtures from the previous released version.
7. New log or telemetry statements are reviewed against the allowlist registry (P12), and any
   new allowlist entry carries an argued justification.
8. A new FIX-* case, if the bug was a corpus miss, plus a row in the corpus-miss ledger (§4.4).
9. New or changed screens pass the automated accessibility audit and have been checked at the
   largest Dynamic Type size; every suppressed audit issue carries a comment and an issue link.
10. All new user-facing strings are in the string catalogue with translator comments.
11. Public API documented (DocC); user-visible changes have a CHANGELOG entry.
12. No new dependency without a licence check, a maintenance assessment and an ADR.
13. If the change can only be validated on hardware, the device smoke checklist is completed and
    recorded by a human who names the device and OS build.

### 11.2 Coverage policy — the honest view

**A single global coverage percentage is a bad gate for this product, and I would rather say so
now than defend a number later.** The reason is structural, not philosophical: the least
coverable code — the HealthKit adapter, the Network.framework transport, background scheduling,
platform glue, SwiftUI view bodies — is also the riskiest, so a global threshold pushes
contributors to write tests for trivially coverable code in order to move the number. That is
worse than no gate, because it costs real effort and buys false confidence. And in this project
the incentive is sharper than usual: the genuinely dangerous code is *behind* R-80's seams, on
the Apple side, where coverage is hardest.

Policy instead:

1. **Measure and publish** on every T1 run, with a PR comment showing the delta. Visibility, not
   veto.
2. **Gate designated critical modules at ≥ 90% line coverage**: transform, serialisation per
   format, unit canonicalisation, calendar arithmetic, bucket-key derivation, the aggregation
   engine, the anchor/checkpoint state machine, the retry policy, redaction, the request-template
   evaluator, the Mac companion session state machine. The list is committed and changing it is a
   reviewed change.
3. **100% transition coverage on the anchor/checkpoint state machine** — an explicit
   transition-enumeration assertion, not a line count. This is the machine whose failure loses
   data forever (P5), and line coverage does not distinguish "executed" from "exercised".
4. **≥ 80% patch coverage on changed lines**, with a maintainer-approved waiver path for platform
   glue.
5. **Explicitly excluded from the number**: the HealthKit adapter, the Apple transport
   conformances, SwiftUI view bodies, generated code. Excluding them is honest; including them
   and then gaming them is not.
6. **Mutation testing** on the critical modules on a weekly schedule, as a check on test
   *quality* — coverage measures execution, not assertion. A property suite with weak oracles
   scores 100% line coverage and catches nothing.

### 11.3 Flakiness

A flaky test is a bug against the person who wrote it. Any test failing intermittently is
quarantined — tagged, skipped, issue filed with an owner and an expiry — **within one business
day**. Flake rate is computed over the last 20 nightly runs and published. **No release ships
with a flake rate above 1%**, because a suite people rerun until green is the same as no suite.
The device and UI tiers are kept deliberately small for this reason, and a flaky test is never a
required check.

### 11.4 Release gate

T0–T2 green; T3 green on the release candidate; canaries green in the last 24 h or
dispositioned; **a completed R-87 device pass, signed, naming device, OS build and store
characteristics**; **a completed R-88 soak record with the three-leg reconciliation and zero
unexplained discrepancies**; R-91 baselines within tolerance (or a recorded human decision per
§9.3); the R-78 energy record; upgrade-in-place test from the previous released version using a
migrated real-shaped store; zero open P0/P1; accessibility audits clean with a recorded manual
VoiceOver pass; localisation completeness at or above threshold for shipped languages; a green
fork PR; the release-binary symbol scan showing no seam or test-only symbols. Phased App Store
release with a 72-hour observation window on crash, hang and background-exit metrics before
advancing, and a named rollback decision owner.

---

## What we deliberately will not verify before release, and how we detect it in the field

Each row names the field detector, because an unverified thing with no detector is an unowned
risk, and this table is the honest counterweight to everything above.

| Not verified pre-release | Why | Field detection |
|---|---|---|
| Background delivery **timing** in the wild across the device population | C-03: frequency is a ceiling, throttled by battery, budget and lock state. No sound assertion exists | R-71's measured distribution; R-23's escalation makes lateness visible to the user; R-27's freshness signal is consumable by the user's own monitoring |
| Continuity beyond 21 days | R-88 is 21 days; the product's real horizon is years | R-23 escalation; R-27's signal; the observer-completion-handler bug class (a single missed completion stops all future delivery) is exactly what R-23 exists to surface |
| **Anchor durability under a real iOS process kill** | Exit tests are unavailable on iOS [1][3]; jetsam and watchdog kills are observable, not scriptable (TA-13) | MetricKit background-exit counters, especially the suspended-while-holding-a-file-lock counter, which is precisely the mid-export suspension signature. **Gate: zero non-normal background exits attributable to the export path across the beta cohort before a release advances** |
| Mac companion over real Wi-Fi: AWDL, roaming, Mac sleep/wake, congested networks | Layer B is loopback; Layer C is one iPhone and one Mac on one network | Per-destination failure counters and reason codes in the journal, so a bug report contains a reason code rather than "it stopped working" |
| Energy as a pass/fail gate | Tethered measurement perturbs the measurement; untethered variance likely exceeds the 20% gate (§9.3) | Proxy regressions (CPU per 1,000 samples, wakes per run, bytes per sample) gated in CI; Xcode Organizer energy metrics from the TestFlight and release cohorts; R-88's daily battery diary |
| HA versions outside the declared window, and HA versions released after ours | Unbounded matrix against a monthly train [4] | Nightly canary against current stable and the beta channel, opening a tracking issue on divergence. A canary red >24 h without disposition blocks a release |
| Multi-source de-duplication against **HealthKit's own** behaviour | We cannot forge `HKSource`; anything we write is attributed to us. So FIX-S01 is verified against *our model* of HealthKit, never HealthKit itself | R-07's device comparison against `HKStatisticsCollectionQuery`; R-87 requires ≥3 real sources; R-69's data browser lets the user check our number against Health's |
| Read-denial versus empty store | Apple guarantees these are indistinguishable | Impossible to detect, ever. Handled by R-60 stating both causes rather than by a test. The strongest honest claim is "we exported everything HealthKit returned" |
| Older hardware below REF-B, and locale/keyboard/region combinations at scale | No affordable device farm exists for Apple platforms at OSS budgets | A **community device matrix**: a scripted, copy-pasteable checklist volunteers run on their own hardware, results recorded in a committed file with device, OS build, date and outcome. Target ≥5 results across ≥3 device classes before v1. Not a substitute for a device farm; it is what we have, and saying so is better than implying coverage we lack |
| App Review outcome | Not testable | Pre-submission dry run against RK-3's mitigations (R-69, R-62, R-114) |
| Corpus realism itself | Unfalsifiable in CI by construction | §4.4's four signals, chiefly the corpus-miss ledger |

---

## Open questions for the PM

1. **What does R-91 mean between now and R-71's completion (TA-02)?** R-71 is one engineer-day of
   harness plus **five calendar weeks** of soak, so no Stage 2 close sooner than that can have
   it. I propose R-91 be recorded as *mapped, pending measurement*, with §7's four affected
   thresholds marked provisional and a named re-baseline gate at M1. What I cannot do is report
   R-91 as met. Related: R-24's freshness target N is unstatable until R-71 lands, and N appears
   in-product and in the README.
2. **R-88 versus R-09 and R-05 (TA-06).** Will you amend R-88 to *unexplained* discrepancy, with
   the three explanation classes in §8.1.5? Without it a correctly-behaving product can fail its
   own release gate, and the gate will be waived the first time it fires — which is how a Must
   becomes decorative.
3. **Who owns the Home Assistant supported-version window (TA-05)?** I propose current stable
   back to current stable − 11 releases, with a monthly bump issue. It needs a named owner
   because HA ships on the first Wednesday of every month [4] and an unowned matrix rots inside
   two months.
4. **R-83's seam count (TA-08).** The reliability design asks whether to raise it to seven. My
   answer is no: six *locations*, orthogonal injection vocabulary, and the count stands. I am
   recording it here so you do not receive two contradictory recommendations.
5. **Is the Health app's "Export All Health Data" the sanctioned independent oracle for R-88?**
   It is the only independent view of the store we have, and without it reconciliation compares
   our count to our count (§8.1.4). It also means a maintainer's real `export.xml` exists on the
   receiver host during a soak — which is real health data, outside the repository but inside our
   process. I need an explicit handling rule: where it lives, that it never enters git, CI or an
   issue attachment, and when it is destroyed.
6. **Hardware budget.** One always-on receiver host, one REF-A daily-driver iPhone with real
   history, one REF-B, and ideally a second soak device. Without the receiver host, R-89/R-90
   canaries and the soak's destination legs do not exist. Without a REF-B, half of §9's
   thresholds are unmeasured — and REF-B is where they are most likely to fail (RK-2).
7. **Public container-registry mirror (§6.1).** Publishing the pinned HA/Mosquitto mirrors as
   public packages is what makes R-89 and R-90 fork-safe without a secret. It is a visibility
   decision and I would like it confirmed rather than assumed, even though it follows naturally
   from the repository being public. The build-and-release design pins runner image labels rather
   than using `ubuntu-latest`/`macos-latest` on the release path, which is correct; the same
   pinning discipline should apply to the mirrored images.
8. **Name a reference Mac for R-82 (TA-12)**, and confirm the T0/T1/T2 tier naming so the
   ≤10-minute budget binds to the 10M tier rather than to the 200 committed samples.
9. **Release cadence corridor (§10.4).** R-88's ~1-month soak cycle and TestFlight's 90-day
   build expiry bound the cadence from both sides. Is a minor release every 6–8 weeks the
   intended rhythm? It affects how many soaks a year we owe.
10. **Does the app ship a demo/fake-data mode in release builds?** R-114 requires a synthetic
   dataset and demo mode, and R-83/QA-38 require test-only code absent from release. These are
   reconcilable — a demo mode built on the *shipped* corpus reader rather than on the fault seams
   — but it needs a product decision about whether demo mode is a release feature or a test
   artifact, because the two have different attack surfaces.
11. **Second maintainer (D-10) and the soak.** R-88 requires a maintainer's daily-driver phone
    for three weeks per release. With one maintainer, that is one device, one store shape, one
    usage pattern, and one person's availability gating every release. This is a continuity risk
    (RK-1) expressed through the test strategy, and a second maintainer with a second real store
    is the cheapest mitigation available.

---

## Sources

Facts verified for this document during Stage 2. Stage 1's 41 sources remain the basis for the
HealthKit, Simulator, MetricKit, TestFlight and accessibility claims and are not repeated here.

1. Swift Evolution ST-0008, *Exit tests* — status **Implemented (Swift 6.2)**; supported on
   macOS, Linux, FreeBSD, OpenBSD and Windows; `SWT_NO_EXIT_TESTS` where unsupported.
   <https://github.com/swiftlang/swift-evolution/blob/main/proposals/testing/0008-exit-tests.md>
2. Swift Evolution ST-0012, *Exit test value capturing* — status **Implemented (Swift 6.3)**;
   captured values must be `Sendable` and `Codable`.
   <https://github.com/swiftlang/swift-evolution/blob/main/proposals/testing/0012-exit-test-value-capturing.md>
3. Swift Testing toolchain matrix — exit testing requires Swift 6.2 / Xcode 26.0; capture lists
   require the Swift 6.3 compiler; **not for iOS/tvOS/watchOS runtime targets**;
   `Issue.record(_:severity:)` and `Test.cancel(_:)` from Swift 6.3 / Xcode 26.4. *(Secondary
   source; the primary claims are corroborated by 1 and 2.)*
4. Home Assistant — Release FAQ: a new stable version on the **first Wednesday of every month**,
   with weekly patch releases and a ~1-week beta period.
   <https://www.home-assistant.io/faq/release/>
5. Home Assistant Developer Docs — Versioning (CalVer `YYYY.MM.PATCH`).
   <https://developers.home-assistant.io/docs/versioning/>
6. Home Assistant — Unsupported Core version: Supervisor treats Core older than **24 months
   (~24 releases)** as unsupported; update in increments of no more than 6 releases.
   <https://github.com/home-assistant/home-assistant.io/blob/current/source/more-info/unsupported/home_assistant_core_version.markdown>
7. Apple — WWDC26 session 267, *Migrate to Swift Testing*: UI automation and performance testing
   APIs remain XCTest-only. <https://developer.apple.com/videos/play/wwdc2026/267/>
8. *Swift Testing vs XCTest migration guide (2026)*: `XCUIApplication` and `XCTMetric` remain
   XCTest-only in Xcode 26. *(Secondary; corroborates 7.)*
9. Swift Testing / XCTest coexistence and `SWIFT_TESTING_XCTEST_INTEROP_MODE`. *(Secondary.)*
10. GitHub Docs — Advisory Database supported ecosystems: Swift is listed with "registry: N/A",
    so advisory coverage is thinner than npm or pip.
    <https://docs.github.com/en/code-security/concepts/vulnerability-reporting-and-management/github-advisory-database>
11. Docker Docs — Docker Hub pull usage and limits: **unauthenticated 100 pulls per 6 hours per
    IPv4 address or IPv6 /64 subnet**; authenticated Personal 200; Pro/Team/Business unlimited.
    <https://docs.docker.com/docker-hub/usage/pulls>
12. Docker Hub rate-limit behaviour in shared-IP CI environments, and the `ratelimit-limit` /
    `ratelimit-remaining` headers. *(Secondary; corroborates 11.)*
13. Apple Support — *Share your data in Health on iPhone* (iOS 26 and iOS 18): Summary → profile
    → **Export All Health Data**, XML format.
    <https://support.apple.com/guide/iphone/share-your-health-data-iph5ede58c3d/26/ios/26>
14. Contents and practical size of `export.zip` — `export.xml`, `export_cda.xml`,
    `workout-routes/`, ECG records; 200 MB–2 GB on a large store; minutes to produce.
    *(Secondary; corroborates 13 on contents and adds the size and duration observations.)*
15. GitHub Docs — GitHub Actions billing: **free for public repositories on standard
    GitHub-hosted runners**; larger runners always billed; macOS `actions_macos` **$0.062/min**;
    Linux 2-core x64 $0.006/min; included minutes 2,000 Free / 3,000 Pro-Team / 50,000
    Enterprise Cloud. <https://docs.github.com/en/billing/concepts/product-billing/github-actions>
16. GitHub — *Pricing changes for GitHub Actions* (2026): "GitHub Actions will remain free for
    public repositories"; ~40% rate reduction from 1 Jan 2026; **"We're postponing the announced
    billing change for self-hosted GitHub Actions"**.
    <https://github.com/resources/insights/2026-pricing-changes-for-github-actions>
17. GitHub Docs — Actions runner pricing reference: per-minute rates; jobs rounded up to the
    whole minute; included minutes never apply to larger runners; larger runners not free for
    public repositories. <https://docs.github.com/en/billing/reference/actions-runner-pricing>
18. Included-minute allowances by plan. *(Secondary; corroborates 15.)*
19. GitHub Docs — GitHub-hosted runners reference: **macOS concurrency sub-limit of 5 on
    Free/Pro/Team** (50 Enterprise), account-wide; **"Nested-virtualization is not supported due
    to the limitation of Apple's Virtualization Framework"** — the basis of C-13.
    <https://docs.github.com/en/actions/reference/runners/github-hosted-runners>
20. GitHub Changelog, 16 December 2025 — the $0.002/min self-hosted platform charge announced for
    1 March 2026, and its postponement. Independently reported as still not in effect as of
    mid-2026, with no new timeline; GitHub described it as postponed rather than cancelled, so
    **treat future self-hosted pricing as uncertain**.
    <https://github.blog/changelog/2025-12-16-coming-soon-simpler-pricing-and-a-better-experience-for-github-actions/>

**Confidence notes.** Sources 1, 2, 4, 5, 6, 7, 11, 13, 15, 16, 17, 19 and 20 are Apple, GitHub,
Docker, Home Assistant or Swift Evolution primary sources. Sources 3, 8, 9, 12, 14 and 18 are
secondary and are flagged in the text where they carry weight; in each case a primary source
corroborates the load-bearing part of the claim. Two claims in this document are **verified
absences** rather than positive citations and I would welcome counterexamples: that no
programmatic path exists to populate the iOS Simulator's HealthKit store, and that GitHub
publishes no guarantee of Docker Hub rate-limit exemption for hosted runner IP ranges. The
§2 audit was performed against the seven Stage 2 design documents present in
`docs/02-design/` on 2026-09-03; `04-security-*.md` was absent, which is finding TA-01. Where a
finding rests on a claim inside another designer's document rather than on a primary source, the
document is named so the PM can check it at source. §2.5's instrument will be re-run against the
security design and against any revision of the other six before Stage 2 review.
