# Stage 3 / 4 remaining

In-scope: code-completable Stage 3 and Stage 4 automated QA.  
Out of scope: device soak (R-71), backup/network-capture, App Store, branding, HACS.

**Stage 3:** proven (`17f6584`).  
**Stage 4:** macos-build 6/6 ios-ui green on `a047513`; not proven on `3ceb386`.

---

## Now

macos-build [`35749564918`](https://github.com/colinedwardwood/open-health-export/actions/runs/35749564918) **failed** (4/6 ios-ui): iPad 1 pseudo-detail DT; iPhone 0 privacy-gate Text clipped. iPad 0/2 and iPhone 1/2 **green**.

Pushing `9f697a9` (privacy lock full width) + `8138b11` (name pseudo-detail DT). Next macos-build ~50–90 min, then matrix.

| Next | Status |
|---|---|
| macos-build (6 ios-ui) | pushing now |
| accessibility-matrix 12/12 | after macos-build green |
| Local iPhone + iPad UI suites | iPad **77/0** on `a047513`; iPhone on `3ceb386` still running, **1 failed** |
| `main` branch protection | last slice only |

---

## Rules

- One pusher on `main` (latest-ref CI cancels in-flight ios-ui).
- Do not watch hosted CI; poll when a run finished or a later slice needs it.
- UI CI stays on GitHub `macos-26`. This Mac / Air / Ubuntu 2015 are local only.

Typical waits: macos-build 50–90 min · matrix 60–90 min · local suites 30–90 min · branch protection 15 min.
