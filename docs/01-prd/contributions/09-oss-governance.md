# Open Source Governance / Licensing Lead — Stage 1 Contribution

> **Status:** Stage 1 requirements. Nothing here creates repository files; everything is
> specified as a requirement with acceptance criteria for the PM to schedule.
>
> **Not legal advice.** I am not a lawyer and neither, presumably, is the reader. This
> document is research plus engineering judgement. Sections tagged **[LEGAL ADVICE]**
> identify the specific decisions where a qualified lawyer should be paid before the
> decision is executed. Everything else is a judgement call the project can make on its own
> and change later.
>
> **Currency:** all research performed 2 September 2026. Two areas move fast and are
> explicitly time-stamped in-line: the EU Cyber Resilience Act phase-in (next milestone is
> **9 days away**, 11 September 2026) and Apple's external-link / commission rules (live
> litigation; Supreme Court merits briefing runs into autumn 2026).

---

## Executive summary

1. **"Make it OSS" is about a dozen decisions, and three of them are effectively
   irreversible.** The licence, the contribution-intake mechanism (CLA vs DCO), and the
   project name are the three that cost real money to reverse. Everything else —
   governance model, funding model, dependency policy — is cheap to change later. The PM
   should extract explicit user sign-off on those three and let me decide the rest.

2. **The GPL-vs-App-Store story is largely folklore, but there is a real residue.** Apple
   does not scan for, ban, or reject GPL licences. GPL-3.0 and even AGPL-3.0 apps are on
   the App Store *today* (Ice Cubes, Passepartout, Blink Shell, YourPods) [16][17][18][19].
   The 2011 VLC removal was triggered by a **copyright holder** filing a complaint against
   Apple, not by Apple objecting to the licence [4][5]. The residual risk is therefore not
   "Apple says no", it is "any single contributor who retains copyright can unilaterally
   get the app pulled". That reframes the problem from a licence problem into a
   **copyright-concentration** problem, which is a contribution-intake decision, not a
   licence decision.

3. **Recommended licence: MPL-2.0 for the app and first-party modules; Apache-2.0 for
   genuinely reusable standalone packages; CC BY 4.0 for docs; CC0-1.0 for schemas and
   example payloads.** MPL-2.0 is the licence VLC actually landed on after the whole saga
   [3]. It is the only mainstream licence that is simultaneously App-Store-clean (no "no
   further restrictions" clause to collide with Apple's minimum EULA terms), carries an
   express patent grant, and imposes file-level copyleft so a closed clone must publish its
   changes to our files. See the table below for what this forecloses.

4. **The Cyber Resilience Act almost certainly does not apply to this project — and the
   reason is a Commission guidance paragraph published five weeks ago that most
   commentary has not caught up with.** Draft guidance C(2026) 5252 of 27 July 2026,
   paragraph 61, states that FOSS supported *exclusively* through donations is unlikely to
   be "placed on the market" **even where donations exceed costs** [8]. That is materially
   more permissive than the plain reading of CRA recital 15 that most blog posts repeat.
   Combined with the fact that an individual (natural person) publishing free FOSS is out
   of scope entirely [8, §3.2.1 ¶53], the project is out of scope **as long as the App
   Store binary is free**. The moment we charge for the binary, we become a CRA
   *manufacturer* with CE marking, conformity assessment, SBOM-in-technical-documentation
   and a defined support period from 11 December 2027. **[LEGAL ADVICE]** before charging.

5. **The most concrete bus-factor constraint is not governance, it is Apple's account
   model.** An Apple Developer Program *individual* enrolment cannot have a team. Apple's
   own documentation: "If you're enrolled as an individual and add users in App Store
   Connect, users receive access only to your content in App Store Connect and are not
   considered part of your team", and "Certificates, Identifiers & Profiles is only
   available to Account Holders and members of an organization's team" [20]. So a
   co-maintainer on an individual account **cannot touch signing identities**. If the
   founder is hit by a bus, the App Store listing is unrecoverable without Apple support
   intervention. Fixing this properly requires organization enrolment, which requires a
   legal entity and a D-U-N-S number [21][22]. That is a real cost with a real trigger
   condition, and it is the single most credible answer to the market analyst's
   "will this be abandoned" objection.

6. **Nothing about the licence choice prevents a paid App Store binary later.** MPL-2.0,
   Apache-2.0 and even GPL-3.0 all permit charging. What a *paid* binary changes is
   regulatory (CRA scope, above), not licensing. Conversely, **charging is the only
   funding route Apple's rules make clean**: guideline 3.2.2(iv) prohibits collecting
   donations in-app unless you are an Apple-approved nonprofit, so donations must be
   collected outside the app via Safari [12][13].

---

## Licence analysis and recommendation

Evaluation criteria, in the order I weighted them: (a) can we ship on the App Store without
a legal cloud; (b) does it stop a competitor shipping a closed paid clone; (c) express
patent grant; (d) does it preserve the option of a paid binary or dual-licence; (e) will
Swift/Apple-ecosystem contributors recognise it.

| Licence | Pros | Cons | App Store viability | Verdict |
|---|---|---|---|---|
| **MIT** | Maximum familiarity; ~1 page; zero friction; dominant in Swift ecosystem | **No express patent grant**; zero clone protection — HealthyApps or anyone else can take the whole codebase, close it, and sell it; no attribution beyond a copyright line in practice | Clean. No conflict with Apple's minimum EULA terms [10] | **Reject.** Gives away the one asset (the code) with nothing back, and the brief explicitly asks whether a competitor could ship a closed clone. Under MIT the answer is "yes, trivially" |
| **Apache-2.0** | Express patent grant (§3) with retaliation termination; explicit NOTICE/attribution mechanics; corporate-friendly; well understood; the safe default for reusable libraries | No copyleft — same clone exposure as MIT; longer text; GPLv2 incompatibility (irrelevant here unless we take a GPLv2 dependency) | Clean | **Adopt for standalone reusable packages only.** Correct licence for anything we want other people's apps to embed |
| **MPL-2.0** | **File-level copyleft**: modify our files, publish those files; add proprietary files freely. Express patent grant (§2.1(b)) + patent retaliation (§5.2). §3.2 explicitly permits distributing executables under other terms. §3.3 permits combining with proprietary code in a Larger Work. No "no further restrictions" clause — nothing to collide with Apple's EULA minimum terms. Built-in upgrade path to later MPL versions (§10.2) reduces relicensing pressure | Less familiar to Swift-ecosystem contributors than MIT/Apache; per-file boundary is a genuinely subtle concept people get wrong; weaker deterrent than GPL against a "wrap it in a proprietary shell" clone | **Clean, and precedented.** MPL is the licence VLC ended up under when it returned to the App Store in 2013 [3] | **✅ Adopt for the app and first-party modules.** Best available trade between clone deterrence and App Store cleanliness |
| **GPL-3.0** | Strongest realistic clone deterrence: a competitor must open their whole app; anti-tivoisation; express patent grant (§11); §7 additional-terms machinery gives an arguable route through store terms [15] | §10 "no further restrictions" collides with Apple's *current* minimum EULA terms, which mandate a "**non-transferable** license to use the Licensed Application on any Apple-branded Products that the End-User owns or controls" [10]. Also forecloses any future dual-licence or proprietary edition without unanimous contributor consent. Deters some corporate contributors | **Viable in practice, cloudy in law.** Many GPL-3.0 apps ship today [16][18][19]. Risk is a copyright-holder complaint, not Apple review | **Reject for the app**, but note this is the *right* answer if the user's priority is maximal copyleft and they accept the residual cloud. Revisit only with **[LEGAL ADVICE]** |
| **AGPL-3.0** | Everything GPL-3.0 has, plus closes the network-service loophole — relevant if a companion/self-hosted server is ever built | Same App Store cloud as GPL-3.0; materially more contributor-hostile (many employers blanket-ban AGPL); §13 network clause is close to meaningless for an on-device iOS app that has no network service | Same as GPL-3.0. Ice Cubes ships AGPL-3.0 on the App Store today [17] | **Reject for the app.** Consider **only** if a hosted companion server is later built, and only for that server |

### Recommended split

| Component | Licence | Why |
|---|---|---|
| App targets (iOS / iPadOS / macOS / watchOS) and first-party modules | **MPL-2.0** | Clone deterrence + patent grant + App Store clean |
| Genuinely reusable standalone Swift packages (e.g. a HealthKit query wrapper, an export-format encoder) | **Apache-2.0** | We *want* other apps to embed these. Copyleft here suppresses the adoption that gives the project relevance. Apache-2.0 code combines into an MPL-2.0 work without friction |
| Documentation, ADRs, PRD | **CC BY 4.0** | Software licences are a poor fit for prose |
| Export schemas, JSON/CSV/GPX examples, integration samples | **CC0-1.0** | These are interoperability surface. Any friction here defeats the purpose; a self-hoster copying a schema fragment should never have to think about it |

**Reversibility.** Loosening is easy; tightening is not. Going MPL-2.0 → Apache-2.0/MIT later
needs consent from every copyright holder whose code is still present. Going
Apache-2.0 → MPL-2.0 later has the same problem. This is why VLC needed to chase ~150
contributors and only got ~230 agreements across the whole effort, with unrelicensable code
left behind [1][2]. **Treat the licence as a one-way door and get explicit user sign-off.**

---

## The GPL / App Store question (researched, not folklore)

The folklore version is "Apple bans the GPL". That is false. Here is what actually happened
and what is actually true today.

**What happened.** VLC for iOS was published in September 2010 by Applidium. In October
2010 Rémi Denis-Courmont, a VLC copyright holder who had *not* consented, sent Apple a
formal copyright infringement notification asserting that the App Store's usage rules
contradicted the GPL. Apple pulled the app in January 2011 [4][5]. **Apple did not object to
the licence.** Apple responded to a takedown demand from a rights holder — the same
mechanism that removes any allegedly infringing app.

**What the actual legal conflict is.** GPLv2 §6 and GPLv3 §10 forbid a distributor imposing
"further restrictions" on downstream recipients. The FSF's 2010 analysis targeted the
then-current iTunes Store usage rules, particularly the five-device storage limit [4][6].
Those specific terms have since changed. The live conflict in **2026** is different and
narrower, and I verified it directly against Apple's current published document rather than
relying on secondary sources: Apple's *Minimum Terms of Developer's End-User License
Agreement*, clause 2, requires that "The license granted to the End-User for the Licensed
Application must be limited to a **non-transferable** license to use the Licensed Application
on any Apple-branded Products that the End-User owns or controls" [10]. Clause 1 additionally
forbids the developer's EULA from providing usage rules that conflict with the Apple Media
Services Terms. A non-transferable, Apple-hardware-limited licence is on its face a further
restriction that GPL §10 does not permit. (Fetched 2 September 2026.)

**What is true in practice.** Apple does not police licences. Copyleft apps ship on the
App Store right now:

| App | Licence | Evidence |
|---|---|---|
| Ice Cubes (Mastodon client) | **AGPL-3.0** | [17] |
| Passepartout (VPN client) | GPL-3.0 | [18] |
| Blink Shell | GPL-3.0 | [16] |
| YourPods (podcast client, **paid binary, free source**) | GPL-3.0 | [19] |

YourPods is worth noting for a separate reason: it is a working instance of exactly the
model the brief asks about — GPL-3.0 source on GitHub, paid binary on the App Store, with
"build it yourself" documented as the free alternative [19].

**The correct conclusion.** The risk under a copyleft licence is not rejection by Apple. It
is that **a single copyright holder can force removal**, and under a DCO regime every
contributor is a copyright holder. This couples the licence decision to the
contribution-intake decision:

- Copyleft + DCO = every contributor holds a veto over App Store distribution.
- Copyleft + CLA = the project holds all rights and can consent to its own distribution,
  which collapses the practical risk to near zero.
- MPL-2.0 (either way) = no "further restrictions" clause exists, so the conflict does not
  arise at all.

Two further factors that did not exist in 2011 and weaken the old analysis: since 2015
anyone can build and install on their own device with a free Apple ID, and since the EU
Digital Markets Act, alternative app marketplaces can distribute under their own terms
[15][14]. Both give a GPL-clean distribution route that coexists with an App Store listing.

**[LEGAL ADVICE]** — if the user overrides me and wants GPL-3.0 or AGPL-3.0 on the App
Store, get an opinion first. It is a defensible position, it is demonstrably survivable, but
it is not something to walk into on the strength of a blog post or this document.

---

## Contribution intake: CLA vs DCO

| | CLA | DCO |
|---|---|---|
| Mechanism | Separate signed agreement, once per contributor (+ employer) | `Signed-off-by:` trailer per commit, `git commit -s` |
| Express patent grant | Yes (Apache ICLA style) | No |
| Enables relicensing | Yes | No — needs unanimous consent |
| Friction | High; measurably suppresses drive-by contributions | Near zero |
| Norm in this ecosystem | Corporate-stewarded projects | Linux kernel, CNCF, Git, most indie Swift projects |
| Tooling | cla-assistant.io (free, SAP-backed), EasyCLA | DCO GitHub App / GitHub Action |

Source for the comparison and tooling: [23][24][25].

**Recommendation: DCO 1.1, enforced by a bot, no CLA.** Reasoning:

- A CLA on a solo-founder project reads as "the founder is preparing to take this
  commercial". That is precisely the suspicion the market analyst says is the strongest
  objection to an OSS alternative, and a CLA feeds it.
- The main thing a CLA buys — relicensing ability — is largely neutralised by choosing
  MPL-2.0, because MPL §10.2 already lets the project move to later MPL versions without
  contributor consent, and because MPL creates no App Store conflict that would need curing
  by relicensing.
- A CLA on a project with, realistically, single-digit early contributors buys little and
  costs the contributions that make the project look alive.

**The honest counter-argument, stated plainly:** if the user thinks there is more than
roughly a one-in-five chance of a future dual-licence, commercial edition, or acquisition,
take the CLA **now**. Retrofitting one is the most expensive governance mistake available:
VLC's relicensing took over a year, required chasing every contributor individually, and
left code behind that could not be relicensed [1][2]. This is a genuine fork in the road and
belongs to the user, not to me.

**Mechanism if DCO is adopted:** `Signed-off-by` required on every commit; DCO check as a
required status check on `main`; `CONTRIBUTING.md` states inbound licence = outbound licence
explicitly; `GOVERNANCE.md` records that any licence change requires consent of all
copyright holders. That last sentence costs nothing now and prevents a future maintainer
from assuming they can relicense.

**Reversibility:** DCO → CLA is a hard, expensive change (must chase every prior
contributor). CLA → DCO is trivial. Asymmetric, and it favours starting with the CLA if you
are genuinely unsure — which is why this needs user sign-off rather than my preference.

---

## Governance model and bus-factor mitigation

**Recommendation: documented BDFL with a written succession plan, converting to a
maintainer team of ≥2 within 6 months of public launch.** A foundation is disproportionate —
it costs money, adds process, and buys credibility the project has not yet earned. A
maintainer team from day one is aspirational: there is no team yet.

The market analyst is finding that "this will be abandoned" is the strongest objection to an
OSS alternative. The answer to that objection cannot be a paragraph of intent. It has to be
mechanically verifiable by a sceptic reading the repo. Concretely:

1. **The Apple account is the real bus factor, not the git repo.** Verified against Apple's
   documentation: an individual enrolment cannot have a team; users added to App Store
   Connect under an individual account "are not considered part of your team", and
   Certificates, Identifiers & Profiles access is restricted to Account Holders and members
   of an *organization's* team [20]. So under individual enrolment a second maintainer
   cannot sign or ship a build. Organization enrolment requires a recognised legal entity
   and a D-U-N-S number; sole proprietorships do not qualify [21][22]. Converting later is
   possible via Apple Developer Support plus an App Transfer, but it is a support-ticket
   process, not a self-service one [21].
2. **Everything except signing must be reproducible by a stranger.** If the founder
   disappears, someone must be able to fork, build, and ship a renamed binary from a clean
   machine without asking anyone anything.
3. **A stated dormancy trigger.** A public, dated commitment ("if no maintainer response
   for 90 days, the project is declared dormant and the archive/handover procedure runs")
   is worth more to a sceptical evaluator than any amount of roadmap.

Requirements OSS-11 to OSS-14 below make these testable.

**Reversibility:** governance is the *cheapest* thing here to change. BDFL → maintainer team
→ fiscal host → foundation is a well-trodden escalation path and each step is reversible in
practice. Do not over-engineer it now.

---

## Required repository artifacts

Everything below is a Stage 1 *requirement*. The PM decides what gets created and when.
"Norm" vs "obligation" is called out per row, because conflating them is how projects end up
doing compliance theatre.

| Artifact | Purpose | Acceptance criteria |
|---|---|---|
| `LICENSE` (+ `LICENSES/` dir) | The actual grant. Nothing else in this table matters if this is wrong | Verbatim MPL-2.0 text at repo root, unmodified. `LICENSES/` contains verbatim text for every SPDX identifier used anywhere in the tree. GitHub's licence detector correctly identifies the repo as MPL-2.0 |
| `README.md` | First and usually only thing anyone reads | Contains: one-line description; platform support matrix; licence badge; build-from-source instructions verified on a clean machine; explicit "what this project deliberately does not do"; links to `CONTRIBUTING`, `SECURITY`, `SUPPORT`, `CODE_OF_CONDUCT` |
| `CONTRIBUTING.md` | Contribution mechanics and the inbound licence statement | States DCO requirement with a copy-pasteable `git commit -s` example; states inbound licence = outbound licence explicitly; describes branch/PR/review flow; states expected review latency; links to `GOVERNANCE.md` |
| `CODE_OF_CONDUCT.md` | Community norm. **Not a legal obligation** | Contributor Covenant, verbatim, current version at adoption time, with the enforcement contact filled in. **Enforcement owner named as a real reachable address, not "the maintainers".** An unenforced CoC is worse than none: it advertises a promise the project cannot keep |
| `SECURITY.md` | Vulnerability intake. Norm today; becomes load-bearing if CRA scope is ever triggered | Names a private reporting channel; GitHub private vulnerability reporting **enabled** on the repo; states a target initial-response time (OpenSSF Best Practices requires ≤14 days [26][27]); states disclosure policy and embargo expectations; linked from `README` |
| `SUPPORT.md` | Deflects support load away from the issue tracker; sets expectations honestly | States what is and is not supported; states that support is best-effort by volunteers; routes questions to Discussions and bugs to Issues |
| Issue templates | Make bug reports actionable; **critical for a health app** — reports will otherwise contain personal health data | Separate bug / feature / question forms. Bug form has explicit fields for OS version, device, app version. **Prominent warning not to paste real health data**, with instructions for redaction |
| PR template | Reviewer checklist | Checkboxes for: DCO signed, tests added, docs updated, changelog fragment added, no new dependency without licence check |
| `CODEOWNERS` | Routes review; makes ownership legible | Every top-level path has an owner. Reviewed whenever the maintainer set changes |
| Branch protection on `main` | Prevents the founder from accidentally becoming the only thing standing between a bad commit and users | Linear history; ≥1 approving review; required status checks: build, tests, DCO, licence scan; no force-push; no deletion. Admin bypass **disabled** once there are ≥2 maintainers |
| `CHANGELOG.md` | The single artifact users check to judge whether a project is alive | Keep a Changelog format; every user-visible change lands with a changelog fragment in the same PR; a release is not a release without one |
| SemVer policy (in `CONTRIBUTING` or `VERSIONING.md`) | Makes breaking changes predictable, which matters for the export formats self-hosters build against | SemVer 2.0.0. **Explicitly defines what the public API is** — for this project the export schema and any TCP/REST contract are public API, so a schema field removal is a major bump even if no Swift symbol changed |
| `NOTICE` / third-party attribution | Attribution obligations from permissive licences are **legal obligations**, not norms | Generated, not hand-written. Covers every shipped dependency. Rendered in an in-app "Acknowledgements" screen. Regenerated in CI; CI fails if stale |
| `MAINTAINERS.md` | Who decides, who can be contacted, what the succession plan is | Lists each maintainer with GitHub handle, scope, and contactable address. Contains the dormancy/handover procedure. Reviewed quarterly. Preferred over `AUTHORS` — `AUTHORS` is a contributor list, generated from git history, and carries no governance meaning |
| `GOVERNANCE.md` | Answers "what happens if the founder stops" in writing | Documents decision-making, how maintainers are added/removed, the licence-change rule, and the dormancy trigger |
| REUSE / SPDX headers | **Norm becoming near-obligation.** Not required by any statute I found, but it is the cheapest possible path to a defensible SBOM and licence audit | REUSE Specification 3.3 compliance [28][29]: `SPDX-FileCopyrightText` + `SPDX-License-Identifier` header in every source file; `reuse lint` passes in CI. Adopting this at commit one costs nothing; retrofitting it across thousands of files costs days |
| SBOM generation | **Not currently a legal obligation for this project** (see CRA section). Becomes one if we ever charge | CI produces an SPDX 2.3+ or CycloneDX 1.6+ SBOM per release, machine-readable, attached to the GitHub release. Covers at minimum top-level dependencies — the CRA floor [30][31][32] |

On SBOM specifically, because the brief asks whether it is becoming an obligation: **yes,
but not yet for us.** CRA Annex I Part II(1) requires an SBOM "in a commonly used and
machine-readable format covering at the very least the top-level dependencies", it sits in
the *technical documentation* and need not be published (recital 77), and it becomes
enforceable on 11 December 2027 — and only for products in scope [30][31]. No format is
mandated; Article 13(24) reserves that to a future implementing act that does not yet exist
[30][32]. Doing it now is cheap insurance, not compliance.

---

## Regulatory exposure: EU CRA and friends

### Status as of 2 September 2026

Regulation (EU) 2024/2847 entered into force 10 December 2024. Phase-in [31][33]:

| Date | What applies | Status today |
|---|---|---|
| 11 Jun 2026 | Ch. IV — notification of conformity assessment bodies | In effect |
| **11 Sep 2026** | **Art. 14 — reporting of actively exploited vulnerabilities and severe incidents; ENISA Single Reporting Platform live** | **9 days away** |
| 11 Dec 2027 | Full application: Annex I essential requirements, conformity assessment, CE marking, technical documentation, enforceable SBOM | Scheduled |

Art. 14 reporting deadlines are 24h early warning / 72h notification / 14 days final report
for vulnerabilities. Critically, it is not retroactive to knowledge acquired before
11 September 2026 [33].

### Does this project fall in scope?

The chain of reasoning, each step cited:

1. A mobile app downloaded from an app store **is** a "product with digital elements"
   [8, Example 3]. So we do not escape on the "it's just software" argument.
2. The CRA only bites on products "placed on the market", which requires supply **in the
   course of a commercial activity** [8, §2.1].
3. Publishing FOSS source on a public repository is generally **not** placing it on the
   market [8, ¶23]. So the GitHub repo alone is out of scope regardless.
4. For the shipped app: "the provision of products with digital elements qualifying as free
   and open-source software that are **not monetised** by their manufacturers should not be
   considered to be a commercial activity" (CRA recital 18, quoted at [8, ¶42]).
5. **On donations — this is the finding that matters and it is recent.** Draft Commission
   guidance C(2026) 5252 of 27 July 2026, ¶61: "The mere fact of including a link to a
   donation platform or similar tools to collect donations should not be viewed as an
   intention to make a profit, **even where the amount collected via donations exceeds the
   mere costs** associated with the design, development and provision of a product with
   digital elements. This includes… a natural person's reasonable living expenses… A FOSS
   supported only through donations is therefore unlikely to be considered to be placed on
   the market within the meaning of the CRA." [8]

   This is materially more permissive than CRA recital 15 read alone, which conditions the
   carve-out on donations "not exceeding costs". Most commentary still repeats the recital-15
   framing. **Flagged as draft guidance**: C(2026) 5252 is a Commission draft dated
   27 July 2026 and I could not confirm from the sources available today whether it has been
   formally adopted in final form. Treat as strong indicative guidance, not settled law.
6. ¶62 draws the line: donations become commercial activity where they are "de facto
   equivalent to charging a price" — e.g. access to the software, essential functionality,
   or *updates* is conditioned on donating. **This directly constrains product design**: a
   "donate to unlock" or "supporters get builds first" mechanic would plausibly push the
   project into CRA scope. See hard constraints.
7. Third-party sponsorship or paid feature work does **not** create scope, provided the
   result is openly published [8, ¶63–65, Example 23].

**Conclusion: out of scope while the app is free, published by an individual, and funded
only by donations/sponsorship.** Note also ¶53: where the publisher is a *natural person*,
the free community version is outside CRA scope entirely — whereas a *legal person* still
picks up steward obligations. **Incorporating a nonprofit to improve the bus factor could
therefore pull the project into Article 24 steward obligations that it does not have today.**
That is genuinely counterintuitive and the PM should know it before treating incorporation
as a free win. Note that "steward" is defined as a *legal person* [7][8, ¶47]; an individual
maintainer cannot be one.

### What changes if we charge money

Charging a price for the App Store binary = commercial activity = placed on the market =
we are a **manufacturer**, not a steward, with the full Annex I essential requirements,
conformity assessment, CE marking, technical documentation retained 10 years, a declared
support period, and Art. 14 reporting — from 11 December 2027, with fines attached. Stewards
are expressly exempt from administrative fines; manufacturers are not [7].

**[LEGAL ADVICE] — this is the single most consequential legal question in the document.**
Do not charge for the binary without an opinion on CRA scope.

Open question I could not resolve: whether Apple is a CRA *distributor* or *importer* for
apps sold through the App Store, and what that pushes onto developers contractually. Not
addressed in the guidance I read.

### EU Digital Services Act — this one already applies

Since **17 February 2025**, Apple requires every developer account to declare DSA trader
status, and apps without it are removed from the EU App Store [11]. Traders must supply an
address, phone number and email, which Apple **publishes on the App Store product page** in
all 27 EU territories [34]. A non-trader declaration is still required even for accounts not
distributing in the EU [34].

For a solo maintainer this is a personal-safety issue, not a paperwork issue: a free app with
no monetisation should qualify as non-trader, but accepting money can flip the analysis.
Apple confirms individuals may use a **P.O. Box** rather than a home address [34]. This
should be settled before first submission, not after.

### Other regimes touched but not owned by me

- **GDPR** — health data is Article 9 special category. On-device-only processing with no
  controller relationship is the strong position; the observability/OpenTelemetry
  differentiator in the brief threatens it directly. Owned by the privacy lead; flagged here
  because it interacts with the "no account, no tracking" positioning.
- **EU MDR / medical device classification** — an app that exports data a user already has,
  making no diagnostic or therapeutic claim, is very unlikely to be a medical device. But
  "very unlikely" is doing work, and marketing copy is what usually breaks it. **[LEGAL
  ADVICE]** if any claim beyond "moves your data" is ever made.
- **US** — no federal SBOM mandate applies to a consumer app; FDA 524B applies to cyber
  devices, not to us [31].

---

## Trademark and brand mechanics

The mechanics, which are widely misunderstood:

- **An open source licence grants copyright and sometimes patent rights. It grants no
  trademark rights.** Apache-2.0 says so expressly (§6); MPL-2.0 §2.3(c) likewise. This is
  the standard position, not a quirk [35][36][37].
- **Registration is not ownership.** Trademark rights arise from use in trade; registration
  confers presumptions and remedies, not existence [35][37].
- **A forker may take all of the code and none of the name.** They must rebrand. They may
  factually state their software is "a fork of X" — nominative/descriptive use is permitted
  in the EU under Arts. 14–15 of Regulation (EU) 2017/1001 where consistent with honest
  practices — but they may not name their product X, register X as a mark, or use the logo
  [38].
- **Not policing dilutes the mark.** A trademark held and never enforced weakens toward
  unenforceability [36].

### Recommendation

1. **Do a clearance search before the name is committed** — USPTO TESS, EUIPO eSearch, App
   Store name availability, npm/GitHub/domain. Cheap, and the only step that is genuinely
   urgent. The marketing manager is choosing the name; this check must gate that choice, and
   it must include a check that the name does not incorporate an Apple mark ("Apple Health",
   "HealthKit", "iOS" and similar in a product name will be rejected).
2. **Publish a trademark policy from day one, based on the Model Trademark Guidelines**
   (CC BY 3.0 template, free) [35]. Costs an afternoon. It is what lets you tell a forker to
   rebrand without it looking arbitrary.
3. **Do not register initially.** EUIPO is €850 for the first class, USPTO from $350/class,
   plus renewals [35]. That is not a good use of early money for a project with no revenue.
4. **Register when a trigger fires**: someone ships a confusing clone; the project takes
   money; a company wants to distribute it. Registration remains available later — this is
   the *most* reversible decision in the document, with the sole exception that the name
   itself gets harder to change the longer you wait.

**Reversibility:** trademark strategy is cheap to change; the **name** is not. Renaming after
an App Store launch costs the listing's reviews, ranking, and inbound links.

---

## Sustainability and funding

What Apple's rules actually permit, verified:

| Route | Apple's rule | Verdict |
|---|---|---|
| Donations collected **in-app** | **Prohibited** unless you are an Apple-approved nonprofit. Guideline 3.2.2(iv): apps raising money "must be free on the App Store and may only collect funds outside of the app, such as via Safari or SMS" [12][13] | Not available |
| Apple-approved nonprofit + Apple Pay | Permitted under 3.2.1(vi), but requires Apple's own nonprofit approval — US entities need a Candid Seal of Transparency, non-US apply via Benevity. IRS 501(c)(3) status alone is not sufficient [12][13] | Disproportionate |
| **Link out to GitHub Sponsors / Open Collective, opened in Safari** | Permitted. This is the express escape hatch in 3.2.2(iv) | **✅ Recommended** |
| Paid App Store binary, source free | Permitted; no licence we are considering forbids charging. Working precedent: YourPods, GPL-3.0, paid binary, free source [19] | Available — but triggers CRA manufacturer scope. **[LEGAL ADVICE]** |
| External purchase links for digital goods | US storefront only, post-*Epic* injunction. Commission is currently **0%**; Apple proposed 15% (5% for Small Business Program) on 13–14 August 2026, pending district court approval. Ninth Circuit largely affirmed contempt on 11 Dec 2025 but vacated the total commission ban; Supreme Court granted cert 30 June 2026 on a narrow contempt question, decision expected 2027. Outside the US this generally still requires the StoreKit External Purchase Link Entitlement [39][40][41][42] | **Unstable. Do not build a funding model on it** |

### The realistic funding story

Be honest with the PM: for a privacy-focused health-data utility with a small addressable
audience, GitHub Sponsors and Open Collective will plausibly cover the Apple Developer
Program fee ($99/yr) and hosting, and not much more. The realistic model is:

1. **Free app, donation link that opens in Safari.** Compliant, zero regulatory
   consequence under the CRA analysis above, and the position that best supports the
   "genuinely open source, not a funnel" positioning.
2. **Open Collective with a fiscal host** if donations become non-trivial — it gives
   transparent accounting without incorporating, and transparent accounting is itself an
   answer to the abandonment objection.
3. **Paid binary only as a deliberate, later, legally-advised decision** with the CRA
   consequences priced in.

**Critical design constraint that follows from ¶62 of the Commission guidance:** do not make
donations a condition of access, functionality, or updates. "Supporters get TestFlight
builds first" is exactly the pattern that ¶62 describes as de facto charging a price, and it
would plausibly pull the project into CRA scope for a trivial amount of money [8].

**Reversibility:** funding model is easy to change. Adding a paid tier later is
straightforward; removing one after users have paid is not.

---

## Third-party dependency licence policy

A health-data app moves Article 9 special-category data. Dependency provenance is a security
requirement here, not just a licensing one.

**Allowlist (auto-approve):** MIT, Apache-2.0, BSD-2-Clause, BSD-3-Clause, ISC, MPL-2.0,
Zlib, CC0-1.0, Unlicense, and Apple's own frameworks.

**Review required (maintainer approval, recorded in the PR):** LGPL-2.1/3.0 (static linking
into an App Store binary reproduces the relinking problem that LGPL relicensing did not solve
for VLC [1][6] — dynamic linking on iOS is constrained, so treat LGPL as effectively
denylisted for shipped app code); EPL-2.0; CDDL; anything dual-licensed; anything with a
custom or modified licence text.

**Denylist (never, without an explicit written maintainer decision):** GPL-2.0, GPL-3.0,
AGPL-3.0 in shipped app code — incompatible with an MPL-2.0 outbound licence and reintroduces
the App Store cloud we chose MPL to avoid; SSPL, BUSL, Elastic License, Commons Clause, and
any other source-available-but-not-OSI licence; **no licence at all** (a repo with no
`LICENSE` file grants nothing — "it's on GitHub" is not a licence); AI-generated code of
unknown provenance pasted from an unattributed source.

Build-time-only tooling that is not distributed (linters, formatters, generators) may use a
wider set, since we are not conveying it — but this must be an explicit, documented carve-out
rather than an assumption.

**Attribution.** Generate `NOTICE` and the in-app Acknowledgements screen from the dependency
graph in CI. Fail the build if stale. Hand-maintained attribution files are always wrong
within three months.

**Provenance.** Every dependency pinned to an exact version; `Package.resolved` committed;
SPM dependencies resolved from a named upstream (no unpinned branch references, no forks
without a recorded reason); a new dependency requires a PR that states what it does, why a
first-party implementation was rejected, its licence, and its maintenance signal.

**Handling a dependency that changes licence** — a recurring event (HashiCorp→BUSL,
Elastic, Redis, Sentry, MongoDB), so this needs a procedure, not improvisation:

1. A licence change is not retroactive. The last release under the old licence remains under
   the old licence. **Pin there immediately** — this buys time and is always the correct
   first move.
2. Assess: is the new licence on the allowlist? Is there a community fork (there usually is —
   OpenTofu, Valkey, OpenSearch)? Is the dependency replaceable, or is it load-bearing?
3. Decide within 90 days, record the decision as an ADR, and communicate it in the changelog.
   Users of a health app deserve to know when the supply chain shifts under them.
4. Never silently upgrade across a licence change. CI must detect the change and fail.

---

## Requirements I own

| ID | Requirement | Priority | Rationale | How we verify |
|---|---|---|---|---|
| OSS-01 | App and first-party modules licensed MPL-2.0; verbatim `LICENSE` at repo root present in the first commit | **Must** | App Store clean, express patent grant, file-level copyleft deters closed clones. Irreversible in practice | GitHub licence detection reports MPL-2.0; `LICENSE` byte-identical to the canonical text |
| OSS-02 | Reusable standalone Swift packages licensed Apache-2.0; docs CC BY 4.0; schemas and example payloads CC0-1.0 | **Should** | Adoption of shared components is the point; copyleft on interop schemas defeats the self-hoster differentiator | Each package directory contains its own `LICENSE`; `reuse lint` passes |
| OSS-03 | No GPL-family licence adopted for App Store-distributed code without a written legal opinion | **Must** | Apple's minimum EULA terms mandate a non-transferable, Apple-hardware-limited licence, which collides with GPL §10 [10] | Decision recorded as an ADR citing the opinion, or licence is non-GPL |
| OSS-04 | DCO 1.1 required on every commit, enforced as a required status check | **Must** | Provenance of contributions must be auditable; near-zero contributor friction | A PR without `Signed-off-by` cannot merge to `main` |
| OSS-05 | `CONTRIBUTING.md` states inbound licence = outbound licence explicitly; `GOVERNANCE.md` states licence change requires consent of all copyright holders | **Must** | Removes the ambiguity that makes future relicensing or dual-licensing legally messy | Both statements present and reviewed at each maintainer change |
| OSS-06 | No CLA unless the user signs off on a future dual-licence/commercial intent | **Should** | A CLA on a solo project signals commercial intent and suppresses contribution; but retrofitting one later is very expensive | Explicit recorded user decision before first external PR is merged |
| OSS-07 | Repository ships `README`, `CONTRIBUTING`, `CODE_OF_CONDUCT`, `SECURITY.md`, `SUPPORT.md`, `GOVERNANCE.md`, `MAINTAINERS.md`, `CHANGELOG.md`, issue/PR templates, `CODEOWNERS` before public announcement | **Must** | Credibility floor for an OSS project handling health data | All files present; each satisfies its acceptance criteria in the artifacts table |
| OSS-08 | Code of Conduct is Contributor Covenant with a named, reachable enforcement contact | **Must** | An unenforceable CoC is worse than none — it advertises a promise the project cannot keep | Enforcement contact is a working address a test message reaches |
| OSS-09 | GitHub private vulnerability reporting enabled; `SECURITY.md` states a ≤14-day initial-response target and disclosure policy | **Must** | Health data. Also the mechanism CRA Art. 14 reporting would run through if scope is ever triggered [26][27][33] | Private reporting enabled in repo settings; a test report is acknowledged within target |
| OSS-10 | Branch protection on `main`: ≥1 approving review, required checks (build, test, DCO, licence scan), linear history, no force-push | **Must** | Prevents the founder becoming a single point of unreviewed failure | Settings audit; a force-push attempt is rejected |
| OSS-11 | Build-from-source is reproducible by a stranger with no project-specific credentials, verified on a clean machine each release | **Must** | The primary bus-factor mitigation and the GPL-style "user freedom" answer without the GPL | CI job builds from a fresh clone on a clean runner; documented steps followed by someone who has never built it |
| OSS-12 | Before public launch, a written succession plan in `MAINTAINERS.md`: dormancy trigger (90 days no maintainer response), handover procedure, and who to contact | **Must** | Directly answers the strongest market objection ("will this be abandoned") with something falsifiable | Document exists, is dated, and is reviewed quarterly |
| OSS-13 | Second maintainer with commit and release rights recruited within 6 months of public launch | **Should** | Bus factor of 1 is the credibility ceiling for an OSS alternative to a commercial product | A release is cut end-to-end by someone other than the founder |
| OSS-14 | Decision recorded on Apple Developer Program enrolment type (individual vs organization) with bus-factor implications stated | **Must** | Individual enrolment cannot share signing identities [20]; organization enrolment needs a legal entity + D-U-N-S [21][22]. This constraint is invisible until it bites | ADR recorded before first App Store submission |
| OSS-15 | REUSE Specification 3.3 compliance: SPDX headers in every source file; `reuse lint` in CI | **Should** | Cheap at commit one, expensive to retrofit; underpins any future SBOM or licence audit [28][29] | `reuse lint` exits 0 in CI |
| OSS-16 | Machine-readable SBOM (SPDX 2.3+ or CycloneDX 1.6+) generated per release and attached to the GitHub release | **Should** | Not currently a legal obligation for us, but is the CRA floor if scope is ever triggered [30][31][32] | SBOM artifact present on each release; validates against its schema |
| OSS-17 | Dependency licence policy enforced in CI with the allowlist/denylist above; new dependencies require a PR stating purpose, licence and maintenance signal | **Must** | Health data supply chain; also prevents accidentally poisoning the outbound licence | CI fails on a denylisted or unknown licence; test with a deliberate violation |
| OSS-18 | `NOTICE` and in-app Acknowledgements generated from the dependency graph in CI, failing the build if stale | **Must** | Attribution is a **legal obligation** under permissive licences, not a courtesy | Build fails when a dependency is added without regenerating |
| OSS-19 | Documented procedure for a dependency licence change: pin to last compatible release immediately, decide within 90 days, record an ADR, note in changelog | **Should** | A recurring industry event that reliably catches projects unprepared | Procedure documented; dry-run against a historical example |
| OSS-20 | Trademark clearance search (USPTO, EUIPO, App Store, domains, GitHub org) completed and passed before the name is committed to | **Must** | Renaming after launch destroys the App Store listing's accumulated value | Search results recorded and dated in the naming ADR |
| OSS-21 | Trademark policy published, based on Model Trademark Guidelines, stating what a forker may and may not call their build | **Should** | The licence grants no trademark rights; without a stated policy, enforcement looks arbitrary [35][36] | Policy published in repo and on the project site |
| OSS-22 | App remains free on the App Store; donations collected only outside the app via Safari link-out | **Must** | Apple 3.2.2(iv) forbids in-app donation collection for non-approved-nonprofits [12][13]; keeps the project outside CRA scope [8] | App Review approval; no in-app payment surface |
| OSS-23 | No functionality, update, or build access is ever conditioned on donating or sponsoring | **Must** | Commission guidance ¶62: donations that condition access are de facto a price, which places the product on the market and triggers CRA manufacturer obligations [8] | Feature-flag audit at each release: no sponsor-gated capability exists |
| OSS-24 | DSA trader status declared in App Store Connect before first submission, with a decision recorded on trader vs non-trader and on P.O. Box vs home address | **Must** | Mandatory since 17 Feb 2025; non-declaration means removal from the EU App Store. Contact details are published publicly [11][34] | Declaration complete in App Store Connect; address choice recorded |
| OSS-25 | Legal opinion obtained before (a) charging for the binary, (b) adopting any GPL-family licence for shipped code, or (c) incorporating an entity | **Must** | Each of these changes regulatory posture materially, and each is expensive to unwind | Written opinion on file, referenced from the relevant ADR |
| OSS-26 | Project does not adopt an OSI-non-approved "source-available" licence (BUSL, SSPL, Elastic, Commons Clause) at any point | **Won't** | "Genuinely open source" is differentiator #1 in the brief; a later rug-pull would destroy the only thing distinguishing us from the incumbent | Licence audit at each release |

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Licence chosen at Stage 1 turns out wrong at Stage 3; relicensing needs unanimous contributor consent | Medium | **High** — VLC needed a year and still had unrelicensable code left [1][2] | Force explicit user sign-off now (OSS-01); prefer MPL-2.0 whose §10.2 gives a built-in version-upgrade path; keep a clean copyright register from commit one |
| A contributor objects to App Store distribution and files a copyright complaint with Apple, as happened to VLC [4][5] | Low (MPL) / Medium (if GPL adopted) | **High** — app pulled | MPL-2.0 has no "no further restrictions" clause, so the conflict does not arise (OSS-01); `CONTRIBUTING.md` states distribution channels explicitly so no contributor is surprised (OSS-05) |
| Project is perceived as abandoned; users stay with the commercial incumbent | **High** | High — kills adoption regardless of code quality | Public dormancy trigger and succession plan (OSS-12); second maintainer (OSS-13); reproducible build so a fork is genuinely viable (OSS-11); visible changelog cadence |
| Founder becomes unavailable and the App Store listing cannot be maintained because signing identities are not shareable under individual enrolment [20] | Medium | **High** — users get no updates at all, including security fixes | Record the enrolment decision with eyes open (OSS-14); make source builds a first-class supported path (OSS-11); document the App Transfer route |
| Donations or sponsorship inadvertently pull the project into CRA manufacturer scope | Low | **High** — CE marking, conformity assessment, fines from Dec 2027 | Never gate anything on donations (OSS-23); keep the binary free (OSS-22); legal opinion before charging (OSS-25); re-check when the Commission guidance is finalised |
| Guidance C(2026) 5252 changes materially between draft and adoption, invalidating the ¶61 donations analysis | Medium | Medium | Treat the analysis as provisional; set a calendar review; do not build a funding model that depends on the most permissive reading |
| A dependency changes licence mid-project (BUSL/SSPL-style) | **High** over a multi-year horizon | Medium | Pin-and-assess procedure (OSS-19); CI licence gate (OSS-17); prefer dependencies with foundation governance |
| Name collides with an existing mark or an Apple trademark, forcing a rename after launch | Medium | High — loses App Store reviews, ranking, inbound links | Clearance search gates the naming decision (OSS-20) |
| A low-effort clone reskins the app and ships it on the App Store | Medium | Medium — reputational, and confuses users searching the store | MPL-2.0 forces publication of changes to our files (OSS-01); trademark policy plus Apple's guideline 4.1 copycat rule give a takedown route (OSS-21) |
| DSA trader disclosure exposes the maintainer's home address | Medium | Medium — personal safety | Decide trader status and use a P.O. Box deliberately before first submission (OSS-24) [34] |
| CLA omitted, then a commercial opportunity appears that requires relicensing | Low–Medium | High | Surface the decision to the user now rather than discovering it later; keep a complete contributor register so the chase is at least possible |

---

## Hard constraints that limit the product

Stated loudly, per the brief's rules of engagement.

1. **In-app donations are prohibited.** Apple guideline 3.2.2(iv): unless you are an
   Apple-approved nonprofit, you may not collect funds in-app; the app must be free and
   funds collected outside via Safari or SMS [12][13]. Any design that assumed a "support
   the project" purchase sheet is invalid.
2. **Nothing may be gated behind donating.** Not features, not updates, not early builds.
   Commission guidance ¶62 treats access conditioned on donation as de facto charging a
   price, which places the product on the market and triggers CRA manufacturer obligations
   [8]. This kills "sponsors get TestFlight early" as a growth mechanic.
3. **Charging for the binary changes the project's regulatory class.** Free → out of CRA
   scope. Paid → CRA manufacturer, with CE marking, conformity assessment, technical
   documentation, declared support period and fines from 11 December 2027 [8][31].
4. **Copyleft on the App Store carries an unresolved conflict with Apple's minimum EULA
   terms** (mandatory non-transferable, Apple-hardware-limited licence) [10]. Survivable in
   practice, but it means any contributor retains a de facto veto over distribution.
5. **An individual Apple Developer enrolment cannot share signing identities** [20]. The
   bus-factor ceiling is set by Apple's account model, not by our governance document.
   Raising it requires a legal entity and a D-U-N-S number [21][22].
6. **EU App Store distribution requires published trader contact details** since 17 February
   2025 [11][34]. There is no anonymous route to the EU App Store.
7. **LGPL dependencies are effectively unusable in the shipped app.** The relinking
   requirement is not satisfiable under iOS distribution constraints — the specific problem
   that LGPL relicensing failed to solve for VLC [1][6].
8. **External purchase links are an unstable foundation.** US-only, commission currently 0%
   but Apple has proposed 15%, pending court approval, with a Supreme Court decision
   expected in 2027 [39][40][41][42]. Do not design a business model around the current
   state.

---

## Open questions for the PM

1. **Licence sign-off.** MPL-2.0 for the app + Apache-2.0 for libraries — does the user
   accept, or do they want maximal copyleft (GPL-3.0) and the App Store cloud that comes
   with it? Effectively irreversible; needs an explicit answer, not silence.
2. **CLA or DCO.** I recommend DCO. But this is a bet on "no future dual-licence". If the
   user places that probability above ~20%, take the CLA now. Only the user can price that.
3. **Will the binary ever be paid?** The answer determines CRA exposure, the funding model,
   and whether a legal budget is needed. A "maybe later" answer is fine but must be recorded,
   because it changes what we build now.
4. **Individual or organization Apple enrolment?** Organization fixes the worst bus-factor
   problem but requires a legal entity, a D-U-N-S number and money, and may pull the project
   into CRA steward obligations it does not currently have.
5. **Is there a legal budget at all?** Three items warrant paid advice: charging for the
   binary (CRA), any GPL-family adoption, and any CLA text. If the answer is "no budget",
   the safe path is: MPL-2.0, DCO, free forever, donations outside the app — which is what I
   have recommended, and which is specifically chosen to be defensible without a lawyer.
6. **Who enforces the Code of Conduct, by name?** A solo project cannot credibly run an
   enforcement process against its own founder. Either name a second person, or say plainly
   in the document that enforcement is the founder's and accept the limitation.
7. **Does the marketing manager's naming work have my clearance requirement as a gate?**
   I need the naming decision to be blocked on OSS-20, not merely informed by it.
8. **Is a companion server in scope?** If yes, its licence is a separate decision (AGPL-3.0
   becomes genuinely relevant there in a way it is not for an on-device app) and I should
   contribute a follow-up.

---

## Sources

All URLs accessed 2 September 2026.

1. Relicensing VLC from GPL to LGPL — LWN.net — https://lwn.net/Articles/525718/
2. Jean-Baptiste Kempf, "How to properly(?) relicense a large open source project — part 3" — https://jbkempf.com/blog/How-to-properly-relicense-a-large-open-source-project-part-3/
3. FSF Licensing blog, "Left wondering why VLC relicensed some code to LGPL" — https://www.fsf.org/blogs/licensing/left-wondering-why-vlc-relicensed-some-code-to-lgpl
4. FSF, "More about the App Store GPL Enforcement" — https://www.fsf.org/blogs/licensing/more-about-the-app-store-gpl-enforcement
5. ZDNET, "No GPL Apps for Apple's App Store" — https://www.zdnet.com/article/no-gpl-apps-for-apples-app-store/
6. Hacker News discussion, "VLC Core is LGPL" (LGPL relinking under iOS) — https://news.ycombinator.com/item?id=4787965
7. OpenSSF Global Cyber Policy WG, "Linux Foundation Leadership CRA Stewards One Pager" — https://policy.openssf.org/CRA/stewards-one-pager.html
8. European Commission, draft guidance C(2026) 5252 final, 27 July 2026 — CRA guidance including §3 "Free and open-source software" (¶23, ¶42, ¶47, ¶53, ¶61, ¶62, ¶63–65, Examples 3, 13, 20, 21, 23) — https://www.juridice.ro/wp-content/uploads/2026/07/C_2026_5252_1_EN_annexe_acte_autonome_cp_part1_v3_kXuCPwXXxAuG8Uj44Ar0o2Vros_131456.pdf
9. Red Hat, "EU Cyber Resilience Act Stewardship Guidelines for Red Hat Supported Open Source Projects" — https://access.redhat.com/security/eu-cyber-resilience-act-stewardship-guidelines
10. Apple, "Instructions for Minimum Terms of Developer's End-User License Agreement" (clauses 1, 2, 5) — https://www.apple.com/legal/internet-services/itunes/dev/minterms/
11. Apple Developer, "DSA trader status required for apps in the EU" (since 17 Feb 2025) — https://developer.apple.com/news/upcoming-requirements/?id=02172025a
12. Apple, App Review Guidelines (§3.1.1, §3.2.1(vi), §3.2.1(vii), §3.2.2(iv)) — https://developer.apple.com/app-store/review/guidelines/
13. Apple Developer Forums, "Sending user outside app to pay" (§3.2.2(iv) applied) — https://developer.apple.com/forums/thread/124215
14. Apple Developer, "Operating an alternative app marketplace in the EU" — https://developer.apple.com/support/alternative-app-marketplace-in-the-eu
15. The App Fair Project, "The GPL and Commercial App Stores: Time for a Reconsideration" — https://appfair.org/blog/gpl-and-the-app-stores/
16. blinksh/blink — GPL-3.0, distributed on the App Store — https://github.com/blinksh/blink
17. Dimillian/IceCubesApp — **AGPL-3.0**, distributed on the App Store — https://github.com/dimillian/icecubesapp
18. partout-io/passepartout — GPL-3.0, distributed on the App Store — https://github.com/partout-io/passepartout/
19. asecretcompany/yourpods-source — GPL-3.0, **paid** App Store binary with free source — https://github.com/asecretcompany/yourpods-source
20. Apple Developer, "Apple Developer Program Roles" (individual accounts cannot have team members; Certificates/Identifiers/Profiles restricted to organization teams) — https://developer.apple.com/help/account/access/roles
21. Apple Developer, "Enrollment — Membership" (individual vs organization; conversion via Apple support) — https://developer.apple.com/help/account/membership/program-enrollment/
22. Apple Developer, "D-U-N-S Number" (legal entity required; sole proprietorships must enrol as individuals) — https://developer.apple.com/help/account/membership/D-U-N-S
23. "DCO vs CLA: Managing Contribution Agreements in Open Source" — https://tenthirtyam.org/dispatches/2026/04/08/dco-vs-cla-managing-contribution-agreements-in-open-source/
24. "Open Source Contributor License Agreements: A Compliance Review" — https://safeguard.sh/resources/blog/oss-contributor-license-agreements-review
25. TODO Group, "A Guide to Outbound Open Source Software" (DCO 1.1, CLA Assistant) — https://todogroup.org/resources/guides/a-guide-to-outbound-open-source-software/
26. OpenSSF, "Guide to implementing a coordinated vulnerability disclosure process for open source projects" — https://oss-vulnerability-guide.openssf.org/maintainer-guide.html
27. OpenSSF Best Practices badge criteria (`vulnerability_report_process`, `vulnerability_report_private`, ≤14-day response) — https://www.bestpractices.dev/en/projects/5621
28. REUSE Specification v3.3 — https://reuse.software/spec-3.3/
29. REUSE tutorial (SPDX-FileCopyrightText / SPDX-License-Identifier headers) — https://reuse.software/tutorial/
30. "CRA SBOM Requirements: Mandated, Optional, and Unclear" (Annex I Part II(1); Art. 13(24) implementing act not yet adopted; BSI TR-03183-2) — https://cra-decoded.com/blog/posts/004_cra_sbom_requirements/
31. Finite State, "Software Supply Chain Security Compliance: What Each Regulation Actually Demands" (CRA Annex I Part II(1), Art. 13(5), Art. 13(6); FDA 524B) — https://finitestate.io/blog/software-supply-chain-security-and-the-eu-cra-a-manufacturers-guide
32. OpenSSF, "SBOMs in the Era of the CRA: Toward a Unified and Actionable Framework" — https://openssf.org/blog/2025/10/22/sboms-in-the-era-of-the-cra-toward-a-unified-and-actionable-framework/
33. cyberresilienceact.eu, "CRA Reporting: 24h, 72h & 14-Day Deadlines (Article 14)" (Art. 14 applies 11 Sep 2026; Art. 24(3) stewards; not retroactive) — https://www.cyberresilienceact.eu/reporting.html
34. Apple, App Store Connect Help, "Manage European Union Digital Services Act trader requirements" (address/phone/email published; P.O. Box permitted for individuals) — https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements
35. Model Trademark Guidelines (CC BY 3.0 template) — http://modeltrademarkguidelines.org/index.php?title=Model_Trademark_Guidelines
36. Google Open Source, "Trademarks in Open Source" (casebook) — https://opensource.google/docs/casebook/trademarks
37. TermsFeed, "Protecting Your Brand in Open Source: Trademarks, Forks, and Enforcement Strategies" (USPTO/EUIPO fees) — https://www.termsfeed.com/blog/open-source-trademark/
38. NLnet / NGI0, "Q & A about Forks and Trademarks" (Arts. 14–15 Regulation (EU) 2017/1001) — https://nlnet.nl/NGI0/bestpractices/Forking_and_Trademarks.pdf
39. Mondaq, "Update Your App: External Purchase Developments For Apple & Google" (30 Apr 2025 contempt; 11 Dec 2025 Ninth Circuit; cert granted 30 Jun 2026) — https://www.mondaq.com/unitedstates/it-and-internet/1825852/update-your-app-external-purchase-developments-for-apple-google
40. TechCrunch, "Apple proposes to take a 15% cut of purchases made outside the App Store" (14 Aug 2026) — https://techcrunch.com/2026/08/14/apple-proposes-to-take-a-15-cut-of-purchases-made-outside-the-app-store/
41. MacRumors, "Apple Wants to Charge Developers Up to 15 Percent for Linking Outside the App Store" (13 Aug 2026) — https://www.macrumors.com/2026/08/13/app-store-fees-apple-link-outs/
42. AppStoreReview, "External Payment Links for Digital Purchases: What's Allowed in 2026" (US vs non-US; External Purchase Link Entitlement) — https://appstorereview.app/guides/app-store-external-payment-links-digital-purchases
43. Regulation (EU) 2024/2847 (Cyber Resilience Act), consolidated text — https://eur-lex.europa.eu/legal-content/EN/TXT/PDF/?uri=CELEX%3A02024R2847-20241120
44. Docker, "EU Cyber Resilience Act (CRA): Overview" (phase-in dates; steward category) — https://www.docker.com/blog/eu-cyber-resilience-act-overview/
