# Brand guide

**Status:** Living document. It is the single source for names, colour, type, icon and voice.
**Date:** 2026-09-29
**Applies to:** the iOS app, the widget, the App Store listing, the landing page, and anyone designing for the product.

Where this guide and the code disagree, the code is being fixed; tell us. The files that implement each section are named in it.

## 1. Names

| Use | Text | Where it is set |
|---|---|---|
| Product and App Store name | **KeepMyMetrics** (one word, capital K, M, M) | `Brand.xcconfig` `PRODUCT_NAME`, `STORE_NAME`; `store/en/name.txt` |
| Home-screen label and in-app name | **Keep Metrics** (12 characters, so it never truncates) | `Brand.xcconfig` `DISPLAY_NAME` |
| App Store subtitle | **Your vitals, on your server** (proposed; awaiting owner confirmation) | `store/en/subtitle.txt` |
| Bundle identifier root | `com.cewdesign.exporter` (never shown to people) | `Brand.xcconfig` |

Rules:

- `Brand.xcconfig` is the only file that may contain the product name. Code reads it through `ProductName.display`. Copy that needs the name uses that value, never a literal.
- Write "KeepMyMetrics" in store and web copy. Write "Keep Metrics" where iOS shows the app, e.g. "Settings → Apps → Keep Metrics".
- Never abbreviate it to "KMM", and never write "Keep My Metrics" as three words.
- The name is pending legal clearance (#22), in particular against the registered "keep metrics®" mark. Don't print it on anything expensive until that closes.

## 2. Positioning

**One line:** your Apple Health data, delivered automatically to places you own: files, Home Assistant, MQTT, or your own server.

**What makes it different, in order of weight:**

1. **Ownership.** There is no account, no cloud of ours, and we never see the data. It goes from the phone to the destination the person set up.
2. **It keeps running.** Background exports, catch-up when the app opens, and late-arriving readings are still picked up.
3. **It tells you when something's wrong.** If a destination stops answering, the app says which one and what to do.

**Who it is for:** self-hosters, Home Assistant users, quantified-self people and developers. They are technical, allergic to hype, and pay for tools that are quiet and dependable.

**Business model:** a free download with manual export to every destination. A one-time US$14.99 unlock adds automatic exports (D-08a, D-08b). There is no subscription, and security notices and updates are never locked.

## 3. Colour

The app uses the iOS system palette for everything except one accent. Status colours keep their iOS meanings.

### 3.1 Palette

| Token | Light | Dark | Use |
|---|---|---|---|
| **Accent** | `#0F766E` deep teal | `#2DD4BF` bright teal | Tint: buttons, links, the selected tab, toggles' tint where not status |
| **Status: ok** | `#248A3D` | `#30D158` | "Up to date" glyphs |
| **Status: attention** | `#C93400` | `#FF9F0A` | Overdue, stale, partial, unconfirmed |
| **Status: blocked** | `#D70015` | `#FF453A` | Failing, or waiting for the person |
| **Status: neutral** | system `.secondary` | system `.secondary` | Not set up, paused, waiting on iOS |
| **Brand coral** | `#FF6B5E` | `#FF6B5E` | Icon and marketing only (see 3.3) |

Everything else (backgrounds, text, separators, grouped cards) uses iOS semantic colours: `.background`, `.secondarySystemGroupedBackground`, `.primary`, `.secondary` and `.separator`. We don't hard-code a hex value for them.

The light status values are Apple's increased-contrast variants; the dark values are the standard dark-mode system colours.

**Implemented in:**
- `Apps/AppShared/Theme.xcassets`, where the accent is `AccentColor` and the status colours are `StatusOK`, `StatusAttention` and `StatusBlocked`;
- `Apps/AppShared/Theme.swift`, which maps each tone to a colour;
- `StatusTone` in `Sources/Watchdog/DestinationSnapshot.swift`, which maps each state to a tone.

### 3.2 Measured contrast (WCAG 2.x)

| Colour | On white | On grouped `#F2F2F7` | Dark: on card `#1C1C1E` | Dark: on black |
|---|---|---|---|---|
| Accent | 5.5 | 4.9 | 9.1 | 11.3 |
| Ok | 4.4 | 3.9 | 8.4 | 10.4 |
| Attention | 5.3 | 4.7 | 8.3 | 10.2 |
| Blocked | 5.4 | 4.8 | 5.0 | 6.2 |
| Coral | 2.8 | 2.5 | 6.1 | 7.5 |

White text on the accent measures 5.5:1.

What follows from the numbers:

- Every status colour clears 3:1 in both appearances, so it's fine for **glyphs and large text**.
- **Ok green is 4.4:1 on white, so it is not for body text.**
- **Status words are written in `.primary` or `.secondary`,** and colour only reinforces the glyph beside them.
- **Coral is never used for text or UI in light mode.** At 2.8:1 on white, it fails even the 3:1 bar.

### 3.3 Colour rules

1. **Colour is never the only signal.** Every state has a distinct SF Symbol silhouette and a text label (UX-41). The widget and the app use the same glyph for the same state.
2. **One accent.** Don't introduce a second brand colour into the app UI. Coral belongs to the icon and marketing.
3. **No Health pink or red as a brand colour.** Red means "blocked" and nothing else.
4. **Coral on teal is only 2.0:1** (the two colours are almost the same brightness). Wherever they touch, as in a coral heart on a teal icon, separate them with luminance: a white outline, a much darker teal, or a lighter coral. Otherwise the mark disappears in the tinted icon and for colour-blind viewers.
5. **Both appearances are required.** Each screen is designed and checked in light and dark mode. The app follows the phone's setting and never forces an appearance.

## 4. Type

- **In the app: SF Pro, the system font, only.** No custom fonts: they fight Dynamic Type and accessibility, and a calm utility doesn't need them.
- **All text uses Dynamic Type styles and scales to the largest accessibility sizes.** Never set a fixed point size for text.

| Role | Style | Notes |
|---|---|---|
| Screen title | `.largeTitle` (the navigation title) | Standard large title, collapsing on scroll |
| Status headline | `.title2` or `.title`, bold | The plain sentence at the top of Status, e.g. "Two of three destinations are up to date." |
| Section title | `.headline` + `.isHeader` | Use `SectionTitle`; never style a heading by hand |
| Row title | `.body` | |
| Metadata | `.subheadline`, `.secondary`, monospaced digits | Use `.metadata()`: timestamps, counts, where data went |
| Footnotes and legal | `.footnote`, `.secondary` | |

- **Numbers that update** (counts, times, sizes) use `.monospacedDigit()`, so they don't jitter.
- **Units** are formatted with Foundation formatters: "3.6 MB", "37.2 °C", "2 Jan, 14:03", never raw bytes or ISO timestamps.

**Implemented in:** `Apps/Exporter-iOS/Shell/Styles.swift`.

**The web** (landing page, docs site) uses the system stack `-apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif`. Where SF isn't available, Inter is an acceptable fallback. The web uses the same accent colours as the app.

## 5. Layout and components

- **Native first.** Use inset-grouped lists, standard navigation stacks, a tab bar (Status, Data, Destinations, History) and system controls. The product earns trust by looking like it belongs on iOS.
- **Status screen pattern** (from the approved mockups):
  - a plain-sentence headline that says what's going on;
  - below it, one secondary line with the detail;
  - if something needs the person, a single button that goes straight to the fix ("Check Mosquitto").
- **Attention cards** sit inside the list (`.attentionCard(_:)`), so they scroll with the content and can never cover the navigation title.
- **Destination detail** shows a 24-hour delivery strip (one cell per hour: delivered, nothing new, couldn't deliver), plus a legend in words.
- **Touch targets** are at least 44 × 44 pt.
- **Motion** uses system transitions only, and respects Reduce Motion.

**Mockups:** the design canvas "KeepMyMetrics iOS design" has eight screens in light and dark:
- welcome;
- choose data;
- add destination;
- Status (all good);
- Status (overdue);
- destination detail;
- History;
- Settings.

## 6. App icon

**Idea:** health data flowing out to several places the person owns. A heart is the anchor, so people link the app with Apple Health. Several outgoing lines, arrows or nodes show that the data goes to more than one destination.

**Must:**
- Be clearly the product's own mark in its own colours: teal, with a white or coral heart.
- Read at 29 pt and 20 pt. Use at most 2–3 elements and no fine lines.
- Be supplied as 1024 × 1024 full-bleed artwork (no pre-rounded corners), in light, dark and tinted variants. Supply Icon Composer layers for iOS 26 when the final icon is produced.
- Stay recognisable in greyscale. Check luminance, not only hue (see 3.3 rule 4).

**Must not:**
- Resemble Apple's Health icon or any Apple icon. That means no pink or red heart on white, no Activity rings, and no Apple logo; App Review guideline 5.2.5 rejects look-alikes.
- Use medical imagery (a cross, stethoscope, heartbeat line or pills). The app is not a medical device.
- Contain text.
- Look like Health Auto Export's red heart with an arrow when shown in a greyscale grid.

**The icon (owner choice, 2026-10-01):**
- **Left half:** a heart drawn as three nested strokes, coral, white and bright teal from outside in.
- **Right half:** three white arrows fanning out from the heart's point, where the right half of the heart would be.
- **Background:** deep teal `#0F766E`, as a system-derived gradient.
- **Dark appearance:** the same mark on `#0B1514`.
- **Tinted and clear appearances:** rendered by the system from the layers.

The white strand gives the heart its luminance edge (rule 3.3.4).

**Source:** `Apps/Icon/AppIcon.icon` is a layered Icon Composer file, shared by the iPhone app and the Mac companion.
- **Layers:** the arrows are the front group, and the three heart strands are the back group.
- **Fallbacks:** Xcode generates the flat icons for iOS 18 and the `.icns` for macOS 15 from it.
- **Editing:** change `Apps/Icon/generate.py` and run it, rather than editing the bundle by hand. Preview the glass rendering by opening the `.icon` in Icon Composer.
- **Licence:** the artwork will be licensed separately from the code (#90).

## 7. Voice and tone

**Plain, calm, precise.** Write like a careful engineer explaining something to a friend.

1. **Say what happened, with numbers.** "We sent 312 records to Home Assistant at 09:14." Not "Sync complete!"
2. **Be honest about limits once, where it matters.** iOS decides when background work runs, so say that where it affects the person, and don't repeat it everywhere.
3. **Don't overclaim.** Queued data can be dropped if the queue fills (R-09), so say "queued and will send when it's back", not "nothing is lost". Background delivery is best-effort, so never promise a time.
4. **Lead with the fix.** An error gives the cause in one sentence and the next step as a button.
5. **No jargon in primary copy.** "Page", "anchor", "tombstone", "scope", "ledger", "egress" and requirement IDs (R-, SEC-, UX-) can appear under Details, not on the main screens. The glossary is: export, destination, archive folder, run.
6. **No hype, no emoji, no exclamation marks.** No "revolutionary", "seamless" or "unlock your potential".
7. **Never make medical or clinical claims.** First run, About, the store listing and the website all say: "This is not a medical device. It does not diagnose or treat anything."
8. **Sentence case** for titles and buttons: "Export now", "Add destination".

| Instead of | Write |
|---|---|
| "Sync complete!" | "Sent 1,204 records to Files, 12 minutes ago." |
| "Error: destinationUnreachable" | "Mosquitto didn't answer. Check that the broker is running, then tap Test connection." |
| "Nothing is lost." | "312 records are queued and will send, oldest first, when it's back." |
| "Export one page" | "Export now" |
| "I understand — continue" | "Continue" |
| "Your data is 100% secure" | "Data goes straight from this iPhone to the destination you set up. We never see it." |

## 8. Open items

| Item | Owner | Tracking |
|---|---|---|
| Legal clearance of the name | Owner and counsel | #22 |
| Confirm the subtitle "Your vitals, on your server" | Owner | — |
| Separate licence for the icon and artwork; trademark policy | Owner and counsel | #90 |
| Register `keepmymetrics.com` / `.app` | Owner | — |
| Rewrite the store copy in this voice (the current description predates it) | Engineering | #53 |
