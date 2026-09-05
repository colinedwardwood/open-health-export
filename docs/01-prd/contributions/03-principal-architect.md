# Principal Software Architect — Stage 1 Contribution

> Stage 1 deliverable. This document contains feasibility judgements, non-functional
> requirements and cut-line recommendations. It deliberately contains no module layouts,
> protocol definitions or code — those belong to Stage 2.
>
> Cost figures are in **engineer-weeks (EW)** for one competent Swift engineer working
> to a shippable standard (tests, error taxonomy, settings UI, docs). Where a figure is my
> judgement rather than a measured or cited fact, it is labelled **Assumption**.

---

## Executive summary

The reference product advertises eight destinations, three formats and 150+ metrics. Read as a
feature list this looks like eight units of work. It is not. Roughly 75% of the total cost of
this product sits in **one** place — a correctness engine that answers "did we export every
sample exactly once, and can we prove it" — and that engine is paid for once regardless of how
many destinations exist. The destinations themselves are cheap to write and expensive to *own*.
The consequence for the PRD is counter-intuitive: **cutting destinations barely reduces v1
cost, but it very substantially reduces the cost of still being alive in eighteen months.**
That is the trade we should be making, and we should make it aggressively.

Five findings that should change the PRD before it is written:

1. **HealthKit cannot be read on macOS.** `HKHealthStore.isHealthDataAvailable()` returns
   `false` on macOS 13 and later, including macOS 26 [1]. The framework links and compiles;
   it returns nothing. The brief's differentiator "first-class support across
   iOS / iPadOS / macOS / watchOS" is not a scope decision we get to make — it is
   architecturally false for three of the four platforms in the export role. macOS can be a
   *viewer* or a *receiving destination*; it cannot be an exporter. If the PRD lists macOS as
   a peer platform we will discover this in Stage 2 and redesign.

2. **HealthKit is unreadable while the device is locked**, returning
   `HKError.errorDatabaseInaccessible` [2][3]. Every "automatic export every N minutes"
   promise is therefore conditional on the user having unlocked their phone. Combined with
   the fact that background delivery fires on *saves* and effectively not on delete-only
   changes [4][5], and that `BGTaskScheduler` is opportunistic with no guaranteed cadence
   [6][7], **the product cannot offer a wall-clock freshness SLA.** This must be a stated
   requirement, not a discovered disappointment.

3. **The built-in TCP server is not buildable as advertised.** Apple's own networking
   engineer states that a background listening socket is "fundamentally incompatible with
   iOS's background execution model" and that Network framework has the same constraint as
   BSD sockets [8]. A TCP server on iOS works only while the app is foregrounded. Shipping
   one as a headline feature sets up a support burden we cannot discharge.

4. **The real trick in the reference product is aggregation, not raw sample export.** Every
   community integration for it configures `Summarize Data: ON` with hourly or daily time
   grouping [9][10]. Nobody ships 4.3 million raw samples to Grafana. Aggregation is a Must,
   not a Could — and it is *architecturally easier* than raw sample export, because an
   aggregate bucket is idempotent by construction (recompute and overwrite by bucket key),
   whereas raw samples require UUID-level upsert plus tombstones. A PRD that specifies only
   raw sample export will have specified the hard problem and missed the useful one.

5. **The 150-metric taxonomy is the single most under-costed line item.** I estimate
   9–18 engineer-weeks of pure semantic mapping work for full parity (see
   [Dependency and sustainability policy](#dependency-and-sustainability-policy)). It is
   boring, it is not automatable, and it cannot be validated without real multi-year data
   from real devices. It is three times bigger than it looks and it will not be done by
   volunteers.

My recommended v1 destination set is **three**: local file (user-chosen folder), generic
HTTPS, and MQTT — with Home Assistant delivered as a *preset* of the HTTPS destination
rather than an integration. Google Drive, Dropbox, Calendar, the TCP server, GPX and a
plugin model are all **Won't** for v1, for reasons given below.

---

## Integration surface: cost, risk and the recommended v1 cut line

### Destinations

| Destination | Impl. (EW) | Ongoing burden | Dependency risk | Credential complexity | Upstream break rate | v1 verdict |
|---|---|---|---|---|---|---|
| **Local file → user-chosen folder** (document picker + security-scoped bookmark) | 1.5 | Very low | None (Foundation) | None | Bookmark staleness on OS upgrade; ~annual | **Must** |
| **Generic HTTPS POST** (URL, method, headers, body template, gzip) | 3 | Low | None (URLSession) | User-supplied token in Keychain | None — it is our own contract | **Must** |
| **Home Assistant** | 0.5 *on top of* HTTPS | Very low | None | Long-lived token, or unauthenticated webhook URL | Very low; the REST/webhook contract has been stable for years | **Should** — as a preset, not an integration |
| **MQTT** | 3 | Medium | `mqtt-nio` (Apache-2.0) is mid-rewrite to 3.0 [11]; large SwiftNIO transitive graph | Username/password or client cert; TLS trust for self-signed brokers is the real pain | Library-driven, not protocol-driven | **Should** (see caveat) |
| **iCloud Drive** | 1 | Low | None | None | Rule risk, not technical risk | **Could**, reframed — see below |
| **Dropbox** | 3 | Medium–high | `SwiftyDropbox` (MIT, healthy) [12] | We must own a Dropbox app registration; app key embedded in a public repo | SDK majors ~annual; scope/permission changes | **Won't** |
| **Google Drive** | 5 | **High** | Google Sign-In + GTMAppAuth + Drive client; largest dep graph of any option | We must own a Google Cloud project, pass OAuth brand verification, and keep it verified; `drive.file` avoids the annual third-party CASA assessment, broader scopes do not [13][14][15] | Google OAuth policy changes are frequent and non-negotiable | **Won't** |
| **Calendar (EventKit)** | 2 | Low–medium | None | Write-only calendar access exists (iOS 17+), which is genuinely cheap | Low | **Won't** for v1 (low value, not low cost) |
| **TCP server** | 4 (and still broken) | High | None | None | N/A | **Won't** — not buildable in background [8] |
| **Mac companion receiver** (device-to-device over local network) | 5 | Medium | None (Network framework / MultipeerConnectivity) | Pairing UX | Low | **Won't** for v1 |

### Formats

| Format | Impl. (EW) | Verdict | Reasoning |
|---|---|---|---|
| **NDJSON** (newline-delimited JSON, gzip) | 1 | **Must** | Streamable in constant memory, appendable, resumable, trivially chunkable into HTTP bodies. This should be the native format. |
| **JSON** (single document) | 0.3 | **Must** | Required for HTTP bodies and for human inspection. Constrain to bounded batches; a single JSON document over a 4.3M-sample store is a memory bomb — the same mistake as DOM-parsing Apple's own 1.8 GB `export.xml` [16][17]. |
| **CSV** (RFC 4180, UTF-8, `.` decimal, ISO 8601) | 1.5 | **Should** | Cheap, and it is what non-programmers actually want. The cost is not the writer; it is deciding the column schema for 150 heterogeneous metrics. |
| **HAE-compatible JSON profile** | 1.5 | **Should** | Buys day-one compatibility with an existing installed base of sinks and dashboards [9][10][18]. See [Prior art](#prior-art-worth-reusing). |
| **GPX** | 2 | **Won't** v1 | Only meaningful for outdoor workouts with route data. Requires per-workout `HKWorkoutRouteQuery` fan-out, thousands of `CLLocation` objects per route, and Apple warns route points are accurate only to 50 m and need smoothing [19]. High cost, narrow audience, and it interacts badly with the batching model. |
| **FHIR R4** | 3+ | **Won't** v1 | Real value for a clinical audience we do not have yet. `HealthKitOnFHIR` (MIT) makes it tractable *later* [20]. |

### Narrative: why this cut line

**The generic HTTPS destination is the product.** Home Assistant's documented integration
path for third-party apps is a `POST` with an `Authorization: Bearer` header, or an
unauthenticated webhook URL [21][22]. That is a *configuration* of a generic HTTP client,
not an integration. Delivering Home Assistant as a preset (pre-filled URL shape, header,
payload template, and a "test connection" button) costs about half an engineer-week on top
of the HTTP destination and gives us the headline. Building it as a bespoke integration
would cost three and give us nothing extra. The same reasoning extends to InfluxDB,
Grafana Cloud, Prometheus remote-write endpoints, n8n, and anything else a self-hoster
runs: one destination, many presets. **This is the highest-leverage decision in the PRD.**

**Google Drive and Dropbox fail on ownership, not on code.** The adapter is a week. The
problem is that an OAuth-based cloud destination requires *the project* to own and
perpetually maintain a registered third-party application. For Google that means a Google
Cloud project, an OAuth consent screen, brand verification, and — if we ever need a scope
broader than `drive.file` — an annual security assessment by a Google-approved assessor
[13][15]. The client ID lives in a public repository. When Google changes its OAuth policy
(which it does, repeatedly and unilaterally), every installed copy of our app breaks
simultaneously and the only fix is a new App Store release. For a two-maintainer OSS
project this is an unbounded liability attached to a feature that a self-hoster — our stated
core audience — does not want. There is also a positioning contradiction: the brief claims a
privacy-first posture, and "your health data now transits Google's servers" is the opposite
of that.

**iCloud Drive needs reframing, not building.** App Store Review Guideline 5.1.3(ii) states
plainly that apps "may not store personal health information in iCloud" [23]. The reference
product ships an iCloud Drive backup feature, so a workable interpretation clearly exists in
practice — most likely that a *user-directed* write to a folder the user picked is different
from the app choosing to store PHI in iCloud on the user's behalf. I would not bet a release
on our reading of that line. **Recommendation:** do not build an "iCloud Drive destination"
at all. Build one local-file destination that writes to a folder the user selects through the
system document picker. If the user picks an iCloud-backed folder, that is the user's
decision, made in Apple's own UI, and we have no iCloud code, no ubiquity container, and no
5.1.3(ii) surface. Same user outcome, one destination instead of two, and the review risk
moves off our balance sheet. Note this rule also forecloses CloudKit-based settings sync for
anything that touches health data.

**MQTT is the one genuine judgement call.** It is the destination our audience actually
wants, and it cannot be faked with a preset. But it is also the only option that forces a
non-Apple runtime dependency into the app. `mqtt-nio` is Apache-2.0, SSWG-incubated, and
pulls `swift-nio`, `swift-nio-ssl`, `swift-nio-transport-services` and `swift-log` [11][24].
It is essentially a single-author project and 3.0 is an in-flight structured-concurrency
rewrite, i.e. a breaking change is queued. `CocoaMQTT` is lighter but its licence metadata
is inconsistent across sources (repo says MIT, GitHub reports "Other", CocoaPods reports
NOASSERTION) and the CocoaPods listing shows no SPM support [25][26] — for a project whose
entire premise is auditability, ambiguous licence metadata in a linked dependency is
disqualifying. **My recommendation: MQTT is a Should, gated on one explicit decision by the
PM — are we willing to accept one non-Apple runtime dependency with a known upcoming API
break?** If the answer is no, MQTT moves to v1.1 and we lose very little, because an MQTT
user can bridge from our HTTP destination via Home Assistant's `mqtt/publish` service [21]
in the meantime.

**The TCP server should be replaced, not descoped.** Users who want it want *pull* semantics:
"let my laptop or my LLM ask the phone for data." The affordable version of that intent is
App Intents plus Shortcuts (see [Extensibility](#extensibility-what-is-feasible-on-apple-platforms)),
which gives a scriptable read surface with none of the background-socket impossibility. We
should say in the PRD that we deliberately do not ship a server, and say why.

---

## Load-bearing correctness problems the PRD must address

These are the things that must be *decided* in requirements. Every one of them, left
undecided, becomes a class of user-visible data bug that is expensive to diagnose because it
only manifests over weeks on someone else's device with data we cannot see.

**1. Anchor durability and the write-ahead invariant.**
`HKQueryAnchor` is an opaque, per-sample-type cursor [27]. There will be roughly 150 of them.
The invariant that must be stated as a requirement: *the anchor is advanced only after the
corresponding batch is durably persisted to the outbound queue, in the same transaction.*
Get this backwards and a crash silently loses samples forever, because the anchor has moved
past data that was never enqueued. Corollary: duplicates are acceptable (the destination
upserts), gaps are not. This asymmetry should be written into the PRD explicitly, because it
drives every other decision here.

**2. Anchors are not sufficient on their own.** Anchors can be invalidated — device restore
from backup, reinstall, HealthKit re-sync events. A per-type anchor with no fallback means a
silent restart-from-zero (mass duplicate re-export) or, worse, a stale anchor that is
accepted and skips data. Requirement: maintain **both** a per-type anchor and a per-type
date high-water mark, plus a bounded **reconciliation sweep** — a periodic date-ranged
re-query of the last N days (default 7) compared against what we recorded as sent — and a
user-triggerable full reconcile. The sweep is how we can honestly answer "did we miss
anything". Without it, the answer is "we believe so", which is not a product claim.

**3. Deletions are best-effort and the PRD must say so.** Background delivery wakes the app
when samples are *saved*; a delete-only change frequently produces no callback until the next
insert of that type [4][5]. `HKDeletedObject` records are also not retained indefinitely, so
a delete followed by a long quiet period can be missed entirely [5]. Promising "deletions
propagate to your destination" is a promise we cannot keep. State it as: deletions are
propagated on a best-effort basis via tombstone records; guaranteed convergence requires a
reconciliation sweep, which detects removal by absence.

**4. Idempotency key.** `HKObject.uuid` is the only sane destination-side primary key. But an
"edit" in the Health app is a delete plus a fresh insert with a *new* UUID, so UUID stability
does not mean value stability. Requirement: the destination contract is *upsert by sample
UUID*, plus a separate tombstone stream, and the payload schema must carry the UUID as a
first-class field for every sample. This one requirement is what makes the whole retry story
safe, and it is the single most important line in the export schema.

**5. Ordering and late-arriving data.** The stream is emphatically not ordered by sample
time. An Apple Watch syncs hours late; third-party apps backfill weeks of history in one
write; a restored backup injects years at once. Requirement: every record carries both the
sample's own time range **and** an `observedAt` (when *we* saw it). Destinations must be
documented as forbidden from ordering by sample timestamp or from treating "newest sample
seen" as a watermark. Any reference sink we ship must demonstrate correct behaviour under
out-of-order arrival, and the QA stage should have a test that replays a batch in reverse.

**6. Durable queueing, retry and the drop policy.** Background `URLSession` is the correct
primitive: file-based upload tasks survive app suspension and system termination, and the
system relaunches the app to deliver completion events [28][29]. Two limits must be written
into requirements. First, **a user force-quit cancels background transfers and the system
will not relaunch the app** [30] — so the queue must be reconstructible from our own
persisted state, never from URLSession state. Second, the queue is finite. The PRD must
choose and publish a **bounded queue size and an explicit drop policy** (my recommendation:
256 MB cap, oldest-batch-first eviction, with a persistent, user-visible "N samples were
dropped between date A and date B" record and a one-tap re-export of that window). Silently
dropping health data is the worst possible failure for this product; silently growing to fill
the device is the second worst. Choosing between them is a product decision, not an
implementation detail.

**7. Multi-device conflicts.** iPhone and iPad both have readable HealthKit stores with
overlapping-but-not-identical contents. If both run the app and target the same destination,
you get two independent anchor sets producing overlapping streams. Upsert-by-UUID makes this
*harmless* rather than *correct* — but the aggregate export mode is not protected the same
way, because two devices will compute different daily totals from different subsets of data
and overwrite each other. Requirement: each installation has a stable exporter instance ID
carried in the payload; each destination has exactly one designated exporter device by
default, chosen by the user, with the others explicitly in a "read-only / manual export"
state. (The iPhone-plus-Mac conflict named in the brief does not arise, because the Mac
cannot read HealthKit [1].)

**8. Time zones — this is worse than it looks.** HealthKit stores absolute instants. There is
no time zone field on `HKSample`; there is only an optional `HKMetadataKeyTimeZone` metadata
entry that the *writing* app must have chosen to populate [31][32]. Measured reality, from a
maintainer's full-sync audit: regular records (steps, heart rate) **never** carry it; Apple
Watch sleep records essentially always do (2,024 of 2,026 records); workouts carry it only
when recorded by an Apple Watch (5 of 19) [33]. Falling back to the device's *current* time
zone falsifies history — the user may have been in Tokyo. Requirements: (a) emit UTC instants
always; (b) emit the time zone when known **and** a `timeZoneSource` enum
(`sampleMetadata` | `inferred` | `deviceCurrent` | `unknown`) so the consumer can decide
whether to trust it; (c) never silently substitute the current zone.

**9. DST and daily bucketing.** A "day" is 23 or 25 hours twice a year, and "local midnight"
is unknowable for most samples per (8). Requirement: a local-time bucket is defined as a
calendar day in an explicit IANA zone that the *user* selects for the export configuration,
and every emitted bucket carries the zone ID plus the bucket's absolute UTC start and end.
Any daily/weekly/monthly aggregate must be labelled as computed in that named zone. Without
this, users comparing our daily step totals against the Health app will find discrepancies
around travel and DST boundaries and will report them as data loss.

**10. Statistics do not equal the sum of samples.** HealthKit's statistics queries
de-duplicate overlapping data from multiple sources (iPhone and Watch both counting steps);
naively summing raw samples double-counts. Two exports of "steps" — one raw, one aggregated —
will legitimately disagree, and users will file that as a bug. Requirement: the metric
catalogue declares, per metric, the canonical aggregation semantics (cumulative vs discrete,
sum vs mean vs min/max), and every aggregate record states which computation produced it. Do
not let this be discovered by a user with a spreadsheet.

**11. Units and locale.** `HKUnit` is explicit, so unit *correctness* is tractable; unit
*consistency* is the requirement. Emit one canonical unit per metric regardless of the user's
locale or Health app display preference, and carry the unit string in the payload. Separately:
machine-readable output must never be locale-formatted. `.` as decimal separator, ISO 8601
timestamps with explicit offset, UTF-8, RFC 4180 CSV. A German user's export must not contain
`72,5` for heart rate. This is a two-line requirement that prevents a whole class of
downstream breakage.

**12. Schema evolution.** The payload schema is a public API from the first release, because
someone will build a server against it within a week. Requirement: `schemaVersion` in every
payload from day one; additive-only changes within a major version; a stated compatibility
window (I suggest: any major version remains emittable for at least 12 months after its
successor ships, selectable per destination). This is cheap now and impossible to retrofit.

**13. Clock skew.** `observedAt` comes from a device clock the user can set to anything, and
sample times come from whichever device recorded them. Requirement: destinations must not use
any of our timestamps as an ordering or de-duplication key (see (5)); include a monotonically
increasing per-installation batch sequence number for that purpose. Also: do not use
timestamps in idempotency keys.

**14. Freshness cannot be promised.** Composing (2), (4) and (6) from the executive summary:
HealthKit is unreadable while locked [2], `BGAppRefreshTask` gets roughly 30 seconds at times
the system chooses [6][7], and watchOS shares a budget of about four wakes per hour with
complication refreshes [4]. Requirement: express delta latency as a distribution conditioned
on device unlock (see NFRs), and state prominently in the product copy that automatic export
is opportunistic. Every competitor's one-star reviews are about this. We should be honest
about it in the PRD and in the UI rather than in a support thread.

---

## Extensibility: what is feasible on Apple platforms

**A plugin model is not available.** App Store Review Guideline 2.5.2 forbids downloading,
installing or executing code that introduces or changes app functionality, and Apple's
rejection letters explicitly name dynamic symbol resolution (`dlopen`, `dlsym`,
`performSelector:` with remote-derived arguments) as triggers — the reviewer reads the binary's
symbol table, not your intent [34][35][36]. An embedded scripting runtime executing
user-supplied destination code is the exact shape Apple rejects. This is not a "risky but
possible" area; it is closed. Requirement: **AR-22, Won't — no dynamic code loading, ever.**

**The cheap 80% is three things, and it costs about four engineer-weeks total:**

1. **A declarative HTTP request template.** URL, method, headers, and a body template with a
   small, closed, *non-Turing-complete* substitution grammar — named field placeholders,
   simple formatting directives, no conditionals, no loops, no expression evaluation. This is
   data-driven configuration, which stays clearly on the safe side of 2.5.2 [35]. It covers
   every request/response destination anyone will ask for: InfluxDB, VictoriaMetrics,
   Prometheus remote-write, n8n, Node-RED, a self-hosted Flask endpoint, a Grafana Cloud
   ingest URL. **~2 EW** on top of the base HTTP destination.
   *Security note for Stage 2:* templated headers are a credential-exfiltration surface (a
   token templated into a request whose URL the user was tricked into changing). Credentials
   live in the Keychain, are referenced by handle rather than interpolated into stored config,
   and configuration export/sharing must redact them. Requirement, not implementation detail.

2. **App Intents with `supportedModes = [.background]`,** exposed to Shortcuts [37][38]. This
   is the answer to "I want to script it," and it is where the deleted TCP server's use cases
   go. The user composes "export the last hour of heart rate → do something arbitrary" in
   Apple's own automation UI, using every other app on their phone as the destination. It
   costs us **~1.5 EW** and it is a genuine differentiator that the reference product only
   partially has. Note the constraint honestly: background intents get roughly 30 seconds, so
   the intent must expose bounded operations (`export window`, `export since last sync`),
   not "export everything."

3. **A documented, versioned payload schema plus a reference sink.** The extension point that
   actually gets used in OSS is "here is the wire format, here is a working server, go."
   **~0.5 EW** beyond work we are doing anyway.

**A config-driven destination is feasible only for request/response protocols.** MQTT needs a
connection lifecycle, QoS and topic-tree semantics; OAuth destinations need a redirect dance
and token refresh; a filesystem needs security-scoped bookmarks. None of these are
expressible as a template. So the honest framing for the PRD is: *one extensible destination
(HTTP) plus a small number of hand-built ones.* Do not write a requirement for "a plugin
architecture for destinations" — it will produce an abstraction in Stage 2 that carries the
cost of generality with a population of exactly three implementations.

---

## Non-functional requirements

### Reference devices and reference data

| ID | Definition | Why this one |
|---|---|---|
| **REF-PHONE-A** | iPhone 15 (A16, 6 GB RAM), iOS 26.6 | Mainstream target; two-year-old mid-range at time of writing |
| **REF-PHONE-B** | iPhone 11 (A13, 4 GB RAM), iOS 26.6 | The **floor**: oldest device iOS 26 supports [39]. All ceilings must hold here. |
| **REF-WATCH** | Apple Watch Series 9, watchOS 26.6 | Only relevant if a watch target is in scope |
| **REF-MAC** | MacBook Air (M2, 16 GB), macOS 26.6 | Viewer/receiver role only [1] |
| **REF-STORE-XL** | Synthetic HealthKit store: **4.3 M samples spanning 10 years** | Basis: a measured real-world 10-year Apple Watch user's `export.xml` is 1.8 GB / **4.26 M records** [16][17]. Cited, not guessed. |
| **REF-STORE-M** | Synthetic store: 450 k samples spanning 1 year, iPhone + Watch | The realistic median new user |
| **REF-DELTA** | 20 k samples/day steady state | Assumption: a Watch-wearing user generating continuous HR, HRV, activity and sleep data. To be validated with real device measurement in Stage 4. |

### Targets

| ID | NFR | Target | Device | Basis / reasoning |
|---|---|---|---|---|
| NFR-01 | Cold start, foreground, to interactive UI | p90 ≤ 1,200 ms | REF-PHONE-B | Standard SwiftUI app expectation; halved on REF-PHONE-A (≤ 700 ms) |
| NFR-02 | **Headless background launch to first HealthKit query issued** | ≤ 400 ms | REF-PHONE-B | The `BGAppRefreshTask` budget is ~30 s total [6][7]. Spending 8 s on dependency-graph construction burns 27% of the budget before any work — a documented failure mode [7]. This NFR is more important than NFR-01. |
| NFR-03 | Initial full-history export throughput | ≥ 1,600 samples/s sustained | REF-PHONE-A | Derived: 4.3 M samples ÷ 45 min. **Assumption** — must be validated by a Stage 2 spike before the PRD is signed off. If real throughput is 400/s, the full-history story changes shape completely. |
| NFR-04 | Initial full-history export wall clock, REF-STORE-XL → local NDJSON+gzip | ≤ 45 min (REF-PHONE-A); ≤ 90 min (REF-PHONE-B) | both | Follows from NFR-03 at 1.0× and 0.5× throughput |
| NFR-05 | Peak resident memory, full-history export | ≤ 150 MB (REF-PHONE-A); ≤ 120 MB (REF-PHONE-B) | both | Requires strict streaming: never materialise more than one query page. This is the constraint that kills "build a JSON document then write it" — the same error that makes DOM parsers die on Apple's 1.8 GB export [16] |
| NFR-06 | Peak resident memory under `BGProcessingTask` | ≤ 100 MB | REF-PHONE-B | **Assumption**: background jetsam headroom is tighter than foreground and is not documented as a fixed figure. Stage 2 must measure. |
| NFR-07 | Delta export, 10 k samples, HealthKit read → durably enqueued | ≤ 8 s (REF-PHONE-A); ≤ 15 s (REF-PHONE-B) | both | 10 k ÷ 1,600/s = 6.3 s plus serialisation. (The brief's illustrative "<5 s on iPhone 13" is optimistic; I would not sign up to it without NFR-03 evidence.) |
| NFR-08 | Delta export freshness, from sample landing in HealthKit to accepted at destination | p50 ≤ 90 s **and** p95 ≤ 60 min, **both measured only over intervals in which the device was unlocked at least once**; no target while locked | REF-PHONE-A | Unavoidable: HealthKit is unreadable while locked [2][3] and `BGTaskScheduler` is opportunistic [6][7]. Any unconditional freshness number in the PRD would be a fiction. |
| NFR-09 | Steady-state CPU budget | ≤ 90 CPU-seconds per 24 h at REF-DELTA volume | REF-PHONE-A | Derived: 20 k samples ÷ 1,600/s ≈ 13 s of core work; remainder is wake overhead, TLS, serialisation. Measured via MetricKit `cumulativeCPUTime`. |
| NFR-10 | Steady-state battery | ≤ 1.0% of battery per 24 h at REF-DELTA volume | REF-PHONE-A | 90 CPU-s at ~1.5 W ≈ 0.04 Wh against a ~13 Wh battery ≈ 0.3%; 1.0% leaves 3× headroom for radio wake. **Assumption** on the power figure; verify with Xcode Energy Log. |
| NFR-11 | One-time full-history export battery | ≤ 12% of battery, and **must not be initiated from a system-scheduled background task** | REF-PHONE-A | 45 min of sustained work is ~8–10% by the same arithmetic. This is why NFR-12 exists. |
| NFR-12 | Full-history export execution model | User-initiated via `BGContinuedProcessingTask`, with system progress UI and user cancellation | REF-PHONE-A | iOS 26 API designed for exactly this — Apple's own Journal app uses it for file export [40][41]. Requires an explicit user action to start [41]. |
| NFR-13 | Checkpoint granularity | Termination at any instant loses ≤ 0 samples and re-sends ≤ 1 batch (≤ 5,000 samples) | REF-PHONE-B | `BGProcessingTask` is killed the moment the user picks up the device [6]. Recovery must be cheap and must never lose data. |
| NFR-14 | On-disk footprint: app + configuration + state | ≤ 60 MB installed, excluding the outbound queue and user-chosen export files | REF-PHONE-A | Keeps us honest about SQLite/index bloat over years |
| NFR-15 | Outbound queue cap | Hard cap 256 MB, with oldest-first eviction and a persisted, user-visible gap record | REF-PHONE-A | At REF-DELTA (~6 MB/day raw, ~600 KB gzipped) a 256 MB cap absorbs well over a year of destination downtime, so eviction should be effectively unreachable in practice. That is the point: the cap exists to bound worst-case disk, not to be hit. |
| NFR-16 | Network efficiency | gzip mandatory; ≥ 8:1 on NDJSON payloads; ≤ 1 HTTP request per 5,000 samples or 4 MB uncompressed body, whichever first | REF-PHONE-A | 8:1 is conservative — Apple's own health XML compresses 25:1 (1.8 GB → 71 MB) [17] and NDJSON starts denser |
| NFR-17 | Metered network | Zero bytes over cellular unless explicitly enabled per destination; default off | REF-PHONE-A | `allowsExpensiveNetworkAccess` / `allowsConstrainedNetworkAccess` [28][29] |
| NFR-18 | Correctness over a soak | 30-day continuous soak against a reference sink: **0 missed samples**; duplicates ≤ 0.1% | REF-PHONE-A | Duplicates are harmless under upsert-by-UUID; gaps are not. Asymmetric target on purpose. |
| NFR-19 | Crash-free sessions | ≥ 99.8% | REF-PHONE-A + REF-PHONE-B | A crash mid-export is a correctness event, not just a stability event |
| NFR-20 | watchOS wake budget, **if** a watch target is in scope | Complete useful work within 4 wakes/hour, shared with complication refresh | REF-WATCH | Documented Apple limit [4] |

---

## Dependency and sustainability policy

**Licence constraint — this one is binary.** The app will be distributed through the App
Store. Apple's Terms of Service impose usage restrictions that are incompatible with the
GPL's prohibition on further restrictions; the FSF enforced exactly this against GNU Go, and
VLC was pulled from the App Store on the same grounds [42][43][44]. LGPL is also
problematic, because its relinking expectation conflicts with iOS static linking and
guideline 2.5.2 [45]. Therefore:

- **The project itself must be licensed permissively — MIT or Apache-2.0.** A GPL-licensed
  "genuinely open source health app" cannot be shipped on the App Store by its own
  maintainers. If the PRD asserts both "genuinely open source" and "available on the App
  Store", the licence choice is already constrained and should be recorded as an ADR now, not
  argued about in Stage 3. My recommendation: **Apache-2.0** (explicit patent grant, NOTICE
  discipline that suits a project handling health data).
- **No copyleft in anything we link.** Permitted: MIT, BSD-2/3, Apache-2.0. Prohibited:
  GPL, LGPL, AGPL, and any dependency whose licence metadata is inconsistent across its
  repository, package index and manifest (this disqualifies `CocoaMQTT` on current
  evidence [25][26]).

**Dependency budget.** Target **zero** non-Apple runtime dependencies in shipping app
targets, with a hard ceiling of **three**, each requiring a written justification in an ADR.
Rationale, in order of severity: (1) every dependency is a Swift 6 language-mode migration
you do not control; (2) every dependency needs a privacy manifest you must audit and vouch
for; (3) every dependency is a supply-chain surface in an app that handles health data. If
MQTT is approved, that is one of the three, and it drags in four transitive SwiftNIO packages
— which is the honest cost of the feature and should be stated as such in the PRD.

Mechanics: exact-version pins, `Package.resolved` committed, automated update PRs with a
7-day cooling-off before merge, a published SBOM per release, and reproducible builds as a
stretch goal. Test-only and tooling dependencies are governed separately and more loosely.

**The uncomfortable numbers.**

- **One maintainer can keep about three destination integrations alive. Two maintainers,
  about five.** Basis (**assumption**, from my own experience of OSS integration
  maintenance): each credentialed third-party integration costs 0.5–1 engineer-day per month
  in steady state — SDK majors, OAuth policy changes, API deprecations, platform betas, and
  the support triage where you cannot see the user's data or their broker. A realistic OSS
  maintainer has 4–8 hours per week *in total*, including reviews, releases and issue triage.
  Eight destinations is 4–8 engineer-days per month of pure maintenance, which is most of a
  volunteer's entire capacity before a single feature is written. HealthyApps sustains that
  surface because it is a paid product with revenue funding it. We are not, and the PRD
  should not pretend otherwise.

- **The 150-metric taxonomy is 9–18 engineer-weeks.** Basis (**assumption**, decomposed):
  iOS 26 exposes roughly 100 `HKQuantityType` identifiers plus ~65 `HKCategoryType`
  identifiers, plus workouts, ECG, audiograms, series types and clinical records. Per type
  the irreducible work is: canonical field name, canonical unit, aggregation semantics
  (cumulative vs discrete, and which statistic is meaningful), enum decoding for category
  types, value-range sanity bounds, a fixture, and a test. At 0.3–0.6 engineer-days per type
  once a harness exists, 150 types is 45–90 engineer-days. It is not parallelisable across
  volunteers without a very strong harness, and it cannot be validated without real
  multi-year data from real devices — which no single contributor has for all 150 types.
  **This is the line item most likely to sink the schedule, and it does not look like a risk
  on a feature list.**

  **Recommendation:** v1 ships ~40 curated metric families chosen by actual usage
  (steps, distance, active/basal energy, heart rate, resting HR, HRV, VO₂max, respiratory
  rate, SpO₂, sleep stages, workouts, body mass/composition, blood pressure, blood glucose,
  mindful minutes, exercise/stand minutes and their close relatives) with full declared
  semantics, plus a **generic passthrough** for every other type that emits the raw HealthKit
  identifier, raw value and raw unit with an explicit `semantics: "unmapped"` marker. That
  gets us to "150+ metrics exported" honestly on day one, at roughly a fifth of the cost,
  and it turns the taxonomy into an incremental, community-contributable backlog with a
  natural review checklist.

---

## Prior art worth reusing

| Project | Licence | Health (as of Sep 2026) | Verdict |
|---|---|---|---|
| **[HealthKitOnFHIR](https://github.com/StanfordBDHG/HealthKitOnFHIR)** (Stanford BDHG) | MIT [20] | 28★, 3 open issues, actively maintained | **Reuse the mapping data, even if we never emit FHIR.** Its customisable HealthKit-type → standardised-code (LOINC) mappings are precisely the expensive taxonomy artefact described above, already curated and MIT-licensed. Strongest reuse candidate on this list. |
| **[SpeziHealthKit](https://github.com/StanfordSpezi/SpeziHealthKit)** | MIT [46] | 40★, 16 open issues, release Dec 2025 | **Read, don't link.** It solves our exact problem (long-lived background collection, `handleNewSamples` / `handleDeletedObjects` seams) and its design is worth studying closely. But it is a module of the wider Spezi *application* framework, so depending on it means adopting Spezi's app lifecycle. Wrong coupling for a single-purpose exporter. |
| **[HealthKitReporter](https://github.com/kvs-coder/HealthKitReporter)** | MIT [47] | 90★, 9 open issues, essentially single-maintainer, CocoaPods-era | **Reference only.** Codable wrappers for HK types are useful prior art for our schema, but Swift 6 strict-concurrency status is unclear and the bus factor is 1. |
| **[mqtt-nio](https://github.com/swift-server-community/mqtt-nio)** | Apache-2.0 [11][24] | SSWG Sandbox; 2.13.0 stable (Feb 2026), 3.0.0-alpha.1 (Jun 2026); one primary author | **The correct choice if MQTT ships**, with eyes open: an API break is queued in 3.0, and it pulls `swift-nio` + `-ssl` + `-transport-services` + `swift-log`. |
| **[CocoaMQTT](https://github.com/emqx/CocoaMQTT)** | Ambiguous — repo says MIT, GitHub reports "Other", CocoaPods reports NOASSERTION and no SPM support [25][26] | 1,749★, 126 open issues, release Jul 2026 | **Reject.** Popular and lighter, but inconsistent licence metadata is disqualifying for a project whose premise is auditability, and the missing SPM support is a second strike. |
| **[opentelemetry-swift](https://github.com/open-telemetry/opentelemetry-swift)** | Apache-2.0 [48] | 359★, **123 open issues**; tracing/baggage stable, **logs beta**, **metrics on an outdated spec**; CocoaPods being deprecated Jul–Dec 2026 [49] | **Opt-in only, and read the status line carefully.** The brief's "observable by design" differentiator currently rests on a package whose logs signal is beta and whose metrics implementation is knowingly non-conformant. See [Where the premise is wrong](#where-the-premise-is-wrong). |
| **[swift-log](https://github.com/apple/swift-log)** | Apache-2.0 | Apple-maintained, SSWG graduated | **Adopt.** Cheapest possible route to the "structured logging" half of the observability claim. |
| **[Health Auto Export JSON format](https://github.com/Lybron/health-auto-export/wiki)** + **[health-auto-export-server](https://github.com/HealthyApps/health-auto-export-server)** | Docs/server public; format is a third party's product surface | Server 148★; a visible community of third-party sinks built against it [9][10][18] | **Ship an optional HAE-compatible payload profile (~1.5 EW).** This is the highest-value-per-week item in this whole document: it makes us drop-in compatible with an existing installed base of Grafana dashboards and ingest servers on day one, which is otherwise years of ecosystem building. Caveat: it is someone else's undocumented-drift-prone schema, so treat it strictly as a compatibility *profile* over our own versioned native schema, never as the native schema. |
| **[healthsync](https://github.com/BRO3886/healthsync)** (Go) | Public | Active | **Cross-check only.** Not reusable, but its metric→table/unit schema and its `INSERT OR IGNORE` idempotent re-import pattern are a useful independent validation of our schema decisions [16]. |

**Swift 6 concurrency note (affects Stage 2, flagged now because it affects effort
estimates):** HealthKit's object model is largely non-`Sendable` — `HKSample`,
`HKWorkoutBuilder` and friends are classes that predate strict concurrency, and passing them
out of a query callback into an actor produces "sending risks causing data races" errors. The
community answer is `@preconcurrency import HealthKit` plus converting to `Sendable` value
types at the framework boundary [50][51][52]. This is manageable and in fact *good* design for
us — we want to convert to our own value types immediately anyway — but "Swift 6 strict
concurrency" in the brief should be understood as "strict in our code, with one
`@preconcurrency` seam at the HealthKit boundary", not as a clean-room property. Budget
1–2 EW for the boundary layer.

---

## Requirements I own

| ID | Requirement | Priority | Rationale | How we verify |
|---|---|---|---|---|
| **AR-01** | Platform roles are asymmetric and stated: iOS and iPadOS are exporters; macOS is a viewer and/or receiving destination only; watchOS is not an exporter. | Must | `isHealthDataAvailable()` returns `false` on macOS [1]. Non-negotiable platform fact. | Platform capability matrix in the PRD; a runtime assertion test that the macOS target contains no HealthKit read path |
| **AR-02** | Exactly one export/correctness engine; every destination is a sink behind a single internal contract. No destination may hold its own cursor or retry state. | Must | 75% of cost is the engine. Duplicating it per destination multiplies the bug surface by the number of destinations. | Architecture review at Stage 2 gate; a conformance test suite every sink must pass |
| **AR-03** | Per-sample-type anchors are advanced only in the same durable transaction that persists the outbound batch (write-ahead). Gaps are forbidden; duplicates are permitted. | Must | A crash between "anchor advanced" and "batch persisted" loses data permanently and silently. | Fault-injection test: kill the process at every step of the pipeline; assert zero gaps |
| **AR-04** | Maintain a per-type date high-water mark alongside each anchor, plus a bounded reconciliation sweep (default trailing 7 days) and a user-triggerable full reconcile. | Must | Anchors can be invalidated by restore/reinstall/HealthKit re-sync. The sweep is the only mechanism that lets us answer "did we miss anything". | Restore-from-backup test; deliberate anchor corruption test; reconcile detects and repairs |
| **AR-05** | Every exported sample carries `HKObject.uuid`. The destination contract is upsert-by-UUID. | Must | Makes retry, duplicate delivery and multi-device overlap harmless instead of corrupting. | Schema validation; replay the same batch 10× against the reference sink and assert an unchanged row count |
| **AR-06** | Deletions are propagated as tombstone records on a **best-effort** basis, documented as such; guaranteed convergence is via AR-04 only. | Must | Background delivery does not reliably fire on delete-only changes and `HKDeletedObject` is not retained indefinitely [4][5]. | Delete-only-change test documenting actual observed behaviour; product copy review |
| **AR-07** | Every payload carries `schemaVersion`. Additive-only within a major. Any major remains selectable for ≥ 12 months after its successor ships. | Must | The schema is a public API from release day. | Schema-diff CI gate that fails on non-additive change within a major |
| **AR-08** | Every record carries UTC instants, the sample time zone when known, and a `timeZoneSource` enum (`sampleMetadata`/`inferred`/`deviceCurrent`/`unknown`). Never silently substitute the current zone. | Must | `HKMetadataKeyTimeZone` is absent for essentially all non-sleep records [31][32][33]. | Fixture set covering all four source cases; assert no record ever reports `sampleMetadata` without metadata present |
| **AR-09** | Local-time bucketing requires a user-selected IANA zone; every bucket carries the zone ID plus absolute UTC start/end. | Must | 23/25-hour days; travel; per AR-08 the recording zone is usually unknown. | DST-boundary test in a DST-observing zone (both directions) and a zone-change test |
| **AR-10** | Aggregated/summarised export is a first-class mode with idempotent bucket keys, not an add-on to raw sample export. | Must | This is what real users configure [9][10], and it is the volume lever that makes the product usable. | Recompute-and-resend a bucket; assert convergence at the sink |
| **AR-11** | Canonical unit per metric independent of locale; machine formats use `.` decimal separator, ISO 8601 with offset, UTF-8, RFC 4180 CSV. | Must | Locale-formatted numbers in machine output break every downstream consumer. | CI runs the export suite under `de_DE`, `ar_EG` and `en_US` and byte-compares output |
| **AR-12** | Bounded outbound queue (256 MB) with oldest-first eviction, a persisted user-visible gap record, and one-tap re-export of the evicted window. | Must | The only alternatives are silent data loss or filling the user's device. This choice must be the product's, made explicitly. | Fill-the-queue test; assert gap record accuracy and successful re-export |
| **AR-13** | Exponential backoff with jitter, per-destination circuit breaker, bounded retry with a terminal failed state surfaced in the UI. No unbounded retry loops. | Must | An always-down destination must not burn battery or hide failure from the user. | Fault-injection harness across 4xx/5xx/timeout/TLS-failure/DNS-failure |
| **AR-14** | Records carry `observedAt` (device clock) and a per-installation monotonic batch sequence, distinct from sample times. Destinations are documented as forbidden from ordering or de-duplicating by timestamp. | Must | Late-arriving and backfilled data; user-settable clocks. | Out-of-order replay test; clock-skew test with the device clock set backwards |
| **AR-15** | Each installation has a stable exporter instance ID in the payload. Each destination has one designated exporter device by default; others are manual-export only. | Should | iPhone + iPad both readable; aggregate mode is not protected by upsert-by-UUID. | Two-device soak against one sink; assert no aggregate flapping |
| **AR-16** | The product makes no unconditional wall-clock freshness guarantee. Freshness is specified and communicated as conditional on device unlock (NFR-08). | Must | HealthKit is unreadable while locked [2][3]; `BGTaskScheduler` is opportunistic [6][7]. | Product copy review; locked-device soak measuring the actual distribution |
| **AR-17** | Full-history export is user-initiated, runs under `BGContinuedProcessingTask` with system progress UI and cancellation, and is resumable. | Must | The only iOS 26 mechanism sized for tens of minutes of work; requires explicit user action [40][41]. | Manual test on REF-PHONE-B; cancel and resume mid-export |
| **AR-18** | Credentials live in the Keychain, referenced by handle. Configuration export/backup/sharing redacts all secrets. Templates may reference credentials but stored config never contains them. | Must | Templated headers are a credential-exfiltration surface; users will share configs in GitHub issues. | Security review of the config export path; grep-based CI check on exported fixtures |
| **AR-19** | No telemetry leaves the device to any endpoint the project controls. Default observability is a local, human-readable, exportable export journal. | Must | 5.1.3(i) restricts third-party disclosure of HealthKit-derived data [23]; the brief promises no tracking. | Network-egress test on a clean install with default settings: assert zero requests to non-user-configured hosts |
| **AR-20** | OTLP export is opt-in, targets a user-supplied collector only, carries no health values and no sample UUIDs, and emits at most one span per batch. | Should | Resolves the brief's stated privacy/observability tension by making telemetry a destination the user owns. Per-sample spans would also be a cardinality disaster. | Span/attribute allow-list test; assert no health-typed field can appear in telemetry |
| **AR-21** | The generic HTTP destination is configured by a declarative template with a closed, non-Turing-complete substitution grammar. No runtime expression evaluation. | Must | Guideline 2.5.2 forbids downloaded/executed code that changes functionality [34][35]. Data-driven config is safe; an evaluator is not. | Grammar spec review; binary symbol audit for `dlopen`/`dlsym`/dynamic dispatch on remote input |
| **AR-22** | No plugin system and no dynamic code loading of any kind, in any release. | Won't | Closed by platform rule [34][35][36]. Stating it as Won't prevents recurring debate. | Static analysis in CI |
| **AR-23** | Background App Intents exposed to Shortcuts for bounded export operations (`export window`, `export since last sync`). | Should | The affordable answer to "let me script it", and the replacement for the impossible TCP server [37][38]. | Manual Shortcuts automation test on device; assert completion within the background intent budget |
| **AR-24** | v1 covers ~40 curated metric families with fully declared semantics, plus a generic passthrough for all remaining HealthKit types marked `semantics: "unmapped"`. | Should | Full 150-metric semantics is 9–18 EW. This gets honest coverage at ~20% of the cost and makes the rest a community backlog. | Catalogue completeness test against the iOS 26 SDK's type list; assert every type is either curated or passthrough, none silently dropped |
| **AR-25** | Ship an optional Health-Auto-Export-compatible payload profile alongside the native schema. | Should | Day-one compatibility with an existing installed base of sinks and dashboards [9][10][18]. | Round-trip our output through `health-auto-export-server` and assert its dashboards populate |
| **AR-26** | The project is licensed permissively (Apache-2.0 recommended). No GPL/LGPL/AGPL dependency may be linked. No dependency with inconsistent licence metadata may be linked. | Must | GPL is incompatible with App Store distribution [42][43][44]; LGPL relinking conflicts with iOS static linking [45]. | Automated licence scan in CI with an explicit allow-list |
| **AR-27** | Maximum three non-Apple runtime dependencies in shipping app targets; each requires an ADR. Exact version pins; `Package.resolved` committed; SBOM published per release. | Must | Dependency count is the strongest single predictor of OSS maintenance load and supply-chain exposure. | CI gate counting resolved runtime dependencies; SBOM artefact per release |
| **AR-28** | v1 destination set is: local file (user-chosen folder), generic HTTPS, MQTT (gated on AR-27), Home Assistant preset. | Must | See cut-line analysis. | PRD scope statement |
| **AR-29** | Explicitly out of scope for v1: Google Drive, Dropbox, Calendar, a TCP/network server, a bespoke iCloud Drive destination, GPX, FHIR, a macOS HealthKit reader, a watchOS exporter. | Won't | Each is justified above; several are impossible rather than merely expensive. | PRD scope statement; reviewer sign-off |
| **AR-30** | The metric catalogue declares, per metric, the canonical aggregation semantics; every aggregate record states which computation produced it. | Must | HealthKit statistics de-duplicate multi-source data; naive sample summation double-counts. Users will find the discrepancy. | Compare our aggregates against `HKStatisticsCollectionQuery` for a multi-source metric on a real device; document any divergence |
| **AR-31** | Cellular and other metered/constrained networks are off by default, per destination. | Should | Health payloads are small but full-history exports are not; a 130 MB surprise on a metered plan is a one-star review. | Network-condition test with cellular-only connectivity |
| **AR-32** | A reference sink (self-hostable, permissively licensed) ships alongside v1 and is the executable definition of the destination contract. | Should | It is the real extension point, it is how we test AR-05/AR-14/AR-18, and it is how self-hosters adopt us. | The sink's conformance suite is part of the release gate |

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Real HealthKit read throughput is far below NFR-03 (≥ 1,600 samples/s), invalidating the full-history export NFRs | Medium | High — reshapes the product's flagship operation | **Stage 2 spike before the PRD is signed off**: measure anchored-query throughput on REF-PHONE-B against a store of ≥ 1 M samples. Cheap (2–3 days), and it de-risks the largest unvalidated assumption in this document |
| The 150-metric taxonomy consumes the schedule | **High** | High | AR-24: 40 curated families plus marked passthrough. Reuse HealthKitOnFHIR's mappings [20]. Make the remainder a community backlog with a strict review checklist |
| App Review rejects or challenges a destination under 5.1.3 (health data to third parties / iCloud) [23] | Medium | High — a blocked release | Ship no bespoke iCloud destination (AR-29); no third-party cloud destinations in v1; local-file destination routes entirely through the system document picker so the storage choice is the user's |
| Users report "export stopped working" that is actually the locked-device and opportunistic-scheduling reality [2][6] | **High** | Medium — reputational, and unfixable by us | AR-16: state the constraint in the PRD, the App Store description and the in-app UI. Show a visible "last successful export" with the reason for any gap. Do not let the first explanation be a support thread |
| `mqtt-nio` 3.0 API break, or the project's single maintainer stepping away [11] | Medium | Medium | Isolate behind our own sink contract (AR-02); pin exactly; be prepared to vendor. Alternatively defer MQTT to v1.1 |
| The observability differentiator is undeliverable as stated: opentelemetry-swift logs are beta and metrics are on an outdated spec [48] | Medium | Medium — a lost differentiator | Reframe now: `swift-log` plus a local export journal in v1; OTLP as an opt-in destination to the user's own collector (AR-20) |
| Silent data loss from an anchor/enqueue ordering bug | Low (if AR-03 holds) | **Severe** — it is health data and it is unrecoverable | AR-03 write-ahead invariant plus fault injection at every pipeline step; AR-04 reconciliation as a safety net; NFR-18 as the release gate |
| Users' aggregate totals disagree with the Health app, reported as a data bug | **High** | Medium — high support cost | AR-30 (declared semantics), AR-09 (explicit bucketing zone), and documentation that shows the arithmetic rather than asserting correctness |
| Two-device duplicate/flapping aggregates | Medium | Medium | AR-05 upsert, AR-15 designated exporter |
| Template-based HTTP destination becomes a credential-exfiltration vector | Low–Medium | High | AR-18 (Keychain by handle, redacted config export); closed grammar per AR-21; a security review of the config path is a release gate |
| Scope creep back toward reference-product parity during Stage 2/3 | **High** | High | AR-29 records the Won'ts *with reasons*, so re-litigating requires new evidence rather than new enthusiasm |
| Maintainer burnout as destination count grows post-v1 | Medium–High | High | Publish the maintenance-capacity number (3 per maintainer) in CONTRIBUTING; require every new destination PR to come with a named maintainer who commits to it |
| iOS 27 ships during our development window, changing the minimum-OS calculus and possibly offering `LongRunningIntent` for background exports [53] | Medium | Low–Medium | Treat minimum OS as a PM decision (open question below); design AR-17 so a `LongRunningIntent` path can be added without reworking the engine |

---

## Hard constraints that limit the product

These are platform facts. They are not negotiable by any amount of engineering effort, and
each one forecloses something a reasonable person would otherwise put in the PRD.

1. **HealthKit is not readable on macOS.** `isHealthDataAvailable()` returns `false` on macOS
   13 and later [1]. No Mac-side export, no Mac-side scheduling, no Mac-only product.
2. **HealthKit is not readable while the device is locked** — `errorDatabaseInaccessible`
   [2][3]. Writes are journalled and merged on unlock; reads simply fail. No overnight
   unattended export from a locked phone.
3. **No guaranteed background cadence.** `BGAppRefreshTask` is roughly 30 seconds when the
   system chooses; `BGProcessingTask` gets minutes but only while the device is idle and is
   killed the instant the user picks the device up [6][7]. There is no timer API.
4. **No background listening socket.** Per Apple, a background TCP server is "fundamentally
   incompatible with iOS's background execution model" and Network framework has the same
   constraint as BSD sockets [8]. No always-on server, ever.
5. **No dynamic code loading.** Guideline 2.5.2 plus DPLA §3.3.2; rejection letters name
   `dlopen`/`dlsym` symbols found in the binary [34][35][36]. No plugin architecture.
6. **PHI may not be stored in iCloud by the app** — Guideline 5.1.3(ii) [23]. This
   forecloses a bespoke iCloud Drive destination and CloudKit sync of anything health-derived,
   including export logs that contain sample values.
7. **HealthKit-derived data may not be disclosed to third parties** except to benefit the
   user directly, and only with permission — Guideline 5.1.3(i) [23]. Any telemetry that
   reaches us is a compliance question, not just a privacy preference.
8. **Sample time zones are mostly unknowable.** No time zone field exists on `HKSample`; the
   optional metadata key is absent for essentially all non-sleep records [31][32][33]. Perfect
   local-time reconstruction of historical data is impossible, not merely hard.
9. **A user force-quit cancels background transfers and prevents automatic relaunch** [30].
   Queue state must be entirely ours.
10. **watchOS background budget is about four wakes per hour, shared with complication
    refresh, with most types capped at hourly frequency** [4]. A watch-based exporter is not
    viable.
11. **App Store distribution is incompatible with GPL** [42][43][44]. The project's own
    licence is constrained by the decision to ship on the App Store.
12. **Any OAuth cloud destination requires the project to own and perpetually maintain a
    registered third-party application**, with its client identifier embedded in a public
    repository, and (for Google) ongoing verification obligations [13][14][15].

---

## Open questions for the PM

1. **Is macOS in scope at all for v1, and in what role?** Constraint 1 means it is a viewer
   or a receiving destination, never an exporter. My recommendation is to defer macOS
   entirely to v1.1 and reword the differentiator now — but this touches the product's
   headline claim and is your call, not mine.

2. **MQTT in v1: yes, at the cost of our first non-Apple runtime dependency and a known
   upcoming API break?** Or defer to v1.1 and tell MQTT users to bridge via Home Assistant
   in the meantime? This is the only destination decision I am genuinely torn on.

3. **Minimum supported OS.** iOS 26 is the verified toolchain, and `BGContinuedProcessingTask`
   (which AR-17 depends on) is iOS 26+. Supporting iOS 18 as well would cost us a second,
   worse full-history export path. If iOS 27 has shipped by our release date the calculus
   shifts again. My recommendation: iOS 26.0 minimum, single path.

4. **The observability differentiator: do we accept the reframing in AR-19/AR-20?** Local
   journal plus `swift-log` in v1, with OTLP as an opt-in destination to the user's own
   collector. This keeps the claim honest given opentelemetry-swift's current maturity, and
   it saves roughly 4 EW — but it is a softer story than "OpenTelemetry tracing by design"
   and you may prefer to fight for the stronger version.

5. **Project licence: Apache-2.0 or MIT?** Needs deciding now, because it is an ADR that
   constrains every dependency choice from Stage 2 onward. Apache-2.0 is my recommendation.

6. **The drop policy in AR-12 is a product decision I should not make alone.** When a
   destination has been unreachable long enough to fill a 256 MB queue, do we evict the
   oldest data, stop exporting new data, or prompt the user? I have proposed
   oldest-first-with-a-visible-gap-record, but this is the one place where the product
   deliberately loses health data and it deserves an explicit owner.

7. **Does the PRD accept a 40-metric v1 (AR-24)?** "150+ metrics" is a marketing number the
   reference product owns. Matching it costs 9–18 EW of unglamorous taxonomy work. The
   passthrough mechanism lets us claim broad coverage honestly while curating incrementally,
   but it means some metrics ship with raw identifiers and no semantic guarantee, and
   somebody will notice.

8. **Do we commit to the HAE compatibility profile (AR-25)?** ~1.5 EW for day-one access to
   an existing ecosystem of sinks and dashboards. Cheapest adoption lever available. The
   counter-argument is strategic: it anchors us to a competitor's schema and might read as
   derivative rather than alternative.

9. **May I run the throughput spike now?** It is 2–3 engineer-days and it is the difference
   between NFR-03/04/07/11 being requirements and being guesses. If the PRD ships with those
   numbers unvalidated, the first thing Stage 2 will do is discover they are wrong.

---

## Sources

1. `isHealthDataAvailable()` — Apple Developer Documentation. HealthKit framework is present on macOS 13+ but reads/writes are unavailable; the call returns `false`. https://developer.apple.com/documentation/healthkit/hkhealthstore/ishealthdataavailable()
2. `HKError.Code.errorDatabaseInaccessible` — Apple Developer Documentation. "The HealthKit data is unavailable because it's protected and the device is locked." https://developer.apple.com/documentation/healthkit/hkerror/code/errordatabaseinaccessible
3. "HealthKit data inaccessible in background" — Stack Overflow, quoting Apple: "Because the HealthKit store is encrypted, your app cannot read data from the store when the phone is locked." https://stackoverflow.com/questions/30361033/healthkit-data-inaccessible-in-background
4. `enableBackgroundDelivery(for:frequency:withCompletion:)` — Apple Developer Documentation. Entitlement requirement; hourly frequency caps; watchOS four-updates-per-hour shared budget; observer-query backoff after three unresponsive failures. https://developer.apple.com/documentation/healthkit/hkhealthstore/enablebackgrounddelivery(for:frequency:withcompletion:)
5. "HealthKit HKObserverQuery Updates with ONLY HKDeletedObject" — Stack Overflow. Delete-only changes do not reliably produce a callback until the next insert; `HKDeletedObject` retention is time-limited. https://stackoverflow.com/questions/33002565/healthkit-hkobserverquery-updates-with-only-hkdeletedobject
6. "Finish tasks in the background" — WWDC25 session 227, Apple. `BGProcessingTask` characteristics; `BGContinuedProcessingTask` introduction in iOS/iPadOS 26. https://developer.apple.com/videos/play/wwdc2025/227/
7. iOS BGTask limits reference. `BGAppRefreshTask` ~30 s hard ceiling; `BGProcessingTask` typically 1–10 min; `dasd` opportunistic scheduling; headless cold-start eats the budget. https://raw.githubusercontent.com/brewkits/kmpworkmanager/master/docs/IOS_BGTASK_LIMITS.md
8. "BSD Socket TCP Server in background" — Apple Developer Forums (Apple DTS response). "iOS suspends apps shortly after you move them to the background, and at that point all networking stops"; "Network framework won't let you achieve the specific goal… exactly the same constraints as BSD Sockets." https://developer.apple.com/forums/thread/687672
9. `HealthyApps/health-auto-export-server` — the reference product's own open-source Grafana companion. Documents the recommended automation config: REST API destination, JSON, aggregate enabled, daily interval, batched requests. https://github.com/HealthyApps/health-auto-export-server
10. `Dzarlax-AI/health_dashboard` — third-party sink documenting real-world Health Auto Export automation settings (Export Version v2, Summarize Data ON, Time Grouping hourly/default). https://github.com/Dzarlax-AI/health_dashboard
11. `mqtt-nio` — Swift Package Index. Apache-2.0; 2.13.0 (Feb 2026); 3.0.0-alpha.1 (Jun 2026); NIOTransportServices required on iOS. https://swiftpackageindex.com/swift-server-community/mqtt-nio
12. `dropbox/SwiftyDropbox` — MIT; SPM-distributed; requires an app key and a `db-<APP_KEY>` URL scheme registered by the app. https://github.com/dropbox/SwiftyDropbox
13. "Choose Google Drive API scopes" — Google for Developers. `drive.file` is non-sensitive; broader Drive scopes are Restricted and require restricted-scope OAuth verification. https://developers.google.com/workspace/drive/api/guides/api-specific-auth
14. "Requesting Minimum Scopes" — Google Cloud Console Help. `drive.file` avoids an additional security assessment. https://support.google.com/cloud/answer/13807380
15. "Restricted scope verification" — Google for Developers. Annual third-party security assessment required for apps accessing restricted data from or through a server. https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification
16. "Apple Health export.xml to JSON: stop using DOM parsers" — DEV Community. A long-term Apple Watch user's `export.xml` is 1.8 GB / ~4.26 M records; DOM parsers die; streaming tools hold ~10 MB heap. https://dev.to/philipad/apple-health-exportxml-to-json-stop-using-dom-parsers-il3
17. "Converting 10 Years of Apple Health Data (1.8GB) to SQLite" — Zenn. Measured: 4.26 M records, 1.8 GB XML, 71 MB gzipped (~25:1). https://zenn.dev/hideakitamai/articles/8ab4733e65e0dc?locale=en
18. `Lybron/health-auto-export` — the reference product's public documentation repository, including the API Export JSON format wiki. https://github.com/Lybron/health-auto-export
19. "Reading route data" — Apple Developer Documentation. `HKWorkoutRouteQuery` returns locations in batches; route points are accurate to within 50 m and may need smoothing. https://developer.apple.com/documentation/healthkit/reading-route-data
20. `StanfordBDHG/HealthKitOnFHIR` — MIT. HealthKit → FHIR R4 with customisable HealthKit-type-to-standardised-code (LOINC) mappings. https://github.com/StanfordBDHG/HealthKitOnFHIR
21. "REST API" — Home Assistant Developer Docs. `Authorization: Bearer TOKEN`; `POST /api/states/<entity_id>`; `POST /api/services/mqtt/publish`. https://developers.home-assistant.io/docs/api/rest/
22. "Sending data home" — Home Assistant Developer Docs. Webhook endpoints require no authentication; `<instance_url>/api/webhook/<webhook_id>`. https://developers.home-assistant.io/docs/api/native-app-integration/sending-data/
23. App Store Review Guidelines §5.1.3 — Apple. (i) no disclosure of health data to third parties for advertising/marketing/data-mining; (ii) "may not store personal health information in iCloud." https://developer.apple.com/app-store/review/guidelines/
24. SSWG-0018 proposal: MQTTNIO — Apache-2.0; dependencies swift-nio, swift-nio-ssl, swift-nio-transport-services, swift-log. https://github.com/swift-server/sswg/blob/main/proposals/0018-mqtt-nio.md
25. `emqx/CocoaMQTT` — GitHub. README states MIT; GitHub reports licence "Other"; 1,749★, 126 open issues. https://github.com/emqx/CocoaMQTT/
26. CocoaMQTT on CocoaPods.org — reports `License: NOASSERTION` and `Supports SPM: ✗`. https://cocoapods.org/pods/CocoaMQTT
27. `HKAnchoredObjectQuery` — Apple Developer Documentation. Anchor corresponds to the last sample or deleted object received; subsequent queries restrict results to newer objects. https://developer.apple.com/documentation/healthkit/hkanchoredobjectquery
28. "Build robust and resumable file transfers" — WWDC23 session 10006, Apple. Background sessions run outside the app process and continue when the app is suspended or terminated; `isDiscretionary`; `countOfBytesClientExpectsToSend`. https://developer.apple.com/videos/play/wwdc2023/10006/
29. "Keep Downloading with a Background Session" — William Boles. Background session semantics; `sessionSendsLaunchEvents`; upload and download tasks survive suspension and termination. https://williamboles.com/keep-downloading-with-a-background-session/
30. `URLSessionConfiguration.background(withIdentifier:)` behaviour on force-quit, quoting Apple docs: "If the user terminates the app from the multitasking screen, the system cancels all of the session's background transfers… the system does not automatically relaunch apps that were force quit." https://stackoverflow.com/questions/77477827/how-to-resume-urlsessiondownloadtask-after-app-termination
31. "HKMetadataKeyTimeZone is always nil for health data created by Apple's Health App" — Stack Overflow. Time zone metadata is present only if the writing app sets it; Apple's own Health app frequently does not. https://stackoverflow.com/questions/49250964/hkmetadatakeytimezone-is-always-nil-for-health-data-which-is-created-by-apples
32. "Storing the Time Zone With a Date" — Michael Tsai. HealthKit requires start/end dates but time zone is optional and buried in an omittable metadata dictionary. https://mjtsai.com/blog/2021/01/18/storing-the-time-zone-with-a-date/
33. "Apple Health & timezones: what we know and current limitations" — open-wearables discussion #606 (Mar 2026). Measured full-sync audit: regular records never carry a time zone; 2,024 of 2,026 sleep records do; 5 of 19 workouts do (all Apple Watch). Current device zone rejected as a fallback because it falsifies history. https://github.com/the-momentum/open-wearables/discussions/606
34. App Store Review Guidelines §2.5.2 — Apple. Apps "may not download, install, or execute code which introduces or changes features or functionality of the app." https://developer.apple.com/app-store/review/guidelines/
35. "Why did Apple reject my app for Guideline 2.5.2?" — analysis of the data/logic boundary; remote configuration driving data is acceptable, runtime expression evaluation is not. https://ptkd.com/journal/guideline-2-5-2-downloading-scripts-without-review
36. Realm-JS issue #1967 — a verbatim Apple rejection letter naming `dlopen()`, `dlsym()`, `respondsToSelector:`, `performSelector:` and `method_exchangeImplementations()` as 2.5.2 / DPLA §3.3.2 triggers. https://github.com/realm/realm-js/issues/1967
37. `AppIntent.supportedModes` — Apple Developer Documentation. `.background` runs the action entirely in the background (iOS 26+). https://developer.apple.com/documentation/appintents/appintent/supportedmodes
38. "Implementing App Intents and Shortcuts" — Emrld Labs (2026). Background intents get roughly 30 seconds; locked-device behaviour must be tested on real hardware. https://emrldlabs.com/blog/implementing-app-intents-shortcuts-siri-ready-2026/
39. "Does My iPhone Support iOS 26?" — MacRumors. iOS 26 supports iPhone 11 and later (A13 Bionic minimum); iPhone XR/XS/XS Max are not supported. https://www.macrumors.com/2025/09/12/will-my-iphone-support-ios-26/
40. `BGContinuedProcessingTaskRequest` — Apple Developer Documentation. iOS 26.0+; submitted from the foreground as the result of a person's action; continues running after backgrounding. https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtaskrequest
41. "SwiftUI Background Tasks iOS 26" — comparison of `BGAppRefreshTask` (~30 s), `BGProcessingTask` (minutes, idle-gated, expires when the user returns) and `BGContinuedProcessingTask` (user-initiated, runs to completion). https://swiftcrafted.dev/article/swiftui-background-tasks-ios-26-bgapprefreshtask-bgprocessingtask-bgcontinuedprocessingtask
42. "GPL Enforcement in Apple's App Store" — Free Software Foundation. App Store ToS restrictions are "forbidden by section 6 of GPLv2"; Apple removed GNU Go rather than amend its terms. https://www.fsf.org/news/2010-05-app-store-compliance
43. "More about the App Store GPL Enforcement" — FSF. Detail on the §9(b) Usage Rules as prohibited "further restrictions". https://www.fsf.org/blogs/licensing/more-about-the-app-store-gpl-enforcement
44. "No GPL Apps for Apple's App Store" — ZDNET. VLC removed from the App Store on GPLv2 grounds. https://www.zdnet.com/article/no-gpl-apps-for-apples-app-store/
45. "Open Source Licenses in Your App Can Create Legal Risk" — AppCompliance. Static linking is the norm on iOS and Apple does not permit dynamically loaded code (guideline 2.5.2), creating unresolved tension with LGPL's relinking expectation. https://appcompliance.io/blog/open-source-license-compliance-mobile-binaries/
46. `StanfordSpezi/SpeziHealthKit` — MIT. Long-lived background collection; `HealthKitConstraint` with `handleNewSamples(_:ofType:)` and `handleDeletedObjects(_:ofType:)`. https://github.com/StanfordSpezi/SpeziHealthKit
47. `kvs-coder/HealthKitReporter` — MIT. Codable wrappers over HealthKit types; 90★, 9 open issues. https://github.com/kvs-coder/HealthKitReporter
48. `open-telemetry/opentelemetry-swift` — Apache-2.0; 359★, 123 open issues. Project's own status statement: tracing and baggage stable, logs beta, metrics "implemented using an outdated spec". https://github.com/open-telemetry/opentelemetry-swift
49. "CocoaPods Deprecation Notice for OpenTelemetry Swift" — OpenTelemetry blog (Jul 2026). Final CocoaPods release by 30 Sep 2026; support ends 2 Dec 2026; SPM is the only forward distribution mechanism. https://opentelemetry.io/blog/2026/otel-swift-cocoapods-deprecation/
50. "Swift 6 Migration error in Sample" — Apple Developer Forums. `HKSample` is not `Sendable`; "Sending 's' risks causing data races" when resuming a continuation from an anchored-query callback. https://developer.apple.com/forums/thread/763998
51. "Concurrency issues with HKLiveWorkoutBuilder managed by @Observable class" — Stack Overflow. "Adding `@preconcurrency` in front of `import HealthKit` will save you from headaches, as many of HK's moving parts are not `@Sendable`." https://stackoverflow.com/questions/79011751/concurrency-issues-with-hkliveworkoutbuilder-managed-by-observable-class
52. "Updating an App to Use Swift Concurrency" — Apple sample code. Canonical continuation pattern for `HKAnchoredObjectQuery`. https://github.com/cntrump/UpdatingAnAppToUseSwiftConcurrency
53. `LongRunningIntent` — Apple Developer Documentation. Extends an app intent's background execution beyond the standard 30 s for file operations, data synchronisation and large-dataset processing; requires regular progress reporting. https://developer.apple.com/documentation/appintents/longrunningintent
