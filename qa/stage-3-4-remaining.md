# Stage 3 / 4 remaining (in-scope)

Living checklist for code-completable Stage 3 implementation and Stage 4 automated QA.
Updated as items finish. Times are wall-clock, including hosted CI waits.

Last updated: 2026-09-20 19:30 ET (America/New_York)

**Origin `a23a987` macos-build [`35463198198`](https://github.com/colinedwardwood/open-health-export/actions/runs/35463198198): failed.** iPhone 0/1/2 ios-ui green; iPad 0/1/2 red (empty+detail Dynamic Type then `-56`; Destinations+History RTL `-56`; public-destination Contrast). Local stack `f0c9c8b`… plus public-destination banner is ready to push.

Local iPad suite on `1010d4e` finished **74/3** (Xcode 27): pseudo-locale empty `-56`, pseudo disclosure/controls XCTFuture 1000, share-warning Contrast. Air iPhone suite **76/1**: R-114 623s timeout (same as this Mac; hosted iPhone 2 on `1010d4e` already green).

`iPad 4` hosted failures: `testEveryDestinationDisplayStatePassesAccessibilityAudit` Dynamic Type on Status “time to first screen” (retry passed; both iterations required), and `testShareWarningIsShownOnceAndGatesTheShareControl` Contrast on Settings-sheet bottom fade (failed twice). Local iPad retest after wrapping the Status caption and classifying Settings bottom fade: both tests **passed** (56s and 192s).

Proven locally, not on GitHub:

- iPad `testDarkBoldAX5` 39.6s, then 40.2s with chrome snapshot
- iPhone `testDarkBoldAX5` 22.5s
- iPhone `testBrowserEmptyStateInRTL` 50.9s
- iPad Destinations empty-state 37.6s
- iPad RTL empty 53.8s
- iPhone RTL Destinations+History 27.5s
- iPhone RTL disclosure 22s and browser-detail 54s (suite 76s)
- Air (Xcode 27, iOS 26.5 iPhone 17 Pro): AX5 25s green; RTL empty was audit **-56** at 107s, then **63s green** after caching chrome queries once per audit

Local iPad suite on `1010d4e` finished **74/3** (see header). Chrome snapshot plus matrix iPad 4 fixes are local commits, unpushed until `iPhone 2` completes.

**Prior [`35372523862`](https://github.com/colinedwardwood/open-health-export/actions/runs/35372523862) on `b1de381`:** compile green; iPhone 0/1 and iPad 0 green; iPad 2 `testDarkBoldAX5` failed on unscaled `configuration-import`; iPhone 2 cascade after accessibility-audit timeout `-56`.

Out of scope: physical-device / R-71 soak, backup and network-capture evidence, App Store, branding, HACS.

---

## Speed (what we will and will not do)

- **One pusher on `main`.** Latest-ref concurrency cancels the previous run. No second implementer pushing while shards are in flight.
- **Do not spend agent time watching hosted CI.** After a slice is pushed, GitHub macOS owns the next hour. Poll only when a run has finished or a later slice needs the result.
- **No GitHub-attached self-hosted runners for required UI.** The repo is public. QA-28 / R-85 forbid self-hosted jobs on `pull_request`. `macos-build` and `accessibility-matrix` stay on `macos-26`. This Mac, the Air, and the 2015 Ubuntu box are **local** executors only.
- **Local suites in parallel with hosted waits**, not after them. Air (Xcode 26.6, iOS 26.5 sims) matches hosted better than this Mac (Xcode 27).

## Now (blocking hosted UI)

- [x] **Type into fields when the hardware keyboard has focus**
- [x] **Assert paused-anchor banner after disclosure**
- [ ] **Watch XXXL launch flake** (no extra code unless it repeats)
- [x] **Wait for macos-build `35287922062`** — finished red; stack pushed as `8f4068f`
- [x] **Wait for macos-build `35297071470`** — cancelled by `61b8ec9`
- [x] **Wait for macos-build `35297295677` on `61b8ec9`** — iPhone green; iPad red
- [x] **r84-determinism arm apt 404**
- [x] **Selected destination / unit / time / QoS choices stay enabled at primary contrast**
- [x] **Data-tab catalogue rows stay VoiceOver-visible** (`children: .combine`)
- [x] **iPad 1 nil-element inaccessible text** — iPad 0/1 green on `44c6560`
- [x] **iPhone 0 AX timeout cascade** — green on `44c6560`
- [x] **Restore trailing RTL keyboard dismiss** (`d4a91a5`, Air 94s; on origin in `591279e`)
- [x] **Combine Data-tab end-date toggle** (on origin `591279e`; local iPhone/iPad empty-pseudo green)
- [x] **Name iPad RTL empty-state nil-element** (on origin `591279e`; local iPad empty-RTL green)
- [x] **Clock-format 12-hour Contrast nearly passed** — fixed locally on `d1efd55`; push after `35287922062`
- [x] **Paused-type banner seeds in-memory on appear** (`de52667`; iPad test 12.5s)
- [x] **Data-tab detail Latest/Samples reflow at AX Dynamic Type** (`8f4068f`; local iPad RTL detail 51s)
- [x] **Wait for macos-build `35355589530` on `39b5c45`** — all six `ios-ui` failed
- [x] **Wait for macos-build `35372523862` on `b1de381`** — iPad 2 AX5 `configuration-import`; iPhone 2 audit-timeout cascade
- [x] **Load-30-days button 44pt Dynamic Type** (`61b8ec9`)
- [x] **Destinations `.tributary` import wrapping Dynamic Type** (`fdd4966`; local iPad empty Destinations 39s)
- [x] **Wait for macos-build `35387460964` on `1010d4e`** — all six `ios-ui` shards green
- [x] **Wait for macos-build `35463198198` on `a23a987`** — iPhone ios-ui green; iPad 0/1/2 red

## After hosted UI is green

- [x] **Dispatch `accessibility-matrix.yml`** — [`35392384276`](https://github.com/colinedwardwood/open-health-export/actions/runs/35392384276) on `1010d4e` (iPad 4 red)
- [x] **Dispatch `accessibility-matrix.yml`** — [`35431247193`](https://github.com/colinedwardwood/open-health-export/actions/runs/35431247193) on `703912d`: **11/12**, only iPad 1 empty-pseudo `-56`
- [ ] **Fix remaining matrix / hosted iPad gaps** — empty-search collapse and wrapping local; public-destination Contrast banner not yet on origin
- [ ] **Local iPhone UI suite** — last full suite Air **76/1** on older HEAD; re-run on proven HEAD
- [ ] **Local iPad UI suite** — last full suite this Mac **74/3** on `1010d4e`; re-run on proven HEAD
- [ ] **Configure `main` branch protection** (~15 min)
  - Only after the last direct-push implementation slice. Not before.

## Completion audit (do not skip)

- [x] **Prove Stage 3 one-read / N-sink fan-out and automatic orchestration from current `main`** (engine + unit tests on `17f6584`; hosted UI is Stage 4)
- [ ] **Prove Stage 4 automated QA wedges from current CI**
  - Release gate already names all six `ios-ui` shards, T1/T2 volume jobs, and twelve `full-state-matrix` jobs (`qa/release-gate.json`). Those checks are not proven until macos-build and a dispatched matrix succeed.

## Done (do not re-open)

- [x] One-read durable per-destination fan-out and automatic orchestration
- [x] AR-14 sequence, UUIDv7 batch IDs, schema v20 deliveries
- [x] ExportRun / reconcile / drain / backfill / observers on destination change
- [x] T1 RSS and T2 ExportRun 50M sharded evidence
- [x] DeviceNoun, iPad copy, diagnostic JSON accessibility
- [x] Release gate requires UI shards, T1/T2, machine-readable canary evidence
- [x] Latest-ref macos-build concurrency (stop starving UI shards)
- [x] iPhone 0 and iPad 0/1 hosted UI on `44c6560`

## Clock

| Slice | Typical wait |
|---|---|
| Code + DCO commit + push | 15–45 min |
| macos-build (6 UI shards) | 50–90 min |
| accessibility-matrix (12 jobs) | 60–90 min |
| Local iPhone + iPad suites (parallel) | 30–90 min wall if two Macs |
| Branch protection | 15 min |
