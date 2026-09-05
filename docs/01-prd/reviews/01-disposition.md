# Disposition of Adversarial Review Findings — Stage 1

**Reviewer verdict:** REJECT (5 Blocker, 10 Major, 5 Minor)
**PM disposition:** 19 of 20 accepted, 1 rejected with evidence
**Resulting artifact:** `PRD.md` v0.2
**Date:** 2026-09-02

The review was good. Its central charge — that I wrote a positioning statement about
correctness and then failed to specify the correctness engine — is correct, and it is the
kind of error that would have surfaced in Stage 3 as "why does our data disagree with the
Health app" rather than in Stage 1 where it is cheap. Nineteen findings are accepted.

One is rejected, and the rejection is itself evidenced rather than asserted.

---

## Summary

| Finding | Severity | Disposition | Where fixed |
|---|---|---|---|
| AR-F-01 | Blocker | **Accepted** | R-37 amended to "outbound"; SEC-74 promoted as R-38 |
| AR-F-02 | Blocker | **Accepted** | R-62 split into R-105a / R-105b; G-5 hedged; D-03 promoted to a Stage 1 exit gate |
| AR-F-03 | Blocker | **Accepted** | Non-goal narrowed; HK-27 promoted to Must as R-69 |
| AR-F-04 | Blocker | **Accepted** | SEC-53/54/63/69/70 promoted as R-40…R-44; stealth mode added as a permanent Won't |
| AR-F-05 | Blocker | **Accepted** | §7.1 cost and capacity added; Mac companion returned to Won't |
| AR-F-06 | Major | **REJECTED** | C-02 retained at 10 minutes; citation added — see below |
| AR-F-07 | Major | **Accepted** | AR-10 and AR-30 promoted as R-06 and R-07 |
| AR-F-08 | Major | **Accepted** | R-02 restated as upsert-by-UUID per AR-05 |
| AR-F-09 | Major | **Accepted** | R-05 restated as best-effort per AR-06 |
| AR-F-10 | Major | **Accepted** | AR-12 promoted as R-09; D-11 added |
| AR-F-11 | Major | **Accepted** | AR-04 promoted as R-08; QA-34/35 promoted as R-87/R-88 |
| AR-F-12 | Major | **Accepted** | OSS-23 and SEC-78 promoted as R-110; C-11 moved to risk RK-10; D-08 reopened |
| AR-F-13 | Major | **Accepted** | §7 rewritten to QA-23's six-tuple (R-91); two-tier devices; NFR-02/10/11 restored as R-73/R-77/R-78 |
| AR-F-14 | Major | **Accepted** | OBS-12 escalation promoted into R-23; widget to Must; HK-32 promoted as R-71 |
| AR-F-15 | Major | **Accepted** | QA-11/12 promoted as R-90/R-89; R-27 criterion decoupled from Shoulds; OBS-08 added to R-26 |
| AR-F-16 | Major | **Accepted** | OSS-24 and OSS-25 promoted as R-111 and R-112; D-12, D-13 added; 5.1.1(ix) added to D-03 |
| AR-F-17 | Minor | **Accepted** | iCloud non-goal restated to remove the contradiction with §5.2 |
| AR-F-18 | Minor | **Accepted** | "Only mainstream licence" corrected; Larger Work limitation stated; VLC dropped from D-01 |
| AR-F-19 | Minor | **Accepted** | D-05 rationale restated honestly; recommendation changed to iOS 18.0 |
| AR-F-20 | Minor | **Accepted** | Count corrected to 120; §13 promotion counts added; §12 reworded; `health-md` cited |

---

## AR-F-06 — rejected, with evidence

**The finding:** that C-02's "access relinquished ~10 min after lock" is "wrong by roughly
60×", because Apple documents that for Data Protection class **Complete Protection** the class
key is discarded 10 seconds after lock.

**Why it is rejected:** the HealthKit store is not in Complete Protection. It is in
**Protected Unless Open**, which is a different class with different semantics. Apple's
health-specific security documentation states it directly:

> "This data is stored in the Data Protection class **Protected Unless Open**. Access to the
> data is relinquished **10 minutes after the device locks**, and data becomes accessible the
> next time user enters their passcode or uses Face ID or Touch ID to unlock the device."
>
> — *Protecting access to user's health data*, Apple Platform Security, published 28 January 2026.
> <https://support.apple.com/guide/security/protecting-access-to-users-health-data-sec88be9900f/web>

I fetched this page directly during disposition. The 10-minute figure is current, health-
specific, and correct. The reviewer cited the generic data-protection-classes page, which
describes a class HealthKit does not use.

Three specialists — market analyst, UX designer and observability engineer — independently
cited this same page and all three said 10 minutes. The reviewer's claim that the figure
"appears in no specialist contribution" is also incorrect; it appears in three, twice with the
URL.

**But the reviewer's secondary complaint was fair and is accepted:** C-02 was uncited, and an
uncited quantitative claim in a register marked "Stage 2 may not design around these" is a
legitimate defect regardless of whether the number is right. C-02 now carries the protection
class, the figure, the source and the publication date.

**One thing the finding got right in passing:** the same Apple page documents an
`HKWorkoutSession` exception — health data stays readable while locked for the duration of a
workout session. That is a genuine and previously unrecorded nuance, and it is now noted on
C-02. It does not help us (we do not run workout sessions and should not pretend to in order
to farm background time), but Stage 2 should know it exists.

---

## AR-F-20 — accepted, and the count discrepancy resolved

The reviewer noticed I reported 121 `HKQuantityTypeIdentifier` constants where the HealthKit
expert reported 120, and called it out as presenting a *difference* as *corroboration*. Fair.
I re-ran the count against declarations rather than textual occurrences:

```
HKQuantityTypeIdentifier           declared: 120
HKCategoryTypeIdentifier           declared:  70
HKCharacteristicTypeIdentifier     declared:   6
HKCorrelationTypeIdentifier        declared:   2
```

**The specialist was right and I was wrong.** My 121st match was
`HKQuantityTypeIdentifierFlightClimbed`, which is not an identifier at all — it is a typo
inside an `API_DEPRECATED` message string in `HKWorkout.h`, referring to the real
`HKQuantityTypeIdentifierFlightsClimbed`. My original command counted textual occurrences
across all headers rather than declarations, which is the wrong method for the question.

The PRD now reports 198 declared identifiers in `HKTypeIdentifiers.h` and drops the claim that
the count corroborated anything beyond "more than 150 identifiers exist".

---

## Findings that changed the product rather than the document

Four of the accepted findings are substantive rather than editorial, and are worth naming:

**AR-F-04, the anti-stalkerware controls, is the most important finding in the review.** I
dropped SEC-53 and SEC-54 under a blanket claim that the unpromoted security requirements were
Stage 2 design constraints. That claim was false for these two, and the reviewer's threat
narrative is correct: every design decision in this PRD — no account, no cloud, no maintainer
telemetry, an arbitrary user-configured HTTPS destination described in §5.2 as a "universal
escape hatch" — makes this a better stalkerware payload than the product it competes with. The
egress ledger records the exfiltration faithfully and tells nobody. A prohibition on stealth
modes and a notification on destination change are now product requirements, and the stealth
prohibition is a permanent Won't alongside the TCP server.

**AR-F-01 is a genuine own-goal.** R-27's "never phones home, ever" forbade the only channel
by which a health app could tell its users about a vulnerability in the version on their
phone. Absolutism read as rigour and was actually a gap.

**AR-F-07 and AR-F-08 are the correctness engine.** Aggregation is what users actually
configure and it was entirely absent; content-addressed identity cannot represent an edit,
and HealthKit represents edits as delete-then-add. Both are now specified.

**AR-F-05 caught me promoting the architect's explicit "Won't" to a "Should" without saying
so.** The Mac companion is back where he put it. I have also added the cost and capacity
figures I should have carried through from his estimates in the first place — the resulting
number (~75–80 engineer-weeks against 4–8 maintainer-hours per week) is uncomfortable, which
is precisely why it belongs in the document.

---

## Where the reviewer strengthened the case rather than weakening it

Recorded because it is evidence about the parts of the PRD that are solid:

- PC-1 (HealthKit unreadable on macOS) survived independent checking, and the runtime probe
  was judged the right verification for the right question.
- The "389 US ratings" figure was verified against the App Store lookup API and is more
  accurate than the market analyst's own 375.
- C-11's factual core was verified: Commission guidance C(2026) 5252 is final, adopted
  27 July 2026, not a draft as the governance lead believed.
- R-23's mechanism — a local notification rescheduled on each success, so silence becomes an
  event — was specifically attacked and held. The reviewer's objections were to the
  permission gap and the undefined threshold, both now fixed, not to the design.
- The repositioning itself held. The reviewer went in prepared to conclude "do not build
  this" and did not.
