# Interaction Design — Stage 2

**Author:** UI/UX Designer
**Stage:** 2 of 4 — System Design
**Status:** Draft for PM synthesis and adversarial review
**Date:** 2026-09-03
**Owns:** R-23, R-25, R-26, R-40, R-41, R-60 … R-69
**Inputs:** PRD v1.0 (approved), `contributions/06-ux-designer.md` (50 `UX-`), `contributions/04-security-engineer.md` (T-24, SEC-11/29/53/54/65/67/68)
**Toolchain assumed:** SwiftUI, Xcode 26.6, iOS/iPadOS 18.0 minimum (D-05), macOS 26 for the companion

> No implementation. Flows, states, information architecture, component inventory and real copy.
> Every user-facing string in this document is a proposed final string, not a placeholder.
> Strings appear in `en-GB` source form; §10 covers what localisation does to them.

---

## Executive summary

Stage 1 argued that this is a monitoring app that happens to be configurable. Stage 2 has to make
that true in an actual interface, and three things changed since Stage 1 that force real design
work rather than elaboration.

**The watchdog became the product (R-23).** It survived adversarial review intact, which means the
design job is no longer "propose a mechanism" but "build the whole failure-detection surface
around it and make it degrade honestly". I have designed it as three rungs with a named
degradation path, and I have added one property the Stage 1 sketch lacked: **every rung must be
correct without the app ever running again.** The notification is pre-scheduled with content that
cannot go stale, and the widget's timeline is generated on the assumption that no further export
will ever succeed, so its "3 days ago" ages by itself. A failure detector that needs our code to
run is not a failure detector. That principle propagates into the copy: the watchdog notification
contains **no number that would become a lie if iOS delivered it late.**

**A data browser is required (R-69), and it should not be a separate feature.** The single largest
IA decision in this document is that **the metric picker and the data browser are the same list.**
One tab, called Data, shows every HealthKit type that has data on this device, with its latest
value and timestamp, and whether it is included in an export. Browsing and choosing are the same
act. This collapses a screen, answers "do I want this type?" with the actual value instead of a
name, puts real health data one tap from launch for an App Review reviewer (RK-3), and gives the
correctness wedge its verification surface: from any sample you can reach the exact record we
exported for it, and from any exported record you can reach its source sample. §8 states five
rules that keep it a browser and names the review gate that enforces them.

**Two more surfaces exist (D-04, D-14).** MQTT and the Mac companion add two destination types,
a certificate-import flow, a device-pairing flow, and a second platform. The Mac is a *receiver*,
not a control plane, and I have designed it to look like one: it has no destination editor, no
metric picker, no credential fields for anything but its own pairing, and it does not render
health values. It has exactly four jobs — pair, write, prove it wrote, and be deleteable — plus
its own mirror of the watchdog, because a receiver that stops receiving is the same failure in a
different place.

The three highest-risk decisions I am making, stated here so they are easy to attack: unifying the
picker and the browser; treating `success_nothing_due` as a run that **resets the freshness clock**
(with a second clock for delivered records, because otherwise the watchdog cannot distinguish "no
data" from "no delivery"); and resolving Stage 1's open question Q3 by **splitting the R-63
disclosure away from the HIG pre-alert screen** so the one-button rule binds only the second of
them. §13 lists these and the rest.

---

## Information architecture

### The principle

Each surface is defined by the question it answers. If a surface cannot be described by one
question, it is two surfaces. If two surfaces answer the same question, one of them is wrong.

| Surface | The one question | Deliberately not |
|---|---|---|
| **iPhone** | Everything. This is the product and the only control plane | — |
| **iPad** | Same questions, more room for the long lists | The recommended exporter |
| **Status widget** | "When did this last work?" | Configuration, health values, anything requiring a tap to read |
| **Mac companion** | "Did the data arrive here?" | A control plane, a HealthKit reader, a second data browser |
| **Lock Screen / Smart Stack accessory** | "Is it healthy or not?" | Everything else |
| **Control Centre** | "Export now" | Enabling or disabling anything |
| **Shortcuts / App Intents** | Determinism the platform will not give us | The documented answer to "how do I schedule this?" without also stating C-02 and C-03 |

### iPhone — four tabs

Four, not five. Five tab labels truncate at accessibility text sizes, and HIG warns that an
overflow "More" tab hides content people then cannot find.[^tabbars] Settings lives in the
navigation-bar toolbar of the Status tab.

| Tab | Question | Root content | Not here |
|---|---|---|---|
| **Status** | "Is it working?" | Attention row; two freshness clocks; per-destination state cards; background-grant summary; `Export now` | Anything you configure |
| **Data** | "What's on this iPhone, and what leaves it?" | Type list with latest values (the browser **and** the picker); Sets; format and units | Charts. Anything derived |
| **Destinations** | "Where does it go?" | `Where your data goes` summary (R-41 anchor); destination list; add/test; egress ledger; data-flow explainer | Metric selection |
| **History** | "What happened?" | Problems-first run list; run detail; diagnostic bundle | Live status |

Two structural rules follow from R-41 and are load-bearing, not stylistic:

1. **The Destinations tab position and label never change.** Not by configuration, not by state,
   not by A/B, not by release. It is the second-from-right tab in every build for the life of the
   product. A person told "check the third tab" over the phone by a support volunteer or a
   domestic-violence advocate must find it there.
2. **The Data tab is the app's centre of gravity, and Status is its default.** Status is where the
   app opens, because the app's job is to be trusted passively. Data is where an App Review
   reviewer will go, so it must be the second tab, adjacent to the default, and it must show real
   health data with no configuration.

### iPhone — where the never-hideable surfaces live

R-41 names three things that can never be hidden: destinations, credentials-in-use, and the egress
ledger. They get a single screen — **`Where your data goes`** — reachable from three fixed places:
the top row of the Destinations tab, a footer link on Status, and the first row of Settings. §7
defines what "can never be hidden" means as a set of testable interface invariants.

### iPad

Same binary, same four sections. iPadOS 26 puts the tab bar at the top with an optional conversion
to a sidebar;[^tabbars] we adopt `sidebarAdaptable` so the long lists (the ~150-row type list, the
run history, the ledger) get a persistent index in the sidebar with detail alongside. Data and
History use a two-column split; Status and Destinations do not, because their content is short and
a split view would leave a large empty detail pane on first run.

iPad is not privileged and not discouraged, with one exception. If the only enabled exporter is an
iPad, Status shows a permanent (non-dismissible, non-alarming) row:

> **This iPad is your only exporter.**
> An iPad's Health data is only what this iPad recorded plus what syncs to it, and iPads spend
> more time asleep and off-charge than iPhones do. If you have an iPhone, it will be more
> complete and more current.

### Status widget — a rung, not a decoration

The PRD promoted the widget from Should to Must specifically to be R-23's fallback (§5.1). That
changes its design constraints from "nice glanceable summary" to "must be correct when nothing
else in the system is running".

Families: `systemSmall` and `systemMedium` (iPhone and iPad Home Screen, Today View; Mac desktop
and Notification Center as remote widgets), plus `accessoryRectangular` and `accessoryCircular`
(iPhone/iPad Lock Screen). On iPhone and iPad Home Screen, people choose light, dark, clear or
tinted appearances; clear and tinted desaturate the widget and its content, and Lock Screen
widgets render in the `vibrant` mode with no tint colour at all.[^widgets] So the widget cannot
carry a colour-coded state under any circumstances, which is convenient, because R-64 forbids it
anyway.

Content: state glyph, state word, last-success age in plain language, destination count. **No
health values, ever** — a widget is visible to anyone who glances at the device, and SEC-28
requires widget redaction on a locked device regardless.

### Mac companion — designing a receiver

The Mac cannot read HealthKit (PC-1, C-01), so there is no version of this app on macOS that is
the product. It is a destination that happens to have a screen. The design question is what a
destination's screen is *for*, and the answer is: to prove to the person standing in front of it
that data arrived, and to be removable.

| The Mac has | The Mac does not have |
|---|---|
| A pairing flow with the iPhone, and a list of paired iPhones | A destination editor for any other destination |
| A chosen output folder, and a `Reveal in Finder` | A metric picker |
| A receipt list: per transfer — when, from which iPhone, which types, how many records, window bounds, bytes, filename | A rendering of health values (see below) |
| Its own freshness clock and its own quiet-alarm | An export trigger. It cannot make the iPhone do anything |
| `Delete everything received` and uninstall guidance including manual Keychain removal | A settings surface that can hide the receipt list |
| A menu bar extra with the state glyph and last-received age | A Dock-only presence with no menu bar item |

**Decision: the Mac does not render health values.** It could — it holds the files. I am ruling it
out for three reasons. It would be a second data browser to design, localise, make accessible and
keep out of dashboard territory, on a platform with no HealthKit source of truth to verify
against, which makes it strictly worse than the iPhone's browser at the one job the browser has.
It would put health values on a desktop screen in an office. And it dilutes the definitional
clarity that keeps this app shippable: *the Mac is a place data goes.* The receipt list carries
manifest-level facts — types, counts, window bounds, sizes, filenames — which is what you need to
answer "did it arrive?", and `Reveal in Finder` hands the actual data to the tools the person
already uses. This is an open question for the PM (§13, Q7) because it is the kind of scope call
that gets quietly reversed in Stage 3.

**The Mac's own watchdog.** A receiver that stops receiving looks exactly like a receiver with
nothing to receive. The Mac keeps its own last-received clock, shows it in the menu bar extra, and
posts its own local notification at the same threshold *N* the iPhone uses (transmitted at pairing
time and refreshed on every transfer). This is deliberate redundancy: if the iPhone is the thing
that has failed, the iPhone's watchdog may also have failed, and a second device that has not
heard from it in a day is an independent witness. It is the only place in the product where we get
a genuinely out-of-band signal, and it costs almost nothing.

### What is out of scope for v1, restated so Stage 3 does not reintroduce it

watchOS app and complication (PRD §5.1 — out); Live Activities except the one-shot historical
archive, which is the only thing in the product with the defined beginning and end that HIG
requires;[^liveactivities] any chart, sparkline, gauge or ring anywhere on any surface; any second data browser;
alternate app icons (§7, invariant 4); any surface that displays a health value outside the app on
the iPhone.

---

## Navigation model

**Structure.** `TabView` at the root on iPhone and iPad. Each tab owns a navigation stack. The tab
bar is a Liquid Glass navigation surface and may minimise on scroll; all status, error, sample and
payload content sits on the **opaque content layer**. Glass is reserved for the navigation layer
and is never stacked on glass.[^glass][^materials] This is not decoration policy — status text on a
translucent surface over arbitrary wallpaper is the single most likely way we fail WCAG 1.4.3 in
the wild.

**Modality.** Sheets are used for: adding or editing a destination, the destination test, the
config-import review, credential replacement, and the verify comparison. Everything that is a
*record of what happened* — run detail, ledger, bundle preview, receipts — is a push, never a
sheet, so it has a back button and a stable place in a stack rather than a dismissal gesture.

**Destructive flows are pushes with an alert at the end**, never a sheet, because a swipe-down
should not be the last thing between a person and an irreversible action, in either direction.

**Deep links, with tap budgets** (R-23 and UX-32 both hang on these):

| Origin | Lands on | Taps to the fix |
|---|---|---|
| Failure notification | Run detail, error object expanded to ①②③④ | 0 |
| Watchdog notification | Destination detail, with the quiet-since explanation at the top | 0 |
| Destination-change notification (R-40) | `Where your data goes`, the changed destination highlighted | 0 |
| Widget tap (healthy) | Status | 0 |
| Widget tap (attention) | The worst destination's detail | 0 |
| Status attention row | Same as above | 1 |
| Anywhere → `Where your data goes` | The R-41 screen | ≤ 2 |
| Settings → Delete everything | The scope screen | 2 |

**Foreground catch-up.** Every foreground launch immediately re-probes coverage and attempts an
export for every non-paused destination, with the Status screen showing it happening. Opening the
app must always be the thing that fixes it, because for many users on many days it is the only
execution we will get.

---

## Screen designs

Each screen is specified as purpose, states, transitions and copy. Every screen has an empty,
loading, partial-permission, stale, degraded and failed state, or an explicit statement that one
is unreachable.

### S1 — Status (default screen)

**Purpose.** Answer "is my health data actually arriving where I sent it?" without a tap, and be
the first rung of R-23.

```
┌──────────────────────────────────────────────┐
│  Tributary                              ⚙︎   │
├──────────────────────────────────────────────┤
│  ⚠  Home Assistant has been quiet for 3 days │  attention row — present only
│     Nothing has failed. Nothing has arrived. │  when ≠ all healthy
│                                     Review › │
├──────────────────────────────────────────────┤
│  Last successful check    12 minutes ago     │  ← two clocks. See below.
│                           3 Sep, 09:47       │
│  Last record delivered    3 days ago         │
│                           31 Aug, 07:12      │
├──────────────────────────────────────────────┤
│  DESTINATIONS                                │
│ ┌──────────────────────────────────────────┐ │
│ │ ⏱  Home Assistant                        │ │  glyph = shape, not colour
│ │    Quiet · no delivery for 3 days        │ │
│ │    Last delivered 31 Aug, 07:12       ›  │ │
│ │    No error has been recorded.           │ │  ← naming the absence
│ └──────────────────────────────────────────┘ │
│ ┌──────────────────────────────────────────┐ │
│ │ ✓  Archive folder (Files)                │ │
│ │    Delivered · 12 minutes ago         ›  │ │
│ │    1,204 records · next attempt within 6h│ │  a window, never a clock time
│ └──────────────────────────────────────────┘ │
│ ┌──────────────────────────────────────────┐ │
│ │ ✈  Mosquitto (MQTT)                      │ │
│ │    Sent, unconfirmed · 12 minutes ago ›  │ │
│ │    QoS 0 can't confirm delivery.         │ │
│ └──────────────────────────────────────────┘ │
├──────────────────────────────────────────────┤
│  HEALTH ACCESS                               │
│  38 of 41 selected types returned data       │  never "3 denied"
│  3 returned nothing               Review ›   │
├──────────────────────────────────────────────┤
│  BACKGROUND                                  │
│  iOS woke this app 3 times in 24 hours.      │  R-22 attribution, honestly
│  Your freshness target is about 6 hours.     │
├──────────────────────────────────────────────┤
│  Where your data goes                    ›   │  R-41 fixed anchor
├──────────────────────────────────────────────┤
│              [  Export now  ]                │
└──────────────────────────────────────────────┘
    Status      Data      Destinations   History
```

**The two clocks.** This is the most consequential small decision on the screen.
`success_nothing_due` is a real, correct run: the engine checked, the watermark said nothing was
due, nothing was sent. If that resets nothing, a person with a quiet week gets a false alarm and
learns to ignore us. If it resets everything, a destination whose credential silently stopped
accepting writes could sit at "healthy" forever. So there are two:

- **Last successful check** — advances on `success`, `success_nothing_due` and `partial`. This is
  what proves the pipeline ran end to end.
- **Last record delivered** — advances only on `success` and `partial`. This is what proves data
  moved.

R-23's watchdog is armed from **last successful check**, because that is the honest definition of
"we are still working". A long gap in *delivered* with a healthy *check* clock is a separate,
softer state (`Quiet`) that raises the attention row and is explained rather than alarmed about.
This needs PM ratification because it changes what R-23's soak test asserts (§13, Q2).

**States.**

| State | Trigger | Screen |
|---|---|---|
| Loading | Launch, before first probe | Skeleton rows with the destination names already correct (we know them); no spinner over the whole screen. Never longer than the R-76 budget |
| Empty (first run complete, never exported) | Zero runs | No clocks. One card: "No exports yet. Run one now to check your setup." + `Export now` |
| Empty (no destinations) | Zero destinations | "Nothing is set up yet." + `Add a destination` + a second, equal-weight `Save to files on this iPhone` |
| Healthy | All destinations `Healthy` | No attention row. Clocks shown. This screen should be boring |
| Partial permission | ≥1 selected type returned nothing | HEALTH ACCESS block shows the dual-cause count; no destination is marked failed on this basis alone |
| Stale / Quiet | See status model | Attention row + per-card state; `No error has been recorded.` shown verbatim |
| Degraded (no notifications, no widget) | Both escalation rungs unavailable | Permanent row, described in §6 |
| Failed | ≥1 destination `Failing` or `Blocked` | Attention row names the destination and the error title, not the count |

**Copy — attention row, by cause.** One row, whichever is worst. Never a count of problems.

- `Failing`: **"Home Assistant rejected the last 3 exports."** / "Token rejected. Review ›"
- `Blocked`: **"Home Assistant is waiting for you."** / "Its certificate changed and exports are halted. Review ›"
- `Quiet`: **"Home Assistant has been quiet for 3 days."** / "Nothing has failed. Nothing has arrived. Review ›"
- `Stale`: **"Nothing has succeeded for 26 hours."** / "iOS hasn't given this app background time. Review ›"
- `Constrained`: **"Background App Refresh is off for this app."** / "Exports will only run when you open it. Review ›"
- Coverage drop: **"Steps stopped returning data on 28 August."** / "Either the data stopped, or access was turned off in Health. Review ›"

### S2 — First run, disclosure and permission priming

**Purpose.** Get to a non-empty first export without a network destination, having told the truth
about the platform first (R-63), without violating HIG's pre-alert rule.[^privacy]

**Resolving Stage 1's Q3 by splitting the screens.** Stage 1 flagged an unresolved risk: HIG says a
custom screen shown before a system permission alert must have exactly one button, must make clear
that the button opens the alert, and must not offer any way to leave without seeing the alert.[^privacy]
Stage 1 assumed a navigation-bar back button was permissible and asked App Review to confirm. That
assumption is unnecessary. **Split the disclosure from the priming:**

- **S2.4 Platform honesty (R-63)** is an ordinary onboarding step. It has a back button, a
  `Continue`, and it is freely navigable. R-63 is satisfied: the disclosure precedes the prompt.
- **S2.5 Priming** is the pre-alert screen. It has no navigation bar, no back, no cancel, and one
  button titled `Continue`. Its only content is which types we are about to ask for and the fact
  that we will not be able to see what is turned off.

This removes an App Review dependency from the critical path and costs one screen.

**Flow.**

| Step | Content | Out |
|---|---|---|
| **S2.1 Welcome** | Two sentences and the data-flow diagram. No account, no sign-in, no upsell, no rating prompt | → S2.2 |
| **S2.2 First destination** | Two equally weighted options: **Save to files on this iPhone** (no network, recommended, gives proof of life) and **Send somewhere else**. A third, quiet: `Skip for now` | → S2.3 |
| **S2.3 What to export** | Pre-selected: **Core Daily**, ~24 types (R-61). One tap to accept, one to open the picker (S3). No sensitive-class type is present (R-66) | → S2.4 |
| **S2.4 Platform honesty** | The R-63 copy in §11. Back + `Continue` | → S2.5 |
| **S2.5 Priming** | Single `Continue`. No escape | → S2.6 |
| **S2.6 System sheet** | Apple's. Not ours | → S2.7 |
| **S2.7 Coverage check** | One-sample probe per selected type. Determinate progress: "Checking 18 of 24 types". Three-state table | → S2.8 / S2.8-partial / S2.8-empty |
| **S2.8 First export** | Runs in the foreground with visible progress. Ends on the run detail, not on a congratulation | → Status |

**S2.5 copy, verbatim** (this is the pre-alert screen; every word is constrained):

> **Next, iPhone will ask for permission**
>
> We're about to ask for read access to 24 types of health data: your activity, heart, sleep, body
> measurements and workouts. The full list is on the previous screen.
>
> Apple's permission sheet is next. Turn on whatever you're comfortable with — you can change it
> any time in Health.
>
> One thing worth knowing: **iPhone does not tell apps what you turned off.** If a type is switched
> off, it looks to us exactly like a type you have no data for. So if something is missing later,
> we will say "we got nothing, and we can't tell you why" — because that is the truth.
>
> `[ Continue ]`

**`NSHealthShareUsageDescription`:** "Reads the health types you choose so it can copy them to
destinations you set up yourself — a folder on this iPhone, your own server, or your Mac."

**S2.7 coverage table.** Three states and no fourth. The third is not an error and does not get a
warning glyph.

| State | How we know | Copy |
|---|---|---|
| Data available | ≥1 sample returned | "Steps — 4,812 samples, latest today 08:41" |
| Limited window | `getEarliestAuthorizedSampleDate(for:)` returned a date | "Heart rate — access limited to data from 1 Aug 2026 onward. Earlier data can't be exported." |
| Nothing returned | Zero samples, no limited-window date | "Blood glucose — nothing returned. Either Health has no blood glucose data, or access is off. Check in Health → Sharing → Apps." |

**Failure paths.**

| Failure | Behaviour |
|---|---|
| `isHealthDataAvailable() == false` | One terminal screen naming the platform limitation. No spinner, no retry, no empty dashboard. On Mac this screen does not exist because the Mac app never claims to read |
| `requestAuthorization` throws | Our bug (usually a missing purpose string). Build-level error with the build hash and a `File an issue` action. Never phrased as the person's fault |
| Backed out at S2.4 | Resumable and idempotent. Status shows one row: "Health access not set up yet — Set up ›". No modal on next launch, ever |
| Everything denied | Surfaces only as S2.8-empty. We never assert denial (R-60), because Apple states plainly that an app cannot determine whether read permission was granted and that denial "simply appears as if there is no data of the requested type"[^healthkit] |
| Revoked months later | Undetectable directly. Caught by the coverage re-probe on foreground launch and before every export |

**S2.8-empty copy** (the highest-signal recoverable state in the product):

> **Nothing came back**
>
> All 24 types returned no data. There are two possible reasons and we genuinely cannot tell which:
> this iPhone's Health app has no data for those types, or access to them is switched off.
>
> To check: open **Health → your profile picture → Privacy → Apps → Tributary**. Everything you
> want exported needs to be switched on there.
>
> `[ Check again ]`  `[ Choose different types ]`

### S3 — The Data tab: type list (browser and picker, unified)

**Purpose.** Show what health data exists on this device and which of it leaves. This is R-61 and
R-69 in one surface.

```
┌──────────────────────────────────────────────┐
│  Data                            Sets  Select│
│  38 types with data · 24 exported            │
├──────────────────────────────────────────────┤
│  [ ✓ Only types with data ]  ← filter, ON    │
├──────────────────────────────────────────────┤
│  ACTIVITY                                    │
│  Steps                              ↑ 3 dest │
│  8,412 count · today 09:31                   │
│  Active energy                      ↑ 3 dest │
│  486 kcal · today 09:28                      │
│  Push count                         — not    │
│  No data on this iPhone                      │
├──────────────────────────────────────────────┤
│  HEART                                       │
│  Heart rate                         ↑ 2 dest │
│  67 count/min · today 09:44                  │
│  Resting heart rate                 ↑ 2 dest │
│  54 count/min · today 04:12                  │
│  Heart rate variability             — not    │
│  38 ms · today 04:12                         │
├──────────────────────────────────────────────┤
│  ⚠ SENSITIVE — choose individually    0 of 21│
├──────────────────────────────────────────────┤
│                        ⌕ Search              │  bottom placement
└──────────────────────────────────────────────┘
```

**Two modes on one list.**

- **Browse** (default). Tapping a row pushes the type detail (S4). The trailing indicator says
  whether the type is exported and to how many destinations. This is what an App Review reviewer
  sees, and it is health data with values and timestamps on the second tab.
- **Select** (entered via `Select`). Rows gain leading multi-select controls; the toolbar gains
  section-scoped bulk actions, `Invert` and `Clear all`; there is no unscoped Select All. Exiting
  Select commits through the diff review (S3b).

**States.**

| State | Screen |
|---|---|
| Loading | Rows render immediately from the catalogue with the value line as a redacted placeholder; values fill in as probes return. Never a full-screen spinner over a list we can already draw |
| Empty (filter on, nothing has data) | "No Health data found on this iPhone. Either there isn't any yet, or access is off — [check in Health]. You can also [turn off the filter] to see all 152 supported types." |
| Empty (search) | "No type matches 'glukose'. Search matches names, common abbreviations (HRV, SpO₂, BP) and HealthKit identifiers." |
| Partial permission | Rows read "No data on this iPhone" — never "Denied". A previously-populated type that goes empty gets a persistent inline note: "Returned data until 28 Aug, then stopped." |
| Filter off | 152 rows, sectioned by Apple Health's own categories, with `no data` subtitles. The row count is shown so the person understands what they turned on |
| Sensitive section | Collapsed, count-only, never bulk-selectable, individual opt-in with a confirmation naming the destination (R-66) |

**Search.** Bottom toolbar placement — a 152-row list is exactly where thumb reachability matters,
and the field animates up over the keyboard. Matches display name, curated synonyms, and the raw
identifier (`HKQuantityTypeIdentifierStepCount`), because P1 and P3 use different vocabularies.

**S3b — diff review before commit.** Committing a selection change shows what changes before
anything happens, predicts the size of the next Apple sheet, and states that removal is not
retraction.

```
┌────────────────────────────────────────────┐
│  Review changes                            │
├────────────────────────────────────────────┤
│  Adding 12 types                        ›  │
│  Removing 3 types                       ›  │
├────────────────────────────────────────────┤
│  ⓘ 9 of the 12 need new Health permission. │
│    Apple's sheet is next. It will show     │
│    9 rows.                                 │
├────────────────────────────────────────────┤
│  ⚠ Removing a type does not delete data    │
│    already sent to homeassistant.local.    │
│    Ask whoever runs that system.           │
├────────────────────────────────────────────┤
│              [ Continue ]                  │
└────────────────────────────────────────────┘
```

### S4 — Type detail: the data browser (R-69)

**Purpose.** Show one type's actual values and timestamps, and let a person verify an exported
record against its source.

```
┌──────────────────────────────────────────────┐
│  ‹ Data          Resting heart rate          │
├──────────────────────────────────────────────┤
│  LATEST                                      │
│  54 count/min                                │
│  Today, 04:12 (BST, UTC+1)                   │
│  Source: Apple Watch                         │
├──────────────────────────────────────────────┤
│  EXPORTED TO                                 │
│  Home Assistant · last sent 31 Aug, 07:12 ›  │
│  Archive folder  · last sent today, 09:47 ›  │
│  Export unit: count/min                      │
├──────────────────────────────────────────────┤
│  SAMPLES              [Day] [Week] [Month]   │  list length, not a plot range
│  TODAY                                       │
│  54 count/min   04:12   Apple Watch      ›   │
│  57 count/min   03:58   Apple Watch      ›   │
│  YESTERDAY                                   │
│  55 count/min   04:44   Apple Watch      ›   │
│  …                                           │
│  412 samples in the last month               │
└──────────────────────────────────────────────┘
```

For a type exported as an aggregate (R-06, R-07), a second section appears above SAMPLES:

```
├──────────────────────────────────────────────┤
│  DAILY BUCKETS (this is what we export)      │
│  3 Sep   8,412 count   sum of 47 samples  ›  │
│  2 Sep  11,204 count   sum of 63 samples  ›  │
│  Computed as: sum · cumulative · local day   │
└──────────────────────────────────────────────┘
```

Naming the aggregation function in the interface is R-07's user-facing half. Expanding a bucket
lists the samples that went into it, which is how someone reconciles our number against theirs.

**States.** Loading — the LATEST block resolves first, samples page in. Empty — "No samples for
this type on this iPhone. Either there aren't any, or access is off in Health." Not exported —
the EXPORTED TO block says "Not included in any export. [Add to an export]". Partial — "Access is
limited to data from 1 Aug 2026 onward. Samples before that date can't be read or exported."
Failed — "Couldn't read this type. Health data is locked while iPhone is locked; this usually
resolves on its own."

### S5 — Verify a record

**Purpose.** The correctness wedge, made touchable. Reachable from any sample row in S4, and in
reverse from any record in a run detail.

```
┌────────────────────────────────────────────┐
│  Verify                              Done  │
├────────────────────────────────────────────┤
│  IN HEALTH ON THIS iPHONE                  │
│  54 count/min · 3 Sep 04:12:07 +01:00      │
│  Source: Apple Watch                       │
│  UUID: 4f2a91c8-…-b31d                     │
├────────────────────────────────────────────┤
│  WHAT WE SENT                              │
│  To Home Assistant, run #1,204,            │
│  3 Sep 04:38                            ›  │
│                                            │
│  {"uuid":"4f2a91c8-…-b31d",                │
│   "type":"restingHeartRate",               │
│   "value":54,"unit":"count/min",           │
│   "start":"2026-09-03T04:12:07+01:00",     │
│   "end":"2026-09-03T04:12:07+01:00",       │
│   "source":"Apple Watch","schema":"1.0"}   │
├────────────────────────────────────────────┤
│  ✓ Same value. Same timestamp. Same UUID.  │
├────────────────────────────────────────────┤
│  Home Assistant currently reports 54.      │  read-back where the protocol allows
│  Checked just now.                         │
└────────────────────────────────────────────┘
```

**The unit case, which is where people actually get confused:**

```
├────────────────────────────────────────────┤
│  ⓘ Health shows this as 176 lb because     │
│    that's your preference in the Health    │
│    app. We exported 79.83 kg because your  │
│    export unit for Body Mass is kilograms. │
│    Same measurement, different unit.       │
│    [ Change export unit ]                  │
└────────────────────────────────────────────┘
```

**States.** Not yet exported — "This sample hasn't been exported yet. It's in the queue for Home
Assistant." Evicted (R-09) — "This sample was in the window dropped on 12 Aug when the queue hit
its 256 MB limit. [Re-export 4–12 Aug]". Mismatch — the interesting one: "**These don't match.**
We sent 54; Health now reads 55. That usually means the sample was edited after we sent it. The
next run will re-send it. [Export now]". A mismatch is presented as information, never as an
error, because the overwhelmingly common cause is a legitimate late edit — which is the exact
thing R-01 exists to handle.

### S6 — `Where your data goes` (the R-41 anchor)

**Purpose.** One screen that answers "what is leaving this iPhone, to whom, using what credential,
and when did it last happen" — and that cannot be hidden. §7 covers the invariants; this is the
screen they apply to.

```
┌──────────────────────────────────────────────┐
│  ‹ Destinations   Where your data goes       │
├──────────────────────────────────────────────┤
│  Your health data is being sent to 3 places. │  plain sentence, first
├──────────────────────────────────────────────┤
│  homeassistant.local:8123                    │
│  Home Assistant · HTTPS · bearer token       │
│  Added 12 Mar 2026 · last sent 31 Aug 07:12  │
│  41 types · 182,004 records total         ›  │
│                                              │
│  This iPhone → Archive folder                │
│  Local files · no network                    │
│  Added 12 Mar 2026 · last sent today 09:47›  │
│                                              │
│  mqtt://nas.example.com:8883                 │
│  MQTT · TLS · username + password            │
│  Added 21:14 yesterday · last sent 09:47  ›  │  ← recent additions surface here
├──────────────────────────────────────────────┤
│  RECENT CHANGES                              │
│  2 Sep 21:14  mqtt://nas.example.com added   │
│  14 Jul 08:02 Home Assistant address changed │
│               from 192.168.1.4 to            │
│               homeassistant.local            │
│                             See all (7) ›    │
├──────────────────────────────────────────────┤
│  Egress ledger — every transmission       ›  │
│  2,104 entries · append-only                 │
├──────────────────────────────────────────────┤
│  Credentials in use (3)                   ›  │
├──────────────────────────────────────────────┤
│  If someone else set this up              ›  │
├──────────────────────────────────────────────┤
│  This list is what the app records about     │
│  its own network use. For an independent     │
│  check, the source is at commit a91c8e and   │
│  you can watch the traffic with a proxy.     │
└──────────────────────────────────────────────┘
```

That last paragraph matters. A self-reported list is corroboration, not proof, and claiming
otherwise would itself be the kind of dishonesty this product exists to avoid.

**Egress ledger row format** — one line per transmission, including failures:

```
3 Sep 09:47  homeassistant.local  TLS 1.3, pinned  1,204 records
             41 types · 842 KB · delivered
3 Sep 09:47  nas.example.com:8883 TLS 1.2, pinned  1,204 records
             41 types · 791 KB · sent, unconfirmed
3 Sep 03:41  homeassistant.local  —                0 records
             not attempted · iPhone was locked
```

Filterable by destination and outcome; exportable as a file; **erasable only by R-43's
delete-everything**, never selectively.

### S7 — Add a destination (shared shell)

**Purpose.** Get a working, tested destination configured without typing a token by hand, and make
it structurally impossible to enable one that has not proved it works (R-25).

**States:** `Choose type` → `Draft` → `Testing` → `Test passed` | `Test failed` | `Delivery
unconfirmable` → `Saved & enabled` | `Saved & paused`.

| Sub-state | Design |
|---|---|
| `Choose type` | Five rows, each with a one-line description of what it needs: *Local folder — nothing. HTTPS — a URL and usually a token. Home Assistant — your HA address and a long-lived token. MQTT — a broker address and credentials. Mac — the Tributary app running on your Mac.* |
| `Draft` | Fields render **parsed back** beneath the input as you type: `https · homeassistant.local · :8123 · /api/webhook/ab3f-…`. Missing components are stated, not guessed silently: "No port — we'll use 443." `Save` is unavailable and says why |
| `Testing` | Determinate, named steps; each individually reportable. The step that fails is the diagnosis |
| `Test passed` | Shows exactly what was sent and exactly what came back: request line (secret redacted), response status, response body (truncated, revealable), round-trip time, and the certificate identity card |
| `Test failed` | The five-part error object with the failing step highlighted. `Save` is available **only** as `Save & pause`: "We'll keep this configuration but won't schedule it until a test passes." |
| `Delivery unconfirmable` | A distinct third outcome. Not a pass. See MQTT below |

**Test steps by destination type (R-25).** Every step is named in the UI and reported individually.

| Destination | Steps |
|---|---|
| Local folder | `Open folder` → `Write canary file` → `Read it back` → `Confirm bytes match` |
| HTTPS / request template | `Resolve host` → `TLS handshake` → `Confirm certificate` → `Authenticate` → `Send canary` → `Read response` |
| Home Assistant | the HTTPS steps, plus `Create test entity` → `Read entity back` → `Check unit, device class and state class` |
| MQTT | `Resolve host` → `TLS handshake` → `Confirm certificate` → `CONNECT / CONNACK` → `Subscribe to our own topic` → `Publish canary` → `Receive our own message back` |
| Mac companion | `Find Mac on this network` → `Connect` → `Confirm pairing key` → `Send canary` → `Mac confirms it wrote the file` |

**Certificate confirmation card** (R-31, SEC-10) — shown at first connection and again on any
change, with the export halted until explicitly re-approved:

```
┌────────────────────────────────────────────┐
│  Confirm this server                       │
├────────────────────────────────────────────┤
│  homeassistant.local resolved to           │
│  192.168.1.42 (a private address)          │
│  TLS 1.3                                   │
│  Subject   CN=homeassistant.local          │
│  Issuer    CN=Home CA (not publicly        │
│            trusted — you imported this)    │
│  Valid     14 Feb 2026 – 14 Feb 2027       │
│  SPKI      SHA-256 9f:2c:1a:…:b4           │
├────────────────────────────────────────────┤
│  We'll remember this certificate. If it    │
│  changes, exports stop until you confirm   │
│  the new one.                              │
├────────────────────────────────────────────┤
│  [ This is my server ]   [ Cancel ]        │
└────────────────────────────────────────────┘
```

On change: the same card with **both** fingerprints, old above new, and the copy "Exports to
homeassistant.local are stopped. This certificate is different from the one we recorded on
12 March. That is normal after a renewal, and it is also what an interception attack looks like.
If you didn't renew it, don't approve this."

### S8 — Export history

**Purpose.** "What happened?" Default filter is **problems first**, because a reverse-chronological
list of 400 successes with one failure at position 87 hides the only row that matters.

```
┌──────────────────────────────────────────────┐
│  History                                  ⌕  │
│  [ Problems ] [ All ] [ Home Assistant ▾ ]   │
├──────────────────────────────────────────────┤
│  TODAY                                       │
│  ✕ 09:14  Home Assistant                     │
│           Token rejected                  ›  │
│  ◐ 08:02  Archive folder                     │
│           Partly delivered · 29 of 41 types› │
│  ⏸ 03:41  Home Assistant                     │
│           Health data was locked          ›  │
│  ⧗ 02:10  Archive folder                     │
│           Ran out of background time      ›  │
├──────────────────────────────────────────────┤
│  Showing 4 of 47 runs today. 43 delivered.   │
│                              Show all ▸      │
└──────────────────────────────────────────────┘
```

Run detail contains, for every run: outcome; destination; trigger (background / foreground launch /
manual / Shortcut / widget / Control Centre); sample window bounds; **record count per type**; byte
size; duration; each named step with its own duration; the full error object if any; the exact
payload, redacted by default and revealable; and `Create a diagnostic bundle` (S9).

Every record in a run detail is tappable and lands on S5, verify — completing the round trip.

**States.** Empty: "No exports yet. Run one now to check your setup." with the action. Loading:
list renders from the journal immediately; it is local. Filtered-empty: "No problems in the last
90 days. 1,204 runs delivered." — an empty state that is good news must read as good news.
Retention: shown and bounded, stated on the screen ("Keeping 90 days or 1,000 runs, whichever is
larger. [Change]"), and covered by R-43.

### S9 — Diagnostic bundle preview (R-26)

**Purpose.** Let a person export a redacted bundle, having actually seen it — and make it
structurally impossible to share it without having scrolled through it.

**The design that satisfies the acceptance criterion.** Do not put a disabled Share button in the
toolbar that enables on scroll; that is fragile, invisible to VoiceOver users, and testable only by
proxy. Instead: **there is no share affordance anywhere except at the very end of the content.**
The bundle renders as monospaced text in a scroll view, and below its last line sits the
`Share bundle` button. You cannot reach it without traversing the whole thing, whether you scroll,
swipe with VoiceOver, or tab with Full Keyboard Access. The assertion "no share affordance is
reachable without passing the preview" becomes a structural fact about the view hierarchy rather
than a state machine to verify.

```
┌──────────────────────────────────────────────┐
│  ‹ Run #1,204     Diagnostic bundle           │
├──────────────────────────────────────────────┤
│  412 lines. Read it before you send it.      │
│                                              │
│  WHAT WE REMOVED                             │
│  3 hostnames → destination-1, -2, -3         │
│  2 credentials → omitted entirely            │
│  0 health values (none are ever included)    │
│  1 folder path → user-folder-1               │
│                                              │
│  WHAT WE KEPT                                │
│  41 HealthKit type identifiers, record       │
│  counts, timings, error codes, build hash    │
├──────────────────────────────────────────────┤
│  ─────────── bundle begins ───────────       │
│  build: 1.0.0 (a91c8e) ios: 26.1             │
│  device: iPhone15,2                          │
│  run: 1204 trigger: background               │
│  destination-1: https, port 443, pinned      │
│  step resolve: 41ms ok                       │
│  step tls: 118ms ok                          │
│  step auth: 92ms FAILED http/401             │
│  …                                           │
│  ─────────── bundle ends ───────────         │
├──────────────────────────────────────────────┤
│  [ Share bundle ]   [ Copy as text ]         │  ← only affordance, at the end
│  Sharing sends this outside the app's        │
│  protection. It goes wherever you send it.   │
└──────────────────────────────────────────────┘
```

### S10 — Failure diagnosis

**Purpose.** From a notification or Status, reach a screen that names the cause and offers the fix
in at most two taps, and attempt the fix without leaving the app unless the fix is genuinely
elsewhere.

The five-part error object is a fixed schema, not a style. ① what did not happen, in the person's
terms, naming the destination. ② cause, plain language, second person. ③ the fix, imperative,
naming the specific thing and where it lives — including in someone else's product. ④ one or two
buttons that begin the fix. ⑤ collapsed technical evidence with `Copy diagnostics`.

Prohibited without exception: "Something went wrong", "Unknown error", an unqualified "Please try
again", raw `NSError` descriptions, bare numeric codes as titles, and the word "sync".

Two additions to the Stage 1 archetype catalogue, both new in Stage 2 scope:

| Condition | Required copy |
|---|---|
| MQTT broker refuses the client certificate | ① "The broker rejected this iPhone's certificate" ② "`nas.example.com` accepted the connection, then closed it during the TLS handshake. The broker is configured to require a client certificate it trusts, and it doesn't trust this one." ③ "Check that your broker's `cafile` includes the CA that signed this certificate, and that the certificate hasn't expired — this one expires 14 Feb 2027." ④ `Replace certificate` · `Test again` |
| Mac companion not found | ① "Couldn't find your Mac on this network" ② "`Colin's MacBook Pro` isn't reachable. Both devices need to be on the same network, the Mac needs to be awake, and Tributary needs to be running on it." ③ "Wake the Mac and open Tributary on it, then test again. If you're away from home, the Mac destination will wait until you're back — it never leaves your local network." ④ `Test again` · `Pause this destination` |

Non-actionable failures are labelled as such and never accumulate toward a failing badge, because
a badge that counts things you cannot fix is a badge people learn to ignore.

### S11 — Delete everything, and what we cannot delete (R-43)

Two taps from Settings. No retention interstitial, no "are you sure you want to lose all your hard
work", no countdown, no undo we cannot honour.

| Step | Content |
|---|---|
| 1. Scope | Itemised with counts, each individually deletable too: destinations (3), metric sets (2), stored credentials (3, from the Keychain), queued payloads (0 records, 0 MB), run history (412 runs), egress ledger (2,104 entries), diagnostic logs (18 MB) |
| 2. Honest limits | **"We cannot delete data your destinations already received."** Then the concrete list: "homeassistant.local received data from 12 Mar to 2 Sep · Archive folder holds files from 4 Apr to 3 Sep on this iPhone · nas.example.com received data from 2 Sep to 3 Sep. To have that deleted, ask whoever runs those systems — for two of the three, that's you." |
| 3. Health access | **"We cannot turn off our own Health access."** Exact path: Health → your profile picture → Privacy → Apps → Tributary. Text instructions always shown; any deep link is an enhancement on top |
| 4. Mac | "Your Mac has its own copy. Open Tributary on `Colin's MacBook Pro` and use Delete everything received there. Deleting here does not reach it." |
| 5. Confirm | One destructive confirmation, typed only for the all-inclusive version |
| 6. Receipt | Terminal screen: what was deleted, what remains and why, the things only they can do. Then first-run state |

Deleting a single type's access (R-44): when the app detects that a previously-populated type has
gone empty, it purges that type's queued payloads within 60 seconds and says so in the coverage
review: "Blood glucose stopped returning data on 28 August. We removed 4 queued records for it."

### S12 — The status widget

Two families that matter. Content is state glyph, state word, plain-language age, destination
context. Nothing else.

```
systemSmall — healthy         systemSmall — quiet
┌────────────────────┐        ┌────────────────────┐
│ ✓  Up to date      │        │ ⏱  Quiet           │
│                    │        │                    │
│ Last export        │        │ Last export        │
│ 42 minutes ago     │        │ 3 days ago         │
│                    │        │                    │
│ 3 destinations     │        │ Tap to check       │
└────────────────────┘        └────────────────────┘

systemMedium
┌──────────────────────────────────────┐
│ ⏱  Quiet · last export 3 days ago    │
│    31 Aug, 07:12                     │
│ ✕ Home Assistant   failing, 3 tries  │
│ ✓ Archive folder   12 minutes ago    │
│ ✈ Mosquitto        sent, unconfirmed │
└──────────────────────────────────────┘
```

**The property that makes it a rung rather than a cache.** The widget's timeline is generated on
the assumption that **no further export will ever succeed**, with entries at increasing intervals
that pre-compute the ageing language, and relative-date text that the system re-renders without
needing us. If exports keep working, each success reloads the timeline and the widget never gets
past "minutes ago". If everything stops — background starvation, force-quit, a crash on launch,
an OS upgrade that breaks us — the widget ages on its own, correctly, with no code of ours
running. This is the same insight as the pre-scheduled notification, applied to the third rung.

**States:** never configured ("Nothing set up yet — tap to start"); no data yet ("No exports yet");
healthy; quiet; failing; degraded ("Alerts are off — this widget is your only warning"). Every
state legible in `fullColor`, `accented` and `vibrant`, in greyscale, at every Dynamic Type size
the widget honours.

### S13 — The Mac companion

One window, one menu bar extra. Menu bar presence is required, not optional: a receiver whose only
presence is a window you closed is a receiver you forget you are running.[^macos][^menubar]

```
┌───────────────────────────────────────────────────────┐
│  Tributary Receiver                                   │
├───────────────────────────────────────────────────────┤
│  ✓  Receiving from Colin's iPhone                     │
│     Last received 12 minutes ago · 3 Sep 09:47        │
│                                                       │
│  Writing to  ~/Health/Tributary            [Change…]  │
│              [ Reveal in Finder ]                     │
├───────────────────────────────────────────────────────┤
│  RECEIVED                                             │
│  3 Sep 09:47  1,204 records · 41 types                │
│               2 Sep 09:47 – 3 Sep 09:47               │
│               842 KB · 2026-09-03T0947.ndjson    ›    │
│  3 Sep 03:47  0 records · nothing new                 │
│  2 Sep 21:14  1,180 records · 41 types           ›    │
│                                       Show all (312)  │
├───────────────────────────────────────────────────────┤
│  Paired iPhone: Colin's iPhone                        │
│  Paired 12 Mar 2026 · key 9f:2c:…:b4        [Unpair]  │
├───────────────────────────────────────────────────────┤
│  Delete everything received…                          │
└───────────────────────────────────────────────────────┘
```

Menu bar extra: glyph + "12 min", opening to last-received, the folder, `Reveal in Finder`,
`Open Tributary Receiver`, `Quit`.

**States.** Not paired: a single pairing screen with the QR and the fallback code — see §9.
Waiting: "Paired with Colin's iPhone. Nothing received yet. Exports arrive when both devices are
on the same network and the iPhone is unlocked." Quiet (the Mac's own watchdog): "**Nothing
received for 3 days.** The last transfer was 31 Aug at 07:12. Either your iPhone hasn't been on
this network, or exports have stopped. Check Tributary on your iPhone." Folder unavailable:
"`~/Health/Tributary` isn't there any more. Transfers are being held. [Choose a folder]" — and the
iPhone is told, so the iPhone's ledger records the failure rather than a phantom success. Disk
full: named, with the free space figure. Version mismatch: "This Mac is running 1.0.0; your iPhone
is running 1.2.0. Transfers still work, but [what's different]."

---

## The status model made visible

Two distinct things are being modelled and the interface must not conflate them.

- A **run outcome** is an event: one attempt, one result, recorded in the journal, immutable
  (R-20, R-21). Seven values.
- A **destination state** is a condition: what is true right now, derived from the run history and
  the clock. This is what the Status screen, the widget and the notifications render.

The reason this distinction is load-bearing: **the most important destination state has no
corresponding run outcome.** `Quiet` and `Stale` are conditions produced by the *absence* of
events. The incumbent's blind spot exists precisely because it only models events.

### The seven run outcomes, with real strings

Every string below is the proposed final string. None names an exception. Each names the cause and
the fix, or says plainly that there is no fix.

| Outcome | Glyph (shape) | Label | Title | Cause and fix |
|---|---|---|---|---|
| `success` | `checkmark.circle.fill` | **Delivered** | "Delivered 1,204 records to Home Assistant" | No cause, no fix. Subtitle: "41 types · 2 Sep 09:47 – 3 Sep 09:47 · 842 KB · 4.2 s" |
| `success_nothing_due` | `minus.circle` | **Nothing new** | "Nothing new to send to Home Assistant" | "We checked at 09:47. Nothing has been recorded in your selected types since 07:29, so there was nothing to send. This counts as a successful check." Conditional second paragraph when a selected type has *never* returned data: "3 of your 41 types have never returned anything. That can mean there's no data for them, or that access is off in Health — we can't tell which. [Check coverage]" |
| `partial` (types) | `circle.lefthalf.filled` | **Partly delivered** | "Delivered 18,204 records from 29 of your 41 types" | "12 types returned nothing this run. Either there's no data for them in that window, or access is off in Health. We can't tell which, because iPhone doesn't tell apps what you've turned off." Fix: "Check Health → your profile picture → Privacy → Apps → Tributary." Actions: `Review coverage` · `Export now` |
| `partial` (records) | `circle.lefthalf.filled` | **Partly delivered** | "Home Assistant accepted 1,180 of 1,204 records" | "24 records were rejected. Home Assistant said: `invalid state value`. The other 1,180 arrived." Fix: "This usually means a type is being sent in a shape Home Assistant doesn't accept. [See the rejected records] will show you which types." Actions: `See rejected records` · `Change format` |
| `unknown_ack` (structural) | `paperplane.circle` | **Sent, unconfirmed** | "Sent 1,204 records to nas.example.com — delivery not confirmed" | "You're publishing at QoS 0, which doesn't ask the broker to acknowledge anything. The broker may have accepted these and dropped them, and we would not be able to tell. This is not a failure and it is not a success." Fix: "Set QoS to 1 so the broker confirms each message." Actions: `Set QoS to 1` · `Keep QoS 0` |
| `unknown_ack` (incidental) | `paperplane.circle` | **Sent, unconfirmed** | "Sent 1,204 records to homeassistant.local, then lost the connection" | "The records left this iPhone but the connection dropped before the server confirmed them. They may or may not have arrived." Fix: "Sending again is safe. Every record carries an ID, so a duplicate is merged rather than counted twice." Actions: `Send again` · `Leave it` |
| `failed` | `exclamationmark.triangle.fill` | **Failed** | Per the error archetype: "homeassistant.local rejected the token" | The five-part object. See S10 |
| `abandoned_no_budget` | `hourglass.circle` | **Ran out of time** | "iOS stopped this run before it finished" | "iOS gives a background task about thirty seconds. We read 8,400 of an estimated 31,000 records and saved our place. The next run picks up exactly where this one stopped — nothing was lost, and nothing will be sent twice." Fix: "Nothing to fix. If you'd rather clear the backlog now, run one in the foreground — there's no time limit there." Actions: `Export now` |
| `abandoned_no_budget`, third consecutive | `hourglass.circle` | **Ran out of time (3 in a row)** | "Three background runs in a row ran out of time" | "Your backlog is bigger than iOS's thirty-second background window, so it isn't shrinking. A foreground run has no time limit and will clear it." Fix as above. Actions: `Export now` |
| `cancelled_by_system` (locked) | `lock.circle` | **Health data was locked** | "Health data was locked, so nothing could be read" | "iPhone has to be unlocked for any app to read Health data. Access ends about ten minutes after you lock it. This is an Apple restriction on health data, not a setting." Fix: none. "Nothing to fix — we'll export next time you unlock." Actions: none. **Non-actionable: does not count toward failure escalation** |
| `cancelled_by_system` (other) | `pause.circle.fill` | **Stopped by iOS** | "iOS stopped this run" | "iOS can end a background task at any point — usually because the device got hot, the battery got low, or something else needed the resources. We saved our place." Fix: "Nothing to fix. If it keeps happening, running an export when you open the app will keep you current." Actions: `Export now`. **Non-actionable** |

### The derived destination states

| State | Definition | Glyph | Label | Counts toward |
|---|---|---|---|---|
| `Not set up` | Created, never passed a test | `circle.dashed` | Not set up | nothing |
| `No exports yet` | Enabled, zero runs | `circle.dotted` | No exports yet | nothing |
| `Manual only` | No freshness target by choice | `hand.tap` | Manual only | nothing — never escalates, and says so |
| `Healthy` | Last run succeeded and *last check* ≤ max(1.5·F, 45 min) | `checkmark.circle.fill` | Up to date | — |
| `Quiet` | Checks are healthy; *last delivered* > max(4·F, 24 h) | `clock` | Quiet | attention row, not the failure count |
| `Sent, unconfirmed` | Last run `unknown_ack` | `paperplane.circle` | Sent, unconfirmed | escalates after 2 consecutive |
| `Partial` | Last run `partial` | `circle.lefthalf.filled` | Partly delivered | attention row |
| `Stale` | *Last check* > max(2·F, 90 min) **and no error recorded** | `clock.badge.exclamationmark` | Stale | **escalation, with no error present** |
| `Failing` | ≥1 consecutive actionable error | `exclamationmark.triangle.fill` | Failing | escalation |
| `Blocked` | Needs a person: credential rejected, certificate changed, folder gone | `exclamationmark.octagon.fill` | Waiting for you | escalation |
| `Waiting` | Last attempt deferred for a system reason | `pause.circle.fill` | Waiting | staleness only |
| `Limited by iOS` | Background App Refresh off, or Low Power Mode > 24 h | `bolt.slash.fill` | Limited by iOS settings | persistent banner with the exact path |
| `Paused` | Person paused it | `pause.fill` | Paused | nothing |

Colour is applied on top of shape and label and carries no information not already carried by
both. Every state is rendered with a distinct SF Symbol *silhouette*, verified in greyscale and
under protanopia, deuteranopia and tritanopia simulation, and every state's word is a distinct
word, not a distinct shade. Freshness is always shown relative **and** absolute — "42 minutes ago ·
3 Sep, 09:47" — because relative alone is unreadable after a week and absolute alone requires
arithmetic. VoiceOver announces the absolute form.

---

## The escalation chain (R-23)

The failure this prevents is the category's defining one, so the design goal is not "notify the
user" — it is **make silence structurally impossible to miss, with as few dependencies on our own
code as possible.**

### Rung 0 — foreground catch-up (not counted as a rung; it is the floor)

Every foreground launch immediately runs a coverage probe and an export attempt for every
non-paused destination. This means opening the app is always the remedy, and it means the app is
self-healing for the large population of users who will get little or no background execution.

### Rung 1 — in-app indicator

The Status attention row, the tab bar badge on Destinations, and the app icon badge (count of
destinations needing attention). Present the moment the condition is true. This rung requires the
person to look, which is exactly why it cannot be the only one.

### Rung 2 — the local notification

**Mechanism.** On every run that advances the *last successful check* clock, cancel any pending
watchdog notification for that destination and schedule a new one for `lastCheck + N`. If exports
keep working, the notification is perpetually deferred and never fires. If they stop for *any*
reason — background starvation, revoked HealthKit access, dead server, our own crash, an OS
upgrade that breaks us, the app being force-quit — it fires, because a scheduled local notification
is delivered by the system whether or not our process ever runs again.

**N, and where it is visible.** *F* is the user's freshness target. *N* = max(4·F, N_floor).
N_floor is derived from the R-71 background-delivery measurement (R-24); until that lands, the
design assumes **6 hours** and treats it as a labelled assumption. *N* appears literally in three
places: on the freshness-target screen ("If nothing succeeds for 24 hours, we'll tell you"), in
the destination detail, and in the README. It is a number the product commits to, not an internal
constant.

**Copy rule that is specific to this rung: no number in a pre-scheduled notification may be able
to become false.** We schedule it hours in advance and we will not be running when it fires. iOS
may deliver it late — scheduled summary, a Focus, a powered-off device. So the body carries only
facts fixed at schedule time.

**The watchdog notification, verbatim:**

> **Home Assistant has gone quiet**
> Last successful export: 2 September, 08:31. Open to see why.

Wrong versions, for contrast: "No export for 24 hours" (becomes false if delivered late);
"You have 1,204 unsent records" (a count we cannot know at schedule time); anything containing a
health value (a Lock Screen and Apple Watch disclosure).

Multiple destinations quiet at once collapse into one:

> **Exports have gone quiet**
> Nothing has succeeded for any of your 3 destinations since 2 September, 08:31. Open to see why.

**Notification properties.**

| Property | Value | Why |
|---|---|---|
| Interruption level | **Active** | HIG reserves Time Sensitive for something happening now or within the hour; a stale export is a condition that has persisted. Overclaiming urgency is how people turn a channel off[^notifications] |
| Thread identifier | Per destination | Repeats collapse rather than accumulate |
| Rate | Max 1 per destination per 24 h | |
| Actions | `Open and export` · `Remind me tomorrow` | Named honestly: the action opens the app, because a notification action cannot reliably read HealthKit on a locked device (C-02) |
| Content | Status, destination label, absolute date. No health values, no counts, no hostnames beyond the destination's own label | |

**Failure notifications** (distinct from the watchdog) fire at the moment of an actionable error,
carry the error's ① title as the body, deep-link to the run detail, are capped at one per
destination per 24 h, and never exist for success.

**Permission strategy.** Request `.provisional` at first destination setup, never on day one.
Provisional grants immediately without a prompt and delivers quietly to Notification Center with
Keep / Turn off attached. Request full authorisation only in context, after a real failure has
already been delivered quietly — because nobody can evaluate failure alerts before seeing one, and
because a denied full request destroys provisional too. That last hazard is why we never prompt
speculatively.[^notifprompt]

### Rung 3 — the status widget

Designed in S12. Its critical property is that it ages correctly with no execution of ours. When
notification permission is absent, this rung is not a nice extra — it is the whole alarm, which is
why the PRD moved it to Must.

### The notification-denied path

Notification state is re-read on **every foreground launch**, because it can change in Settings at
any time and there is no callback. Three configurations, three designs.

**(a) Notifications available, widget installed.** Full chain. Nothing said.

**(b) Notifications denied or turned off, widget installed.** The widget becomes the alarm and the
app says so once, in place, without nagging. On Status, a permanent row (not an alert, not a
modal):

> **Alerts are off, so your widget is doing this job.**
> With notifications off we can't tell you when exports stop — but your Home Screen widget shows
> how long it's been, and it keeps counting even if this app never runs.
> `Turn on alerts` · `How the widget works`

**(c) Notifications denied and no widget.** This is the honest failure case and the product must
name it rather than pretend. A permanent, non-dismissible row at the top of Status, above the
attention row:

> **Nothing will tell you if exports stop.**
> Alerts are off and you don't have the widget. If exports fail, you'll only find out by opening
> this app. That's the failure this app exists to prevent, so it's worth fixing.
> `Turn on alerts` · `Add the widget`

`Add the widget` opens a short, illustrated, three-step instruction screen (long-press the Home
Screen → Edit → search Tributary), because "add a widget" is not a thing an app can do for you and
a large fraction of users have never added one.

**Never:** a modal on launch, a repeated prompt, a red interstitial, or a refusal to function. The
row is permanent while true and disappears the moment either rung is restored. It is honest, not
coercive — and the reason it can be permanent without being nagging is that it occupies a fixed
place and never interrupts.

### One refinement adopted from the observability design

`05-observability-design.md` was written in parallel and reaches the same conclusion on the two
questions that matter most here — the watchdog is re-armed only by `success` and
`success_nothing_due`, and it must also evaluate on foreground launch rather than only on wakes.
It catches one thing my design missed, and I am adopting it.

**A QoS-0-only destination would alarm forever.** If `unknown_ack` never advances any success
clock, a destination that is *working exactly as configured* has no last-success timestamp at all,
and the watchdog fires on it permanently — an alarm that is technically true and practically
useless, which is how alarms get turned off. The fix is a separate, clearly labelled clock for
non-confirmable transports: the interface says **"Last sent (unconfirmed) 12 minutes ago"** rather
than "Last delivered", the watchdog is armed from that clock, and the destination card carries a
permanent one-line reminder of what it does not prove:

> **Mosquitto · Sent, unconfirmed · 12 minutes ago**
> QoS 0 means the broker never confirms anything, so "sent" is the most we can honestly say.
> `Set QoS to 1`

That reminder is not a warning glyph and does not raise the attention row. It is the steady state
of a configuration the person chose, and treating it as a fault would be the mirror image of the
incumbent's bug.

The one place we differ is scope: the observability design has the Mac companion's out-of-band
alert as a Should. I have designed it in as part of the receiver's core, because it is the only
genuinely independent witness in the product and the cost is a timestamp and a notification. That
is a PM call (§13, Q12).

### What the escalation chain still cannot do

Stated plainly because the product's claim is honesty. If the person has notifications off, no
widget, and does not open the app, we cannot reach them; there is no out-of-band channel, by
design (R-37). The one partial exception is the Mac companion, which has its own clock and its own
notification on a second device. Beyond that, R-27's "time since last successful export" is
consumable by the person's own monitoring — the honest answer for P1, who already runs an alerting
stack and should point it at us.

---

## Anti-coercion surfaces

The threat, stated concretely, is T-24: a person with physical access and the passcode configures
a destination they control, and the victim's sleep, cycle-adjacent and location-adjacent data flows
to them indefinitely. Every property that makes this product good — no account, no cloud, no
telemetry, an arbitrary user-configured endpoint — makes it a better vehicle for that. R-30's
ledger records it faithfully and tells nobody. R-40 and R-41 are what turn a passive record into an
active one.

### R-40 — a notification when a destination is added or re-pointed

Fires on: destination creation; any change to a destination's host, port, path, topic or transport;
any change to a Mac pairing; enabling a destination that was paused; and importing a configuration
that produces any of the above.

**Copy, verbatim:**

> **New destination added**
> Health data will be sent to `nas.example.com` once it's enabled. Added 21:14 today. If you didn't
> do this, open Tributary.

> **Home Assistant now points somewhere else**
> Changed from `homeassistant.local` to `203.0.113.9` at 21:14 today. If you didn't do this, open
> Tributary.

> **A configuration file added 2 destinations**
> `nas.example.com` and `203.0.113.9` were added from an imported file at 21:14 today. If you
> didn't do this, open Tributary.

**Properties.** Interruption level **Time Sensitive** — unlike the watchdog, this *is* something
happening now, and it is the one notification in the product that justifies breaking through a
Focus.[^notifications] It has no in-app off switch (§7, invariant 5). It deep-links to
`Where your data goes` with the changed destination highlighted. It carries the hostname, because
the hostname is the entire point. It fires even if the destination is created and immediately
paused, because "added but not yet enabled" is exactly how a careful abuser would stage it.

### R-41 — "can never be hidden" as an interface property

R-41 is a prohibition, and prohibitions rot unless they are expressed as things you can test. Six
invariants:

**1. Fixed address.** Destinations, credentials-in-use and the egress ledger are reachable in ≤ 2
taps from the app's root, by a path that is identical in every build, every state and every
configuration. The Destinations tab does not move, does not change label, is never conditionally
hidden, and is never empty-stated away. *Test:* a UI test asserts the tap path from cold launch in
each of: first run, no destinations, three destinations, all paused, delete-all just completed.

**2. No authentication above the app's own.** SEC-29 permits an optional app-level biometric or
passcode gate. R-41 means that gate applies to the **entire app or to nothing** — there is never a
second, additional gate in front of destinations, credentials or the ledger. A "hide these behind
Face ID" setting cannot exist, because it is a stealth mode wearing a security costume. *Test:*
feature review gate; no code path presents an authentication challenge on a subtree of the UI.

**3. Evidence is append-only and cannot be selectively erased.** The egress ledger has no per-row
delete, no date-range clear, no "clear history" action. It can be emptied only by R-43's
delete-everything, which is itemised, irreversible, requires typed confirmation, **and itself fires
a notification** ("All destinations, credentials, history and the egress ledger were deleted at
21:14"). An abuser cannot quietly scrub the record; they can only detonate it, which is loud. This
notification is my addition to R-43 and I am flagging it (§13, Q4) because it has a legitimate-user
cost of exactly one notification.

**4. No disguise.** No alternate app icons (`CFBundleAlternateIcons` is absent from the build), no
configurable app name, no "discreet mode", no Focus-filter that hides the app, no setting that
removes it from search. The app looks like itself on the Home Screen forever. *Test:* build-time
assertion on the shipped `Info.plist`; recorded as a permanent Won't alongside the stealth-mode
prohibition.

**5. No setting whose effect is reduced visibility.** There is no in-app control anywhere whose
result is fewer visible destinations, a shorter ledger, or a quieter destination-change alert. The
R-40 notification category is not user-disableable in the app. (It is disableable at the OS level;
we cannot prevent that, and when it happens the Status degraded row from §6 appears — which is
itself a signal.) *Test:* enumerate every settings toggle and assert none reduces the visibility of
a destination, a credential or a ledger entry.

**6. Legible without expertise.** `Where your data goes` leads with a plain sentence — "Your health
data is being sent to 3 places" — before any hostname, protocol or fingerprint. A person who does
not know what MQTT is must still be able to tell that three things are receiving their health data
and when each started. *Test:* comprehension test — 5 participants, none technical, all correctly
answer "how many places is this phone sending data to, and when did the newest one start?"

### The "If someone else set this up" screen

A static, offline, in-app text screen linked from `Where your data goes`. No network request, no
external link, no phone number we would have to keep current. Its content is factual, not advisory,
because we are not qualified to give safety advice:

> **If someone else set this up**
>
> Everything on the previous screen is a complete record of where this iPhone sends health data,
> and it cannot be hidden or edited from inside this app.
>
> Some things worth knowing before you change anything:
>
> - **Removing a destination is visible at the other end.** Whoever set it up will see the data
>   stop arriving. If that matters to your safety, think about the timing before you do it.
> - **You can take a copy of the record first.** The egress ledger exports as a file, with dates,
>   destinations and record counts.
> - **Deleting this app does not delete what was already sent.** We cannot reach data that has
>   already left this iPhone.
> - **This app cannot hide itself, and it cannot be made to.** If it is on this iPhone, it is on
>   the Home Screen and in Settings, and this screen exists.
>
> If you want help thinking through the safety side of this, organisations that specialise in
> technology-facilitated abuse do that work. We have deliberately not put a link here, because a
> link on this screen would appear in this iPhone's browsing history.

That last paragraph is a deliberate design decision and I want it argued rather than assumed. It
needs review by someone who actually works in this field (§13, Q5).

### Honest limits — what the interface cannot defend against

I would rather write this than have the adversarial reviewer write it.

1. **Everything we do is on the shared device.** The notification, the ledger, the widget and the
   banner all land on the iPhone that the coercer has access to. We have no out-of-band channel,
   by design (R-37), and adding one would collapse the privacy posture that makes this product
   worth building. This is the fundamental limit and everything below is a consequence of it.
2. **A notification can be dismissed before the victim sees it.** Someone who configures a
   destination and hands the phone back thirty seconds later will have cleared the R-40
   notification. The ledger entry survives, but the ledger requires the victim to go and look.
3. **We cannot detect coercion, and we will not try.** Any behavioural heuristic ("this destination
   was added in under 90 seconds by someone who then immediately opened Settings") would be a false
   accusation generator in the overwhelming majority of cases, would be a specific safety hazard
   when wrong in an intimate-partner context, and would be published in our own source for any
   abuser to read around. The design is deliberately uniform: every destination is reported the
   same way.
4. **Our source is public.** An abuser can read exactly how R-40 and R-41 work. The controls are
   designed to survive being fully understood — there is no obscurity in them — but "the abuser
   knows the notification will fire and takes the phone back to clear it" is a real scenario and
   the design does not solve it.
5. **The OS can hide us.** Screen Time restrictions, an MDM profile, or App Library placement can
   make the app hard to find even though we never hide ourselves. We can be honest about this in
   documentation; we cannot fix it in the app.
6. **The optional app-level gate does not defend against this threat.** SEC-29's biometric gate
   stops a stranger who picks up an unlocked phone. It does nothing against someone who knows the
   passcode, which is the T-24 actor by definition, and it must never be presented as protection
   against them.
7. **The victim may configure it themselves, under pressure.** No interface property helps here.
   The record we keep is still worth keeping, because it is evidence, but it is not a defence.

What the design *does* achieve: an abuser cannot make this app quiet, cannot make it look like
something else, cannot erase its record without a loud, itemised, notified deletion, and cannot
prevent the person from finding the whole picture in two taps from a place that is the same in
every build. That is a meaningfully higher bar than the category norm, and it is worth being
precise about, because overclaiming here would be worse than the gap.

---

## The data browser

### Why it exists, and how that constrains it

Two reasons, both of which push the same way. Guideline 2.5.1 expects HealthKit to be used for
health purposes, §5.1.3 governs what a health app may do with the data,[^review] and "HealthKit
capability with no substantial health functionality" is a reported rejection cause — so the browser
is RK-3's real mitigation. And it is the verification surface for
the correctness wedge: the place a person checks our number against Health's number. Both reasons
are satisfied by showing values and timestamps faithfully. Neither is satisfied by anything else,
which is the whole argument for restraint.

The design is S3 (the type list) plus S4 (type detail) plus S5 (verify). No additional screens.

### The five rules that keep it a browser

1. **No visual encoding of quantity.** No charts, sparklines, bars, gauges, rings, progress arcs or
   heatmaps, anywhere, in any size class, on any surface. Numbers and text only. If a number needs
   a picture to be understood, that is the Health app's job and it does it better.
2. **No derived numbers we did not export.** The browser shows exactly two kinds of value: a raw
   sample as HealthKit returned it, and an aggregate we actually computed for a real export,
   labelled with the function that produced it. No display-only averages, no week-over-week, no
   deltas, no streaks, no personal bests, no min/max highlighting.
3. **No cross-type views.** Every screen is scoped to exactly one type. No daily summary, no
   combined timeline, no correlation, no "today at a glance". This single rule kills most dashboard
   drift before it starts, because almost every dashboard idea needs two types on one screen.
4. **No time-series affordances.** The Day / Week / Month control chooses how many rows to list. It
   is not a plotting window, there is no zoom, no pan, no scrubbing. Sort order is time descending,
   always, with no alternative.
5. **No interpretation, ever (R-42).** No colour by good or bad, no thresholds, no normal ranges,
   no "elevated", no trend arrows. Not because it would be hard, but because it is the boundary
   between a utility and a regulated medical device, and the boundary has to be visible in the
   interface for it to be defensible.

**The enforcement mechanism, because rules without one do not survive Stage 3.** Any pull request
that introduces a chart type, a computed statistic, a second type on a browser screen, or a
threshold comparison into the browser fails a named review gate, in the same way R-42's
non-interpretation boundary does. This should be a CODEOWNERS path, not a convention.

### What makes it genuinely useful rather than compliance theatre

The verify round trip (S5). From any sample: what we sent, to whom, in which run, with the UUID
and the unit conversion made explicit. From any exported record in the History: back to the source
sample. This is the only place in the product where a person can *prove* the wedge claim rather
than believe it, and it is cheap because both halves already exist — the journal has the records
and the browser has the samples; verify is a join and a comparison view.

The second genuinely useful thing is the aggregate bucket view, which shows the function
("sum · cumulative · local day") and the samples that fed it. When someone's Grafana panel and
their Health app disagree, that screen is the answer, and building it costs almost nothing on top
of R-07's existing requirement to name the computation in the payload.

### What an App Review reviewer sees

They will use a simulator with no Health data. So: **R-114's demo mode must populate the Data tab**,
and the tab must show real values and timestamps within two taps of launch. The reviewer's path is
launch → Data → a list of types with values → tap one → samples with values and timestamps. If
that path is not obvious on a clean simulator, RK-3's mitigation does not exist. This is a design
requirement on demo mode, not on the browser, and it needs to be stated somewhere an engineer will
read it.

---

## Destination configuration

### Shared patterns (R-67)

| Mechanism | Priority | Design |
|---|---|---|
| **Paste** | Must | A visible system paste button on every URL and secret field. No long-press discovery, no clipboard-access prompt. Combined with Universal Clipboard this is the fastest path from a Mac and we should stop hiding it |
| **QR / camera config import** | Should | Scan a QR encoding a config bundle from the person's own server, our Mac companion, or a local page in our docs. **Always** followed by the review screen below |
| **Config file import** | Should | A `.tributary` JSON file via the document picker or AirDrop. Same review screen. Secrets excluded by default; a typed confirmation is required to include them in an export |
| **Typed entry** | Must | The fallback, made survivable: autocorrection, autocapitalisation and smart punctuation off on every URL and secret field; leading and trailing whitespace stripped **visibly** ("Removed a trailing space."); live parse-back of URL components; shape feedback on secrets without revealing them ("214 characters · looks like a JWT") |
| **Deep-link config URL** | Won't | A URL cannot safely carry a secret — URLs land in logs, history and pasteboards. Rejected deliberately, not omitted |

**Import review screen.** No destination is ever created, modified or enabled by a scan, a file, a
URL scheme or a Handoff activity without this screen and an explicit confirmation:

```
┌────────────────────────────────────────────┐
│  Review before importing            Cancel │
├────────────────────────────────────────────┤
│  This will add 1 destination.              │
├────────────────────────────────────────────┤
│  Name       Home lab MQTT                  │
│  Type       MQTT over TLS                  │
│  Host       nas.example.com                │
│  Port       8883                           │
│  Topic      health/+/state                 │
│  QoS        0  ⚠ can't confirm delivery    │
│  Retain     on ⚠ see below                 │
│  Credential username + password (included) │
│  Types      41 selected                    │
├────────────────────────────────────────────┤
│  ⚠ Retained messages stay on the broker    │
│    until something replaces them. Anyone   │
│    who can subscribe to health/… later     │
│    will see your most recent values —      │
│    including after you stop exporting.     │
├────────────────────────────────────────────┤
│  Nothing is saved and nothing is sent      │
│  until you test it.                        │
├────────────────────────────────────────────┤
│         [ Add and test ]                   │
└────────────────────────────────────────────┘
```

**Secret handling in the interface.** Stored secrets render as a mask plus a non-reversible
descriptor: `●●●●●●●● · 214 chars · JWT · added 12 Mar`. The primary action is **Replace**, which
opens an empty field — editing a masked value in place invites silent truncation. `Reveal` requires
local authentication, shows one field, and auto-hides after 15 seconds. Secrets never appear in a
list, in History, in a payload preview, in a diagnostic bundle or in a trace, and redaction happens
at composition rather than as a display filter.

### The five destination types

**1. Local file.** Fields: a folder chosen through the system document picker, a filename template,
a format (NDJSON / JSON / CSV / HAE-compatible), and rotation. No credentials, no network, no
allowlist entry. The person may point it at an iCloud-backed folder in Apple's own picker; we ship
no iCloud code and we do not filter the picker (PC-3). The `Draft` state shows the resolved path
and an example filename. Failure state that matters: a stale security-scoped bookmark — "The folder
you chose isn't available. This usually means it's on a drive or a cloud folder that isn't reachable
right now. [Choose it again]".

**2. Generic HTTPS POST with a request template.** Fields: URL, method, headers (key/value rows with
a `Bearer …` helper), body template, timeout, and a per-destination plain-HTTP or private-CA opt-in
(R-35) that names the risk in words and is never the default. The template editor renders a **live
preview against a real sample from this device** below the editor, which is both the dry-run
preview (R-31) and the fastest way to catch a template mistake. Placeholders are listed in a picker
rather than documented elsewhere.

**3. Home Assistant preset.** Fields: base URL, and either a long-lived access token or a webhook
ID. Configuration, not integration. The test does the extra thing that matters (R-89): it creates
a test entity, reads it back, and **shows the read-back to the person**:

> **Home Assistant accepted it.**
> We created `sensor.tributary_test` and Home Assistant reports it back as:
> unit `count`, device class `none`, state class `measurement`.
> That state class is what makes long-term statistics work. Without it, Home Assistant records the
> value and silently keeps no history.

That is R-89's silent-failure mode, surfaced at setup time in the one place it can still be cheap
to fix.

**4. MQTT.** Fields: host, port, TLS mode (TLS / plain, with the R-35 opt-in for plain), client ID,
username and password, optional TLS client certificate, QoS, topic template, retain flag, clean
session, and keep-alive.

Two design points specific to MQTT.

*The test can confirm what steady state cannot.* At QoS 0 there is no acknowledgement, so ongoing
exports are `unknown_ack` by construction. But the **test** can subscribe to the topic it is about
to publish to and watch its own canary come back, which is a genuine end-to-end confirmation. The
UI must be explicit that this proves less than it appears to:

> **Confirmed — for this test.**
> We published a test message and received it back by subscribing to `health/test`. That confirms
> the broker accepted and redistributed it.
>
> Ongoing exports won't be confirmed this way. At QoS 0 the broker doesn't acknowledge anything, so
> every run will be recorded as **Sent, unconfirmed**. Set QoS to 1 and we can confirm each one.
> `[ Set QoS to 1 ]`  `[ Keep QoS 0 ]`

*TLS client certificates, with SEC-67 and SEC-68 both honoured.* Two paths, offered in this order:

- **Generate a key on this iPhone (recommended).** The private key is created in the Secure Enclave
  and cannot leave. We produce a certificate signing request; the person saves or copies it, signs
  it with their own CA, and imports the signed certificate back. Copy: "The private key is created
  inside this iPhone's Secure Enclave and can never be copied off it — not by us, not by a backup,
  not by anyone with this iPhone."
- **Import a certificate and key you already have** (PKCS#12 from Files, with a passphrase field).
  On import we display subject, issuer, serial and validity dates, and we say the true thing:
  "This certificate's private key is stored in the keychain on this iPhone and excluded from
  backups. It is **not** protected by the Secure Enclave — a key created elsewhere cannot be put
  there. If that matters to you, generate one here instead."

**5. Mac companion.** Pairing, designed as a mutual-confirmation flow rather than a code the phone
types into the void.

```
On the Mac                          On the iPhone
┌──────────────────────────┐        ┌──────────────────────────┐
│  Pair with your iPhone   │        │  Add a Mac               │
│                          │        │                          │
│   ████ ▄▄ █ ▄█████       │  scan  │   [ camera viewfinder ]  │
│   █  █ ██▄▄ ▄█   █       │ ─────► │                          │
│   █▄▄█ ▄ ██  █▄▄▄█       │        │  Point at the code on    │
│                          │        │  your Mac.               │
│  Can't scan? Type this   │        │  [ Type a code instead ] │
│  on your iPhone:         │        │                          │
│      K4T9 - MZ2P - 7     │        │                          │
└──────────────────────────┘        └──────────────────────────┘

                    then, on both screens

┌──────────────────────────┐        ┌──────────────────────────┐
│  Do these match?         │        │  Do these match?         │
│                          │        │                          │
│         4 7 2 9 1 6      │        │         4 7 2 9 1 6      │
│                          │        │                          │
│  [ Yes, pair ]  [ No ]   │        │  [ Yes, pair ]  [ No ]   │
└──────────────────────────┘        └──────────────────────────┘
```

The six digits are derived from the established session, and confirming them on both devices is
what makes the pairing resistant to a machine-in-the-middle on the local network. Local Network
permission is requested at exactly this moment, with an accurate purpose string — the prompt is
triggered by real outbound traffic and needs `NSLocalNetworkUsageDescription` and declared Bonjour
service types in the built `Info.plist`.[^lnp]

`NSLocalNetworkUsageDescription`: "Finds the Tributary receiver running on your Mac, so this iPhone
can send exports to it directly over your own network."

The test's final step is the strongest canary in the product: **the Mac displays the received file
on its own screen while the person is looking at it.** The iPhone shows "Your Mac confirmed it
wrote `canary-2026-09-03T0947.ndjson` to ~/Health/Tributary" and the Mac simultaneously shows the
same filename at the top of its receipt list. Two devices, one fact, no trust required.

Key change on re-pair halts transfers and requires explicit re-approval, with both fingerprints
shown, exactly as the certificate change card does.

---

## Accessibility, localisation and units

These are properties of the design, not a checklist applied to it. Where a requirement is
structural I say what the structure is.

### Designed properties

**Status is not colour-coded, it is shape-and-word-coded.** The status primitive is a triple —
(SF Symbol silhouette, state word, fixed position) — and colour is applied afterwards, carrying no
information the other two do not already carry. This is why the widget works in `vibrant` and
`accented` modes without a separate design, why greyscale rendering is a screenshot test rather
than a redesign, and why WCAG 2.2 SC 1.4.1 is satisfied by construction rather than by
audit.[^wcag] Verification: render all thirteen states to greyscale and through protanopia,
deuteranopia and tritanopia simulation; all must remain mutually distinguishable *and* correctly
identifiable.

**Status rows are vertically stacked at every size.** They are not horizontal layouts that reflow
at `isAccessibilitySize`; they are stacks that happen to look compact at small sizes. There is no
layout change to get wrong at AX5, and no state word can ever truncate because state words wrap
rather than truncate. Apple's guidance for the App Store's Larger Text claim is that content works
to at least 200%; accessibility sizes go to 310%, and our screenshot matrix targets 310% with Bold
Text and Display Zoom also on.[^ant] Type styles come from the system throughout, per Apple's
Dynamic Type guidance.[^typography]

**Liquid Glass is confined to the navigation layer.** Status text, error content, sample values and
payload previews are on the opaque content layer; toolbars, the tab bar, sheets and the floating
`Export now` control may be glass, and glass is never stacked on glass.[^glass][^materials] This is
a legibility decision before it is an aesthetic one: contrast must be measured on **composited**
colours, in light, dark and Increase Contrast, in both Liquid Glass appearances, because
translucency changes the measured result and a flat hex value proves nothing.

**Every status row is one VoiceOver element speaking one sentence.**[^voiceover] "Home Assistant. Failing. Last
successful export 31 August at 7:12 a.m." Secondary detail — attempt count, next-attempt window,
error title — hangs off custom content so the default announcement stays short but nothing is
unreachable. Error objects are navigable ① → ⑤ in order with the fix actions as buttons and the
evidence as a disclosure. History gets a rotor for failed runs so a screen-reader user can jump
between failures without traversing successes. Masked secrets are never spoken; the descriptor is:
"Token. 214 characters. Added 12 March. Double-tap to replace."

**The composite acceptance test** is that Flows S2, S7, S8/S10 and S11 are completable end to end
with VoiceOver and the screen curtain on, by a proficient tester, unaided and recorded. Every
label-level check is an input to that; that is the one that matters.

**Touch targets** are ≥ 44×44 pt with ≥ 12 pt of padding between bezelled controls, audited first
on the type list, whose dense rows are the likeliest offender.[^a11y]

**System settings are honoured, not tolerated.** With Reduce Transparency on, no status text sits
on a translucent surface over arbitrary content. With Reduce Motion on, no state change is
communicated by animation or glass morph alone — every transition that carries meaning also
changes text. With Increase Contrast on, glass picks up a border and we do not fight it.

**Accessibility Nutrition Labels.** iOS 26 surfaces these on the product page and Apple has said
they will eventually be required.[^ant2] We should claim, and be able to defend: VoiceOver, Voice
Control, Larger Text, Sufficient Contrast, Differentiate Without Color Alone, Dark Interface,
Reduce Motion. `Differentiate Without Color Alone` is the one that maps directly onto R-64 and it
is the one that would be embarrassing to fail, given the claim we are making about legibility.
Which labels we commit to at v1 is a PM call (§13, Q9).

### Localisation and RTL

All user-facing strings localised; **no runtime string concatenation for sentences**, all
interpolation positional. Dates, times, numbers and units formatted through system format styles,
never by hand. A pseudo-localised build (+40% length, accented) must show no truncation on any
screen at default type size. Verified across `en_GB`, `en_US`, `de_DE`, `ja_JP` and `ar_EG` with
both 12- and 24-hour preferences.

RTL: leading/trailing layout, mirrored chevrons and progress direction, and correct bidirectional
rendering of mixed strings containing Latin hostnames — a hostname inside an Arabic sentence is the
specific case to screenshot, and it appears on `Where your data goes`, in every error title, and in
the ledger.

The error object's ⑤ Evidence stays **untranslated** — identifiers, status codes, headers,
fingerprints — so a pasted diagnostic is searchable by maintainers regardless of the reporter's
language. ① through ④ are localised. German is the truncation canary: "Limited by iOS settings" is
long, and state labels wrap rather than truncate at every size.

### Units (R-65)

| Rule | Why |
|---|---|
| **Display units follow the Health app.** Read `preferredUnits(for:)`, observe `HKUserPreferencesDidChange`, update immediately. We do not invent a display-unit setting; we offer an override for the person who wants one, defaulted to "follow Health" | Their weight is in stones in Health. Showing kilograms here would be us being wrong inside their own device |
| **Export units are separate, explicit, stable, and never change because a Health preference changed** | If someone toggles pounds in Health and their Grafana panels silently switch units, we have corrupted their dataset. Display follows the person; the wire format follows the contract |
| **Every exported value carries its unit, next to a payload schema version** | Makes the payload self-describing and a future unit change detectable rather than silent |
| **Changing an export unit is a diffed, warned, versioned action** | "This changes Body Mass from kg to lb for all future exports to nas.example.com. Data already at the destination is not converted." |
| **Timestamps on the wire are ISO 8601 with an explicit offset**, plus the sample's recorded time zone | `2026-09-03T09:47:14+01:00`. Never a naive local string, never a bare epoch |
| **When display and export units differ, the verify screen says so and shows the conversion** | This is where users conclude we have a bug. S5 has the copy |
| 12/24-hour and decimal separators from locale and system setting | Never hard-coded |

---

## Platform-honesty copy

R-63 requires the locked-device and best-effort-scheduling constraints to be disclosed in-product
before the first HealthKit permission prompt, and in the README. Per §S2 this is screen **S2.4**,
which is an ordinary navigable onboarding step — deliberately *not* the HIG pre-alert screen, so
the one-button rule binds only S2.5.

The brief for this copy is that it must be truthful without reading as an apology for the product.
The way to do that is to make the constraint the *setup* and our response the *payoff*, in that
order, and to end on a capability rather than a limitation.

The ten-minute figure is Apple's own, from the health-specific platform security page: the
HealthKit store sits in the Data Protection class *Protected Unless Open*, and "access to the data
is relinquished 10 minutes after the device locks."[^lock] The copy below states it as a fact about
iPhone rather than a fact about us, because that is what it is.

**S2.4, verbatim:**

> ## Two things about how iPhone works
>
> Both of these are Apple's design, not ours, and neither can be engineered around. They shape
> what this app can promise, so here they are before you decide anything.
>
> **Health data is locked when your iPhone is.**
> About ten minutes after you lock your iPhone, iOS encrypts the Health database, and no app can
> read it again until you unlock. It is one of the stronger protections on the device. It also
> means that if an export is due while your iPhone is in your pocket, it waits.
>
> **iOS decides when apps run in the background.**
> There is no way for an app to book itself a slot. iOS grants background time when it judges the
> moment right — and sometimes it doesn't grant any. So we don't offer a "every day at 3 a.m."
> switch. It would look precise and behave randomly, and you would eventually conclude, reasonably,
> that we were broken.
>
> ### So here is what we actually do
>
> You tell us how out of date you are willing to be. We export whenever iOS lets us, and always
> when you open the app. And every single time an export succeeds, we book an alert with iOS for
> the moment you would be overdue — then cancel it on the next success.
>
> That last part is the whole idea. **If we stop working, the alert stops being cancelled, and it
> fires.** It fires whether or not iOS ever runs this app again, whether or not the app has
> crashed, whether or not you force-quit it. Silence is the thing this app is built to notice.
>
> If you need exact timing, run an export from Shortcuts or the Control Centre button. Then it is
> your schedule, and iOS keeps it.
>
> `‹ Back`                                                        `[ Continue ]`

**The same content, compressed for the README** (R-63's second half):

> **What this app can and cannot promise.** iOS encrypts Health data about ten minutes after your
> iPhone locks, and gives no app a way to schedule itself. So there is no time-of-day scheduler
> here — you set a freshness target, we export whenever iOS allows and whenever you open the app,
> and we tell you when we have fallen behind. The overdue alert is scheduled with iOS on every
> success, so it fires even if this app never runs again. For exact timing, use Shortcuts.

**Related honest copy, for the freshness-target screen:**

> **How out of date are you willing to be?**
> ○ About an hour   ● About 6 hours (default)   ○ About a day   ○ Only when I ask
>
> We'll attempt an export whenever iOS lets us run in the background, and always when you open the
> app. iOS decides the timing and can skip it entirely, and Health data can't be read while your
> iPhone is locked.
>
> **If nothing succeeds for 24 hours, we'll tell you.** That alert is scheduled every time an
> export succeeds, so it fires even if this app never runs again.
>
> For exact timing, run an export from Shortcuts or the Control Centre button.

---

## Component inventory

| Component | Used by | Notes |
|---|---|---|
| `StatusGlyph` | everywhere | Thirteen states; silhouette-distinct; carries an accessibility label; renders in `fullColor` / `accented` / `vibrant` |
| `StatusLabel` | everywhere | The state word. Wraps, never truncates |
| `FreshnessLabel` | Status, cards, widget, ledger | Relative + absolute pair. VoiceOver speaks the absolute form. Auto-updating relative text so the widget ages without a reload |
| `AttentionRow` | Status | Present only when not all-healthy. Names the destination and the cause, never a count |
| `PersistentNoticeRow` | Status | Non-dismissible while true. Used by the degraded-escalation notice, `Limited by iOS`, and the iPad-only-exporter notice |
| `DestinationCard` | Status | Glyph, name, state, both clocks, one-line cause, chevron |
| `OutcomeChip` | History rows, run detail, ledger | The seven run outcomes plus the two `unknown_ack` flavours |
| `ErrorObject` | anywhere a failure surfaces | Fixed five-part schema; ⑤ collapsed; `Copy diagnostics` always present |
| `StepProgress` | Destination test, export run | Determinate, named steps, per-step result. No indeterminate spinner where a total is knowable |
| `ParseBackField` | URL and host fields | Live component rendering; states missing components rather than guessing silently |
| `SecretField` | credentials | Mask + descriptor; `Replace` primary; `Reveal` gated and timeboxed |
| `CertificateCard` | HTTPS, MQTT, Mac pairing | Subject, issuer, validity, SPKI, resolved address, address class. Two-fingerprint variant for changes |
| `PairingCard` | Mac companion | QR + fallback code + six-digit mutual confirmation |
| `PayloadPreview` | destination editor, run detail, verify | Redacted by default, revealable, byte count, exportable |
| `BundlePreview` | R-26 | Share affordance exists only after the last line of content |
| `TypeRow` | Data tab | Name, latest value + unit + timestamp, sample count, inclusion indicator; multi-select variant |
| `SampleRow` | type detail | Value, unit, time, source |
| `BucketRow` | type detail | Aggregate value, function name, contributing sample count |
| `VerifyComparison` | S5 | Three-way: Health / exported record / unit note |
| `CoverageTable` | onboarding, coverage review | Three states, never four; "nothing returned" is neutral, not a warning |
| `DiffReview` | selection commit, preset upgrade, unit change | What changes, permission consequence, non-retraction warning |
| `LedgerRow` | egress ledger | Timestamp, destination, transport state, counts, bytes, outcome |
| `ManifestRow` | Mac receipts | Timestamp, source device, types, counts, window, bytes, filename |
| `EmptyState` | every list | Sentence + the action. Never a sentence alone |
| `TerminalScreen` | `isHealthDataAvailable() == false`, unsupported platform | No spinner, no retry, no empty dashboard |
| `DeleteScope` | R-43 | Itemised counts, individually deletable, honest-limits block |
| `WidgetSmall` / `WidgetMedium` / `WidgetAccessory` | R-23 rung 3 | Self-ageing timeline |
| `MenuBarExtra` | Mac | Glyph + age; the Mac's permanent presence |

---

## Open questions for the PM

| # | Question | What I need, and what I'll do without an answer |
|---|---|---|
| **Q1** | **Do you accept unifying the metric picker and the data browser into one Data tab?** | It is the largest IA decision here. It saves a screen, makes selection informative, and puts health data one tap from launch for App Review. The risk is that a list optimised for browsing is worse at bulk selection than a list optimised for selection. Absent a decision I will build it unified with an explicit Select mode, and I would want the comprehension test in R-61's verification extended to cover both jobs |
| **Q2** | **Does `success_nothing_due` reset the freshness clock?** | I have designed two clocks — last successful *check* and last record *delivered* — with R-23's watchdog armed from the check clock and `Quiet` derived from the delivered one. This changes what R-23's soak test asserts, so it needs ratifying rather than assuming. The alternative (arm from delivered) produces false alarms for anyone with a quiet week; the naive alternative (arm from check only, no second clock) hides a destination that has silently stopped accepting writes |
| **Q3** | **What is N_floor before R-71 lands?** | R-24 says the freshness target N is a stated number derived from R-71's measurement. R-71 is a Stage 2 spike. I need a shipped default now to write the copy, and 6 hours is Stage 1's labelled assumption. If R-71 comes back saying background wakes are rarer than that, N_floor rises and every string containing "24 hours" changes. I would rather the number live in one place with a named owner than be threaded through copy |
| **Q4** | **Should R-43's delete-everything fire a notification?** | My §7 invariant 3 says yes, so that an abuser cannot quietly scrub the record. The cost is one notification to a legitimate user doing a legitimate thing on their own device. I think it is clearly worth it, but it is an addition to R-43 rather than a reading of it |
| **Q5** | **Who reviews the "If someone else set this up" screen?** | I have written factual copy and deliberately included no external link, on the grounds that a link would appear in browsing history. Both of those are judgement calls in a domain I am not qualified in. This should be read by someone who works on technology-facilitated abuse before it ships, and I would rather that be a named commitment than a good intention |
| **Q6** | **Watchdog notification interruption level: Active or Time Sensitive?** | I have chosen Active for the watchdog and Time Sensitive for R-40, on HIG's own reasoning about what Time Sensitive is for. The counter-argument is that a quiet export is exactly what a self-hoster wants to break through a Focus. Getting this wrong in the loud direction is how people turn the channel off entirely |
| **Q7** | **Does the Mac companion render received health values?** | I have said no, and given three reasons. It is the scope call most likely to be reversed in Stage 3 by someone reasonably observing that the data is right there in a file |
| **Q8** | **Are Metric Sets in v1, or is selection purely per-destination?** | SEC-16 wants per-destination minimisation with a default of zero types; five destination types means five selections. Without a reusable object that is 5 × 150 decisions. With one it is a library, versioning, forking and diffing. I have designed the library and marked fork/version machinery as Should, but this is a real cost line and it is not in §7.1's estimate as a distinct item |
| **Q9** | **Which Accessibility Nutrition Labels do we commit to at v1?** | I have proposed seven, including Differentiate Without Color Alone, which maps directly onto R-64. Claiming a label requires that *all common tasks* be completable with that feature, which is a stronger commitment than "we support VoiceOver". Under-claiming is safe and invisible; over-claiming is a credibility failure in exactly the domain we are selling |
| **Q10** | **Is the no-alternate-app-icons prohibition (§7, invariant 4) ratified as a permanent Won't?** | It is a natural consequence of R-41 but it is not written down anywhere, and it is exactly the kind of small, harmless-looking feature request ("let me pick a different icon") that arrives in year two with no context attached |
| **Q11** | **Is there a supportable deep link into Health → Privacy → Apps?** | Carried over from Stage 1 Q6 and still open. S2.8-empty, the coverage review, S11 and three error archetypes all send people there. Text instructions are the guaranteed path and I have written them that way; a supported link would materially improve four flows |
| **Q12** | **Is the Mac companion's own quiet-alarm a Must or a Should?** | The observability design has it as a Should; I have designed it into the receiver's core. It is the only out-of-band witness we have — a second device that notices the first one has gone silent — and it costs a stored timestamp and a local notification. If it is a Should, the Mac receiver ships without the one property that distinguishes it from a folder |

---

## Sources

[^privacy]: Apple — *Human Interface Guidelines: Privacy*. Pre-alert screens: "Include only one button and make it clear that it opens the system alert… Use a term like 'Continue' or 'Next'"; "Don't include additional actions in your custom screen or window. For example, don't provide a way for people to leave the screen or window without viewing the system alert." Also "Request access only to data that you actually need." <https://developer.apple.com/design/human-interface-guidelines/privacy>

[^glass]: Apple — *Adopting Liquid Glass*, Technology Overviews. "Liquid Glass applies to the topmost layer of the interface, where you define your navigation… Ensure that you clearly separate your content from navigation elements, like tab bars and sidebars, to establish a distinct functional layer above the content layer." <https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass>

[^materials]: Apple — *Human Interface Guidelines: Materials*. Liquid Glass in the content layer "can result in unnecessary complexity and a confusing visual hierarchy"; use standard materials for content-layer elements; the regular variant "blurs and adjusts the luminosity of background content to maintain legibility"; variants respond to Reduce Transparency and Increase Contrast. <https://developer.apple.com/design/human-interface-guidelines/materials>

[^tabbars]: Apple — *Human Interface Guidelines: Tab bars* (updated 8 June 2026). Overflow "More" tabs make content harder to find; don't hide or disable tab bar buttons; in iPadOS the tab bar appears near the top with an optional conversion to a sidebar (`sidebarAdaptable`); in iOS the tab bar floats on Liquid Glass and can minimise on scroll. <https://developer.apple.com/design/human-interface-guidelines/tab-bars>

[^widgets]: Apple — *Human Interface Guidelines: Widgets*. Home Screen appearances (light, dark, clear, tinted); clear and tinted desaturate content; `fullColor` / `accented` / `vibrant` rendering modes and the per-platform table; Lock Screen widgets are monochromatic without a tint colour; Mac desktop widgets use full-colour and vibrant; "Convey meaning without relying on specific colors to represent information." <https://developer.apple.com/design/human-interface-guidelines/widgets>

[^notifications]: Apple — *Human Interface Guidelines: Managing notifications*. The four interruption levels and their behaviours; "Use the Time Sensitive interruption level only for notifications that are relevant in the moment… an event that's happening now or will happen within an hour"; Critical requires an entitlement. <https://developer.apple.com/design/human-interface-guidelines/managing-notifications>

[^notifprompt]: Apple — *Asking permission to use notifications* (UserNotifications). Provisional authorisation is granted without a prompt and delivers quietly to Notification Center with keep/turn-off controls. <https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications>

[^liveactivities]: Apple — *Human Interface Guidelines: Live Activities*. "Offer Live Activities for tasks and events that have a defined beginning and end… that don't exceed eight hours"; "Always end a Live Activity immediately when the task or event ends, and consider setting a custom dismissal time… In most cases, 15 to 30 minutes is adequate"; after ending, it remains up to four hours on the Lock Screen, in the Mac menu bar and the watchOS Smart Stack. <https://developer.apple.com/design/human-interface-guidelines/live-activities>

[^a11y]: Apple — *Human Interface Guidelines: Accessibility*. WCAG Level AA contrast values used by Accessibility Inspector (4.5:1; 3:1 at 18 pt or bold); "Convey information with more than color alone"; iOS minimum control size 44×44 pt with ~12 pt padding around bezelled elements; Reduce Motion guidance. <https://developer.apple.com/design/human-interface-guidelines/accessibility>

[^voiceover]: Apple — *Human Interface Guidelines: VoiceOver*. <https://developer.apple.com/design/human-interface-guidelines/voiceover>

[^typography]: Apple — *Human Interface Guidelines: Typography* (Dynamic Type guidance, moved here from the Accessibility page in March 2025). <https://developer.apple.com/design/human-interface-guidelines/typography>

[^ant]: Apple — *Prepare your app for Accessibility Nutrition Labels*, Tech Talk 111433. Default Dynamic Type range 100–135%; accessibility sizes to 310%; "To add Larger Text support… make sure that your app works well up to a minimum of 200%." Nine claimable features including Differentiate Without Color Alone. <https://developer.apple.com/videos/play/tech-talks/111433/>

[^ant2]: Apple — *Overview of Accessibility Nutrition Labels*, App Store Connect Help. Labels appear on devices running iOS/iPadOS/macOS/watchOS/visionOS 26 or later; to claim a feature, "users must be able to complete all of the common tasks of your app using that feature." <https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels/>

[^macos]: Apple — *Human Interface Guidelines: Designing for macOS*. Menu bar, window management, keyboard-driven work styles, 1–3 ft viewing distance. <https://developer.apple.com/design/human-interface-guidelines/designing-for-macos>

[^menubar]: Apple — *Human Interface Guidelines: The menu bar*. <https://developer.apple.com/design/human-interface-guidelines/the-menu-bar>

[^lnp]: Apple — *TN3179: Understanding local network privacy*. The local-network prompt is triggered by outbound traffic, not by an API; `NSLocalNetworkUsageDescription` and declared `NSBonjourServices` are required; local network privacy tracks program identity by code signature. <https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy>

[^wcag]: W3C — *Web Content Accessibility Guidelines (WCAG) 2.2*. SC 1.4.1 Use of Color (A), SC 1.4.3 Contrast Minimum (AA, 4.5:1 / 3:1 large), SC 1.4.4 Resize Text (AA), SC 1.4.11 Non-text Contrast (AA). <https://www.w3.org/TR/WCAG22/> · <https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum>

[^healthkit]: Apple — *Authorizing access to health data* (HealthKit). An app "cannot determine whether or not a user has granted permission to read data"; denial "simply appears as if there is no data of the requested type"; `getEarliestAuthorizedSampleDate(for:)` is the only positively detectable restriction. <https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data>

[^lock]: Apple — *Protecting access to user's health data*, Apple Platform Security (published 2026-01-28). "This data is stored in the Data Protection class Protected Unless Open. Access to the data is relinquished 10 minutes after the device locks." <https://support.apple.com/guide/security/protecting-access-to-users-health-data-sec88be9900f/web>

[^review]: Apple — *App Store Review Guidelines* §5.1.3 Health and Health Research. <https://developer.apple.com/app-store/review/guidelines/#5.1.3>

---

## Labelled assumptions

- **A1.** N_floor = 6 hours until R-71 reports. Every string containing a threshold derives from
  one constant and changes together.
- **A2.** Staleness at max(2·F, 90 min) and overdue at max(4·F, N_floor) are Stage 1's untested
  defaults, carried forward unchanged and expected to move after R-71.
- **A3.** The Core Daily set of ~24 types produces a non-empty first export for the large majority
  of users. Validate on real devices in Stage 4 (R-87's device pass is the natural place).
- **A4.** History retention default of 90 days or 1,000 runs, whichever is larger.
- **A5.** MQTT test-time delivery confirmation by subscribing to our own publish topic works
  against the common brokers. Needs confirming against R-90's real-broker integration test — if a
  broker declines to redistribute a client's own publication, the MQTT test's final step degrades
  to `Sent, unconfirmed` and the copy in §9 changes.
- **A6.** A six-digit short authentication string displayed on both devices is the right pairing
  ceremony for the Mac companion. The security engineer owns the actual construction; I own the
  requirement that both screens show it and both require confirmation.
- **A7.** WidgetKit's reload budget permits a timeline dense enough near the present to keep the
  ageing language accurate without relying on the app running. If it does not, the widget's copy
  becomes coarser ("more than a day ago") rather than the mechanism changing.
