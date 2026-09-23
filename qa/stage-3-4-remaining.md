# Stage 3 / 4 remaining

In-scope: code-completable Stage 3 and Stage 4 automated QA.  
Out of scope: device soak (R-71), backup/network-capture, App Store, branding, HACS.

**Stage 3:** proven (`17f6584`).  
**Stage 4:** macos-build **5/6** on `f28604c`. Only iPad 2 red.

---

## Now

[`35880413239`](https://github.com/colinedwardwood/open-health-export/actions/runs/35880413239) on `f28604c`: iPhone 0/1/2 and iPad 0/1 **green**, iPad 2 red.

**Every Dynamic Type finding is gone**, on every shard. So are the launch
timeouts and termination failures. Splitting the Dynamic Type audit into its
own pass and booting the simulator before xcodebuild fixed both classes.

iPad 2's only remaining failure is audit `-56` "failed to complete in time":
`testDarkBoldAX5AccessibilitySettingsPassAudit` on both iterations (82s, 84s),
and `testBrowserDetailInRTL` once, which then passed on retry.

Pushing now: that test audited three screens in one process, so the third
inherited the cost of the first two. It is now three cases, one screen each,
with no audit removed. Locally 11.7s + 30.7s + 37.5s, all green.

## Fixed and confirmed on hosted

| Fix | Commit | Evidence |
|---|---|---|
| privacy-gate `Text clipped` | `abfb8dc` | iPhone 0 green, twice |
| `otlp-url` keyboard focus | `6ce9079` | iPhone 1 green |
| Dynamic Type drift | `cd0ddcf` | no DT finding on any shard |
| simulator launch timeouts | `f28604c` | iPad 0/1 green |

## Local coverage with the split audit

All three iPad shards green: 26/26, 26/26, 25/25 — 77 tests, no findings.

| Next | Status |
|---|---|
| macos-build 6/6 | pushing DarkBold split |
| accessibility-matrix 12/12 | after macos-build green |
| `main` branch protection | last slice only |

---

## Rules

- One pusher on `main` (latest-ref CI cancels in-flight ios-ui).
- Do not watch hosted CI; poll when a run finished or a later slice needs it.
- UI CI stays on GitHub `macos-26`. This Mac / Air / Ubuntu 2015 are local only.

Typical waits: macos-build 50–90 min · matrix 60–90 min · local suites 30–90 min · branch protection 15 min.
