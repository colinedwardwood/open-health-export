# Stage 3 / 4 remaining (in-scope)

Living checklist for code-completable Stage 3 implementation and Stage 4 automated QA.
Updated as items finish. Times are wall-clock, including hosted CI waits.

Last updated: 2026-09-17 19:40 ET (America/New_York)

**Current HEAD (local, pushing):** `d4a91a5` plus the Data-tab toggle/heading contrast slice. Origin was `44c6560`.

**Last macos-build:** [`35268426814`](https://github.com/colinedwardwood/open-health-export/actions/runs/35268426814) on `44c6560` **failed**. Compile jobs green. UI: **iPhone 0, iPad 0, iPad 1 green**. Red:

- **iPhone 1** `testBrowserEmptyStateInPseudoLocale`: Contrast on unlabeled `Stop sending after a date Stop sending after a date` at y≈207 (this push combines that toggle).
- **iPhone 2** `testBrowserDetailInRTL` / `testBrowserEmptyStateInRTL`: keyboard stayed up (`3c1a925` skipped the trailing Return tap). Air proved restore+retry on `d4a91a5`.
- **iPad 2** `testBrowserEmptyStateInRTL`: nil-element "Potentially inaccessible element" (this push names `rtl-browser-empty` and matches that compact description).

**Do not push again** until the next macos-build's six UI shards finish.

**Estimate if the next macos-build is green:** about **4–8 hours** remaining (matrix + local suites + protection).
**Estimate if another hosted UI cycle is needed:** add **2–4 hours** per cycle.

Out of scope (not on this list as work to do): physical-device / R-71 soak, backup and network-capture evidence, App Store, branding, HACS.

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
- [ ] **Wait for macos-build after this push** (~50–90 min)
  - Do not push again while those shards are in flight.
  - Do not attach an agent watch to the run.
- [x] **r84-determinism arm apt 404**
- [x] **Selected destination / unit / time / QoS choices stay enabled at primary contrast**
- [x] **Data-tab catalogue rows stay VoiceOver-visible** (`children: .combine`)
- [x] **iPad 1 nil-element inaccessible text** — named states landed; iPad 0/1 green on `44c6560`
- [x] **iPhone 0 AX timeout cascade** — green on `44c6560`
- [x] **Restore trailing RTL keyboard dismiss** (`d4a91a5`, Air 94s)
- [ ] **iPhone 1 pseudo empty-state contrast** — combine Data-tab end-date toggle (this push)
- [ ] **iPad 2 RTL empty-state nil-element** — `rtl-browser-empty` + "Potentially inaccessible element" (this push)

## After hosted UI is green

- [ ] **Dispatch `accessibility-matrix.yml` immediately** (~60–90 min, 12 hosted jobs)
- [ ] **Fix any matrix findings** (0 if green; 2–4 hours if red, plus another matrix)
- [ ] **Local iPhone UI suite** (~20–40 min) — Air, in parallel with hosted matrix / macos-build
- [ ] **Local iPad UI suite** (~30–90 min) — this Mac Xcode 27 (76 passed earlier; re-run after this slice if time)
- [ ] **Configure `main` branch protection** (~15 min)
  - Only after the last direct-push implementation slice. Not before.

## Completion audit (do not skip)

- [x] **Prove Stage 3 one-read / N-sink fan-out and automatic orchestration from current `main`** (engine + unit tests on `17f6584`; hosted UI is Stage 4)
- [ ] **Prove Stage 4 automated QA wedges from current CI** (~20 min)
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
