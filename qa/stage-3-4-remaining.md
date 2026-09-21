# Stage 3 / 4 remaining

In-scope: code-completable Stage 3 and Stage 4 automated QA.  
Out of scope: device soak (R-71), backup/network-capture, App Store, branding, HACS.

**Stage 3:** proven (`17f6584`).  
**Stage 4:** not proven — need all 6 `ios-ui` shards + 12-job accessibility matrix green on current HEAD.

---

## Now

Hosted [`35545175003`](https://github.com/colinedwardwood/open-health-export/actions/runs/35545175003) on origin `825c06e`: **iPad 0/1/2 green; iPhone empty + RTL empty Text clipped; iPhone 1 cancelled.** Local empty+detail 84s and RTL empty 47s green after 44pt search field.

| Next | Status |
|---|---|
| Fix Data-tab empty-search clip | local green; push with wrapping stack |
| macos-build (6 ios-ui) | after push |
| accessibility-matrix 12/12 | after macos-build green |
| Local iPhone + iPad UI suites | re-run on proven HEAD |
| `main` branch protection | last slice only |

Watch XXXL launch flake — no extra code unless it repeats.

---

## Rules

- One pusher on `main` (latest-ref CI cancels in-flight ios-ui).
- Do not watch hosted CI; poll when a run finished or a later slice needs it.
- UI CI stays on GitHub `macos-26`. This Mac / Air / Ubuntu 2015 are local only.

Typical waits: push 15–45 min · macos-build 50–90 min · matrix 60–90 min · local suites 30–90 min · branch protection 15 min.
