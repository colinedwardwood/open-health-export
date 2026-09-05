# UI/UX Designer — Stage 1 Contribution

> Stage 1 artifact. Requirements, flows, states and acceptance criteria only. No visual design,
> no SwiftUI. ASCII wireframes are used only where they disambiguate information architecture.
> Requirement IDs use the prefix `UX-`. Priorities are MoSCoW.

---

## Executive summary

The premise describes a data pipeline configured on a phone. That framing is the problem. If we
build "a configuration app for a pipeline", we will build the incumbent: a wall of toggles that
works on the day you set it up and then quietly stops. The most-cited complaint about this
category is not that configuration is hard — it is that **exports stop and nobody notices for
weeks** [28][29][30]. That is a design failure, not an engineering one, and it is the failure we
should organise the entire product around.

So the design position I am taking is: **this is a monitoring app that happens to be
configurable.** The default screen answers one question — *is my health data actually arriving
where I sent it?* — and every other surface is subordinate to that. Configuration is a thing you
do a few times. Trusting the thing is something you do every day, passively, by not having to
think about it.

Four findings from research materially change what Stage 1 can promise:

1. **HealthKit read permission is invisible to us.** Apple states plainly that an app "cannot
   determine whether or not a user has granted permission to read data" and that a denial "simply
   appears as if there is no data of the requested type" [1][2][3]. The only permission state we
   can positively identify is *limited historical window*, via
   `getEarliestAuthorizedSampleDate(for:)` [1]. We therefore cannot build a permission manager, we
   cannot show "3 of 40 types denied", and every empty result is genuinely ambiguous. Designing as
   though we know is the single biggest trap in this product.
2. **The HealthKit store is unreadable while the device is locked.** It is in the Data Protection
   class *Protected Unless Open*; access is relinquished 10 minutes after lock and returns only on
   passcode/Face ID unlock [7]. Reads in that window fail with `errorDatabaseInaccessible` [8].
   Combined with `BGTaskScheduler`'s `earliestBeginDate` being a lower bound the system may ignore
   entirely [33], **a time-of-day schedule cannot be honoured.** "Export daily at 03:00" is a
   promise the platform will not keep. We must not offer that control. I propose freshness targets
   instead of cron (see [Flow 4](#flow-4--scheduling) and [C2](#hard-constraints-that-limit-the-product)).
3. **macOS cannot read HealthKit.** `isHealthDataAvailable()` returns `false` on Mac, confirmed by
   Apple DTS in September 2025 [4][5]. The premise's "first-class support across
   iOS / iPadOS / macOS / watchOS" is not achievable for the core function. The Mac app cannot be
   an exporter. It can be a config author, a diagnostics viewer and a local receiver — and that is
   a genuinely useful role, but it is a different product from what the brief implies.
4. **App Store guideline 5.1.3(ii) forbids storing personal health information in iCloud** [19].
   That removes the incumbent's mechanism for getting data onto a Mac [28] and constrains any
   "sync config and data via iCloud" design. Config sync is fine; health data sync is not.

Given (1)–(3), reliability is not something we can promise. **Legibility is.** The product's
central commitment should be: *if it stops working, you will know within one cadence period, you
will know why in words you can act on, and you will know what to change.* Everything in this
document serves that sentence.

The two highest-leverage requirements in the whole contribution are small and cheap:

- **A local-notification watchdog** ([UX-22](#requirements-i-own)). Local notifications fire at
  their scheduled time whether or not our app ever gets background execution [33]. Every
  successful export reschedules a pending "you haven't exported since X" notification. Silence
  becomes an *event* rather than an absence. This single mechanism makes the category's defining
  failure mode structurally impossible to miss.
- **"Only types that actually have data on this device"** ([UX-13](#requirements-i-own)). Probing
  each type with a one-sample query collapses the 150-metric problem from ~150 rows to the 30–60
  the person actually owns. It is the largest usability win available and it costs one query per
  type.

---

## Personas and jobs to be done

Four personas, drawn from the plausible audience. I have deliberately **excluded the
researcher/clinician-adjacent user** as a target — see [Anti-personas](#anti-personas-explicit-non-targets)
for the argument, which is a scope decision the PM should ratify or overturn.

### P1 — Priya, the home-automation self-hoster

*38, infrastructure engineer by day, runs Home Assistant on a Proxmox box in a cupboard. Ten years
of Apple Watch data. Wants her house to know she slept badly.*

| Dimension | Detail |
|---|---|
| **Job to be done** | "Get today's steps, sleep, resting heart rate and weight into Home Assistant as sensor entities, forever, without thinking about it, so my dashboards and automations can use them." |
| **Technical ceiling** | High on infrastructure, low patience for GUIs. Comfortable with YAML, MQTT topics, reverse proxies, long-lived access tokens, self-signed certificates. Will read our docs. Will not read our marketing. |
| **Volume of metrics wanted** | Small — 15–30 types. She wants *the ones HA can render*, not everything. |
| **Abandonment moment** | She discovers her HA energy-and-health dashboard has been flat since a phone update three weeks ago. She will not give us a second chance, because the whole point was not having to check. Secondary abandonment: typing a 180-character long-lived access token on a touch keyboard and having it silently fail with "Error -1202". |
| **Success looks like** | An HA dashboard that has not gone flat in six months, and a phone app she has opened twice since setup — both times deliberately, neither time in a panic. |
| **What she needs from the UI** | Status first. Honest delivery confirmation. Error text that names the fix. Paste and QR affordances. A preset that maps to HA's data model. |

### P2 — Marcus, the quantified-self archivist

*45, data analyst, runs Postgres + Grafana on a NAS. Has a spreadsheet going back to 2011. Believes
strongly that his data should outlive any vendor.*

| Dimension | Detail |
|---|---|
| **Job to be done** | "Continuously land every health sample I generate into my own time-series store in a stable, documented format, and back-fill the entire history I already have." |
| **Technical ceiling** | High. Will inspect our JSON. Will complain, correctly, if a unit changes between releases. Cares about schema stability more than features. |
| **Volume of metrics wanted** | Maximal — everything with data. This is the persona who genuinely wants the "everything" preset. |
| **Abandonment moment** | A silent unit change (kg → lb because he toggled something in Health) that corrupts three months of Grafana panels. Or a historical back-fill that takes four days of opportunistic background runs with no progress indication and no way to force it. |
| **Success looks like** | A one-time full archive that completes in a bounded, visible session; then a delta pipeline that never surprises him. A payload he can point at and say "that is what was sent". |
| **What he needs from the UI** | Export units decoupled from display units. A visible, forceable, resumable historical back-fill with progress. Byte-accurate payload preview per run. Schema version stamped in the payload. |

### P3 — Dana, the developer building on their own data

*29, iOS-adjacent web developer. Building a personal side project — a training-load model, a sleep
correlation notebook. Treats the exporter as an API, not an app.*

| Dimension | Detail |
|---|---|
| **Job to be done** | "Give me a documented, addressable feed of my own health data so I can build something on top of it, and let me trigger it from Shortcuts / a script when I'm iterating." |
| **Technical ceiling** | Highest. Reads HealthKit identifier strings natively. Will search for `HKQuantityTypeIdentifierStepCount`, not "Steps". |
| **Volume of metrics wanted** | Narrow but precise — 5–10 types, exact ones, exact units, exact time windows. |
| **Abandonment moment** | A Shortcuts action that fails with "Something went wrong. Please try again." — the incumbent's live bug [32]. Or discovering the export silently truncated a window and there is no way to tell a truncated run from a complete one. |
| **Success looks like** | An App Intent that works headlessly, returns a result they can branch on, and reports a distinguishable failure. Config expressible as a file they can commit. |
| **What they need from the UI** | Identifier-level search. Config import/export as a plain file. App Intents with typed errors. Per-run record counts and window bounds. |

### P4 — Sam, leaving iOS

*33, has bought an Android phone, has eight years of Apple Health data and forty-eight hours to get
it out. Will use this app exactly once.*

| Dimension | Detail |
|---|---|
| **Job to be done** | "Get all of it, once, into files I can keep, and then never open this app again." |
| **Technical ceiling** | Moderate. Can operate Files and AirDrop. Will not stand up an MQTT broker. Does not have a server. |
| **Volume of metrics wanted** | Everything, indiscriminately. |
| **Abandonment moment** | Being asked for an endpoint URL before being allowed to do anything. Sam has no endpoint. If "add a destination" is a mandatory gate, we lose this persona at screen two. |
| **Success looks like** | A single folder of files on their Mac or in Files, complete, with a manifest saying what is in it, produced in one sitting without an internet destination. |
| **What they need from the UI** | A first-class **local file / Files.app destination** that requires no network configuration, and a one-shot "archive everything" mode with visible progress and a completion manifest. |

**Design consequence of P4:** the destination model must include a zero-configuration local
destination, and the first-run flow must not require a network destination. This is not a
nice-to-have; without it a whole persona bounces off the second screen. It is also the safest way
for *any* persona to see proof-of-life before they trust us with a credential.

### Anti-personas (explicit non-targets)

| Non-target | Why not, and what we say instead |
|---|---|
| **Researcher / clinician-adjacent user** | Research use implies claims we cannot support in v1: completeness guarantees, audit trails, subject consent flows, ethics-review posture, and possible medical-device classification. 5.1.3 requires informed consent and ethics-board approval for human-subject research apps [19]. The honest position: the app is fit for **one person exporting their own data**, and we should say so in plain words rather than court a use case we would fail. *Recommendation to PM: state a non-goal explicitly.* |
| **Non-technical consumer wanting pretty charts** | Apple Health already does this, better, for free. Charts are the incumbent's differentiator, not ours. Every hour spent on charts is an hour not spent on making failure legible. *Recommend "Won't" for v1 — see [Platform split](#platform-split).* |
| **Someone exporting *someone else's* data** | Out of scope entirely, and a safeguarding concern. No multi-profile support. Say so. |

---

## Information architecture

### The central IA decision

The incumbent's home screen is a list of automations — i.e. configuration. Ours must be **status**.
If the first thing the app shows is what you can change, it teaches you that the app is a thing you
configure. If the first thing it shows is whether it is working, it teaches you that the app is a
thing you can trust, and gives you somewhere to look when you doubt it.

### The second central IA decision: metric selection belongs to a reusable Metric Set, not to a destination

Attaching 150 toggles to each destination means a person with three destinations configures the
selection three times and reconciles it forever. Instead:

- **Metric Sets** are named, reusable, first-class objects living in their own tab ("Data").
- A **destination references** one Metric Set (and may add per-destination overrides).
- Shipped Metric Sets are **versioned templates** the person can adopt or fork.

This turns "the 150-toggle problem" into "pick a set, maybe fork it" — a one-decision task instead
of a 150-decision task — and it makes the presets in
[Solving metric selection at scale](#solving-metric-selection-at-scale) load-bearing rather than
decorative.

### Top level

Four tabs plus Settings. Search is **scoped, not global** — a global search tab would be a
`Tab(role: .search)` [26] that mostly returns metric names, which is a poor use of one of five
top-level slots. Search lives inside Data and inside History.

| Tab | Answers | Contains |
|---|---|---|
| **Status** (default) | "Is it working?" | Attention summary; per-destination state cards; Health-access coverage summary; primary `Export now` action |
| **Destinations** | "Where does my data go?" | Destination list with state; add/edit/test; per-destination schedule; network-activity ledger |
| **Data** | "What gets sent?" | Metric Set library; metric picker with search/presets/bulk actions; export format and units; payload preview |
| **History** | "What happened?" | Run log, filterable by outcome; run detail with record counts, window bounds, redacted payload, error detail, diagnostics export |
| Settings (toolbar, not a tab) | "How does this behave?" | Notifications; units for display vs export; diagnostics/OpenTelemetry opt-in; data-flow explainer; build provenance; **Delete everything** |

Rationale for Settings-in-toolbar rather than a fifth tab: on iOS 26 the tab bar minimises on
scroll and is a Liquid Glass navigation surface [20][21]; four items keeps labels legible at
accessibility text sizes, where five begins to truncate. Settings is a low-frequency destination
and does not deserve permanent screen residency.

### Status screen (annotated wireframe)

```
┌──────────────────────────────────────────────┐
│  Health Exporter                        ⚙︎   │  toolbar (glass layer only)
├──────────────────────────────────────────────┤
│  ⚠  1 destination needs your attention       │  attention row: present only
│                                              │  when ≠ all-healthy
├──────────────────────────────────────────────┤
│  DESTINATIONS                                │
│ ┌──────────────────────────────────────────┐ │
│ │ ✕  Home Assistant                        │ │  state glyph = shape, not colour
│ │    Failing · 3 attempts since 2 Sep      │ │
│ │    Last success 31 Aug, 07:12 (2 d ago)  │ │  relative AND absolute
│ │    "homeassistant.local rejected the     │ │  the error, inline, in words
│ │     token"                            ›  │ │
│ └──────────────────────────────────────────┘ │
│ ┌──────────────────────────────────────────┐ │
│ │ ✓  NAS archive (files)                   │ │
│ │    Healthy · 42 min ago                  │ │
│ │    Next attempt within 6 h            ›  │ │  window, never a clock time
│ └──────────────────────────────────────────┘ │
│ ┌──────────────────────────────────────────┐ │
│ │ ◷  Grafana (OTLP)                        │ │
│ │    Stale · no success for 3 d            │ │  ← the silent-failure state,
│ │    No error was recorded              ›  │ │    named and surfaced
│ └──────────────────────────────────────────┘ │
├──────────────────────────────────────────────┤
│  HEALTH ACCESS                               │
│  38 of 41 selected types returned data       │  never "denied" — we can't know
│  3 returned nothing               Review ›   │
├──────────────────────────────────────────────┤
│              [  Export now  ]                │
└──────────────────────────────────────────────┘
   Status    Destinations    Data    History
```

Three things about this layout are requirements, not taste:

1. **"No error was recorded" is displayed.** A destination that has never failed but has not
   succeeded is the exact case the incumbent hides. Naming the absence is the whole point.
2. **"Next attempt within 6 h"**, never "Next: 03:00". We cannot honour clock times
   ([C2](#hard-constraints-that-limit-the-product)). Displaying one is a lie with a timestamp on it.
3. **"38 of 41 returned data"**, never "3 denied". We cannot distinguish denial from absence
   [1][2][3].

---

## Critical flows

Each flow is specified as entry conditions, states, transitions and failure paths. Acceptance
criteria are stated per flow and consolidated in
[Requirements I own](#requirements-i-own).

### Flow 1 — First run and HealthKit permission priming

This is the highest-risk flow in the product, for a reason that is worth stating in full.

**The design trap.** HealthKit's authorisation sheet is per-type, all-in-one-sheet, and its outcome
is invisible to us. Apple: *"your app cannot determine whether or not a user has granted permission
to read data. If you are not given permission, it simply appears as if there is no data of the
requested type"* [2]. There is no callback when permission is revoked later [1]. The only state we
can positively detect is a **limited historical window**, via
`getEarliestAuthorizedSampleDate(for:)`; full access and denial are indistinguishable [1]. So:

- A person can deny 40 of 41 types and our app will look, to itself, exactly like a person who has
  no data. If we then report "Export succeeded: 0 records", we have built the incumbent.
- If we say "permission denied" we may be lying. If we say "no data" we may be lying. **We must say
  both, always, in that order of likelihood, and give one action that resolves the ambiguity: the
  person looking in Health.**

**A second constraint bites here.** HIG rules for pre-permission screens are strict: a custom
screen shown immediately before a system permission alert *"[must] include only one button"*,
titled *"Continue"* or *"Next"*, and *"don't provide a way for people to leave the screen or window
without viewing the system alert — like offering an option to close or cancel"* [14]. So the
familiar "Enable Health Access / Not Now" priming pair is **not permitted**. The mitigation: make
priming a screen the person *navigated to deliberately* within an onboarding stack, whose only
in-content control is `Continue`, with escape available through the standard navigation bar rather
than a competing in-content button. *Assumption, flagged: that a standard nav-bar back button is
not "an additional action in your custom screen". This needs App Review confirmation before we
commit — see [Open questions](#open-questions-for-the-pm) Q3.*

**Flow states**

| State | What the person sees | Transitions out |
|---|---|---|
| `S1 Welcome` | One screen: what this app does in two sentences, and the data-flow diagram (see [Designing for trust](#designing-for-trust)). No account, no sign-in, no upsell. | → `S2` |
| `S2 Choose a first destination` | Two options only: **"Save to files on this device"** (zero config, recommended, satisfies P4 and gives everyone proof-of-life) and **"Send to a server"**. Skippable. | → `S3` |
| `S3 Choose what to export` | Pre-selected: the **Core Daily** Metric Set (~24 types, see [Solving metric selection at scale](#solving-metric-selection-at-scale)). One tap to accept, one tap to open the picker. | → `S4` |
| `S4 Priming` | Plain language: exactly which types we are about to ask for, grouped; that Apple's sheet is next; that **we will never be able to see what they turned off**, so if data is missing later they should check Health → Sharing. Single button: `Continue`. | → `S5` |
| `S5 System sheet` | Apple's HealthKit sheet. Not ours. Our purpose strings (`NSHealthShareUsageDescription`) must be a single active sentence naming the destination category [11][14]. | → `S6` |
| `S6 Coverage check` | We run a one-sample probe per selected type and report a **three-state coverage table**. Determinate progress; typically < 3 s. | → `S7` / `S7-partial` / `S7-empty` |
| `S7 First export` | "Run your first export now?" Primary action runs it in the foreground with visible progress (Flow 5). | → Status tab |
| `S7-empty` | **Every type returned nothing.** Highest-signal recoverable state. Copy names both causes and gives the exact path in Health. | → remediation, then re-probe |

**Coverage check states (the core artefact of this flow)**

| Coverage state | How we know | Copy |
|---|---|---|
| **Data available** | One-sample query returned ≥ 1 sample | "Steps — 4,812 samples, latest today 08:41" |
| **Limited to a recent window** | `getEarliestAuthorizedSampleDate(for:)` returned a date [1] | "Heart rate — access limited to data since 1 Aug 2026. Earlier data can't be exported." |
| **Nothing returned** | Query returned zero samples, no limited-window date | "Blood glucose — nothing returned. Either Health has no blood glucose data, or access is off. Check in Health → Sharing → Apps." |

Note the third row: it is the honest state and it is deliberately not called an error. It gets a
neutral glyph (`circle.dashed`), not a warning glyph, because for most people most of these types
genuinely have no data.

**Failure paths**

| Failure | Behaviour |
|---|---|
| `isHealthDataAvailable() == false` (iPad ≤ iPadOS 16, Mac, restricted enterprise device) [4] | Do not show onboarding. Show a single terminal screen naming the platform limitation and, on Mac, offer the companion roles ([Platform split](#platform-split)). Never a spinner, never a retry loop. |
| `requestAuthorization` throws | Almost always a missing purpose string, i.e. our bug [11]. Show a build-level error with the build hash and a link to file an issue. Do not blame the person. |
| Person backs out at `S4` | Onboarding is resumable and idempotent. Status shows a single "Health access not set up yet — Set up ›" row. No nagging, no modal on next launch. |
| Person denies everything | Detected only as `S7-empty`. We must never assert denial. |
| Permission revoked months later | Undetectable directly. Surfaces as a coverage drop; the periodic coverage re-probe (**UX-06**) is the only mechanism that catches it. |

**Acceptance criteria** — see UX-01…UX-07.

### Flow 2 — Adding and testing a destination

**States:** `Draft` → `Testing` → `Test passed` / `Test failed` → `Saved & enabled` / `Saved & paused`.

**The non-negotiable rule: no destination may be saved in an enabled state without a successful
real test.** Not a reachability check — a real one. The incumbent's MQTT path reported *"Data
published to broker"* for a deliberately bogus broker address, with an empty error field [30]. A
test that can pass while delivery fails is worse than no test at all, because it converts the
person's healthy suspicion into false confidence.

| Sub-state | Detail |
|---|---|
| `Draft` | Fields render **parsed-back**: "You entered · https · homeassistant.local · port 8123 · path /api/webhook/abc123". Live parse feedback, no modal validation. Save is disabled. |
| `Testing` | Determinate stepped progress with named steps, each individually reportable: `Resolve host` → `TLS handshake` → `Authenticate` → `Send test record` → `Confirm delivery`. The step that failed is the diagnosis. |
| `Test passed` | Shows exactly what was sent and what came back: request line (redacted), response status, response body (truncated, revealable), round-trip time. Save enabled. |
| `Test failed` | Full error object per [Error content guidelines](#error-content-guidelines), with the failing step highlighted and the fix action inline. Save available **only** as `Save & pause`, with the reason stated: "We'll keep this configuration but won't schedule it until a test passes." |
| `Delivery unconfirmable` | A distinct outcome, not a pass. For MQTT QoS 0, fire-and-forget webhooks and similar: "Sent. This protocol can't confirm a subscriber received it." Recommend QoS ≥ 1 so `PUBACK` can be reported. |

**Failure paths:** all fifteen archetypes in
[Error content guidelines](#error-content-guidelines) are reachable from this flow. Two deserve
naming here because they are the self-hoster's daily reality:

- **Untrusted certificate** (private CA / self-signed): see
  [Credential entry without misery](#credential-entry-without-misery) for the three options and my
  recommendation.
- **`.local` hostname resolves at home, not on cellular.** Extremely common and extremely
  confusing. The error must name it: "`homeassistant.local` didn't resolve on your current network.
  `.local` names only work on the same network. If you're away from home, use your external address
  or connect to your VPN." Additionally the destination editor should offer an optional
  **secondary address** used when the primary fails, because the honest fix is two addresses, not
  one.

**Acceptance criteria** — UX-08…UX-12, UX-27…UX-32.

### Flow 3 — Selecting which metrics to export

Full treatment in [Solving metric selection at scale](#solving-metric-selection-at-scale).
Flow-level states:

`Set library` → `Editing a set` → `Diff review` → `Permission delta` → `Committed`.

The step that does not exist in the incumbent and must exist here is **Diff review**: committing a
change to a Metric Set shows what changed before anything happens.

```
┌────────────────────────────────────────────┐
│  Review changes to "Home Assistant Core"   │
├────────────────────────────────────────────┤
│  Adding 12 types                           │
│    Sleep analysis, Respiratory rate, …  ›  │
│  Removing 3 types                          │
│    Dietary caffeine, …                  ›  │
├────────────────────────────────────────────┤
│  ⓘ 9 of the 12 new types need new Health   │
│    permission. Apple's permission sheet    │
│    will appear next. You'll see 9 rows.    │
├────────────────────────────────────────────┤
│  ⚠ Removing types does not delete data     │
│    already sent to homeassistant.local.    │
├────────────────────────────────────────────┤
│           [ Continue ]                     │
└────────────────────────────────────────────┘
```

Two design acts here. First, **predicting the permission sheet** removes the single most
disorienting moment in HealthKit apps — the unexplained sheet with an arbitrary number of rows. We
can predict it: `getRequestStatusForAuthorization(toShare:read:)` reports whether the system would
prompt [4], and we know which types are newly added. Second, **stating that removal is not
retraction** is an honesty requirement, not a legal disclaimer — people genuinely assume
un-ticking a box recalls the data.

**Acceptance criteria** — UX-13…UX-18.

### Flow 4 — Scheduling

**This flow must be redesigned away from the premise.** Cron-style scheduling cannot work:

- HealthKit is unreadable while the device is locked; access returns only on unlock [7][8]. A 03:00
  export will find the store encrypted.
- `BGTaskScheduler.earliestBeginDate` is *"a lower bound, not a scheduled launch time"*; the system
  may never grant execution [33]. Apple's own DTS: *"there are common scenarios where it won't grant
  you any background execution time at all"* [33].
- `enableBackgroundDelivery` frequency is a maximum, not a schedule; `stepCount` is capped at hourly
  on iOS regardless of what you ask for; and if our observer completion handler fails three times
  HealthKit **stops delivering background updates entirely** [9][10].
- Background App Refresh being off, or Low Power Mode being on, stops it all [28][33].

Offering "Every day at 03:00" produces a control that looks precise and behaves randomly, which is
exactly how the incumbent generates its bug reports [29][31].

**Proposed replacement: a freshness target.** The person expresses *how out of date they are willing
to be*, and we express *what we will attempt and what we cannot promise*.

```
┌────────────────────────────────────────────┐
│  How fresh should this destination be?      │
├────────────────────────────────────────────┤
│  ○  Within about an hour                    │
│  ●  Within about 6 hours        (default)   │
│  ○  Within about a day                      │
│  ○  Only when I ask                         │
├────────────────────────────────────────────┤
│  We'll attempt an export whenever iOS lets  │
│  us run in the background, and always when  │
│  you open the app. iOS decides the timing   │
│  and can skip it — and Health data can't be │
│  read while your iPhone is locked.          │
│                                             │
│  If nothing succeeds for 12 hours we'll     │
│  notify you.                        [ⓘ Why] │
├────────────────────────────────────────────┤
│  For exact timing, trigger an export from   │
│  Shortcuts or the Control Centre button.    │
└────────────────────────────────────────────┘
```

| State | Definition |
|---|---|
| `Target set` | Cadence *C* chosen; staleness and escalation thresholds derived from it (see [Status model](#status-model)) |
| `Manual only` | No background attempts; staleness never escalates; explicitly labelled so nobody thinks it is broken |
| `Deferred` | An attempt was made and could not proceed for a system reason we do not control (locked device, no network, Low Power Mode, Background App Refresh off). Non-actionable — must **not** count toward consecutive-failure escalation, but **must** count toward staleness |
| `Constrained` | Background App Refresh is off for our app, or Low Power Mode has been on for > 24 h. Persistent banner with the exact Settings path, because in this state we are close to non-functional and should say so |

**Deliberate honesty requirement:** the schedule screen must state that iOS controls timing and
that health data is unreadable while locked. That sentence prevents the majority of the incumbent's
support load [28][29][31]. The temptation to omit it, because it makes the product sound weak,
should be resisted — the alternative is a person concluding we are broken and telling others so.

For P3 (Dana) and anyone needing determinism, the honest answer is **Shortcuts / App Intents**,
where the *person's* automation supplies the trigger. Note the incumbent's App Intent is currently
broken with an opaque failure [32] — a typed, testable intent is a real differentiator.

**Acceptance criteria** — UX-19…UX-21, UX-33.

### Flow 5 — Manual / on-demand export with progress

Entry points: Status primary button; destination detail; Control Centre control; Home Screen widget
tap; App Intent / Shortcuts; Apple Watch.

| State | Requirement |
|---|---|
| `Queued` | Only if another run holds the lock. Show which destination is running and its progress. Never two concurrent runs against one destination. |
| `Reading Health` | **Determinate**: "Reading 24 of 41 types". Indeterminate spinners are forbidden anywhere the total is knowable. |
| `Transforming` | Merged into `Reading` unless > 1 s; separate step only when it is genuinely slow (large workout route series). |
| `Sending` | Determinate by bytes or by chunk: "Sending chunk 3 of 12 — 4.1 MB of 14.8 MB". |
| `Confirming` | Present only for protocols that can confirm. Distinguishing this step is what makes `Sent, unconfirmed` an honest state rather than a lie. |
| `Succeeded` | Record count, sample window bounds, byte size, duration, destination. Link to the run in History. |
| `Partial` | **Distinct from success.** "Exported 18,204 records from 29 of 41 types. 12 types returned nothing." With the coverage link. Partial must never be rendered as a tick. |
| `Failed` | Full error object. The run appears in History with the same detail. |
| `Cancelled` | Person-initiated. Must state whether the destination received a partial payload — and if it might have, say so, because Marcus needs to know whether to de-duplicate. |
| `Interrupted` | App backgrounded or killed mid-run. Must be recorded as interrupted, not lost. On next launch: "The export started at 09:14 didn't finish." |

**Long-running historical archive** is a distinct sub-mode (P2, P4). It may run for many minutes,
is person-initiated, and has a definite end — which is precisely the HIG profile for a **Live
Activity** [15]. See [Making failure legible](#notifications-and-live-surfaces) for the argument
that this is the *only* justified Live Activity in the product.

Archive mode additionally requires: resumability with a durable cursor; a visible completed/total
by month; and a **completion manifest** file listing types, record counts and window bounds per
type — so Sam can verify they got everything without opening the data.

**Acceptance criteria** — UX-23…UX-26.

### Flow 6 — Reviewing export history

**Default view is not chronological.** A reverse-chronological list of 400 successes with one
failure at position 87 hides the only row that matters. Default filter: **problems first**, then
everything.

```
┌────────────────────────────────────────────┐
│  History                             ⌕     │
│  [ Problems ] [ All ] [ Home Asst ▾ ]      │  segmented; Problems default
├────────────────────────────────────────────┤
│  TODAY                                     │
│  ✕ 09:14  Home Assistant                   │
│           Token rejected (401)          ›  │
│  ◐ 08:02  NAS archive                      │
│           Partial · 29 of 41 types      ›  │
│  ⊘ 03:41  Grafana (OTLP)                   │
│           Deferred · iPhone was locked  ›  │
├────────────────────────────────────────────┤
│  Showing 3 of 47 runs today.               │
│  44 succeeded.                  Show all ▸ │
└────────────────────────────────────────────┘
```

Run detail must contain, for every run: outcome; destination; trigger (background / manual /
Shortcut / widget / watch); sample window bounds; record count **per type**; byte size; duration;
each named step with its own duration; the full error object if any; the **exact payload, redacted
by default and revealable** (see [Designing for trust](#designing-for-trust)); and a `Copy
diagnostics` action producing a secret-free text block suitable for pasting into a GitHub issue.

Retention must be visible and bounded, with a stated default (assumption: 90 days or 1,000 runs,
whichever is larger) and the person able to change or clear it. History of health exports is itself
sensitive — it reveals when you sleep and where you send your data — so it must be covered by
[Flow 8](#flow-8--revoking-and-deleting-everything).

Empty state (a real state, seen by everyone on day one): "No exports yet. Run one now to check your
setup." — with the action, not just the sentence.

**Acceptance criteria** — UX-34, UX-40.

### Flow 7 — Diagnosing a failure

This is the flow the product lives or dies on. The design goal is stated as a measurable target:

> **A person who has never read our documentation can, from the notification or the Status screen,
> reach a screen that names the cause and offers the fix in at most two taps, and can attempt the
> fix without leaving the app unless the fix is genuinely outside it.**

**Path:** notification / Status card → run detail with error object → fix action → retest →
resolution.

Error object anatomy (all five parts mandatory — this is the design deliverable):

```
┌────────────────────────────────────────────┐
│  Home Assistant                            │
│  Failed · 3 attempts · 2 Sep 09:14         │
├────────────────────────────────────────────┤
│  ① homeassistant.local rejected the token  │  what didn't happen, in your terms
│                                            │
│  ② The server accepted the connection but  │  cause, plain language
│    refused the credential. Home Assistant  │
│    long-lived tokens are revoked when you  │
│    change your password or delete the      │
│    token in your profile.                  │
│                                            │
│  ③ Create a new long-lived access token in │  the fix, imperative, names where
│    Home Assistant → your profile →         │
│    Security, then replace it here.         │
│                                            │
│  ④ [ Replace token ]  [ Test again ]       │  the fix, as buttons
│                                            │
│  ⑤ ▸ Technical details                     │  evidence, collapsed
│      HTTP 401 · POST https://homeassist…   │
│      /api/webhook/ab…23 · 2 Sep 09:14:03   │
│      Authorization: Bearer ●●●●            │
│      Response: {"message":"Unauthorized"}  │
│      Trace 4f2a91c8 · build 1.0.0 (a91c8e) │
│      [ Copy diagnostics ]                  │
└────────────────────────────────────────────┘
```

Two structural rules:

- **Evidence is collapsed but complete.** Dana and Priya want the status code, the host, the exact
  path and the response body. Sam does not. Collapsing serves both; omitting serves neither.
- **`Copy diagnostics` must be secret-free by construction** — redaction happens when the
  diagnostic is composed, never as a display-layer filter over a string that contains the secret.
  The security engineer owns this constraint; I own the requirement that the affordance exists and
  is one tap from every failure.

**Non-actionable failures are labelled as such.** "iPhone was locked, so Health data couldn't be
read. We'll try again after you unlock. This is an Apple restriction on health data" [7][8]. These
must not accumulate toward a "Failing" badge, or the badge becomes noise and is ignored — which is
how status indicators die.

**Acceptance criteria** — UX-27…UX-32, UX-41.

### Flow 8 — Revoking and deleting everything

Reachable in **two taps** from Settings. Not buried, not behind a web page, no retention
interstitial, no "are you sure you want to lose all your hard work".

| Step | Content |
|---|---|
| 1. Scope | Itemised list of what will be deleted, with counts: destinations (3), Metric Sets (2), stored credentials (3, from Keychain), run history (412 runs), cached samples (0 — we should cache nothing at rest by default), diagnostic logs (18 MB). Each individually deletable too. |
| 2. Honest limits | **"We cannot delete data your destinations already received."** Then the concrete list, because vague statements are useless: "homeassistant.local received data from 12 Mar to 2 Sep · NAS archive received data from 4 Apr to 2 Sep · Grafana Cloud received data from 1 Jun to 28 Aug. To have that deleted, ask whoever runs those systems — for two of the three, that's you." |
| 3. Health access | **"We cannot turn off our own Health access."** Then the exact path — Health → Sharing → Apps → Health Exporter, or Settings → Privacy & Security → Health [1] — plus a deep link *if* one is available (see Q6). Text instructions are the guaranteed path and must always be shown. |
| 4. Confirm | Single destructive confirmation. Typed confirmation only for the all-inclusive delete, not for individual items. No countdown, no undo promise we cannot keep. |
| 5. Result | Terminal receipt screen: what was deleted, what remains and why, and the two things only they can do. Then the app is in first-run state. |

**Acceptance criteria** — UX-42…UX-44.

---

## Solving metric selection at scale

### What is actually hard

HealthKit exposes over 100 quantity identifiers and roughly 63 category identifiers, plus
characteristics, workouts, ECG, audiograms and clinical records — and the set grows every release
[1]. So "150+" is real and it is a moving target. Three things make a flat list unusable:

1. **Most types are empty for most people.** Nobody has data for all 45+ symptom types, blood
   alcohol content, UV exposure, and peritoneal-dialysis volume simultaneously.
2. **Names do not match mental models across personas.** Priya wants "sleep"; Dana wants
   `HKCategoryTypeIdentifierSleepAnalysis`; Marcus wants both plus the unit.
3. **Selection has a permission consequence** — every newly selected type widens the Apple sheet
   next time — so it cannot be a low-stakes, fiddle-freely control.

### The default state on first run: a curated set. Argued.

| Option | Why not / why |
|---|---|
| **Everything (all supported types)** | Rejected. Produces a ~150-row Apple permission sheet, which people either dismiss or blanket-accept — and blanket-accepting means we requested read access to sexual activity, pregnancy, mental-wellbeing and clinical records to export step counts. That is a data-minimisation failure the HIG explicitly warns against (*"Request access only to data that you actually need"* [14]), it is contrary to our whole trust proposition, and it inflates every payload with empty arrays. |
| **Nothing** | Rejected. A first run that exports zero records teaches the person the app does not work, at the exact moment they are deciding whether to trust it. Empty states are where this product lives, and an *avoidable* empty state is a self-inflicted wound. |
| **Curated set (recommended)** | **Chosen.** ~24 types covering what nearly everyone has and nearly everyone wants: activity, sleep, heart, body mass, workouts. Small enough that the Apple sheet is comprehensible (~24 rows, scannable). Guarantees a non-empty first export for essentially every user. One tap to expand. |

**Additional rule: no shipped preset ever includes a sensitive type.** Sensitive class (my
proposed definition, for the PM and security engineer to ratify): sexual activity, pregnancy /
lactation / contraceptive, menstrual and cycle types, mental wellbeing and State of Mind, alcohol
and substance-related types, all clinical records, and all symptom types. These require individual,
deliberate selection with a confirmation that names the destination. The concrete harm being
designed against: a "Select all" that silently publishes a pregnancy record to an MQTT topic on a
broker in a shared household. That is not a theoretical privacy nit; it is a safety event, and
"the user chose Select all" is not a defence.

### The picker

```
┌──────────────────────────────────────────────┐
│  Core Daily                          Done    │
│  ⌕ Search 41 selected of 152                 │
├──────────────────────────────────────────────┤
│  ▸ PRESETS                                   │
│    Home Assistant Essentials       Adopt     │
│    Sleep & Recovery                Adopt     │
│    Workouts & Routes               Adopt     │
│    Everything with data on this iPhone       │
│                                      Adopt   │
│    Everything supported (152)      Adopt     │
├──────────────────────────────────────────────┤
│  [ ✓ Only types with data ]  ← filter, ON    │
├──────────────────────────────────────────────┤
│  ACTIVITY                        12 of 18 ▾  │
│   ☑ Steps            4,812 samples · count   │
│   ☑ Walking + Running distance    · km       │
│   ☐ Push count       no data      · count    │
│  HEART                            6 of 14 ▾  │
│   ☑ Heart rate      182,004 · count/min      │
│   ☑ Resting heart rate  412 · count/min      │
│   ☐ Atrial fibrillation burden  no data · %  │
│  SLEEP                             1 of 1 ▾  │
│   ☑ Sleep analysis    2,204 · category       │
│  ⚠ SENSITIVE — select individually     0 of 21│
├──────────────────────────────────────────────┤
│  Select section · Invert · Clear all         │
└──────────────────────────────────────────────┘
```

Design decisions and why:

| Decision | Rationale |
|---|---|
| **Sections mirror Apple Health's own categories** (Activity, Body Measurements, Cycle Tracking, Hearing, Heart, Medications, Mental Wellbeing, Mobility, Nutrition, Respiratory, Sleep, Symptoms, Vitals, Other Data, Clinical Records) | The person already has a mental model from the Health app. Reusing it is free comprehension. Inventing our own taxonomy costs them a translation step. |
| **`Only types with data` filter, default ON** | The single biggest reduction available: ~152 rows → typically 30–60. Costs one one-sample query per type, which we run anyway for coverage (Flow 1, `S6`). |
| **Row subtitle carries sample count, latest sample, and unit** | Answers "do I want this?" without a tap. The unit is what Marcus is actually checking. |
| **Search matches display name, synonyms, *and* the raw HealthKit identifier** | Dana types `HKQuantityTypeIdentifierStepCount`. Priya types "weight" and must find Body Mass. Synonyms are a content deliverable: weight→bodyMass, BP→bloodPressure, VO2→vo2Max, HRV→heartRateVariabilitySDNN, SpO2→oxygenSaturation, glucose→bloodGlucose. |
| **Search placed in the bottom toolbar** | iOS 26 guidance: bottom placement is the most ergonomic and the field animates up over the keyboard [26]. A 152-row list is exactly the case where reachability matters. |
| **Bulk actions are section-scoped, plus Invert and Clear all** | No unscoped "Select all" — the only way to select everything is to adopt the explicit `Everything supported` preset, which carries its own warning and its sensitive-type exclusion. |
| **Sensitive section is collapsed, count-only, and cannot be bulk-selected** | Per the rule above. |
| **Diff review before commit** (Flow 3) | Makes the permission consequence visible before it happens, and predicts the Apple sheet. |

### The presets, as a content deliverable

| Preset | Approx. types | Intent | Notes |
|---|---|---|---|
| **Core Daily** (first-run default) | ~24 | Non-empty first export for nearly everyone | Steps, distances, active/basal energy, exercise & stand time, flights, heart rate, resting HR, HRV, walking HR avg, VO2max, sleep analysis, body mass, height, BMI, body fat %, respiratory rate, blood oxygen, workouts |
| **Home Assistant Essentials** | ~18 | Types HA renders well as sensors, at cadences HA expects | Must be co-designed with whoever owns the HA integration; a preset that emits entities HA cannot type is worse than no preset |
| **Sleep & Recovery** | ~12 | Sleep stages, HRV, resting HR, respiratory rate, wrist temperature, sleeping breathing disturbances | |
| **Workouts & Routes** | ~10 + workout types | Workouts, routes/GPX, per-workout aggregates | Route data is location data — needs its own consent line |
| **Body & Vitals** | ~14 | Mass, BMI, body fat, BP, temperature, oxygen saturation | |
| **Nutrition & Hydration** | ~30 | Only useful to people who log food; opt-in, never default | |
| **Everything with data on this iPhone** | dynamic | The pragmatic "everything" — computed from the has-data probe | Excludes sensitive class unless individually added |
| **Everything supported** | ~152 | P2/P4's true "give me it all" | Warning screen: sheet size, payload size, sensitive types listed individually for explicit inclusion |

Presets must be **versioned**, and adopting one creates a **fork** the person owns. When we ship
v2 of "Home Assistant Essentials" the person is *offered* the diff ("adds 3 types, removes 1"), not
silently migrated. Silently changing what a person exports is the same class of violation as
silently changing units.

---

## Making failure legible

### Status model

One state machine, per destination, used identically by the Status screen, the destination list,
History, the widget, the watch and notifications. A person must never see two surfaces disagree.

Let *C* = the destination's cadence (from its freshness target). Let *L* = time since last
**success**.

| State | Definition (testable) | Non-colour encoding | Person's next action |
|---|---|---|---|
| `Unconfigured` | Created, never passed a test | `circle.dashed` + "Not set up" | Finish setup |
| `Manual only` | No cadence; person's choice | `hand.tap` + "Manual only" | none — never escalates |
| `Never run` | Enabled, zero runs | `circle.dotted` + "No exports yet" | Export now |
| `Healthy` | Last run succeeded **and** *L* ≤ max(1.5·*C*, 45 min) | `checkmark.circle.fill` + "Healthy" | none |
| `Sent, unconfirmed` | Last run sent but protocol cannot confirm delivery | `paperplane.circle` + "Sent, not confirmed" | Consider QoS ≥ 1 |
| `Partial` | Last run completed; ≥ 1 selected type returned nothing, or destination rejected some records | `circle.lefthalf.filled` + "Partial" | Review coverage |
| `Stale` | *L* > max(2·*C*, 90 min) **and** no error recorded | `clock.badge.exclamationmark` + "Stale" | Export now / diagnose |
| `Failing` | ≥ 1 consecutive **actionable** error; count shown | `exclamationmark.triangle.fill` + "Failing" | Fix, named in the error |
| `Blocked` | Cannot proceed without a person's action: credential rejected, certificate untrusted, coverage empty | `exclamationmark.octagon.fill` + "Blocked" | The named fix |
| `Deferred` | Last attempt could not proceed for a system reason (device locked, no network, Low Power Mode, no background grant) | `pause.circle.fill` + "Waiting" | usually none; if persistent → `Constrained` |
| `Constrained` | Background App Refresh off, or Low Power Mode > 24 h | `bolt.slash.fill` + "Limited by iOS settings" | Exact Settings path |
| `Paused` | Person paused it | `pause.fill` + "Paused" | Resume |

**Escalation to notification** at *L* > max(4·*C*, 6 h) — call this the *overdue* threshold — for
`Stale`, `Failing`, `Blocked` and persistently `Deferred`.

**Three requirements that distinguish us from the incumbent:**

1. **Absence of success is itself an error condition.** `Stale` exists, is computed from
   `lastSuccess` alone, and escalates *without any error having been recorded*. This is the
   incumbent's blind spot [29][31] and closing it is the product's reason to exist.
2. **`Deferred` never masquerades as success and never inflates failure.** It counts toward
   staleness (so silence still escalates) but not toward consecutive-failure counts (so the badge
   stays meaningful).
3. **`Sent, unconfirmed` is a first-class state.** Reporting "Data published to broker" when the
   broker address is bogus [30] is the exact bug this state exists to prevent.

**Freshness is always shown as relative *and* absolute:** "42 min ago · 2 Sep, 08:31". Relative
alone is unreadable after a week; absolute alone requires arithmetic. VoiceOver announces the
absolute form.

### Error content guidelines

Error content is a design deliverable with a fixed schema. Every error has five parts:

| Part | Rule |
|---|---|
| **① Title** | What did not happen, in the person's terms, naming the destination. Never an exception class, never a numeric code, never "Error". ≤ 60 characters at default type size. |
| **② Cause** | Plain language, one or two sentences, in the second person. May name the protocol. Must not paraphrase a stack trace. |
| **③ Fix** | Imperative. Names the specific thing to change and where it lives — including *in someone else's product* when that is where the fix is. If there is no fix, say there is no fix. |
| **④ Actions** | 1–2 buttons that begin the fix. Prefer in-app. `Test again` is always available. |
| **⑤ Evidence** | Collapsed. Status code, method, host, redacted path, timestamp with offset, response body (truncated), trace ID, build hash. Plus `Copy diagnostics`. |

**Prohibited, without exception:** "Something went wrong", "Unknown error", "Please try again"
without saying what changed, raw `NSError` descriptions, bare numeric codes as the title, and the
word "sync" (ambiguous — say "export", "read", or "deliver").

**The archetypes.** This table is the content spec; each row is a string the copy owner writes and
QA tests by inducing the condition.

| Condition | Typical (rejected) | Required |
|---|---|---|
| Host will not resolve | `NSURLErrorDomain -1003` | ① "Couldn't find homeassistant.local" ② "That name didn't resolve on your current network. `.local` names only work on the same network as the server." ③ "If you're away from home, use your external address or connect to your VPN. You can add a second address for when you're away." ④ Edit destination · Test again |
| TLS trust failure | `-1202` | ① "Couldn't verify nas.example.com's certificate" ② "The server presented a certificate this iPhone doesn't trust. Self-signed and private-CA certificates aren't trusted by default." ③ "Import the server's certificate and pin it here, or install a publicly trusted certificate (Let's Encrypt) on the server." ④ Import certificate · How to do this |
| Certificate expired | `-1201` | ① "nas.example.com's certificate expired on 14 Aug" ② "…" ③ "Renew it on the server. If you use Caddy or Traefik, check that automatic renewal is still running." |
| HTTP 401 | `Request failed: 401` | ① "homeassistant.local rejected the token" ② "The connection was accepted but the credential refused. HA long-lived tokens are revoked when you change your password or delete the token." ③ "Create a new long-lived access token in HA → your profile → Security, then replace it here." ④ Replace token · Test again |
| HTTP 403 | | ① "homeassistant.local refused this request" ② "The credential was recognised but isn't allowed to write here." ③ "Check the token's permissions, or the webhook's allowed scope." |
| HTTP 404 | | ① "That path doesn't exist on homeassistant.local" ② "The server responded, but nothing is listening at /api/webhook/ab…23." ③ "Check the webhook ID in HA → Settings → Automations → your webhook trigger." |
| HTTP 413 | | ① "The export was too large for homeassistant.local" ② "We sent 8.4 MB; the server appears to accept about 1 MB." ③ "Shorten the export window from 24 hours to 6, or raise `client_max_body_size` on your reverse proxy." ④ **Shorten window** — a fix we own |
| HTTP 429 | | ① "homeassistant.local asked us to slow down" ② "Rate limited. It asked us to wait 15 minutes." ③ "We'll retry automatically. If this keeps happening, choose a less frequent freshness target." |
| HTTP 5xx | | ① "homeassistant.local returned an error (502)" ② "The server, or the proxy in front of it, isn't healthy. **Your settings here look correct.**" ③ "Check the server. We'll keep retrying." |
| Timeout | | ① "homeassistant.local didn't respond in time" ② "We waited 30 seconds. The host may be asleep, or the connection may be slow." ③ "Try again on Wi-Fi. If the server sleeps, wake it or increase its timeout." |
| MQTT CONNACK 5 | `MQTT error 5` | ① "The broker refused the credential" ② "The broker accepted the connection then rejected the username or password (CONNACK 5, not authorised)." ③ "Check the MQTT user in your broker's config." |
| MQTT QoS 0 publish | **"Data published to broker"** [30] | ① "Sent — delivery not confirmed" ② "QoS 0 doesn't confirm anything received the message. The broker may have accepted and dropped it." ③ "Set QoS to 1 so we can confirm delivery." ④ **Set QoS to 1** |
| HealthKit locked (`errorDatabaseInaccessible`) [8] | `HKError 6` | ① "Health data was locked" ② "iPhone must be unlocked for any app to read Health data. Access ends ten minutes after you lock it. This is an Apple restriction." ③ "Nothing to fix. We'll export next time you unlock." — marked **non-actionable**; no failure count |
| Background never ran | *silence* [29][31] | ① "No exports since 31 Aug" ② "iOS decides when apps may run in the background and can skip us — especially in Low Power Mode or if Background App Refresh is off." ③ "Turn on Settings → General → Background App Refresh → Health Exporter, or export manually / from Shortcuts for exact timing." ④ Export now · Open Settings |
| Zero records | "Success: 0 records" | ① "Nothing to export" ② "None of your 41 selected types returned data for 1–2 Sep. That can mean there's no new data, or that access to those types is off in Health — **we can't tell which**." ③ "Check Health → Sharing → Apps → Health Exporter." ④ Review coverage |
| Destination out of space | | ① "Dropbox is full" ② "…" ③ "Free space, or choose another destination." |
| Rejected payload shape | | ① "homeassistant.local didn't understand the payload" ② "It responded 400 with: `expected 'state' key`." ③ "Check the format setting on this destination. HA webhooks expect …" ④ Change format · See payload |

### Notifications and live surfaces

**Consent.** Request notification permission with `.provisional` at first destination setup.
Provisional grants immediately without a prompt and delivers quietly to Notification Center with
"Keep"/"Turn off" buttons attached [18]. This is the right fit: the person cannot evaluate whether
they want failure alerts before they have seen one, and a day-one prompt for an app whose value is
"tell me when it breaks" will be denied by people who would have wanted it. Upgrade to full
authorisation at the moment a real failure occurs, in context ("Get alerted next time this
happens?"). Note the hazard: if we later prompt for full authorisation and the person denies,
provisional notifications also stop [18] — so never prompt speculatively.

| Category | Default | Rule |
|---|---|---|
| **Failure** (actionable) | On | Max 1 per destination per 24 h. Thread-identified per destination so repeats collapse. Body = the error's ① Title. Deep links to the run detail. |
| **Stale / overdue** | On | Fires at the overdue threshold. **Implemented as a pre-scheduled local notification** (see below). |
| **Recovered** | Off | Available, off by default. |
| **Weekly digest** | On | "This week: 41 exports, 2 failures, all destinations healthy." Establishes that the monitoring itself is alive. |
| **Progress / success** | Never | Per-export success notifications are the fastest way to train someone to ignore us. |

**The watchdog — the most important mechanism in this document.** Background execution cannot be
relied upon [33], so a failure detector that requires our code to run is a failure detector that
fails exactly when needed. But **local notifications fire at their scheduled time whether or not
the app runs** [33]. Therefore:

> On every successful export, cancel and re-schedule a local notification for
> `lastSuccess + overdueThreshold`, per destination. If exports keep working, the notification is
> perpetually deferred and never seen. If they stop for any reason at all — background starvation,
> revoked permission, dead server, app crash, iOS update — it fires.

This inverts the category's defining failure. Silence becomes an event. Copy: "No exports to Home
Assistant since 31 Aug. Open to check." (**UX-22**, Must.)

**Content rule: notifications must never contain health values.** Notifications appear on the Lock
Screen and mirror to Apple Watch, potentially in front of other people. "Blood glucose 4.2 mmol/L
exported" is a disclosure. Notifications carry status, destination and error text only.

**Widget: yes.** Small and medium `systemSmall` / `systemMedium`, available on iPhone Home Screen
and Today View, iPad, and — since iOS widgets appear on Mac as remote widgets [17][27] — on the Mac
desktop and Notification Center without extra work. Content: destination name, state glyph, "42 min
ago", next-attempt window. Constraints: WidgetKit `accented` and `vibrant` rendering modes strip
colour and desaturate [16], so state **must** be legible by glyph shape and text alone — which the
[Status model](#status-model) already guarantees. The widget shows **no health values**, for the
same reason as notifications. Tap deep-links to the destination's status.

**Control Centre control: yes.** A `ControlWidgetButton` "Export now" [17] is an excellent fit for
the on-demand job (P3, P4) and for the "I'm about to look at my dashboard" moment (P1). Cheap,
high-value, and it gives people determinism the scheduler cannot.

**Live Activity: no, with one exception.** HIG: Live Activities are for *"tasks and events that
have a defined beginning and end… that don't exceed eight hours"*, and *"Live Activities that appear
unexpectedly… may [be unwelcome]"* [15]. A routine 4-second background export has no business on
the Lock Screen, and an 8-hour cap plus 4-hour residency [15] makes it useless as a persistent
status surface — that is the widget's job. **The exception is the one-shot historical archive**
(P2, P4): person-initiated, minutes-to-hours, definite end, genuinely benefits from off-app
progress. End it immediately on completion with a dismissal policy of 15–30 minutes so the summary
is glanceable, per HIG [15]. (**UX-25**, Should.)

**Redundancy requirement.** Notifications can be denied or turned off, so they cannot be the only
failure surface. Every escalated state must be simultaneously visible in: the Status screen
attention row, the app icon badge (count of destinations needing attention), the widget, and the
watch complication. Four independent surfaces, one shared state machine.

---

## Credential entry without misery

Typing `https://homeassistant.local:8123/api/webhook/ab3f-91c8-4d2e` and a 180-character
long-lived access token on a touch keyboard is the worst five minutes in this product. Worse, it
fails *quietly* — a smart-quote substitution or a trailing space produces a 401 that looks like a
revoked token.

*A security engineer is separately setting hard constraints on secret storage, transport and
redaction. What follows is the interaction design that must work within whatever they decide; where
the two conflict, they win and I will redesign.*

### Getting the string in without typing it

| Mechanism | Priority | Detail |
|---|---|---|
| **QR / camera config import** | Should | Camera scans a QR encoding a config bundle. Best flow in the product: the person's server (HA add-on, our OSS companion, or a page in our docs where *they* paste their own values locally) renders a QR; the phone scans it; every field is populated and the connection test runs immediately. Import must show a **review screen** listing every field and destination host before anything is saved — an unreviewed scan is a phishing vector. |
| **Config file import (Files / AirDrop / Handoff)** | Should | A `.ohexport` JSON file authored on the Mac (see [Platform split](#platform-split)) or hand-written by Dana, opened via the document picker or AirDropped. Same review screen. Secrets may be omitted from the file and requested separately. This is also the honest answer to "Handoff from Mac": the Mac authors config, the phone consumes it. |
| **Paste, made obvious** | Must | A visible paste affordance on every URL and secret field, using the system paste button so no clipboard-access prompt appears. Combined with Universal Clipboard, copy-on-Mac → paste-on-iPhone is already the fastest path and we should stop hiding it behind a long-press. |
| **Password AutoFill / Keychain** | Could | Where a destination genuinely maps to a website credential. Low value for bearer tokens; do not over-invest. |
| **Typed entry** | Must | The fallback, made as safe as possible — see below. |
| **Deep-link config URL** | Won't (v1) | A `openhealthexporter://configure?...` link cannot safely carry a secret: URLs land in logs, history and pasteboards. If we support it at all it carries non-secret config only. Rejecting this is a deliberate choice, not an omission. |

### Making typed entry survive a touch keyboard

Requirements, all testable:

- URL and token fields **disable autocorrection, autocapitalisation and smart punctuation** (smart
  quotes and en-dashes silently corrupting tokens is the most common invisible cause of 401s), use
  the URL keyboard type for URLs, and never trim characters silently.
- **Leading/trailing whitespace is stripped, visibly**, with an inline note: "Removed a trailing
  space."
- **Parse-back display.** As the person types, render the parsed components underneath:
  `https · homeassistant.local · :8123 · /api/webhook/ab3f-…`. If a component is missing or
  surprising, say so inline: "No port — we'll use 443." This catches most typos before any network
  call.
- **Field-level, non-blocking validation.** No modal alerts, no validation-on-save-only.
- **Length and shape feedback on secrets** without revealing them: "214 characters · looks like a
  JWT". Shape detection catches "you pasted the wrong thing" — e.g. a HA *webhook URL* pasted into
  the token field.

### Test before save

Specified in [Flow 2](#flow-2--adding-and-testing-a-destination). Restating the requirement because
it is the most load-bearing one in this section: **a destination cannot be saved in an enabled
state until a real test has passed**, the test must exercise the real path with the real credential
and a real (minimal) payload, and it must report per-step so the failing step is the diagnosis.

### Storing, displaying and replacing secrets

| Pattern | Requirement |
|---|---|
| **Never displayed by default** | A stored secret renders as a fixed-width mask plus a non-reversible descriptor: `●●●●●●●● · 214 chars · JWT · added 12 Mar`. Enough to answer "is this the new one?" without exposing it. |
| **Reveal is gated and timeboxed** | `Reveal` requires local authentication (Face ID / Touch ID / passcode), reveals **one** field, auto-hides after 15 seconds, and is unavailable while any screen recording is active if detectable. Reveal is a `Could` — replacing is usually the better answer. |
| **Replace, not edit** | The primary secret action is `Replace`, which opens an empty field. Editing in place invites truncation of a masked value. |
| **Never in a list, never in a log** | Secrets never appear in the destination list, History, payload previews, `Copy diagnostics`, OpenTelemetry traces, or crash reports. Redaction happens at composition, not display. |
| **Deletion is explicit and confirmed** | Removing a destination removes its Keychain item, and the confirmation says so. |

### Certificates and self-signed servers — the honest problem

Self-hosters overwhelmingly run private CAs or self-signed certificates. TLS trust failure will be
one of our top three errors. Three options:

| Option | Assessment |
|---|---|
| **(a) Refuse; require a publicly trusted certificate** | Safest, and increasingly reasonable given Let's Encrypt with DNS-01 works for internal hosts. But it makes us useless to a large share of our core audience on day one, delivered as a wall. |
| **(b) Import and pin a specific certificate (recommended)** | The person imports the certificate (Files / AirDrop / QR / fetch-and-confirm-on-first-connect). We display **subject, issuer, SHA-256 fingerprint, validity dates** and require an explicit "I trust this certificate for nas.example.com". Trust is scoped to that host, persisted, and shown in the destination detail with an expiry warning 14 days out. |
| **(c) A global "allow insecure connections" toggle** | **Reject.** It is a dark pattern pointed at the person who trusts us most: one switch, no evidence, permanently on, silently accepting any certificate for any host thereafter. It also destroys the trust story that is our whole differentiator. |

Recommendation: **(b), with (a) as the guided default** — the TLS error's ③ Fix names Let's Encrypt
*first* and certificate pinning second. Final call belongs to the security engineer
([Q7](#open-questions-for-the-pm)).

---

## Platform split

The honest split follows from one fact: **only iOS, iPadOS and watchOS can read HealthKit**
[4][5]. Everything else is companion.

| Surface | Owns | Explicitly out of scope | Why |
|---|---|---|---|
| **iPhone (iOS 26)** | The product. All configuration, all metric selection, all credential entry, all HealthKit reads, all export execution, all history, all diagnostics. The only surface where the app is complete. | — | It is the only device that is both HealthKit-capable and always carried. Everything else is derivative. |
| **iPad (iPadOS 26)** | Same binary, adaptive layout (sidebar + detail). Genuinely *better* than iPhone for: authoring Metric Sets (152 rows on a large display), reading run history and diagnostics, entering credentials with a hardware keyboard. Can export its own HealthKit data (iPadOS 17+) [4]. | Being the primary scheduled exporter. | An iPad's HealthKit store holds only what that iPad recorded plus what syncs to it — and iPads are frequently uncharged and unattended for days, which is the worst possible host for a freshness guarantee. **Requirement:** if the iPad is the only enabled exporter, say so plainly and recommend the iPhone. |
| **Mac (macOS 26)** | **Not an exporter — it cannot be one** [4][5]. Honest roles: (1) **config author** — build destinations and Metric Sets on a real keyboard, export a `.ohexport` bundle for the phone (secrets optional); (2) **diagnostics viewer** — open a diagnostics bundle from the phone, read run history and traces on a big screen; (3) **local receiver** — a destination the phone sends to over the local network, paired by QR. Plus iOS widgets appear on the Mac desktop for free [17][27]. | Reading Health data. Charts of health data. Any iCloud-mediated transfer of health data. | `isHealthDataAvailable()` returns `false` on Mac, confirmed by Apple DTS [5]. And 5.1.3(ii) forbids storing personal health information in iCloud [19], which closes the incumbent's iCloud-sync-to-Mac route [28]. **The premise's "first-class macOS support" must be restated as "a first-class Mac companion".** Priority: Should, not Must. |
| **Apple Watch (watchOS 26)** | Exactly three things: (1) a Smart Stack widget / complication showing the worst destination state and time since last success; (2) an `Export now` button; (3) failure notifications forwarded from the phone. | Destination editing. Credential entry. Metric selection. History browsing. Charts. Anything requiring text input or more than one decision. | HIG: watch interactions should be *"focused and highly-specialised"*, optimised for glanceability and a few seconds [35]. Also watchOS background budget is roughly four updates per hour *and only with an active complication* [9] — so the watch cannot be a reliable independent exporter either. |
| **Widgets (iOS / iPadOS / watchOS / Mac)** | Export status only: destination, state glyph, relative freshness, next-attempt window. Small and medium families. | **Any health value, ever.** | Widgets are visible to anyone glancing at the device. A menstrual-cycle or blood-glucose value on a Home Screen is a disclosure with no consent step. Also `accented`/`vibrant` rendering modes strip colour [16], which the shape-based status encoding already handles. |
| **Control Centre / Action button** | One `ControlWidgetButton`: `Export now` (configurable destination) [17]. | Toggling destinations on/off — too consequential for an accidental Control Centre tap. | Cheap, and gives determinism the scheduler cannot. |
| **Shortcuts / App Intents** | First-class: `Export now`, `Export type X for window Y`, `Get last export status`, with typed results and distinguishable failures. | Being the *documented* answer to "I want a reliable schedule" without also stating the device-lock constraint. | The honest determinism story (Flow 4). The incumbent's intent currently fails opaquely [32] — a working, testable intent is a real differentiator. |
| **visionOS** | Nothing in v1. | Everything. | HealthKit is available on visionOS [4] but there is no audience and no job to be done. Say "no" clearly rather than shipping a stub. |
| **All surfaces** | — | **Statistics and charts of health data.** | This is the incumbent's differentiator, not ours. It doubles the design surface, competes with Apple Health and with Grafana (which is where our users' charts already live), and every hour spent on it is an hour not spent making failure legible. **Recommend "Won't" for v1**, and say so in the README so we are not accused of an omission. |

---

## Accessibility, localisation and units

These are requirements with acceptance criteria, not aspirations. Standard: **WCAG 2.2 Level AA**
as the floor for everything we control [22], plus Apple platform guidance where it is stricter or
more specific.

### Visual and motor

| Requirement | Standard | Acceptance |
|---|---|---|
| Text contrast ≥ 4.5:1; large text (≥ 18 pt, or 14 pt bold) ≥ 3:1 | WCAG 2.2 SC 1.4.3 (AA) [22][23] | Every text/background pair measured on composited colours (not flat hex — translucency changes the result) in light, dark, and Increase Contrast, in both Liquid Glass appearances (Clear and Tinted) [34]. Zero failures. |
| Non-text contrast ≥ 3:1 for status glyphs, control boundaries, focus rings | WCAG 2.2 SC 1.4.11 (AA) [22][24] | Measured for all twelve status glyphs against every surface they appear on, including the widget's `vibrant` mode [16]. |
| **Status is never conveyed by colour alone** | WCAG 2.2 SC 1.4.1 (A) [22][24] | Every status is a distinct **SF Symbol shape** + a **text label** + a stable position. Verification: render every state to greyscale and through protanopia, deuteranopia and tritanopia simulation; all twelve states remain mutually distinguishable **and** correctly identifiable by shape and label with hue removed. |
| Dynamic Type from xSmall to AX5 | WCAG 2.2 SC 1.4.4; Apple Dynamic Type guidance [25] | Every screen in Flows 1–8 at AX5 with **Bold Text and Display Zoom also enabled**: no clipped text, no overlap, no horizontal scrolling, no truncated status words, all controls reachable. Layouts reflow (rows → stacked) at `isAccessibilitySize`. |
| Fixed-size text has a Large Content Viewer alternative | Apple guidance [25] | Any element that legitimately cannot scale (tab bar, toolbar glyphs) responds to long-press with the Large Content Viewer. |
| Touch targets ≥ 44×44 pt | Apple guidance | Audited on the metric picker, whose dense rows are the likeliest offender. |
| Honour Reduce Transparency, Increase Contrast, Reduce Motion, Reduce Brightness | Apple accessibility settings; Liquid Glass responds to these [34] | With Reduce Transparency on, no status text sits on a translucent surface over arbitrary content. With Reduce Motion on, no state change is communicated by animation or glass morph alone. |
| Liquid Glass confined to the navigation layer | Current HIG: glass is *"best reserved for the navigation layer that floats above the content"*; never stack glass on glass [20][21] | Status cards, error content, metric rows and payload previews are on the opaque content layer. Toolbars, tab bar, sheets and the floating `Export now` control may be glass. Multiple glass elements share a container [20]. |

### VoiceOver and screen-reader semantics

| Requirement | Acceptance |
|---|---|
| Every status row announces one sentence: state + destination + freshness. "Home Assistant. Failing. Last successful export 31 August at 7:12 a.m." | Spoken output transcript reviewed for all twelve states. |
| Secondary detail via `accessibilityCustomContent` so the default announcement stays short but nothing is unreachable | Attempt count, next-attempt window, error title all retrievable without visual inspection. |
| Metric picker rows announce name, has-data status, and unit — not the raw identifier | "Resting heart rate. 412 samples. Counts per minute. Selected." |
| Error objects are navigable in order ① → ⑤, with the fix actions as buttons and ⑤ as a disclosure | — |
| A History rotor for failed runs | A screen-reader user can jump between failures without traversing successes. |
| **Flows 1, 2, 5 and 7 completable with the screen curtain on** | Recorded end-to-end runs by a VoiceOver-proficient tester. This is the acceptance test that matters; the rest are inputs to it. |
| Masked secrets never spoken; the descriptor is | "Token. 214 characters. Added 12 March. Double-tap to replace." |

### Localisation and RTL

| Requirement | Acceptance |
|---|---|
| All user-facing strings localised; **no runtime string concatenation** for sentences; all interpolation positional | Pseudo-localised build (+40% length, accented) shows no truncation at default type size on any Flow 1–8 screen. |
| Dates, times, numbers and units formatted via system `FormatStyle` / `Measurement`, never hand-formatted | Verified under `en_US`, `de_DE`, `ja_JP`, `ar_EG`, `en_GB` with both 12- and 24-hour preferences. |
| RTL-ready: leading/trailing layout, mirrored chevrons and progress direction, correct bidi in mixed strings containing Latin hostnames | RTL screenshot review of Status, Destinations, metric picker, error detail, History. A hostname inside an Arabic sentence renders correctly. |
| Error ⑤ Evidence stays untranslated (identifiers, status codes, headers); ①–③ localised | So a pasted diagnostic is searchable by the maintainers regardless of the reporter's language. |
| **Reduce truncation risk in status words** — "Limited by iOS settings" is long in German | Layout uses wrapping, not truncation, for state labels at all type sizes. |

### Units, and the one non-obvious decision

Apple provides the person's own unit preference: `preferredUnits(for:)` returns the unit chosen in
the Health app, or the locale default, and `HKUserPreferencesDidChange` fires when they change it
[12][13].

| Requirement | Rationale |
|---|---|
| **Display units follow the Health app.** Read `preferredUnits(for:)`, observe `HKUserPreferencesDidChange`, update immediately [12][13]. We do not invent our own display-unit setting. | Their weight is in stones in Health; it must be in stones here. Anything else is us being wrong in their own app. |
| **Export units are separate, explicit, and stable.** Default to a canonical unit per type (SI where sensible: kg, m, s, °C, mmol/L, count/min), configurable per Metric Set, **and never changed by a Health app preference change.** | This is the important one. If Marcus toggles lb in Health and his Grafana panels silently switch units, we have corrupted his dataset and he will not forgive it. Display follows the person; the wire format follows the contract. |
| **Every exported value carries its unit explicitly**, alongside a payload-level schema version | Makes the payload self-describing and makes a future unit change detectable rather than silent. |
| **Changing an export unit is a versioned, diffed, warned action** | Same treatment as a Metric Set change: "This changes the unit of Body Mass from kg to lb for all future exports to nas.example.com. Existing data at the destination is not converted." |
| Timestamps on the wire are **ISO 8601 with explicit offset**, always, plus the sample's recorded time zone | "2026-09-02T08:31:14+02:00". Never a naïve local string, never a bare epoch without documentation. |
| Blood glucose respects HealthKit's documented exception for results-type units [12] | Noted so it is not treated as a bug. |
| 12/24-hour display from locale and system setting | Never hard-coded. |

---

## Designing for trust

We are asking people to hand the most sensitive data on their device to a piece of software, and
our entire value proposition is that they can. Trust is not earned by a privacy paragraph. It is
earned by **showing**, repeatedly and verifiably, exactly what happens.

### 1. The data-flow explainer (Must)

A first-class screen, shown in onboarding and permanently reachable from Settings, in plain
language, rendered from the person's *actual* configuration — not a generic marketing diagram:

```
   Apple Health (on this iPhone)
        │  we read 41 types you chose
        ▼
   Health Exporter (this app, on this iPhone)
        │  we transform to JSON. Nothing is stored
        │  after a successful send.
        ├──▶ homeassistant.local:8123  ·  HTTPS  ·  bearer token
        ├──▶ nas.example.com:8883      ·  MQTTS  ·  username + password
        └──▶ Files on this iPhone      ·  no network
   
   Nowhere else. No account. No analytics. No crash reporting.
   Diagnostics leave this device only when you tap Copy or Share.
```

Every host in it is a host the person typed. That is the argument, made structurally.

### 2. "Show me exactly what you sent" (Must)

For every run in History, the **exact payload**, redacted by default, revealable. Truncated with a
byte count for large runs, with the full payload exportable to Files.

This is simultaneously the strongest trust artefact and the best debugging tool in the product, and
it is the thing no incumbent offers. It converts "trust us" into "look for yourself". It is also
what lets Dana build against us and Marcus verify us.

### 3. The network activity ledger (Should)

A persistent, append-only list: every host this app has ever contacted, with first-seen, last-seen,
request count and bytes. It should be short and it should contain nothing surprising.

Intellectual honesty requirement: this list is **self-reported** and must say so — "This is what
the app records about its own network use. For an independent check, the source is at
`<commit>` and you can watch the traffic with a proxy." A self-reported list is not proof; combined
with an auditable build it is corroboration, and pretending otherwise would itself be a trust
violation.

### 4. Build provenance (Should)

Settings shows the version, the **exact source commit hash**, and a link to it. For an
open-source trust claim, "auditable" is meaningless unless the running binary maps to readable
source. Reproducible builds are an engineering ask I am registering here as a UX requirement,
because the *claim* is a UX artefact.

### 5. Resolving the observability/privacy tension (Must)

The brief flags that OpenTelemetry tracing and privacy-first are in tension and that resolving it
is a requirement [brief §3]. The UX resolution:

- Diagnostics and tracing are **off by default**, opt-in, with no nag.
- An OTLP endpoint is **a destination like any other** — it appears in the destination list, in the
  data-flow explainer, and in the network ledger. It is not a privileged back channel.
- Traces carry **type identifiers, record counts, durations and outcomes — never sample values**.
  This must be enforced at composition, not by a redaction pass.
- Before enabling, the person sees a **live preview of a real trace** from their own device, with
  the actual fields. Not a description of what it contains — the thing itself.
- Sensitive-class types are represented in traces by count only, never by name, because
  "read 1 sample of `sexualActivity`" is itself a disclosure.

### 6. Dark patterns, enumerated and forbidden

| Forbidden | Because |
|---|---|
| Pre-ticked consents of any kind | — |
| An unscoped "Select all" over metric types | Ships sensitive types by accident (see [metric selection](#solving-metric-selection-at-scale)) |
| Reporting success when delivery is unconfirmed | The incumbent's exact bug [30] |
| Rating prompts, upsells, "pro" gates, launch interstitials | It is OSS with no account; there is nothing to sell and no excuse |
| Retention interstitials on delete ("are you sure you want to lose…") | Flow 8 must be frictionless |
| Any custom screen resembling a system alert, or annotating the screen behind one | Explicitly prohibited by HIG and grounds for App Review rejection [14] |
| A permission-priming screen with a competing "Allow"-flavoured button | Explicitly prohibited by HIG [14] |
| Claiming or implying we know what the person denied in Health | We cannot know [1][2][3]. Saying we do is a lie about their privacy posture — the worst possible category of lie for this app |
| Notifications or widgets containing health values | Unconsented disclosure to bystanders |
| Burying the honest platform limitations (device lock, background timing, macOS) | Short-term polish bought with long-term trust |

### 7. What we say about deletion

Flow 8 states two things most apps hide: we cannot revoke our own Health access, and **we cannot
delete data your destination already received.** Saying both, with the concrete date ranges per
destination, is worth more than any privacy badge — because it is the kind of statement only
someone not trying to manipulate you would volunteer.

---

## Requirements I own

Every requirement has a verification method a QA engineer could execute. `C` = the destination's
cadence.

### First run and permissions

| ID | Requirement | Priority | Rationale | How we verify |
|---|---|---|---|---|
| UX-01 | The app must never assert, imply or display that a HealthKit read permission was denied. All zero-result cases must state both possible causes ("no data in Health, **or** access is off") and offer the path to check. | Must | Read grants are invisible to the app [1][2][3]; asserting denial is a false statement about the person's privacy. | String audit: no user-facing string containing "denied", "refused" or "blocked" in a HealthKit read context. Induce a full denial in a test build; confirm every surface uses the dual-cause wording. |
| UX-02 | First run must not require a network destination. A zero-configuration local-file destination must be offered and selectable. | Must | Persona P4 has no server; a mandatory endpoint gate loses them at screen two. Also gives every persona proof-of-life before entrusting a credential. | Complete onboarding to a successful export on a device with networking disabled. |
| UX-03 | The HealthKit permission-priming screen must present exactly one in-content button, titled `Continue` or `Next`, with no cancel/close/skip control in the content area. | Must | HIG requirement for pre-alert screens [14]; non-compliance risks App Review rejection. | Design review against HIG [14] + App Review submission outcome. |
| UX-04 | Priming must, before the system sheet, name the categories being requested and state that the app will not be able to see which types were turned off. | Must | Sets an accurate expectation that prevents the "why is my data missing" support spiral. | Copy review; comprehension test with 5 participants — ≥ 4 correctly answer "can the app tell what you turned off?" |
| UX-05 | After authorisation the app must run a coverage check and report each selected type as exactly one of: data available (with sample count and latest date), limited to a window (with the earliest authorised date), or nothing returned. | Must | The only honest rendering of what we can know [1]. | Test device with a known mix: full-access types, a limited-window type, and empty types. All three classified correctly. |
| UX-06 | Coverage must be re-probed on every foreground launch and before every export, and a drop from data-available to nothing-returned for a previously populated type must raise a `Partial` state and an attention row. | Must | Revocation produces no callback [1]; periodic probing is the only detection mechanism. | Revoke a type in Health mid-session; confirm detection on next foreground and next export. |
| UX-07 | On a device where `isHealthDataAvailable()` is false, the app must show a single terminal explanatory screen (with Mac companion options on macOS) and never a spinner, retry loop or empty dashboard. | Must | Mac and older iPads cannot read HealthKit [4][5]. | Launch on macOS 26 and on an iPadOS 16 device/simulator. |

### Destinations and credentials

| ID | Requirement | Priority | Rationale | How we verify |
|---|---|---|---|---|
| UX-08 | A destination cannot be saved in an enabled state until a connection test has passed. A failed test may only be saved as `Saved & paused`, with the reason displayed. | Must | Prevents the "configured but never worked" class entirely. | Attempt to enable a destination with a bad token; confirm enabling is impossible and the paused reason is shown. |
| UX-09 | The connection test must exercise the real protocol, real path, real credential and a real minimal payload, and must report per named step (`Resolve` / `TLS` / `Authenticate` / `Send` / `Confirm`). | Must | A reachability-only test that passes while delivery fails is worse than none — the incumbent's MQTT bug [30]. | For each of 15 induced failure conditions, the correct step is reported as the failure point. |
| UX-10 | Where a protocol cannot confirm delivery (e.g. MQTT QoS 0), the outcome must be reported as `Sent, unconfirmed` and never as success, with an action to enable a confirmable mode. | Must | Directly targets the incumbent's most damaging bug [30]. | Publish to a broker with QoS 0 and no subscriber; confirm the state is `Sent, unconfirmed`. Repeat with a deliberately bogus broker host. |
| UX-11 | URL and secret fields must disable autocorrection, autocapitalisation and smart punctuation; must strip leading/trailing whitespace with a visible note; and must display live parse-back of URL components. | Must | Smart-quote and whitespace corruption is a top invisible cause of 401s. | Paste a token containing a leading space and a URL with a smart quote; confirm both are corrected/flagged before save. |
| UX-12 | Stored secrets must render only as a mask plus a non-reversible descriptor (length, apparent type, date added), must never appear in lists, history, payload previews, diagnostics or traces, and `Reveal` (if provided) must require local authentication and auto-hide within 15 s. | Must | Secret hygiene at the interaction layer; hard constraints owned by the security engineer. | Search a `Copy diagnostics` output and an exported trace for the secret string: zero matches. Screen-by-screen audit. |

### Metric selection

| ID | Requirement | Priority | Rationale | How we verify |
|---|---|---|---|---|
| UX-13 | The metric picker must offer an "only types with data on this device" filter, enabled by default. | Must | The single largest reduction of the 150-metric problem. | On a device with data for 44 types, the default picker view shows 44 rows, not 152. |
| UX-14 | First-run default selection must be the curated **Core Daily** set (~24 types), not all types and not none. | Must | Argued in [Solving metric selection at scale](#solving-metric-selection-at-scale): "all" is a data-minimisation and comprehension failure; "none" guarantees an empty first export. | Fresh install: selection count is Core Daily, and the first export returns > 0 records on a device with typical Health data. |
| UX-15 | No shipped preset may include a sensitive-class type (sexual activity, pregnancy/lactation/contraceptive, cycle, mental wellbeing/State of Mind, alcohol/substance, clinical records, symptoms). These require individual selection with a confirmation naming the destination. | Must | A "select all" that publishes a pregnancy record to a shared MQTT broker is a safety event, not a privacy nit. | Adopt every preset in turn; assert zero sensitive types selected. Attempt bulk selection of the sensitive section; confirm it is impossible. |
| UX-16 | Committing a change to a Metric Set must show a diff (types added / removed), state how many added types will require new Health permission, and warn that removal does not retract data already sent. | Must | Makes the permission consequence visible before it happens and corrects a common false belief. | Add 12 types (9 new to HealthKit); confirm the diff reports 12/3/9 correctly and the Apple sheet then shows 9 rows. |
| UX-17 | Search must match display name, curated synonyms, and the raw HealthKit type identifier string. | Should | Personas P1 and P3 use different vocabularies for the same type. | Searching `HKQuantityTypeIdentifierStepCount`, `steps`, `weight`, `HRV`, `SpO2`, `BP` each returns the correct type. |
| UX-18 | Presets must be versioned; a new preset version must be offered as an opt-in diff and never silently applied. | Should | Silently changing what a person exports is the same violation class as silently changing units. | Ship a preset v2 in a test build; confirm existing users are offered a diff and remain on v1 until they accept. |

### Scheduling, execution and failure

| ID | Requirement | Priority | Rationale | How we verify |
|---|---|---|---|---|
| UX-19 | The app must not offer time-of-day or cron scheduling, and must not display a predicted clock time for a background attempt. Scheduling is expressed as a freshness target; predictions are expressed as windows ("within 6 hours"). | Must | HealthKit is unreadable while locked [7][8] and `BGTaskScheduler` timing is not guaranteed [33]. A clock time is a promise the platform will not keep. | UI audit: no schedule control accepts a time of day; no surface shows a future clock time for a background attempt. |
| UX-20 | The scheduling screen must state, in plain language, that iOS controls background timing and that Health data cannot be read while the iPhone is locked, and must point to Shortcuts / Control Centre for deterministic triggering. | Must | Prevents the dominant support and abandonment cause in this category [28][29][31]. | Copy review; comprehension test — ≥ 4 of 5 participants correctly answer "will this definitely run at 3 a.m.?" |
| UX-21 | Failures that the person cannot act on (device locked, no network, Low Power Mode, background not granted) must be shown as `Deferred`, labelled non-actionable, excluded from consecutive-failure escalation, and **included** in staleness. | Must | Keeps the failure badge meaningful while ensuring silence still escalates. | Induce `errorDatabaseInaccessible`; confirm state is `Deferred`, no failure count increment, staleness clock continues. |
| UX-22 | On every successful export, a local notification must be scheduled for `lastSuccess + max(4·C, 6 h)` and any prior one cancelled, per destination. | Must | Local notifications fire without app execution [33]; this is the only failure detector that survives total background starvation. It makes weeks-long silent failure structurally impossible. | Configure `C` = 1 h, complete a success, then prevent all further execution (airplane mode + force-quit). Confirm a notification arrives at ≈ 6 h. |
| UX-23 | Any progress indicator whose total is knowable must be determinate and must name the current unit of work ("Reading 24 of 41 types"). | Must | Indeterminate spinners in a multi-minute pipeline are indistinguishable from a hang. | Screen audit across Flows 2, 5; zero indeterminate indicators where a total exists. |
| UX-24 | A run in which any selected type returned no data, or any record was rejected, must be reported as `Partial`, never as success. | Must | "Success: 0 records" is the incumbent's most misleading output [31]. | Deselect access to 12 of 41 types; confirm the run reports `Partial · 29 of 41` and links to coverage. |
| UX-25 | The one-shot historical archive must be resumable, must show completed/total by month, must produce a completion manifest (types, record counts, window bounds), and may use a Live Activity ended with a 15–30 minute dismissal policy. | Should | Multi-minute, person-initiated, definite end — the only HIG-appropriate Live Activity here [15]. Persona P2 and P4's core job. | Start an 8-year archive, force-quit at 40%, relaunch: resumes from the cursor. Manifest matches destination contents. |
| UX-26 | An export interrupted by app termination must be recorded as `Interrupted` with its partial extent, and surfaced on next launch. | Should | Marcus needs to know whether to de-duplicate. | Force-quit mid-run; confirm the History entry and the next-launch notice. |

### Error content

| ID | Requirement | Priority | Rationale | How we verify |
|---|---|---|---|---|
| UX-27 | Every user-facing error must contain all five parts: ① what didn't happen (in the person's terms, naming the destination), ② plain-language cause, ③ imperative fix naming the specific thing and where, ④ 1–2 fix actions, ⑤ collapsed technical evidence with `Copy diagnostics`. | Must | Error content is the primary UI surface of a networked pipeline; a structural schema is the only way to keep it consistent as errors are added. | All 15 archetypes induced in a test harness; each renders all five parts. |
| UX-28 | No user-facing error may contain a raw `NSError` description, a bare numeric code as its title, or the strings "Something went wrong", "Unknown error", or an unqualified "Please try again". | Must | These sentences shift the diagnostic burden to the person while withholding the information they need. | Automated string scan of the error catalogue; manual review of all 15 archetypes. |
| UX-29 | Where the fix is a setting the app owns (export window, QoS, cadence, credential), the error must offer it as a direct action. | Must | Turns diagnosis into a single tap; the 413 and QoS 0 cases are the exemplars. | 413, 429 and QoS-0 errors each expose the corresponding in-app fix button and applying it resolves the condition. |
| UX-30 | Errors caused by the destination's own health (5xx, timeouts) must explicitly state that the person's configuration appears correct. | Should | Prevents hours spent re-checking correct settings — a specific, common, avoidable waste. | Copy review of the 5xx and timeout archetypes. |
| UX-31 | `Copy diagnostics` must be secret-free by construction and must include trace ID, build hash and source commit. | Must | Makes a GitHub issue actionable without leaking a token. | Grep the output for every stored secret: zero matches. Confirm commit hash present. |
| UX-32 | From a failure notification or the Status screen, the person must reach the error's ① ② ③ ④ within two taps. | Must | The measurable form of "failure is legible". | Timed task with 5 participants from each persona group; all reach the fix screen in ≤ 2 taps. |

### Status, notifications and surfaces

| ID | Requirement | Priority | Rationale | How we verify |
|---|---|---|---|---|
| UX-33 | A `Stale` state must be derived from time-since-last-**success** alone and must escalate to notification at the overdue threshold **even when no error has been recorded**. | Must | Closes the incumbent's defining blind spot [29][31]. | Simulate a destination that neither succeeds nor errors; confirm `Stale` at max(2·C, 90 min) and notification at max(4·C, 6 h). |
| UX-34 | Status, destination list, History, widget, watch and notifications must render the same state machine; no two surfaces may show contradictory states for one destination. | Must | Contradiction destroys the credibility of the whole status system at a stroke. | Cycle a destination through all twelve states; screenshot all six surfaces at each; zero disagreements. |
| UX-35 | Notification permission must be requested with `.provisional` at first destination setup, never as a day-one prompt, and full authorisation requested only in context after a real failure. | Must | Provisional grants immediately and quietly [18]; nobody can evaluate failure alerts before seeing one. Also avoids the trap where a denied full prompt kills provisional too [18]. | Fresh install: no notification prompt appears; a quiet notification with Keep/Turn-off arrives on first failure. |
| UX-36 | Failure notifications must be limited to one per destination per 24 hours, thread-collapsed per destination, and must never contain a health value. Success notifications must not exist. | Must | Notification fatigue is how status systems die; Lock Screen and Watch mirroring make values a disclosure. | Induce 10 failures in an hour: exactly 1 notification. String audit for value interpolation. |
| UX-37 | A status widget must be provided for iPhone, iPad and watchOS Smart Stack, must convey state without colour, and must contain no health values. | Should | Persistent, consent-free surface; the widget is the durable status display (Live Activities cannot be [15]). Also arrives on Mac free as a remote widget [17][27]. | Render every state in `fullColor`, `accented` and `vibrant` modes [16]; all distinguishable in greyscale. String audit for values. |
| UX-38 | An `Export now` Control Centre control and App Intents for `Export now`, `Export type/window` and `Get last export status` must be provided, with typed, distinguishable failures. | Should | The only honest route to deterministic timing; the incumbent's intent currently fails opaquely [32]. | A Shortcut branches correctly on success, `Partial` and each of three failure classes. |
| UX-39 | The Apple Watch app must be limited to status display, `Export now`, and forwarded failure notifications. No configuration, credential entry, metric selection or history browsing. | Should | HIG: watch experiences are focused and glanceable [35]; watch background budget is ~4 updates/hour with an active complication [9]. | Feature audit of the watch target. |
| UX-40 | History must default to a problems-first filter and must record, per run: outcome, trigger, window bounds, per-type record counts, byte size, duration, per-step timings, error object, and a redacted-revealable exact payload. | Must | Reverse-chronological success lists hide the only interesting row. The payload is both the trust artefact and the debugging tool. | Field-by-field inspection of a run detail; confirm default filter on fresh install. |

### Accessibility, trust and deletion

| ID | Requirement | Priority | Rationale | How we verify |
|---|---|---|---|---|
| UX-41 | All twelve statuses must be distinguishable by SF Symbol shape and text label with hue removed, and must meet 3:1 non-text contrast on every surface including widget `vibrant` mode. | Must | WCAG 2.2 SC 1.4.1 and 1.4.11 [22][24]; status is the product's core information. | Greyscale + three colour-blindness simulations across all surfaces; contrast measured on composited colours in Clear and Tinted appearances [34]. |
| UX-42 | Every screen in Flows 1–8 must be fully usable at Dynamic Type AX5 with Bold Text and Display Zoom enabled: no clipping, overlap, horizontal scrolling or truncated state labels. | Must | WCAG 2.2 SC 1.4.4 [22]; Apple Dynamic Type guidance [25]. | Screenshot matrix: 8 flows × {default, AX3, AX5} × {Bold on/off}. Zero defects. |
| UX-43 | Flows 1, 2, 5 and 7 must be completable end-to-end with VoiceOver and the screen curtain on. | Must | The composite test that subsumes label-level checks. | Recorded runs by a VoiceOver-proficient tester; all four flows completed unaided. |
| UX-44 | Display units must follow the Health app preference via `preferredUnits(for:)` and `HKUserPreferencesDidChange`; export units must be configured separately, default to canonical units, be emitted explicitly with every value, and must not change when the Health preference changes. | Must | Display must match the person's own app; the wire format must not silently break downstream dashboards [12][13]. | Toggle kg↔lb in Health: display changes immediately, exported payload unit and values are byte-identical. |
| UX-45 | A data-flow explainer rendered from the person's actual configuration must be shown in onboarding and permanently reachable from Settings, naming every destination host, protocol and credential type. | Must | Transparency shown, not asserted — the foundation of the trust claim. | Configure three destinations; confirm all three appear with correct host, protocol and credential type. |
| UX-46 | Settings must expose "Delete everything" within two taps, itemised with counts, and its confirmation must state that we cannot revoke our own Health access and cannot delete data already received — listing each destination with the date range it received. | Must | The statements only a non-manipulative product volunteers; also genuinely actionable. | Tap-count test; confirm all three destinations and their ranges are listed correctly. |
| UX-47 | Diagnostics and OpenTelemetry export must be off by default, opt-in, listed as a destination in the data-flow explainer, must never carry sample values, and must show a live preview of a real trace before enabling. | Must | The UX resolution of the brief's flagged observability/privacy tension. | Enable tracing, capture the trace: contains type identifiers, counts and durations; contains zero health values and zero sensitive-type names. |
| UX-48 | Settings must display the version, exact source commit hash and a link to it. | Should | "Auditable open source" is meaningless if the binary cannot be mapped to source. | Compare displayed hash against the build's git SHA. |
| UX-49 | A network activity ledger listing every host contacted, with counts and first/last seen, must be available, and must state that it is self-reported. | Should | Corroborates the local-only claim; the honesty caveat prevents it from becoming a false guarantee. | Contact three hosts; ledger lists exactly three plus the caveat text. |
| UX-50 | Statistics and charts of health data are out of scope for v1, and the omission must be stated in the README rather than left as a gap. | Won't (v1) | Doubles the design surface, duplicates Apple Health and Grafana, and competes for the effort that makes failure legible. | README contains the explicit non-goal. |

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| **Background execution is so unreliable that the app is functionally manual-only for many users, and we get reviewed as broken.** | High | High | Ship the watchdog (UX-22) so silence is always surfaced; state the constraint on the scheduling screen (UX-20); make Shortcuts and the Control Centre control first-class (UX-38); make foreground-launch export instant and automatic so opening the app always catches up. Measure background grant rate in opt-in diagnostics and publish it. |
| **A person denies most HealthKit types, we cannot tell, and they conclude the app is broken.** | High | High | Coverage check with three honest states (UX-05); dual-cause copy everywhere (UX-01); `Partial` rather than success (UX-24); periodic re-probe (UX-06); priming that sets the expectation up front (UX-04). |
| **Credential entry attrition: people abandon during destination setup.** | High | Medium | Local-file destination first so nobody has to configure a network destination to succeed (UX-02); parse-back and input hygiene (UX-11); test-before-save so failure surfaces at the moment of entry, not silently at 3 a.m. (UX-08); QR and file import (Should). Measure completion rate from onboarding start to first successful export. |
| **TLS trust failures make us unusable for a large share of self-hosters on day one.** | High | Medium | Certificate import with fingerprint confirmation, host-scoped (recommended option (b)); error copy that names Let's Encrypt first; explicit refusal of a global "allow insecure" toggle. Needs the security engineer's ruling (Q7). |
| **"Mac app" expectation collapse** — the brief promises first-class macOS and the platform cannot deliver it. | Certain | Medium | Restate the Mac role as companion (config author / diagnostics viewer / local receiver) in Stage 1, not Stage 3; set the priority to Should; be explicit in the README. Failing to do this in Stage 1 means discovering it in Stage 3 with a Mac target already scaffolded. |
| **Status indicators become noise and get ignored.** | Medium | High | Strict separation of `Deferred` (non-actionable) from `Failing` (actionable) (UX-21); one failure notification per destination per 24 h (UX-36); no success notifications; attention row present only when something is wrong. |
| **A sensitive type is exported without deliberate consent** (via a preset, a bulk action, or a preset upgrade). | Medium | Very high | Sensitive class excluded from every preset and from bulk selection (UX-15); individual confirmation naming the destination; preset upgrades are opt-in diffs (UX-18); widgets and notifications never carry values (UX-36, UX-37). |
| **Silent unit or schema drift corrupts a user's historical dataset.** | Medium | High | Export units decoupled from display and from Health preferences (UX-44); units emitted per value; schema version in payload; unit changes are diffed and warned. |
| **App Review friction** — health data to third-party destinations, iCloud/PHI (5.1.3(ii)), pre-permission screen compliance. | Medium | High | HIG-compliant priming (UX-03); no PHI in iCloud anywhere in the design; per-destination explicit consent with plain-language disclosure; purpose strings written as active, specific sentences [14]. Needs a legal/review read (Q4). |
| **Accessibility is deferred to Stage 3 and becomes a retrofit.** | Medium | Medium | Accessibility requirements are in the Stage 1 requirements table with acceptance criteria (UX-41…UX-43), so they are gate conditions rather than backlog. Screenshot matrix and VoiceOver runs belong in the Stage 4 QA plan explicitly. |
| **Liquid Glass legibility** — status text over translucent surfaces at low contrast. | Medium | Medium | Glass confined to the navigation layer per current HIG [20][21]; all status and error content on the opaque content layer; contrast measured on composited colours in both Clear and Tinted appearances and with Reduce Transparency on [34]. |
| **Scope creep into charts/analysis**, at the cost of the failure-legibility work that is our reason to exist. | Medium | Medium | Explicit "Won't" with a stated rationale (UX-50), recorded in Stage 1 so it must be formally overturned rather than quietly absorbed. |

---

## Hard constraints that limit the product

Stated loudly, per the brief's rules of engagement. Each of these invalidates something a
reasonable person would otherwise expect to build.

| ID | Constraint | What it invalidates | Design response |
|---|---|---|---|
| **C1** | HealthKit read authorisation is invisible to the app. Denial is indistinguishable from absence of data. There is no revocation callback. The only positively detectable state is a limited historical window, via `getEarliestAuthorizedSampleDate(for:)`. [1][2][3] | Any in-app permission manager. Any "3 of 40 types denied" summary. Any accurate "you need to enable X" prompt. Any reliable distinction between "you have no blood pressure data" and "you denied blood pressure". | Three-state coverage model; dual-cause copy; periodic re-probe; `Partial` as a first-class outcome. UX-01, UX-05, UX-06, UX-24. |
| **C2** | The HealthKit store is in Data Protection class *Protected Unless Open*. Access is relinquished 10 minutes after the device locks and returns only on unlock. Reads while locked fail with `errorDatabaseInaccessible`. [7][8] | **Time-of-day scheduling.** "Export nightly at 03:00" cannot work — the store will be encrypted. Also invalidates any promise of a bounded export latency. | Replace cron with freshness targets; state the constraint on the schedule screen; classify lock failures as non-actionable `Deferred`. UX-19, UX-20, UX-21. |
| **C3** | `BGTaskScheduler` is opportunistic: `earliestBeginDate` is a lower bound the system may ignore entirely, and Apple's own guidance is that some apps get no background time at all. `HKUpdateFrequency` is a maximum, not a schedule; `stepCount` is capped hourly on iOS; three unanswered observer completions and HealthKit **stops** background delivery permanently. Background App Refresh off or Low Power Mode stops everything. [9][10][33] | Any reliability guarantee. Any "exports every 15 minutes" claim. Any failure detector that depends on our own code running. | Promise legibility, not reliability. Watchdog via local notification. Foreground-launch catch-up. Shortcuts for determinism. UX-22, UX-38. |
| **C4** | **macOS cannot read or write HealthKit data.** `isHealthDataAvailable()` returns `false`; confirmed by Apple DTS in September 2025. [4][5] | The premise's "first-class support across iOS / iPadOS / macOS / watchOS" for the core function. A Mac exporter. A Mac app that displays the person's health data from HealthKit. | Mac is a companion: config author, diagnostics viewer, local receiver. Priority Should. Stated in the README. See [Platform split](#platform-split). |
| **C5** | App Store guideline 5.1.3(ii): apps "may not store personal health information in iCloud". [19] | iCloud-mediated data sync to a Mac companion (the incumbent's mechanism [28]). Any iCloud-backed cache of samples. Possibly complicates iCloud Drive as an export destination. | Config may sync via iCloud; health data may not. Mac receives data over the local network or by explicit file transfer. Needs a review read (Q4). |
| **C6** | HIG: a custom screen preceding a system permission alert must have exactly one button, titled `Continue`/`Next`, and must not offer a way to leave without seeing the alert. [14] | The conventional "Enable Health Access / Not Now" priming pair. Also prohibits any custom screen resembling an alert, or annotating the screen behind one. | Priming as a deliberately navigated onboarding step with a single `Continue`; escape via the navigation bar. UX-03, and Q3 for App Review confirmation. |
| **C7** | watchOS background budget: roughly four updates or refresh tasks per hour, **and only while the app has a complication on the active watch face**. Most types are capped at hourly on watchOS. [9] | An independently reliable Apple Watch exporter. Any watch-driven schedule. | Watch is status + one action + notifications. UX-39. |
| **C8** | We cannot revoke our own HealthKit access programmatically, and we obviously cannot delete data a destination has already received. | Any "delete all my data everywhere" promise. Any in-app permission-off switch. | Flow 8 states both limits explicitly, with per-destination date ranges and the exact Health/Settings path. UX-46. |
| **C9** | Live Activities are capped at 8 hours active plus ~4 hours Lock Screen residency, and HIG restricts them to tasks with a defined beginning and end. [15] | A Live Activity as a persistent export-status display. | The widget is the persistent surface; a Live Activity is used only for the one-shot archive. UX-25, UX-37. |
| **C10** | Notification authorisation can be denied or later revoked, and provisional authorisation is destroyed if a subsequent full request is denied. [18] | Notifications as the sole failure surface. Any speculative full-authorisation prompt. | Four redundant surfaces for every escalated state; provisional first, full only in context after a real failure. UX-35, UX-34. |

### Features in the premise I do not believe can be made usable as stated

| Premise feature | Verdict | Proposed alternative |
|---|---|---|
| **"150+ metrics" as a selectable list** | Unusable as a flat list; usable once reframed | Reusable **Metric Sets** + versioned presets + an "only types with data" filter that collapses ~152 rows to 30–60 + identifier-aware search + diff-before-commit. The person makes one decision, not 150. |
| **Scheduled/automated exports at chosen times** | Not achievable — C2 + C3 | **Freshness targets** ("within about 6 hours") plus an explicit statement of who controls timing, plus Shortcuts/Control Centre for determinism, plus the watchdog so that failure to meet the target is always surfaced. |
| **First-class macOS app** | Not achievable for the core function — C4 | **Mac companion**: config author, diagnostics viewer, local network receiver. Genuinely useful, honestly described, priority Should. |
| **Mac companion for viewing/analysis of health data** (as the incumbent does, via iCloud) | Blocked by C4 + C5 | Local-network transfer to a Mac receiver, or the person's own destination. And v1 does not do analysis at all (UX-50). |
| **Statistics charts and analysis** | Achievable but wrong | Explicit non-goal for v1. Our users' charts live in Grafana and Apple Health already. |
| **A built-in TCP server for direct reads** (incumbent feature) | Achievable but a UX and security liability | Not mine to rule on, but from a UX standpoint: an always-listening server on a health-data device cannot be explained safely in one screen, and "is it exposed?" becomes a status the person must monitor. Recommend deferring past v1 and flagging to the security engineer. |

---

## Open questions for the PM

| # | Question | Why it needs you, and what I'd do absent a decision |
|---|---|---|
| **Q1** | **Do we accept restating "first-class macOS" as "first-class Mac companion" in the PRD?** | This is a premise change driven by C4 [4][5]. It has to be settled in Stage 1 — discovering it in Stage 3 means a scaffolded Mac target with nothing to put in it. Absent a decision I will specify the companion roles and mark them Should. |
| **Q2** | **Do we accept freshness targets in place of time-of-day scheduling, knowing it will read as a feature gap against the incumbent's screenshots?** | The incumbent shows time pickers; we would not. The trade is honest behaviour versus apparent parity. My recommendation is unambiguous — the time picker is the root of the incumbent's bug reports [29][31] — but it is a positioning call, not a design call. |
| **Q3** | **Can someone confirm with App Review that a nav-bar back button on a permission-priming screen is compliant with the one-button rule?** | HIG says no additional actions and no way to leave without seeing the alert [14]. If a back button counts as an additional action, priming must be a non-dismissible modal step, which changes Flow 1 materially. Needs an answer before Stage 2. |
| **Q4** | **Who owns the App Review risk assessment for exporting HealthKit data to user-specified third-party endpoints?** | Apple: an app "must not disclose any information gained through HealthKit to a third party without express permission… and only… if they also provide a health or fitness service to the user" [6], plus 5.1.3(i)'s constraints [19]. The incumbent evidently passes review, so this is navigable — but "the destination is the person's own server" and "the destination is Dropbox" are different arguments and I need to know which we are making, because it changes the consent copy I write. |
| **Q5** | **Do we ship the researcher/clinician-adjacent use case as a non-goal?** | I have excluded it (see [Anti-personas](#anti-personas-explicit-non-targets)) because it implies completeness guarantees and consent/ethics posture we cannot support in v1. If you want it, it is a materially larger product and I need to redo personas and Flow 8. |
| **Q6** | **Is there a supportable deep link into Health → Sharing → Apps, or into Settings → Privacy & Security → Health?** | Flow 1 and Flow 8 both need to send people there. `x-apple-health://` is undocumented and `App-prefs:` sub-paths are private. My design assumes **text instructions are the guaranteed path** and any deep link is an enhancement — but if a supported link exists, several flows get materially better. Needs an engineering answer. |
| **Q7** | **Certificate policy: refuse untrusted certificates, or support user-pinned certificates?** | The security engineer owns the ruling; I need it to write Flow 2's copy. My recommendation is host-scoped pinning with fingerprint confirmation, plus error copy that names a publicly trusted certificate as the better fix. A blanket "allow insecure" toggle I will not design. |
| **Q8** | **Is the sensitive-type class definition acceptable?** (sexual activity, pregnancy/lactation/contraceptive, cycle, mental wellbeing/State of Mind, alcohol/substance, clinical records, symptoms — excluded from all presets and from bulk selection.) | This makes the "export everything" job slightly harder for P2 and P4 on purpose. I believe the trade is right, but it is a product-values decision, and I would rather you own it than discover it in a review. |
| **Q9** | **Is the built-in TCP server in or out?** | It is in the incumbent's feature list and therefore in the premise's shadow. From a UX standpoint an always-listening server on a health-data device introduces a permanent "is this exposed?" status the person must monitor, and I do not have a good one-screen explanation for it. Recommend out for v1; needs your and the security engineer's agreement. |
| **Q10** | **Is "no charts in v1" (UX-50) acceptable, and will you defend it?** | It is the most likely requirement to be quietly re-added, and re-adding it costs exactly the effort that makes failure legible. If it goes back in, I want a named trade — which of UX-22, UX-40 or UX-45 is coming out. |

---

## Sources

1. Apple — *Authorizing access to health data* (HealthKit). https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data
2. Apple — `HKHealthStore.authorizationStatus(for:)`. https://developer.apple.com/documentation/healthkit/hkhealthstore/authorizationstatus(for:)
3. Apple — `HKAuthorizationStatus`. https://developer.apple.com/documentation/healthkit/hkauthorizationstatus
4. Apple — `HKHealthStore.isHealthDataAvailable()`. https://developer.apple.com/documentation/healthkit/hkhealthstore/ishealthdataavailable()
5. Apple Developer Forums — *HealthKit on macOS* (Apple DTS: "your app can't read or write HealthKit data on macOS as of today. `isHealthDataAvailable()` will return you `false`"), thread 798780, September 2025. https://developer.apple.com/forums/thread/798780
6. Apple — *Protecting user privacy* (HealthKit). https://developer.apple.com/documentation/healthkit/protecting-user-privacy
7. Apple — *Protecting access to user's health data*, Apple Platform Security ("Data Protection class Protected Unless Open. Access to the data is relinquished 10 minutes after the device locks"). https://support.apple.com/guide/security/protecting-access-to-users-health-data-sec88be9900f/web
8. Apple — `HKError.Code.errorDatabaseInaccessible`. https://developer.apple.com/documentation/healthkit/hkerror/errordatabaseinaccessible
9. Apple — `enableBackgroundDelivery(for:frequency:withCompletion:)` (frequency caps; watchOS four-updates-per-hour budget). https://developer.apple.com/documentation/healthkit/hkhealthstore/enablebackgrounddelivery(for:frequency:withcompletion:)
10. Apple — `HKObserverQueryCompletionHandler` ("If your app fails to respond three times, HealthKit assumes that your app cannot receive data, and stops sending you background updates"). https://developer.apple.com/documentation/healthkit/hkobserverquerycompletionhandler
11. Apple — *Configuring HealthKit access* (purpose strings; revocation via Settings or Health). https://developer.apple.com/documentation/xcode/configuring-healthkit-access
12. Apple — `preferredUnits(for:completion:)`. https://developer.apple.com/documentation/healthkit/hkhealthstore/preferredunits(for:completion:)
13. Apple — `HKUserPreferencesDidChange`. https://developer.apple.com/documentation/foundation/nsnotification/name-swift.struct/hkuserpreferencesdidchange
14. Apple — *Human Interface Guidelines: Privacy* (contextual permission requests; pre-alert screens must include only one button titled "Continue"/"Next" and no way to leave without seeing the alert; purpose-string copy guidance). https://developer.apple.com/design/human-interface-guidelines/privacy
15. Apple — *Human Interface Guidelines: Live Activities* (defined beginning and end, ≤ 8 hours, end immediately, 15–30 minute custom dismissal; updated December 2025). https://developer.apple.com/design/human-interface-guidelines/live-activities
16. Apple — *Human Interface Guidelines: Widgets* (families and placements per platform; `fullColor` / `accented` / `vibrant` rendering modes; watchOS Smart Stack; updated December 2025). https://developer.apple.com/design/human-interface-guidelines/widgets
17. Apple — *Developing a WidgetKit strategy* (controls in Control Center, Lock Screen, Action button; per-platform capability matrix; iOS widgets on Mac). https://developer.apple.com/documentation/widgetkit/developing-a-widgetkit-strategy
18. Apple — *Asking permission to use notifications* (provisional authorisation: granted automatically, delivered quietly to Notification Center with keep/turn-off buttons). https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications
19. Apple — *App Store Review Guidelines* §5.1.3 Health and Health Research (no advertising/data-mining use; third-party disclosure limits; "may not store personal health information in iCloud"). https://developer.apple.com/app-store/review/guidelines/#5.1.3
20. Apple — *Applying Liquid Glass to custom views* (`glassEffect`, `GlassEffectContainer`, morphing, transitions). https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views
21. Apple Newsroom — *Apple introduces a delightful and elegant new software design* (Liquid Glass across iOS 26, iPadOS 26, macOS Tahoe 26, watchOS 26). https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/
22. W3C — *Web Content Accessibility Guidelines (WCAG) 2.2* (SC 1.4.1 Use of Color, Level A; SC 1.4.3 Contrast Minimum, AA; SC 1.4.4 Resize Text, AA; SC 1.4.11 Non-text Contrast, AA). https://www.w3.org/TR/WCAG22/
23. W3C WAI — *Understanding Success Criterion 1.4.3: Contrast (Minimum)* (4.5:1; 3:1 for large text). https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum
24. W3C WAI — *How to Meet WCAG (Quick Reference)*, colour and contrast techniques for 1.4.1 and 1.4.11. https://www.w3.org/WAI/WCAG22/quickref/?tags=color%2Ccontrast&versions=2.2
25. Apple — *Get started with Dynamic Type*, WWDC24 session 10074 (7 default sizes plus 5 accessibility sizes; Large Content Viewer). https://developer.apple.com/videos/play/wwdc2024/10074/
26. Apple — *Design intuitive search experiences*, WWDC26 session 292 (bottom-toolbar search placement for reachability; search tab guidance). https://developer.apple.com/videos/play/wwdc2026/292/
27. Apple — *WidgetKit foundations*, WWDC26 session 277 (iOS widgets appear on macOS as remote widgets). https://developer.apple.com/videos/play/wwdc2026/277/
28. HealthyApps — *Sync to Mac*, Health Auto Export help centre ("Apps are not allowed to access health data while iPhone is locked… This is a limitation imposed by Apple which cannot be circumvented"; background-refresh and Low Power Mode caveats; iCloud-mediated Mac sync). https://help.healthyapps.dev/en/health-auto-export/sync-to-mac
29. Lybron/health-auto-export issue #21 — *Automatic export function does not work automatically* (activity log shows "Succeeded" but no data arrives). https://github.com/Lybron/health-auto-export/issues/21
30. Lybron/health-auto-export issue #35 — *MQTT not working?* ("the response still indicates 'Data published to broker'… Even if the MQTT server address is obviously bogus"). https://github.com/Lybron/health-auto-export/issues/35
31. Lybron/health-auto-export issue #22 — *Empty Data in Automation Export* (empty payloads reported as successful). https://github.com/Lybron/health-auto-export/issues/22
32. Lybron/health-auto-export issue #49 — *"Export Health Metrics" Shortcuts action fails with "Something went wrong. Please try again."* (open as of February 2026). https://github.com/Lybron/health-auto-export/issues/49
33. M. Bulan — *Don't rely on BGAppRefreshTask for your app's business logic*, quoting Apple DTS ("there are common scenarios where it won't grant you any background execution time at all"); and *Running iOS Background Tasks Reliably* on `earliestBeginDate` as a lower bound and local notifications firing without app execution. https://mertbulan.com/dont-rely-on-bgapprefreshtask-for-your-apps-business-logic/ · https://calcopilot.app/blog/posts/running-ios-background-tasks-reliably-part1/
34. Cult of Mac / iDownloadBlog — Liquid Glass legibility mitigations available to users: Settings → Display & Brightness → Liquid Glass (Clear/Tinted), Accessibility → Reduce Transparency, Increase Contrast, Reduce Motion, Reduce Brightness (26.4+). https://www.cultofmac.com/how-to/turn-off-liquid-glass · https://www.idownloadblog.com/2025/06/13/disable-liquid-glass-apple-devices/
35. Apple — *Meet watchOS 10* / *Design and build apps for watchOS*, WWDC23 ("Apple Watch apps should be focused and highly-specialized… optimize for glanceability and short interaction time"). https://developer.apple.com/videos/play/wwdc2023/10026/ · https://developer.apple.com/videos/play/wwdc2023/10138/
36. HealthyApps — *Health Auto Export* product page (reference product feature surface). https://www.healthyapps.dev/apps/health-auto-export/

---

### Labelled assumptions (not sourced)

- **A1.** The "Core Daily" set of ~24 types produces a non-empty first export for the large majority of users. Should be validated against real devices in Stage 4.
- **A2.** Staleness thresholds of max(2·*C*, 90 min) and overdue at max(4·*C*, 6 h) are the right defaults. Chosen to be testable, not measured; expect to tune after real-world background-grant data.
- **A3.** History retention default of 90 days or 1,000 runs, whichever is larger.
- **A4.** The sensitive-type class definition in [UX-15](#requirements-i-own) is mine, not Apple's. Needs ratification (Q8).
- **A5.** A standard navigation-bar back button on a permission-priming screen does not constitute "an additional action" under HIG [14]. Explicitly flagged for confirmation (Q3).
- **A6.** ~152 supported types is the right order of magnitude for the picker's denominator; the true number depends on which HealthKit categories we support and grows every OS release [1].
