# Competitive / Market Analyst — Stage 1 Contribution

> Role: Competitive / Market Analyst. Research conducted 2 September 2026. All load-bearing
> factual claims carry a numbered source. My own inferences are labelled **ASSUMPTION**.

## Executive summary

**The premise as written is weak, and three of the four stated differentiators have close to
zero market value. There is a narrower product here that is worth building, but it is not
"an OSS Health Auto Export".**

Five findings drive that verdict.

1. **The reliability complaints that look like the incumbent's biggest weakness are Apple's
   fault, not the incumbent's.** HealthKit's store is encrypted while the device is locked and
   access is "relinquished 10 minutes after the device locks" [1][2]. Health Auto Export (HAE)
   states plainly that automations only run while unlocked and that this "is a limitation
   imposed by Apple which cannot be circumvented" [3]. Home Assistant's own iOS maintainers
   cited this exact constraint as the reason they will never ship a HealthKit integration [4].
   We inherit the identical ceiling. **We cannot win on background-export reliability.**
2. **Willingness to pay is roughly $6 per year.** HAE Premium is $0.99/month, $5.99/year, or
   $24.99 lifetime; the Basic one-time unlock is $2.99 [5]. Being free is therefore not a
   wedge — it is a rounding error. Every monetisation route open to an OSS project in this
   category is worse than "no revenue", so this must be planned as a gift, not a business.
3. **The market is small.** After roughly ten years on the App Store, HAE has 375 US ratings
   at 4.3 stars [6]; its public docs repo has 261 GitHub stars [7]. Both are proxies, but both
   point at a user base in the tens of thousands globally, not millions.
4. **"Genuinely open source" is already occupied and is not a differentiator.** At least five
   OSS HealthKit exporters exist, including Health Lens (MIT, shipping on the App Store, free)
   [8], Vital2AI (MIT) [9], HealthExporter [10], workout-exporter [11] and health4ai — an OSS
   Swift app that already does `HKObserverQuery` + `BGTaskScheduler` sync to Postgres with an
   MCP server [12]. What none of them have is sustained maintenance and breadth. Health Lens's
   last shipped version is v1.1 from February 2025 [8]. The failure mode in this category is
   abandonment, not closed source.
5. **The fastest-growing reason to export was commoditised eight months ago.** Anthropic
   shipped a native Apple Health connector for Claude in January 2026 [13][14], two weeks
   after OpenAI shipped ChatGPT Health with an Apple Health connector [14]. "Get my health
   data into an LLM" is now a first-party feature of both major assistants.

**What is genuinely worth building.** There is one evidenced, unfixed, *not-Apple's-fault*
class of defect in the incumbent: **incremental-sync watermark semantics silently corrupt
downstream databases.** HAE's `Since Last Sync` keys off the HealthKit *write* timestamp, so
when a third-party app backfills historical samples, the historical dates are never
re-summarised and are "permanently stale in any downstream system" [15]. Separately, Apple
finalises sleep staging hours after waking and writes the early part of the night with the
prior evening's timestamps, so `Since Last Sync` ships truncated nights — a downstream
maintainer traced Grafana showing 4.8h nights against Apple Health's real 9h33m [16]. That is
a data-correctness bug, not an annoyance, and it is the one thing a careful competitor can
actually beat. Combine it with speaking HAE's existing wire format so the whole receiver
ecosystem works on day one, and there is a defensible, small, honest product.

## Competitive landscape

### Comparison table

| Product | What it does | Platforms | Price | Licence | Most-complained-about weakness |
|---|---|---|---|---|---|
| **Health Auto Export** (benchmark) | 150+ metrics to CSV/JSON/GPX; automations to REST, MQTT, Home Assistant, Dropbox, Google Drive, iCloud Drive, Calendar, Email; TCP server; MCP server | iPhone, iPad, Mac, **visionOS — not watchOS** [17] | Free tier; Basic $2.99 one-time; Premium $0.99/mo, $5.99/yr, $24.99 lifetime [5] | Proprietary. Public repo is **docs only** [7]; companion Grafana server is OSS [18] | Automations report "Succeeded" while nothing arrives downstream [19]; incremental sync permanently loses backfilled history [15]; behaviour changes between releases [20] |
| **HealthFit** | Workouts to Strava/TrainingPeaks/Intervals.icu + ~18 more; FIT/GPX/CSV/Markdown; multisport | iPhone (+Watch data via phone) | $6.99–$9.99 one-time + optional $7.99–$14.99 supporter IAP [21] | Proprietary | Needs periodic manual reopening when iOS backgrounds it [22]; workouts-only, not a general health exporter |
| **HealthSave** | CSV/JSON/PDF; background sync to *your* server via a frozen `POST /api/apple/batch` v1 contract; Home Assistant; private REST API | iPhone | Free tier; Pro **$24.99 one-time** [23] | App proprietary. Companion "Observatory" is **open-core**: contracts/SDK Apache-2.0, server core Elastic-2.0 source-available [24][25] | Newest entrant, small track record; explicitly "no managed option — you run the server, DB, backups, reverse proxy" and sync is "best-effort ~1–5 min, not instant" [24] |
| **QS Access** | Original HealthKit→CSV table exporter | iPhone | Free | Proprietary | **Dead.** Maintainers: "We no longer maintain this app"; crashes on launch on modern iOS [26][27] |
| **Simple Health Export CSV** | Select quantity types → CSV | iPhone | Free / paid | Proprietary | Manual only; no automation. Recommended as the QS Access successor by the QS forum [26] |
| **Health Lens — CSV Exporter** | Quantity types → CSV | iPhone, visionOS | **Free** | **MIT** [8] | Narrow (quantity types only), 11 ratings, last update v1.1 Feb 2025 — the abandonment pattern |
| **Vital2AI** | 90+ metrics → "AI-ready" CSV; workouts; Face ID | iPhone | Free | **MIT** [9] | 4 GitHub stars; manual export only; no automation |
| **health4ai** | OSS Swift app: `HKObserverQuery` + `BGTaskScheduler` → your Postgres, plus an 11-tool MCP server | iPhone (TestFlight) | Free / BYO Postgres | OSS [12] | TestFlight-only, single-maintainer, requires you to run Postgres + Supabase |
| **MetricBridge** | 190 metrics → local JSON + 7-tool MCP server | iPhone | Paid IAP | Proprietary | Contains ad-attribution SDK (non-health) [28] — an odd fit for a privacy-first buyer |
| **Gyroscope** | Life/health OS with AI coaching | iPhone + web | **~$1/day** (G1); $3–8/day (MAX) [29] | Proprietary | Requires an account; ~30× the price of HAE; not an exporter |
| **Bearable** | Symptom/mood tracker that *reads* Apple Health | iPhone, Android | Free + subscription | Proprietary | Not an exporter; aggregation is inbound-only |
| **Exist.io** | Correlation engine across Apple Health + ~15 services; has an API | iOS, Android, web | **$6.99/mo** or $62.90/yr [30] | Proprietary | Cloud account mandatory; monthly subscription; analysis product, not a data-liberation product |
| **Heads Up Health** | Clinical-leaning aggregation for patients + providers | iPhone, Mac, visionOS | **$8.99/mo** or $78.99/yr [31] | Proprietary | Cloud account mandatory; priced for clinics |
| **Apple's own "Export All Health Data"** | One `export.zip` containing one nested `export.xml` | iPhone | Free, built in | N/A | Can exceed 1 GB and hang or crash mid-export; not per-metric; not openable in a spreadsheet; no date or metric filtering [32][33][34] |

### OSS receiver ecosystem (complements, not competitors — and strategically decisive)

Every one of these is built to consume **HAE's** wire format:

- `irvinlim/apple-health-ingester` — Go HTTP server → InfluxDB / VictoriaMetrics / local file [35]
- `HealthyApps/health-auto-export-server` — official OSS Node + Grafana companion [18]
- `mrkhachaturov/hae-vault` — CLI + HTTP ingest → SQLite, terminal dashboard [36]
- `Klebb` — free OSS self-hosted dashboard, "plugs into Health Auto Export" [37]
- `HealthLog` — self-hosted timeline; documents HAE date-range gotchas [16]
- Assorted `export.xml` → DuckDB / SQLite MCP servers [38][39]

**This is the single most important strategic fact in the landscape.** The incumbent's moat is
not its app; it is that a dozen independent receivers already speak its JSON. A new exporter
that invents its own format starts with an ecosystem of zero.

### Per-competitor notes

**Health Auto Export.** Not a lazy incumbent. It ships Activity Logs grouped per run, with
slow-query warnings and specific diagnostic strings including "Health data could not be fully
read. The device may have locked during the export" [3][40]. That matters directly to us: the
brief's "observable by design" differentiator is **catching up, not leading**. Its real
weaknesses are (a) the incremental-watermark correctness class above [15][16], (b) a "Succeeded
but nothing arrived" failure mode where the log lies to the user [19], (c) regression churn —
"Its behavior changes with every update, and things that used to work stop working" [20], and
(d) a TCP server with **no TLS and no auth** that only works in the foreground [41]. Note also
that its documented workaround for background reliability is to charge the device and use
iPhone Mirroring so the phone "behaves in the same way as if it were unlocked" [3] — a
telling admission of the platform ceiling.

**HealthSave.** The most direct threat to this project's premise, and it launched into exactly
our intended position: self-hoster-focused, one-time $24.99, no cloud, open-core companion,
Home Assistant, private REST API [23][24]. Critically, it **froze its v1 ingest contract**
specifically so that "any server that speaks this contract works, including community
implementations", and licensed the contract layer Apache-2.0 while keeping the server core
Elastic-2.0 [25]. It has understood the ecosystem lesson. Its server core is *not* OSS by OSI
definition, which is the one honest opening we have — but it is a narrow one.

**HealthFit.** Do not compete here. $6.99 one-time buys ~20 training-platform integrations,
true multisport FIT export and years of trust with athletes [21]. This segment is closed.

**QS Access.** Instructive rather than competitive. The canonical community exporter died of
maintainer exhaustion, with users on the QS forum asking for years that it be open-sourced
[27]. That is the future of this project if we do not solve sustainability at Stage 1.

## Monetisation and pricing

**What the incumbent charges.** Free (widgets + dashboard); Basic **$2.99 one-time** (manual
export, Shortcuts, sleep phases / ECG / blood-glucose metadata, GPX routes, aggregation
control); Premium **$0.99/month, $5.99/year, or $24.99 lifetime** (automated background
exports, REST/MQTT/Home Assistant/Drive/Dropbox/Calendar/Email destinations, Mac sync). All
tiers include Family Sharing, and there is a 7-day full trial [5].

**What that tells us.** Three things, and they are unwelcome.

1. **The automation layer — the entire hard part — is priced at $5.99/year.** The incumbent has
   already established that this functionality is worth about the price of one coffee annually.
   "Free" saves the user $6/year, which will not motivate a switch on its own.
2. **The ceiling is set by a one-time $24.99.** Both HAE and HealthSave offer lifetime unlocks
   at $24.99 [5][23]. **ASSUMPTION:** a new entrant cannot charge more than that, and as an
   unknown quantity would need to charge less.
3. **Nobody in this category has found recurring revenue at scale.** The apps that do charge
   subscriptions (Exist $6.99/mo, Heads Up $8.99/mo, Gyroscope ~$30/mo) are all *analysis*
   products with a cloud account [29][30][31] — a business we have explicitly ruled out.

**Options open to an OSS project, assessed.**

| Option | Verdict | Reasoning |
|---|---|---|
| **Free binary, no revenue** (NetNewsWire model) | **Recommended** | NetNewsWire ships free OSS on the App Store and *actively refuses* money, because taking any money would force a legal entity, a bank account, accounting and taxes — "time I could have spent working on NetNewsWire itself" [42][43]. It works, but note the preconditions: a retired maintainer, 10k GitHub stars and 90 contributors [43]. We would have none of those. |
| **Paid App Store binary, source available** | Viable, not worth it | Legal (we own the copyright), and precedent exists. But at a $6–25 price ceiling against a well-reviewed incumbent, revenue would not cover the $99/year Apple Developer Program fee [44] plus support time for a long while. It also converts the project from gift to obligation. |
| **Sponsorware / GitHub Sponsors** | Not viable | Only 1.3% of active repos have sponsorship enabled at all, and the median monthly sponsorship among *those* is about $50 [45]. |
| **Donations / tip jar** | Not viable | "Putting up a 'buy me a coffee' link rarely generates sustainable income" [45]. |
| **Paid cloud sidecar** | **Reject** | Contradicts the privacy posture, creates an operational obligation, competes with a dozen free OSS receivers [35][36][37], and drags us into App Store 5.1.3 territory on health-data handling [46]. |
| **Open-core (HealthSave model)** | Reject | Elastic-2.0 source-available is not open source. Adopting it forfeits the only differentiator we actually have against HealthSave [25]. |

**Recommendation:** free, ungated, no IAP, no subscription, no cloud. Treat the **$99/year
Apple Developer Program fee** [44] as a permanent unrecovered cost and name the person paying
it in the PRD. If nobody will commit to that fee for five years, the project should not start.

## Evidenced gaps and unmet needs

I separate these deliberately. Only the first two justify a switch.

### Would switch products over it

**Gap 1 — Incremental sync silently and permanently corrupts downstream databases.** HAE's
`Since Last Sync` uses the HealthKit *write* timestamp. When Withings, Sonicare, Oral-B or any
other app backfills historical samples in bulk, HAE emits an updated daily summary only for the
sync date, never for the historical measurement dates. Verbatim from the filed issue:

> "The result: the historical dates are permanently stale in any downstream system consuming
> HAE's incremental REST API, even though Apple Health now has correct data for those dates.
> The only way to recover those historical summaries is a full manual export covering the
> affected date range." [15]

The same class of bug hits sleep, because Apple finalises sleep staging hours after waking and
writes the early third of the night — the deep-sleep-rich part — with the prior evening's
timestamps. A downstream maintainer's root-cause writeup:

> "The Apple Health app held the full nights (9 h 33 / 8 h 52, with early-night deep sleep).
> `raw_ingest` (the verbatim HAE payload, before any parsing) only contained the late fragment
> of each night — the early portion never arrived." [16]

This is the strongest finding in this report. It is silent, it is permanent, it destroys trust
in a longitudinal record, and unlike the locked-device ceiling **it is entirely fixable in
software.**

**Gap 2 — The success/failure signal lies.** Multiple users report the activity log showing
"Succeeded" while nothing reaches Home Assistant, with the workaround being to open the app and
press the export button manually [19]. A log that reports success on a run that delivered
nothing is worse than no log, because the user stops looking. The brief's "observable by design"
hypothesis is validated here — but the requirement is **truthful per-run delivery accounting**,
not tracing for its own sake.

### Genuinely annoying, but not switch-driving

- **Time resolution silently collapses.** A reviewer trying to export blood pressure: the app
  "does NOT export the time of the reading… The app simply indicates that all readings occurred
  at 00:00:00", and the workaround "develops a line of data for EVERY minute in your export
  range, regardless of whether there is any actual data" [47].
- **Metric selection not honoured.** Same reviewer: export files produced for State of Mind and
  Symptoms "even though that selection was clearly NOT checked" [47].
- **Regression churn.** "Its behavior changes with every update, and things that used to work
  stop working. I bought another app to replace it" [20]. And: "it no longer works since the
  last update: 'An error occurred while generating the health metrics CSV file'" [20].
- **Onboarding cliff for non-technical users.** "All I have is a JSON file and I don't know how
  to use it" [20]. Relevant mainly as a warning about who *not* to target.
- **TCP server has no TLS and no auth, and is foreground-only** [41]. Real, but it is a niche
  feature for a niche audience.

### Not a gap — do not treat these as opportunities

- **Background export reliability.** Structurally capped by Apple [1][2][3][4]. Anyone claiming
  to fix it is lying or has not read the docs.
- **watchOS support.** HAE runs on iPhone, iPad, Mac and visionOS but **not** watchOS [17], and
  Watch data routes to the paired iPhone anyway — "Apple Health data export happens on iPhone,
  even when sourced from Apple Watch" [48]. The brief lists first-class watchOS support as a
  differentiator. It is a gap with no user value behind it.
- **"Export to AI".** Now native in both Claude and ChatGPT [13][14], plus HAE's own MCP server
  [41] and at least four OSS MCP servers [12][28][38][39].

## Audience segmentation and sizing

Sizing here is weak by nature. Nobody publishes Apple Health exporter market size, and I could
not find any credible third-party estimate. Anchors: ~2.5bn active Apple devices [49]; an
estimated 170M+ active Apple Watch install base [50]; Home Assistant reports 676,069 opt-in
active installations and estimates that "less than a fourth" of users opt in [51]. Everything
below carries wide error bars and is labelled.

| Rank | Segment | Need | Reachability | OSS fit | Rough size (**ASSUMPTION**, ±1 order of magnitude) |
|---|---|---|---|---|---|
| 1 | **Self-hosters / Home Assistant users** | High | High | Excellent | ~2.7M HA installs [51]; **ASSUMPTION** 1–3% want Apple Health in their stack → 30k–80k interested, of whom perhaps 5–10k would install |
| 2 | **Developers building on their own data** | Medium-high | High (GitHub, HN, Lobsters) | Excellent | **ASSUMPTION** 10k–30k globally, but shrinking as first-party AI connectors absorb the casual end |
| 3 | **Quantified-self hobbyists** | High | Low and falling | Good | **ASSUMPTION** low thousands. The QS forum is quiet and its canonical tool has been dead for years [26][27] |
| 4 | **People leaving iOS** | High but one-shot | Low | Poor | Real need — there is no official Apple Health → Health Connect path at all [52]. But zero retention, zero community, and free tools plus Apple's own export already cover the archive case [32] |
| 5 | **Athletes** | Medium | High | Poor | **Do not serve.** HealthFit owns this for $6.99 one-time [21] |
| 6 | **Researchers / clinicians** | High | Low | Very poor | **Cannot serve.** Guideline 5.1.1 expects health-service apps to come from recognised institutions or hold regulatory clearance, and 5.1.3 requires IRB approval plus informed consent for human-subject research [46][53] |

**Ranking rationale.** Segment 1 wins on all three axes simultaneously: the need is acute (they
already run Grafana/InfluxDB/HA and have built receivers by hand [35][36][37][54]), they are
reachable through channels that cost nothing (HA forums, r/homeassistant, r/selfhosted, GitHub),
and they are the rare audience that treats "you can read the code that moves your health data"
as a real purchase criterion rather than a slogan. They are also tolerant of the locked-device
ceiling, because ambient dashboards do not need real-time data.

Segment 2 is the natural contributor pool and therefore matters out of proportion to its size —
**ASSUMPTION**: this is where maintainers come from, so it should be served even where the
user-count case is thin.

Segments 5 and 6 should be explicit non-goals in the PRD. Attempting either burns the small
maintenance budget on the two audiences we serve worst.

**Honest total.** **ASSUMPTION:** a realistic ceiling for this product is single-digit
thousands of active users, with a plausible outcome in the hundreds. Every requirement below is
written for that reality. If the PRD's success criteria assume more, they are wrong.

## Requirements I own

| ID | Requirement | Priority | Rationale | How we verify |
|---|---|---|---|---|
| **MA-01** | Incremental export must be correct under late-arriving and backfilled samples: the watermark is keyed on sample **measurement** time, and any aggregate window touched by a newly-observed sample is re-emitted regardless of how old that window is. | **Must** | The single evidenced defect class that permanently corrupts downstream databases and is not Apple's fault [15][16]. This is the product's reason to exist. | Write a HealthKit sample dated 30 days in the past; the next incremental run must re-emit the daily aggregate for that historical date. Second test: write sleep samples with an evening start and a next-morning write time; the exported night must span the full session, not the post-watermark fragment. |
| **MA-02** | Every destination write must be idempotent and content-addressed, so replay and overlap are free. | **Must** | Correctness under MA-01 requires re-sending overlapping windows; that is only affordable if receivers can dedupe. Existing OSS receivers already do content-hash dedup [16][36]. | Replay an identical export window three times against a reference receiver; downstream row count and values are unchanged after runs 2 and 3. |
| **MA-03** | Emit a payload that is **wire-compatible with the Health Auto Export REST/JSON shape**, or ship a documented, versioned mapping plus a conformance fixture set. | **Must** | The incumbent's real moat is a dozen independent receivers that already speak its format [18][35][36][37]. Inventing a format starts our ecosystem at zero. | Run our export unmodified against `apple-health-ingester` and `hae-vault` and confirm ingest succeeds with correct values, without patching either receiver. |
| **MA-04** | Every run produces an on-device, machine-readable receipt: per-metric sample counts read, counts delivered, bytes sent, destination response status, and a specific failure reason. A run that delivers zero samples must never be reported as success. | **Must** | Directly answers the "Succeeded but nothing arrived" complaint [19] and grounds the brief's "observable by design" hypothesis in an evidenced need rather than a preference for tracing. | Force each failure mode (device locked mid-run, destination 500, destination unreachable, auth rejected, no data in range) and assert the receipt names that specific cause and is not marked success. |
| **MA-05** | State the locked-device constraint in the README and in-product **before** the first HealthKit permission prompt, including that scheduled times are not guaranteed. | **Must** | The ceiling is real and unfixable [1][2][3][4]. Setting the expectation up front is the only available defence against the incumbent's most common support burden. | Onboarding copy review; assert the disclosure string is present and precedes the authorization request in the flow. |
| **MA-06** | Licence must permit App Store distribution without ambiguity: a permissive licence (Apache-2.0 / MIT), or GPLv3 with an explicit §7 App Store additional permission. | **Must** | GPL/App Store tension is real but solved by §7 additional permissions or a Nextcloud-style non-enforcement commitment [55][56][57]. Leaving it unresolved blocks distribution and deters contributors. | `LICENSE` present; if copyleft, the App Store additional-permission text is committed and referenced from the README. |
| **MA-07** | No third-party telemetry, analytics, ad-attribution or crash SDK enabled by default. Any OpenTelemetry export is opt-in, off by default, and sends only to a user-specified endpoint. | **Must** | Guideline 5.1.3 restricts health-data handling and forbids use for advertising or data mining [46]. It is also the only credible differentiator against a competitor that ships ad attribution [28]. Resolves the brief's stated privacy/observability tension in the market's favour. | Static check that no analytics/attribution SDK is linked; network capture on a clean install shows zero outbound connections to any host the user did not configure. |
| **MA-08** | Ship free, with no tiers, no IAP, no subscription and no feature gating. | **Should** | The incumbent's entire automation layer costs $5.99/year [5]. Price cannot be a wedge, and gating would cost us the only audience that cares about the licence. | App Store listing shows no in-app purchases. |
| **MA-09** | Publish the export wire format as a versioned specification in its own right, stability-committed and independent of the app's release cycle. | **Should** | HealthSave froze its v1 ingest contract precisely so receivers survive app churn [25]; regression churn is a top incumbent complaint [20]. Also the project's best insurance against its own abandonment. | A versioned spec document plus machine-readable fixtures exist in-repo; CI fails on any breaking change to a frozen version. |
| **MA-10** | v1 destinations: local file / iCloud Drive, generic REST webhook with bearer auth, and Home Assistant. | **Should** | The minimum set the rank-1 segment actually needs, matching the destinations self-hosters already wire by hand [35][37][54]. | Each destination has an integration test against a real receiver. |
| **MA-11** | Full-history backfill must complete without user babysitting, and the measured completion time for a stated history size must be published. | **Should** | Backfill is the first thing every new user does and where Apple's own export fails outright [32][33]. Comparable products report ~20 minutes for ~5M data points [58]. Falsifiable target: **5 years of typical Apple Watch history completes in under 30 minutes on a supported device, resumable across interruptions.** | Timed backfill against a seeded 5-year store; kill the app mid-run and confirm it resumes without duplicating or skipping. |
| **MA-12** | MQTT, Dropbox, Google Drive, Calendar, Email destinations. | **Could** | Present in the incumbent [5] but each adds a permanent maintenance liability against a tiny user base. Add only on evidenced demand. | Deferred; revisit only with a filed request from an identified user. |
| **MA-13** | **Won't:** standalone watchOS export app. | **Won't** | Watch data already routes to the paired iPhone [48]; the incumbent does not ship watchOS [17] and this is not among any evidenced complaint. Contradicts the brief — deliberately. | N/A |
| **MA-14** | **Won't:** FIT/TCX export or training-platform integrations (Strava, TrainingPeaks, Intervals.icu et al). | **Won't** | HealthFit owns this segment with ~20 integrations for $6.99 one-time [21]. Unwinnable and off-mission. | N/A |
| **MA-15** | **Won't:** research/clinical features — FHIR, cohort export, IRB workflows, provider sharing. | **Won't** | Guidelines 5.1.1 and 5.1.3 impose institutional and IRB requirements no volunteer project can carry [46][53]. | N/A |
| **MA-16** | **Won't:** any hosted service, account system, or paid cloud sidecar. | **Won't** | Contradicts the privacy posture, creates an unfunded operational obligation, and competes with free OSS receivers that already exist [18][35][36][37]. | N/A |

## Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| **Maintainer abandonment.** The category's defining failure. QS Access died this way [26][27]; Health Lens has not shipped since Feb 2025 [8]; OSS sponsorship medians are ~$50/month [45]. | **High** | **Critical** | Treat sustainability as a Stage 1 requirement, not an afterthought. MA-09 (versioned spec) and MA-03 (compatibility with existing receivers) mean users are not stranded if we stop. Name the person paying the $99/year fee [44] and the succession plan in the PRD. Keep scope brutally small (MA-12/13/14/15/16). |
| **HealthSave already occupies the intended position** — self-hoster focus, one-time price, no cloud, open-core companion, frozen wire contract [23][24][25]. | **High** | High | Compete only where they are genuinely closed: their server core is Elastic-2.0 source-available, not OSS [25], and the iOS app is proprietary. Do not compete on breadth. |
| **App Store review rejects or delays a HealthKit app whose primary function reads as "data plumbing."** Apple rejects apps that use HealthKit without "primary features that require health or fitness data" [59], and requires per-type purpose strings plus visible in-app health UI [46][60][61]. | Medium | **Critical** — no distribution, no product | Design for reviewability: request only the types actually exported, write specific purpose strings, and include genuine in-app data display. Flagged to the design stage as a gating constraint. **ASSUMPTION:** an export-only app with no data display is at material rejection risk. |
| **Users blame us for Apple's locked-device ceiling**, generating unanswerable support load — the incumbent's single largest support theme [3][19]. | **High** | Medium | MA-05 (disclose before permission prompt) and MA-04 (receipt names the real cause, e.g. "device locked mid-run"). |
| **Platform vendors absorb the use case.** Claude and ChatGPT both shipped Apple Health connectors in January 2026 [13][14]. Apple could ship first-party structured export at any WWDC. | Medium | High | Do not build for the AI-export use case. Anchor on the self-hoster segment, which no vendor has an incentive to serve. |
| **Integration maintenance outruns capacity.** Each destination is a permanent liability against a user base in the low thousands. | **High** | Medium | MA-10 caps v1 at three destinations; MA-12 makes the rest evidence-gated. Prefer a documented webhook contract over bespoke integrations. |
| **Market is too small to attract contributors.** HAE: 375 US ratings [6], 261 docs-repo stars [7]. Compare NetNewsWire's 10k stars / 90 contributors, which is what makes its no-revenue model survive [43]. | Medium-high | High | Recruit from segment 2 (developers) explicitly, and treat MA-03 compatibility as the adoption lever that gets us in front of existing receiver communities. |
| **Copyleft/App Store licence dispute deters contributors or blocks release** [55][56][57]. | Low | Medium | MA-06 settles it before the first external contribution. |

## Hard constraints that limit the product

1. **HealthKit is unreadable while the device is locked.** Apple: the device "encrypts the
   HealthKit store when the user locks the device. As a result, your app may not be able to read
   data from the store when it runs in the background" [1]; access "is relinquished 10 minutes
   after the device locks" [2]; queries against a locked store fail with
   `errorDatabaseInaccessible` [62]. **This makes truly unattended, scheduled export impossible
   on iOS.** The only documented exception is `HKWorkoutSession` during an active workout [2].
   Everything the PRD says about export reliability must be written inside this constraint.
2. **iOS does not permit time-scheduled background execution.** Background App Refresh timing is
   the system's decision, degraded by Low Power Mode, extended inactivity and resource pressure
   [3][63]. "Export every night at 02:00" is not implementable.
3. **There is no HealthKit server API.** All access is on-device [64]. No agent, cron job or
   cloud function can ever fetch this data directly; an on-device app is structurally mandatory.
4. **App Store Review Guideline 5.1.3** forbids using health data for advertising, marketing or
   use-based data mining, forbids sharing without consent and selling outright, requires a
   privacy policy covering health-data use, and requires IRB approval plus informed consent for
   human-subject research [46]. This constrains any telemetry design (see MA-07) and rules out
   the research segment.
5. **HealthKit must be the app's primary purpose.** Apps that declare HealthKit without primary
   health features are rejected [59][60][61]. An export-only utility with no in-app data display
   carries real rejection risk (**ASSUMPTION** on degree).
6. **Distribution costs $99/year, forever.** Required for App Store distribution and for macOS
   Developer ID signing and notarisation; notarisation is unavailable on a free account
   [44][65][66]. A lapsed membership means the app disappears.
7. **Copyleft needs an explicit App Store carve-out.** Solvable via a GPLv3 §7 additional
   permission or a Nextcloud-style non-enforcement statement [55][56][57], but it must be
   decided before external contributions arrive.
8. **Medications require separate, per-medication authorisation** in Apple Health [40] — a
   permissions edge case any "export everything" claim must account for.
9. **Apple's own export is the free floor.** It is bad — 1 GB+ single-XML blobs that hang or
   crash mid-export, no filtering, not spreadsheet-openable [32][33][34] — but it exists, costs
   nothing, and covers the one-shot archive case. It caps what the migration segment will pay.

## Open questions for the PM

1. **Who commits to the $99/year Apple Developer Program fee, and for how many years?** [44] If
   the answer is "unclear", my recommendation is not to start. This is a hard gate.
2. **Do we accept MA-03 (wire-compatibility with Health Auto Export's payload shape) even though
   it means designing to a competitor's format?** I believe it is the single highest-leverage
   adoption decision available [18][35][36][37], but it constrains the design stage
   significantly and needs an explicit yes/no from you.
3. **Does the PRD accept my recommendation to drop first-class watchOS support (MA-13), given it
   contradicts the brief?** I found no evidence of user demand and the incumbent does not ship it
   [17][48].
4. **Is "free, no revenue, ever" acceptable?** Every alternative is worse (see Monetisation). If
   the user expects this to become self-sustaining, that expectation should be corrected now.
5. **What does success look like at this market size?** If the PRD's success criteria assume more
   than low-thousands of active users, they should be rewritten. I need a target to write
   verifiable requirements against.
6. **Do we ship a real in-app data display purely to de-risk App Store review**, even though it
   is scope we would otherwise cut? [59][60][61] This is a product-shape decision, not a
   research one.
7. **Given Anthropic and OpenAI both shipped native Apple Health connectors in January 2026**
   [13][14], do we accept "no AI/MCP features" as a non-goal, or is there a self-hoster-specific
   MCP angle worth keeping?

## Sources

1. Apple, *Protecting user privacy* (HealthKit) — https://developer.apple.com/documentation/healthkit/protecting-user-privacy
2. Apple, *Protecting access to user's health data* (Platform Security) — https://support.apple.com/guide/security/protecting-access-to-users-health-data-sec88be9900f/web
3. HealthyApps Help Center, *Automations* (limitations, troubleshooting, activity logs) — https://help.healthyapps.dev/en/health-auto-export/automations
4. Home Assistant Community, *[iOS Feature Request] Apple HealthKit Integration* — https://community.home-assistant.io/t/ios-feature-request-apple-healthkit-integration/24494
5. HealthyApps Help Center, *Frequently Asked Questions* (pricing tiers) — https://help.healthyapps.dev/en/health-auto-export/faq
6. App Store, *Health Auto Export — Ratings & Reviews* (4.3 / 375 US ratings) — https://apps.apple.com/us/app/health-auto-export-json-csv/id1115567069?platform=ipad&see-all=reviews
7. GitHub, `Lybron/health-auto-export` (documentation-only repo, 261 stars) — https://github.com/Lybron/health-auto-export
8. App Store, *Health Lens — CSV Exporter* (free, MIT, v1.1 Feb 2025) — https://apps.apple.com/us/app/health-lens-csv-exporter/id6578440958
9. GitHub, `agalbourdin/vital2ai` (MIT) — https://github.com/agalbourdin/vital2ai
10. GitHub, `evandhoffman/HealthExporter` — https://github.com/evandhoffman/HealthExporter
11. GitHub, `limulus/workout-exporter` (MIT) — https://github.com/limulus/workout-exporter
12. GitHub, `jefflitt1/health4ai` — https://github.com/jefflitt1/health4ai
13. Fortune, *Anthropic unveils Claude for Healthcare* (11 Jan 2026) — https://fortune.com/2026/01/11/anthropic-unveils-claude-for-healthcare-and-expands-life-science-features-partners-with-healthex-to-let-users-connect-medical-records/
14. MacObserver, *Anthropic's Claude Gets Apple Health Support* (notes OpenAI's ChatGPT Health shipped two weeks earlier) — https://www.macobserver.com/news/anthropics-claude-gets-apple-health-support-in-new-ios-update/
15. GitHub issue, *[Feature Request] Incremental REST API sync misses historical data backfilled by third-party HealthKit apps* — https://github.com/Lybron/health-auto-export/issues/56
16. GitHub PR, `anym001/healthlog` #60, *recommend "Standard" HAE date range over "Since Last Sync"* (sleep late-finalisation root cause) — https://github.com/anym001/healthlog/pull/60
17. App Store, *Health Auto Export* listing (iPhone, iPad, Mac, Apple Vision) — https://apps.apple.com/us/app/health-auto-export-json-csv/id1115567069
18. GitHub, `HealthyApps/health-auto-export-server` (OSS Grafana companion) — https://github.com/HealthyApps/health-auto-export-server
19. GitHub issue, *[BUG] Automatic export function does not work automatically* — https://github.com/Lybron/health-auto-export/issues/21
20. MWM app profile aggregating Health Auto Export reviews (regression churn, CSV generation errors) — https://mwm.ai/apps/health-auto-export-json-csv/1115567069
21. App Store, *HealthFit* (price, supporter IAP, integration list) — https://apps.apple.com/us/app/healthfit/id1202650514
22. Dylan Mason, *Syncing an Apple Watch to Strava with HealthFit* — https://www.dylanmason.com/blog/2021/5/19/syncing-an-apple-watch-to-strava-with-healthfit
23. HealthSave, *FAQ* (free vs Pro $24.99 one-time) — https://healthsave.app/faq/
24. HealthSave, *Apple Health Data for Self-Hosters* — https://healthsave.app/for/self-hosters/
25. GitHub, `umutkeltek/healthsave-observatory` API docs (frozen v1 contract; Apache-2.0 / Elastic-2.0 split) — https://github.com/umutkeltek/healthsave-observatory/blob/main/docs/api/index.md
26. Quantified Self Forum, *QS Access on iOS 14* ("We no longer maintain this app") — https://forum.quantifiedself.com/t/qs-access-on-ios-14/8473
27. Quantified Self Forum, *QS Access App* (open-source requests; crash reports) — https://forum.quantifiedself.com/t/qs-access-app/1158
28. MetricBridge — https://www.healthexport.dev/
29. Gyroscope, *Products* (~$1/day G1; $3–8/day MAX) — https://gyrosco.pe/products/
30. Exist.io ($6.99/mo, $62.90/yr) — https://exist.io/
31. App Store, *HeadsUp: Health, Fasting, Keto* ($8.99/mo, $78.99/yr) — https://apps.apple.com/us/app/headsup-health-fasting-keto/id1399133678
32. HealthSave, *Apple Health's Export Gives You an Unusable XML File* — https://healthsave.app/guides/apple-health-export-xml-to-csv/
33. BitRecover, *Export Apple Health Data to PDF* (1 GB+ exports, memory exhaustion, hangs) — https://www.bitrecover.com/blog/export-apple-health-data-pdf/
34. BitRecover, *How to View Apple Health Data on PC* — https://www.bitrecover.com/blog/view-apple-health-data-on-pc/
35. GitHub, `irvinlim/apple-health-ingester` — https://github.com/irvinlim/apple-health-ingester
36. GitHub, `mrkhachaturov/hae-vault` — https://github.com/mrkhachaturov/hae-vault
37. Klebb (free OSS self-hosted health dashboard, HAE-fed) — https://klebb.app/
38. GitHub, `vpetersson/apple-health-mcp-server` — https://github.com/vpetersson/apple-health-mcp-server
39. GitHub, `smarzola/apple-health-mcp` — https://github.com/smarzola/apple-health-mcp
40. HealthyApps Help Center, *Data Missing in Export Files* (incl. per-medication authorisation) — https://help.healthyapps.dev/en/health-auto-export/troubleshooting/missing-data
41. GitHub, `HealthyApps/health-auto-export-mcp-server` — TCP server docs ("no TLS/auth", foreground only) — https://github.com/HealthyApps/health-auto-export-mcp-server/blob/main/docs/tcp-server.md
42. Brent Simmons, *On Not Taking Money for NetNewsWire* — https://inessential.com/2023/02/20/on_not_taking_money_for_netnewswire.html
43. GitHub, `Ranchero-Software/NetNewsWire` (MIT, 10.1k stars, 90 contributors) — https://github.com/Ranchero-Software/NetNewsWire
44. Apple Developer Program ($99 annual membership) — https://developer.apple.com/programs/
45. *The Open Source Maintainer Burnout Crisis Nobody's Fixing* (1.3% of repos with sponsorship; ~$50 median monthly) — https://medium.com/@sohail_saifii/the-open-source-maintainer-burnout-crisis-nobodys-fixing-5cf4b459a72b
46. PTKD Journal, *App Store health and medical data rules (5.1.3)* — https://ptkd.com/journal/app-store-health-medical-data-rules-5-1-3
47. App Store, *Health Auto Export* review detail (blood-pressure timestamps zeroed; unchecked metrics exported) — https://apps.apple.com/us/app/health-auto-export-json-csv/id1115567069?platform=ipad&see-all=reviews
48. *Export Apple Watch Health Data to Google Sheets* ("Apple Health data export happens on iPhone, even when sourced from Apple Watch") — https://smartwatch-straps.co.uk/blogs/blog/how-do-i-export-apple-watch-health-data-to-google-sheets
49. Asymco, *Apple Hits 2.5 Billion Active Devices* (Feb 2026) — https://asymco.com/2026/02/02/1-7-billion-customers/
50. Runify, *Apple Watch Running Statistics 2026* (170M+ active install base — third-party estimate) — https://www.runifyapp.com/blog/apple-watch-running-statistics
51. Home Assistant Analytics (676,069 active installations; "less than a fourth" opt in) — https://analytics.home-assistant.io/
52. HealthSave, *Backing Up Apple Health Before Switching to Android* ("no official path to move Apple Health into Google Fit or Android Health Connect") — https://healthsave.app/for/switching-to-android/
53. aQuickSoft, *iOS HealthKit App Privacy Review* (5.1.1 institutional expectations; common rejection patterns) — https://aquicksoft.com/blog/ios-healthkit-app-privacy-review
54. Home Assistant Community, *AppleHealth AutoExport* thread — https://community.home-assistant.io/t/applehealth-autoexport/419983
55. App Fair Project, *The GPL and Commercial App Stores* — https://appfair.org/blog/gpl-and-the-app-stores/
56. GitHub, `nextcloud/ios` — `COPYING.iOS` non-enforcement commitment — https://github.com/nextcloud/ios/blob/master/COPYING.iOS
57. Open Source StackExchange, *GPL with license exception for iOS?* — https://opensource.stackexchange.com/questions/8674/gpl-with-license-exception-for-ios
58. DEV Community, *Unlock your Apple Health data in 15 minutes* (~5M data points, ~20 min full sync) — https://dev.to/bartmichalak/unlock-your-apple-health-data-export-analyze-it-in-15-minutes-5ek9
59. GitHub, `carekit-apple/CareKit` issue #531 — rejection: "uses HealthKit, but does not appear to include any primary features that require health or fitness data" — https://github.com/carekit-apple/CareKit/issues/531
60. Apple, *Configuring HealthKit access* (purpose strings are an App Store requirement; background delivery) — https://developer.apple.com/documentation/xcode/configuring-healthkit-access
61. StackOverflow, *iOS app rejected because of HealthKit* (4.2.1 / metadata and UI evidence of integration) — https://stackoverflow.com/questions/39716868/ios-app-reject-because-of-healthkit
62. Apple, `HKError.Code.errorDatabaseInaccessible` — https://developer.apple.com/documentation/healthkit/hkerror/code/errordatabaseinaccessible
63. GitHub, `baccula/health-dashboard-export` ("Background sync timing is controlled by iOS… HealthKit data is inaccessible while the device is locked") — https://github.com/baccula/health-dashboard-export
64. DEV Community, *How to give Claude Code access to your Apple Health data* ("Apple has no HealthKit REST API… All access goes through an on-device app") — https://dev.to/jglitt/how-to-give-claude-code-access-to-your-apple-health-data-3p76
65. Apple, *Notarizing macOS software before distribution* — https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
66. Apple Developer Forums, *Is macOS notarization possible without a paid account?* — https://developer.apple.com/forums/thread/121113

### Research gaps — where I could not find current information

- **No public market-size estimate exists** for Apple Health export/automation tooling. My
  sizing rests on App Store rating counts [6], GitHub stars [7] and Home Assistant's
  install-base figures [51], all of which are proxies.
- **HAE's install base and revenue are not public.** 375 US ratings [6] is the best available
  signal and a weak one.
- **I found no large-N structured review corpus.** Apple's review RSS feed caps at 500 reviews
  and excludes star-only ratings [67], so I could not produce a "N of M reviews complain about
  X" figure. The complaints I cite are individually verifiable but not statistically weighted —
  treat frequency claims in this document as directional.
- **Reddit search returned no substantive r/QuantifiedSelf or r/HomeAssistant threads** beyond
  the Home Assistant community forum thread [54] and the QS forum [26][27]. I could not
  corroborate complaint volumes on those subreddits.
- **HealthSave's traction is unknown.** It appears to be a 2025/26 entrant (App Store ID
  6759843047) with no public download or revenue data.

67. Rivioo, *App Store 500-Review Export Limit* — https://www.rivioo.app/blog/app-store-review-limits
