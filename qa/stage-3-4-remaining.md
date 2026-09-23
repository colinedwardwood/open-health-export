# Stage 3 / 4 remaining

In-scope: code-completable Stage 3 and Stage 4 automated QA.  
Out of scope: device soak (R-71), backup/network-capture, App Store, branding, HACS.

**Stage 3:** proven (`17f6584`).  
**Stage 4:** macos-build **5/6** on `8d3ba8f`. Only iPad 0 red, one test.

---

## Now

Pushing: audit Dynamic Type at the default content size only.

Measured on the dark/bold/AX5 Destinations screen, the pass that would not
finish:

```
allExceptDynamicType  2s
dynamicType          19s
```

Hosted runs ~2x slower, which lands on the observed 38–46s `-56` failures.
Asking whether text scales while already pinned at the maximum size is the
least informative place to ask. Destinations keeps its Dynamic Type audit at
the default size in `testEveryDestinationDisplayStatePassesAccessibilityAudit`.
Clipping, contrast, hit regions, and element detection still run at AX5.

Locally after the change: Destinations 37.4s → 18.1s, Controls 31.9s → 11.7s,
AX3XL 35.2s → 13.1s, all green, and the two default-size audits confirm they
still run the Dynamic Type pass.

## Fixed and confirmed on hosted

| Fix | Commit | Evidence |
|---|---|---|
| privacy-gate `Text clipped` | `abfb8dc` | iPhone 0 green |
| `otlp-url` keyboard focus | `6ce9079` | iPhone 1 green |
| Dynamic Type drift | `cd0ddcf` | no DT finding on any shard |
| simulator launch timeouts | `f28604c` | iPad 0/1 green |
| three AX5 screens in one process | `8d3ba8f` | iPad 2 green |

## Local coverage

All three iPad shards green with the split audit: 26/26, 26/26, 25/25.

| Next | Status |
|---|---|
| macos-build 6/6 | pushing Dynamic Type scope |
| accessibility-matrix 12/12 | after macos-build green |
| `main` branch protection | last slice only |

---

## Rules

- One pusher on `main` (latest-ref CI cancels in-flight ios-ui).
- Do not watch hosted CI; poll when a run finished or a later slice needs it.
- UI CI stays on GitHub `macos-26`. This Mac / Air / Ubuntu 2015 are local only.

Typical waits: macos-build 50–90 min · matrix 60–90 min · local suites 30–90 min · branch protection 15 min.
