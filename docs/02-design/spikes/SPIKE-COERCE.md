# SPIKE-COERCE — does iOS 18 concealment defeat the watchdog?

**Owner:** product owner (one device, under an hour)
**Blocks:** Stage 2 close, R-23's rung count, R-41 restatement completeness
**Date opened:** 2026-09-03
**Status:** **partial — widget survived, notification delivered.** See `SPIKE-COERCE-results.md`.
No longer blocks Stage 2 close.

Apple's Personal Safety guide already settles that hiding a user-installed app removes it from
the Home Screen and that locking strips notification *previews*. This spike answers the two
questions that guide does not: whether a **widget** survives, and whether a **pre-scheduled
local notification** is delivered after hide, and with what content.

That decides whether R-23's escalation has **one rung or zero** against the T-24 coercer.

## Device

Any iPhone on **iOS 18 or later**. iOS 26 is fine — Hide and Require Face ID shipped in 18 and
is what we need. A developer-signed build of *this* app is not required: any third-party app
that has a Lock Screen or Home Screen widget *and* can schedule a local notification is a valid
proxy, because the behaviour is OS-level. Prefer an app you already have a widget for.

Record: model, iOS version, Face ID vs passcode.

## Setup (5 minutes)

1. Add the app's widget to the **Home Screen** and, if the app provides one, the **Lock Screen**.
2. Grant notification permission. In Settings, set the app's notifications to **Lock Screen,
   Notification Centre, Banners, Sounds, Badges — all on**. Previews: **Always** (or
   When Unlocked — record which).
3. From the app, trigger a **future local notification** 3–5 minutes out, with a body that
   contains a distinctive string (a hostname analogue, e.g. `canary.example`). If you cannot
   schedule from the app, use Shortcuts → Automation is *not* a substitute; we need an
   *app-scheduled* `UNNotificationRequest`. A Calendar alert is also not a substitute.
4. Confirm, before hiding, that:
   - the widget is visible and showing live-looking content;
   - a test notification delivered *now* shows the distinctive body on the Lock Screen.

## Procedure (hide, then wait)

Follow Apple's path, not a long-press hide-from-Home-Screen:

**Settings → Screen Time is not this.** Use:

1. Home Screen → touch and hold the app icon → **Require Face ID** (or **Hide and Require
   Face ID** on iOS 18). Confirm.
2. Observe immediately:
   - [ ] App icon gone from Home Screen?
   - [ ] App still in App Library? In a Hidden folder?
   - [ ] Home Screen widget still present? Still rendering? Blank? Removed?
   - [ ] Lock Screen widget still present? Still rendering? Removed?
3. Lock the device. Wait for the scheduled notification.
4. Without unlocking, observe the Lock Screen:
   - [ ] Notification arrived at all?
   - [ ] Banner / Lock Screen shows the **distinctive body**, a generic "Notification", or
     nothing?
   - [ ] Badge visible anywhere?
5. Unlock. Check Notification Centre for the same three content states.
6. Open **Settings → Apps → Hidden Apps** (Face ID / passcode required). Confirm the app is
   listed. This is the recovery path R-41 must document.
7. Un-hide. Confirm widget and notifications return, and whether the widget had to be **re-added
   by hand**.

## Repeat once with notifications denied

Same hide, but first: Settings → Apps → [app] → Notifications → Off.

- [ ] Widget still present after hide? (This is R-23's "and again with notifications denied".)

## What to write back

Fill this block into `docs/02-design/spikes/SPIKE-COERCE-results.md` (create it):

```
Device / iOS:
Proxy app used (if not ours):
Hide removed Home Screen icon: yes/no
Home Screen widget after hide: present-live / present-blank / removed
Lock Screen widget after hide: present-live / present-blank / removed / n/a
Scheduled notification arrived while hidden: yes/no
Notification content while hidden: full-body / generic / none
Widget after hide + notifications off: present-live / present-blank / removed
Un-hide restored widgets without re-adding: yes/no
Recovery path Hidden Apps listed the app: yes/no
```

## How the design reads the result

| Widget after hide | Notification body after hide | R-23 against a coercer |
|---|---|---|
| present-live | full-body | Three rungs survive; still document OS concealment in R-41 |
| present-live | generic / none | Widget is the only surviving rung; hostname cannot ride the notification |
| removed | full-body | Notification is the only surviving Home-adjacent rung; R-27 becomes load-bearing |
| removed | generic / none | **Zero rungs.** R-27 + ledger-in-Files become the chain. Widget is no longer the reason it is a Must |

Do not "fix" the table in the PRD until this file has numbers. The restatement of R-41 (binary
claim + recovery path) already landed in PRD v1.1 and does not depend on the widget answer.
