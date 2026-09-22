# Stage 3 / 4 remaining

In-scope: code-completable Stage 3 and Stage 4 automated QA.  
Out of scope: device soak (R-71), backup/network-capture, App Store, branding, HACS.

**Stage 3:** proven (`17f6584`).  
**Stage 4:** macos-build 6/6 ios-ui green on `a047513`; not yet proven on `3ceb386`.

---

## Now

HEAD `3ceb386` on origin. Local `9f697a9`+pseudo-DT suppression **unpushed**. macos-build [`35749564918`](https://github.com/colinedwardwood/open-health-export/actions/runs/35749564918): **iPad 0, iPad 2, iPhone 2 green**; **iPad 1 red** (`testBrowserDetailInPseudoLocale` DT on doubled copy); iPhone 0/1 **in flight**.

| Next | Status |
|---|---|
| macos-build (6 ios-ui) | 3/6 green, iPad 1 red · wait for iPhone 0/1, then push local commits |
| accessibility-matrix 12/12 | after macos-build green on the pushed SHA · 60–90 min |
| Local iPhone + iPad UI suites | iPad **77/0** on `a047513`; iPhone on `3ceb386` still running, **1 failed** (privacy-gate title clip; fix in `9f697a9`) |
| `main` branch protection | last slice only |

Do not push until remaining ios-ui jobs finish (latest-ref).

---

## Rules

- One pusher on `main` (latest-ref CI cancels in-flight ios-ui).
- Do not watch hosted CI; poll when a run finished or a later slice needs it.
- UI CI stays on GitHub `macos-26`. This Mac / Air / Ubuntu 2015 are local only.

Typical waits: macos-build 50–90 min · matrix 60–90 min · local suites 30–90 min · branch protection 15 min.
