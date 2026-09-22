# Stage 3 / 4 remaining

In-scope: code-completable Stage 3 and Stage 4 automated QA.  
Out of scope: device soak (R-71), backup/network-capture, App Store, branding, HACS.

**Stage 3:** proven (`17f6584`).  
**Stage 4:** macos-build 6/6 ios-ui green on `a047513`; not yet proven on `3ceb386`.

---

## Now

HEAD `3ceb386` wrap-without-fixedSize. macos-build [`35749564918`](https://github.com/colinedwardwood/open-health-export/actions/runs/35749564918): darwin-package / ios-build / companion / from-source / release-artifact-scan **green**. ios-ui: **iPad 0 + iPhone 2 green**; iPad 1/2 + iPhone 0/1 **in flight**.

| Next | Status |
|---|---|
| macos-build (6 ios-ui) | 2/6 green · ~10–40 min remaining |
| accessibility-matrix 12/12 | after macos-build green · 60–90 min |
| Local iPhone + iPad UI suites | iPad **77/0** on `a047513`; iPhone on `3ceb386` still running, **1 failed** (privacy-gate title clip) |
| `main` branch protection | last slice only |

Local iPhone `testOptionalPrivacyGateFailsClosed…` **Text clipped** on
`privacy-gate-locked-title` (hug ~246pt). Fix is ready locally; do not push
until hosted ios-ui on `3ceb386` finishes (latest-ref). That test is iPhone shard 0.

Watch XXXL / DarkBold `-56` — no extra code unless it repeats without a DT fail.

---

## Rules

- One pusher on `main` (latest-ref CI cancels in-flight ios-ui).
- Do not watch hosted CI; poll when a run finished or a later slice needs it.
- UI CI stays on GitHub `macos-26`. This Mac / Air / Ubuntu 2015 are local only.

Typical waits: macos-build 50–90 min · matrix 60–90 min · local suites 30–90 min · branch protection 15 min.
