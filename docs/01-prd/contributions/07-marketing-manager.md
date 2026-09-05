# Marketing Manager — Stage 1 Contribution

> Stage 1 artifact. Everything here is expressed as a requirement or a constraint, not a campaign.
> Research current as of 2 September 2026. Load-bearing external facts are cited in **Sources**.
> Anything that is my judgement rather than a cited fact is labelled **[assumption]**.

## Executive summary

Four findings change what we should build.

**1. The category is much smaller than the brief implies.** Health Auto Export has been on the App Store
since May 2016 and has **389 US ratings** after ten years [S1]. Using a conventional 0.5–2 % rating rate,
that implies lifetime US downloads somewhere in the low tens of thousands, and a paying base smaller
still. This is a market of thousands of people, not millions. The honest positioning is *a niche tool for
a few thousand self-hosters*. That is a perfectly good outcome, and it should change the product: it
argues against chasing 150-metric parity, against a Mac analytics dashboard, and in favour of one
pipeline that never silently breaks.

**2. The "genuinely open source" wedge is already partly occupied.** `Health.md` shipped on the App Store
in February 2026: Swift, SwiftUI, HealthKit, AGPL-3.0, ~208 GitHub stars, currently 21 US ratings
[S2][S3]. It is the app-itself-is-open-source product the brief's differentiator #1 describes. We are not
first. We should stop treating "it's open source" as the wedge and start treating it as table stakes.

**3. Open source alone does not sell.** Health.md has been open source and on the store for seven months
and has 21 ratings; Health Auto Export is closed source and has 389 [S1][S2]. Health Auto Export also
already ships an open-source companion server and already claims a privacy-first, no-account, no-tracking
posture [S4]. Open source, privacy, and free are all either occupied, neutralised, or invisible to the
buyer.

**4. The wedge that survives contact is verifiability plus failure transparency**, not licensing. The
thing a closed-source competitor structurally cannot offer is: *you can see exactly where your data went,
the app produces a receipt proving it, it refuses to talk to anything you did not allow, and when the
pipeline breaks it tells the monitoring stack you already run.* That converts an abstract licence into a
feature a non-programmer can evaluate, and it is the brief's observability differentiator (#3) promoted
from a nice-to-have to the core of the value proposition.

The single biggest marketing-owned risk is not competition. It is the abandonment objection, and the only
honest answers to it are product requirements: bus factor greater than one, a published continuity plan,
and an output format that keeps working after we stop.

---

## Positioning and the wedge

### Positioning statement

> For self-hosters and quantified-self practitioners who already run their own infrastructure and want
> their Apple Health history inside it, **[NAME]** is an open-source health data exporter for iPhone,
> iPad, Mac and Apple Watch that moves HealthKit data to destinations you control and **proves it did**.
> Unlike closed-source exporters, the code that touches your health data is auditable, every export
> produces a receipt you can inspect, the app cannot reach any network destination you have not
> explicitly allowed, and every failure surfaces in the monitoring you already run.

### Value proposition (one line)

**Your health data, in your stack, with a receipt.**

### The wedges that actually work, ranked

**W1 — Verifiable egress (strongest).** The differentiator is not "you can read the source", because
almost nobody will. It is "you can prove where your data went and prove it went nowhere else." Concretely:
a per-export receipt (what left, how many samples, to which destination, at what time, with what result); a
user-configured network allowlist the app enforces and displays; a published mapping from each App Store
build to a source tag plus an SBOM. This is a claim a closed-source app cannot make and a claim that
existing OSS competitors have not made either. It is also the only version of "open source" that a
non-programmer can act on.

**W2 — Failure transparency.** The dominant failure mode in this category is the silent one: the
background export stops and the user finds out weeks later when the graph has a hole in it. Our audience
already runs Prometheus, Grafana, or Home Assistant. Expose "time since last successful export" as
something they can alert on, and ship the alert rule. Nobody in this category does this well.
**[assumption]** — inferred from the shape of the product, not from a survey; validate with the PM's
user-research contributor.

**W3 — No lock-in as a contract, not a slogan.** A published JSON Schema, a semver'd output contract, a
written deprecation policy, and full config export/import. "No lock-in" is only credible if the cost of
leaving is written down.

**W4 — Self-hoster-native distribution.** Ship the receiving end, not only the sending end: a Home
Assistant integration in the HACS default list, a Grafana dashboard in the community catalog, and a
one-command reference receiver. This is simultaneously a product requirement and the highest-yield
distribution channel we have (see Channels).

### Wedges that sound good and do not work

| Wedge | Why it fails |
|---|---|
| **"It's open source"** | Already claimed by a shipping competitor [S2]. The incumbent already ships an open-source companion server [S4]. On the App Store, the licence is invisible; the buyer sees a 4.3-star app with 389 ratings versus an unknown one. Necessary, not sufficient. |
| **"It's free"** | The incumbent's entry tier is a **$2.99 one-time purchase** and its lifetime tier is **$24.99** [S5]. Price is not the barrier for people who spend hundreds on a homelab. Worse, "free" is the answer that makes the abandonment objection *stronger*, because it implies nothing funds maintenance. |
| **"Privacy-first"** | The incumbent already advertises no account, no tracking, data stays on device [S4]. This is parity. We can only differentiate by making privacy *checkable* (W1), not by asserting it harder. |
| **"Swift 6, SwiftUI, strict concurrency"** | Invisible to users and to buyers. It is a quality bar and a contributor-recruitment argument, not positioning. Putting it in App Store metadata risks a 2.3.7 "unverifiable product claims" problem in the subtitle [S6]. |
| **"150+ metrics"** | A parity race we lose at v1, and Apple rejects apps that request HealthKit types they do not visibly use [S7]. Requesting 150 types to look competitive is an actual rejection risk. |
| **"Community-extensible / plugins"** | The population able and willing to write Swift plugins for an iOS health exporter is very small, and Guideline 4.7 constrains shipping non-embedded executable code [S6]. Extensibility should live in the *output format* and the *receiver*, not in the app. |
| **"An alternative to [competitor]"** | Cannot be said where it matters. Apple forbids referencing other apps in app names, subtitles, screenshots and previews, and reviewers read the hidden keyword field; 2026 enforcement can clear the entire field [S6][S8][S9]. Comparison content is legal on our own site only. |

### Honest market sizing

**[assumption, anchored on S1]** Realistic 12-month ceiling: 2,000–8,000 cumulative App Store units, of
which perhaps 200–800 run continuously against a self-hosted destination. If the PRD is written assuming
a larger outcome, the project will be judged a failure at exactly the point where it is succeeding.

---

## Naming analysis

Constraints that bind before taste does:

- App names are limited to **30 characters** and must be unique; metadata may not be packed with
  trademarked terms or popular app names [S6].
- **Apple filed `APPLE HEALTH` in four classes on 8 June 2026** (Classes 9, 41, 42, 44), and
  `WORKS WITH APPLE HEALTH` is a live Apple registration [S10][S11]. Apple's third-party guidelines
  forbid using any Apple word mark as part of a product name [S12].
- Guideline **5.2.5** forbids apps that appear confusingly similar to an existing Apple product, and
  specifically restricts Activity-ring-style visualisations of Move/Exercise/Stand [S6]. A red-heart-on-
  white icon is the single most obvious way to fail this.
- A generic descriptive name ("Health Export") is both crowded and legally unprotectable.

Availability signals below were gathered by querying the iTunes Search API (US storefront), the GitHub
users API, and RDAP on 2 September 2026. These are **signals, not a clearance search**; a formal
trademark clearance is a separate, mandatory step (MKT-01).

| Candidate | Rationale | Risks | Verdict |
|---|---|---|---|
| **Tributary** | Many streams flowing into a river you own — exactly the product. Distinct, spellable, no Health & Fitness collision. App Store: only unrelated Lifestyle apps and Spanish-language tax agencies. `github.com/tributary-app` free; `tributary.io` unregistered. | `tributary.app` / `.dev` registered. Reads as tax-adjacent in ES/PT/IT locales (*Agencia Tributaria*). 9 letters. No trademark clearance done. | **Recommended** |
| **Curlew** | A wading bird; outdoorsy, quiet, memorable, zero App Store collision (only a school district and an unrelated Lifestyle app). `github.com/curlewhq` and `getcurlew` free; `curlew.io`, `curlew.sh`, `curlewapp.com` unregistered. Cleanest availability profile of the set. | Weak semantic link to the product; needs the subtitle to do all the ASO work. Spelling/pronunciation friction for non-native English speakers. | **Fallback** |
| **Sluice** | A gate that controls flow — good metaphor for scheduled, user-controlled export. Short. No live US Class 9 registration found; prior Class 35 filing is dead. | Crowded in data tooling: at least two OSS projects already ship as "Sluice" (a CDC sync tool and an ETL toolkit). `sluice.app`, `sluice.dev`, `getsluice.com` all registered. An unrelated "Sluice" exists on the App Store (Business category). | Viable but crowded — third choice |
| **Aqueduct** | Moving a vital resource along infrastructure you built. | Multiple App Store Games collisions; historically a well-known Dart web framework; `aqueduct.app` registered. Long (8) and slightly grandiose. | Reject |
| **Marrow** | Bodily, distinctive, short. | Collides head-on with *Marrow*, a large medical-education app (Neuroglia Health), plus a Medical-category app. A Health & Fitness app named Marrow invites both confusion and 5.2.1 scrutiny [S6]. | Reject |
| **Open Vitals** | Descriptive; signals both openness and health. | An app literally named **Open Vitals** already exists in Health & Fitness — a direct 2.3.7 unique-name failure [S6]. "Open" as a prefix also markets the licence, which we established is not the wedge. | Reject |
| **HealthBridge / Health Export** | Maximum ASO keyword value. | Five near-identical App Store names, including **"HealthBridge: Health Export"** — direct collision. "Health" plus heart iconography sits closest to Apple's marks and the 5.2.5 confusability rule [S6][S10][S12]. Unprotectable as a mark. | Reject — **App Review name-rejection risk** |
| `open-health-exporter` (status quo) | Honest and descriptive. To a self-hosting audience "exporter" usefully evokes a Prometheus exporter. | Unbrandable, unmemorable, no trademark protection, poor App Store presence. `github.com/open-health-exporter` is free. | Keep as the **repo** name; do not ship it as the App Store name |

**Recommendation:** **Tributary**, with the App Store subtitle carrying the keywords the name does not
(e.g. an accurate, competitor-free description of exporting health data to your own destinations, within
the 30-character name limit and the subtitle metadata rules [S6]). **Fallback: Curlew**, which has the
cleanest availability profile and the lowest legal risk, at the cost of semantic connection.

Neither may be committed to before MKT-01 completes.

---

## Messaging architecture and objection handling

**Primary message:** Your Apple Health data, in your stack, with proof it got there.

### Pillar 1 — Auditable end to end

*Proof points (each must be a shipped artifact, not a claim):* the shipping app itself is the public repo,
not a companion; every App Store version maps to a published, signed source tag; an SBOM is published per
release; **zero third-party SDKs** in the binary; the App Privacy label reads "Data Not Collected" and
matches `PrivacyInfo.xcprivacy` exactly; the user-configured egress allowlist is visible in-app.

Worth stating plainly to the PM: an open licence does not by itself guarantee a clean binary. One of the
open-source competitors lists an attribution SDK for release builds in its own README [S13]. "Open source"
and "no third-party SDKs" are different promises, and only the second one is checkable by a user. We
should make the second one.

### Pillar 2 — It tells you when it breaks

*Proof points:* a per-export receipt with sample counts, destination and outcome; a "last successful
export" value exposed as a Home Assistant sensor and as a plain, local, user-enabled endpoint; a
documented failure taxonomy in the docs; an example alert rule shipped with the Grafana dashboard;
optional OpenTelemetry export **to the user's own collector, default off, no vendor endpoint, ever**.

### Pillar 3 — Nothing to leave

*Proof points:* a published JSON Schema; a semver'd output contract with a written deprecation policy;
every UI action also available as an App Intent / Shortcut; config export and import as a plain file; a
licence that permits forks.

### Objections to pre-empt

**"Is it safe?"** — Answer with structure, not reassurance. Read-only HealthKit access, requesting only
the types tied to visible features (over-broad requests are a common rejection cause [S7]); no network
permission needed for local-only destinations; enforced egress allowlist; no analytics, no ads, no
crash-reporting SDK; a written threat model in the repo. HealthKit data may never be used for marketing or
data mining under 5.1.2(vi) and 5.1.3(i) [S6] — we should say so and point at the guideline, because it
means our promise is also Apple's rule.

**"Will it be abandoned in six months?"** — This is the strongest objection against any OSS alternative
and it deserves real treatment rather than a paragraph of sincerity. The base rate is against us: most
solo open-source iOS apps do stall, and a maintainer promising commitment is worth nothing because every
abandoned project's README once said the same thing. The only credible answers are structural, and each
is a requirement:

1. **Bus factor greater than one at launch.** Two named humans with commit rights and App Store Connect
   access, both of whom have shipped a release before v1.0. A single-maintainer project cannot honestly
   rebut this objection, and if that is our situation we should say so in the README rather than imply
   otherwise. (MKT-15)
2. **A published continuity plan.** What specifically happens if maintenance stops: how the signing
   identity is handed over, how the project is declared unmaintained, and the fact that the licence
   permits anyone to fork and ship. Written before launch, not after. (MKT-15)
3. **The data outlives the app.** This is the strongest answer and it is a product property, not a
   promise: because output is a documented open format written into infrastructure the user already owns,
   everything exported before abandonment keeps working forever. A user who deletes the app loses nothing
   they already have. Nothing the incumbent offers matches this, because the argument only lands if the
   schema is published and versioned independently of the app. (MKT-08)
4. **A visible liveness signal.** A machine-readable maintenance status (`maintained` /
   `seeking-maintainers` / `archived`) and a supported-OS matrix in the README, updated at each release.
   An honest "seeking maintainers" badge is better marketing than a stale repo, because it lets a user
   make a decision instead of guessing. (MKT-17)
5. **Say how it is funded.** An unfunded "free forever" is the promise most likely to be broken. (MKT-18)

**"Why is it free — what's the catch?"** — My recommendation is that **it should not be free**, or at
least not free-and-unfunded. A small one-time price answers the catch question with "you paid for it",
funds the abandonment mitigation, filters for the user we want, and is well inside what this audience
already pays: the incumbent charges $2.99 one-time for its entry tier and $24.99 lifetime [S5]. A
paid App Store build of copyleft-licensed source is a well-established pattern and is itself a proof point
— anyone who prefers to build it themselves may. Whatever the answer, it must be stated on the landing
page and in the README. Note that we cannot put price framing in the App Store name, subtitle or
screenshots at all: 2.3.7 bars prices and pricing terms from that metadata [S6]. This is a business-model
decision for the PM and the user, not for me (see Open questions).

**"Is it as good as the paid one?"** — No, and saying otherwise is both dishonest and, in App Store
metadata, a 2.3.1 "misleading marketing" exposure [S6]. We publish an honest comparison **on our own
site** that states where we are behind, and never in App Store metadata, where referencing other apps is
prohibited [S6][S8]. Being the first project in this category to publish its own weaknesses is worth more
than any feature claim.

---

## Launch-blocking product requirements

These are things that must be true of the product for a launch to work. Full IDs and acceptance criteria
are in *Requirements I own*.

**Evaluation without a data history.** The single highest-leverage launch asset is a **synthetic health
dataset and a demo mode**. It does three jobs at once: it makes App Store screenshots legal (2.3.9
requires fictional rather than real personal data [S6]), it lets App Review exercise the app on a
simulator with no HealthKit history, and it lets a prospective user or a blogger evaluate the whole
pipeline without owning three years of Apple Watch data. Without it, nobody can try the product before
committing to it, and no third party can write about it. Note that if a demo mode is offered *in lieu of
a demo account*, Apple requires prior approval [S6]; we have no login, so this is a screenshots-and-
evaluation asset rather than a review-credentials substitute.

**App Store listing assets.** Screenshots must show the app in use rather than splash art (2.3.3), be
appropriate to a 4+ rating (2.3.8), contain fictional data (2.3.9), contain no competitor name, no other
platform's name, and no pricing (2.3.7), and must not render Activity-ring-alike visualisations of Move,
Exercise or Stand (5.2.5) [S6]. The icon must not be confusable with Apple Health's; that rules out the
obvious red heart.

**Mandatory App Store Connect declarations.** Since 26 March 2026, any *new* app whose primary or
secondary category is Health & Fitness or Medical, distributed in the EEA, UK or US, must declare its
regulated-medical-device status before it can be distributed [S14][S15]. Our answer is "No", but the
declaration is blocking and must be in the launch checklist, not discovered at submission.

**Documentation as the primary marketing asset.** For this audience the docs *are* the sales page. A
tested quickstart for each of the top two destinations, each verified end-to-end by someone who is not a
maintainer, is worth more than any amount of copy.

**Landing page that answers "will this do what I need?" in 60 seconds:** supported metrics table,
supported destinations, a real example of the output JSON, and the honest comparison. Not a hero video.

**Distribution artifacts, which are product work.** The Home Assistant integration in the **HACS default
list** is the highest-leverage distribution channel available to us, and HACS has hard, checkable
requirements: a public GitHub repo with a description, topics and issues enabled; `hacs.json` with at
least a name; a valid `manifest.json` with `domain`, `documentation`, `issue_tracker`, `codeowners`,
`name`, `version`; brand assets; **at least one full GitHub release**; passing HACS Action and hassfest
workflows; and a PR submitted by the owner or a major contributor [S16][S17][S18]. A published Grafana
community dashboard requires a Classic-model export and a Grafana Cloud account [S19]. These are
engineering deliverables, and they should be in the v1 scope, not in a "marketing" backlog.

**Social proof, honestly.** We will have none at launch and should not manufacture any. Fabricated or
solicited reviews are a removal risk under 2.3.1 [S6]. The realistic substitute is *named early users'
real configurations* published as case studies, and a small number of pre-launch testers who agreed to be
quoted. Two real, specific configurations beat twenty generic testimonials with this audience.

**A one-command reference receiver.** A `docker compose up` that stands up a destination so an evaluator
sees their data land in under ten minutes. This is the demo path for the self-hosting audience and it
directly serves the Grafana and Home Assistant channels.

---

## Channels and community

Ranked by realistic yield for *this specific product*. Most of these are one-shot spikes; I have marked
which ones compound, because the product should be optimised for the compounding ones.

| # | Channel | Realistic yield | Compounds? |
|---|---|---|---|
| 1 | **Home Assistant ecosystem** — HACS default list, HA community forum, r/homeassistant (~525k–584k members [S20]) | A forum thread yields tens to low hundreds of installs; the HACS listing yields a slow, indefinite trickle and appears in search forever. Highest total yield because the artifact is durable. | **Yes** |
| 2 | **App Store organic search** | The only channel reaching non-technical buyers, and the only one that compounds automatically. Ceiling is low in this category (incumbent: 389 US ratings in ten years [S1]). Entirely determined by name, subtitle and keywords. | **Yes** |
| 3 | **Grafana community dashboard catalog** [S19] | Low volume, very high intent — people arrive already wanting exactly this. Durable listing. | **Yes** |
| 4 | **r/selfhosted** (~725k subscribers [S21]) | A well-received project post is a one-shot spike, typically low thousands of visits. Strict self-promotion norms: post as a project share with no marketing register, or get removed. | No |
| 5 | **Hacker News (Show HN)** | Front page is 5k–30k visits in 24h and roughly 1.4 GitHub stars per upvote for OSS, with sub-5% conversion [S22][S23]. Harder in 2026: Show HN is now >12% of submissions and the average Show HN score has fallen to ~9 versus ~19.5 for all stories [S24]. Best credibility-per-effort, worst sustained yield. | No (except backlinks) |
| 6 | **r/QuantifiedSelf** (~26k members, growing ~49%/yr [S25]) | Tiny reach, but the best-targeted audience anywhere — the community explicitly discusses centralising Apple Health into personal data warehouses and seeking privacy-first local alternatives [S25]. Highest conversion per impression. | Partly |
| 7 | **Awesome-\* lists** | Durable backlinks. **awesome-selfhosted is probably ineligible**: it requires the first release to be more than four months old, requires active maintenance, and scopes itself to network services and web applications hosted on your own server — a mobile app does not obviously qualify, though the reference receiver might [S26][S27]. awesome-swift / awesome-ios / awesome-home-assistant are eligible. Plan for month 5, not launch. | **Yes** |
| 8 | **Mastodon / Fediverse** | Excellent values fit, negligible reach, no algorithmic amplification. Useful for maintainer credibility and for reaching a handful of high-signal people. Not acquisition. | No |
| 9 | **Product Hunt** | Poor fit. Rewards consumer polish and launch-day coordination; our audience is not there; the yield is a vanity spike with near-zero retention for a developer-adjacent utility. Recommend we do not do it. | No |

**The honest summary:** channels 4, 5 and 9 are one-shot. If we plan acquisition around them we will get a
launch week and then a flat line. The durable channels are the ones that are *product work* — the HACS
listing, the Grafana dashboard, the App Store listing and the awesome-list entries. That is the argument
for treating them as v1 requirements rather than post-launch marketing tasks.

---

## Success metrics under a privacy-first constraint

### What we can know

- **App Store units and proceeds**, next-day, by territory, from Sales and Trends. This requires **no user
  opt-in** and is always available [S28].
- **Impressions, product page views and conversion rate** from App Analytics.
- **GitHub**: stars, forks, unique clones (14-day window), release asset downloads, issue and PR volume,
  and — most usefully — the *number of distinct non-maintainer humans* who open issues.
- **HACS / Home Assistant**: the integration appears in HA's opt-in usage analytics, giving an external,
  privacy-respecting install proxy we do not have to collect ourselves. **[assumption — verify with the HA
  analytics maintainers before relying on it as a target.]**
- **Grafana catalog** dashboard download counts.
- **Community mentions**: forum threads, blog posts, third-party dashboards and blueprints built on our
  schema. The best single signal that the product is genuinely in use.

### What we cannot know, and must stop pretending we will

- **Retention, sessions and active devices** are only collected from users who opted in to share
  diagnostics with developers, need at least five active devices in range, and are suppressed below
  privacy thresholds [S29][S30][S31]. At our expected volumes these tables will be mostly blank or
  meaningless.
- **watchOS is excluded from App Analytics entirely** [S32]. We will have no usage visibility on the Watch
  app at all.
- Feature usage, which destinations people configure, whether exports succeed in the field, and why people
  churn: **unknowable, permanently**, because the fix would be telemetry and telemetry destroys the wedge.

This is a real cost, and it should be stated in the PRD: **we are choosing to be blind in exchange for the
positioning.** If we ever add a phone-home counter — even an anonymous one — the "Data Not Collected"
label becomes false, which is a mechanical 5.1.1 rejection when the privacy manifest and the label
disagree [S33][S34], and the core claim collapses. That trade is not renegotiable after launch, so it must
be made deliberately now.

### Proposed targets

**[assumption — all targets are my estimates anchored on S1 and S22; the PM should treat them as
falsifiable predictions, not commitments.]**

**First 6 months**

| Metric | Target | Why it is not vanity |
|---|---|---|
| Cumulative App Store units | 750–2,000 | Opt-in-free, next-day, territory-level [S28] |
| Distinct non-maintainer issue reporters | ≥ 15 | Proxy for real use; a person who files an issue has the app running |
| HACS default listing achieved | Yes/No, binary | Gates the highest-yield durable channel |
| HA-analytics-reported installs of our integration | 100–300 | External, opt-in, not collected by us |
| Community-authored artifacts (dashboards, blueprints, posts) | ≥ 3 | Strongest evidence of a real, extending user base |
| Second maintainer with release rights | Yes/No, binary | Treated as a metric because abandonment is our top risk |

**First 12 months**

| Metric | Target | Why it is not vanity |
|---|---|---|
| Cumulative App Store units | 2,000–8,000 | See sizing; exceeding 8,000 would mean the market is bigger than S1 implies |
| App Store rating | ≥ 4.3 with ≥ 40 ratings | Deliberately benchmarked to the incumbent's 4.3 / 389 [S1] |
| Distinct non-maintainer issue reporters | ≥ 25, median first response < 72h | Response time is the abandonment signal users actually watch |
| External contributors with merge rights | ≥ 1 | The only thing that converts "open source" into a durability argument |
| Voluntary off-device survey responses | ≥ 100 | Link in docs and release notes only — **never** an in-app prompt |
| GitHub stars | Tracked, **explicitly not a goal** | Vanity; correlates with HN traffic, not with use |

---

## Claims we may never make

**Regulatory.** Never say or imply: *medical*, *medical-grade*, *diagnostic*, *clinical*, *diagnoses*,
*treats*, *prevents*, *monitors a condition*, *FDA-cleared*, *FDA-approved*, *CE-marked*, or *clinically
validated*. Medical apps that could provide inaccurate data or be used for diagnosis get heightened review,
and accuracy claims about health measurements must be substantiated with disclosed methodology or the app
is rejected [S6][S35]. Our safe harbour is that **we do not measure anything** — we move data Apple Health
already holds — and we must never characterise the accuracy of that underlying data.

**Never claim HIPAA compliance.** HIPAA binds covered entities and business associates. A consumer app
with no business associate agreement is neither, so the claim is both meaningless and an
FTC-deception exposure. If the PM wants a compliance-adjacent claim, the honest ones are about *where data
goes*, not about a regulation we are not subject to.

**Apple marks and confusability.** We may not use `Apple`, `Apple Health`, `Works with Apple Health`, or
any Apple mark or logo in the product name, icon or promotional material — Apple's third-party guidelines
prohibit using an Apple word mark as part of a product name, and `APPLE HEALTH` was filed across four
classes in June 2026 with `WORKS WITH APPLE HEALTH` already registered [S10][S11][S12]. We may make
factual compatibility references in body copy only, in Apple's prescribed referential form [S12]. We may
not imply Apple endorsement (5.2.4), create anything confusably similar to an Apple app (5.2.5), or render
Activity rings in a way that resembles Apple's Activity control (5.2.5) [S6].

**Competitor references in App Store metadata.** Prohibited. App subtitles "should not ... reference other
apps"; metadata may not be packed with trademarked terms or popular app names; and reviewers read the
hidden 100-character keyword field even though users cannot see it, with 2026 enforcement capable of
clearing the whole field or triggering a 5.2 rejection [S6][S8][S9]. **Comparison content is permitted on
our own website and in our repo, and nowhere in App Store Connect.**

**Pricing language in the wrong place.** 2.3.7 bars prices and pricing terms from app names, subtitles,
screenshots and previews [S6]. That means "Free", "No subscription" and "One-time purchase" — our most
persuasive consumer-facing claims — cannot appear in the highest-visibility metadata. They belong in the
description body and on the landing page.

**Unverifiable claims.** Subtitles may not make unverifiable product claims [S6]. "The most private health
exporter" is unverifiable. "Exports to destinations you control" is verifiable. Every headline claim must
map to something a reviewer could check in five minutes.

**Mandatory positive obligations.** Declare regulated-medical-device status ("No") in App Store Connect —
blocking for new Health & Fitness apps in the EEA, UK and US since March 2026 [S14][S15]. Carry a
prominent in-app and on-site statement that the app is not a medical device and provides no medical
advice. Never use HealthKit data for advertising, marketing or use-based data mining, including by third
parties [S6] — which permanently forecloses ad-supported monetisation and any data-driven growth loop.

---

## Requirements I own

| ID | Requirement | Priority | Rationale | How we verify |
|---|---|---|---|---|
| **MKT-01** | The product ships under a cleared name. Before any brand spend or App Store Connect name reservation, a trademark clearance search is completed for the chosen name in Nice Class 9 (and Class 42 if a hosted receiver is offered) in the US, EU and UK; the App Store name is ≤ 30 characters; a matching GitHub org and primary domain are registered. | Must | 2.3.7 requires a unique name ≤30 chars; a late clearance failure forces a rename after the listing, docs, HACS entry and dashboards all embed the old name [S6]. | Written clearance opinion or documented search on file; App Store Connect name reserved; GitHub org and domain registered; all three names identical. |
| **MKT-02** | No App Store metadata field — name, subtitle, screenshots, previews, description or the 100-character keyword field — contains a competitor name, another platform's name, a trademark we do not own, or any price or pricing term. | Must | 2.3.7 and 5.2; reviewers read the hidden keyword field and 2026 enforcement can clear it entirely [S6][S8][S9]. | Pre-submission checklist: every metadata field diffed against a denylist of competitor and platform names and price terms; zero matches; recorded in the release checklist. |
| **MKT-03** | The shipped binary contains **zero third-party SDKs**. The App Privacy label reads "Data Not Collected" and is byte-consistent with `PrivacyInfo.xcprivacy`. | Must | A label/manifest mismatch is a mechanical 5.1.1 rejection [S33][S34], and the entire W1 wedge rests on this being literally true. | Dependency manifest reviewed at each release; a CI check fails the build if any non-first-party binary dependency is linked; label and manifest compared in the release checklist. |
| **MKT-04** | A synthetic health dataset and a demo mode exist, covering every metric family the app supports, loadable on a device or simulator with no HealthKit history. | Must | Screenshots must use fictional data (2.3.9) [S6]; App Review needs to exercise the app; evaluators and writers must be able to try it without years of personal data. | A new engineer, on a clean simulator, produces a complete export to a local destination in under 10 minutes using only the demo data and the quickstart. |
| **MKT-05** | The App Store screenshot set and app icon comply with 2.3.3, 2.3.8, 2.3.9 and 5.2.5: app in use, 4+ appropriate, fictional data, no Activity-ring-alike Move/Exercise/Stand visualisation, no icon confusable with Apple Health. | Must | Direct rejection and, for 5.2.5, IP risk [S6]. | Each screenshot mapped to a screen reachable in the shipped build; a documented reviewer sign-off against each of the four guideline numbers. |
| **MKT-06** | Regulated-medical-device status is declared in App Store Connect for the EEA, UK and US, and the app and site each carry a "not a medical device, not medical advice" statement. | Must | Mandatory for new Health & Fitness apps in those regions since 26 March 2026; without it the app cannot be distributed [S14][S15]. | Declaration visible in App Store Connect before submission; disclaimer present in first-run flow, About screen, README and landing page. |
| **MKT-07** | Every export produces a user-inspectable receipt recording timestamp, destination, sample counts by type, bytes, and outcome. Receipts are retained locally and exportable. | Must | This is wedge W1 — the claim that makes "auditable" meaningful to a non-programmer. | A user can, without developer tools, answer "what left my device, when, and to where" for the last 30 exports. |
| **MKT-08** | The output format is published as a versioned schema in the repo with a semantic-versioning policy and a written deprecation policy, mirrored on the landing page. | Must | Wedge W3, and the strongest structural answer to the abandonment objection: exported data keeps working if we stop. | Schema file present and versioned; a third party parses a sample export using only the published schema, with no reference to source code. |
| **MKT-09** | The user configures an explicit allowlist of network destinations; the app makes no network request to any host not on it, and the current allowlist is visible in the UI. | Must | Wedge W1. Converts "privacy-first" from an assertion into something a user or a firewall can check. | A network-level test: with a destination removed from the allowlist, no traffic to that host is observed across a full export cycle. |
| **MKT-10** | The app exposes a "time since last successful export" signal consumable by the user's own monitoring, plus a documented failure taxonomy; any OpenTelemetry export is opt-in, defaults to off, and can only target a user-supplied endpoint. | Must | Wedge W2, and it resolves the brief's privacy/observability tension in the only direction compatible with MKT-03: the user chooses the collector, and we never operate one. | A working alert fires in Home Assistant and in Grafana when exports stop for longer than a user-set threshold, using only shipped artifacts. |
| **MKT-11** | A Home Assistant integration is accepted into the **HACS default list**. | Should (v1) / Must (within 90 days of v1) | The highest-yield durable channel. It requires a public repo with description, topics and issues enabled, `hacs.json`, a valid `manifest.json`, brand assets, at least one full GitHub release, and passing HACS Action and hassfest workflows [S16][S17][S18]. Cannot be "added later" cheaply — the requirements shape the repo. | The integration appears in the HACS default list; HACS Action and hassfest pass in CI on `main`. |
| **MKT-12** | A reference receiver runs from a single command, and a Grafana dashboard is published to the community catalog. | Should | The evaluation path for the self-hosting audience, and a durable, high-intent discovery channel [S19]. | `docker compose up` plus the quickstart puts real exported data on a Grafana panel in under 10 minutes, verified by a non-maintainer; dashboard live in the catalog. |
| **MKT-13** | A landing page exists that answers "will this do what I need?" in 60 seconds: supported metrics, supported destinations, a real sample of output, current maintenance status, and how the project is funded. | Must | This audience evaluates by reading, not by watching. Every element here answers an objection. | Five people in the target audience, unprompted, correctly state what the product does and does not do after 60 seconds on the page. |
| **MKT-14** | Tested quickstarts exist for the top two destinations, each verified end-to-end by someone who is not a maintainer. | Must | For this audience the docs are the sales page, and an untested quickstart is worse than none. | Two non-maintainers each complete a quickstart on a clean machine without asking the maintainers a question. |
| **MKT-15** | `MAINTAINERS.md` names at least two people with commit and release rights, and `CONTINUITY.md` states what happens if maintenance stops, including signing-identity handover and how the project is declared unmaintained. | Must | The abandonment objection is the strongest one against us and cannot be answered with words. If we cannot meet this, the README must say so plainly instead. | Both files present before v1.0; both named maintainers have pushed at least one release; the continuity plan is reviewed by someone outside the project. |
| **MKT-16** | An honest comparison page lives on our own site and repo, states where we are behind the incumbent, and appears nowhere in App Store metadata. | Should | Credibility with a sceptical audience; and referencing other apps in App Store metadata is prohibited [S6][S8]. | Page exists, names at least three areas where we are worse, and is linked from the landing page; zero competitor references in App Store Connect. |
| **MKT-17** | The README carries a machine-readable maintenance status (`maintained` / `seeking-maintainers` / `archived`) and a supported-OS matrix, updated at every release. | Should | Lets a user assess abandonment risk instead of guessing. An honest "seeking maintainers" is better marketing than a stale repo. | Status and matrix present; the release checklist includes updating both; a release cannot be tagged without them. |
| **MKT-18** | The funding and monetisation model is decided, published on the landing page and in the README, and matches what the App Store listing does. | Must | "What's the catch?" is a top-four objection, and an unfunded "free forever" makes the abandonment objection worse. Price framing may not appear in the name, subtitle or screenshots [S6]. | A single sentence on both the landing page and the README states the model; it matches App Store Connect pricing exactly; no price terms in restricted metadata fields. |
| **MKT-19** | The app never phones home, including anonymous install counters, crash reporting, or aggregate usage pings. Growth measurement uses only external, opt-in-free sources. | Must | The moment we add one, "Data Not Collected" becomes false, the wedge collapses, and the label/manifest mismatch is a 5.1.1 rejection [S33][S34]. | The MKT-03 CI check plus a network test showing zero outbound connections to any developer-controlled host in a full session. |
| **MKT-20** | No marketing surface — App Store metadata, site, README, release notes, talks — claims medical, diagnostic, clinical, FDA/CE, or HIPAA status, or characterises the accuracy of health measurements. | Must | 1.4.1 heightened scrutiny and accuracy-substantiation rules [S6][S35]; HIPAA claims are false and an FTC-deception risk. | A denylist check over all published copy at each release; zero matches; the disclaimer from MKT-06 present. |
| **MKT-21** | We deliberately do **not** build at v1: metric-count parity with the incumbent, an in-app analytics dashboard or charting UI, a plugin architecture, or a Product Hunt launch. | Won't | Each is either a losing parity race, invisible to the wedge, constrained by Guideline 4.7, or a vanity spike with no retention. Scope discipline is what makes MKT-07 through MKT-10 achievable. | These items are absent from the v1 scope in the PRD and each carries a one-line recorded rationale. |

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Perceived abandonment risk stops adoption regardless of product quality | High | High | MKT-15 (two maintainers, continuity plan), MKT-08 (data outlives the app), MKT-17 (honest liveness signal). If we cannot meet MKT-15, say so publicly rather than imply durability we do not have. |
| The "genuinely open source" differentiator is already occupied by a shipping competitor [S2][S3] | High | Medium-high | Re-base positioning on W1/W2 (verifiable egress, failure transparency) rather than licensing. Treat the licence as table stakes. Ask the PM to re-affirm or amend the brief's differentiator #1. |
| App Review rejection on metadata or over-broad HealthKit scope delays launch past the moment when interest exists | Medium | High | MKT-01 through MKT-06 as a pre-submission checklist; request only the HealthKit types tied to visible features [S7]; submit a compliance dry run before the launch window opens. |
| The market is a few thousand people and stakeholders read that as failure | High | Medium | State the sizing in the PRD now, anchored on S1, and set the 6- and 12-month targets accordingly. Managing the expectation is cheaper than beating the market. |
| "Free and unfunded" reads as "will be abandoned" and undermines the strongest objection response | Medium | Medium | MKT-18: decide and publish the funding model. Marketing recommends a modest one-time price or explicit named sponsorship over silent free. |
| Late trademark or App Store name rejection forces a rename after the listing, docs, HACS entry and dashboards embed it | Medium | Medium-high | MKT-01 before any spend; reserve the App Store name early; keep the descriptive repo name as an unbranded fallback. |
| The observability differentiator contradicts the privacy claim if any default sends data anywhere we control | Medium | High | MKT-10 and MKT-19: opt-in, off by default, user-supplied endpoint only, enforced by MKT-09's allowlist and MKT-03's zero-SDK rule. |
| A desirable destination (iCloud sync/backup of health data) is prohibited by 5.1.3(ii) and is discovered in Stage 2 or 3 | Medium | High | Flagged now in Hard constraints; the PM should get an explicit design ruling before iCloud appears in any feature list or comparison table. |
| Launch channels deliver one spike then a flat line | High | Medium | Weight v1 scope toward the compounding channels (HACS, App Store search, Grafana catalog, awesome-lists) rather than the one-shot ones; treat HN and Reddit as credibility, not acquisition. |
| Copyleft licence versus App Store terms creates a distribution dispute | Low-medium | High | If AGPL or GPL is chosen, ship the standard §7 app-store additional permission [S36][S37][S38]; otherwise choose a permissive licence. Decide in Stage 1, not at submission. |

---

## Hard constraints that limit the product

Stated loudly, as the brief asks. Each of these invalidates something someone will otherwise propose.

1. **App names are capped at 30 characters and must be unique** [S6]. Our name plus a descriptive suffix
   will not fit; the subtitle has to carry the keywords.
2. **No competitor references anywhere in App Store metadata**, including the hidden keyword field
   [S6][S8][S9]. Our clearest positioning sentence — "the open alternative to X" — is unusable in the
   place where most buyers will read it.
3. **No prices or pricing terms in the app name, subtitle, screenshots or previews** [S6]. "Free" and "no
   subscription" cannot go where they would work hardest.
4. **No Apple-confusable naming, iconography or UI, and no Activity-ring-alike rendering of Move, Exercise
   or Stand** [S6][S12]. This rules out the obvious icon and constrains any dashboard screenshot.
5. **HealthKit data may never be used for marketing, advertising, or use-based data mining, by us or
   anyone** [S6]. We can never build a data-driven growth loop, and ad-supported monetisation is
   permanently off the table.
6. **Personal health information may not be stored in iCloud** (5.1.3(ii)) [S6]. This directly threatens
   any design that syncs exported health data or a health-bearing cache through CloudKit or iCloud backup
   — including an iCloud Drive destination if it is implemented as app-managed storage rather than a
   user-driven file save. **This needs an explicit ruling before iCloud appears in any feature list.**
7. **Choosing "Data Not Collected" costs us all product analytics.** Retention, sessions and active
   devices only cover opted-in users, need ≥5 active devices, and are suppressed below privacy thresholds
   [S29][S30][S31]. **watchOS is excluded from App Analytics entirely** [S32]. Product decisions must come
   from issues, surveys and judgement.
8. **Regulated-medical-device status must be declared** for new Health & Fitness apps in the EEA, UK and
   US [S14][S15]. Blocking, and easy to miss.
9. **HealthKit permission scope must match visible features** [S7]. We cannot request 150 types to look
   feature-complete in a comparison table.
10. **awesome-selfhosted requires a first release older than four months** and scopes itself to
    self-hosted network services and web applications [S26][S27]. That listing cannot be a launch
    deliverable, and the iOS app may never qualify at all.
11. **HACS default listing requires a full GitHub release and passing HACS/hassfest checks** [S16][S17]
    [S18]. It shapes the repo layout, so it must be decided in Stage 2, not bolted on later.
12. **AGPL/GPL versus App Store terms** requires an explicit §7 app-store additional permission to be
    unambiguous [S36][S37][S38]. This is a Stage 1 licensing decision with distribution consequences.

---

## Open questions for the PM

1. **Business model.** Free, free-with-sponsorship, or a one-time paid App Store build with freely
   buildable source? Marketing recommends against free-and-unfunded because it strengthens the
   abandonment objection. This is a user decision and it blocks MKT-18, the landing page and the App Store
   listing.
2. **Licence.** AGPL (or GPL) with the §7 app-store additional permission, or a permissive licence?
   Affects both the credibility of the wedge and the legality of distribution [S36][S37][S38].
3. **Bus factor.** Is there a second named maintainer? If not, MKT-15 cannot be met and we should say so
   in the README rather than launch a durability claim we cannot support. This is the single most
   important input to my messaging.
4. **Does the premise still hold given `Health.md`?** [S2][S3] An open-source, Swift, App-Store-shipping
   Apple Health exporter already exists. The PRD should either restate the differentiator in terms of
   W1/W2 or explicitly accept that we are the second such project.
5. **Do we publish "we are behind the incumbent on X, Y, Z" at launch?** I recommend yes. It needs PM
   agreement because it constrains what the rest of the PRD may claim.
6. **Is iCloud Drive a launch destination**, given 5.1.3(ii) [S6]? Needs a design ruling before it appears
   anywhere in scope.
7. **Who owns the Apple Developer Program account and any legal entity?** Apps must be submitted by the
   person or entity owning the relevant rights (5.2.1) [S6], and an individual-versus-organisation seller
   name materially changes how durable the project looks on the listing.
8. **Is Home Assistant confirmed as the primary distribution bet?** If yes, MKT-11 should be a Must at
   v1 rather than a Should, and that has direct Stage 2 consequences for repo layout and release process.

---

## Sources

1. Health Auto Export — JSON+CSV, App Store (US), via the iTunes Lookup API, retrieved 2 Sep 2026:
   released 2016-05-21, 4.33 average, 389 ratings. https://apps.apple.com/us/app/health-auto-export-json-csv/id1115567069
2. Health.md, App Store (US), via the iTunes Lookup API, retrieved 2 Sep 2026: released 2026-02-04, free,
   Health & Fitness, 21 ratings. https://apps.apple.com/us/app/health-md/id6757763969
3. `CodyBontecou/health-md` — Swift, AGPL-3.0, ~208 stars. https://github.com/CodyBontecou/health-md
4. Health Auto Export product page (privacy posture, integrations, open-source companion server).
   https://www.healthyapps.dev/apps/health-auto-export/
5. HealthyApps Help Center — FAQ, pricing tiers (Basic $2.99 one-time; Premium monthly/annual; Lifetime
   $24.99). https://help.healthyapps.dev/en/health-auto-export/faq
6. Apple, *App Review Guidelines* — 1.4.1, 2.1(a), 2.3.1, 2.3.3, 2.3.7, 2.3.8, 2.3.9, 2.3.10, 4.7, 5.1.2,
   5.1.3, 5.2.1, 5.2.4, 5.2.5. https://developer.apple.com/app-store/review/guidelines/
7. HealthKit review practice — over-broad permission requests as the most common rejection cause.
   https://ahex.co/apple-healthkit-clinical-app-development/
8. App Store keyword field: competitor names indexed but prohibited under 2.3.7.
   https://trysonar.app/blog/app-store-keyword-field
9. Metadata rejection causes, incl. automated clearing of the keyword field for brand terms (2026).
   https://aitoolsguidebook.com/en/articles/app-store-screenshot-metadata-issue/
10. Apple filed `APPLE HEALTH` in Classes 9, 41, 42 and 44 on 8 June 2026.
    https://kaleidoscopelaw.com/2026/06/14/apple-filed-apple-health-in-four-classes-at-once-what-that-strategy-reveals-about-most-founders-biggest-gap/
11. `WORKS WITH APPLE HEALTH`, Apple Inc., USPTO Reg. 7093754 (live).
    https://markinton.com/trademark/works-with-apple-health-88128446
12. Apple, *Guidelines for Using Apple Trademarks and Copyrights* — third parties may not use an Apple word
    mark as part of a product name. https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html
13. `edequalsawesome/health-md` README framework table listing `AppsFlyerLib` for release-build affiliate
    attribution, as retrieved 2 Sep 2026. https://github.com/edequalsawesome/health-md
14. Apple Developer News, *Update on regulated medical device apps in the EEA, UK and US*, 26 March 2026.
    https://developer.apple.com/news/?id=nyqbfz1y
15. App Store Connect Help, *Declare regulated medical device status*.
    https://developer.apple.com/help/app-store-connect/manage-app-information/declare-regulated-medical-device-status
16. HACS, *Include default repositories* (requirements and PR process). https://www.hacs.xyz/docs/publish/include/
17. HACS, *Integrations* (manifest.json keys, brand assets, repository structure). https://www.hacs.xyz/docs/publish/integration/
18. HACS, *GitHub Action* (validation checks). https://www.hacs.xyz/docs/publish/action/
19. Grafana docs, *Share dashboards and panels* — publishing to the community catalog.
    https://grafana.com/docs/grafana/latest/visualizations/dashboards/share-dashboards-panels/
20. r/homeassistant — subscriber estimates of ~525k–584k as of Sep 2026, from third-party subreddit-stats
    aggregators; the range rather than a single figure reflects disagreement between sources, so treat it
    as an order-of-magnitude signal. Community itself: https://www.reddit.com/r/homeassistant/
21. r/selfhosted, ~724,594 subscribers as of 1 Sep 2026. https://redpulse.io/subreddit-search/r/selfhosted/
22. Show HN outcomes for developer tools: 5k–30k visits and sub-5% conversion on a front-page launch.
    https://hub.causo.ai/guides/show-hn-launch-playbook-technical-founders-2026
23. Show HN for OSS: ~1.4 GitHub stars per upvote within 48h.
    https://business.daily.dev/resources/hacker-news-marketing-developer-tools-show-hn-launch-day-sustained-coverage/
24. Show HN volume >12% of submissions and average score down to ~9 vs ~19.5 overall.
    https://github.com/plastic041/hackernews
25. r/QuantifiedSelf, ~26k members, +~9k in the past year; community focus on centralising Apple Health and
    privacy-first local alternatives. https://thehiveindex.com/communities/r-quantifiedself/ and
    https://neura.health/insights/ask-neura/what-does-quantified-self-mean
26. awesome-selfhosted contribution requirements — first release older than 4 months, actively maintained.
    https://github.com/awesome-selfhosted/awesome-selfhosted-data/issues/594
27. awesome-selfhosted scope — Free software network services and web applications hosted on your own
    server. https://awesome-selfhosted.net/
28. App Store Connect Help, *Overview of reporting tools* — Sales and Trends provides next-day units with no
    opt-in requirement. https://developer.apple.com/help/app-store-connect/measure-app-performance/overview-of-reporting-tools
29. App Store Connect Analytics, *App usage* — collected only from users who agreed to share diagnostics and
    usage information. https://developer.apple.com/help/app-store-connect-analytics/engagement/app-usage
30. App Store Connect Analytics, *App retention* — based on opted-in usage data; cells blank below privacy
    thresholds. https://developer.apple.com/help/app-store-connect-analytics/engagement/app-retention
31. App Store Connect Analytics, *Metric definitions* — requires at least five active devices in range.
    https://developer.apple.com/help/app-store-connect-analytics/reference/metrics-definitions
32. App Store Connect Help — "App Analytics doesn't include data from watchOS."
    https://developer.apple.com/help/app-store-connect/measure-app-performance/overview-of-reporting-tools
33. Privacy label versus privacy manifest mismatch as a 5.1.1 rejection.
    https://pushmyapp.ai/blog/ios-privacy-manifest-guide
34. "Data Not Collected" scrutiny and the App Review data-collection email.
    https://orbitkit.io/blog/we-noticed-your-app-collects-data-email-decoded/
35. Guideline 1.4.1 in practice — accuracy claims must be substantiated or the app is rejected.
    https://www.dogtownmedia.com/from-fda-510k-to-app-store-the-dual-approval-gauntlet-for-medical-device-apps/
36. FSF, *More about the App Store GPL Enforcement* — App Store usage rules as "further restrictions".
    https://www.fsf.org/blogs/licensing/more-about-the-app-store-gpl-enforcement
37. The standard AGPL §7 app-store additional permission wording, as adopted by Feeel/wger.
    https://github.com/wger-project/flutter/issues/10
38. AGPL as a hindrance to App Store submission — Element iOS discussion.
    https://github.com/element-hq/element-ios/issues/7839
