# System Design Document

**Product:** open-health-exporter (name pending D-06)
**Stage:** 2 of 4
**Status:** **APPROVED v0.2** — Stage 2 closed 2026-09-03. Owner approved the design and authorised Stage 3.
**Author:** Coordinating PM, synthesising nine specialist designs
**Date:** 2026-09-03

---

## 0. How to read this

This is a synthesis and a decision record, not a replacement for the nine design documents in
this directory. Those total ~12,900 lines and each is authoritative in its own area. This
document does four things they cannot do for themselves: state the shape of the system in one
place, resolve the conflicts between them, record the open questions and how each was settled,
and carry forward the requirements changes that Stage 2 discovered.

| # | Document | Lines | Owns |
|---|---|---|---|
| 01 | `01-system-architecture.md` | 1,242 | Decomposition, correctness engine, concurrency, sink contract, persistence, milestones |
| 02 | `02-healthkit-layer.md` | 1,360 | The seam, query strategy, delta correctness, aggregation, background orchestration, the spikes |
| 03 | `03-wire-format-spec.md` | 1,466 | Schema, encodings, versioning, HAE profile, Home Assistant mapping, receiver contract |
| 04 | `04-security-design.md` | 1,451 | Threat model, control designs, anti-coercion, advisory channel, LAN surfaces, supply chain |
| 05 | `05-observability-design.md` | 1,604 | Journal, outcome taxonomy, failure attribution, escalation, OTLP, redaction |
| 06 | `06-interaction-design.md` | 1,778 | IA, screens, status model, escalation UI, data browser, accessibility, copy |
| 07 | `07-test-architecture.md` | 1,326 | Test architecture, corpus, properties, contract tests, CI, and the cross-audit |
| 08 | `08-reliability-design.md` | 1,205 | Delivery semantics, queue, retry, crash safety, backfill, NFR budgets, degradation |
| 09 | `09-build-and-release.md` | 1,490 | Repo layout, signing, release, reproducibility, governance artifacts, compliance gates |

### 0.1 What changed in v0.2, and why

v0.1 was rejected. The engineering was not the problem — the reviewer's "could not falsify"
section runs to twelve items and covers every load-bearing mechanism. **The synthesis was the
problem.** It dropped thirteen specialist amendments while claiming "six places", misidentified
the QA lead's headline finding, and checked two exit criteria that were false.

The root cause is recorded in `reviews/01-disposition.md` §2 and is worth stating here because
it is a standing hazard rather than a one-off: PRD §6.3 contains this project's own apology for
running an unauditable requirements filter at Stage 1. I ran one again at Stage 2, against the
same specialist. Four of the five Blockers are downstream of that single mechanism.

Two structural changes exist to stop it recurring:

- **§4.4 is new** — a contact table with one row per cross-document interface. Every collision
  v0.1 missed was the same shape: two specialists designing one interface from opposite sides,
  each internally consistent, neither wrong alone. Six rows would have caught four Blockers.
- **§5 now carries every "cannot build / cannot secure as written" item** with an explicit
  accept-or-reject line. Six amendments became twenty. The filter is auditable by construction
  rather than by my diligence.

---

## 1. Executive summary

**The designs converged on structure and collided on interfaces.** That is the normal and
expected output of nine specialists working in parallel, and v0.1's claim that they "converged
rather than collided" was both wrong and causally upstream of its failures — a synthesis that
opens by declaring convergence has stopped looking for collisions.

The convergence on structure is real and remarkable: the seam, the layering, the write-ahead
cursor, and the fault-injection vocabulary were reached independently by designers who could not
see each other's work. The QA lead entered the stage having drafted four pre-emptive Blockers
against designs he had not yet read, and **withdrew all four** because the designers had solved
the problems first. He then filed one new Blocker and five Majors, four of which v0.1 dropped.

The collisions were on interfaces: whether a webhook can report success (§4.3), which Data
Protection class the journal uses (§4.3), what R-23's escalation threshold is (§4.3), and
whether the canonical aggregate is computable without HealthKit (§5, A-9). Each is now resolved
and recorded in §4.4.

The system is built on a single idea, stated most clearly by the architect: the product's claim
is about *knowledge*, not transport. "We can tell you truthfully what we exported and what we
did not" is only credible if the invariants are **enforced by type and transaction boundaries
rather than by their authors' discipline**, because the authors are one to two people over
twenty-plus months and discipline does not survive that. Every significant decision below is an
application of that principle.

Five structural decisions carry the design:

1. **One engine, five sinks, a contract narrow enough to be a conformance suite.** A sink
   receives a file handle plus an idempotency key and returns a classified outcome. It holds no
   cursor, no retry state, no credentials, no persistence. The Mac companion is a capability
   flag, not a special case.
2. **The write-ahead anchor invariant is structural, not conventional.** There is no API that
   persists an anchor. A cursor advance is only accepted as a field of a batch-commit
   transaction, the transaction closure is synchronous so it contains no suspension point, and
   the run outcome is a *derived function of a tally* rather than a value any code path can
   assign.
3. **Anchors prove progress; only date-ranged sweeps prove coverage.** This is the answer to
   R-01 and it is the design's sharpest insight. `HKQueryAnchor` orders by write sequence, so it
   can never certify that an interval of *measurement* time is complete. The measurement-time
   watermark therefore never advances on anchored delivery — only on a bounded date-predicated
   enumeration that positively covers a closed interval. Anchored delivery carries raw samples
   and separately *dirties* every aggregate bucket its samples touch, however old. That
   dirty-bucket ledger turns R-01's "re-emit a 30-day-old window" from a special case into a
   normal operation.
4. **Completeness is audited by one bounded artefact** — a permanent per-(metric, day) census
   digest, with a UUID-level index only inside the reconciliation window. One data structure
   serves four requirements: R-08's reconciliation, R-05's convergence path (deletion by
   absence), R-88's day-21 soak reconciliation, and R-69's data browser.

   *Bounded means bounded:* the UUID index holds ~1.2 M rows at ~40 bytes, so its horizon is
   **~60 days at REF-DELTA's 20,000 samples/day**, not the "~400 days" v0.1 carried — that
   figure holds only at ~3,000 samples/day. Beyond the horizon a deletion cannot be attributed
   to an aggregate bucket until a reconcile. Per O-9 that reconcile is now **scheduled and
   automatic**, so convergence no longer depends on a user action nothing prompts.
5. **A HealthKit-free, Linux-buildable core of fourteen targets**, with a committed dependency
   adjacency manifest enforced in CI. `HealthKitAdapter` is a leaf nothing in core depends on,
   so the moment a core target imports it the Linux job fails.

   *With one committed exception (A-9).* Because §4.3 rules HealthKit's de-duplicated statistic
   canonical, the canonical aggregate for multi-source cumulative metrics is **not** computable
   in a HealthKit-free core. Those metrics are exercised on Linux against recorded reference
   vectors and gated by R-87's device pass. The list is generated from `MetricCatalog` and
   asserted non-growing without an ADR.

Three findings from Stage 2 change the requirements rather than merely implementing them (§3),
and twenty amendments now carry those changes into the PRD (§5).

---

## 2. System shape

### 2.1 Decomposition

Fourteen targets in one SPM package, in a monorepo, plus a second repository for the Home
Assistant integration (HACS requires one repository per integration with GitHub releases
driving versions, which a monorepo cannot satisfy).

The layering is enforced, not documented: acyclicity is proved by level assignment, and what CI
enforces is the *absence of forbidden edges* rather than the absence of cycles, since SPM
already refuses cycles. The Linux build is the enforcement mechanism — it is a required check
from the first commit, and it fails the moment core touches HealthKit.

### 2.2 The seam

`HealthSource` exposes page-at-a-time `AsyncSequence`s of `Sendable`, `Codable`, project-owned
domain values. **No `HK*` type crosses it, including `HKQueryAnchor`**, which crosses as an
`AnchorToken` — versioned opaque `Data` the core never interprets. `HKSample` is converted to
owned value types *inside the query callback, before the continuation resumes*, so no
non-`Sendable` HealthKit object ever crosses an isolation boundary.

The fixture-backed fake reads the *same* NDJSON domain encoding the real adapter emits, which
is what makes the fake trustworthy rather than merely convenient. One CI source scan enforces
that exactly one file in the codebase may say `import HealthKit`.

### 2.3 Persistence

System SQLite behind a `StateStore` port, via a first-party thin wrapper over prepared
statements and transactions. Chosen over GRDB, SwiftData and Core Data primarily because R-80
makes Linux a required check from the first commit, and GRDB's Linux support is explicitly
untested and unmaintained upstream. §4.2 records that I overrode this and then withdrew the
override on verification, along with the architect's reversal trigger.

**Data Protection classes are split, per §4.3 and ADR-OBS-03:**

| Data | Class | Reason |
|---|---|---|
| State and journal tables | **C** — `CompleteUntilFirstUserAuthentication` | A background wake hours after lock must *open* the database cold. Class B forbids that |
| Payload blobs | **B** — `CompleteUnlessOpen` | These hold sample values. They are written during a wake, not opened cold |

This supersedes ADR-0005, which put the whole database at Class B. The first-party wrapper makes
the flag **directly settable at open**, which is one of the reasons the §4.2 withdrawal matters
beyond the dependency question — GRDB mediates it through configuration hooks.

### 2.4 Wire format

RFC 3339 UTC instants plus a separate integer offset and a time-zone provenance enum. Every
sample carries `HKObject.uuid` as a first-class field; deletions are a separate tombstone
stream keyed the same way. Three properties are kept rigorously distinct — record identity
(`uuid`), delivery idempotency (`batchId`), and byte-determinism (RFC 8785 canonicalisation) —
because conflating them is precisely the error the Stage 1 review caught.

CSV is **declared non-convergent in the specification itself**, because a CSV consumer who
loads only the samples file will never see the tombstones.

---

## 3. The three findings that change requirements

### F-1 — The Health Auto Export compatibility profile cannot carry our wedge

The schema engineer researched the incumbent's actual payload from its Help Center and from the
Go type definitions in `apple-health-ingester`, the receiver most third parties build against.
The finding is unambiguous: **HAE metric datapoints carry no stable identifier at all** — only
workouts (v2) and State of Mind entries have an `id` — and **the format has no way to express a
deletion**.

So the compatibility profile structurally cannot carry R-02 (upsert by UUID) or R-05
(tombstones). It buys day-one access to the incumbent's receiver ecosystem — which MA-03
identified as their real moat — at the price of the two properties that are our reason to
exist.

**Resolution (revised in v0.2).** v0.1 proposed a one-time acknowledgement screen. That control
is wrong, and the adversarial reviewer's objection is decisive: a one-time click is the right
instrument for a loss the user experiences immediately and can attribute, but **this loss is
silent and undetectable by construction**. With no tombstones and no upsert key, the destination
quietly accumulates records Apple Health has since deleted — the incumbent's exact failure mode,
and the one this product exists to fix. A consent click weeks before the first divergence arms
nobody.

Ship the profile, with three properties instead of a screen:

1. **Structurally ineligible for the honesty surfaces.** An HAE-profile destination does not
   participate in R-23's freshness escalation, R-24's N, or R-27's external signal, and is
   permanently labelled *"compatibility export — correctness claims do not apply"*. This reuses
   the mechanism §4.3 already invented for MQTT QoS 0. A permanent visible property is the right
   shape for a permanent invisible loss.
2. **Positioned as a migration path**, not a co-equal destination: *point your existing HAE
   receiver at us today, then move to `ohe.wire/1` when you are ready.* The native profile is
   co-enabled by default so the user always holds a convergent copy.
3. **Enumerated as a fourth R-88 explanation class** (A-5). Otherwise a soak run with an HAE
   destination fails the release gate by construction — and that is a gate that gets waived the
   first time it fires, which is the failure A-5 was written to prevent.

**Consequence for RK-1.** PRD RK-1 lists HAE compatibility as an abandonment mitigation, "so
users are not stranded". But a stranded user falling back to HAE falls back into the failure
mode the product exists to fix. The mitigation is weaker than the PRD claims. Restated in A-21.

### F-2 — The outcome taxonomy is wrong in two ways

Both discovered by the reliability engineer, both real.

**`partial` becomes the healthy common case.** In a store-and-forward pipeline, reads and
acknowledgements are decoupled across runs. A wake that reads 500 samples, durably enqueues
them and hands them to a discretionary background transfer has acknowledged *none* of them, so
R-21 forbids reporting `success`. That is correct and honest, and it means most runs are
`partial`. The taxonomy needs a mandatory cause code, and the interface must stop treating
`partial` as bad news.

**There is no member for "the platform refused us the read".** A locked device (C-02) is the
single most common condition this app will ever encounter. Forcing it into `failed` makes the
UI say "failed" for the least alarming thing that happens, which actively damages the honesty
story the taxonomy exists to serve.

**Resolution:** both accepted as PRD amendments (A-1, A-2). A third member is added for Local
Network denial (A-20) — the real TA-01, which v0.1 misidentified.

*A-1 has a prerequisite v0.1 missed:* `blocked_device_locked` cannot be journalled at all unless
the journal is Class C. See §4.3 and SR-F-05. My own headline amendment was self-defeating as
written.

### F-3 — D-05's iOS 18.0 floor costs more than the PRD priced

`BGContinuedProcessingTask` is iOS 26+. The PRD anticipated version-specific cost in D-05's
reversibility note, but two designers independently quantified it:

- The architect: a **second full-history execution path**, ~1.5 EW inside M4.
- The reliability engineer: **on iOS 18–25 an unattended full backfill does not exist.** It
  requires foreground time or a long accumulation of opportunistic wakes. R-11's "without
  babysitting" and R-75's ≤30 min are achievable unattended only on iOS 26+.

**Resolution:** restate R-11 and R-75 per OS tier and say so plainly in the App Store
description (A-4). Do not raise the floor — RK-8 (market too small) is the worse risk, and both
incumbents ship iOS 17.0.

**The unpaid cost, added in v0.2.** PRD §7 specifies *every* NFR on two devices at iOS 26, with
REF-B (iPhone 11) described as "the oldest device iOS 26 supports" — correct, since iOS 26
requires A13. But D-05's iOS 18.0 floor admits the **A12 iPhone XR, XS and XS Max** and the A10
7th-generation iPad, and **not one NFR covers them.**

It compounds with F-3 rather than being independent of it: F-3 gives iOS 18–25 a *separate
foreground-driven backfill path*, so the newest execution path runs on the slowest supported
hardware with zero performance coverage. R-91 says NFRs without a mapped test are rejected at
Stage 2 review. The only iOS 18 coverage is a nightly Simulator matrix, which cannot measure
launch latency, memory under thermal pressure or battery — and which the QA lead's own
confidence note says cannot be populated with HealthKit data at all.

**REF-C** (an A12 iPhone on iOS 18) is added to PRD §7 by A-22, with R-73, R-74, R-76 and
R-75's foreground form restated for it. Per O-11 the owner believes he already owns a suitable
device. Keeping D-05's reach while specifying every threshold on hardware D-05's target cannot
run was not a defensible option.

---

## 4. Conflicts resolved

### 4.1 The QA lead's findings — v0.1's §4.1 was wrong and is withdrawn

**v0.1 claimed TA-01 was a stale "the security design does not exist" blocker, downgraded it to
Minor, and named QA-38 as the sole residue. Every element of that was wrong.** The adversarial
reviewer checked it and I have re-verified each point against `07-test-architecture.md`:

| v0.1 claimed | Actually | Evidence |
|---|---|---|
| TA-01 is "the security design does not exist" | TA-01 is **Local Network permission denial has no enumerated outcome and no distinct copy** | `07`:155 |
| Filed as Blocker, downgraded to Minor | Filed as **Major**, and still live | `07`:155 |
| The PM verified the security design's arrival | The QA lead had already **withdrawn** that pre-emptive blocker himself | `07`:119, `07`:141 |
| Three pre-emptive blockers withdrawn | **Four** | `07`:18, `07`:141 |
| QA-38 is "genuinely unaddressed" residue | `07`'s own audit lists QA-38 as **owned by the security design** | `07`:110 |

What misled me is real but does not excuse the error: `07`:1343 contains a stale sentence
("`04-security-*.md` was absent, which is finding TA-01") contradicted by §2.1, §2.2 and §2.3 of
the same document. I claimed first-hand verification of a finding I had not read in its filed
form. *(Action: ask the QA lead to correct 1343, because it will mislead the next reader too.)*

**The real TA-01 is accepted** and becomes A-20: Local Network denial gets its own member of
R-21's enumerated outcome set, distinct copy, and a row in the error-class registry. Denial is
*positively detectable* here, unlike HealthKit read denial, so there is no excuse for the
ambiguity. R-21's set is PRD text, so this needs ratification.

**The four QA findings v0.1 dropped entirely**, now dispositioned:

| # | Finding | Disposition |
|---|---|---|
| **TA-03** | *His sharpest finding.* R-89's assertion is insufficient in every design that touches it: asserting `state_class` is *present* does not catch the failure R-89 exists to prevent — silently absent long-term statistics. The only sufficient assertion is that a `recorder/statistics_during_period` row exists after a statistics cycle | **Accept.** ~12-minute nightly job by his own estimate. The PRD's own note on R-89: "A silent failure in the primary persona's primary destination, in the product built to eliminate silent failure, is the most embarrassing bug available to us" |
| **TA-04** | Generate the R-89 suite from `MetricCatalog` rather than hand-maintaining it | **Accept.** Cheap, and it closes the drift path |
| **TA-07** | The R-26 bundle window must be the greater of 30 runs or 24 hours | **Accept**, folded into A-12. See §4.4 for why this interacts with F-2 |
| **TA-09** | Split P12 into P12a/P12b | **Accept.** Residual from the R-51 manifest-driven redaction he otherwise praised |

### 4.2 Persistence — I overrode the architect, then verified and withdrew it

**Recorded in full because the reasoning is instructive, not to be self-flagellating.**

The architect chose a **first-party SQLite wrapper** over GRDB on two grounds: R-80 makes Linux
a required check, and the dependency budget was already spent on MQTT. He flagged it as the
decision he was least certain of, naming the reason: it "puts a permanent maintenance
obligation on the correctness critical path in a project whose top risk is abandonment."

Separately, the **security engineer recommended a first-party publish-only MQTT client** rather
than a third-party library, for supply-chain reasons. Reading the two together, I concluded the
budget was misallocated and proposed spending it on GRDB instead — on the grounds that
reinventing crash-safe persistence is worse than reinventing a narrow protocol client.

**I then checked GRDB's actual Linux posture, and the argument collapses.** From its README:

> "Linux support is provided by contributors. It is not automatically tested, and not
> officially maintained. If you notice a build or runtime failure on Linux, please open a pull
> request with the necessary fix, thank you!"
>
> — <https://github.com/groue/GRDB.swift>

GRDB is otherwise in excellent health — MIT (AGPL-compatible), 8,630 stars, v7.11.1, last
pushed August 2026, 15 open issues. But R-80 makes the Linux build a **required check from the
first commit**, and it is the constraint the entire test strategy rests on. Hanging it on a
dependency's explicitly untested and unmaintained code path means every GRDB bump can block CI
for a reason nobody upstream is obliged to fix.

I also mischaracterised what the architect proposed. He did not propose writing a database. He
proposed a thin typed layer over prepared statements and transactions against the **system
SQLite** — crash safety comes from SQLite's WAL and transaction semantics, not from the
wrapper. That is ~1,200 reviewable lines worth ~1–1.5 EW of ~87, not "twenty months writing a
database", which was a strawman.

**Resolution: the architect's design stands.** First-party thin wrapper over system SQLite,
behind the `StateStore` port, with his stated reversal trigger intact.

**A coupling neither of us saw, found by the reviewer.** `01`§7.3 records that the wrapper makes
the Data Protection class *directly settable at open*, whereas GRDB mediates it through
configuration hooks. Per §4.3 that flag is exactly the one that must change to fix a Blocker. The
override would have made the fix indirect. SR-F-05 and SR-F-06 were coupled and neither the
architect nor I noticed.

The MQTT half is decided separately as O-2 — see §4.3 and SR-F-12. v0.1's "a few hundred lines"
was **my** phrase, not the security engineer's; it appears in none of the nine documents and I
retract it.

**Process note:** this was caught by my own verification while the adversarial review was
running, not by the review. Two independent paths reached the same conclusion, which is mild
evidence it is right. It is also exactly the class of error the review exists to catch — a
synthesis that sounds better than its evidence — and that a five-minute check on the README
defeated it is a fair criticism of v0.1.

### 4.3 Everything else

Rows added in v0.2 are marked **[v0.2]**.

| Question | Source | Resolution |
|---|---|---|
| **Can a receiptless webhook ever report `success`?** | **03 vs 08** | **[v0.2] Adopt `08`; override `03`.** See below — this is SR-F-04 and v0.1 got it wrong |
| **Journal Data Protection class** | **05 vs ADR-0005** | **[v0.2] Class C for state + journal, Class B for payload blobs.** See below — SR-F-05 |
| **R-23's escalation threshold** | **05 vs 06 vs 08** | **[v0.2] One function, two regimes, one definition site, owner = the observability engineer.** See below — SR-F-11 |
| **Deletion-dating index horizon** | **02** | **[v0.2] Accept ~60 days at REF-DELTA** (not ~400), **plus a scheduled automatic reconcile** and a targeted per-type sweep driven by `deletion_undatable`. O-9 |
| Neutral, brand-free identifiers under open D-06 | 01 | **Yes.** One file contains the brand; a `rename-drill` CI job substitutes a nonsense brand and asserts a clean build |
| Aggregation canonicality for multi-source cumulative metrics | 01, 02 | **HealthKit's de-duplicated statistic is canonical.** One number. It is what the Health app shows, and the Health app is what users compare against. **[v0.2] This requires A-9's R-80 exception list** — the consequence v0.1 dropped |
| Queue-full ordering | 01, 08 | **Stall-then-evict**, as designed |
| Designated exporter (iPad + iPhone both exporting) | 01 | **Ship it** (~1 EW, M4). Upsert-by-UUID makes raw overlap harmless but aggregate mode is unprotected |
| Bucket keys exclude `computationID` | 02 | **Confirmed.** A catalogue semantics fix rewrites history in place, which is right for an archive |
| `exporterId` excluded from `bucketKey` | 03 | **Confirmed**, consistent with the designated-exporter decision |
| Medications (iOS 26, per-object auth) | 02 | **Defer to v1.1** |
| ECG voltages, workout routes, heartbeat and quantity series | 02 | **Advanced options, default off, with a size estimate shown.** R-70 prices them at M7 |
| `unitProfile` for the HAE profile | 03 | **Allow, with `canonical` as default** |
| MQTT retained state messages | 03 | **Off by default.** Leaving a user's latest health values on a broker indefinitely is not a default we can defend |
| `device_class: energy` for active/basal energy | 03 | **`null`.** Correct classification makes calorie sensors selectable in HA's Energy dashboard, which is actively confusing |
| Characteristic records in v1 | 03 | **Ship, off by default, flagged as re-identifying** |
| Mac companion distribution | 04, 09 | **Developer ID, notarised, outside the Mac App Store.** **[v0.2]** This also determines that Guideline 5.1.3(ii) does **not** bind the companion contractually — see O-10 |
| Queue TTL for undeliverable payloads | 04 | **7 days, then delete-and-alert.** With revocation undetectable, the TTL *is* the exposure bound for R-44 |
| `partial` with a mandatory cause code | 05, 08 | **Yes.** `partial(deferred_discretionary)` presents as "Queued, awaiting delivery" |
| MQTT QoS | 08 | **QoS 1 default; QoS 0 opt-in.** QoS 0 deliveries are terminally `sent_unconfirmed` with a separate "last unconfirmed send" clock rather than contributing to R-23 and R-27 |
| Backfill defaults to aggregates beyond 90 days | 08 | **Confirmed**, with raw-everything available explicitly |
| Eviction fires an unconditional notification | 08 | **Yes**, not separately suppressible from R-40's |
| R-83 seam count | 07, 08 | **Six locations stands**, with an orthogonal injection vocabulary. **[v0.2]** A-11 ratifies the naming change, which alters PRD text |
| Health app "Export All Health Data" as the R-88 oracle | 07 | **Yes**, with a mandatory handling rule in `CONTRIBUTING.md` |
| Public container-registry mirror for HA/Mosquitto | 07 | **Yes.** It is what makes R-89 and R-90 fork-safe without a secret |
| Second repository for the HA integration | 09 | **Yes.** HACS's model is structurally incompatible with the monorepo |
| HA supported-version window | 07 | **Current stable back to −11 releases**, with a monthly bump issue. Needs a named owner (O-6) |
| Determinism property P8 | 07 | The architect defeated it correctly — Darwin and swift-corelibs Foundation ship different tzdata. **Restated as per-platform determinism plus a declared tz-database version.** **[v0.2]** Ratified as A-8, since it changes R-84's stated criterion |

#### The webhook acknowledgement contradiction (SR-F-04)

Two documents said opposite things and v0.1 did not notice a conflict existed:

- `03`:1275 — where a receipt is absent the outcome "is `unknownAck`, **never** `success`."
- `08`:106 — Home Assistant preset: "Ongoing runs report **`success` on 2xx**."

`03`:1384 asked me directly to confirm `unknownAck` as the normal case for webhooks. I confirmed
it without tracing the consequence through `05`, where **only `success` or `success_nothing_due`
re-arms the pre-scheduled watchdog**. So as v0.1 synthesised it, a correctly configured, healthy
Home Assistant webhook — the primary persona's default destination — would produce `unknownAck`
on every run, never advance the freshness clock, and escalate permanently after two runs.

*The product built to eliminate silent failure would have shipped a permanent false alarm on its
most common configuration.* The mechanism to prevent it already existed: §4.3 invented the
separate-clock treatment for QoS 0 and did not apply it here.

**Resolution: grade the evidence rather than flatten it.** The two documents were answering
different questions with one word — `03` means "no receipt enumerating accepted records", `08`
means "a response in the declared success range".

| Condition | Outcome | Journal |
|---|---|---|
| 2xx, no receipt | **`success`** | `ack_evidence = status_only` |
| 2xx, receipt present, counts match | `success` | `ack_evidence = receipt_full` |
| Receipt present, short count | `partial(receipt_short)` | named cause |
| Body sent, response never read | `unknown_ack` | (unchanged — `08`'s original reservation) |

The receipt stays a SHOULD that *upgrades* fidelity where present. The failure `03` rightly
worried about — "succeeded but nothing arrived" — is the statistics-materialisation failure, and
both `08` and TA-03 are right that its mitigation is R-25's configuration-time read-back gate
plus TA-03's statistics-row assertion, not a permanent downgrade of every run outcome.

This is strictly more honest than either original position: the journal now records the
*strength* of the evidence for every acknowledgement.

#### The Data Protection class (SR-F-05)

`05` raised this as one of three items it "raised for the PM rather than papered over". v0.1
dropped it. It is settleable today from Apple's published documentation, and the answer
contradicts ADR-0005.

Class B (`NSFileProtectionCompleteUnlessOpen`) wipes the per-file key on close and re-creates the
shared secret from the class private key on reopen — and that key is protected by the passcode
and device UID. Apple's developer-facing statement is unambiguous: **"A closed file is
inaccessible when the device is locked."** Class B permits *creating and writing new* files while
locked, and *continuing* with an already-open file. It does not permit opening an existing closed
one.

Per C-02, HealthKit access is relinquished ten minutes after lock, so the majority of background
wakes occur while locked. Under ADR-0005 the app **cannot open its own journal** during them:

- **R-20** ("a durable journal records *every* run") is unsatisfiable for the most common wake.
- **R-22**'s scheduling-versus-execution attribution collapses in the direction `05` already
  identified as a bias: an unrecordable wake is indistinguishable from one that never happened.
- **A-1 is self-defeating.** You cannot write a row saying "we could not read because the device
  was locked" into a database you cannot open because the device is locked.

**Resolution:** adopt ADR-OBS-03's split (§2.3). The downgrade is argued once in an ADR on
grounds `05` already supplies — the journal holds metric names and counts, not sample values, and
`01`:760 already commits to no SQLCipher and no encrypted database. The one-hour device test
still runs, as confirmation rather than as the decision procedure. R-83's `StoreLocked` injector
gains an assertion that a locked-device wake produces a journal row. This also resolves the
ADR-0005 / ADR-OBS-03 contradiction that `05` flagged and v0.1 did not carry.

#### R-23's escalation threshold (SR-F-11)

`05`§Q11 asked me to assign an owner in synthesis and v0.1 did not. Three documents hold three
definitions of the single constant that determines when the product makes its central claim: UX
derives it from a user-chosen cadence, `08` from `clamp(2 · N_p95(class), 6 h, 48 h)`, `01` from
`lastSuccess + N`. These are not refinements of each other.

**Resolution:** adopt `05`'s proposal. One threshold function with two regimes — a shipped
default before N exists, the measured form after — with **one definition site** and the
observability engineer as owner. A cross-document assertion is added to the test architecture:
the UI, the notification scheduler and the widget timeline must all read it from that site. The
design already has this pattern (`CoreTemporal` is "the *only* place `Calendar`, `TimeZone` and
`Locale` are constructed"); it is applied to the threshold.

### 4.4 Cross-document contact table *(new in v0.2)*

Every interface where two or more specialists designed from different sides. This table exists
because v0.1 had no equivalent, and four of its five Blockers were collisions it would have
caught.

| Interface | Designers | Status |
|---|---|---|
| Journal schema ↔ persistence schema | 05, 01 | **Resolved** — Class C/B split, §4.3 |
| Outcome taxonomy ↔ delivery semantics ↔ status copy | 05, 08, 06 | **Resolved** — graded `ack_evidence`, §4.3 |
| Sink contract ↔ receipt semantics ↔ retry model | 01, 03, 08 | **Resolved** — same row |
| Seam ↔ fixture-backed fake ↔ corpus | 02, 07 | **Resolved, and independently verified** — the fake reads the same NDJSON encoding the real adapter emits, so drift breaks both |
| Escalation threshold | 05, 06, 08 | **Resolved** — one function, one site, one owner, §4.3 |
| Canonical aggregation ↔ R-80 Linux constraint | 01, 02, 07 | **Resolved with a qualification** — A-9's committed exception list |
| Anti-coercion chain ↔ OS concealment | 04, 06 | **Resolved enough to close.** Widget survived hide; notification still delivered (`spikes/SPIKE-COERCE-results.md`). R-40 must not rely on preview content. Notifications-denied repeat deferred to M0 |
| R-26 bundle window ↔ F-2's run frequency | 01, 07 | **Resolved** — A-12 folds in TA-07's condition. *Two accepted findings interacted to break a third requirement:* F-2 makes `partial` the common case, so runs are frequent; above 30 runs/day a once-daily bundle stops covering 24 hours, silently breaking R-88's day-level bisection |
| MQTT quarantine ↔ R-80 | 01, 07, 09 | **Resolved** — `SinkMQTTPackage` never enters `ExportCore`'s resolution graph. Verified by the reviewer as a real mechanism, not a diagram |
| `CompanionWire` codec ↔ R-80 | 01, 07 | **Resolved** — pure value-typed frame codec at L2, Linux-buildable and fuzzable |

### 4.5 Anti-coercion — the one unresolved conflict (SR-F-01)

This is the most serious finding in the review and v0.1 was silent on it: **`R-41` appears zero
times in v0.1.** The security engineer flagged it, `06` wrote an invariant the OS falsifies, and
the document whose job was to reconcile them said nothing.

The abuse case (RK-11, T-24) is the one risk in this project with an irreversible human cost.

**Settled by Apple's primary source, actionable now.** Apple's Personal Safety User Guide
confirms a user-installed app can be hidden; that it leaves the Home Screen for an
authentication-gated Hidden folder; and that locking strips app information from notification
previews, search, Siri suggestions and call history. A coercer with physical access and the
passcode — exactly our threat actor — does this in four taps, with no in-app control involved.

Therefore:

- **R-40 is already broken as designed.** `06` says the destination-change notification "carries
  the hostname, **because the hostname is the entire point**". A stripped preview delivers
  precisely nothing of value. → A-16.
- **R-41's invariant 4 is false as written** — "the app looks like itself on the Home Screen
  forever". → A-15.

**Settled 2026-09-03 by owner observation** (`spikes/SPIKE-COERCE-results.md`). After hide,
the **widget survived** and a **notification still popped up**. Secondary reports that hiding
removes widgets and suppresses notifications entirely are false for that device. R-23 therefore
has **at least one Home-adjacent rung against a coercer** — the widget, which is why it is a
Must — plus notification *delivery*. Apple's stripping of **previews** still stands, so R-40
must not treat hostname-in-the-banner as the only carrier.

The notifications-denied repeat and the exact notification body were not logged. With the
widget surviving, those no longer decide one-rung-versus-zero. Confirm at M0 on a
developer-signed build of *this* app.

A fifth surface concealment does not reach remains worth shipping, as defence in depth, not as
the only remaining rung: **R-27's external monitoring signal**, plus the R-30 ledger in
Files/Shortcuts.

> **SPIKE-COERCE** — owner, 2026-09-03: widget survived; notification delivered. No longer
> blocks Stage 2 close.

**The conceptual error underneath.** `06`'s governing principle — "every rung must be correct
without the app ever running again" — was designed against app *death*. The coercion threat model
is app *concealment*. Those are different adversaries, and a chain hardened against the first is
not thereby hardened against the second.

R-41 is restated per the security engineer: a claim about *our binary* — no in-app concealment
affordance, no `CFBundleAlternateIcons`, no configurable name, no subtree authentication — plus an
explicit statement that the OS provides concealment we cannot prevent, plus a **documented
recovery path**. Apple's own page names the residual surfaces: Settings > Apps > Hidden Apps,
Screen Time, Battery, and App Store purchase history. That path ships in the README and in
`Where your data goes`, linking Apple's guide.

A fifth surface concealment does not reach is needed. The strongest candidate is one the design
already has and has not used this way: **R-27's external monitoring signal**, plus the R-30
ledger's presence in the Files/Shortcuts surface.

---

## 5. PRD amendments required

v0.1 said "six places". The correct number was nineteen, and v0.2 adds four more, for **twenty-
three**. Every specialist item marked "cannot design as written" or "cannot secure as written"
now has an explicit disposition. This answers the security engineer's open question 6, which
asked me directly and which v0.1 did not answer.

**Ratification state, stated precisely** — O-12 asked the owner about the thirteen *dropped*
amendments and no others, so that is what it ratified:

| Set | Status |
|---|---|
| **A-7 … A-19** (the thirteen dropped specialist amendments) | **Ratified by O-12.** This is what unblocks M6 |
| **A-1 … A-6** (proposed in v0.1 as O-3) | **Ratified 2026-09-03.** Unchanged from v0.1 except A-5's fourth explanation class |
| **A-20 … A-23** (new in v0.2) | **Ratified 2026-09-03** |

**All twenty-three are ratified.** A-23 in particular is an explicit owner acknowledgement that
Stage 2 closes against two unmet Musts whose stated deadline was Stage 2 close, with the four
dependent NFR thresholds carried as provisional until M0. That is the honest framing and it is
now on the record rather than implied.

### Carried from v0.1

| # | Req | Amendment | Why |
|---|---|---|---|
| A-1 | **R-21** | Add `blocked_device_locked` | The most common condition the app will meet; calling it `failed` damages the honesty the taxonomy serves. *Depends on the Class C fix* |
| A-2 | **R-21** | `partial` carries a mandatory cause code | Store-and-forward makes `partial` the healthy common case (F-2) |
| A-3 | **R-24** | N is **per freshness class A–D**, the user's own device's measured p95 once ≥14 days and ≥100 samples exist | A published constant would be a worse claim than a measured one |
| A-4 | **R-11, R-75** | Restate per OS tier | F-3. Must also appear in the App Store description |
| A-5 | **R-88** | Gate on ***unexplained*** discrepancy, **now with four** explanation classes | The fourth is F-1's HAE profile — without it, a soak with an HAE destination fails by construction |
| A-6 | **R-91** | *Mapped, pending measurement* until R-71 completes | Five calendar weeks of soak. No earlier close can honestly report R-91 as met |

### From `01-system-architecture.md` §11 — the architect's seven

| # | Req | Amendment | Disposition |
|---|---|---|---|
| A-7 | **R-44** | 60-second purge deadline restated as bounded best-effort with a stated ceiling | **Accept.** *His highest severity*, and filed independently by the security engineer. **M6's exit criteria cite this as amended** |
| A-8 | **R-84** | Per-platform determinism + declared tz version; cross-platform equality only over UTC/fixed-offset fixtures | **Accept.** Darwin and swift-corelibs ship different tzdata; the criterion is false without any bug. Reviewer independently confirmed |
| A-9 | **R-80 vs R-07** | Linux coverage extends to the whole pipeline **with a committed exception list**: metrics whose canonical aggregation provider is `hkStatistics` run on Linux against recorded reference vectors, gated by R-87's device pass | **Accept, verbatim.** Required by §4.3's canonicality ruling. List generated from `MetricCatalog`, asserted non-growing without an ADR |
| A-10 | **R-91 vs R-77/R-79** | Allow a named, scripted, recorded device protocol per the R-87 pattern | **Accept.** MetricKit gives daily aggregates with no percentile control. Without this, R-91 rejects two of its own NFRs at this review |
| A-11 | **R-83** | Rename two of the six seam names that presuppose an inverted ordering | **Accept.** Was a §4.3 resolution in v0.1; promoted because it changes PRD text |
| A-12 | **R-26** | Bundle bounded by **the greater of 30 runs or 24 hours**, user-adjustable; preview and no-share-without-preview assertions unchanged | **Accept**, with TA-07's condition folded in. See §4.4 for the F-2 interaction |
| A-13 | **SEC-04** | Verification criterion restated | **Accept.** Design-input rather than PRD text, so no owner ratification needed; recorded for completeness |

### From `04-security-design.md` — the security engineer's six

| # | Req | Amendment | Disposition |
|---|---|---|---|
| A-14 | **R-44** | *(merged with A-7)* | **Accept** |
| A-15 | **R-41** | Restate as a claim about our binary + an explicit statement that the OS provides concealment we cannot prevent + a documented recovery path | **Accept.** SR-F-01, the most serious finding in the review |
| A-16 | **R-40** | Acknowledge that notification content is stripped when the app is hidden; the mechanism cannot rely on preview content | **Accept.** R-40's entire value was its content |
| A-17 | **R-32** | Restatement carried | **Accept** |
| A-18 | **R-30** | The property is **tamper-evidence, not immutability** — delete-all writes a genesis marker recording how many entries were destroyed and when | **Accept.** Better than the PRD's own wording: a coercer can wipe it but cannot make the wipe invisible. **M6's exit criteria currently assert "immutable"** and are re-derived |
| A-19 | **R-50** | Restatement carried | **Accept** |

### From the QA lead, and new in v0.2

| # | Req | Amendment | Disposition |
|---|---|---|---|
| A-20 | **R-21** | Local Network denial gets its own enumerated outcome, distinct copy, and an error-class registry row | **Accept.** The real TA-01. Sibling to A-1 |
| A-21 | **RK-1** | Restate: HAE compatibility is a *weak* abandonment mitigation, because a stranded user falls back into the failure mode the product exists to fix | **Accept.** F-1 |
| A-22 | **PRD §7** | Add **REF-C** (A12 iPhone on iOS 18); restate R-73, R-74, R-76 and R-75's foreground form for it | **Accept.** F-3 / SR-F-08. O-11 |
| A-23 | **R-70, R-71** | Strike "before Stage 2 closes"; name **M0** as the deadline, with the four dependent NFRs explicitly marked provisional. **Add R-73 to the M0 spike set** | **Accept.** Both are PRD Musts whose stated deadline is Stage 2 close and neither has run; A-6 amended the requirement that *consumes* the measurement while leaving unamended the two that *mandate its timing*. The spikes genuinely cannot compress, so this is the honest version of what is happening — but the amendment must name the requirements it actually changes |

### Two NFRs that need naming before M0, not during it

Neither is an amendment. Both appear nowhere in v0.1, and between them they are the likeliest
source of a nasty surprise.

**R-72 has zero headroom.** `08` budgets read 6.3 s + transform/encode 1.2 s + compress 0.3 s +
commit 0.2 s = **8.0 s against an 8.0 s budget** — at the assumed 1,600 samples/s that RK-2 says
is unvalidated. `08`'s own note: "At 800 samples/s the read phase alone is 12.5 s and REF-A
fails." An NFR with zero headroom on an unmeasured assumption is a coin flip.

**R-73's "185 ms of margin" is a hypothesis, not a measurement.** `08` presents the 400 ms budget
as comfortably met — process launch + dyld ~120 ms, `HKHealthStore` init ~30, SQLite open + WAL
recovery ~40, anchor row read ~5, query construction + dispatch ~20, total ~215. All five are
unsourced point estimates with no variance stated, on an NFR specified at **p90** under "cold,
thermally unfavourable" conditions on a six-year-old device — which is precisely the quantity
that misbehaves. The *method* is right: treating the background launch path as a closed list of
permitted operations, with a debug trap on violations, is the correct design response. What is
wrong is presenting the result as settled margin. RK-2 already committed this project to
measuring rather than asserting performance assumptions, and R-70/R-71 got spikes while R-73 did
not. A-23 adds it: ≥100 cold background launches on REF-B, p90 reported.

One related claim is now moot. `08` conditioned the ~120 ms dyld figure on "zero third-party
dynamic frameworks on this path", and v0.1's GRDB override put a dependency squarely on it
without re-deriving the budget. The §4.2 withdrawal restores the precondition, so this limb is
discharged — but it was discharged by luck rather than by anyone noticing.

---

## 6. Milestones and schedule

The architect honoured §7.1's sequencing literally. M0 is the R-70/R-71 spikes and nothing else
that matters. The wedge — engine, journal, watchdog, local-file destination — completes at **M6**,
before MQTT, the companion or HACS begin. That ordering front-loads everything that cannot be
retrofitted and leaves the discretionary scope where it can be cut.

### 6.1 M6 is now signable

v0.1 presented M6 as "the single most important property of the plan" while its exit criteria
cited **"R-44 (as amended, §11)"** — an amendment v0.1 never ratified — and **"R-30 … immutable"** —
a property the owning specialist explicitly refuses to let the project claim. As the PRD stood,
M6 could not be signed off.

With **A-7 and A-18 ratified (O-12)**, it can. M6's exit criteria are re-derived against the
ratified set: R-44 reads as bounded best-effort with a stated ceiling, and R-30 reads as
tamper-evident with a genesis marker rather than immutable.

### 6.2 The estimate, stated honestly

v0.1 restated **~87 EW** unchanged while accepting new scope in the same document. Corrected:

| Item | EW |
|---|---|
| Architect's baseline | ~87 |
| F-3's second full-history execution path | +1.5 |
| Designated exporter (§4.3) | +1 |
| O-2's MQTT delta | **unpriced** — the security engineer owns the estimate |
| A-22's REF-C restatement, and the reworked amendments | small, unpriced |
| **Total** | **~90 and rising, with no contingency** |

PRD §7.1 mandated a re-baseline **after** the R-70/R-71 spikes. They have not run, so the
mandated re-baseline cannot have happened, and v0.1 reported the un-re-baselined total without
saying so. The re-baseline is deferred to M0 and now has an exit-criteria row (§8).

**On the designated giver.** v0.1 nominated the Mac companion (M9, 5 EW) as the natural scope
reduction if anything slips. But the companion was restored to scope by owner decision **D-14**
and is a Must in PRD §5.1. Naming it as the giver re-proposes a cut the owner has already
refused once. It goes back to the owner as a question, not into the plan as an assumption.

---

## 7. Owner decisions

O-1 and O-2 are rewritten; O-9 through O-12 are new. Decisions taken on 2026-09-03 are marked.

| ID | Decision | Status |
|---|---|---|
| **O-1** | HAE compatibility profile | **DECIDED 2026-09-03.** Migration path, structurally ineligible for R-23/R-24/R-27, permanently labelled, native profile co-enabled. Landed in PRD v1.1 (R-12, A-21) |
| **O-2** | MQTT: first-party publish-only client vs library | **DECIDED 2026-09-03 — first-party.** MQTT 3.1.1, CleanSession=1, QoS 1, no MQTT-level session state; republish from the app's own durable queue. Still needs an EW price from the security engineer so §6.2 can close the delta; the *choice* is not blocked on the number |
| **O-3** | Ratify the amendments | **SUPERSEDED by O-12** |
| **O-4** | Resource R-71 | **DECIDED 2026-09-03.** Owner runs it, starting this week, two devices if available. Clock starts now, not after Stage 3 harness work — a diary on paper plus timestamps is enough for week 1; the M0 harness ingests it |
| **O-5** | Record the backfill preference *before* R-70 measures | **DECIDED 2026-09-03, pre-measurement** — first-run backfill is **aggregate-only**; raw backfill is an explicit user action. Recorded before R-70 runs, so the measurement cannot become a negotiation. If R-70 returns 400–1,600 samples/s, R-75's target holds under this default rather than being renegotiated against it |
| **O-6** | Named owners | **DECIDED 2026-09-03 — solo and honest.** Owner is the security maintainer. No deputy until D-10 lands. `SECURITY.md` states the bus factor of one and does **not** invent an acknowledgement SLA. HA version-window bumps, advisory-key rotation and CoC enforcement are the same person, recorded as such |
| **O-7** | Hardware budget | **OPEN**, and see O-11 |
| **O-8** | Scope HAE compatibility fixtures out of CC0, pending R-112 | **DECIDED 2026-09-03 — scope out.** Fixtures stay in-repo; they are not dedicated to the public domain until the legal opinion |
| **O-9** | Deletion-dating horizon | **DECIDED** — accept ~60 days at REF-DELTA, **and close the manual gap**: a scheduled low-priority full reconcile subordinated to live delivery via I6, plus a targeted per-type sweep driven by `deletion_undatable`'s `{type, uuid}` |
| **O-10** | Companion writing a decrypted archive to an iCloud-synced folder | **DECIDED** — warn, do not refuse. See below |
| **O-11** | REF-C reference device | **DECIDED 2026-09-03 — iPhone XR.** Qualifies: A12, max iOS 18, permanently on the D-05 floor. Thresholds for R-73/R-74/R-76 and R-75's foreground form are measured on this device at M0, not asserted |
| **O-12** | Ratify the amendments | **DECIDED — all twenty-three ratified (A-1…A-23). M6 is signable.** The thirteen dropped specialist amendments were signed first; A-1…A-6 and A-20…A-23 followed in the same session (§5) |

### O-11 — the X / XR distinction is disqualifying

The owner has "either an X or an XR". These are one year apart and only one of them can serve as
REF-C:

| Device | SoC | Max iOS | Verdict |
|---|---|---|---|
| **iPhone XR** | A12 Bionic | **iOS 18** | **Exactly REF-C.** A12 was dropped by iOS 26, so an XR is permanently on the iOS 18 tier — it cannot drift off the tier it is meant to characterise |
| **iPhone X** | A11 Bionic | **iOS 16.7.16** | **Disqualified.** iOS 17 dropped the iPhone X; it cannot reach iOS 18 at all, so it cannot install the app under D-05's iOS 18.0 floor, let alone measure it |

Sources: Apple's iOS 17 requirements are "iPhone XS and newer" plus the XR
(<https://arstechnica.com/gadgets/2023/06/ios-and-ipados-17-drop-support-for-iphone-x-first-ipad-pros-and-other-old-devices/>);
iPhone X's current OS is iOS 16.7.16 (<https://en.wikipedia.org/wiki/IPhone_X>).

**Identification** — the XR has a *single* rear camera and an aluminium frame in colours (blue,
coral, yellow, red, white, black); the X has *dual vertical* rear cameras and a stainless steel
frame in silver or space grey only. Or: Settings > General > About > Model Name.

If it is an X, A-22 needs a funded REF-C (a used XR is the cheapest qualifying device) or the
fallback stated in §3's F-3 applies: characterise performance on iOS 26 hardware only and reduce
the iOS 18–25 tier's App Store claims to match.

*Note the pleasing coincidence that A12 is the boundary in both directions — iOS 17 dropped
everything below it, and iOS 26 dropped A12 itself. That is exactly why an A12 device is the
right REF-C: it is the only silicon generation that is permanently pinned to the iOS 18 tier.*

### O-10 in detail

The security engineer's document contains the line *"one thing I will not sign off on"* — the Mac
companion writing a decrypted health archive into an iCloud-synced folder, unattended and
repeatedly. v0.1 dropped it entirely, which is the single worst omission in the document: a
specialist's explicit refusal is the highest-priority line he can write.

**The App Review limb dissolves on a decision already taken.** His own open question 1 states
that the distribution choice determines "whether Guideline 5.1.3(ii) binds the companion
**contractually**" — and §4.3 settled it as Developer ID, notarised, **outside** the Mac App
Store. A notarised direct download is not reviewed. The iOS app, which *is* reviewed, still
writes nothing to iCloud, so PRD §3's boundary ("we ship no iCloud code") holds unchanged on the
reviewed product.

The pre-submission enquiry he requested twice is therefore **withdrawn as moot** rather than
deferred a third time. That is a disposition, which is what he was owed.

**What survives is the substantive privacy concern**, independent of Apple policy: our software
may write a decrypted health archive into a synced folder, unattended and repeatedly. Three
implementation notes:

1. **Warning requires the same detection code as refusal** — you cannot warn about an
   iCloud-backed target without detecting one. There is no cost saving in warning, which means
   the decision is purely about user autonomy. That is the right axis for it.
2. The warning is **persistent, not one-time** — the same reasoning that rejected F-1's
   acknowledgement screen. A click at configuration time does not arm a user against a standing
   property.
3. **Reversal trigger:** if the companion is ever proposed for the Mac App Store, 5.1.3(ii)
   binds immediately and this must be revisited before submission. Recorded in the ADR.

---

## 8. Stage 2 exit criteria

Re-checked *after* the work rather than before. v0.1 checked two boxes that were false.

- [x] Nine specialist designs delivered
- [x] Cross-audit performed by the QA lead against §6.6
- [x] Adversarial review completed
- [x] All 18 review findings dispositioned (`reviews/01-disposition.md`) — 18 accepted, 0 rejected
- [x] All twenty-three amendments enumerated with an explicit accept/reject (§5)
- [x] Cross-document contact table complete (§4.4)
- [x] Webhook acknowledgement conflict adjudicated (§4.3)
- [x] Data Protection class settled (§2.3, §4.3)
- [x] Escalation threshold has one definition site and a named owner (§4.3)
- [x] **All twenty-three amendments ratified** (A-1…A-23); **M6 re-derived and signable** (§6.1)
- [x] O-1, O-2, O-4, O-5, O-6, O-8, O-9, O-10, O-12 decided (§7)
- [x] **SPIKE-COERCE** — widget survived hide; notification delivered (§4.5). Preview stripping and notifications-denied repeat are M0 confirmation, not close-blockers
- [x] **O-11 — REF-C is an iPhone XR** (§7)
- [ ] O-7 hardware budget (REF-A / REF-B / always-on receiver host)
- [ ] Security-engineer EW price for O-2 recorded in ADR-0003
- [ ] R-70 and R-71 executed at M0; four provisional NFR thresholds confirmed; **R-73 measured**
- [ ] PRD-mandated re-baseline performed after the M0 spikes (§6.2)
- [x] Design approved — Stage 2 closed 2026-09-03

**Stage 2 closed 2026-09-03.** Carried into Stage 3: M0 is R-70, R-71 (already started) and R-73
on REF-B plus REF-C (XR); the wedge through M6; ADRs 0001–0003; PRD v1.1.

**R-71 is the long pole**: five calendar weeks of soak, already started per O-4. Four NFRs and
R-24's N wait on it. That is M0/Stage 3, not a reason to keep Stage 2 open.

The last Stage 2 owner fact is **XR vs X** (O-11). Everything else on this list is measurement
or a hardware inventory.
