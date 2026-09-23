# Stage 3 / 4 remaining

In-scope: code-completable Stage 3 and Stage 4 automated QA.  
Out of scope: device soak (R-71), backup/network-capture, App Store, branding, HACS.

**Stage 3:** proven (`17f6584`).  
**Stage 4:** macos-build 6/6 ios-ui green on `a047513`; not proven since.

---

## Now

[`35863237805`](https://github.com/colinedwardwood/open-health-export/actions/runs/35863237805) on `abfb8dc`: 3/6. iPhone 0, iPhone 2, iPad 1 **green**.

| Shard | Cause | State |
|---|---|---|
| iPhone 0 | privacy-gate `Text clipped` | **fixed** in `abfb8dc`, hosted green |
| iPhone 1 | `otlp-url` never took keyboard focus | fix pushed, 9/9 locally |
| iPad 0, iPad 2 | Dynamic Type "partially unsupported" | **open — see below** |

The `-56` audit timeouts did not recur on `abfb8dc`.

## The open question: hosted Dynamic Type

Hosted Xcode 26.6 reports Dynamic Type on elements that are correct:
`scope-destination-*` are `Button` + `HarnessButtonStyle`, which is `.font(.body)`
and `minHeight: 44` — a scaling font and a floor, not a fixed height.
`browser-title` and `Export unit: bpm` are plain `.font(.body)` captions.

The findings **drift between runs**, which is the reason not to keep chasing them:

| Run | iPad 0 | iPad 1 | iPad 2 |
|---|---|---|---|
| `3ceb386` | green | DT | green |
| `8b6ce46` | `-56` | green | green |
| `abfb8dc` | DT | green | DT |

Audits also run 91–206s on the failing shards, and the same screens pass
locally on Xcode 27 in ~33s. That points at audit execution under runner
contention, not at the app. `wrappingPrimaryCaption` already carries a note
that hosted 26.6 reports Dynamic Type spuriously when `fixedSize` is applied.

Chasing this element-by-element has not converged over three runs at ~60 min
each. Needs a decision before more cycles are spent.

| Next | Status |
|---|---|
| Dynamic Type approach | **awaiting decision** |
| accessibility-matrix 12/12 | after macos-build green |
| `main` branch protection | last slice only |

---

## Rules

- One pusher on `main` (latest-ref CI cancels in-flight ios-ui).
- Do not watch hosted CI; poll when a run finished or a later slice needs it.
- UI CI stays on GitHub `macos-26`. This Mac / Air / Ubuntu 2015 are local only.

Typical waits: macos-build 50–90 min · matrix 60–90 min · local suites 30–90 min · branch protection 15 min.
