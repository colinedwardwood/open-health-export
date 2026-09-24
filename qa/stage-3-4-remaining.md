# What's next after reopen

Read this first. Stage 3 and Stage 4 **automated** work is complete. Do not
reopen hosted UI-audit hunting unless a new run is actually red.

**Stopped 24 Sep 2026.** Head `ebc9bbc` on `main`. Working tree was clean.
Colin is quitting Cursor, clearing cache, and restarting the Mac. This file
is the durable handoff.

## Proven

- Stage 3: `17f6584`.
- macos-build [`35899467284`](https://github.com/colinedwardwood/open-health-export/actions/runs/35899467284) on `960d4b7`: **6/6 ios-ui**, workflow green.
- accessibility-matrix [`35920493866`](https://github.com/colinedwardwood/open-health-export/actions/runs/35920493866) on `960d4b7`: **12/12**.
- Evidence recorded at `ebc9bbc`.
- `main` **is protected**: 23 PR-time checks, 1 approval, last-push approval,
  stale-review dismissal, admin enforcement, linear history, conversation
  resolution, no force-push, no deletion.

Required PR checks (do not add nightly volume or the 12 matrix jobs here —
those are not pull_request jobs):

```
licence-headers, export-core, darwin-package, ios-build,
ios-ui (0|1|2, iPhone|iPad), from-source, mac-companion,
release-artifact-scan, focused-coverage, mosquitto,
home-assistant-current, home-assistant-oldest, otlp-http,
gitleaks, signed-off-by,
utc-fixed-offset (ubuntu-latest, true),
utc-fixed-offset (ubuntu-24.04-arm, true),
utc-fixed-offset (macos-26, false)
```

## First actions on reopen

1. `git fetch && git status` — expect `main` matching `origin/main` at
   `ebc9bbc` or a later merge. Direct `git push origin main` will now fail
   for everyone, including admins, unless they use a PR.
2. If `ebc9bbc` started workflows, poll them; do not pile another `main`
   push while `ios-ui` is in flight (latest-ref concurrency cancels them).
3. Pick **one** non-automated gate from the list below. Do not invent a new
   UI-audit campaign.

## Next work (in-scope but not CI-completable)

Index: `qa/non-automated-verification.md`.

| Priority | Gate | Why next |
|---|---|---|
| 1 | Device pass / R-87 / QA-34 | Real HealthKit store; two years + three source classes. Templated under `qa/device-pass/`. |
| 2 | Encrypted backup / SEC-30 / R-33 | Protocol in `qa/encrypted-backup/PROTOCOL.md`. CI only checks exclusion attributes. |
| 3 | Energy / QA-25 | `qa/energy-protocol.md` on named hardware. |
| 4 | R-71 soak | Five-week value-free wake diary. Out of this project's code path. |
| 5 | App Store, branding, HACS | External product gates. Never claim them from this repo's CI. |

Community matrix (`qa/community-device-matrix/`) is optional coverage, not a
substitute for R-71 or maintainer hardware.

## Operating rules that still apply

- One pusher on `main` **via PR** now. Direct pushes are blocked.
- UI CI stays on GitHub `macos-26`. This Mac, the Air (`10.9.9.3`), and
  Ubuntu 2015 (`10.9.9.24`) are local executors only (QA-28 / R-85).
- Do not watch hosted CI continuously; poll when a run finishes.
- Hosted Xcode is **26.6**; this Mac is Xcode **27**. Dynamic Type findings
  on hosted 26.6 at accessibility content sizes were scoped: that pass runs
  at default size only. Do not undo `960d4b7` without a new hosted failure.
- `gh run view --log-failed` lies while sibling jobs run. Use
  `gh api --allow-escape-sequences repos/colinedwardwood/open-health-export/actions/jobs/<id>/logs`.
- DCO: `git commit -s`. Changelog: `changes/unreleased/*.md`. R-113
  medical-claim denylist still trips on words like "treat".

## Do not restart

The following were already chased to green. Re-opening them without a new
red hosted job wastes a CI cycle:

- privacy-gate clip (`abfb8dc`)
- `otlp-url` keyboard focus (`6ce9079`)
- split Dynamic Type audit (`cd0ddcf`)
- `simctl boot` before xcodebuild (`f28604c`)
- DarkBold AX5 split into three cases (`8d3ba8f`)
- skip Dynamic Type at accessibility sizes (`960d4b7`)

Prior conversation: [Stage 3/4 remaining](0c8dfa83-5e8a-4fdf-b63d-9f1fd93475df).
