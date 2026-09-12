# Product Requirements Document

**Product:** open-health-exporter (working name — see D-06)
**Stage:** 1 of 4
**Status:** **APPROVED v1.1** — Stage 2 amendments A-1…A-23 ratified 2026-09-03. Stage 1 remains closed; this is a requirements patch, not a re-open.
**Author:** Coordinating PM, synthesising nine specialist contributions
**Date:** 2026-09-03

**Changes in v0.2:** 19 of 20 adversarial review findings accepted, 1 rejected with evidence.
Requirements renumbered. Substantive additions: the correctness engine (aggregation,
reconciliation, upsert-by-UUID, bounded queue), the anti-coercion controls, a security
advisory channel, cost and capacity figures, and an in-app data browser. See
`reviews/01-disposition.md`.

**Changes in v1.0:** Owner decisions D-01…D-14 taken and recorded in §11. Consequential scope
changes: the licence is AGPL-3.0 with a §7 app-store additional permission, Apple enrolment is
organisational, capacity is near-full-time, and both MQTT and the Mac companion return to v1
scope. Cost re-baselined in §7.1.

**Changes in v1.1:** Stage 2 discovered that several Musts were unachievable as written, or
silently incomplete. Twenty-three amendments were ratified against
`docs/02-design/00-system-design.md` v0.2. The largest: R-21 gains `blocked_device_locked`,
`local_network_denied` and a mandatory `partial` cause; R-30 is tamper-evidence not
immutability; R-41 is a claim about *our* binary plus a recovery path, because iOS 18 can hide
the app; R-44's 60-second clock starts at *observation*, not at revocation; R-70/R-71 move to
M0; REF-C (A12 / iOS 18) is added; HAE compatibility is restated as a weak abandonment
mitigation. See §15.

---

## 0. How to read this document

This PRD is a synthesis, not an original work. Nine specialists produced
`docs/01-prd/contributions/` — roughly 7,400 lines and ~300 requirements. My job was to
resolve their conflicts, cut the combined scope to something a very small team could ship, and
be explicit about which findings break the original premise.

Every requirement traces to at least one specialist requirement ID. Where I overrode a
specialist, §12 says so and why. Where the adversarial reviewer overrode *me*, §12 says that
too.

Claims marked **[verified locally]** were checked by me directly, with the method stated.

---

## 1. Executive summary

We set out to build an open-source, Swift-native equivalent of Health Auto Export. Stage 1
research says that specific product should not be built, for two independent reasons.

**The differentiators do not differentiate.** "Genuinely open source" is already occupied —
several OSS Apple Health exporters ship today, including `health-md` (AGPL-3.0, on the App
Store since February 2026) and `health4ai`. "Swift native" is invisible to users. "Reliable"
cannot be ours, because the reliability ceiling is Apple's and we inherit it exactly. Free is
not a wedge against an incumbent whose automation tier costs $5.99/year.

**Three headline capabilities are not deliverable as imagined.** The Mac cannot read HealthKit
at all. Scheduled background export is not something iOS offers. Storing health data in iCloud
is prohibited by App Review.

There is a real product underneath, and the research found it by looking at what users
complain about rather than at the incumbent's feature list. The category's defining failure is
not missing features — it is **silent, undetected failure**: exports stop, or report success
while delivering nothing, and nobody notices for weeks. Compounding it, the incumbent's
incremental sync keys its watermark on HealthKit *write* time, so retroactively-inserted
samples are permanently missed downstream — which means sleep, the metric people most want, is
systematically truncated.

So the product is repositioned:

> **An Apple Health exporter that tells you the truth about what it did.**
> Correct under late-arriving data, honest about every run, and loud when it stops.

Correctness and legibility are the wedge. They are unglamorous, evidenced, and — unlike "open
source" or "native" — they are things the incumbent is measurably bad at. Notably, our nearest
OSS competitor `health-md` charges via StoreKit and collects pseudonymous product events; we
would be the one that does neither.

Two honest downsides, stated once and plainly:

**This is a small market.** The incumbent has **389 US ratings after roughly ten years**. A
realistic ceiling is low thousands of users.

**This is a large build for a small team.** §7.1 costs v1 at roughly 75–85 engineer-weeks
against an assumed 4–8 maintainer-hours per week. That arithmetic does not close, and §7.1
states what we do about it rather than hiding it.

---

## 2. Premise corrections

Findings that change what we are building. Each was raised independently by two or more
specialists, which is why I treat them as settled rather than as opinions.

### PC-1 — The Mac cannot read HealthKit. **[verified locally]**

`HealthKit.framework` is present in the macOS 26.5 SDK and `HKHealthStore` is annotated
`API_AVAILABLE(… macos(13.0))`, so the code *compiles*. It does not *work*. I compiled and ran
a probe on this machine, macOS 26.6:

```
macOS runtime HKHealthStore.isHealthDataAvailable() = false
```

Apple DTS confirmed the same in September 2025 and Apple's documentation states it outright.
Not a gap we can engineer around.

**Consequence:** the iPhone is the only control plane. macOS is not an exporter. Raised by the
HealthKit expert, architect, UX designer and QA lead.

### PC-2 — "Automatic export" cannot mean "on a schedule"

iOS gives a third-party app no scheduling API. `HKObserverQuery` with
`enableBackgroundDelivery` is event-triggered and best-effort; `.immediate` is a ceiling, not a
guarantee, and `stepCount` is capped hourly. `BGTaskScheduler` timing is explicitly not
guaranteed. And the HealthKit store is encrypted while the device is locked (C-02): background
wakes still fire, the reads still fail. Force-quit stops everything until next launch.

**Consequence:** no time-of-day scheduler, because it is a promise the platform will break.
Instead: **freshness targets**, an explicit Shortcuts/App Intents path for users who need
determinism, and a watchdog that makes lateness visible rather than silent. Raised by five of
nine specialists.

### PC-3 — The app may not store health data in iCloud

App Review Guideline 5.1.3(ii): apps "may not store personal health information in iCloud."
This rules out a bespoke iCloud Drive destination, CloudKit sync of health data, and CloudKit
sync of any journal containing sample values.

It does **not** rule out the user pointing our local-file destination at an iCloud-backed
folder through the system document picker. Both specialists who examined this called the
distinction genuinely ambiguous rather than settled; our position is that we ship no iCloud
code and the user's choice in Apple's own UI is the user's. See the non-goals table for the
precise wording, which matters because a Stage 2 engineer reading it loosely would add a
folder filter nobody asked for.

### PC-4 — No listening server on iOS

The reference product ships a TCP server. The security engineer's disqualifying argument is
not the usual LAN-exposure one: **on iOS, network access is not permission-gated, but
HealthKit is.** A localhost listener hands every other app on the device an unprompted read of
the entire health record, bypassing the consent gate Apple built. It plausibly breaches
Guideline 5.1.3(i) as well.

**Consequence:** out of scope permanently, not just for v1.

### PC-5 — The open-source differentiator is already taken

`health-md` (AGPL-3.0, App Store, February 2026) already does iPhone→Mac transfer over
Multipeer Connectivity and lists iCloud Drive among its destinations. `health4ai` already does
observer queries with background sync.

Worth noting for positioning: `health-md`'s App Store listing states it "automatically
collects limited pseudonymous product events using a random app-install ID", and it monetises
via StoreKit 2. The nearest OSS competitor charges and phones home.

**Consequence:** we compete on correctness and honesty, not on licence.

### PC-6 — A medical-device declaration is now mandatory

Since **26 March 2026**, new apps whose primary or secondary category is Health & Fitness or
Medical must declare regulated-medical-device status in App Store Connect for the EEA, UK and
US. Existing apps must comply by early 2027, after which updates are blocked.
<https://developer.apple.com/news/?id=nyqbfz1y>

**Consequence:** launch-blocking compliance, not a nice-to-have. There is a second obligation
of the same character — DSA trader status (R-111) — which the first draft missed entirely.

### PC-7 — The GPL/App Store conflict is mostly folklore; the real risk is worse

Apple does not police licences. AGPL-3.0 (Ice Cubes, and `health-md` in this exact category)
and GPL-3.0 (Passepartout, Blink) apps ship on the App Store today. VLC was pulled in 2011
because a copyright holder who had not consented complained to Apple — not because Apple
objected.

The real risk is therefore reframed: **under copyleft, every contributor holds a de facto veto
over App Store distribution.** That is a copyright-concentration problem, which is why licence
and contribution intake must be decided together (D-01, D-02).

---

## 3. Goals and non-goals

### Goals

| # | Goal | Measured by |
|---|---|---|
| G-1 | The user's chosen destination holds a correct, complete copy of their selected Health data, including retroactively-inserted samples | The R-08 reconciliation capability reports zero discrepancy on the R-88 soak protocol |
| G-2 | A user can always answer "what left my device, when, to where, and did it arrive?" without developer tools | Unaided task success in usability testing, for the last 30 runs |
| G-3 | The app detects and surfaces its own silent failure | R-23's escalation fires within the freshness window in the R-88 soak, including with notifications denied |
| G-4 | A self-hoster goes from install to data-on-a-Grafana-panel in under 10 minutes | Timed, by a non-maintainer, on a clean machine |
| G-5 | The source and build path survive the owner, while the existing Apple identity may not | R-106 continuity and R-108 stranger build; a fork can continue under a different identity |

G-5 is deliberately hedged. The unhedged version is not achievable under individual Apple
enrolment (C-10), and claiming it would violate the document's own standard.

### Non-goals for v1

Stated so Stage 2 does not quietly reintroduce them.

| Non-goal | Why | Source |
|---|---|---|
| Standalone watchOS export app | Watch data already routes to the paired iPhone; incumbent ships none; no evidenced demand; largest untestable surface | MA-13, AR-01, QA |
| Listening TCP server | Bypasses Apple's HealthKit consent gate (PC-4). **Permanent** | SEC-01 |
| Any hidden, stealth or disguised operating mode *in our binary* | Anti-stalkerware. **Permanent**. iOS 18 can hide the app; we cannot. See R-41 | SEC-54 |
| A bespoke iCloud Drive destination, or CloudKit sync of health data or of journals containing sample values | 5.1.3(ii) forbids the app storing PHI in iCloud. **The local-file destination writes wherever the user points the system document picker, including an iCloud-backed folder; that choice is the user's, made in Apple's UI, and we ship no iCloud code** | HK-22, SEC, MKT, AR |
| Google Drive, Dropbox, Calendar, email | Each is a perpetual OAuth obligation with a client ID in a public repo, against a user base in the low thousands | AR, MA-12 |
| Metric-count parity ("150+") | A losing race; we publish a generated coverage matrix instead | MKT-21, AR |
| Analytics, insights, trends, or health dashboards | Invisible to the wedge; Grafana exists and is where this audience lives. **Narrowed from v0.1 — an in-app data browser is now required by R-69** | MKT-21, UX |
| Plugin architecture | Not feasible on iOS (no dynamic code loading) and enormous | AR |
| Any interpretation, diagnosis, screening, clinical-threshold alerting or clinical recommendation | Avoids software-as-a-medical-device status under MDR/FDA. **Permanent** | SEC-63 |
| FHIR, clinical records, research/IRB workflows | Entitlement gated at reviewer judgement; institutional requirements no volunteer project can carry | MA-15, HK |
| Any hosted service, account, or paid cloud sidecar | Contradicts the privacy posture; unfunded operational obligation | MA-16 |
| Any outbound telemetry to a maintainer-controlled host, ever | Would make us a GDPR controller of Article 9 data and collapse the wedge. **Note this is now scoped to *outbound*: R-38 requires an inbound security advisory channel** | SEC, OBS, MKT-19 |
| GPX and FIT/TCX export | HealthFit owns the athlete segment; off-mission | AR, MA-14 |

---

## 4. Users

| # | Persona | Job to be done | Ceiling | Abandons us when |
|---|---|---|---|---|
| P1 | **Self-hoster** — Home Assistant and/or Grafana | "Get my health data into the stack I already run, and alert me when it breaks" | High; runs Docker, reads YAML | Setup exceeds an evening, or data silently stops |
| P2 | **Quantified-self practitioner** | "Own a complete, durable archive of my own data" | Medium; pastes a token, won't write code | Discovers a gap in historical data |
| P3 | **Developer building on their own data** | "A clean, documented feed I can write against" | Very high | The wire format churns |
| P4 | **Person leaving iOS** | "Get everything out before I go" | Low–medium | The one-shot full export fails or is incomplete |

P1 is primary, and is the only segment with a durable acquisition channel (HACS, the Grafana
dashboard catalogue). Ranking settles scope arguments in Stage 2.

---

## 5. Scope

### 5.1 Platform matrix

| Surface | Role in v1 | Explicitly not |
|---|---|---|
| iPhone (iOS) | The product. Control plane, HealthKit reader, exporter, configuration, history, data browser | — |
| iPad (iPadOS) | Same binary; reads HealthKit where the device has data | A separate experience |
| Status widget | **Must.** Last-success age in plain language. This is R-23's fallback when notification permission is denied, which is why it is not a Should | Data visualisation |
| Mac (macOS) | **Must.** Companion receiver: accepts export jobs pushed from the iPhone over the local network and writes them to a user-chosen folder. Restored to scope by D-14 | A HealthKit reader — impossible (PC-1). It is a destination, never a source |
| Apple Watch | Out of scope | Any target |

### 5.2 Destinations

The architect's finding that drove the cut: roughly **75% of the work is one shared
correctness engine**, so cutting destinations barely reduces v1 cost — but it substantially
improves the odds we are still maintained in eighteen months.

| Destination | Priority | Cost | Notes |
|---|---|---|---|
| Local file, to a user-picked folder via the system document picker | Must | 1.5 EW | Also the offline evaluation path and the fixture source |
| Generic HTTPS POST with a declarative request template | Must | 3 + 2 EW | The universal escape hatch; everything else is a preset of it |
| Home Assistant | Must, **as a preset of HTTPS** | 0.5 EW | Its documented third-party path is a bearer-token POST or webhook. Configuration, not integration |
| MQTT | Must | 3 EW | D-04 = yes. **Our first and, for v1, only non-Apple runtime dependency** — admitted subject to a recorded dependency review covering licence, maintenance health and supply-chain provenance |
| Mac companion, over the local network | Must | 5 EW | D-14. The only route to health data on a Mac, since macOS cannot read HealthKit (PC-1) |

### 5.3 Formats

NDJSON (native, streaming), JSON (HTTP bodies), CSV — all Must. Plus a **Health Auto Export
wire-compatible profile** (Must): the incumbent's real moat is not its app, it is the dozen
independent OSS receivers that already speak its format. Emitting a compatible payload starts
our ecosystem at parity instead of zero.

---

## 6. Requirements

MoSCoW. Every row traces to an originating specialist requirement. "Verify" is the acceptance
criterion; a requirement with no testable criterion was not admitted.

### 6.1 Correctness — the wedge

This section was seven rows in v0.1 and the reviewer was right that the wedge cannot rest on
it. The engine the architect prices at 75% of v1 is now specified.

| ID | Requirement | Pri | Verify | Traces |
|---|---|---|---|---|
| R-01 | The incremental watermark is keyed on sample **measurement** time, not HealthKit write time. Any aggregate window touched by a newly-observed sample is re-emitted however old the window is | Must | Write a sample dated 30 days in the past; the next run re-emits that day's aggregate. Write sleep samples with an evening start and a morning write time; the exported night spans the full session | MA-01 |
| R-02 | Every exported sample carries `HKObject.uuid` as a first-class field. The destination contract is **upsert by UUID**, with deletions as a separate tombstone stream keyed the same way | Must | Add, edit and delete a sample; assert the destination's final state matches HealthKit exactly. Replay a batch 10× and assert unchanged row count | AR-05, HK-16 |
| R-03 | Delivery semantics are **at-least-once with an idempotency key**, documented as such. We do not claim exactly-once | Must | Stated in the wire spec; a duplicate-delivery test asserts the receiver converges | QA-16 |
| R-04 | Per-type anchors advance only in the same durable transaction that persists the outbound batch. Gaps forbidden; duplicates permitted | Must | Fault injection: kill the process at every pipeline step; assert no sample is ever lost | AR-03 |
| R-05 | Deletions propagate as tombstones **on a best-effort basis, documented as such** in the wire spec and in the UI. Guaranteed convergence is via R-08 only | Must | A delete-only-change test that documents the actual observed behaviour, including the no-callback case | AR-06 |
| R-06 | Aggregated export is a **first-class mode with idempotent bucket keys**, not post-processing over raw export | Must | Recompute and resend a bucket; assert convergence at the sink | AR-10 |
| R-07 | The metric catalogue declares canonical aggregation semantics **per metric** (cumulative vs discrete; sum, mean, min, max), and every aggregate record states which computation produced it | Must | Compare our aggregates against `HKStatisticsCollectionQuery` for a multi-source metric on a real device; document any divergence | AR-30 |
| R-08 | Maintain a per-type **date high-water mark** alongside each anchor, plus a bounded reconciliation sweep (default trailing 7 days) and a user-triggerable full reconcile | Must | Restore-from-backup test; deliberate anchor-corruption test; reconcile detects and repairs the gap | AR-04 |
| R-09 | Bounded outbound queue (default 256 MB) with oldest-first eviction, a persisted user-visible gap record naming the date range lost, and one-tap re-export of the evicted window | Must | Fill-the-queue test; assert gap-record accuracy and successful re-export | AR-12, SEC-62, D-11 |
| R-10 | Time zone, DST and canonical-unit handling are explicit: every record carries the originating time zone offset, and units are canonicalised per metric with the canonical unit named in the payload | Must | DST-transition, leap-year and unit-boundary fixtures pass; a sample recorded in the repeated hour lands in the correct bucket | AR-08/09/11 |
| R-11 | Full-history backfill **on iOS 26+** completes unattended and resumes across interruption. **On iOS 18–25 it requires foreground time** (or a long accumulation of opportunistic wakes); that is stated in-product and in the App Store description. Default first-run backfill is **aggregate-only**; raw backfill is an explicit user action (O-5) | Should | Timed backfill against a seeded 5-year store on REF-A/REF-B (iOS 26, unattended) and REF-C (iOS 18, foreground-driven); kill mid-run and confirm resume without duplication or skip | MA-11, A-4 |
| R-12 | The export wire format is a versioned specification with its own stability commitment, independent of the app's release cycle. The HAE compatibility profile is a **migration path**, not a co-equal destination: it is structurally ineligible for R-23, R-24 and R-27, permanently labelled *"compatibility export — correctness claims do not apply"*, and the native profile is co-enabled by default | Must | Spec plus machine-readable fixtures in-repo; CI fails on a breaking change to a frozen version; HAE destinations are excluded from the honesty surfaces by construction | MA-09, MKT-08, A-21 |

### 6.2 Honesty

| ID | Requirement | Pri | Verify | Traces |
|---|---|---|---|---|
| R-20 | A durable on-device journal records every run: trigger, per-phase timings, samples read / sent / acknowledged, outcome, error class. It survives process death | Must | Kill-and-relaunch test; journal intact and complete | OBS-01, MA-04 |
| R-21 | A run is **never** recorded as success if acknowledged samples are fewer than samples read. Outcomes are drawn from a closed set: `success`, `success_nothing_due`, `partial`, `unknown_ack`, `failed`, `abandoned_no_budget`, `cancelled_by_system`, **`blocked_device_locked`**, **`local_network_denied`**. `partial` carries a **mandatory cause code**. `success` records `ack_evidence` of `status_only` or `receipt_full`. `blocked_device_locked` is excluded from the circuit breaker and from the escalation's "our fault" state. A 2xx with no receipt body is `success` with `ack_evidence = status_only`, not `unknown_ack` | Must | Force each failure mode including locked-device and Local Network denial; assert the recorded outcome names the specific cause; assert `partial` always has a cause; assert webhook 2xx is `success` | OBS-04, MA-04, A-1, A-2, A-20 |
| R-22 | Scheduling failure (the OS never woke us) is attributed separately from execution failure (we ran and failed) | Must | Simulate both; assert distinct outcomes and distinct user-facing copy | OBS-13 |
| R-23 | Silent failure escalates: **in-app indicator → local notification (if permitted) → status widget** showing last-success age in plain language. Escalation degrades gracefully when notification permission is absent. The notification is rescheduled on every success, so **silence itself becomes an event** | Must | Soak test with export deliberately broken: the escalation surfaces within the freshness window with zero background execution granted, **and again with notifications denied** | OBS-12, UX-22, QA-14 |
| R-24 | The freshness target N is **per freshness class A–D**. Once a destination has ≥14 days and ≥100 samples in a class, N is that device's measured p95; until then R-71's published figure is the placeholder. N is shown before the user relies on it | Must | N appears in-product and in the README, per class; R-71's findings document justifies the placeholder | PC-2, HK-32, A-3 |
| R-25 | No destination may be enabled until a test exercising the real path, credential and payload passes, reported per step. Where the protocol cannot confirm delivery (MQTT QoS 0), the result is `Sent, unconfirmed` — never success | Must | Configure a bogus host; assert the test fails and the destination cannot be saved | UX-08/09/10 |
| R-26 | A redacted diagnostic bundle can be exported by the user. It is bounded by construction to **the greater of the last 30 runs or 24 hours**, user-adjustable. **Every byte that will be shared is rendered** in a scrollable viewer whose end must be reached before any share affordance is reachable | Must | Automated assertion that no share affordance is reachable without passing the preview; a maintainer diagnoses a seeded failure from the bundle alone; canary test asserts no health values, tokens or hostnames present; soak captures cover a full 24 h even when run frequency exceeds 30/day | OBS-08, OBS, A-12 |
| R-27 | "Time since last successful export" is consumable by the user's own monitoring, with a documented failure taxonomy | Must | The signal is emitted and documented; an alert can be constructed from it. **Criterion deliberately does not depend on R-113/R-115, which are Shoulds** | MKT-10 |

### 6.3 Security, privacy and user safety

v0.1 promoted 8 of the security engineer's 78 requirements under a blanket claim that the rest
were Stage 2 design constraints. That claim was false for five of them. The list below is now
explicit, and §12 records which SEC requirements were considered and not promoted, so the
filter is auditable rather than trusted.

| ID | Requirement | Pri | Verify | Traces |
|---|---|---|---|---|
| R-30 | An append-only on-device egress ledger records every transmission: destination, transport security, sample counts, outcome. Entries are **tamper-evident, not immutable**: an out-of-band edit is detected on next launch and reported; delete-all writes a genesis marker into the successor ledger recording how many entries were destroyed and when | Must | Ledger entries exist for every run; an out-of-band edit is detected; delete-all produces a genesis marker naming count and date | SEC-11, A-18 |
| R-31 | Destination verification ships as one indivisible feature: canary handshake before any health data moves, displayed certificate identity, dry-run payload preview, pin-on-first-use with halt-on-change | Must | All four present; a changed certificate halts export pending explicit re-approval | SEC-09/10/12/13 |
| R-32 | The user configures an explicit allowlist of network destinations. The app makes no request to any host not on it. The advisory endpoint (R-38) is the sole built-in entry, is shown in the UI, and is user-disableable | Must | Network capture: with a host removed, zero **application-initiated** connections to it across a full cycle. OS-initiated DNS, OCSP/CRL and CT traffic is enumerated and excluded by name in the harness | MKT-09, A-17 |
| R-33 | Credentials stored at `AfterFirstUnlockThisDeviceOnly`, excluded from backup, verified by taking an actual backup | Must | Take a device backup; assert no credential material present | SEC-33, SEC-30 |
| R-34 | No listening socket on iOS (PC-4) | Must | Static and runtime check: no listener bound | SEC-01 |
| R-35 | Plain-HTTP and private-CA endpoints are permitted only via an explicit per-destination opt-in that names the risk in plain language, is never the default, and is recorded in the ledger | Must | The self-hoster path works; the opt-in is required, logged and visible in the destination list | SEC |
| R-36 | No third-party SDK of any kind — analytics, attribution, crash reporting | Must | CI fails the build if any non-first-party binary dependency is linked; privacy manifest matches | MKT-03, MA-07 |
| R-37 | **No outbound** telemetry. No install counters, no crash reports, no aggregate pings, ever | Must | Clean install, full session; network capture shows zero *outbound-initiated* connections to any developer-controlled host other than R-38's advisory fetch | MKT-19, SEC |
| R-38 | An in-app **security advisory channel**: a signed feed fetched only on user-visible foreground launch, carrying no request-identifying content beyond app version, endpoint printed in the UI and README, fetches recorded in the R-30 ledger | Must | A test advisory is delivered to a device during release rehearsal | SEC-74 |
| **R-40** | **A local notification fires whenever a destination is added or an existing one is re-pointed**, escalating through badge, non-dismissible in-app banner and status widget. Suppression of any rung is itself recorded as a security event. iOS 18 Hide-and-Require-Face-ID **strips notification previews**, so the hostname cannot be the only carrier of the fact | Must | Test asserts the notification fires on destination creation and on re-point, **and again with notifications denied**. SPIKE-COERCE records what survives concealment | SEC-53, A-16 |
| **R-41** | **Our binary never conceals destinations, credentials-in-use or the egress ledger.** No stealth mode, no alternate icons (`CFBundleAlternateIcons` absent), no configurable app name, no subtree authentication that hides those surfaces. **The OS can hide the app**; we cannot prevent it. The README and `Where your data goes` document Apple's recovery path (Settings > Apps > Hidden Apps, Screen Time, Battery, App Store purchase history) and link Apple's Personal Safety guide | Must | Feature review gate at every stage; binary scan for alternate icons and disguise affordances; recovery path present in README; SPIKE-COERCE records the remaining rungs | SEC-54, A-15 |
| R-42 | No feature interprets, diagnoses, screens, alerts on clinical thresholds, or recommends clinical action | Must | Feature review gate at every stage | SEC-63 |
| R-43 | In-app "delete all credentials, queued data, logs, ledger and history", idempotent and verifiable | Must | Post-action Keychain enumeration by access group returns zero items; container contains no payloads | SEC-69, HK-26 |
| R-44 | Within 60 seconds of the app **observing** that read authorisation for a type has been revoked — observation at every foreground launch and every background wake — that type's queued payloads are purged, an R-30 ledger entry is written, and the type is disabled with a user-visible reason. iOS provides no revocation callback; exposure between revocation and the next execution is bounded by the queue TTL (7 days) and size cap. The app also offers an explicit per-type stop-and-purge in two taps | Must | Timed test from observation, plus a UI test of the explicit action; README states there is no callback | SEC-70, A-7 |

R-40 and R-41 are the anti-coercion controls. The threat is concrete: an abusive partner with
a few minutes of physical access and the passcode configures a destination they control, and
the victim's sleep, cycle and location-adjacent data flows to them indefinitely. Every design
choice in this PRD — no account, no cloud, no telemetry, an arbitrary user-configured
endpoint — makes that easier, and R-30's ledger records it faithfully while telling nobody.
These two requirements are the difference between a privacy tool and a surveillance tool.

**v1.1 restates them because iOS 18 can hide a user-installed app in four taps.** The
requirement on *our binary* is not negotiable. The requirement that the OS cannot conceal the
app is false, and claiming it would be the kind of lie this product exists not to make.
SPIKE-COERCE decides how many rungs of R-23 survive concealment; Stage 2 does not close until
that is measured.

### 6.4 Observability

The observability engineer's verdict inverts the original ask, and it is worth restating.
OpenTelemetry on Apple platforms is *more* viable than expected — `opentelemetry-swift-core`
is Apache-2.0, builds for watchOS 4+, tracing is Stable, and it has zero transitive
dependencies on Apple platforms. But it cannot answer the owner's actual question, because on
iOS `OSLogStore` can only be opened with `.currentProcessIdentifier` scope and therefore
**cannot read logs written by a previous run of our own app**. A background wake that failed
three days ago is unreachable through the OS logging system.

So the journal (R-20) is the source of truth and OTLP is a projection of it. If v1 must shed
scope, we cut OTLP export, not the history.

| ID | Requirement | Pri | Verify | Traces |
|---|---|---|---|---|
| R-50 | First-party code logs through `os.Logger` directly, not a `swift-log` facade, preserving `%{private}` / `%{public}` redaction annotations. A transitively linked logging facade, if any third-party MQTT library is later admitted, is not used by our code | Must | ADR recorded; no first-party `swift-log` usage; app-target dependency scan | OBS, A-19 |
| R-51 | Telemetry redaction is by **allowlist**, not denylist. A field is absent unless explicitly permitted, with the permission argued in code review | Must | CI canary test on every commit with a seeded token, hostname `clinic.example.org`, sample value and source name "Dexcom G7"; build fails on any leak | OBS-07, SEC-37/38 |
| R-52 | Default telemetry egress is zero | Must | Automated network-isolation test plus a `PrivacyInfo.xcprivacy` check | OBS-22 |
| R-53 | OTLP/HTTP trace export to a **user-supplied** collector: opt-in, off by default, traces only | Should | A self-hoster receives spans in their own collector; disabling produces zero egress | OBS, MKT-10 |
| R-54 | W3C `traceparent` propagation to destinations is per-destination opt-in, default off, carrying no health attributes | Could | Header present only when opted in; attribute allowlist test passes | OBS + SEC, resolved in §12 |
| R-55 | Maintainer-bound telemetry: **Won't**, permanently, recorded as an ADR | Won't | No collector exists; no code path targets a project-controlled host for egress | SEC, OBS, MKT-19 |

### 6.5 Experience

| ID | Requirement | Pri | Verify | Traces |
|---|---|---|---|---|
| R-60 | The app never asserts that a HealthKit read was denied. Apple guarantees denial is indistinguishable from absent data, so every zero-result case states both causes and offers the path into Health | Must | Copy review plus a test with a denied type; assert no false denial claim | UX-01 |
| R-61 | A "only types with data" filter, default on, plus a curated first-run default of roughly 24 types | Must | First-run selection shows 30–60 rows, not 150+; the first export is non-empty | UX-13/14 |
| R-62 | HealthKit authorisation is requested per feature on enable, never as a bulk request for the full type set | Must | No code path requests all types; each request traces to a visible feature | HK |
| R-63 | The locked-device and best-effort-scheduling constraints are disclosed in-product **before** the first HealthKit permission prompt, and in the README | Must | The disclosure precedes the authorisation request in the flow | MA-05, UX |
| R-64 | Export status never relies on colour alone; full VoiceOver support; Dynamic Type to accessibility sizes; WCAG 2.2 AA contrast | Must | Automated accessibility audit plus a manual VoiceOver pass of the critical flows | UX |
| R-65 | Health measurement units follow locale with explicit override (kg/lb, mmol/L / mg/dL, °C/°F, 12/24h) | Must | Locale matrix test | UX |
| R-66 | A sensitive-type class (reproductive health, mental health, sexual activity, clinical) is excluded from all presets and from bulk-select, requiring individual opt-in | Must | Bulk-select never includes a sensitive type | UX, D-07 |
| R-67 | Credential entry supports QR/config import and paste, with reveal/redact on stored secrets | Should | A destination is configurable end-to-end without typing a token by hand | UX-47 |
| R-68 | Shortcuts / App Intents expose a manual export action, for users who need determinism the platform will not give us | Should | An export runs from a Shortcut and appears in the journal | PC-2, UX |
| R-69 | The app renders the user's own selected health data on device, per type, with values and timestamps — **a data browser, not a dashboard** — sufficient for a reviewer to see health functionality and for a user to verify an export against the source | Must | A reviewer can see health data in the app; a user can compare a browsed value against the exported record | HK-27 |

R-69 exists for two reasons that reinforce each other. Guideline 2.5.1 expects HealthKit to be
used for health purposes, and "HealthKit capability without substantial health functionality"
is a reported rejection cause — so this is RK-3's real mitigation. It is also the natural
verification surface for the correctness wedge: the user checks our number against Health's
number. v0.1 excluded it via an over-broad "no charts" non-goal sourced from specialists who
were not reasoning about App Review.

### 6.6 Testability — constraints on Stage 2

Not test tasks. Architectural constraints that must land in Stage 2 or the strategy collapses
into manual testing.

| ID | Requirement | Pri | Verify | Traces |
|---|---|---|---|---|
| R-80 | HealthKit sits behind a seam such that the whole export pipeline runs with HealthKit **not linked**. The core package and its tests build and pass on Linux, **with a committed exception list**: metrics whose canonical aggregation provider is `hkStatistics` are exercised on Linux against a recorded reference vector, and their canonical correctness is gated by R-87's device pass. The list is generated from `MetricCatalog` and is asserted non-growing without an ADR | Must | Linux CI is a required check from the first commit; exception-list golden file in CI | QA-01, A-9 |
| R-81 | Clock, calendar, time zone and locale are injected, never read from the ambient environment in core code | Must | Static check; DST and leap-year fixtures pass deterministically | QA |
| R-82 | A three-tier synthetic corpus: ~200 committed samples; 10,000,000 generated samples across ≥60 types over ≥5 years from ≥6 sources; a 50,000,000 pathological tier | Must | Tier 1 generates reproducibly from a committed seed in ≤10 min on a reference Mac | QA-04 |
| R-83 | Six named fault-injection seams exist in test builds only. Two assertions are restated against write-ahead ordering: `afterAckBeforeAnchorAdvance` asserts redelivery after a kill between acknowledgement and queue release; `duringAnchorPersist` asserts a kill inside the commit leaves the cursor at its pre-write value with the batch absent. `StoreLocked` asserts a locked-device wake produces a journal row | Must | Each seam exercised by a test; absent from release builds | QA, A-11 |
| R-84 | Output is byte-deterministic given identical input, configuration and a **declared time-zone database version**, recorded in the checkpoint envelope and every export manifest. Cross-platform digest equality is asserted only over UTC and fixed-offset fixtures | Must | (a) 100 runs on arm64 and x86_64 under hostile locale produce one digest per platform; (b) UTC/fixed-offset fixtures match across platforms; (c) CI fails when host tzdata differs from the recorded version | QA, A-8 |
| R-85 | Every required PR check passes on a fork with no secrets and no self-hosted runner | Must | A fork PR goes green | QA-28 |
| R-86 | Export is resumable from an inspectable, versioned checkpoint; anchors never silently reset | Must | Corrupt a checkpoint; assert explicit failure, not a silent full re-export | QA |
| R-87 | Real-device HealthKit verification is part of the release gate: a scripted device pass on a store with ≥2 years of real data from ≥3 sources, on named hardware, recorded | Must | A signed-off device pass in each release issue, naming device, OS and store characteristics | QA-34 |
| R-88 | Long-run correctness is verified by a soak protocol: ≥21 continuous days on a real device with a scripted daily diary, reconciling exported record counts against store counts at the end. The gate is **unexplained** discrepancy. Enumerated explanation classes: (1) documented HealthKit no-callback deletion, (2) known platform cap recorded in the R-71 findings, (3) user-initiated gap from queue eviction with a matching gap record, (4) **HAE-profile destination, which cannot express deletions or upserts** | Must | A completed soak record per minor release; unexplained discrepancy is a P1; HAE destinations are either excluded from the soak or classified under (4) | QA-35, A-5 |
| R-89 | The Home Assistant path is verified against a real HA instance at two pinned versions, asserting entity creation and read-back of `unit_of_measurement`, `device_class`, `state_class` and state precision | Must | Nightly container job creates entities and asserts read-back; the supported-version window is declared and enforced by the test matrix | QA-12 |
| R-90 | MQTT, if D-04 admits it, is verified against a real broker | Must (if D-04 = yes) | Integration test against an ephemeral broker in CI | QA-11 |
| R-91 | Every performance NFR is expressed as (workload, device, OS version, metric, threshold, percentile) with a committed on-device baseline. Each NFR maps to an automated device test **or** to a named, scripted, recorded device protocol executed per release (the R-87 pattern). R-77 and R-79 map to the latter. Until R-70/R-71/R-73 complete at M0, the four dependent thresholds and R-73's margin are **provisional** | Must | Each NFR maps to a device test or a committed protocol; pre-release job fails on >20% regression of the automated subset | QA-23, A-6, A-10, A-23 |

R-89 deserves a note: HA statistics silently fail without `state_class`, and only a real
instance reveals it. A silent failure in the primary persona's primary destination, in the
product built to eliminate silent failure, is the most embarrassing bug available to us.

### 6.7 Project and governance

| ID | Requirement | Pri | Verify | Traces |
|---|---|---|---|---|
| R-100 | Licence committed in the first commit (D-01) | Must | `LICENSE` present at commit 1 | OSS-01 |
| R-101 | DCO sign-off enforced on every commit, plus a written inbound=outbound statement and a licence-change rule | Must | CI rejects an unsigned commit | OSS-04/05 |
| R-105a | A second maintainer and shared commit rights | **Not pursued — owner decision (D-10)** | The commercial product remains owner-directed; continuity is the forkable source/build path in R-106 and R-108, not shared control | MKT-15, OSS-12/13, AR-F-02 |
| R-105b | Multiple maintainers shipping an **App Store** release | **Not applicable** | No additional maintainer role exists; the existing Apple distribution identity remains owner-controlled | AR-F-02 |
| R-106 | `CONTINUITY.md` states what happens if maintenance stops, including signing-identity handover, and — under individual enrolment — states plainly that the App Store channel has a bus factor of one, mitigated by R-108 and by the licence permitting a rebranded fork | Must | Present before v1.0; reviewed by someone outside the project | MKT-15, AR-F-02 |
| R-107 | README carries a machine-readable maintenance status (`maintained` / `seeking-maintainers` / `archived`) and a supported-OS matrix, updated every release | Should | Release cannot be tagged without them | MKT-17 |
| R-108 | Build-from-source is reproducible by a stranger on a clean machine, verified each release | Must | A non-maintainer builds from a tag using only the README | OSS-11 |
| R-109 | Regulated-medical-device status declared in App Store Connect for EEA, UK and US; "not a medical device" in first-run, About, README and landing page (PC-6) | Must | Declaration visible before submission; disclaimer in all four places | MKT-06 |
| R-110 | **No functionality, update, or build access is ever conditioned on donating or sponsoring**, and free binaries and security updates reach everyone regardless | Must | Feature-flag audit at each release: no sponsor-gated capability exists | OSS-23, SEC-78 |
| R-111 | DSA trader status declared in App Store Connect before first submission, with the trader/non-trader and P.O. Box/home-address decisions recorded (D-13) | Must | Declaration complete; address choice recorded | OSS-24 |
| R-112 | A legal opinion is obtained before (a) charging for the binary, (b) adopting any GPL-family licence, or (c) incorporating an entity | Must | Written opinion on file, referenced from the relevant ADR | OSS-25 |
| R-113 | No marketing surface claims medical, diagnostic, clinical, FDA/CE or HIPAA status | Must | Denylist check over published copy at each release; zero matches | MKT-20 |
| R-114 | A synthetic dataset and demo mode cover every supported metric family, loadable with no HealthKit history | Must | A new engineer on a clean simulator produces a complete export in under 10 minutes | MKT-04 |
| R-115 | A reference receiver runs from one command; a Grafana dashboard is published to the community catalogue | Should | `docker compose up` plus quickstart puts real data on a panel in under 10 minutes, verified by a non-maintainer | MKT-12 |
| R-116 | The Home Assistant integration is accepted into the HACS default list | Should v1 / Must within 90 days | Listed in HACS; HACS Action and hassfest pass in CI on `main` | MKT-11 |

R-111 is not paperwork. Apple publishes the declared address, phone number and email on the
product page across all 27 EU territories. For a solo maintainer of a health app that is a
personal-safety decision, which is why D-13 exists.

---

## 7. Non-functional requirements

Three reference devices:

- **REF-A — iPhone 15 Pro.** Representative current hardware. OS: iOS 26.
- **REF-B — iPhone 11.** Oldest device iOS 26 supports (A13). All iOS 26 ceilings must hold here.
- **REF-C — A12 iPhone (XR / XS / XS Max) on iOS 18.** The D-05 floor. Carries R-73, R-74, R-76
  and R-75 in its **foreground-driven** form. An iPhone X (A11, max iOS 16) cannot install the
  app and does not qualify. (A-22)

Every NFR below is stated as (workload, device, OS, metric, threshold, percentile) per R-91.
The architect flagged that these rest on an assumed HealthKit read throughput of ~1,600
samples/second which is **unvalidated** — hence R-70 and RK-2. R-72 has **zero headroom** at
that assumption. Until M0 measurements land, R-72, R-73, R-74, R-75 and R-24's N are
**provisional**.

| ID | Workload | Device | OS | Metric | Threshold | Pctl |
|---|---|---|---|---|---|---|
| R-70 | Measure actual HealthKit read throughput **at M0** (was: before Stage 2 closes) | REF-A, REF-B | iOS 26 | samples/s | Published finding; four NFRs below are void if the assumption is wrong | — |
| R-71 | Measure background-delivery reality: which types iOS silently caps at hourly, whether delivery survives Background App Refresh off, actual observer-query wake duration. **Deadline: M0** (was: Stage 2 close). Five calendar weeks of soak | REF-A, REF-B | iOS 26 | findings doc | Published at M0; R-24's N derives from it | — |
| R-72 | Delta export of 10,000 samples | REF-A / REF-B | iOS 26 | wall clock | ≤ 8 s / ≤ 15 s. **Zero headroom on REF-A at the unvalidated 1,600 samples/s assumption** | p90 |
| R-73 | Headless background launch to first HealthKit query | REF-B / **REF-C** | iOS 26 / **iOS 18** | wall clock | ≤ 400 ms on REF-B; **threshold for REF-C measured at M0, not asserted**. Also a stub of ≥100 cold background launches on REF-B | p90 |
| R-74 | Peak memory during full backfill | REF-B / **REF-C** | iOS 26 / **iOS 18** | RSS | ≤ 100 MB on REF-B; REF-C restated at M0 | max |
| R-75 | Full backfill, 5 years of typical Watch history. **Unattended on iOS 26+; foreground-driven on iOS 18–25.** Default is aggregate-only (O-5) | REF-B / **REF-C** | iOS 26 / **iOS 18** | wall clock | ≤ 30 min unattended on REF-B; foreground form on REF-C, threshold at M0 | p90 |
| R-76 | Cold start to interactive | REF-B / **REF-C** | iOS 26 / **iOS 18** | wall clock | ≤ 1,200 ms on REF-B; REF-C restated at M0 | p90 |
| R-77 | Steady-state battery | REF-A | iOS 26 | % / 24 h | ≤ 1.0%. Mapped to a **named device protocol** (MetricKit + Energy Log), not CI | mean |
| R-78 | Full backfill battery. **Must not be initiated from a system-scheduled background task** | REF-A | iOS 26 | % per run | ≤ 12% | mean |
| R-79 | Wake budget consumed by telemetry | REF-B | iOS 26 | % of wake budget | ≤ 2%. Mapped to a named device protocol, not CI | p90 |

R-73 matters more than R-76: the `BGAppRefreshTask` budget is roughly 30 seconds, so spending
8 seconds constructing a dependency graph burns 27% of it before any work happens.

### 7.1 Cost, capacity and what follows from them

v0.1 claimed scope discipline and contained no number, which made the claim untestable. The
architect's per-item estimates, carried through:

| Component | EW |
|---|---|
| Destinations and formats (local file 1.5, HTTPS 3, request template 2, HA preset 0.5, MQTT 3, NDJSON 1, JSON 0.3, CSV 1.5, HAE profile 1.5) | ~14 |
| Correctness engine, at the architect's "75% of cost" ratio | ~42 |
| Metric taxonomy, curated to ~40 families rather than full coverage | ~4 |
| Data browser (R-69), reference receiver (R-115), HACS integration (R-116) | ~8 |
| Accessibility to WCAG 2.2 AA and full VoiceOver (R-64) | ~3 |
| Test infrastructure: corpora (R-82), Linux CI (R-80), soak harness (R-88), HA contract tests (R-89) | ~8 |
| Mac companion receiver (restored by D-14) | ~5 |
| Governance artifacts, compliance declarations, release engineering | ~3 |
| **Total** | **~87 EW baseline; Stage 2 adds ~2.5 EW of accepted scope plus an unpriced MQTT delta → ~90 and rising, no contingency. Re-baseline owed after M0.** |

**Resolved by D-14: near-full-time capacity, full scope.** At a nominal 1 EW per calendar week,
discounted to ~0.8 to absorb reviews, triage, releases and compliance work, v1 lands at
roughly **20–26 months**. That is a real plan rather than the three-to-six years that volunteer
hours implied, and it is the basis on which the scope above is admitted.

Two things follow, and Stage 2 should treat both as planning constraints rather than
observations:

1. **Sequence the wedge first.** The correctness engine, journal, watchdog and local-file
   destination are ~55 EW of the ~87 and are the part that cannot be retrofitted. They should
   be shippable — internally, if not publicly — well before MQTT, the Mac companion or HACS.
   A 20-month runway with the differentiator landing last is the highest-variance ordering
   available to us.
2. **The estimate has no contingency.** It is a sum of the architect's point estimates, and
   RK-2 can invalidate four NFRs and an unknown slice of the engine. **Re-baseline after the
   R-70 and R-71 measurement spikes at M0** (A-23 moved that deadline off Stage 2 close). The
   spikes remain the cheapest risk reduction available and should happen first.

---

## 8. Constraints register

Non-negotiable. Stage 2 designs within these, not around them.

| ID | Constraint | Type | Evidence |
|---|---|---|---|
| C-01 | HealthKit is unreadable on macOS | Platform | **[verified locally]** — runtime probe returns `false` on macOS 26.6 |
| C-02 | The HealthKit store is Data Protection class **Protected Unless Open**; access is relinquished **10 minutes after the device locks** and returns on next unlock. Reads while locked fail with `HKErrorDatabaseInaccessible`. An `HKWorkoutSession` exception exists but we do not use it | Platform | Apple Platform Security, *Protecting access to user's health data*, published 2026-01-28 — <https://support.apple.com/guide/security/protecting-access-to-users-health-data-sec88be9900f/web> |
| C-03 | No scheduling API; background delivery is best-effort and capped per type | Platform | Apple DTS: "delivery frequency is not guaranteed… there is no API to change the behavior" |
| C-04 | Force-quit halts all background activity until next launch | Platform | Documented iOS behaviour |
| C-05 | Apps may not store personal health information in iCloud | App Review 5.1.3(ii) | Guideline text; see PC-3 for the boundary |
| C-06 | Health data may not be used for advertising or data mining | App Review 5.1.3 | Guideline text |
| C-07 | Requesting HealthKit types not tied to a visible feature is the most-reported rejection cause | App Review | Developer reports |
| C-08 | Medical-device declaration mandatory for new Health & Fitness apps in EEA/UK/US | Regulatory, since 2026-03-26 | <https://developer.apple.com/news/?id=nyqbfz1y> |
| C-09 | Apple FairPlay-encrypts and re-signs App Store binaries, so the shipped binary is **not** independently verifiable against source. We may claim auditable source and verifiable provenance, not a reproducible binary | Platform | Flagged unverified by the reviewer; conclusion is conservative either way |
| C-10 | An individual Apple Developer enrolment cannot share signing identities, capping the App Store bus factor regardless of governance | Apple policy | Developer Account Help: Certificates, Identifiers & Profiles is available only to Account Holders and members of an organisation's team. Independently verified by the reviewer |
| C-11 | DSA trader status must be declared, and Apple publishes the declared contact details publicly across the EU | Regulatory, since 2025-02-17 | OSS-24 |
| C-12 | In-app donation collection is prohibited; donations must be taken outside the app | App Review 3.2.2(iv) | Guideline text |
| C-13 | GitHub-hosted macOS runners have no Docker, so container-based contract testing depends on the core building on Linux (R-80) | CI | GitHub docs |

The CRA position that appeared here as C-11 in v0.1 has moved to RK-10. It rests on Commission
guidance that is expressly non-binding, and the register is for things that are settled.

---

## 9. Success metrics

Constrained by R-37: we are permanently blind to fleet-wide behaviour. That is a real cost and
it removes the usual retention metrics.

| Horizon | Metric | Target |
|---|---|---|
| 6 months | App Store units | 500 |
| 6 months | Issues filed by non-maintainers | 25 |
| 6 months | HACS listing accepted | Yes |
| 12 months | App Store units | 2,000 |
| 12 months | Independent receivers or dashboards built on our wire spec | 3 |
| 12 months | Independent clean build-from-source checks completed | 2 |
| Ongoing | Median time-to-first-successful-export, self-reported | < 20 min |

Deliberately not used: GitHub stars.

---

## 10. Risks

| ID | Risk | L | I | Mitigation |
|---|---|---|---|---|
| RK-1 | **Maintainer abandonment** — the category's defining failure; killed QS Access | High | Critical | R-105a/R-106 continuity, R-12 versioned spec. **HAE wire compatibility is a weak mitigation**: a stranded user falling back to HAE falls into the failure mode this product exists to fix (no tombstones, no upsert). Native profile co-enabled by default is the real continuity path. Scope discipline per §7.1 |
| RK-2 | **HealthKit read throughput far below assumption**, voiding four NFRs | Medium | High | R-70 spike at **M0** — the highest-value early measurement. R-72 has zero headroom at the assumption |
| RK-3 | **App Review rejection** — an export-only app held to lack primary features requiring health data | Medium | Critical | R-69 data browser (the real mitigation), R-62 per-feature authorisation, R-114 demo mode, pre-submission dry run |
| RK-4 | **Users blame us for Apple's locked-device ceiling** | High | Medium | R-63 disclose before the permission prompt; R-22 attribute scheduling failure honestly |
| RK-5 | **Observability requirements erode in Stage 2/3** — the security engineer notes this is the default outcome, not a tail case | High | High | R-51 canary test in CI from commit one, so erosion breaks the build rather than passing review |
| RK-6 | **A redaction defect leaks health data or a destination hostname** | Low | Critical | R-51 allowlist plus canary; irreversible once egressed, so treated as a build gate |
| RK-7 | **Silent export to a wrong host for months** | Medium | Critical | R-31 verification as one indivisible feature; R-30 ledger; R-40 notification on destination change |
| RK-8 | **Market too small to attract contributors**, worsened by any minimum-OS floor above the incumbents' iOS 17 | Medium-high | High | Recruit explicitly from P3; HAE wire compatibility puts us in front of existing receiver communities; D-05 |
| RK-9 | **Late trademark or App Store name rejection** forces a rename after listing, docs, HACS entry and dashboards embed it | Medium | Medium-high | Clearance search gates the name (D-06); keep the descriptive repo name as fallback |
| RK-10 | **CRA scope changes.** Donations keep us out of scope only while access is unconditional (R-110); charging makes us a manufacturer with CE marking and conformity assessment from December 2027. The guidance (C(2026) 5252, adopted 27 July 2026) is **expressly non-binding** — only the CJEU can interpret authoritatively | Low now, Medium if D-08 changes | High | R-110 keeps the condition true; review trigger on any monetisation change; R-112 legal opinion before charging |
| RK-11 | **The app is used as a stalkerware payload** | Medium | Critical | R-40, R-41, R-31, R-27 as a fifth surface concealment does not reach. iOS 18 Hide-and-Require-Face-ID defeats Home Screen presence and notification previews; SPIKE-COERCE measures remaining rungs. R-30's ledger alone is passive and reports to nobody |
| RK-12 | **v1 as scoped is 3–6 years at realistic volunteer capacity** (§7.1) | High | Critical | D-14. Recommendation: option 2, a 25–30 EW v1 that ships only the wedge |

---

## 11. Decisions

**All fourteen taken by the owner on 2026-09-02.** The table below records the decision, not
the recommendation; where the owner chose against my recommendation the reasoning is preserved
so Stage 2 knows what was traded away.

### 11.0 Decision log

| ID | Decision taken | Notes |
|---|---|---|
| D-01 | **AGPL-3.0** | Owner chose against my MPL-2.0 recommendation. Strongest copyleft; demonstrably App-Store-viable (`health-md` ships AGPL-3.0 in this exact category). Cost: the contributor-veto problem is now live, which D-02 must and does close |
| D-02 | **AGPL-3.0 + an explicit GPLv3 §7 additional permission for app-store distribution, granted by every contributor via DCO** | The Nextcloud/VLC-proven construction. Keeps contribution friction low while removing any single contributor's ability to block App Store distribution. The permission text is required in `COPYING`, `CONTRIBUTING.md` and the DCO assertion |
| D-03 | **Organisation enrolment**, using the owner's existing legal entity and D-U-N-S | Resolves C-10. R-105b becomes achievable, G-5 recovers its strong form, Guideline 5.1.1(ix) ceases to be a risk, and D-13 publishes a business address rather than a home one. Creates a CRA steward-vs-manufacturer question for R-112 |
| D-04 | **MQTT in v1** | Our first and only non-Apple runtime dependency, admitted subject to a recorded dependency review |
| D-05 | **iOS 18.0 minimum** | Trades a slightly larger test matrix for reach. Still above the incumbents' iOS 17.0; the residual reach cost is recorded in RK-8 |
| D-06 | **Deferred pending formal clearance search** | `Tributary` recommended, `Curlew` fallback. No name may be committed to code, listing or docs before clearance. The descriptive repo name remains the fallback |
| D-07 | **Ratified** — R-66's sensitive-type exclusion list stands | |
| D-08 | **Free binary, donations and actively-sought named sponsorship, all collected outside the app** | Conditional on R-110: no functionality, update or build access may ever be gated on sponsoring. Visible funding is the strongest available answer to RK-1 |
| D-09 | **Accepted** — permanent blindness to outbound fleet telemetry | Scoped to outbound only; R-38 preserves the ability to warn users. To be recorded as an ADR |
| D-10 | **Resolved — owner-directed, no maintainer recruitment** | R-105a and R-105b are not pursued. R-106 and R-108 preserve the honest continuity path: public source, reproducible builds, and separately identified forks |
| D-11 | **R-09 defaults adopted**: 256 MB queue cap, oldest-first eviction, persisted user-visible gap record, one-tap re-export | The one place the product deliberately loses health data now has an owner |
| D-12 | **Legal budget available**; R-112 stands | Required before charging, and now also for the D-03 CRA steward-vs-manufacturer analysis |
| D-13 | **Trader status declared against the legal entity's address** | Follows from D-03; removes the personal-safety concern that made this a decision |
| D-14 | **Near-full-time capacity, full scope**, with MQTT and the Mac companion both restored | ~87 EW, ~20–26 months. See §7.1 for the two sequencing constraints this imposes on Stage 2 |

### 11.1 Original decision framing

Retained because it records what each decision cost and how reversible it is.

| ID | Decision | Recommendation | Reversibility |
|---|---|---|---|
| **D-01** | **Licence** | MPL-2.0 for the app and first-party modules; Apache-2.0 for reusable standalone packages; CC BY 4.0 docs; CC0 schemas. MPL-2.0 and EPL-2.0 both offer file-level copyleft, an express patent grant, and App Store compatibility; MPL is preferred for ecosystem familiarity and because EPL-2.0 adds an uncapped commercial-contributor indemnity. **Note the anti-clone property is weaker than it sounds**: MPL copyleft is per-file, so a competitor can add all differentiation in new files as a Larger Work under §3.3 and publish nothing | **Very hard** |
| **D-02** | **CLA or DCO** | DCO. A bet that we will never dual-licence | DCO→CLA later means chasing every past contributor; CLA→DCO is free |
| **D-03** | **Apple enrolment: individual or organisation.** *Gate.* | Three inputs, not one. (a) Individual cannot share signing identities (C-10), so R-105b and G-5's strong form are unavailable. (b) Organisation needs a legal entity and D-U-N-S, and incorporating may create CRA steward obligations. (c) Guideline **5.1.1(ix)** says apps in highly regulated fields should be submitted by a legal entity — the HealthKit expert's reading, which I share, is that it should not bite an export utility, but the downside is account-level | Moderate; migration is disruptive |
| **D-04** | **MQTT in v1?** | Only under §7.1 option 1 or 3. Under option 2, no | Easy |
| **D-05** | **Minimum OS** | Genuine trade-off, stated honestly rather than asserted away. Both Health Auto Export and `health-md` ship `minimumOsVersion` 17.0; a higher floor means strictly fewer installable devices in an already small market, worsening RK-8. Against that, one OS version is a large QA saving and the only iOS-26-only API in play is `BGContinuedProcessingTask`, which serves R-11 (a Should). **Revised recommendation: iOS 18.0** | Easy to lower only if Stage 2 avoids version-specific assumptions, which it will not by default |
| **D-06** | **Name** | Marketing recommends **Tributary** (fallback **Curlew**). Reject anything containing "Health" — five near-identical App Store names exist and Apple filed `APPLE HEALTH` across four classes in June 2026. **No name may be committed before a formal clearance search** | Very hard after launch |
| **D-07** | **Sensitive-type class** | Ratify R-66's exclusion list | Easy |
| **D-08** | **Funding model.** *Reopened.* | v0.1 dismissed MKT-18 using a CRA argument that defeats only half of it. MKT-18 recommended "a price **or** explicit named sponsorship", and the same Commission guidance says third-party sponsorship does not create scope provided results are openly published. So: free binary, donations and named sponsorship outside the app (C-12), conditional on R-110. **Sponsorship is now recommended rather than merely permitted**, because visible funding is the strongest available answer to RK-1 | Charging later triggers CRA manufacturer obligations and requires R-112 |
| **D-09** | **Accept permanent fleet blindness?** | Yes, as an ADR. Note this is now blindness to *outbound* telemetry only; R-38 preserves the ability to warn users | Reversing collapses the positioning |
| **D-10** | **Is there a second maintainer?** | No. The product remains owner-directed and does not recruit maintainers. Maintenance status reports whether the owner is actively maintaining it; continuity is via source and independently reproducible builds | Owner decision recorded during Stage 3 |
| **D-11** | **Queue bound, drop policy and TTL** | R-09's defaults: 256 MB, oldest-first eviction, persisted gap record, one-tap re-export. This is the one place the product deliberately loses health data and it needs an owner, not an implementer's default | Easy to tune, hard to retrofit the gap record |
| **D-12** | **Is there a legal budget?** | Two specialists asked independently. If no, the recommended path (MPL-2.0, DCO, free, donations outside the app) is specifically chosen to be defensible without one — which is a better argument for D-08 than the CRA one | — |
| **D-13** | **DSA trader declaration: trader status and published address** | Apple publishes the address across 27 EU territories. Investigate P.O. Box eligibility before declaring. This is a personal-safety decision, not paperwork | Hard to unpublish |
| **D-14** | **Capacity vs scope.** *Gate.* | §7.1: v1 as scoped is ~82 EW against 0.25–0.5 EW/week. Choose more capacity, a ~25–30 EW v1, or a publicly stated multi-year horizon. **Recommendation: the smaller v1** — correctness engine, local-file destination, journal, watchdog, data browser | — |

---

## 12. Conflicts resolved and overrides recorded

### Between specialists

| Conflict | Positions | Resolution |
|---|---|---|
| Licence | MA-06: permissive or GPL+§7. AR: Apache-2.0/MIT. OSS: MPL-2.0. MKT: AGPL+§7 | **MPL-2.0** (D-01). Governance did the deepest research, including checking what VLC's licence actually is. The architect reached the opposite conclusion from primary sources (FSF enforcement statements, the VLC removal) rather than from folklore — he was wrong on the conclusion, not lazy, and v0.1 mischaracterised that |
| Monetisation | MA-08: free, no IAP. MKT-18: a price **or** named sponsorship | **Free + donations + named sponsorship** (D-08). v0.1 used CRA to defeat the whole of MKT-18; CRA reaches only the price. Corrected |
| `traceparent` egress | OBS wants per-destination opt-in; SEC vetoes telemetry egress broadly | **Per-destination opt-in, default off, no health attributes** (R-54). The one thing OTel does here that nothing else can |
| MQTT in v1 | AR: yes, gated on dependency. MA-12: Could, evidence-gated | **Should**, and excluded outright under §7.1 option 2 |
| watchOS | Brief implies it. MA-13, AR-01, QA all say drop | **Dropped.** Unanimous among those who examined it |
| OTel priority | Owner asked for OTel. OBS says the journal outranks it | **Journal Must, OTLP Should.** Respects the intent — seeing what the system is doing — while following the evidence that OTel cannot read a previous process's logs on iOS |
| Metric coverage | Brief implies 150+ parity. HK counted ~210 types; AR prices the taxonomy at 9–18 EW | **Neither parity nor a count claim.** ~40 curated families, marked passthrough, generated coverage matrix |
| Data browser | HK-27 (Should) wants one for App Review; MKT-21 and UX exclude charts | **Required as R-69**, narrowly scoped to a browser rather than a dashboard. v0.1 got this wrong by applying a non-goal from specialists who were not reasoning about App Review |

### Where the adversarial reviewer overrode me

19 of 20 findings accepted; see `reviews/01-disposition.md` for the full table. The four that
changed the product rather than the document: the anti-coercion controls (R-40, R-41), the
security advisory channel (R-38), the correctness engine (R-06 through R-10), and §7.1's cost
arithmetic. The Mac companion returned to Won't, where the architect had put it before I
promoted it without saying so.

### Where I overrode the reviewer

**AR-F-06, rejected.** The reviewer said C-02's 10-minute figure was "wrong by roughly 60×",
citing Apple's generic Data Protection page for **Complete Protection** (10 seconds). But the
HealthKit store is in **Protected Unless Open**, a different class. Apple's health-specific
security page, published 28 January 2026, states: "This data is stored in the Data Protection
class Protected Unless Open. Access to the data is relinquished 10 minutes after the device
locks." I fetched it directly. Three specialists cited this same page, two with the URL. The
reviewer's secondary point was fair and is fixed: C-02 was uncited, and now carries the class,
the figure, the source and the date.

### Local verification, corrected

v0.1 reported 121 `HKQuantityTypeIdentifier` constants and called it consistent with the
HealthKit expert's 120. It was not consistent, it differed, and **the specialist was right**.
Counting declarations rather than textual occurrences:

```
HKQuantityTypeIdentifier        120     HKCharacteristicTypeIdentifier    6
HKCategoryTypeIdentifier         70     HKCorrelationTypeIdentifier       2
```

198 declared identifiers in `HKTypeIdentifiers.h`, before workouts, ECG, audiograms and
clinical types. My extra match was `HKQuantityTypeIdentifierFlightClimbed` — a typo inside an
`API_DEPRECATED` message string in `HKWorkout.h`, not an identifier. The count supports only
"more than 150 identifiers exist"; the argument that a count is a bad marketing claim is the
HealthKit expert's separate and better point.

---

## 13. Traceability

| Specialist | Contribution | Filed | Promoted |
|---|---|---|---|
| Competitive / Market Analyst | `contributions/01-competitive-market-analyst.md` | 16 `MA-`, 67 sources | 8 |
| Apple Platform / HealthKit Expert | `contributions/02-healthkit-platform-expert.md` | 35 `HK-`, 40 sources | 6 |
| Principal Software Architect | `contributions/03-principal-architect.md` | 32 `AR-` + 20 NFRs, 53 sources | 14 |
| Senior Security Engineer | `contributions/04-security-engineer.md` | 78 `SEC-`, 33 threats | 15 |
| Observability Engineer | `contributions/05-observability-engineer.md` | 33 `OBS-`, 57 sources | 9 |
| UI/UX Designer | `contributions/06-ux-designer.md` | 50 `UX-` | 11 |
| Marketing Manager | `contributions/07-marketing-manager.md` | 21 `MKT-` | 11 |
| QA Lead / Test Architect | `contributions/08-qa-lead.md` | 39 `QA-` | 12 |
| OSS Governance / Licensing | `contributions/09-oss-governance.md` | 26 `OSS-` | 8 |

Security requirements considered and **not** promoted, so the filter is auditable rather than
trusted: SEC-02…08 (transport hardening detail), SEC-14…29 (destination-adapter specifics),
SEC-31/32/34…36 (Keychain mechanics), SEC-39…52 (telemetry pipeline internals), SEC-55…61
(supply-chain tooling), SEC-62 (folded into R-09), SEC-64…68 (release engineering),
SEC-71…73/75…77 (disclosure process mechanics). These are genuine Stage 2 design constraints
and carry forward as such. The five that were **not** design constraints — SEC-53, 54, 63, 69,
70 — are now R-40, R-41, R-42, R-43, R-44.

The promotion filter throughout: does this change *what we build* (PRD) or *how we build it*
(Stage 2 input)?

---

## 14. Stage 1 exit criteria

- [x] Nine specialist contributions delivered
- [x] Premise-breaking claims independently verified
- [x] Conflicts resolved and recorded (§12)
- [x] Adversarial review completed
- [x] All 20 findings dispositioned (`reviews/01-disposition.md`)
- [x] **D-03 and D-14 decided** — gates; the document was partly contingent on both
- [x] D-01, D-02, D-04…D-13 decided (§11.0)
- [x] PRD approved by the owner

**Stage 1 closed 2026-09-02.** Carried into Stage 2: the §8 constraints register as
non-negotiable design inputs, the §6.6 testability constraints, the two sequencing constraints
in §7.1, the R-70 and R-71 measurement spikes as the first work items, and the ~230 specialist
requirements not promoted here as design-level inputs.

Open items tracked into Stage 2 rather than blocking closure: D-06 (name
clearance) and R-112's legal opinion on the D-03 CRA analysis. D-10 was later
resolved during Stage 3 in favour of an owner-directed model with no maintainer
recruitment.

---

## 15. Stage 2 amendments (v1.1)

Ratified 2026-09-03 against `docs/02-design/00-system-design.md` v0.2 and
`docs/02-design/reviews/01-disposition.md`. This table is the auditable filter Stage 1 promised
and Stage 2 initially failed to keep.

| # | Req | Change landed in this file |
|---|---|---|
| A-1 | R-21 | `blocked_device_locked` |
| A-2 | R-21 | `partial` cause code; `ack_evidence` |
| A-3 | R-24 | N per freshness class, device-measured p95 |
| A-4 | R-11, R-75 | Per OS tier; App Store disclosure |
| A-5 | R-88 | Unexplained discrepancy; four explanation classes |
| A-6 | R-91 | Mapped, pending M0 measurement |
| A-7 | R-44 | Clock starts at observation |
| A-8 | R-84 | Per-platform + declared tzdata |
| A-9 | R-80 | Committed `hkStatistics` exception list |
| A-10 | R-91 | Device protocol for R-77/R-79 |
| A-11 | R-83 | Write-ahead seam assertions |
| A-12 | R-26 | Greater of 30 runs or 24 h |
| A-13 | SEC-04 | Design-input only; not a PRD row |
| A-14 | R-44 | Merged with A-7 |
| A-15 | R-41 | Binary claim + OS concealment + recovery path |
| A-16 | R-40 | Chain, not a single notification |
| A-17 | R-32 | Application-initiated traffic only |
| A-18 | R-30 | Tamper-evident, genesis marker |
| A-19 | R-50 | First-party `os.Logger`; no facade use |
| A-20 | R-21 | `local_network_denied` |
| A-21 | RK-1 | HAE is a weak abandonment mitigation |
| A-22 | §7 | REF-C |
| A-23 | R-70, R-71, R-73 | Deadline M0; R-73 measured |

**Not yet closed by this patch:** O-7 hardware inventory. SPIKE-COERCE partial-complete
2026-09-03 (widget survived; notification delivered). O-11: REF-C is an iPhone XR.
