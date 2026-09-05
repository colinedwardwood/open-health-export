# Adversarial Review — Stage 2 System Design

**Reviewer:** Adversarial Reviewer (Stage 2)
**Date:** 2026-09-03
**Artifact under review:** `docs/02-design/00-system-design.md` (DRAFT v0.1), against `docs/01-prd/PRD.md` v1.0 (APPROVED)
**Also read:** all nine specialist designs (executive summaries in full; deep reads in the areas listed below), `docs/01-prd/reviews/01-adversarial-review.md`, `docs/01-prd/reviews/01-disposition.md`

**Method.** I read `00-system-design.md` line by line, then read each specialist's executive summary, findings table, "requirements I cannot design/secure as written" section, and open-questions section. I then deep-read: `01`§7.3 and §11 (persistence and the seven amendments), `02`§deletion-dating and open questions, `03`§receipt semantics and the HAE profile, `04`§requirements-I-cannot-secure and open questions, `05`§Q10–Q12 and the outcome taxonomy, `06`§R-40/R-41 and the status model, `07`§2.1–2.3 (the cross-audit), `08`§acknowledgement boundaries and §NFR design. Nine factual claims were checked against primary sources; URLs are in §Sources. Where I could not verify, I say so.

---

## Verdict

**REJECT.**

Not because the engineering is bad. The engineering is, in places, the best I have seen at this stage: the anchors-versus-coverage inversion (§1.3), the census digest, the structural write-ahead cursor, and the `CompanionWire`/`SinkMQTTPackage` treatment of R-80 are all genuinely strong, and I could not falsify them. I have populated §"Claims I attempted to falsify and could not" at length and it is not a courtesy.

I am rejecting the **synthesis**, which is the artifact I was asked to review. `00-system-design.md` is 304 lines standing in front of 12,900, and its job is to be the place where conflicts are resolved and requirement changes are carried forward. It does not do that job reliably. Specifically:

- The architect filed **seven** requirements that "cannot be built as written" with proposed amendments. The security engineer filed **six** he "cannot secure as written" with proposed restatements, and asked the PM a direct question — "Do you accept the restatements of R-44, R-41, R-40, R-32 and R-30?" — which the synthesis does not answer. **Of those thirteen, zero appear in §5's amendment table.** All six of §5's amendments come from observability, reliability and QA.
- The string `R-41` appears **zero times** in `00-system-design.md`. So does `R-32`, `R-30`, `TA-03`, `TA-07`, `Q10`, `Q11` and `Local Network`. R-40 and R-41 are the anti-coercion controls that the PRD declares "not negotiable in Stage 2" (§6.3), and the security engineer says one of them is defeated by a feature of iOS 18 operated by exactly our threat actor.
- §4.1's central claim about the QA lead's TA-01 is wrong on every particular, and the exit criterion "[x] TA-01 verified and downgraded" is therefore false.

This is the same failure mode the PRD itself apologises for at Stage 1 — "v0.1 promoted 8 of the security engineer's 78 requirements under a blanket claim that the rest were Stage 2 design constraints. That claim was false for five of them" (PRD §6.3) — and it has recurred at Stage 2 with the same specialist and, in R-40/R-41's case, the same requirements. The Stage 1 reviewer had to force the anti-coercion controls into the PRD. They have now been dropped out of the design synthesis.

The design is close. The document that certifies it is not, and the certification is what the owner is being asked to sign.

### Conditions for approval

1. **Answer the security engineer's open question 6.** Carry restatements of R-44, R-41, R-40, R-32 and R-30 into §5 as ratifiable amendments, or reject each with reasons. (SR-F-02)
2. **Resolve the anti-coercion collapse** (SR-F-01). Run the security engineer's Q7(a) spike, restate R-41 as a claim about our binary plus a documented recovery path, and stop presenting the widget as R-23's unconditional degraded fallback until the spike says it survives.
3. **Redo §4.1.** TA-01 is not the finding the PM describes. Disposition the real TA-01, TA-03, TA-04, TA-07 and TA-09, and withdraw the "QA-38 residue" claim or reconcile it with `07`§2.1. (SR-F-03)
4. **Adjudicate the webhook acknowledgement contradiction** between `03` and `08`, and design the freshness-clock consequence, before O-1…O-8 go to the owner. (SR-F-04)
5. **Settle Q10** (journal database Data Protection class). It is settleable today from Apple's published documentation and the answer contradicts ADR-0005. (SR-F-05)
6. **Re-argue or withdraw O-2's GRDB half** on the correct facts about GRDB's Linux support, and re-derive R-73's launch budget with the dependency present. (SR-F-06, SR-F-07)
7. **Add an NFR reference device on iOS 18** (or raise the floor), because D-05's floor reaches hardware iOS 26 does not support and no NFR in the design covers it. (SR-F-08)
8. **Carry Q11's escalation-threshold ownership**, HK's deletion-index owner decision, and the architect's R-80 exception list into §4/§7. (SR-F-10, SR-F-11, SR-F-16)
9. **Re-baseline, or state plainly that you cannot.** §6 re-states ~87 EW after this document added scope and while the two spikes the PRD required for re-baselining have not run. (SR-F-09, SR-F-13)

I would not block on SR-F-14 (the HAE profile) — it is a defensible product judgement I disagree with, and I say what I would decide instead.

---

## The three things most likely to kill this project

**1. The anti-coercion story does not survive contact with iOS 18, and nobody is looking at it.**
The abuse case is the one risk in this project with an irreversible human cost (RK-11, T-24). The design's answer is a chain: in-app indicator → notification → widget. A coercer with physical access and the passcode — the exact actor in the threat model — can, in four taps and with no in-app control involved, hide the app: it leaves the Home Screen, its notification content is stripped, and (per multiple secondary reports, which is precisely why the security engineer asked for a spike) its widgets are removed. That is all three rungs of R-23, plus R-40, plus R-41's fourth invariant, defeated by one OS feature. The security engineer flagged it and asked for a one-day spike. The synthesis dropped both the finding and the spike. In eighteen months this surfaces as a support thread from someone who was being surveilled, and the project's answer will be that it was in a Stage 2 document nobody carried forward.

**2. The synthesis is not a reliable record, and the milestone plan already depends on the parts that went missing.**
This is the structural risk, and it is worse than any single dropped item. The architect's M6 exit criteria — the gate at which "THE WEDGE IS INTERNALLY SHIPPABLE" — literally read "**R-44** timed purge (as amended, §11)" and "**R-30** ledger entry for every run, immutable". The first cites an amendment the PM did not ratify; the second asserts a property the security engineer refuses to let the project claim. So the plan's most important gate cannot be met against the PRD as it actually stands. A synthesis that drops thirteen amendments while its own §8 checkbox says "Conflicts resolved and recorded" does not degrade gracefully: Stage 3 will implement whichever document it read last.

**3. Two documents flatly contradict each other about whether the primary persona's destination can ever report success, and the synthesis picked the side that breaks the watchdog.**
`03` says a run without a receipt body is `unknownAck`, "never `success`". `08` says of the Home Assistant preset, "Ongoing runs report `success` on 2xx." §4.3 adopts `03`. Under `05`, only `success` or `success_nothing_due` re-arms the pre-scheduled watchdog notification. Therefore, as synthesised, a healthy Home Assistant webhook destination — P1's primary destination, P1 being "the only segment with a durable acquisition channel" (PRD §4) — never advances the freshness clock and escalates forever. The product built to eliminate silent failure ships with a permanent false alarm on its most common configuration. This is a two-line fix now and a reputational fact later.

---

## Findings

### SR-F-01 — The anti-coercion escalation chain is defeated by iOS 18's own app-hiding feature, and the synthesis does not mention it

**Severity: Blocker**

**Claim under attack.** `00-system-design.md` contains no reference to R-41 at all. Its §5 amendment table does not include R-40 or R-41, and §7's owner decisions do not include the spike the security engineer said was required. Meanwhile `06-interaction-design.md` §R-41 invariant 4 asserts:

> "**No disguise.** No alternate app icons (`CFBundleAlternateIcons` is absent from the build), no configurable app name, no 'discreet mode', no Focus-filter that hides the app, no setting that removes it from search. **The app looks like itself on the Home Screen forever.**"

And `04-security-design.md` §Requirements I cannot secure as written, item 2:

> "**R-41 — 'can never be hidden'.** Defeated by iOS 18's own Hide-and-Require-Face-ID feature, operated by exactly our threat actor, in four taps."

with open question 7(a):

> "Does the status widget survive the app being hidden — **this determines whether the anti-coercion escalation chain has four rungs or one** … Both are cheap; both change a design if the answer is unfavourable; **neither has an owner.**"

**Why it fails.** The security engineer is right, and the consequence is larger than he claimed.

Apple's own Personal Safety User Guide documents the feature: "Hiding an app: The app is locked as described above; it also **disappears from your Home Screen** and moves to the Hidden folder at the bottom of App Library," where locking means "Information inside a locked app won't appear in some locations on your iPhone—for example, in **notification previews**, search, Siri suggestions, or your call history." Apps installed by the user (i.e. ours) can be hidden; only Apple's bundled apps cannot. <https://support.apple.com/guide/personal-safety/lock-or-hide-apps-on-your-iphone-ipsd0be4c185/web>

Take the primary source alone and R-40 is already broken as designed. `06` specifies the destination-change notification and says: "It carries the hostname, **because the hostname is the entire point**." If notification previews are stripped, the hostname is exactly what does not arrive. R-40's whole mechanism is a notification whose value is its content.

Multiple independent secondary reports additionally state that hiding removes the app's Home Screen and Lock Screen widgets and suppresses its notifications entirely — e.g. "If you've added widgets for that app to your Home Screen or Lock Screen, they'll be removed" (<https://www.idownloadblog.com/2024/06/21/how-to-hide-iphone-apps/>) and 9to5Mac's list of suppressed surfaces including Search, Notifications, Spotlight and Siri suggestions (<https://9to5mac.com/2024/09/20/lock-and-hide-apps-on-iphone-how-to/>). I flag these as secondary deliberately: this is the exact question the security engineer's Q7(a) spike exists to settle, and I will not assert it as verified. But note the asymmetry of the bet — if the secondary reports are right, R-23's escalation has **zero** rungs against a coercer, and R-23's PRD acceptance criterion explicitly requires the chain to work "**and again with notifications denied**", where PRD §5.1 names the widget as the reason the widget is a Must rather than a Should.

So three Musts are affected: R-23 (all rungs), R-40 (content stripped), R-41 (invariant 4 is false as written). `06`'s own governing principle — "every rung must be correct without the app ever running again" — was designed against app *death*. It was not designed against app *concealment*, which is the coercion threat model.

This is a design gap, not a synthesis-only gap. But the synthesis is where it should have been caught: one specialist identified it, another wrote an invariant the OS falsifies, and the document whose job is to reconcile them is silent.

**What would fix it.**
1. Run Q7(a) before Stage 2 closes. It is one device, under an hour: hide the app, observe whether the widget persists and renders, and whether a pre-scheduled local notification is delivered and with what content.
2. Restate R-41 per the security engineer: a claim about *our binary* (no in-app concealment affordance, no alternate icons, no subtree authentication), plus an explicit statement that the OS provides concealment we cannot prevent, plus a documented recovery path — Apple's own page names Settings > Apps > Hidden Apps, Screen Time, Battery, and App Store purchase history as places a hidden app remains visible. Ship that path in the README and in `Where your data goes`, and link Apple's Personal Safety guide.
3. Amend `06`'s invariant 4 to strike "forever" and add a fifth surface to the escalation chain that concealment does not reach. The strongest candidate is the one the design already has and has not used this way: R-27's external monitoring signal, plus the R-30 ledger's presence in the Files/Shortcuts surface. If Q7(a) says the widget dies, say so in §5 and stop counting it as R-23's fallback.
4. Add both to §5 as a seventh amendment, and add Q7(a) and Q7(b) to §7 with an owner. The security engineer said neither has one; that is still true.

---

### SR-F-02 — The synthesis dropped all thirteen amendments proposed by the architect and the security engineer, and the milestone plan depends on two of them

**Severity: Blocker**

**Claim under attack.** `00-system-design.md` §5:

> "Stage 2 discovered **six** places where the approved PRD is wrong or unachievable as written. Each needs owner ratification; none changes the product's intent."

and §8: "- [x] Conflicts resolved and recorded (§4)".

**Why it fails.** Stage 2 discovered considerably more than six, and the six carried are not a representative sample.

`01-system-architecture.md` §11 is titled "Requirements I cannot design as written" and opens: "**Seven.** Each with a proposed amendment, offered now because this is the last cheap opportunity." They are R-44 (§11.1, marked *highest severity*), R-84 (§11.2), R-80-vs-R-07 (§11.3), R-91-vs-R-77/R-79 (§11.4), R-83 (§11.5), R-26 (§11.6), and SEC-04's criterion (§11.7).

`04-security-design.md` §Requirements I cannot secure as written opens: "**Six.** Each has a proposed restatement, because flagging a problem without a fix is not a deliverable." They are R-44, R-41, R-40, R-32, R-30, R-50. Its open question 6 asks the PM directly: "**Do you accept the restatements of R-44, R-41, R-40, R-32 and R-30?** They make the document weaker and truer. I would rather lose the sentence than have it be false."

None of the thirteen appears in §5. §5's six are A-1/A-2 (R-21, from observability and reliability), A-3 (R-24, observability), A-4 (R-11/R-75, reliability and architect), A-5 (R-88, QA), A-6 (R-91, QA). Three of the thirteen surface obliquely in §4.3 as *resolved conflicts* rather than as amendments — R-84 as "Determinism property P8", R-83 as "R-83 seam count", R-44 as a consequence of the queue-TTL row — but §4.3 resolutions are not ratifiable by the owner, and R-84's and R-26's *verification criteria* are PRD text that this design changes. R-41, R-32, R-30, R-50, R-26 and §11.3's R-80 exception list are absent entirely.

This is not a bookkeeping complaint, because the plan already leans on the missing pieces. `01-system-architecture.md` §M6 — the gate the PM's §6 calls the point at which the wedge is shippable — reads:

> "**R-30** ledger entry for every run, **immutable**. … **R-41** prohibition recorded and gated at feature review. … **R-44** timed purge (**as amended, §11**)."

So the M6 exit criteria cite an amendment that was never ratified (R-44), assert a property the owning specialist refuses to claim (R-30 "immutable"), and gate a requirement that an OS feature defeats (R-41, per SR-F-01). As the PRD currently stands, M6 cannot be signed off. The PM's §6 nonetheless presents M6 as "the single most important property of the plan".

The pattern is also self-similar to a mistake this project has already made once and documented. PRD §6.3: "v0.1 promoted 8 of the security engineer's 78 requirements under a blanket claim that the rest were Stage 2 design constraints. That claim was false for five of them. The list below is now explicit, **so the filter is auditable rather than trusted**." The Stage 2 filter is neither explicit nor auditable, and it has dropped the same specialist twice.

Distinguishing the three categories the brief asks me to keep separate: that the thirteen were dropped is **wrong** (a factual defect in a decision record). That §5 says "six places" is **wrong**. Whether each individual restatement should be accepted is a **judgement** — and my judgement is that at least R-30, R-32, R-41 and R-44 must be, because in each case the PRD as written asserts something the platform makes false, and the project's entire positioning is that it does not do that.

**What would fix it.** Expand §5 to enumerate all thirteen with an accept/reject and a reason for each; the specialists supplied the proposed wording, so this is an afternoon. Where the PM rejects a restatement, say so explicitly so the specialist's document can be corrected — an unanswered "I cannot secure this as written" is worse than a rejected one. Then re-derive the M6 exit criteria against the ratified set, and re-check §8's "Conflicts resolved and recorded" box afterwards rather than before.

---

### SR-F-03 — §4.1 misidentifies TA-01; the finding it dismisses is live, the blocker it "downgrades" was already withdrawn by its author, and four QA Majors never reached the synthesis

**Severity: Blocker**

**Claim under attack.** `00-system-design.md` §4.1, in full:

> "### 4.1 The QA lead's TA-01 is stale — and I verified it
> The test architecture's headline blocker states 'the security design does not exist', leaving eight verification methods without an owner. This is an artefact of parallel execution: the QA agent read the directory before `04-security-design.md` landed six minutes later.
> I checked the file directly. … **Residue:** `QA-38` (release-binary seam scan) is genuinely unaddressed. TA-01 downgrades from Blocker to Minor with that single item outstanding. The adversarial reviewer should verify this rather than take my word for it."

I verified it. Every load-bearing element is wrong.

**Why it fails.**

*(a) TA-01 is not about the security design.* `07-test-architecture.md` §2.3, the findings table, reads:

> "| **TA-01** | **Local Network permission denial has no enumerated outcome and no distinct copy, so the Mac companion reproduces exactly the ambiguity R-22 and R-60 exist to forbid.** … Denial is *positively detectable* here, unlike HealthKit read denial, so we have no excuse. Needs a distinct member of R-21's enumerated outcome set, distinct copy, and a row in the error-class registry. Without it the product's flagship honesty claim has a hole in its newest destination, and FIX-A07 has nothing to assert against | … | **Major** |"

The QA lead's executive summary names it the same way: "the one most likely to be dismissed as cosmetic is **Local Network permission denial having no enumerated outcome and no distinct copy** (TA-01)". It was dismissed as cosmetic.

*(b) It was never filed as a Blocker, so it cannot be "downgraded from Blocker to Minor."* It is filed **Major**.

*(c) The security-design-absence finding was withdrawn by the QA lead himself, before the PM "verified" anything.* `07`§2.2: "My other two pre-emptive Blockers are cleared elsewhere: **the security design's absence, by its arrival (§2.1)**"; §2.1's audit row for `04-security-design.md` reads "**Exceeds** what I specified on canary verification (§2.2). **Landed last; audited**"; and §2.2 concludes "**All four of my pre-emptive Blockers are withdrawn, and no design-defect Blocker remains.**"

In fairness to the PM, the QA document is internally inconsistent here: its closing confidence note (line 1343) says "`04-security-*.md` was absent, which is finding TA-01" — a stale sentence contradicted by §2.1, §2.2 and §2.3 of the same document. That explains the PM's error; it does not excuse it, because §4.1 claims first-hand verification ("I checked the file directly") of a finding the PM had evidently not read in its filed form.

*(d) The "residue" is contradicted by the QA lead's own audit.* §4.1 says QA-38 is "genuinely unaddressed". `07`§2.1's row for the security design lists what it owns as "R-33, R-36, R-37, R-43, R-51's canary, R-31's four elements, R-30, **QA-38**", and marks the document audited. `07` further records at line 1191 that the release gate includes "the release-binary symbol scan showing no seam or test-only symbols". So the one item §4.1 concedes is the one item the QA lead says is covered.

*(e) The synthesis dropped four QA Majors and one Minor.* Mapping all nine findings against `00-system-design.md`: TA-02 → A-6 (carried). TA-05 → §4.3 + O-6 (carried). TA-06 → A-5 (carried). TA-08 → §4.3 (carried). **TA-01 → misidentified and dismissed. TA-03, TA-04, TA-07 → absent. TA-09 → absent.** TA-03 is the one its author calls "**my sharpest remaining finding**": that R-89's assertion is insufficient in every design that touches it, because asserting `state_class` is *present* does not catch the failure R-89 exists to prevent — silently absent long-term statistics — and the only sufficient assertion is that a `recorder/statistics_during_period` row exists after a statistics cycle. The PRD's own note on R-89 says "A silent failure in the primary persona's primary destination, in the product built to eliminate silent failure, is the most embarrassing bug available to us." It is now unowned.

*(f) The exit criterion is therefore false.* §8: "- [x] TA-01 verified and downgraded".

**What would fix it.** Rewrite §4.1 against the filed findings table. Carry TA-01 as an amendment sibling to A-1 — it needs a new member of R-21's enumerated outcome set for Local Network denial, exactly as `blocked_device_locked` was added, and R-21's set is PRD text so this requires ratification. Disposition TA-03 and TA-04 (they are cheap: generate the R-89 suite from `MetricCatalog` and add the statistics-row assertion, ~12-minute nightly job by the QA lead's own estimate). Disposition TA-07 (bundle window = greater of 30 runs or 24 hours) and TA-09 (P12a/P12b split). Withdraw the QA-38 residue claim. And ask the QA lead to fix line 1343, because it will mislead the next reader too.

---

### SR-F-04 — `03` and `08` contradict each other on whether a webhook can ever report success; §4.3 adopted the side that makes the watchdog alarm forever on the primary persona's destination

**Severity: Blocker**

**Claim under attack.** `00-system-design.md` §4.3:

> "| Receiver receipt body | 03 | **SHOULD, not MUST.** A MUST excludes Home Assistant's own webhook — the primary persona's destination. `unknownAck` is therefore the *normal* outcome for webhook destinations, which the UI must reflect |"

**Why it fails.** The two designs being synthesised say opposite things, and §4.3 does not acknowledge that a conflict exists.

`03-wire-format-spec.md`: "It is a SHOULD rather than a MUST because a plain webhook — including Home Assistant's — cannot produce it… **Where the receipt is absent the run outcome is `unknownAck`, never `success`.**"

`08-reliability-design.md` §Acknowledgement boundaries, Home Assistant preset row: acknowledgement boundary is "Identical to HTTPS: 2xx from `POST /api/states/<entity>` or the webhook"; confirmable is "**Receipt yes**, persistence no"; and the outcome column states "**Ongoing runs report `success` on 2xx.** The statistics gap is closed at configuration time, not at delivery time… This is the one sink where the ack is weaker than it looks and **the mitigation is a gate, not a retry**." The generic HTTPS row is the same: confirmable **Yes**, with `unknown_ack` reserved for "Body fully sent, response never read".

The two documents are answering different questions with the same word. `03` means "we have no receipt enumerating accepted records". `08` means "we received a response in the declared success range". The PM's row collapses them, and picks `03`.

Now trace the consequence through `05-observability-design.md`, which the PM did not: the pre-scheduled watchdog notification is re-armed only on `success` or `success_nothing_due` — "**Nothing else re-arms it.** A `partial`, `unknown_ack`, …". And `06-interaction-design.md`'s status model gives `unknown_ack` "escalates after 2 consecutive".

So as synthesised: a correctly configured, correctly functioning Home Assistant webhook destination produces `unknownAck` on every run, never re-arms the notification, never advances the freshness clock, and escalates after two runs — permanently. R-23 fires against a healthy system; R-24's freshness target N is undefined for that destination; R-27's "time since last successful export" never advances for the primary persona. The PM even noticed the shape of the problem for MQTT and solved it there — §4.3's QoS row gives QoS 0 "a separate 'last unconfirmed send' clock rather than contributing to R-23 and R-27" — but did not apply the same reasoning to the far more common webhook case. `06` line 1096 flags the general hazard in terms: "**A QoS-0-only destination would alarm forever.**"

**What would fix it.** Adopt `08`'s position, not `03`'s, and say that you are overriding `03`. A 2xx from a declared success range is a genuine acknowledgement of receipt; the failure `03` is worried about — "succeeded but nothing arrived" — is the statistics-materialisation failure, and `08` and TA-03 are right that the correct mitigation is R-25's configuration-time read-back gate plus the statistics-row assertion, not a permanent downgrade of the run outcome. Then keep the receipt body as a SHOULD that *upgrades* fidelity where present: with a receipt, a short-count becomes `partial(receipt_short)` with a named cause; without one, `success` on 2xx with `ack_evidence = status_only` recorded in the journal so the audit trail states the strength of the evidence. That is honest — it distinguishes grades of acknowledgement rather than flattening them — and it does not alarm the primary persona forever.

If the PM instead keeps `03`'s position, then the "separate unconfirmed clock" mechanism must be generalised from QoS 0 to every receiptless destination, and R-24 and R-27 must be amended to say that the primary persona's default destination has no success clock at all. I think that is the worse answer, and I would want it argued rather than arrived at.

---

### SR-F-05 — The journal database's Data Protection class makes the locked-device wake unrecordable, which is precisely what A-1 exists to record; Q10 was escalated to the PM and dropped

**Severity: Blocker**

**Claim under attack.** `00-system-design.md` §2.3 in its entirety: "SQLite behind a `StateStore` port. See §4.2". The document contains no reference to Q10, to Data Protection classes, or to the conflict below. `05-observability-design.md` raised it in its opening reconciliation note as one of "three places [that] do **not** reconcile cleanly and are raised for the PM rather than papered over".

`05`§Q10:

> "ADR-0005 puts the whole database at `SQLITE_OPEN_FILEPROTECTION_COMPLETEUNLESSOPEN`; I need `CompleteUntilFirstUserAuthentication` for the state and journal tables, because a background wake hours after lock must **open** the database cold and I do not believe `CompleteUnlessOpen` permits that. **If I am right, the journal is unwritable during exactly the wakes we most need to record, including every locked-HealthKit failure.**"

`01-system-architecture.md` §7.3 confirms the other side: the chosen first-party wrapper's advantage is listed as protection class "**Directly settable**: `SQLITE_OPEN_FILEPROTECTION_COMPLETEUNLESSOPEN` at open".

**Why it fails.** The observability engineer says this "should be settled by a one-hour test on a real locked device before M2, not by argument". He is being too modest: it is settleable by argument today, from Apple's own documentation, and the answer is that he is right.

Apple's Platform Security guide, *Data protection classes*, on Class B (`NSFileProtectionCompleteUnlessOpen`): "As soon as the file is closed, the per-file key is wiped from memory. **To open the file again, the shared secret is re-created using the Protected Unless Open class's private key** and the file's ephemeral public key, which are used to unwrap the per-file key that is then used to decrypt the file." That private key is protected by the user's passcode and the device UID, i.e. unavailable while locked. <https://support.apple.com/guide/security/data-protection-classes-secb010e978a/web>

Apple's developer-facing description of the same class states the consequence directly: "**Protected Unless Open.** Files are encrypted. **A closed file is inaccessible when the device is locked.** After the device is unlocked, your app can open and use the file. If the user has a file open and locks the device… your app can continue to access the file."

So ADR-0005 as written means: on any background wake occurring while the device is locked and the database not already open — which, per C-02, is the majority of wakes, since HealthKit access is relinquished ten minutes after lock — the app **cannot open its own journal**. Consequences, all against Musts:

- **R-20** ("A durable on-device journal records **every** run… It survives process death") is unsatisfiable for the most common wake condition.
- **R-22** (scheduling failure attributed separately from execution failure) collapses in the direction the observability design already identified as a bias: an unrecordable wake looks identical to a wake that never happened. `05` accepts that bias only for the narrow pre-first-unlock window; under Class B it applies to nearly every wake.
- **A-1**, the PM's own headline amendment, is self-defeating. `blocked_device_locked` exists so the app can honestly report "the platform refused us the read". You cannot write a row saying "we could not read because the device was locked" into a database you cannot open because the device is locked.

This is the sharpest illustration of why dropping §4-level conflicts is dangerous: the PM's most-argued amendment depends on a question the PM did not carry.

**What would fix it.** Settle it in this document, not at M2. Adopt `05`'s ADR-OBS-03 with the split it proposes: the state and journal tables move to `CompleteUntilFirstUserAuthentication` (Class C), payload blobs stay at Class B, and the downgrade is argued once in an ADR with the justification the observability design already supplies — the journal holds metric names and counts, not sample values, and `01`§760 already commits to "**No SQLCipher, no encrypted database**… Journal and ledger rows — metric names, counts". Note this also resolves ADR-0005's contradiction with ADR-OBS-03, which `05` flags and `00` does not mention. Then still run the one-hour device test as a confirmation, not as the decision procedure. And add a fault-injection assertion under R-83's `StoreLocked` injector that a locked-device wake produces a journal row.

---

### SR-F-06 — O-2's GRDB half rests on a claim that omits the exact fact the architect's objection turned on

**Severity: Major**

**Claim under attack.** `00-system-design.md` §4.2:

> "**Spend the dependency budget on GRDB, not on MQTT.** … A crash-safe, migration-capable persistence layer is *exactly* where correctness bugs live… and reinventing it is the single most effective way to spend twenty months writing a database instead of a product. **GRDB is mature, MIT-licensed (AGPL-compatible), and builds on Linux.**"

**Why it fails.** Two of those three clauses are true. I verified GRDB is actively maintained (v7.10.0, released 2026-02-15, ~9k stars) and MIT-licensed, hence outbound-compatible with AGPL-3.0. The third clause is technically true and materially misleading, and it is the only one the architect's objection depended on.

GRDB's README states its requirements as "iOS 13.0+ / macOS 10.15+ / tvOS 13.0+ / watchOS 7.0+ • SQLite 3.20.0+ • Swift 6.1+ / Xcode 16.3+" — Linux is not among them — and carries this note:

> "**Note**: Linux support is provided by contributors. **It is not automatically tested, and not officially maintained.** If you notice a build or runtime failure on Linux, please open a pull request with the necessary fix, thank you!"

<https://github.com/groue/GRDB.swift/blob/master/README.md>

Linux, Android and Windows support arrived in v7.10.0 in February 2026, six months ago, and the maintainer's own release announcement frames the platform work as contributor-driven. <https://forums.swift.org/t/grdb-v7-10-0-android-linux-windows-and-sqlcipher-swiftpm/84754>

Now read what the architect actually wrote, in `01`§7.3's options table:

> "| **SQLite via GRDB** (MIT) | Linux: **Supported, but secondary to Darwin** | … | **Reject, with regret and a reversal trigger.** The migrator and the hardened edge cases are worth **~1–1.5 EW**. But R-80 makes Linux a *required check from the first commit*, and betting the core's storage on a package **whose Linux support is a secondary target** is a schedule risk in the first milestone that matters |"

The architect had already conceded "builds on Linux". His objection was that Linux support is *secondary*, and GRDB's own README says something stronger than secondary: not automatically tested, not officially maintained. §4.2 does not rebut that argument. It restates the premise the architect granted, in a form that omits the qualifier, and declares the matter resolved.

The failure mode is concrete and cheap to name. R-80 makes the Linux build "a required check from the first commit" — Stage 1's hardest-won constraint, and the mechanism §1.5 and §2.1 rely on to enforce the whole layering. Under O-2, the storage layer beneath every correctness test in the project depends on a code path its upstream does not test. When an upstream release breaks Linux, the project's required check goes red for a reason the project cannot fix except by upstreaming a patch and waiting — on a two-maintainer project whose top risk is abandonment.

Two further costs §4.2 does not price. First, the saving being bought is the architect's ~1–1.5 EW out of ~87, against his stated alternative of "1,200 reviewable lines" — so §4.2's rhetoric ("twenty months writing a database instead of a product") argues against a strawman rather than against the architect's actual proposal. Second, `01`§7.3 records that GRDB "Needs custom open flags; reachable via configuration hooks" for the Data Protection class, whereas the wrapper makes it "Directly settable" — and per SR-F-05 that flag is exactly the one that has to change. The override makes the fix for a Blocker indirect.

To be clear about category: I am not claiming GRDB is a bad library, and I am not claiming the PM's *conclusion* is necessarily wrong. I am claiming the **argument as written is not sound**, and the owner is being asked to take O-2 on a premise that omits the operative fact.

**What I would have decided instead.** Keep the architect's first-party wrapper for v1, with his reversal trigger intact. The reasoning: the wrapper is 1,200 lines against a fixed, frozen, extremely well-documented C API — SQLite is the most-tested software in the dependency tree either way, and what the wrapper owns is open flags, WAL configuration, `BEGIN IMMEDIATE`, and a `user_version`-gated migrator, all of which are on the critical path and all of which the design wants to control explicitly anyway (protection class per SR-F-05; WAL capped at 4 MB per R-73; `SQLITE_OPEN_FILEPROTECTION_*` at open). The 1–1.5 EW premium buys zero supply-chain exposure under a required-from-commit-1 Linux check, and buys direct control of two knobs GRDB mediates. If the PM still prefers GRDB, then: state the README's actual Linux status in §4.2, pin the version, vendor a fallback, add a CI job that builds GRDB's Linux target independently so upstream breakage is attributable, and record the reversal trigger the architect asked for.

I also note the MQTT half of O-2 is better-founded than §4.2's framing suggests — see SR-F-12 — so the two halves should be decided separately rather than as one trade.

---

### SR-F-07 — R-73's 400 ms margin is an unsourced budget whose stated precondition O-2 invalidates, and it was never re-derived

**Severity: Major**

**Claim under attack.** `00-system-design.md` does not state the number, but §6 and §1 rest on the plan being feasible, and `08-reliability-design.md` puts it in the executive summary as one of three things "the PM needs before synthesis":

> "And one number: **R-73's 400 ms is achievable, with roughly 185 ms of margin on an iPhone 11**, but only if the background launch path is treated as a closed list of permitted operations rather than as 'the app, started'."

The budget, in `08`§R-73: process launch + dyld ~120 ms; `HKHealthStore` init ~30; SQLite open + WAL recovery ~40; anchor row read ~5; query construction + dispatch ~20; total ~215; margin ~185.

**Why it fails.** Two problems, of different kinds.

*Unsupported.* Every one of the five line items is an unsourced point estimate. There is no citation, no measurement, no reference to a comparable app, and no stated variance — on an NFR specified at **p90** under "cold, thermally unfavourable" conditions, where the p90 of a cold dyld launch on a six-year-old device under thermal pressure is precisely the quantity that misbehaves. The design is candid that the *method* is right (a closed list of permitted operations, with a debug trap on violations, is exactly the correct design response), and I am not attacking the method. I am attacking the presentation of ~185 ms as "margin" in the executive summary of a document the PM then synthesised as settled. It is a hypothesis with a testable prediction, and R-70/R-71's sibling spikes exist because this project has already agreed that unvalidated performance assumptions get measured rather than asserted (RK-2). This one did not get a spike.

*Wrong, or at least invalidated.* The same section states the budget's precondition:

> "**The dependency budget is a launch-latency decision as much as a supply-chain one. Zero third-party dynamic frameworks on this path is what keeps dyld at ~120 ms**; MQTT's SwiftNIO graph must be linked into a target the background read path never touches."

§4.2 then puts GRDB underneath "open SQLite" and "read the `anchor` rows" — two of the five permitted operations, i.e. squarely on that path. The synthesis does not mention the interaction and does not re-derive the budget. In fairness, SPM products link statically into the app binary by default, so the effect is likely far smaller than a dylib load, and I could not find a measured figure for GRDB's contribution to launch time — I am not claiming R-73 now fails. I am claiming that a stated precondition of the project's tightest NFR was falsified by an override in the same document, and nobody noticed.

Related and worse, in the same section: R-72's budget is "read 6.3 s + transform/encode 1.2 s + compress 0.3 s + commit 0.2 s = **8.0 s. Zero headroom**", explicitly at "the assumed 1,600 samples/s" that RK-2 says is unvalidated, with the note "At 800 samples/s the read phase alone is 12.5 s and REF-A fails." An NFR with zero headroom on an unmeasured assumption is a coin flip, and `00-system-design.md` mentions neither R-72 nor the zero-headroom finding anywhere.

**What would fix it.** Add R-73 to the M0 spike set alongside R-70/R-71: a stub app that does nothing but the permitted operations, measured over ≥100 cold background launches on REF-B, p90 reported, built twice — with and without the persistence dependency — so the dyld delta is a number rather than an argument. This is hours of work and it decides O-2 on evidence. Until then, state R-73's margin as provisional in §5's A-6 alongside the other four provisional thresholds, and add R-72's zero-headroom finding to §5 explicitly, because it is the NFR most likely to fail and it currently appears nowhere in the synthesis.

---

### SR-F-08 — No NFR in the design covers any device that can run the app, because D-05's floor reaches hardware iOS 26 does not support

**Severity: Major**

**Claim under attack.** `00-system-design.md` §3, F-3:

> "**Resolution:** restate R-11 and R-75 per OS tier and say so plainly in the App Store description. **Do not raise the floor** — RK-8 (market too small) is the worse risk, and both incumbents ship iOS 17.0."

and §5, A-4: "Restate per OS tier: unattended full backfill requires iOS 26+; on iOS 18–25 it needs foreground time".

**Why it fails.** The resolution is right and the consequence is unpaid.

PRD §7 defines the entire NFR set on two devices, both at iOS 26: "REF-A — iPhone 15 Pro" and "**REF-B — iPhone 11. The floor: oldest device iOS 26 supports.** All ceilings must hold here." Every row of the NFR table — including R-73's 400 ms, R-74's 100 MB, R-76's 1,200 ms and R-77/R-78's battery figures — carries "OS: iOS 26".

That characterisation of REF-B was correct when written, and I verified it: iOS 26 requires an A13 Bionic or newer, making iPhone 11 and iPhone SE (2nd gen) the oldest supported models, and it dropped the A12 iPhone XR, XS and XS Max, which top out at iOS 18. <https://tidbits.com/2025/06/12/the-real-system-requirements-for-os-26/>

But D-05 set the deployment target to **iOS 18.0**. So the devices that can install this app include exactly the ones iOS 26 excludes: iPhone XR, XS and XS Max on A12, and — for iPadOS 18 — the 7th-generation iPad on A10 Fusion. Those devices are one to three silicon generations below REF-B, and **not one NFR in the PRD or in any of the nine designs states a threshold for them.**

The gap compounds with F-3 rather than being independent of it. F-3's whole point is that iOS 18–25 gets a *different execution path*: `08`§698–703 specifies a separate foreground-driven backfill mode for that tier, and `01` prices it as "a second full-history execution path, ~1.5 EW". So the newly-designed second execution path, on the slowest hardware in the supported set, has zero performance coverage. R-91 says: "Every performance NFR is expressed as (workload, device, **OS version**, metric, threshold, percentile) with a committed on-device baseline. **NFRs without a mapped test are rejected at Stage 2 review.**"

The only iOS 18 coverage anywhere is `07`§1067's nightly tier: "full Simulator matrix (iOS 18.0 floor and current, iPadOS)" — a non-required check, on a Simulator, which cannot measure launch latency, memory under thermal pressure or battery, and which the QA lead's own confidence note lists among his two "verified absences": "that **no programmatic path exists to populate the iOS Simulator's HealthKit store**". So the iOS 18 tier is nominally covered by an environment that cannot hold the data.

**What would fix it.** I agree with the PM's judgement on the floor — RK-8 is the worse risk and I would also decide "do not raise it". Then pay for it: add **REF-C — an A12 iPhone (XR or XS) on iOS 18** to PRD §7 as a seventh amendment, and restate at minimum R-73, R-74 and R-76 for it, plus R-75 in its foreground-driven form. If the owner will not fund a third device (O-7 already asks for three), then the honest alternative is to state in §5 and in the App Store description that performance is characterised on iOS 26 hardware only, and to reduce the iOS 18–25 tier's claims accordingly — but that is a real product statement, not a footnote. What is not acceptable is a design that takes D-05's reach while specifying every threshold on hardware D-05's target cannot run.

---

### SR-F-09 — R-70 and R-71 are PRD Musts due "before Stage 2 closes"; A-6 amends R-91 instead, and §8's exit criteria omit them entirely

**Severity: Major**

**Claim under attack.** `00-system-design.md` §8, the complete exit-criteria list, which contains no item for R-70 or R-71; and §5's A-6, which amends only R-91:

> "| A-6 | **R-91** | Record as *mapped, pending measurement* until R-71 completes… | R-71 is one engineer-day of harness plus **five calendar weeks** of soak. No Stage 2 close sooner than that can honestly report R-91 as met |"

**Why it fails.** R-70 and R-71 are not merely inputs to R-91. They are themselves rows in the PRD's NFR table, with their own Must-equivalent acceptance criteria keyed to this stage:

> "| R-70 | **Measure actual HealthKit read throughput before Stage 2 closes** | … | Threshold: **Published finding**; four NFRs below are void if the assumption is wrong |"
> "| R-71 | Measure background-delivery reality… | … | Threshold: **Published before Stage 2 closes**; R-24's N derives from it |"

Neither has run. `07`§TA-02 confirms it in terms: "they are **designed, not executed**". PRD §14 lists "the R-70 and R-71 measurement spikes as the first work items" carried into Stage 2, and PRD §7.1's second sequencing constraint says "Stage 2 should **re-baseline** after the R-70 and R-71 measurement spikes, which are the cheapest risk reduction available and should happen first." The design instead schedules them at M0 — i.e. in Stage 3, after this stage closes.

A-6 is a partial and slightly misdirected fix: it amends the requirement that *consumes* the measurement while leaving unamended the two requirements that *mandate the measurement's timing*. And §7's O-4 asks the owner to resource R-71 "starting now", which concedes the point without recording it as an amendment. The result is that Stage 2 is being closed against two unsatisfied Musts that name Stage 2 close as their deadline, with no amendment and no exit-criteria row.

Separately, the architect's §11.4 identifies a second and different R-91 problem that A-6 does not cover: R-77 (battery) and R-79 (wake budget) have **no mappable automated test at all** — "MetricKit delivers daily aggregates from real devices, opportunistically, with no simulator equivalent and no percentile control. As written, R-91 rejects two of its own NFRs at this review." His proposed amendment (allow a named, scripted, recorded device protocol per the R-87 pattern) is not in §5. So R-91 is unsatisfiable at this review for two independent reasons and §5 addresses one.

**What would fix it.** Either amend R-70 and R-71 to strike "before Stage 2 closes" and name M0 as the deadline with the four dependent NFRs explicitly marked provisional (which is close to what A-6 does for R-91, and is the honest version of what is happening) — or hold Stage 2 open for the five weeks and run them, which is what the PRD as approved requires. Add the architect's §11.4 amendment for R-77/R-79. Add an exit-criteria row for each so the next reader can see the state. My preference is the first: A-6's logic is sound and the spikes genuinely cannot compress, but the amendment must name the requirements it is actually changing.

---

### SR-F-10 — The deletion-dating index question was explicitly escalated to the owner and dropped; its horizon at REF-DELTA is ~60 days, and repair depends on an action nothing schedules

**Severity: Major**

**Claim under attack.** `00-system-design.md` §1.4:

> "**Completeness is audited by one bounded artefact** — a permanent per-(metric, day) census digest, with a UUID-level index only inside the reconciliation window. One data structure serves four requirements: R-08's reconciliation, **R-05's guaranteed-convergence path (deletion by absence)**, R-88's day-21 soak reconciliation, and R-69's data browser."

The synthesis contains no reference to the index's size, its horizon, or the trade. §4.3 resolves the HealthKit designer's open questions 2 and 3 (bucket keys, medications) and omits question 1 — the one he escalated:

> "1. **The deletion-dating index costs 48 MB and buys a bounded horizon (~400 days at low volume, far less at REF-DELTA).** Beyond it, deletions are emitted as tombstones but cannot be attributed to an aggregate bucket until a full reconcile. Do you accept that trade…? This is the one place where R-05's 'best-effort' is quantified, and **it deserves your signature rather than mine.**"

**Why it fails.** Three things.

*The dropped decision.* A specialist who says "this deserves your signature rather than mine" about the one place a Must's best-effort clause is quantified has asked for an owner decision. Two of his three questions were answered in §4.3. This one, the only one with a number attached, was not, and it is not in §7 either.

*The horizon is worse than the phrasing conveys, and the arithmetic is checkable.* `02`§535–542 gives ~40 bytes per row and a 48 MB cap, which is 1.2 million rows. At the stated REF-DELTA rate of 20,000 samples/day that is **60 days**, not "~400". The "~400 days" figure holds only at roughly 3,000 samples/day. Both numbers are consistent with the design's own arithmetic — the designer says "far less at REF-DELTA" and is not hiding anything — but the synthesis carries neither, and 60 days is a materially different product property from 400. A heavy user with a Watch, a CGM and a third-party scale is not an exotic case; the PRD's own reference corpus (R-82) posits ≥60 types from ≥6 sources.

*The repair path is manual, which undercuts §1.4's claim.* Every reference to the full reconcile in every design marks it user-triggered: `02`§550 "the next full reconcile (**user-triggerable**, R-08) repairs it by absence"; `02`§599 "(iii) on explicit user request"; `01`§358 "**Full reconcile (R-08, user-triggerable)**". I could find no scheduled, automatic, or opportunistic full reconcile anywhere in the nine documents. So for a deletion of a sample older than the horizon, the exported aggregate is knowingly wrong until the user manually asks for a repair they have no way of knowing is needed. Calling that "R-05's **guaranteed**-convergence path" in the executive summary is over-claiming: it is guaranteed *conditional on a user action that nothing prompts*.

This matters because it is asymmetric with R-01. For late-arriving *additions*, the dirty-bucket ledger makes re-emission automatic and unbounded in age — genuinely excellent, and the design's best idea. For *deletions* beyond the horizon, there is no equivalent. The product's headline is "correct under late-arriving data", and half of that promise degrades to manual.

**What would fix it.** Put the question in §7 as O-9 with the REF-DELTA number stated in days rather than as "far less". Then close the manual gap: schedule a low-priority full reconcile on a cadence (the design already has an admission-control mechanism, I6, that subordinates catch-up work to live delivery, so this is nearly free), or make the `deletion_undatable` journal event drive a targeted reconcile of the affected type rather than waiting for a global one — the event already carries `{type, uuid}`, so a bounded per-type sweep is available. And soften §1.4's "guaranteed-convergence" to state the condition.

---

### SR-F-11 — Q11: three documents hold three different definitions of R-23's escalation threshold, and the PM was asked to assign an owner in synthesis and did not

**Severity: Major**

**Claim under attack.** `00-system-design.md` contains no reference to the escalation threshold, to Q11, or to the disagreement. `05-observability-design.md`§Q11:

> "**Q11 — One escalation threshold, three definitions.** UX derives it from a user-chosen cadence, the reliability design from `clamp(2 · N_p95(class), 6 h, 48 h)`, the architecture design from `lastSuccess + N`. R-23 is a Must and R-71 has not run, so a threshold that requires N cannot ship on its own. My proposal is one function with two regimes… and a single owner. **The PM should assign that owner in synthesis**, because three documents each holding a version of the same constant is precisely how the twelve-state model ends up disagreeing with itself in Stage 3."

**Why it fails.** The specialist named the failure mode, named the three conflicting definitions, proposed a resolution, and made a specific request of the synthesis. The synthesis did none of it. This is the second of `05`'s three explicitly-flagged non-reconciling items to be dropped (Q10 is SR-F-05; only Q12 was carried, as §4.3's `partial` row).

The consequence is not hypothetical. R-23 is the requirement `06` calls "the watchdog became the product". Its threshold is the single constant that determines when the product makes its central claim ("loud when it stops"), and it is currently defined three ways in three authoritative documents. One of the three (`lastSuccess + N`) depends on R-71's unmeasured N, which per SR-F-09 will not exist for five weeks; another (`clamp(2·N_p95(class), 6h, 48h)`) is per freshness class, matching A-3's amendment of R-24; the third is user-chosen, which is a different product decision entirely. These are not refinements of each other — a user-chosen cadence and a measured-p95-derived clamp will disagree by hours, and the twelve-state status model in `06` will render whichever one the implementing engineer wired up.

**What would fix it.** Adopt `05`'s proposal — one threshold function, one owner, two regimes (a shipped default before N exists, the measured form after) — and record it in §4.3 with the owner named, exactly as the observability engineer asked. Then add a cross-document assertion to the test architecture: one constant, one definition site, and a test that the UI, the notification scheduler and the widget timeline all read it from that site. The design already has the mechanism for this pattern (`CoreTemporal` is "the **only** place `Calendar`, `TimeZone` and `Locale` are constructed"); apply it to the threshold.

---

### SR-F-12 — "A few hundred lines" is the PM's own number, not the security engineer's, and O-2 changes MQTT's cost basis without repricing it

**Severity: Major**

**Claim under attack.** `00-system-design.md` §4.2:

> "**A publish-only MQTT client is a few hundred lines of well-specified protocol with a narrow failure surface**, and the security engineer wants to own it anyway."

**Why it fails.** I went looking for the source of "a few hundred lines" in the specialist designs. The phrase does not appear in any of the nine. The security engineer's actual scoping is narrower and more careful:

> "MQTT 3.1.1's **publish-only** subset is small. CONNECT, CONNACK, PUBLISH, PUBACK, PINGREQ/PINGRESP, DISCONNECT. No subscribe, no websockets, no broker-side session management, no MQTT 5 property system."

He says "small". He does not put a line count on it, he scopes it explicitly to 3.1.1 (not 5.0), and his argument is not about size at all — it is the T-36 enforcement-point argument: "**Every third-party MQTT stack brings its own TLS implementation and its own connection establishment**", so a library puts R-32's allowlist, R-31's pin-on-first-use, SEC-15's address-class re-check and SEC-22's trust anchors off the enforcement path.

On the spec surface, I checked the brief's specific concern and it partly cuts the *other* way, so I will say so. Under MQTT 3.1.1, QoS 1 requires the publisher to assign an unused Packet Identifier per message, treat the PUBLISH as unacknowledged until the matching PUBACK arrives, and — this is the important part — retransmission is mandatory in exactly one circumstance: "When a Client reconnects with CleanSession set to 0, both the Client and Server MUST re-send any unacknowledged PUBLISH Packets (where QoS > 0)… **This is the only circumstance where a Client or Server is REQUIRED to redeliver messages** [MQTT-4.4.0-1]." <https://docs.solace.com/API/MQTT-311-Prtl-Conformance-Spec/Operational_behavior.htm>

So a publish-only client that connects with CleanSession=1 and republishes from the app's **own** durable queue on reconnect is spec-conformant and needs no MQTT-level session persistence. The design is already built for exactly that: `08`'s I3 releases a batch only on confirmed acknowledgement, PUBACK is the ack, and T2 is the commit boundary. The "QoS 1 needs crash-safe session state" objection therefore does not land here, and the PM's instinct that the surface is narrow is defensible.

What does land is the pricing. PRD §5.2 costs MQTT at **3 EW** as a destination — i.e. as a library integration, which is what D-04's dependency review contemplated. O-2 changes that to a first-party protocol implementation plus TLS integrated with the R-31/R-32/R-35 trust machinery, plus keepalive timers, variable-length integer encoding, UTF-8 string and topic-name validation, CONNACK return-code handling, packet-ID lifecycle, PUBACK correlation, and R-90's real-broker conformance testing. That is not obviously 3 EW, and §6 restates the ~87 EW total unchanged. The GRDB half of O-2 saves ~1–1.5 EW; the MQTT half spends an unquantified amount. **Neither direction is priced, and they are presented as a single balanced trade.**

**What I would have decided instead.** Split O-2 into two decisions, and take the MQTT half on the security engineer's argument rather than on the PM's line count. I agree with him: the T-36 enforcement-point reasoning is strong, and a fragmented egress chokepoint would undermine R-31 and R-32, which are load-bearing for RK-7. But price it — ask the security engineer for an EW figure, since he is volunteering to own it — and record in ADR-0006 that the client is MQTT **3.1.1 publish-only with CleanSession=1 and no MQTT-level session state**, because that constraint is what keeps the surface small and a future contributor will otherwise "improve" it into a general client. Then take the GRDB half separately, on the corrected facts (SR-F-06).

---

### SR-F-13 — §6 re-states ~87 EW after this document added scope, without the re-baseline the PRD required

**Severity: Major**

**Claim under attack.** `00-system-design.md` §6:

> "The wedge — engine, journal, watchdog, local-file destination — completes at **M6 with ~57 of ~87 EW consumed**, before MQTT, the companion or HACS begin."

**Why it fails.** The ~87 EW figure and the ~57/~87 split are faithfully carried from `01`§981 ("Total **87 EW**, matching §7.1's baseline") and are internally consistent with the PRD. That is not the problem. The problem is that PRD §7.1 says two things about this number which the synthesis does not honour:

> "2. **The estimate has no contingency.** It is a sum of the architect's point estimates, and RK-2 can invalidate four NFRs and an unknown slice of the engine. **Stage 2 should re-baseline after the R-70 and R-71 measurement spikes**, which are the cheapest risk reduction available and should happen first."

The spikes have not run (SR-F-09), so the mandated re-baseline cannot have happened — and §6 reports the un-re-baselined total without saying so. Meanwhile `00-system-design.md` itself accepts new scope in the same document: F-3's second full-history execution path (~1.5 EW, per `01`), §4.3's designated-exporter decision ("**Ship it** (~1 EW, M4)"), O-2's unpriced MQTT delta (SR-F-12), and A-6's five-calendar-week R-71 dependency which O-4 says must start now and which A-6 concedes is on the critical path "for four NFRs and for R-24". A total that was described as having no contingency has absorbed at least ~2.5 EW of newly-accepted scope and is restated unchanged.

This is squarely in the "unsupported" category rather than the "wrong" one — I cannot show that 87 is the wrong number, and against a 20–26 month horizon ~2.5 EW is noise. What I object to is that §6 presents the figure as a settled property of the plan ("That ordering is the single most important property of the plan") in the one document whose job is to report what Stage 2 discovered, while the discoveries that move the number sit two sections earlier.

**What would fix it.** State the delta explicitly: ~87 EW plus F-3's ~1.5, plus the designated exporter's ~1, plus an O-2 delta to be supplied, equals ~90 and rising, with no contingency and a re-baseline still owed after M0's spikes. Add a row to §8's exit criteria recording that the PRD-mandated re-baseline is deferred to M0 and why. And name the giver more honestly than §6 does: §6 nominates the Mac companion (M9, 5 EW), but the companion was restored to scope by owner decision D-14 and is a Must in PRD §5.1, so "designated giver" is a scope reduction the owner has already refused once and should be asked about again rather than assumed.

---

### SR-F-14 — F-1's resolution is coherent as a bet but the acknowledgement screen is the wrong control, and the profile is load-bearing for RK-1 in a way that makes it worse

**Severity: Major** (judgement, not defect)

**Claim under attack.** `00-system-design.md` §3, F-1, and O-1:

> "**Resolution:** ship it, gated behind a one-time explicit acknowledgement naming both losses, and never as a user's only destination without a standing warning."

**Why it fails.** I accept the finding as stated — the schema engineer's research is careful and I could not falsify it (see §Claims I attempted to falsify). My objection is to the control, and to a second-order effect the synthesis does not notice.

*The control is mismatched to the harm.* A one-time acknowledgement is the right instrument for a loss the user experiences immediately and can attribute. This loss is neither: a user on the HAE profile has no tombstones and no upsert key, so their destination silently accumulates records Apple Health has since deleted or edited. That is the incumbent's exact failure mode, and the whole premise of this product is that users cannot detect it unaided — which is why R-08's reconciliation, R-23's watchdog and R-69's browser exist. A consent click at configuration time, weeks or months before the first divergence, does not arm the user against a failure whose defining property is that it is invisible.

Worse, the profile interacts badly with the product's own gates. R-08's reconciliation will detect discrepancies against an HAE destination that it structurally **cannot repair** through that sink, because repair requires upsert-by-UUID and tombstones. G-1's measure is "The R-08 reconciliation capability reports zero discrepancy on the R-88 soak protocol", and A-5's amendment gates R-88 on *unexplained* discrepancy with "three explanation classes enumerated". If the HAE profile becomes a fourth explanation class, then A-5's enumeration is incomplete; if it does not, a soak run with an HAE destination fails the release gate by construction. §5 does not address this, and it is the kind of thing that gets waived the first time it fires — which is precisely the failure A-5 was written to prevent.

*The second-order effect.* PRD RK-1 lists HAE wire compatibility as a mitigation for maintainer abandonment: "R-12 versioned spec **and HAE wire compatibility so users are not stranded**". So the profile is load-bearing for the project's top risk. But a stranded user falling back to the HAE profile falls back to a format that cannot express deletions — i.e. the abandonment mitigation delivers users into the failure mode the product exists to fix. That is not a reason to drop the profile, but it means the RK-1 mitigation is weaker than the PRD claims and should be restated.

**What I would have decided instead.** Ship the profile, but not as a co-equal monitored destination. Three changes:

1. **Make it structurally ineligible for the honesty surfaces.** An HAE-profile destination does not participate in R-23's freshness escalation, R-24's N, or R-27's external signal, and is marked in the UI as "compatibility export — correctness claims do not apply". This is exactly the mechanism §4.3 already invented for MQTT QoS 0 ("a separate 'last unconfirmed send' clock rather than contributing to R-23 and R-27"), reused. It replaces a one-time click with a permanent, visible property, which is the right shape for an undetectable loss.
2. **Position it as a migration and interop path**, not a destination: the pitch is "point your existing HAE receiver at us today, then move to `ohe.wire/1` when you are ready", with the native profile always co-enabled by default so the user has a convergent copy from day one.
3. **Enumerate it as a fourth R-88 explanation class in A-5**, or exclude HAE destinations from the soak, so the release gate stays meaningful.

That keeps MA-03's ecosystem access — which is the real argument for shipping it, and it is a good one — without letting the compatibility profile borrow the product's central claim. If the owner prefers the PM's version, O-1 should at least record that an acknowledgement screen is consent, not mitigation.

---

### SR-F-15 — §4.3 resolves the aggregation-canonicality conflict but drops the R-80 exception list it requires, leaving §1's Linux claim unqualified

**Severity: Major**

**Claim under attack.** `00-system-design.md` §1.5:

> "**A HealthKit-free, Linux-buildable core of fourteen targets**, with a committed dependency adjacency manifest enforced in CI. `HealthKitAdapter` is a leaf nothing in core depends on, so the moment a core target imports it the Linux job fails."

and §4.3: "| Aggregation canonicality for multi-source cumulative metrics | 01, 02 | **HealthKit's de-duplicated statistic is canonical.** One number. It is what the Health app shows… |"

**Why it fails.** The PM answered the canonicality question and dropped the consequence, which the architect had filed as one of his seven unbuildable requirements. `01`§11.3, *R-80 vs R-07*:

> "HealthKit's statistics queries de-duplicate overlapping samples from multiple sources using an algorithm Apple does not document. For a multi-source cumulative metric such as `stepCount`, the *canonical* aggregate therefore **cannot be computed in a HealthKit-free core**. Either the core computes a different (and knowingly divergent) number, or that metric's canonical aggregation lives behind the seam and is unverifiable on Linux.
> **Proposed amendment:** *'R-80's Linux coverage extends to the whole pipeline with a committed exception list: metrics whose canonical aggregation provider is `hkStatistics` are exercised on Linux with a recorded reference vector rather than a live computation, and their canonical correctness is gated by R-87's device pass instead…'*"

By choosing "HealthKit's de-duplicated statistic is canonical", the PM chose the branch that requires the exception list. R-80 as approved reads "the whole export pipeline runs with HealthKit **not linked**. The core package and its tests build and pass on Linux", and R-07's verification is "Compare our aggregates against `HKStatisticsCollectionQuery` for a multi-source metric on a real device". After §4.3's ruling, the canonical aggregate for multi-source cumulative metrics is verifiable only on a device, against recorded reference vectors on Linux. That is a sound engineering answer — I would decide the same way, because the alternative is knowingly shipping a number that disagrees with the Health app, which destroys R-69's verification surface — but it is a **qualification of the project's hardest-won constraint**, and §1.5 states R-80 unqualified.

The brief asked whether the design holds R-80 in the diagram and breaks it in the details. On the two axes I expected to find trouble — the MQTT quarantine and the `CompanionWire` codec — it holds, and I say so in §Claims I attempted to falsify. This is the axis where it does not, and it is the one nobody was watching because it is an *aggregation* question rather than a *transport* one.

**What would fix it.** Carry `01`§11.3's amendment into §5 verbatim; it is well-drafted and includes the safeguards (list generated from `MetricCatalog`, asserted non-growing without an ADR, every aggregate record already naming its computation). Then qualify §1.5: the core builds and tests on Linux, with a committed, non-growing exception list of metrics whose canonical aggregate is device-verified. And note the interaction with SR-F-08: if canonical correctness for those metrics is gated by R-87's device pass, R-87's named-hardware list inherits the iOS 18 gap.

---

### SR-F-16 — The security engineer's explicit non-signoff item, and three of his eight open questions, never reached §7

**Severity: Major**

**Claim under attack.** `00-system-design.md` §7 lists eight owner decisions. §4.3 carries the security engineer's open questions 1 (companion distribution) and 4 (queue TTL); O-6 partially carries question 3 (advisory key). Questions 5, 6, 7 and 8 are absent, as is the item he flagged as a refusal.

`04-security-design.md`:

> "**And one thing I will not sign off on that is not yet in the document.** The Mac companion writing a decrypted health archive into an iCloud-synced folder by default. PC-3's reasoning does not extend to an unattended, repeated, app-managed write to a remembered path. **If the PM wants that behaviour it needs a pre-submission App Review answer first, not a shipped bet.**"

and, in his executive summary, the same hazard: "it writes a decrypted health archive into a user-chosen folder, unattended and repeatedly, and if that folder is iCloud-synced then **our app — not the user in Apple's own picker — is storing personal health information in iCloud**."

**Why it fails.** A specialist stating "one thing I will not sign off on" is the single highest-priority line in his document, and it does not appear in the synthesis at any severity. It is also not a novel risk: it is C-05 / PC-3 / App Review Guideline 5.1.3(ii), which the PRD treats as a hard constraint and whose boundary PRD §3 draws with unusual care ("The local-file destination writes wherever the user points the system document picker… **we ship no iCloud code**"). The security engineer's point is that the *companion* breaks the reasoning behind that boundary, because the write is unattended, repeated and app-managed rather than a one-time user choice in Apple's UI. `08`'s local-file row shows the same awareness ("If the user pointed at an iCloud folder, our ack covers commit to the local filesystem only"). Whether 5.1.3(ii) bites is a judgement I cannot settle — Apple's guideline text does not distinguish attended from unattended writes, and I found no authoritative interpretation either way, so I record this as genuinely unresolved rather than as a violation. Which is exactly why it needs the pre-submission enquiry the specialist asked for.

His question 8 asks for that enquiry and notes it is the second time: "**Stage 1 recommended this and it was not dispositioned.**" It has now not been dispositioned twice.

Question 5 is also material and unowned: "Who owns the security-maintainer role, and who is the deputy? SEC-47, SEC-84 and SEC-85 all assume a named person with an acknowledgement SLA, and D-10 records no second maintainer. **An unowned `SECURITY.md` promises a response nobody has agreed to give.**" O-6 asks for named owners for the HA version window, the R-38 advisory key, and Code of Conduct enforcement — a close-adjacent list that conspicuously omits the security-response role, on a health-data application shipping a security advisory channel as a Must (R-38).

Question 6 is SR-F-02. Question 7 is SR-F-01.

**What would fix it.** Add to §7: an O-9 recording the companion's folder-write question with the pre-submission App Review enquiry attached and a default position (my recommendation: default the companion's write target to a non-syncing location, detect an iCloud-backed target and refuse it with an explanation, and ship the enquiry regardless — the detection is cheap and it converts a policy bet into a product behaviour). Add the security-maintainer and deputy roles to O-6's list. And when a specialist writes "I will not sign off on", the synthesis should quote him.

---

### SR-F-17 — §1's convergence claim is not supportable, and it is the reason the drops happened

**Severity: Minor**

**Claim under attack.** `00-system-design.md` §1:

> "**The design holds.** Nine specialists working in parallel **converged rather than collided**, and the QA lead — who entered the stage expecting to file four blockers against the other designs — **withdrew three of them** because the designers had independently solved the problems. That is the strongest signal available at this stage that the PRD's constraints were the right ones."

**Why it fails.** The count is wrong and the characterisation is wrong.

`07`§2.2 states: "**All four of my pre-emptive Blockers are withdrawn**, and no design-defect Blocker remains", and separately files a *new* Blocker (TA-02) that was not among the four. So the QA lead withdrew four and filed one; the PM reports three withdrawn. The underlying good news is better than the PM claims, which makes the error odd — and it appears to be the same misreading that produced §4.1, since the fourth withdrawal is the security-design-absence one the PM believed was still live.

"Converged rather than collided" is contradicted inside the documents being synthesised. `05`'s opening note says three places "do **not** reconcile cleanly and are raised for the PM rather than papered over". SR-F-04 is a flat contradiction between `03` and `08` on the product's most common destination. SR-F-05 is a flat contradiction between ADR-0005 and ADR-OBS-03 on a Data Protection class. `07` files five Majors against the other designs. The honest summary is that the designs converged impressively on *structure* — the seam, the layering, the write-ahead cursor, the fault-injection vocabulary, all reached independently — and collided on several *interfaces*, which is the normal and expected outcome of parallel work and exactly what §4 exists to catalogue.

I file this as Minor because on its own it is a characterisation error in a summary. I file it at all because it is causally upstream of the Blockers: a synthesis that opens by declaring convergence is a synthesis that has stopped looking for collisions, and the four collisions it missed (SR-F-04, SR-F-05, SR-F-11, SR-F-15) are all of the same kind — two specialists designing the same interface from different sides, each internally consistent.

**What would fix it.** Correct the count. Replace the convergence sentence with the structural-versus-interface distinction, and add a §4.4 listing every cross-document interface where two designers made contact, with a resolved/unresolved marker. There are not many — the journal-versus-persistence schema, the outcome taxonomy versus delivery semantics versus status copy, the sink contract versus receipt semantics versus retry, the seam versus the fake versus the corpus, the escalation threshold, the protection class. Six rows would have caught four Blockers.

---

### SR-F-18 — R-26's bounding and TA-07's dependency on it are both absent, so a PRD Must's acceptance criterion is silently changed

**Severity: Minor**

**Claim under attack.** `00-system-design.md` makes no reference to R-26. `01`§11.6 proposes bounding it ("The journal grows without bound. A bundle covering a year is tens of megabytes, and 'render all of it, and the user must scroll it' is not a viable interaction… the practical effect would be an engineer quietly capping it, which is exactly the erosion RK-5 predicts"), and `07`§TA-07 makes the bound conditional ("the bundle window is **the greater of 30 runs or 24 hours**, or the soak uses a test-build time-windowed journal export… Costs nothing now; costs the soak on day 12").

**Why it fails.** R-26 is a Must whose acceptance criterion is "**Its full contents are rendered on screen** to read and scroll before any share affordance is reachable", with an "[a]utomated assertion that no share affordance is reachable without passing the preview". The architect's amendment changes "full contents" to "the last 30 runs by default, user-adjustable". That is a change to approved PRD text and needs ratification, or Stage 3 inherits a requirement two designs have already agreed cannot be met literally. TA-07's addition is the interesting part and the reason this is worth reporting at all: because F-2 makes `partial` the healthy common case, runs are frequent, and if run frequency exceeds 30/day a once-daily bundle capture stops covering 24 hours — which silently breaks R-88's day-level bisection, the mechanism that turns "we lost 41 `heartRate` samples" into "day 12, run 3". Two accepted findings (F-2 and the R-26 bound) interact to break a third requirement, and the synthesis carries F-2 but neither of the others.

I keep this Minor because the fix is a one-line requirement change and nothing is architecturally at risk. It is included because it is a clean example of the systemic problem: the amendment is cheap now and expensive on day 12 of a 21-day soak.

**What would fix it.** Carry `01`§11.6's amendment into §5 with TA-07's condition folded in: bounded by the greater of 30 runs or 24 hours, user-adjustable, with the preview and no-share-without-preview assertions unchanged.

---

## Claims I attempted to falsify and could not

These are the parts of the design I went after and could not break. Several are better than the synthesis gives them credit for.

**1. Anchors prove progress; only date-ranged sweeps prove coverage (§1.3, `02`§2).** This is the design's best idea and it survives attack. `HKQueryAnchor` is ordered by write sequence, so it genuinely cannot certify that an interval of measurement time is complete; refusing to advance `completeThrough` on anchored delivery is the correct and non-obvious consequence; and the dirty-bucket ledger converts R-01's "re-emit a 30-day-old window" from a special case into the normal path. I tried to find a case where a sample could dirty no bucket, or where the watermark could advance without positive coverage, and the design forecloses both by making `completeThrough` unassignable from an anchored result (ADR-HK-2). This is the mechanism that fixes the incumbent's defect and it is sound. My only qualification is the deletion asymmetry in SR-F-10, which is about the reverse direction.

**2. The structural write-ahead cursor (§1.2).** "There is no API that persists an anchor" plus "`CursorAdvance` is only accepted as a field of a batch-commit transaction" plus a synchronous transaction closure containing no suspension point plus an outcome derived from a tally rather than assignable — I could not find a path that advances a cursor without a committed batch. Making the run outcome a derived function, and enforcing `success ⇒ acked ≥ read` with a database CHECK constraint (`05`§R-21 verification), is the correct answer to "invariants enforced by type and transaction boundaries rather than by their authors' discipline". This is the claim the whole document rests on and it holds.

**3. R-80's transport story: the MQTT quarantine and `CompanionWire`.** The brief pointed me here and I expected to find the break. I did not. `SinkMQTTPackage` quarantining `mqtt-nio` and SwiftNIO in a package that never enters `ExportCore`'s resolution graph is a real mechanism, not a diagram; `CompanionWire` as a pure value-typed frame codec and state machine at L2, with `SinkCompanion` as a thin `NWConnection` adapter above it, is the correct Layer A/Layer B split and is genuinely Linux-buildable and fuzzable. The QA lead independently withdrew both as pre-emptive Blockers on inspection (`07`§2.2), and the four enforcement checks he lists — Linux build+test, adjacency manifest diffed against `swift package dump-package`, per-target import allowlist denying `HealthKit`/`Network`/`Security`/`SwiftData` in L0–L4, and a linked-framework plus `HK*` symbol assertion — are the right set. R-34 holding "by construction rather than by a symbol grep" (the Mac listens, the phone connects outward) is exactly the kind of enforcement the PRD asked for. The R-80 problem is in the aggregation path (SR-F-15), not here.

**4. The fixture-backed fake shares an encoding with the real adapter.** I probed this because "the fake and the real thing drift" is the standard failure of seam-based test strategies. The design's answer is not a convention: the fake reads the *same* NDJSON domain encoding the real adapter emits, so a change to the encoding breaks both. Paired with `FileWriteKit` being used by both the phone's local-file sink and the Mac receiver — "one writer, two hosts", designed that way specifically to enable a byte-identical differential test — this is a genuine anti-drift mechanism. I could not construct a divergence that the shared encoding would not catch.

**5. `HKDeletedObject` carries a UUID and nothing datable.** Tagged **[SDK]** and verified by the specialist against `HKDeletedObject.h` under `iPhoneOS26.5.sdk`, with the available metadata keys named exactly (`HKMetadataKeySyncIdentifier`, `HKMetadataKeySyncVersion`). I could not verify the header myself, but the claim is specific, falsifiable, attributed to a named artifact, and consistent with the documented API surface — and the whole deletion-dating index design follows from it, which means the designer had every incentive to wish it otherwise. I accept it. It is also the right kind of claim: the consequence (you need your own `uuid → (type, day)` index) is derived rather than asserted.

**6. The egress ledger is tamper-evident, not immutable.** The security engineer's refusal to let the project claim immutability, and the T-51 resolution — delete-all writes a genesis marker recording how many entries were destroyed and when, so "a coercer can still wipe it; they cannot make the wipe invisible" — is better than the PRD's own wording and is the correct security property for a device its owner controls. `06`'s complement (no per-row delete, no date-range clear, delete-all fires its own notification) is consistent with it. My only complaint is that the PM did not carry the R-30 rewording (SR-F-02), which leaves the architect's M6 gate asserting "immutable".

**7. C-02's Protected Unless Open / 10 minutes.** I re-checked the finding the Stage 1 reviewer got wrong, because I was warned about it. The Stage 1 disposition was right: the HealthKit store is in Class B (`NSFileProtectionCompleteUnlessOpen`), not Class A, and Apple's health-specific security page carries the 10-minute figure. Apple's *Data protection classes* page confirms the class taxonomy and Class B's semantics independently. The PRD's C-02 row is now correctly cited with class, figure, source and date. Note the irony that the same page which vindicates the PM at Stage 1 convicts ADR-0005 at Stage 2 (SR-F-05).

**8. The QoS 0 "alarm forever" problem is genuinely solved.** I went at the outcome-taxonomy / delivery-semantics / status-copy triangle expecting the three sides not to meet, and for MQTT they do. `08` identifies the paradox, `05` refuses to let `unknown_ack` set a last-success timestamp, `06` writes the copy ("This is not a failure and it is not a success") with a fix action, and §4.3 carries the separate "last unconfirmed send" clock. That is four documents agreeing on a subtle state. It is also what makes SR-F-04 so frustrating: the mechanism to fix the webhook case already exists and was not applied to it.

**9. The tzdata defeat of determinism property P8.** The architect is right and the QA lead's adoption of it "verbatim" is correct. Darwin Foundation and swift-corelibs-foundation do not ship the same tzdata version, tzdata changes several times a year, and a cross-platform SHA-256 equality assertion over calendar-dependent output is therefore false without any bug in the code. The restatement — per-platform determinism plus a declared tz-database version recorded in the checkpoint envelope, cross-platform equality asserted only over UTC and fixed-offset fixtures, and a CI gate on tzdata drift — is the right shape, and rejecting "vendor a pinned tz table" as one more dependency for a property no consumer asked for is the right call. (It should still be a §5 amendment, per SR-F-02, because it changes R-84's stated criterion.)

**10. GRDB is mature and AGPL-compatible.** Two of §4.2's three clauses hold: GRDB is MIT-licensed and therefore outbound-compatible with AGPL-3.0, and it is actively maintained — v7.10.0 shipped 2026-02-15 with the maintainer active in release notes and on the Swift forums. My objection in SR-F-06 is confined to the Linux clause and to the fact that the architect's argument was never engaged.

**11. `OSLogStore` cannot read a previous process's logs on iOS, so the journal must be the source of truth.** Carried from Stage 1 and load-bearing for the entire observability design. I could not falsify the `.currentProcessIdentifier` scope limitation, and the consequence the design draws from it — every observability surface is a read of the journal, and OTLP is a deferred projection with no span construction on the hot path — is the correct inversion of the owner's original framing. It also gives R-79's ≤2% wake budget "by construction rather than by measurement", which is the only NFR in the set that earns that phrase.

**12. `partial` becoming the healthy common case (F-2).** I tried to argue this was over-thought and could not. In a store-and-forward pipeline reads and acknowledgements genuinely are decoupled across runs, R-21 genuinely does forbid `success` when acked < read, and therefore a wake that durably enqueues 500 samples and hands them to a discretionary transfer has honestly acknowledged none. The mandatory cause code, and `partial(deferred_discretionary)` presenting as "Queued, awaiting delivery" while the user-facing headline stays on the freshness clock, is the right resolution. `05`'s Q12 condition — that it must still advance nothing on the freshness clock, so silence still escalates — is the load-bearing detail and §4.3 carries it.

---

## Sources

Primary and near-primary sources consulted for factual verification. Where a claim rests on secondary sources I say so in the finding.

**Apple — platform and policy**

1. *Lock or hide apps on your iPhone* — Apple Personal Safety User Guide, published October 2025. Confirms that user-installed apps can be hidden; that hiding removes the app from the Home Screen and moves it to an authentication-gated Hidden folder; that locking strips app information from notification previews, search, Siri suggestions and call history; and enumerates the residual surfaces (Settings > Apps > Hidden Apps, Screen Time, Battery, App Store purchase history) that constitute a recovery path. Used in SR-F-01. <https://support.apple.com/guide/personal-safety/lock-or-hide-apps-on-your-iphone-ipsd0be4c185/web>

2. *Data protection classes* — Apple Platform Security. Class taxonomy A–D, and the Class B (`NSFileProtectionCompleteUnlessOpen`) mechanism: per-file key wiped on close, re-opening requires the class private key, which is protected by the user's passcode and the device UID. Used in SR-F-05, and to re-verify C-02's class assignment. <https://support.apple.com/guide/security/data-protection-classes-secb010e978a/web>

3. *Protecting access to user's health data* — Apple Platform Security, published 2026-01-28. The health-specific page carrying the Protected Unless Open assignment and the 10-minute figure. Re-checked to confirm the Stage 1 disposition of AR-F-06 was correct. <https://support.apple.com/guide/security/protecting-access-to-users-health-data-sec88be9900f/web>

4. *Authorizing access to health data* — Apple Developer documentation. Cited by the security engineer for the proposition that read-authorisation revocation is undetectable, which underpins R-44's unimplementability. Consistent with `getRequestStatusForAuthorization`'s documented semantics; I did not independently falsify it. <https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data>

**iOS version and hardware support**

5. *The Real System Requirements for OS 26* — TidBITS, 2025-06-12. iOS 26 requires A13 Bionic or newer; iPhone 11 is the oldest supported model; iPhone XR, XS and XS Max are dropped and top out at iOS 18. Used in SR-F-08. Corroborated by Digital Trends and Beebom device lists, and by the iPadOS 26 line (7th-generation iPad, A10, maxes at iPadOS 18). <https://tidbits.com/2025/06/12/the-real-system-requirements-for-%EF%A3%BFos-26/>

**GRDB**

6. GRDB.swift README, `master`. Requirements list (iOS 13.0+ / macOS 10.15+ / tvOS 13.0+ / watchOS 7.0+ — Linux absent) and the verbatim note: "Linux support is provided by contributors. It is not automatically tested, and not officially maintained." Used in SR-F-06. <https://github.com/groue/GRDB.swift/blob/master/README.md>

7. *GRDB v7.10.0, Android, Linux, Windows, and SQLCipher+SwiftPM* — Swift Forums, 2026-02-15, by the maintainer. Establishes that Linux support arrived in v7.10.0, that the platform work was contributor-driven, and that GRDB + SQLCipher via SPM still requires a fork. Also establishes active maintenance. Used in SR-F-06. <https://forums.swift.org/t/grdb-v7-10-0-android-linux-windows-and-sqlcipher-swiftpm/84754>

8. GRDB.swift release v7.10.0, 2026-02-15. <https://github.com/groue/GRDB.swift/releases/tag/v7.10.0>

**MQTT**

9. MQTT 3.1.1 Protocol Conformance Specification, §4 *Operational behavior*. QoS 1 publisher obligations (assign an unused Packet Identifier; send with QoS=1, DUP=0; treat as unacknowledged until PUBACK); session state storage requirement [MQTT-4.1.0-1]; and [MQTT-4.4.0-1], that reconnection with CleanSession=0 is "the only circumstance where a Client or Server is REQUIRED to redeliver messages". Used in SR-F-12, including the part that supports the PM's position. <https://docs.solace.com/API/MQTT-311-Prtl-Conformance-Spec/Operational_behavior.htm>

10. OASIS MQTT normative-statement checklist (mqtt-spec), for MQTT-2.1.2-3, MQTT-4.3.2-1 and MQTT-4.4.0-1/2 (DUP flag on redelivery, in-flight resend on session resumption). <https://github.com/mqttjs/mqtt-spec/blob/master/list.md>

**Secondary, used only where flagged as such**

11. *How to hide apps on iPhone or iPad for privacy* — iDownloadBlog, updated for iOS 18/26. Reports that hiding removes the app's Home Screen and Lock Screen widgets and suppresses its notifications. Flagged as secondary in SR-F-01; this is the claim the security engineer's Q7(a) spike should settle on-device. <https://www.idownloadblog.com/2024/06/21/how-to-hide-iphone-apps/>

12. *Lock and hide apps on iPhone in iOS 18* — 9to5Mac, 2024-09-20. Enumerates the suppressed surfaces for locked-and-hidden apps: Search, Notifications, Spotlight suggestions, Siri suggestions, call history, Maps routing suggestions. Flagged as secondary in SR-F-01. <https://9to5mac.com/2024/09/20/lock-and-hide-apps-on-iphone-how-to/>

**Project artifacts** — `docs/01-prd/PRD.md` v1.0; `docs/01-prd/reviews/01-adversarial-review.md` and `01-disposition.md`; `docs/02-design/00-system-design.md` through `09-build-and-release.md`. Line references in the findings are to the files as of 2026-09-03.

**Claims I could not verify either way, and did not rely on:** whether App Review Guideline 5.1.3(ii) distinguishes an unattended, app-managed, repeated write to a remembered iCloud-backed path from a one-time user selection in the document picker (SR-F-16 — this is why the pre-submission enquiry matters); GRDB's contribution to dyld and launch time under static SPM linking (SR-F-07); and the contents of `HKDeletedObject.h` in `iPhoneOS26.5.sdk`, which I accepted on the HealthKit designer's `[SDK]` attribution.
