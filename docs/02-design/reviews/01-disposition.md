# Disposition of the Stage 2 Adversarial Review

**Author:** Coordinating PM
**Date:** 2026-09-03
**Reviewing:** `01-adversarial-review.md` — verdict REJECT, 18 findings, 5 Blockers
**Outcome:** **REJECT accepted in full.** 18 of 18 findings accepted. 0 rejected. 2 discharged in whole or part by action taken before the review landed.

---

## 1. Verdict

I accept the rejection without argument. I verified every internal claim against the source
documents before writing this, and the reviewer was right on each one I could check:

| Reviewer's claim | Verification | Result |
|---|---|---|
| TA-01 is *Local Network permission denial*, filed **Major** | `07`:155 | **Confirmed** |
| The QA lead withdrew **four** pre-emptive Blockers, not three | `07`:18, `07`:141 | **Confirmed** |
| `04-security-design.md` is listed as owning **QA-38** | `07`:110 | **Confirmed** — my "residue" claim was false |
| `03` says receiptless is "`unknownAck`, never `success`" | `03`:1275 | **Confirmed** |
| `08` says HA webhook runs "report `success` on 2xx" | `08`:106 | **Confirmed — flat contradiction** |
| The architect filed **seven** unbuildable requirements | `01`:1008–1117 (§11.1–11.7) | **Confirmed** |
| The security engineer filed **six** | `04`:1291 | **Confirmed** |
| `R-41`, `R-32`, `R-30`, `R-26`, `R-72`, `Q10`, `Q11`, `Local Network`, `Data Protection`, `will not sign off` appear **zero times** in the synthesis | `rg -c` against `00-system-design.md` | **Confirmed — all zero** |

Thirteen proposed amendments, and §5 said "six places".

## 2. The root cause, stated plainly

The reviewer's closing paragraph identifies it correctly and I am not going to soften it.

PRD §6.3 contains this project's own apology for exactly this failure at Stage 1: v0.1 promoted
8 of the security engineer's 78 requirements "under a blanket claim that the rest were Stage 2
design constraints. That claim was false for five of them", and the remedy promised was that the
filter would be "**auditable rather than trusted**".

I then ran an unauditable filter at Stage 2, against the same specialist, on overlapping
requirements, and it dropped thirteen amendments and four of the nine QA findings. Four of the
five Blockers are downstream of that one mechanism.

SR-F-17 diagnoses *why*, and it is the part worth internalising: I opened the synthesis with
"the design holds — nine specialists converged rather than collided." A document that opens by
declaring convergence has stopped looking for collisions. The four interface collisions I missed
(SR-F-04, SR-F-05, SR-F-11, SR-F-15) are all the same shape — two specialists designing one
interface from opposite sides, each internally consistent, neither wrong alone. That is the
*expected* output of parallel work and the specific thing §4 existed to catch.

The structural fix is SR-F-17's: a §4.4 contact table with one row per cross-document interface
and a resolved/unresolved marker. The reviewer notes six rows would have caught four Blockers. I
am adding it, and I am adding a §5 rule that every specialist's "cannot build / cannot secure as
written" item gets an explicit accept-or-reject line, so the filter is auditable by construction
rather than by my diligence.

## 3. Disposition summary

| # | Severity | Disposition |
|---|---|---|
| SR-F-01 | Blocker | **Accept.** Anti-coercion. Primary-source half actionable now; widget half → spike SPIKE-COERCE |
| SR-F-02 | Blocker | **Accept.** All 13 amendments enumerated in §5 with accept/reject each |
| SR-F-03 | Blocker | **Accept.** §4.1 rewritten against the filed findings table; QA-38 claim withdrawn |
| SR-F-04 | Blocker | **Accept.** Adopt `08`, override `03`, add graded `ack_evidence` |
| SR-F-05 | Blocker | **Accept.** Class C for state+journal, Class B for payload blobs |
| SR-F-06 | Major | **Discharged.** Withdrawn independently before the review landed — see §4 |
| SR-F-07 | Major | **Accept in part; part discharged.** See §4 |
| SR-F-08 | Major | **Accept.** REF-C added → O-11 |
| SR-F-09 | Major | **Accept.** Amend R-70/R-71 deadline to M0, dependents marked provisional |
| SR-F-10 | Major | **Accept.** 60 days at REF-DELTA; scheduled reconcile; soften "guaranteed" → O-9 |
| SR-F-11 | Major | **Accept.** One threshold, one definition site, named owner |
| SR-F-12 | Major | **Accept.** O-2 split; "a few hundred lines" retracted as my invention |
| SR-F-13 | Major | **Accept.** ~90 EW and rising, no contingency, re-baseline owed |
| SR-F-14 | Major (judgement) | **Accept the reviewer's alternative over my own.** See §5 |
| SR-F-15 | Major | **Accept.** `01`§11.3 exception list carried verbatim; §1.5 qualified |
| SR-F-16 | Major | **Accept.** Security non-signoff → O-10; maintainer role → O-6 |
| SR-F-17 | Minor | **Accept.** Count corrected; convergence claim replaced; §4.4 added |
| SR-F-18 | Minor | **Accept.** R-26 bound + TA-07's condition |

**Accepted: 18. Rejected: 0.**

At Stage 1 I rejected one finding of twenty with evidence. I looked for one here and did not find
it. Manufacturing a rejection to demonstrate independence would be the same failure as
manufacturing a convergence claim, so I am not doing it.

## 4. The two findings partly overtaken by events

**SR-F-06 (GRDB) — discharged.** While the review was running I checked GRDB's Linux posture on
my own initiative and found the same README sentence the reviewer quotes. I withdrew the override
and reinstated the architect's first-party wrapper roughly twenty minutes before the review
landed. Two independent paths reached the same conclusion, which is mild evidence the conclusion
is right.

The reviewer adds two costs I had not priced, and both stand:

1. My "twenty months writing a database" rhetoric argued against a strawman. The architect
   proposed ~1,200 reviewable lines over a frozen C API, worth ~1–1.5 EW of the ~87 — not a
   database.
2. `01`§7.3 records that the wrapper makes the Data Protection class **directly settable** at
   open, whereas GRDB mediates it through configuration hooks. Per SR-F-05 that flag is exactly
   the one that must change. The override would have made the fix for a Blocker indirect.

The second point is the more interesting one: SR-F-05 and SR-F-06 are coupled, and neither the
architect nor I saw the coupling. The reviewer did.

**SR-F-07 (R-73's 400 ms) — accepted in part.** The finding has two limbs and they now diverge:

- *Limb 2 — the GRDB dyld precondition is invalidated:* **discharged** by the §4.2 withdrawal.
  The path is dependency-free again, which is what `08`'s ~120 ms dyld figure assumed.
- *Limb 1 — the budget is five unsourced point estimates:* **stands, fully.** This is the limb
  that matters. A p90 NFR under "cold, thermally unfavourable" conditions on a six-year-old
  device, presented as "~185 ms of margin" with no measurement, no variance and no citation, is a
  hypothesis. RK-2 already committed this project to measuring rather than asserting performance
  assumptions, and R-73 did not get a spike while R-70 and R-71 did.

R-73 joins the M0 spike set: a stub doing only the permitted operations, ≥100 cold background
launches on REF-B, p90 reported. Additionally — and the reviewer is right that this is worse —
**R-72 has zero headroom** (8.0 s budget, 8.0 s spend) at the 1,600 samples/s that RK-2 says is
unvalidated, with the design's own note that "at 800 samples/s the read phase alone is 12.5 s and
REF-A fails." R-72 appears nowhere in my synthesis. It is the NFR most likely to fail and it is
now in §5.

## 5. SR-F-14 — where I am taking the reviewer's judgement over my own

The reviewer explicitly declined to block on this and offered an alternative. I am adopting the
alternative, because on reflection it is better than mine and the argument is short.

I proposed shipping the HAE compatibility profile behind a **one-time acknowledgement screen**.
The reviewer's objection is that the control is mismatched to the harm: a one-time click is right
for a loss the user experiences immediately and can attribute, but this loss is *silent and
undetectable by construction* — no tombstones, no upsert key, so the destination quietly
accumulates records Apple Health has since deleted. That is the incumbent's exact failure mode,
and the premise of this entire product is that users cannot detect it unaided.

A consent click weeks before the first divergence does not arm anyone against an invisible
failure. That is decisive and I should have seen it.

Adopting the reviewer's three changes:

1. **Structurally ineligible for the honesty surfaces.** An HAE-profile destination does not
   participate in R-23's escalation, R-24's N, or R-27's external signal, and is permanently
   marked "compatibility export — correctness claims do not apply". This reuses the mechanism
   §4.3 already invented for MQTT QoS 0. A permanent visible property is the right shape for a
   permanent invisible loss.
2. **Positioned as a migration path**, not a co-equal destination, with the native profile
   co-enabled by default so the user always holds a convergent copy.
3. **Enumerated as a fourth R-88 explanation class** in A-5 — otherwise a soak run with an HAE
   destination fails the release gate by construction, and that is a gate that gets waived the
   first time it fires.

I am also accepting the second-order point: PRD RK-1 lists HAE compatibility as an *abandonment
mitigation* ("so users are not stranded"). But a stranded user falling back to HAE falls back into
the failure mode the product exists to fix. The mitigation is weaker than the PRD claims and RK-1
must be restated. That goes in §5.

## 6. The amendment ledger — all thirteen, adjudicated

This answers the security engineer's open question 6, which asked me directly and which I did not
answer. Every item gets accept or reject with a reason. **Nothing is silently dropped.**

### From `01-system-architecture.md` §11

| # | Req | Disposition |
|---|---|---|
| A-7 | **R-44** — 60 s purge deadline not implementable (*his highest severity*) | **Accept.** Both specialists filed it independently. Restate as a bounded best-effort with a stated ceiling |
| A-8 | **R-84** — cross-platform byte-determinism defeated by tzdata skew | **Accept.** Per-platform determinism + declared tz version; cross-platform equality only over UTC/fixed-offset fixtures. The reviewer independently confirmed the tzdata reasoning |
| A-9 | **R-80 vs R-07** — canonical aggregate unobtainable HealthKit-free | **Accept, verbatim.** This is SR-F-15. Committed non-growing exception list, generated from `MetricCatalog` |
| A-10 | **R-91 vs R-77/R-79** — two NFRs have no mappable automated test | **Accept.** Named, scripted, recorded device protocol per the R-87 pattern. Without it R-91 rejects two of its own NFRs at this review |
| A-11 | **R-83** — two seam names presuppose an inverted ordering | **Accept.** Was in §4.3 as a resolved conflict; promoted to a ratifiable amendment because it changes PRD text |
| A-12 | **R-26** — "full contents rendered on screen" unbounded | **Accept**, with TA-07's condition folded in: greater of 30 runs or 24 hours, user-adjustable. This is SR-F-18 |
| A-13 | **SEC-04**'s verification criterion | **Accept.** Design-input rather than PRD text, so it needs no owner ratification — recorded for completeness |

### From `04-security-design.md`

| # | Req | Disposition |
|---|---|---|
| A-14 | **R-44** | **Accept** — merged with A-7 |
| A-15 | **R-41** — "can never be hidden" defeated by iOS 18 | **Accept.** This is SR-F-01, the most serious finding in the review |
| A-16 | **R-40** — notification content stripped when the app is hidden | **Accept.** R-40's mechanism is a notification whose entire value is its content |
| A-17 | **R-32** | **Accept.** Restatement carried |
| A-18 | **R-30** — "immutable" is false; the property is tamper-evidence | **Accept.** The reviewer calls the T-51 genesis-marker design better than the PRD's own wording, and I agree. The architect's M6 gate currently asserts "immutable" and must be re-derived |
| A-19 | **R-50** | **Accept.** Restatement carried |

Plus, from the QA lead:

| # | Req | Disposition |
|---|---|---|
| A-20 | **R-21** — Local Network denial needs its own enumerated outcome | **Accept.** The real TA-01. Sibling to A-1's `blocked_device_locked`; R-21's set is PRD text so it needs ratification |

**Consequence the reviewer flagged and I confirm:** the architect's **M6 exit criteria** — the gate
at which the wedge is internally shippable — cite "R-44 (as amended, §11)" and "R-30 … immutable".
Both were unratified. With A-7 and A-18 accepted, M6 becomes signable; until they are ratified by
the owner it is not. M6 is re-derived in v0.2.

## 7. Blocker remediations in detail

### SR-F-01 — anti-coercion

Splitting by evidence quality, because the reviewer was careful to and the split changes what can
be decided today:

**Settled by Apple's primary source, actionable now.** Apple's Personal Safety User Guide confirms
a user-installed app can be hidden; that it leaves the Home Screen for an authentication-gated
Hidden folder; and that locking strips app information from notification previews, search, Siri
suggestions and call history. So **R-40 is already broken as designed** — `06` says the
notification "carries the hostname, because the hostname is the entire point", and the hostname is
precisely what a stripped preview does not deliver. R-41's invariant 4 ("the app looks like itself
on the Home Screen forever") is false as written. Both are amended now (A-15, A-16).

**Not settled; needs the spike.** Whether the widget survives concealment rests on secondary
sources, which is exactly why the security engineer asked for Q7(a) and why the reviewer refused
to assert it. This decides whether R-23's escalation chain has **one rung or zero** against a
coercer, and PRD §5.1 names the widget as the reason it is a Must rather than a Should.

`SPIKE-COERCE` — one device, under an hour: hide the app, then observe (a) whether the widget
persists and renders, and (b) whether a pre-scheduled local notification is delivered, and with
what content. **Owner action, blocking Stage 2 close.**

Restating R-41 per the security engineer: a claim about *our binary* — no in-app concealment
affordance, no `CFBundleAlternateIcons`, no configurable name, no subtree authentication — plus an
explicit statement that the OS provides concealment we cannot prevent, plus a documented recovery
path. Apple's own page names the residual surfaces: Settings > Apps > Hidden Apps, Screen Time,
Battery, and App Store purchase history. That path ships in the README and in `Where your data
goes`, linking Apple's guide.

`06`'s governing principle — "every rung must be correct without the app ever running again" — was
designed against app *death*. The coercion threat model is app *concealment*, and those are not
the same adversary. A fifth surface that concealment does not reach is needed; the strongest
candidate is one the design already has and has not used this way: R-27's external monitoring
signal, plus the R-30 ledger's presence in the Files/Shortcuts surface.

### SR-F-04 — the webhook acknowledgement contradiction

Adopting `08`, overriding `03`, and saying so explicitly. `03`:1384 asked me to confirm that
`unknownAck` was acceptable as the normal case for webhook destinations. I confirmed it in §4.3
without tracing the consequence through `05`, and the consequence is that a healthy Home Assistant
webhook — the primary persona's default destination — never re-arms the watchdog, never advances
the freshness clock, and escalates permanently after two runs.

The product built to eliminate silent failure would have shipped a permanent false alarm on its
most common configuration.

The two documents were answering different questions with one word. `03` means "no receipt
enumerating accepted records"; `08` means "a response in the declared success range". The fix is
to grade the evidence rather than flatten it:

- **No receipt, 2xx** → `success` with `ack_evidence = status_only` recorded in the journal.
- **Receipt present, short count** → `partial(receipt_short)` with a named cause.

The receipt stays a SHOULD that *upgrades* fidelity where present. The failure `03` was rightly
worried about — "succeeded but nothing arrived" — is the statistics-materialisation failure, and
`08` and TA-03 are both right that its mitigation is R-25's configuration-time read-back gate plus
TA-03's statistics-row assertion, not a permanent downgrade of every run outcome.

This is honest: the journal states the *strength* of the evidence for every acknowledgement, which
is strictly more information than either original position carried.

### SR-F-05 — Data Protection class

Settled here rather than deferred to M2, because it is settleable from Apple's published
documentation and the answer contradicts ADR-0005.

Class B (`NSFileProtectionCompleteUnlessOpen`) wipes the per-file key on close and re-creates the
shared secret from the class private key on reopen — and that private key is protected by the
passcode and device UID. Apple's developer-facing statement of the consequence is unambiguous: "A
closed file is inaccessible when the device is locked." Class B permits *creating and writing new*
files while locked and *continuing* to use an already-open file; it does not permit opening an
existing closed one.

ADR-0005 puts the whole database at Class B. Per C-02, HealthKit access is relinquished ten minutes
after lock, so the majority of background wakes occur while locked. Under ADR-0005 the app cannot
open its own journal during those wakes.

The self-defeating consequence, which is what makes this a Blocker rather than a Major:
**A-1 — my own headline amendment — cannot work.** `blocked_device_locked` exists so the app can
honestly report that the platform refused the read. You cannot write a row saying "we could not
read because the device was locked" into a database you cannot open because the device is locked.
R-20 ("a durable journal records **every** run") is unsatisfiable for the most common wake
condition, and R-22's scheduling-versus-execution attribution collapses in exactly the direction
`05` identified as a bias: an unrecordable wake is indistinguishable from a wake that never
happened.

Adopting `05`'s ADR-OBS-03: **state and journal tables at Class C**
(`CompleteUntilFirstUserAuthentication`), **payload blobs remain Class B**. The downgrade is
argued once in an ADR on the grounds the observability design already supplies — the journal holds
metric names and counts, not sample values, and `01`:760 already commits to no SQLCipher and no
encrypted database. The one-hour device test still runs, as confirmation rather than as the
decision procedure. And R-83's `StoreLocked` injector gains an assertion that a locked-device wake
produces a journal row.

This also resolves the ADR-0005 / ADR-OBS-03 contradiction, which `05` flagged and I did not carry.

## 8. Owner decisions — revised

O-1 through O-8 are superseded. The revised set, with the new items the review forced:

| # | Decision | Change |
|---|---|---|
| O-1 | HAE profile: ship as a *migration path* ineligible for the honesty surfaces | **Rewritten** per SR-F-14 |
| O-2 | MQTT client: first-party publish-only vs library | **Split**; GRDB half withdrawn; needs an EW price from the security engineer |
| O-3…O-8 | *(carried, with O-6 extended)* | O-6 gains the **security-maintainer role and deputy** — SEC-47/84/85 assume a named person with an SLA and D-10 records no second maintainer |
| **O-9** | Deletion-dating index: accept a **~60-day** horizon at REF-DELTA (not "~400 days")? | **New** — SR-F-10. The specialist said this "deserves your signature rather than mine". **DECIDED §11** — accepted, with the manual gap closed |
| **O-10** | Companion writing a decrypted health archive to an iCloud-synced folder | **New** — SR-F-16. The security engineer's explicit non-signoff. **DECIDED §11** — warn, do not refuse. App Review limb moot on the Developer ID decision |
| **O-11** | Fund **REF-C** (A12 iPhone XR/XS on iOS 18) as a third reference device? | **New** — SR-F-08. **DECIDED §11** — owner likely already owns one; model confirmation pending |
| **O-12** | Ratify all thirteen amendments (§6) | **New** — M6 is unsignable until A-7 and A-18 land. **DECIDED §11 — all thirteen ratified. M6 is signable** |

### SR-F-08 deserves its own note

This is the finding I am most annoyed to have missed, because the gap is created by a decision I
recommended. D-05 set the floor at iOS 18.0. PRD §7 defines *every* NFR on two devices at iOS 26,
with REF-B (iPhone 11) described as "the oldest device iOS 26 supports" — correct, since iOS 26
requires A13.

But iOS 18.0 admits the A12 iPhone XR, XS and XS Max, and the A10 7th-generation iPad. **Not one
NFR anywhere covers them.** And it compounds with F-3 rather than being independent: F-3 gives
iOS 18–25 a *separate foreground-driven backfill path* costed at ~1.5 EW, so the newly-designed
second execution path runs on the slowest hardware in the supported set with zero performance
coverage. R-91 says NFRs without a mapped test are rejected at Stage 2 review.

The only iOS 18 coverage is a nightly Simulator matrix — which cannot measure launch latency,
memory under thermal pressure or battery, and which the QA lead's own confidence note says cannot
be populated with HealthKit data at all.

I stand by not raising the floor: RK-8 (market too small) is the worse risk and both incumbents
ship iOS 17.0. But the reviewer is right that the judgement must be *paid for*, not assumed. Either
fund REF-C and restate R-73/R-74/R-76 plus R-75's foreground form for it, or state in the App Store
description that performance is characterised on iOS 26 hardware only and reduce the tier's claims
to match. Taking D-05's reach while specifying every threshold on hardware D-05's target cannot run
is not an option.

## 9. Schedule honesty

Per SR-F-13, and stated the way §6 should have stated it the first time:

**~87 EW → ~90 EW and rising, with no contingency and a re-baseline still owed.**

- F-3's second full-history execution path: **+1.5 EW**
- The designated-exporter decision in §4.3: **+1 EW**
- O-2's MQTT delta: **unpriced** — the security engineer owns the estimate
- SR-F-08's REF-C restatement: unpriced, small
- The five new/reworked amendments: unpriced, small

PRD §7.1 mandated a re-baseline *after* the R-70/R-71 spikes, which have not run — so the mandated
re-baseline cannot have happened, and §6 reported the un-re-baselined total without saying so.

I also accept the reviewer's correction on the giver. §6 nominated the Mac companion (M9, 5 EW) as
the natural scope reduction. But the companion was restored to scope by owner decision **D-14** and
is a Must in PRD §5.1. Naming it as the giver is re-proposing a cut the owner has already refused
once. It goes back to the owner as a question, not into the plan as an assumption.

## 10. What v0.2 must contain

1. §1 — convergence claim replaced with the structural-versus-interface distinction; QA withdrawal count corrected to four; §1.4's "guaranteed-convergence" softened to state its condition; §1.5's R-80 claim qualified by A-9's exception list
2. §4.1 — rewritten against the filed findings table; QA-38 residue claim withdrawn; TA-03, TA-04, TA-07, TA-09 dispositioned
3. **§4.4 — new.** The cross-document contact table: journal ↔ persistence schema; outcome taxonomy ↔ delivery semantics ↔ status copy; sink contract ↔ receipt semantics ↔ retry; seam ↔ fake ↔ corpus; escalation threshold; protection class. Resolved/unresolved per row
4. §4.3 — webhook adjudication (SR-F-04) with the `ack_evidence` grading; Q11's threshold owner named with a single definition site
5. §5 — all twenty amendments (A-1…A-20), each with accept/reject and a reason; R-72's zero headroom added
6. §6 — ~90 EW and rising, no contingency, re-baseline deferred to M0 with an exit-criteria row; M6 re-derived against the ratified amendment set
7. §7 — O-1 rewritten, O-2 split, O-6 extended, O-9…O-12 added
8. §8 — every exit criterion re-checked *after* the work rather than before. The two false ones (`TA-01 verified and downgraded`, `Conflicts resolved and recorded`) come down until they are true

## 11. Owner decisions taken — 2026-09-03

Four decisions were put to the owner after this disposition was drafted. All four are recorded
here; two change what §10 must contain.

### O-12 — Ratify all thirteen amendments: **YES, all thirteen as dispositioned**

A-7 through A-20 are ratified. **M6 becomes signable**, since the architect's exit criteria
citing "R-44 (as amended)" and "R-30 … immutable" now have a ratified amendment set behind them.
M6 is re-derived against that set in v0.2, and the security engineer's open question 6 is
answered in full for the first time.

### O-9 — Deletion-dating horizon: **accept ~60 days, and close the manual gap**

The `~400 days` figure is struck from the synthesis and replaced with **~60 days at REF-DELTA's
20,000 samples/day**, stated in days rather than as "far less". The manual-repair gap is closed
two ways, both of which the design can already afford:

1. A **scheduled low-priority full reconcile** on a cadence, subordinated to live delivery by the
   existing I6 admission-control mechanism — so it is nearly free.
2. A **targeted per-type sweep** driven by the `deletion_undatable` journal event, which already
   carries `{type, uuid}`, rather than waiting for a global reconcile.

§1.4's "guaranteed-convergence" survives with this, because convergence no longer depends on a
user action nothing prompts. The asymmetry the reviewer identified — automatic and unbounded for
late *additions* via the dirty-bucket ledger, manual for late *deletions* — is removed.

### O-11 — REF-C: **owner believes he already owns a suitable A12 device**

Pending model confirmation (see §12). If it is an iPhone XR, XS or XS Max, it is necessarily on
iOS 18 or lower — A12 cannot install iOS 26 — so it satisfies REF-C by construction.

### O-10 — Companion iCloud-folder write: **warn, do not refuse**

The owner chose to allow the write with a warning. **I recommended otherwise and I was working
from a stale premise; the owner's call is better-founded than my recommendation.**

My recommendation, and the security engineer's non-signoff behind it, both rested on App Review
Guideline 5.1.3(ii). But the security engineer's own open question 1 states that the distribution
choice is what "determines … whether Guideline 5.1.3(ii) binds the companion **contractually**",
and §4.3 had already settled it: **Developer ID, notarised, outside the Mac App Store**. A
notarised direct download is not reviewed, so 5.1.3(ii) does not bind the companion. The App
Review limb of the objection dissolves, and the reviewer's SR-F-16 — which recorded the question
as "genuinely unresolved" because Apple's guideline text does not distinguish attended from
unattended writes — is moot for a product App Review never sees.

Note also that the iOS app, which *is* reviewed, still writes nothing to iCloud. PRD §3's boundary
("we ship no iCloud code") holds unchanged on the reviewed product.

What survives is the **substantive privacy concern**, independent of Apple policy: our software,
unattended and repeatedly, may write a decrypted health archive into a synced folder. That is a
real property and it is what the warning exists to surface. Three implementation notes:

1. **Warning requires the same detection code as refusal.** You cannot warn about an
   iCloud-backed target without detecting one. So the cheap detection the security engineer
   wanted is still built; only the policy on a positive result differs. There is no cost saving
   in `warn_only`, which means the decision is purely about user autonomy — the right axis for it.
2. The warning must be **persistent, not one-time**, for the same reason the HAE acknowledgement
   screen was rejected in SR-F-14: a one-time click at configuration time does not arm a user
   against a standing property. Consistency matters here; I argued the general form of this point
   two sections ago and it applies to my own recommendation.
3. **Reversal trigger:** if the companion is ever proposed for the Mac App Store, 5.1.3(ii) binds
   immediately and this decision must be revisited before submission. Recorded in the ADR.

The pre-submission App Review enquiry the security engineer requested — twice, per SR-F-16 — is
**withdrawn as moot for the companion** on the Developer ID decision, rather than deferred a
third time. That is a disposition, which is what he was owed.

## 12. Stage 2 cannot close yet

Blocking on the owner: **SPIKE-COERCE** (SR-F-01), and ratification of the thirteen amendments
(O-12), without which M6 is unsignable.

Blocking on measurement: R-70 and R-71 are PRD Musts whose stated deadline is "before Stage 2
closes" and neither has run. Per SR-F-09 I am taking the reviewer's preferred option — amend both
to name M0 as the deadline and mark the four dependent NFRs provisional — because A-6's logic is
sound and the spikes genuinely cannot compress. But the amendment must name the requirements it
actually changes, which A-6 did not.

The design is close and, in places, genuinely strong — the reviewer's twelve-item "could not
falsify" section is not a courtesy and it covers the load-bearing mechanisms: the
anchors-versus-coverage inversion, the structural write-ahead cursor, the R-80 transport story,
the anti-drift fake, and the tamper-evident ledger. The engineering largely holds.

The document certifying it did not, and the certification is what the owner was being asked to
sign.
