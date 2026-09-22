# Stage 3 / 4 remaining

In-scope: code-completable Stage 3 and Stage 4 automated QA.  
Out of scope: device soak (R-71), backup/network-capture, App Store, branding, HACS.

**Stage 3:** proven (`17f6584`).  
**Stage 4:** macos-build 6/6 ios-ui green on `a047513`; not proven on `6ca0a71`.

---

## Now

macos-build [`35741241924`](https://github.com/colinedwardwood/open-health-export/actions/runs/35741241924) **failed**: iPad 1 `testBrowserDetailInPseudoLocale` DT (Latest / Load Health); iPad 2 `browser-select` DT (demo honesty / MQTT) and DarkBold `-56`. Local Xcode 27 still green.

| Next | Status |
|---|---|
| Push wrap-without-fixedSize | after local iPad detail+select |
| macos-build (6 ios-ui) | after push · 50–90 min |
| accessibility-matrix 12/12 | after macos-build green |
| Local iPhone + iPad UI suites | iPad **77/0** on `a047513`; iPhone aborted |
| `main` branch protection | last slice only |

Watch XXXL / DarkBold `-56` — no extra code unless it repeats without a DT fail.

---

## Rules

- One pusher on `main` (latest-ref CI cancels in-flight ios-ui).
- Do not watch hosted CI; poll when a run finished or a later slice needs it.
- UI CI stays on GitHub `macos-26`. This Mac / Air / Ubuntu 2015 are local only.

Typical waits: push 15–45 min · macos-build 50–90 min · matrix 60–90 min · local suites 30–90 min · branch protection 15 min.
