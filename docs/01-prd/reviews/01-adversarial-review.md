# Adversarial Review — Stage 1 PRD

**Reviewer:** Adversarial Reviewer, Stage 1
**Artifact:** `docs/01-prd/PRD.md` (DRAFT v0.1, 2026-09-02)
**Date:** 2026-09-02

---

## Verdict

**REJECT.** Not because the analysis is bad — most of it is unusually good, and the premise
corrections are correct and well-evidenced — but because the PRD promotes a slogan
("correctness and honesty") while systematically dropping the requirements that would make it
true, and because five of its load-bearing structures do not survive contact with their own
constraints register.

The document is close. It is not signable. Resubmit with the following conditions met.

### Conditions for approval

1. **Resolve D-03 before Stage 1 closes, not after.** R-62, G-5 and the 12-month success
   metric are all unsatisfiable on the individual-enrolment path (C-10), and R-62 is the
   *only* mitigation listed for RK-1, the PRD's own highest-rated risk. Either commit to
   organisation enrolment, or restate R-62 conditionally and say plainly in the README that
   the App Store channel has a bus factor of one. (AR-F-02)
2. **Carve an exception into R-27 for a signed, user-visible security advisory channel**, and
   promote SEC-74. As written, the PRD forbids the only mechanism by which users of a health
   app could ever be told about a vulnerability. (AR-F-01)
3. **Promote the anti-coercion controls SEC-53 and SEC-54.** They are product prohibitions,
   not Stage 2 design constraints, and §6.3's disposal of them is factually wrong about what
   they are. (AR-F-04)
4. **Reconcile the "Charts, dashboards, analytics UI" non-goal with RK-3.** You have excluded
   the mitigation your HealthKit specialist made a requirement (HK-27) for the risk you rated
   Critical. Pick one. (AR-F-03)
5. **Add a scope cost and a capacity statement.** No effort estimate, no target date and no
   maintainer-hours figure appears anywhere, while the Mac companion — priced at 5 EW and
   classified **Won't** by the architect — was promoted to Should without comment. (AR-F-05)
6. **Restore the correctness requirements the wedge depends on**: aggregation as a first-class
   mode with declared per-metric semantics (AR-10, AR-30), the reconciliation sweep and
   date high-water mark (AR-04), time zone and canonical-unit handling (AR-08/09/11), the
   bounded queue and its drop policy (AR-12, SEC-62), and upsert-by-UUID rather than
   content-addressing (AR-05). (AR-F-07, AR-F-08, AR-F-09, AR-F-10, AR-F-11)
7. **Fix C-02.** "~10 min" is wrong by roughly 60×, uncited, and errs in the flattering
   direction. (AR-F-06)
8. **Reopen the D-08 reasoning.** The CRA constraint you used to override MKT-18 does not
   reach the half of MKT-18's recommendation that matters, and C-11 is stated as
   non-negotiable when the guidance it rests on is expressly non-binding. (AR-F-12)
9. **Add DSA trader status (OSS-24) and the 5.1.1(ix) publishing-entity question**, and record
   whether there is a legal budget — asked for by two specialists, dropped by both. (AR-F-16)
10. **Rewrite §7 to QA-23's own standard** — (workload, device, OS version, metric, threshold,
    percentile) — restore NFR-02 and a battery NFR, and either justify or drop the reference
    device softening from iPhone 11 to iPhone 13. (AR-F-13)

---

## The three things most likely to kill this project

**1. The bus factor is unresolved, and on the default path it is unresolvable.** The PRD's
answer to maintainer abandonment — the failure mode it correctly identifies as the category's
defining one — is R-62, "two people with commit and release rights." Apple's account model
makes that literally impossible under individual enrolment, the PRD knows this (C-10, D-03),
and its recommendation for D-03 is "decide consciously," which is not a recommendation. In
eight months this surfaces as: one person holds the signing identity, the second maintainer
can review but cannot ship, and the continuity plan in `CONTINUITY.md` describes a handover
Apple does not support without a support ticket.

**2. The wedge was repositioned but not re-specified.** The PRD concluded the original
differentiators fail, and picked "correct under late-arriving data, honest about every run."
That is the right call. But the requirements that would deliver it were dropped in the
synthesis: there is no aggregation requirement (only R-01's acceptance criterion, which tests
aggregates the PRD never requires), no declared aggregation semantics, no reconciliation
sweep, no time zone handling, no canonical unit rule, no bounded queue, and an idempotency
key (R-02, "content-addressed") that cannot represent an edit — which is exactly how HealthKit
represents an edit. What survived into §6.1 is seven rows that read like correctness. The
engine that the architect says is 75% of the cost is specified in about 300 words.

**3. The scope is described as disciplined rather than costed as disciplined.** The PRD claims
scope discipline as its central act of judgement and then contains no number: no engineer-week
estimate, no date, no statement of available maintainer hours — despite the architect having
published all three and explicitly recommending the capacity figure go into `CONTRIBUTING`.
Summing the architect's own figures for the surface the PRD kept, and applying his own "75% is
the engine" ratio, v1 lands somewhere around 80–100 engineer-weeks before the metric taxonomy.
For two volunteers at the 4–8 hours/week he cites, that is not a schedule, it is a decade.
Nothing in §3 or §10 defends against this, because nothing in the document acknowledges it.

---

## Findings

### AR-F-01 — R-27 makes it impossible to tell users about a vulnerability

**Severity: Blocker**

**Claim under attack:**
> R-27 | The app never phones home. No install counters, no crash reports, no aggregate pings,
> ever | Must | Clean install, full session, network capture shows zero connections to any
> developer-controlled host

reinforced by R-22 ("The app makes no request to any host not on it") and the §3 non-goal
"Any maintainer-bound telemetry, **ever**".

**Why it fails:** The security engineer's SEC-74 requires an in-app security advisory channel.
It is not telemetry — it is inbound, not outbound — and it is the only mechanism by which a
user of a health app learns that the version on their phone has a vulnerability. R-27's
acceptance criterion ("zero connections to any developer-controlled host") forbids it by
construction, and R-22's user-managed allowlist cannot substitute, because a user cannot
allowlist a host they have never been told about. The PRD promotes 8 of the security
engineer's 78 requirements and drops this one silently under the blanket claim in §6.3 that
"the remainder are Stage 2 design constraints and carry over wholesale."

This also removes the delivery mechanism for anything the project would need to tell users
under the FTC Health Breach Notification Rule, and — if D-08 is ever revisited — under CRA
Article 14, whose reporting obligations commenced on 11 September 2026.

**What would fix it:** Amend R-27 to read "no *outbound* telemetry, no analytics, no crash
reports, no install counters." Promote SEC-74 as a Must: a signed advisory feed, fetched only
on user-visible foreground launch, containing no request-identifying content beyond the app
version, with the endpoint printed in the UI and in the README, and its fetches recorded in
the R-20 egress ledger like any other. Amend R-22's acceptance criterion to allowlist that one
host explicitly rather than by omission.

---

### AR-F-02 — R-62, G-5 and the 12-month success metric are unsatisfiable on the default path

**Severity: Blocker**

**Claim under attack:**
> R-62 | `MAINTAINERS.md` names at least two people with commit and release rights;
> `CONTINUITY.md` states what happens if maintenance stops, including signing-identity
> handover | Must | Both present before v1.0; **both maintainers have shipped a release**

against
> C-10 | An individual Apple Developer enrolment cannot share signing identities, capping the
> bus factor regardless of governance

**Why it fails:** The PRD flags the tension in D-03 and then does not resolve it, which is not
the same as resolving it. Three separate structures depend on R-62 being satisfiable: G-5
("The project survives its founder"), the §9 metric "12 months | Second maintainer with
release rights active | Yes", and RK-1's mitigation — where R-62 is the *first* item listed
against the risk the PRD rates High/Critical and calls "the category's defining failure."

C-10 is correct and I verified it independently. Apple's Developer Account Help states that
Certificates, Identifiers & Profiles "is only available to Account Holders and members of an
organization's team," and Apple DTS restates it in the forums: "If you're enrolled as an
individual and add users in App Store Connect, users receive access only to your content in
App Store Connect and are not considered part of your team in the Apple Developer Program."
So R-62's acceptance criterion — "both maintainers have shipped a release" — cannot be met.

D-10 then compounds it by asking "Is there a second maintainer?" — meaning the PRD's answer to
its top risk is contingent on a question the PRD does not know the answer to, resting on a
capability the PRD knows may not exist.

**What would fix it:** Split R-62 into two requirements. R-62a (Must, unconditional): two
people hold commit rights, and both have independently cut a *source* release and a notarised
macOS build — neither of which requires the iOS signing identity. R-62b (Must, conditional on
D-03=organisation): both have shipped an App Store release. Then state in the README, under
the R-63 maintenance status, that under individual enrolment the App Store channel
specifically has a bus factor of one, and that the mitigation is R-64 build-from-source plus
the licence permitting a rebranded fork. That is a weaker claim, but it is a true one, and the
whole document's stated premise is preferring true claims to strong ones.

---

### AR-F-03 — The non-goals exclude the mitigation for the PRD's own Critical App Review risk

**Severity: Blocker**

**Claim under attack:**
> | Charts, dashboards, analytics UI | Invisible to the wedge; Grafana already exists and is
> where this audience lives | MKT-21, UX |

against
> RK-3 | **App Review rejection** — an export-only app may be held to lack "primary features
> requiring health data" | Medium | Critical | R-42 per-feature authorisation, R-67 demo mode
> so reviewers can exercise it, pre-submission compliance dry run

**Why it fails:** The HealthKit expert wrote HK-27 specifically to address RK-3: "The app MUST
include a genuine in-app health data browser, not merely a configuration screen," citing
Guideline 2.5.1's requirement that HealthKit "be used for health and fitness purposes and
integrate with the Health app" and the reported rejection pattern of "HealthKit capability
without substantial health functionality." His own framing: "'it's a data pipe' is a weaker
story than 'it's a health data manager with charts you can see'."

The PRD's non-goal is sourced to MKT-21 and UX — neither of which was reasoning about App
Review — and the override of HK-27 appears nowhere in §12. Note also that a data browser is
not the same thing as "charts, dashboards, analytics UI"; the non-goal is written broadly
enough to exclude both, and Stage 2 will read it broadly.

The three mitigations that remain do not close the gap. R-42 addresses a *different* rejection
cause (over-requesting types). R-67's demo mode gives a reviewer synthetic data to export, but
what 2.5.1 asks is whether the app does something with health data beyond moving it.

**What would fix it:** Narrow the non-goal to "analytics, insights, trends and health
dashboards," and add a Must: "the app renders the user's own selected health data on device,
per type, with values and timestamps, sufficient for a reviewer to see health functionality
and for a user to verify an export against the source." That is a data browser, it is cheap,
it is the natural verification surface for the correctness wedge anyway, and it removes the
strongest reading of RK-3.

---

### AR-F-04 — The anti-stalkerware controls were dropped, and mis-classified in the process

**Severity: Blocker**

**Claim under attack:**
> The security engineer produced 78 requirements and 33 threats. These are the ones that shape
> the *product*; **the remainder are Stage 2 design constraints and carry over wholesale.**

**Why it fails:** The statement is false for at least three of the dropped requirements, and
the most important is SEC-54, the prohibition on any hidden, stealth or disguised operating
mode — which the security engineer lists among the things they will not sign off on — together
with SEC-53, notification to the device owner when a new destination is added.

This is not a design constraint. It is a product prohibition, and it is the control that stops
this app from being an excellent stalkerware payload. Consider the threat concretely: an
abusive partner with a few minutes of physical access and the passcode configures a
destination pointing at a server they control. The victim's location-adjacent data, sleep,
menstrual cycle and workout patterns then flow continuously to the abuser. Every design
decision in this PRD makes that *easier*: no account, no cloud, no maintainer telemetry, an
arbitrary user-configured HTTPS destination, and — per §5.2 — a "universal escape hatch."

R-21 (destination verification) and R-20 (egress ledger) are the right primitives but they are
passive: they record the exfiltration faithfully and tell nobody. The PRD's own §5.1 status
widget is a **Should**.

Also dropped and also not design constraints: SEC-63 (no interpretation or diagnosis
features — the medical-device feature boundary that R-65/R-66 only address at the marketing
layer), SEC-69 (a delete-all action, which is also HK-26 and a reported App Review rejection
cause under 5.1.1(i)), and SEC-70 (revoking authorisation purges queued payloads).

**What would fix it:** Promote SEC-53 and SEC-54 verbatim as Musts in §6.3, with SEC-54
mirrored into §3 non-goals as a permanent Won't alongside the TCP server. Promote SEC-63,
SEC-69 and SEC-70. Then delete the "carry over wholesale" sentence from §6.3 and replace it
with an explicit list of which SEC requirements were considered and not promoted, so the next
reviewer can check the filter rather than trust it.

---

### AR-F-05 — No cost, no capacity, no date; and a Won't was promoted to a Should

**Severity: Blocker**

**Claim under attack:**
> The architect's finding that drove this cut: roughly **75% of the work is one shared
> correctness engine**, so cutting destinations barely reduces v1 cost

and
> | Mac companion (local network) | **Should** | Answers PC-1 for the "I want it on my Mac"
> user |

**Why it fails:** The PRD cites the architect's cost model to justify its cut line and then
declines to apply it. The architect priced every item in engineer-weeks. The Mac companion
receiver is in his table at **5 EW** with the verdict "**Won't** for v1", and it appears again
in AR-29's explicit v1 exclusions. The PRD promotes it to Should with no acknowledgement in
§12 and no cost attached. It is, by his own figures, the single most expensive line item the
PRD adopted, and it was on his Won't list.

More broadly: this document is written for a team of one to two people and contains no
estimate of anything. Sum the architect's figures for the surface the PRD kept — local file
1.5, HTTPS 3, HA preset 0.5, MQTT 3, Mac companion 5, request template 2, NDJSON 1, JSON 0.3,
CSV 1.5, HAE profile 1.5 — and you have ~19 EW of destination and format work. If that is the
25% the architect says it is, v1 is on the order of 75–80 EW before the metric taxonomy
(9–18 EW full, ~4 EW at AR-24's curated 40), before the reference receiver (R-68), before the
HACS integration (R-69), before WCAG 2.2 AA and full VoiceOver (R-44), before the 10M and 50M
synthetic corpora (R-52), before Linux CI (R-50), and before the twelve governance artifacts.

Against that, the architect's own capacity figure: "A realistic OSS maintainer has 4–8 hours
per week *in total*, including reviews, releases and issue triage." He recommended publishing
that number. The PRD does not contain it.

A PRD may legitimately decline to set a date. It may not claim scope discipline as its central
contribution and omit every number that would let a reviewer test the claim.

**What would fix it:** Add a §7.1 with three figures: an engineer-week estimate for v1 with
the architect's per-item numbers carried through; the assumed maintainer capacity in
hours/week; and the implied calendar duration. Then either move the Mac companion back to
Won't (per AR-29) or record the override in §12 with its 5 EW cost stated. My own view: cut
it. PC-1 is answered adequately by the local-file destination plus the HTTPS destination — a
Mac that runs the R-68 reference receiver already has the data — and 5 EW is roughly the whole
correctness budget you are short.

---

### AR-F-06 — C-02's "~10 min" is wrong by about 60×, uncited, and errs optimistic

**Severity: Major**

**Claim under attack:**
> | C-02 | HealthKit is unreadable while the device is locked | Platform |
> `HKErrorDatabaseInaccessible`; **access relinquished ~10 min after lock** |

**Why it fails:** The figure is wrong and it appears in no specialist contribution. The
HealthKit expert established that the HealthKit store sits in Data Protection class Complete
Protection; Apple's own documentation states that for that class, "**Shortly after the user
locks a device (10 seconds, if the Require Password setting is Immediately), the decrypted
class key is discarded**."
(<https://support.apple.com/guide/security/data-protection-classes-secb010e978a/web>)

Ten seconds, not ten minutes. It is the only quantitative claim in the constraints register —
described as "non-negotiable," a register "Stage 2 may not design around" — that has no source
and no specialist behind it, and the error runs in the direction that makes the product's
freshness story look better. A 10-minute post-lock read window would materially change how
often a background wake can do useful work; a 10-second one means what the specialists
actually said, which is that real export happens when the user is holding the phone.

I have not been able to determine where the number came from. If it is a real, measured
observation on iOS 26 it would be a genuinely interesting finding and should be marked
**[verified locally]** with the method, like PC-1 — but as it stands it reads as a
transcription error, and it is doing work in the register.

**What would fix it:** Replace the evidence cell with "Data Protection class Complete
Protection; class key discarded ~10 s after lock (Apple Platform Security)." If a longer
practical window has actually been observed, promote HK-32 to a Must and let Stage 2 measure
it, rather than asserting it here.

---

### AR-F-07 — The wedge's flagship requirement rests on a capability the PRD never requires

**Severity: Major**

**Claim under attack:**
> R-01 | The incremental watermark is keyed on sample **measurement** time, not HealthKit write
> time. **Any aggregate window touched by a newly-observed sample is re-emitted** however old
> the window is | Must | Write a sample dated 30 days in the past; **the next run re-emits that
> day's aggregate**

**Why it fails:** There is no requirement anywhere in the PRD that the product produces
aggregates. §5.3 specifies formats (NDJSON, JSON, CSV, HAE profile), not modes. R-01's
acceptance criterion therefore tests a behaviour of a feature the document does not commit to
building, which means the criterion is not verifiable against the PRD as written.

This matters because the architect made aggregation his fourth headline finding: "The real
trick in the reference product is aggregation, not raw sample export. Every community
integration for it configures `Summarize Data: ON`... Nobody ships 4.3 million raw samples to
Grafana... **A PRD that specifies only raw sample export will have specified the hard problem
and missed the useful one.**" AR-10 makes aggregated export a Must and a first-class mode with
idempotent bucket keys. It is not in the PRD.

AR-30 is also missing, and it is the one that generates support load: HealthKit's statistics
queries de-duplicate overlapping multi-source data, so a raw-sample sum and an aggregate will
legitimately disagree, and users will file that as data loss. The architect rated the
likelihood High. For a product whose entire proposition is "your destination holds a correct
copy," shipping two numbers that disagree with the Health app and with each other, without a
declared semantics per metric, is the wedge failing in its own terms.

**What would fix it:** Promote AR-10 as a Must in §6.1 ("aggregated export is a first-class
mode with idempotent bucket keys, not a post-processing step over raw export") and AR-30 as a
Must ("the metric catalogue declares canonical aggregation semantics per metric — cumulative
vs discrete, sum vs mean vs min/max — and every aggregate record states which computation
produced it"). Add AR-30's acceptance criterion, which is good: compare against
`HKStatisticsCollectionQuery` for a multi-source metric on a real device and document any
divergence.

---

### AR-F-08 — "Content-addressed" silently replaces upsert-by-UUID and cannot express an edit

**Severity: Major**

**Claim under attack:**
> R-02 | Every destination write is idempotent and **content-addressed** | Must

with
> R-54 | Output is byte-deterministic with **data-derived record identity** | Must

**Why it fails:** The architect was specific and emphatic: "`HKObject.uuid` is the only sane
destination-side primary key... the destination contract is *upsert by sample UUID*, plus a
separate tombstone stream, and the payload schema must carry the UUID as a first-class field
for every sample. **This one requirement is what makes the whole retry story safe, and it is
the single most important line in the export schema.**" (AR-05.)

The PRD substitutes content-addressing without recording the change in §12. These are not the
same scheme and the difference is exactly the case the wedge exists to handle. Under
content-addressing, identity is a function of the payload; when a user edits a sample in the
Health app, the value changes, so the identity changes, so the destination receives a *new*
record rather than an update to the old one — and the stale original stays there forever. The
HealthKit expert established that "**Updates arrive as delete-then-add**," with Apple warning
explicitly for medication dose events that samples are "logged for days in the past, deleted
and re-persisted when editing," and HK-16 requires the format to express an update.

R-05 requires deletions to propagate, so in principle the tombstone cleans up the original —
but R-05 is discussed at AR-F-09 below and is itself over-promised. And the PRD carries no
requirement that UUID appears in the payload at all.

Separately, R-02's acceptance criterion tests replay of an *identical* window three times. It
verifies idempotency under exact repetition, which is the easy case, and never exercises the
edit case that distinguishes the two schemes.

**What would fix it:** Restate R-02 as "every destination write is an idempotent upsert keyed
on `HKObject.uuid`, which is a first-class field in every sample record; deletions are a
separate tombstone stream keyed the same way." Keep R-54's byte-determinism, which is a
different and worthwhile property, and stop calling the identity content-derived. Change
R-02's acceptance criterion to: add, edit and delete a sample; assert the destination's final
state matches HealthKit exactly (this is HK-16's criterion, and it is better).

---

### AR-F-09 — R-05 promises what the platform will not deliver, and its criterion tests the easy path

**Severity: Major**

**Claim under attack:**
> R-05 | **Deletions and retractions propagate to destinations** | Must | Delete a sample in
> Health; the next run emits a tombstone the reference receiver applies

**Why it fails:** The architect addressed this exact sentence: "**Promising 'deletions
propagate to your destination' is a promise we cannot keep.**" Background delivery wakes the
app when samples are *saved*; a delete-only change frequently produces no callback until the
next insert of that type, and `HKDeletedObject` records are not retained indefinitely, so a
delete followed by a long quiet period can be missed entirely. AR-06 accordingly states
deletions as **best-effort, documented as such**, with guaranteed convergence coming only from
the AR-04 reconciliation sweep.

The PRD promotes the flat Must and drops the qualifier — in the section titled "Honesty."

The acceptance criterion makes it worse rather than better: "Delete a sample in Health; the
next run emits a tombstone" tests the case where a run happens, which is the case that works.
It does not test the delete-only-no-callback case, which is the failure the architect
identified.

**What would fix it:** Restate R-05 as AR-06 wrote it: "Deletions are propagated as tombstone
records on a best-effort basis, documented as such in the wire spec and in the UI; guaranteed
convergence is via the reconciliation sweep only." Change the criterion to the one AR-06
proposed — a delete-only-change test that documents the actual observed behaviour — and add
the reconciliation sweep it now depends on (AR-F-11).

---

### AR-F-10 — The one place the product deliberately loses health data has no owner

**Severity: Major**

**Claim under attack:** the absence of any queue-bound or drop-policy requirement in §6, and
the absence of the decision from §11.

**Why it fails:** Two specialists escalated this to the PM explicitly and neither got an
answer. The architect (AR-12, and Open Question 6): "Silently dropping health data is the
worst possible failure for this product; silently growing to fill the device is the second
worst. **Choosing between them is a product decision, not an implementation detail**... this
is the one place where the product deliberately loses health data and it deserves an explicit
owner." The security engineer asked the parallel question about queue TTL (SEC-62, Question 5).

Neither appears in §6, §8 or the D-01…D-10 list. The PRD's decision register instead contains
D-07 ("ratify R-46's exclusion list") and D-09 ("accept permanent fleet blindness?" —
recommendation: yes), which are lighter-weight than the one that was escalated.

Left undecided, this resolves itself in Stage 3 as whatever the implementer types, and the
most likely default — unbounded growth until the OS evicts the app's container — is the one
that produces a silent gap. In a product whose one-sentence pitch is "loud when it stops."

**What would fix it:** Promote AR-12 as a Must with the architect's proposed numbers as the
default (256 MB cap, oldest-batch-first eviction, a persisted user-visible "N samples were
dropped between date A and date B" record, and one-tap re-export of the evicted window), and
add **D-11: queue bound, drop policy and TTL** to §11 so the owner signs it. If you disagree
with oldest-first, say so and pick another — but this cannot leave Stage 1 unowned.

---

### AR-F-11 — G-1 is measured by a reconciliation check the PRD never requires

**Severity: Major**

**Claim under attack:**
> G-1 | A user's chosen destination holds a correct, complete copy... | **Reconciliation
> check**: destination row counts and values match a device-side census for a seeded corpus

**Why it fails:** There is no requirement for a reconciliation capability. AR-04 — "maintain
**both** a per-type anchor and a per-type date high-water mark, plus a bounded reconciliation
sweep (default trailing 7 days) and a user-triggerable full reconcile" — was not promoted.
R-04 covers anchor durability (AR-03) and R-56 covers checkpoint resumability, which are
different properties.

The architect's reason for AR-04 is the sentence this PRD should care most about: "The sweep
is how we can honestly answer 'did we miss anything'. **Without it, the answer is 'we believe
so', which is not a product claim.**" He also gives the failure mode: anchors are invalidated
by device restore, reinstall and HealthKit re-sync events, producing either a silent
restart-from-zero or a stale anchor that skips data. R-56 requires that anchors "never silently
reset," which detects corruption but does not repair a gap.

So G-1's measurement is a maintainer-side test against a seeded corpus, not a capability the
user has. The QA lead also required the field version of it — QA-35, a ≥21-day soak on a real
device with end-of-run reconciliation of exported counts against store counts, "any
discrepancy is a P1 by definition" — and that is not promoted either, though G-3 and R-13's
criterion both say "soak test" as though the infrastructure were specified somewhere.

**What would fix it:** Promote AR-04 as a Must in §6.1, and promote QA-34 and QA-35 into §6.6
as the release-gate infrastructure that G-1 and G-3 are measured against. Without QA-35 in
particular, "soak test" appears three times in this PRD as an acceptance criterion and is
defined nowhere.

---

### AR-F-12 — The CRA constraint used to override marketing does not reach marketing's recommendation

**Severity: Major**

**Claim under attack:**
> | Monetisation | MA-08: free, no IAP. **MKT-18: unfunded-free worsens the abandonment
> objection; prefers a price or named sponsorship** | **Free + external donations** (D-08),
> because charging triggers CRA manufacturer status (C-11) — **a constraint MKT did not have
> when it wrote its recommendation.** Dissent recorded and surfaced to the owner rather than
> buried |

**Why it fails:** Three distinct problems, in ascending order of seriousness.

*First*, MKT-18 recommended "a price **or explicit named sponsorship**." C-11 defeats the
price. It does not touch sponsorship. The same Commission guidance the PM is relying on says
so directly — the OSS governance lead's summary of ¶63–65 and Example 23: "Third-party
sponsorship or paid feature work does **not** create scope, provided the result is openly
published." So the PM dismissed a two-part recommendation using a constraint that reaches one
part, and characterised the dissenter as merely uninformed. The half of MKT-18 that survives
CRA scrutiny intact is not addressed anywhere.

*Second*, C-11 is stated as a non-negotiable constraint — §8's header says "Stage 2 may not
design around these" — on the strength of guidance that is expressly non-binding. I verified
the underlying document and, on the fact the governance lead flagged as uncertain, **the PM is
right and the specialist was over-cautious**: C(2026) 5252 is final, adopted 27 July 2026, not
a draft. But the commentary is equally clear that "the guidance is explicitly stated to be
non-binding: only the Court of Justice of the EU can give an authoritative interpretation."
(<https://cyber.thomasmurray.com/insights/eu-cyber-resilience-act-commission-publishes-implementation-guidance>)
A non-binding interpretive position belongs in the risk register with a review date, not in
the register of things Stage 2 may not design around.

*Third and most concretely*: C-11's conclusion is conditional, and the PRD does not require
the condition. The carve-out holds only where "access to the software, its source code and its
updates is not conditional on making a donation." Both OSS-23 and SEC-78 exist precisely to
make that a testable requirement. Neither is promoted. So the PRD asserts the conclusion
("donations keep the project outside CRA scope") while omitting the requirement that keeps it
true, and nothing stops Stage 3 from shipping "sponsors get TestFlight builds first" — which
the guidance names as the exact pattern that flips the analysis.

**What would fix it:** (a) Promote OSS-23 as a Must in §6.7, with its acceptance criterion
("feature-flag audit at each release: no sponsor-gated capability exists"). (b) Move C-11 to
§10 as a risk with a stated review trigger, or keep it in §8 with the words "non-binding
Commission guidance, adopted 27 July 2026" in the evidence cell. (c) Reopen D-08 to cover
named sponsorship separately from charging, since the constraint you cited does not exclude
it, and MKT-18's underlying argument — that visible funding answers the abandonment objection
that RK-1 rates Critical — is not answered by "free plus donations."

---

### AR-F-13 — §7 fails the standard the PRD's own QA requirement sets

**Severity: Major**

**Claim under attack:**
> Reference device: **iPhone 13** (chosen as a realistic floor for the audience, not a
> flattering one).
> R-71 | Delta export of 10,000 samples | < 5 s wall clock
> R-74 | Cold start to interactive | < 1.5 s

**Why it fails:** Four problems, all of which are the PRD softening the architect without
saying so.

*The floor is not the floor.* The architect defined REF-PHONE-B as iPhone 11 — "**the floor**:
oldest device iOS 26 supports. All ceilings must hold here." The PRD calls iPhone 13 "a
realistic floor... not a flattering one" while it is precisely the more flattering of the two
available choices, and D-05 sets the minimum OS at iOS 26, which supports iPhone 11.

*R-71 reinstates a number the architect refused to sign.* His NFR-07 is "≤ 8 s (REF-PHONE-A);
≤ 15 s (REF-PHONE-B)", with the parenthetical: "**(The brief's illustrative '<5 s on iPhone
13' is optimistic; I would not sign up to it without NFR-03 evidence.)**" The PRD restores the
brief's number, drops both device tiers, and does not record the override in §12. RK-2
acknowledges the throughput assumption is unvalidated but not that the target was contested.

*The NFR he said mattered most is gone.* NFR-02 — headless background launch to first
HealthKit query, ≤ 400 ms — carries his note: "**This NFR is more important than NFR-01**",
because the `BGAppRefreshTask` budget is ~30 s and spending 8 s on dependency-graph
construction burns 27% of it before any work happens. The PRD promotes NFR-01 (cold start,
loosened from p90 ≤ 1,200 ms to < 1.5 s with the percentile dropped) and drops NFR-02.

*There is no battery NFR at all.* NFR-10 (≤ 1.0% per 24 h at steady state) and NFR-11 (≤ 12%
for a full backfill, and "**must not be initiated from a system-scheduled background task**")
are both absent. For an app whose value proposition is running unattended in the background,
battery is the most likely uninstall reason and the most likely one-star review, and it is
unbudgeted.

Finally, §7 does not meet QA-23, which the PRD promotes nowhere but which states the house
rule: "Every performance NFR must be expressed as (workload, device, OS version, metric,
threshold, percentile)... **NFRs without a mapped test are rejected at Stage 2 review.**" None
of R-71 to R-75 carries a percentile or an OS version. R-75 ("< 5% of the wake budget") has no
defined workload and loosens OBS-32's ≤ 2% while changing the denominator.

**What would fix it:** Adopt the architect's two-tier reference devices verbatim. Restore
NFR-02, NFR-10 and NFR-11. Restate R-71 as his ≤ 8 s / ≤ 15 s pending R-70, or record the
override in §12 with a reason. Re-express every NFR in QA-23's six-tuple and promote QA-23
itself into §6.6 as the gate.

---

### AR-F-14 — The watchdog, the PRD's signature mechanism, depends on a permission the user can deny

**Severity: Major**

**Claim under attack:**
> R-13 | A staleness watchdog, independent of the export pipeline, notifies the user when
> time-since-last-success exceeds a threshold. **Implemented as a local notification
> rescheduled on every success**, so **silence itself becomes an event** | Must | Soak test
> with export deliberately broken; the notification fires within the window even with zero
> background execution granted

**Why it fails:** The mechanism is clever and the zero-background-execution claim holds —
scheduled local notifications are delivered by the system regardless of the app's background
budget, so I could not falsify that part. Two other things fail.

*Notification permission.* If the user denies notification permission, the Must silently
degrades to nothing, and the PRD has no fallback requirement. OBS-12 specified the escalation
chain — "in-app indicator → local notification (if permitted) → widget / watch complication
showing last-success age in plain language. **Escalation degrades gracefully when notification
permission is absent**" — with an explicit test: "automated test that the indicator appears
with notifications denied." The PRD promotes only the middle rung. The widget that would be
the fallback is a **Should** in §5.1. So the product's answer to silent failure is itself
silently disableable, and R-13's acceptance criterion does not test the denied case.

*The threshold has no source.* R-13 says "exceeds a threshold"; PC-2 promises "freshness
targets ('data at your destination is usually less than N hours old')"; G-3 says "within the
stated freshness window." N is never stated, no requirement sets it, and — critically —
HK-32, the Must that would let you set it honestly, is not promoted. HK-32 requires empirically
determining which types iOS silently caps at hourly, whether background delivery survives
Background App Refresh being off, and the actual observer-query wake duration, on the grounds
that "**the product's honesty depends on knowing them**." The architect's NFR-08 — freshness
as a distribution conditioned on device unlock — is also absent.

So the PRD replaced the scheduler it correctly rejected with a freshness promise, and then
specified neither the promise nor the measurement that would justify it.

**What would fix it:** Promote OBS-12's full escalation chain into R-13, add "with
notifications denied, the in-app indicator and widget still surface staleness" to its
acceptance criterion, and promote the status widget from Should to Must. Promote HK-32 as a
Must alongside R-70 — it is the same kind of pre-Stage-2 measurement spike and it is cheaper.
Add an NFR for freshness in the architect's conditional form.

---

### AR-F-15 — Musts whose acceptance criteria depend on Shoulds and on unrequired test infrastructure

**Severity: Major**

**Claim under attack:**
> R-16 | "Time since last successful export" is consumable by the user's own monitoring... |
> **Must** | An alert fires in **both Home Assistant and Grafana** when exports stop past a
> user-set threshold, **using only shipped artifacts**

**Why it fails:** The shipped artifacts in question are R-68 (reference receiver plus published
Grafana dashboard) and R-69 (HACS listing) — both **Should**. A Must cannot be verified by
exercising two Shoulds; if scope slips and they are cut, R-16 becomes untestable while
remaining a Must.

The same pattern recurs across §6, and in each case the QA lead had specified the missing
infrastructure as a Must and it was not promoted:

- **Home Assistant is a Must destination** (§5.2) and P1's primary path, but QA-12 —
  "verified against a real Home Assistant instance at two pinned versions... asserting entity
  creation and the read-back values of `unit_of_measurement`, `device_class`, `state_class`" —
  is not promoted. Her rationale is directly on the wedge: "**HA statistics silently fail
  without `state_class`; only a real instance reveals this.**" A silent failure in the primary
  persona's primary destination, in the product built to eliminate silent failure.
- **MQTT** (Should, D-04) drops QA-11's requirement to test against a real broker.
- **G-1 and G-3** depend on QA-34 (real-device release gate) and QA-35 (21-day soak), neither
  promoted — see AR-F-11.
- **R-15's** diagnostic-bundle criterion ("a maintainer diagnoses a seeded failure from the
  bundle alone") drops OBS-08's requirement that the bundle's full contents be rendered for the
  user *before* any share affordance is reachable. That preview is what makes the consent real
  and turns users into redaction-bug detectors; without it R-15 is a share sheet.

**What would fix it:** Promote QA-11, QA-12, QA-34 and QA-35 into §6.6, which is explicitly
the section for "architectural constraints that must land in Stage 2 or the entire test
strategy collapses into manual testing." Either raise R-68/R-69 to Must or restate R-16's
criterion so it does not depend on them. Add OBS-08's preview clause to R-15.

---

### AR-F-16 — DSA trader status, 5.1.1(ix), and the legal-budget question are all missing

**Severity: Major**

**Claim under attack:** the absence of OSS-24 and HK-33 from §6/§8/§11, and D-03's framing.

**Why it fails:** The PRD correctly identifies PC-6 (medical-device declaration) as a
launch-blocking compliance task and promotes it as R-65. There is a second one of exactly the
same character that it does not mention at all.

OSS-24 (Must): "DSA trader status declared in App Store Connect before first submission, with
a decision recorded on trader vs non-trader and on P.O. Box vs home address." Mandatory since
17 February 2025; without it the app is removed from the EU App Store. And it is not
paperwork — Apple publishes the declared address, phone number and email on the product page
in all 27 EU territories. For a solo maintainer of a health app that is a personal-safety
decision, which is why the governance lead flagged it and why P.O. Box eligibility mattered
enough to research. It is nowhere in the PRD.

Second omission: D-03 discusses individual-vs-organisation enrolment purely in terms of
signing identities and CRA steward obligations. It does not mention Guideline **5.1.1(ix)**,
which the HealthKit expert raised (HK-33) and called "the one I would expect an unlucky
reviewer to reach for": apps providing services in highly regulated fields "should be submitted
by a **legal entity** that provides the services, and not by an individual developer." His own
reading is that it should not bite an export utility — I agree — but the downside is
account-level, it is a third input to a decision the PRD calls irreversible-ish, and the owner
is being asked to decide without it.

Third: the OSS governance lead's Question 5 ("Is there a legal budget at all?") and OSS-25
(legal opinion required before charging, adopting a GPL-family licence, or incorporating) are
both dropped, and the security engineer asked the same question independently. Two specialists
asking the same question of the PM and getting no answer is a synthesis failure, not a
prioritisation call. It also matters for D-08: the governance lead's fallback advice was that
"MPL-2.0, DCO, free forever, donations outside the app... is what I have recommended, and which
is **specifically chosen to be defensible without a lawyer**" — which is a much better argument
for D-08 than the CRA one the PM actually used (AR-F-12).

**What would fix it:** Promote OSS-24 as a Must in §6.7 with the address decision surfaced as
a D-item, since it is a personal-safety choice the owner must make. Add 5.1.1(ix) to D-03's
decision text. Add "Is there a legal budget?" as D-12.

---

### AR-F-17 — The iCloud non-goal asserts a prohibition the PRD's own specialists called ambiguous, and contradicts §5.2

**Severity: Minor**

**Claim under attack:**
> | iCloud Drive destination | **Prohibited by 5.1.3(ii)** (PC-3) | HK, SEC-, MKT |

**Why it fails:** The guideline text is exactly as quoted — I verified it — and I agree with
the outcome. The reasoning is the problem, and it produces an internal contradiction.

Both specialists who examined it said the specific question was ambiguous, not settled. The
HealthKit expert (HK-22): "Whether a *user-initiated save into their own iCloud Drive via the
document picker* counts is **genuinely ambiguous** — the reference product ships iCloud Drive
export, which is evidence Apple has tolerated it, but that is not a rule. **PM decision
required.**" The architect: "I would not bet a release on our reading of that line," and his
recommendation was the one the PRD actually adopted — build no iCloud destination, build one
local-file destination through the system document picker, and if the user picks an
iCloud-backed folder that is the user's decision made in Apple's own UI.

Which means §5.2's Must destination *can* write to iCloud Drive, by design, while the non-goals
table says iCloud Drive is prohibited. Both are in the PRD. A Stage 2 engineer reading the
non-goal will reasonably add a filter that blocks iCloud-backed folders in the picker, which
is a worse product than the architect designed and is not what anyone asked for.

Two shipping apps contradict the flat reading in practice: Health Auto Export, and `health-md`,
which lists "Files, iCloud Drive, Obsidian, or a nearby Mac" as destinations on a live App
Store listing.

**What would fix it:** Restate the non-goal as "A bespoke iCloud Drive destination or CloudKit
sync of health data — 5.1.3(ii) forbids the app storing PHI in iCloud. The local-file
destination writes wherever the user points the system document picker, including an
iCloud-backed folder; that choice is the user's, made in Apple's UI, and we ship no iCloud
code." Note that D-05's "settings-only sync" question is separately answerable: the architect
observed that 5.1.3(ii) also forecloses CloudKit sync of export journals that contain sample
values.

---

### AR-F-18 — D-01's "only mainstream licence" is false, and its precedent argues for D-02's opposite

**Severity: Minor**

**Claim under attack:**
> **D-01** ... **MPL is the only mainstream licence that is simultaneously App-Store-clean,
> carries an express patent grant, and forces a cloning competitor to publish changes to our
> files** | **Very hard.** VLC took over a year to relicense

**Why it fails:** Two factual problems and one that undercuts the D-01/D-02 pairing.

*"Only" is wrong.* **EPL-2.0** satisfies all three: file-level copyleft, an express patent
grant in §2(b), and no "no further restrictions" clause to collide with Apple's minimum EULA
terms. CDDL-1.0 is a third, though less mainstream. I would still choose MPL-2.0 here —
EPL-2.0 adds a commercial-contributor indemnity that is a genuine reason to avoid it, and MPL
is far better recognised in the Swift ecosystem — but that is the argument the PRD should
make. "Only" is doing rhetorical work to close down a decision the PRD itself calls "very
hard" to reverse, and it is not true.

*The anti-clone property is weaker than stated.* MPL's copyleft is per-file. A cloning
competitor takes the codebase, adds all of their differentiation in new files as a Larger Work
under §3.3, ships a closed paid binary, and publishes nothing they did not have to modify.
"Forces a cloning competitor to publish changes to our files" is literally true and
strategically thin, and the brief specifically asked whether a competitor could ship a closed
clone.

*The VLC precedent argues against D-02.* VLC for iOS is not MPL — its `COPYING` reads "This
software is **bi-licensed under the GPLv2 (or later) and the MPLv2**", and the very next line
is: "**Any commit to this repository implicitely allows VideoLAN to relicense this software to
any OSI-approved license, without prior consent.**"
(<https://github.com/videolan/vlc-ios/blob/master/COPYING>) That is a contributor relicensing
grant — functionally the thing a CLA buys. So the precedent the PRD cites for D-01 pairs its
licence choice with the *opposite* of D-02's DCO recommendation. That does not make DCO wrong;
the governance lead's argument for it (a CLA on a solo project signals commercial intent) is
good and I would probably make the same call. But the PRD should not cite VLC as support for
the pair.

**What would fix it:** Replace "the only mainstream licence" with "MPL-2.0 and EPL-2.0 both
satisfy these three; MPL-2.0 is preferred for ecosystem familiarity and because EPL-2.0 adds an
uncapped commercial-contributor indemnity." State the Larger Work limitation on the anti-clone
property honestly. Drop VLC from D-01's rationale or note what its contribution terms actually
are.

---

### AR-F-19 — D-05's iOS 26 floor is asserted, not evidenced, against two competitors on iOS 17

**Severity: Minor**

**Claim under attack:**
> **D-05** | **Minimum OS** | **iOS 26.0.** One OS version to test is a large QA saving for a
> tiny team, **and this audience updates.** The cost is reach, in an already small market

**Why it fails:** "This audience updates" is the load-bearing clause and it has no evidence
behind it. No specialist made the claim. Meanwhile both products the PRD names as competitors
sit two years lower: Health Auto Export's App Store metadata lists `minimumOsVersion` 17.0, as
does `health.md`. In a market the PRD itself sizes at "low thousands," choosing to be
installable on strictly fewer devices than either incumbent is a real cost, asserted away in
half a sentence.

The QA saving is genuine. But the *technical* driver is thin: the only iOS-26-only API in
play is `BGContinuedProcessingTask`, which underpins AR-17 / R-06 — and R-06 is a **Should**.
The architect flagged the trade-off as an open question rather than a settled matter and noted
the calculus shifts again if iOS 27 ships during the development window, which on Apple's
cadence it will.

**What would fix it:** Either supply evidence for the adoption claim, or restate the rationale
honestly as "we are trading reach for a single-version test matrix because we cannot afford
two full-history export paths," and record the reach cost in RK-8 (market too small to attract
contributors), which it directly worsens. Note that this decision is only "easy to lower
later" if Stage 2 does not build iOS-26-only assumptions throughout, which it will.

---

### AR-F-20 — Process integrity: uneven traceability, an over-claimed local verification, and an unused finding

**Severity: Minor**

**Claim under attack:**
> **Local verification note:** I counted the iOS 26.5 SDK headers directly — **121**
> `HKQuantityTypeIdentifier`, 70 `HKCategoryTypeIdentifier`, 6 `HKCharacteristicTypeIdentifier`
> constants... **This is consistent with the HealthKit expert's ~219**

and §13's traceability row: `| Principal Software Architect | contributions/03-... | AR- |`

**Why it fails:** Three small things that together say something about the filter.

*The count is not consistent; it differs.* The HealthKit expert counted **120** quantity
identifiers from the same headers. The PM counted 121, reported it as corroboration, and did
not note the discrepancy. One of the two is wrong — most likely a deprecated or
newly-added-in-a-point-release identifier — and the honest form of a local verification is to
say which and why. More importantly, the verification does not support the conclusion drawn
from it. The count supports "the SDK exposes more than 150 identifiers." It does not support
"It remains a bad marketing claim because most types are empty for most users" — that is the
expert's separate argument, and it is a good one, but it is not what was verified.

By contrast, PC-1's verification is exemplary: a runtime probe answering exactly the question
asked. Two of the three "[verified locally]" marks are the same probe (PC-1 and C-01), so the
document has one strong local verification and one weak one, not three.

*The architect's requirement count is the only one missing.* Every other row in §13 carries a
count — 16 MA, 35 HK, 78 SEC, 33 OBS, 50 UX, 21 MKT, 39 QA, 26 OSS. The architect's cell reads
just `AR-`. He filed 32 requirements and 20 NFRs across 53 sources, and he is also the
specialist whose requirements were most heavily dropped (AR-04, AR-08, AR-09, AR-10, AR-11,
AR-12, AR-15, AR-30, and NFR-02/10/11 — see AR-F-07 through AR-F-13). The missing count is
almost certainly an oversight rather than a concealment, but it is the one that would have made
the filter visible.

*§12 mischaracterises the dissent.* "Governance did the primary research and was the only party
to check the VLC history rather than repeat it." The architect cited the FSF's own 2010
enforcement statements and the VLC removal directly (his sources 42–44) and reached the
opposite conclusion. He was wrong about the conclusion; he was not repeating folklore, and
saying he was makes the override look better than it is.

*One finding was verified but not used.* PC-5's claim that `health-md` "already does
iPhone→Mac transfer over Multipeer Connectivity" appears in no contribution — the specialists
discussed Multipeer only in the context of *our* Mac companion. I checked, and the claim is
**true**: `health-md`'s README lists "**Sync:** encrypted Multipeer/Manual IP + bounded
checksum-validated transfer." So the PM did independent research here and simply did not mark
or cite it. What is odd is what the PRD then failed to take from the same source. `health-md`
is **AGPL-3.0, shipping on the App Store today** — the single strongest piece of live evidence
for PC-7, in the exact product category, and the PRD instead cites Ice Cubes and Blink. And
its App Store listing states it "automatically collects limited pseudonymous product events
using a random app-install ID," and it uses StoreKit 2. The nearest OSS competitor charges and
phones home. That is direct, checkable support for the wedge the PRD is arguing for, and it is
sitting in a footnote the PM already had open.

**What would fix it:** Fix the count or explain the delta. Add the architect's requirement
count to §13, and add a one-line note in §13 stating how many requirements from each specialist
were promoted, so the filter is auditable. Reword the §12 licence row. Cite `health-md`'s
licence and telemetry posture in PC-5 and PC-7 — they strengthen both.

---

## Claims I attempted to falsify and could not

These held up under independent checking. Some of them held up better than the specialists
who supplied them.

1. **PC-1 / C-01 — HealthKit is unreadable on macOS.** Apple's documentation is explicit that
   the framework is present on macOS 13+ but `isHealthDataAvailable()` returns `false`, and
   the PM's runtime probe on macOS 26.6 is exactly the right verification for exactly the right
   question. Three specialists reached this independently. Solid, and the repositioning of
   macOS that follows from it is correct.
2. **PC-6 / C-08 — the medical-device declaration.** Verified against Apple's own developer
   news post of 26 March 2026, which matches the PRD's characterisation precisely: required for
   new apps whose primary or secondary category is Health & Fitness or Medical, in the EEA, UK
   and US, immediately; existing apps by early 2027, after which updates are blocked. The PRD's
   framing as launch-blocking is right, and R-65 is well-formed.
   <https://developer.apple.com/news/?id=nyqbfz1y>
3. **PC-3 / C-05 — 5.1.3(ii).** The guideline text is exactly as quoted: apps "must not write
   false or inaccurate data into HealthKit... and may not store personal health information in
   iCloud." (My objection at AR-F-17 is to the inference, not the text.)
4. **"389 US ratings after roughly ten years."** Verified directly against the App Store
   lookup API: `userRatingCount` 389, average 4.33, first released 2016-05-21. Notably the
   market analyst's contribution says 375; **the PM's number is the correct one**, and the
   sobriety of §1 about market size is well-founded rather than performative.
5. **C-10 — individual enrolment cannot share signing identities.** Verified against Apple's
   Developer Account Help ("Certificates, Identifiers & Profiles is only available to Account
   Holders and members of an organization's team") and a DTS forum post restating it. The
   constraint is real; my finding at AR-F-02 is that the PRD does not act on it, not that it is
   wrong.
6. **C-11's factual core, on the point the specialist doubted.** The OSS governance lead
   flagged C(2026) 5252 as a draft he could not confirm was adopted. It was adopted, on
   27 July 2026, and the donations analysis in ¶61 is the final text. Here the PM's flat
   statement is **more** accurate than the contribution it synthesises. My objection at AR-F-12
   is to its use as a non-negotiable constraint and to the missing condition, not to the law.
7. **PC-7 — copyleft apps ship on the App Store.** Ice Cubes is AGPL-3.0 and Blink and
   Passepartout are GPL-3.0, all listed; `health-md` is a fourth, AGPL-3.0, in this exact
   category. The 2011 VLC removal did follow a copyright-holder complaint rather than an Apple
   licence objection, and VideoLAN's own account confirms the app was pulled at their
   instigation. PC-7's reframing from "Apple says no" to "any contributor holds a veto" is
   correct and is the most valuable single correction in §2.
8. **R-13's zero-background-execution claim.** I went looking for a hole here and did not find
   one. A `UNUserNotificationCenter` local notification scheduled for T+N is delivered by the
   system independently of the app's background execution budget, and cancel-and-reschedule on
   each success is a sound construction. My objections at AR-F-14 are the notification-permission
   gap and the undefined threshold, not the mechanism, which is genuinely good design.
9. **The `health-md` Multipeer claim in PC-5.** Uncited, but true — see AR-F-20.
10. **PC-4 — the localhost-listener argument.** I could not independently re-verify the Apple
    DTS quotation on background sockets within this review, but the security engineer's
    distinctive argument — that on iOS network access is not permission-gated while HealthKit
    is, so a localhost listener hands every other app on the device an unprompted read of the
    health record — is sound on its own terms and I found nothing to counter it. Making it a
    permanent Won't rather than a v1 Won't is the right call.
11. **C-09 — FairPlay re-signing defeating binary reproducibility.** I could not verify this
    either way in this session and am flagging it as unchecked rather than endorsed. The
    conclusion the PRD draws from it (claim auditable source and verifiable provenance, not a
    reproducible binary) is appropriately conservative regardless.
12. **The overall repositioning.** I was prepared to conclude "do not build this," and I do not.
    The failure mode the PRD identifies — exports that stop, or report success while delivering
    nothing, and nobody notices for weeks — is real, is the incumbent's most-complained-about
    behaviour, and is not something a competitor closes in one release, because closing it
    means admitting in the UI that the platform is unreliable. The write-time-watermark finding
    behind R-01 is a genuine correctness bug in the incumbent with a concrete user-visible
    consequence (truncated sleep). That is a defensible wedge. It is undermined here by
    under-specification (AR-F-07 through AR-F-11), not by being wrong.

---

## Sources

Verified independently during this review; all accessed 2 September 2026.

1. App Store Review Guidelines §5.1.3 — <https://developer.apple.com/app-store/review/guidelines/>
2. "Update on regulated medical device apps in the European Economic Area, United Kingdom, and United States", Apple Developer News, 26 March 2026 — <https://developer.apple.com/news/?id=nyqbfz1y>
3. MacRumors coverage of the same, 26 March 2026 — <https://www.macrumors.com/2026/03/26/app-store-medical-device-status/>
4. Apple Platform Security, "Data Protection classes" — Complete Protection, class key discarded ~10 s after lock — <https://support.apple.com/guide/security/data-protection-classes-secb010e978a/web>
5. Apple iOS Security white paper — HealthKit database in Complete Protection; operational database in Protected Until First User Authentication — <https://www.apple.com/hk/en/privacy/docs/iOS_Security_Guide.pdf>
6. Apple Developer Account Help, "Apple Developer Program Roles" — Certificates, Identifiers & Profiles restricted to organization teams — <https://developer.apple.com/help/account/access/roles>
7. Apple DTS (Quinn), Apple Developer Forums — individual teams and Certificates, Identifiers & Profiles — <https://developer.apple.com/forums/topics/developer-tools-and-services/apple-developer-program>
8. Commission guidance C(2026) 5252 final, 27 July 2026, §3.2.4 and Examples 20–23 (donations, conditioned access) — <https://kunnus.tech/downloads/eu-cra-commission-guidance-c2026-5252.pdf>
9. Thomas Murray, "EU Cyber Resilience Act: Commission Publishes Implementation Guidance" — adopted 27 July 2026, substantive text final, **explicitly non-binding** — <https://cyber.thomasmurray.com/insights/eu-cyber-resilience-act-commission-publishes-implementation-guidance>
10. Heck, "The final CRA Guidance is here" — paragraph-level comparison of draft against final on donations — <https://www.linkedin.com/pulse/final-cra-guidance-here-what-actually-new-already-law-maximilian-heck-4dmie>
11. `videolan/vlc-ios` `COPYING` — bi-licensed GPLv2+/MPLv2 plus the contributor relicensing grant — <https://github.com/videolan/vlc-ios/blob/master/COPYING>
12. VideoLAN, "VLC for iOS 2.0 released" — "The MPLv2 is applicable for distribution on the App Store" — <https://www.videolan.org/vlc/download-ios.html>
13. The Next Web, July 2013, on the 2011 removal and the bi-licensing that resolved it — <https://thenextweb.com/news/vlc-for-ios-will-return-to-the-app-store-on-july-19-full-re-write-open-source-licensed-under-mplv2-and-gplv2>
14. Finite State, "Open Source License Types" — MPL-2.0 §3.3 Larger Work; EPL-2.0 file-level copyleft with patent grant at §2(b) — <https://finitestate.io/blog/the-complete-guide-to-open-source-licenses>
15. "Eclipse Public License 2.0 explained" — §2(b) patent grant, Modified Works file scope, §4 commercial-contributor indemnity — <https://faun.dev/toolbox/license/epl-2-0/>
16. `CodyBontecou/health-md` — AGPL-3.0, Swift, App Store, "Sync: encrypted Multipeer/Manual IP", minimum iOS 17.0 — <https://github.com/CodyBontecou/health-md>
17. Health.md on the App Store — iCloud Drive destination; pseudonymous product events with a random app-install ID; StoreKit 2 — <https://apps.apple.com/us/app/health-md/id6757763969>
18. Apple iTunes lookup API, id 1115567069 (Health Auto Export) — `userRatingCount` 389, `averageUserRating` 4.33, `releaseDate` 2016-05-21, `minimumOsVersion` 17.0 — <https://itunes.apple.com/lookup?id=1115567069&country=us>
19. Apple iTunes lookup API, id 6757763969 (Health.md) — `minimumOsVersion` 17.0 — <https://itunes.apple.com/lookup?id=6757763969&country=us>
