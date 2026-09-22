# Stage 3 / 4 remaining

In-scope: code-completable Stage 3 and Stage 4 automated QA.  
Out of scope: device soak (R-71), backup/network-capture, App Store, branding, HACS.

**Stage 3:** proven (`17f6584`).  
**Stage 4:** macos-build 6/6 ios-ui green on `a047513`; matrix 11/12 (iPad 5 red).

---

## Now

DatePicker titles hosted as SwiftUI text; Data title uses one scalable body font. Local iPad `testDisclosureAndControlsInPseudoLocale` **33s green**.

| Next | Status |
|---|---|
| macos-build (6 ios-ui) | after this push · 50–90 min |
| accessibility-matrix 12/12 | dispatch after macos-build green |
| Local iPhone + iPad UI suites | iPad **77/0** on `a047513`; iPhone aborted; re-run after this HEAD |
| `main` branch protection | last slice only |

Watch XXXL launch flake — no extra code unless it repeats.

---

## Rules

- One pusher on `main` (latest-ref CI cancels in-flight ios-ui).
- Do not watch hosted CI; poll when a run finished or a later slice needs it.
- UI CI stays on GitHub `macos-26`. This Mac / Air / Ubuntu 2015 are local only.

Typical waits: push 15–45 min · macos-build 50–90 min · matrix 60–90 min · local suites 30–90 min · branch protection 15 min.
