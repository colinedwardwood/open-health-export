# Stage 3 / 4 remaining (in-scope)

Living checklist for code-completable Stage 3 implementation and Stage 4 automated QA.
Updated as items finish. Times are wall-clock, including hosted CI waits.

Last updated: 2026-09-17 20:54 ET (America/New_York)

**Origin HEAD:** `591279e`. **Local, unpushed:** through in-memory paused-type seed (`de52667`) plus uncommitted Data-tab detail wrapping.

**Last macos-build:** [`35287922062`](https://github.com/colinedwardwood/open-health-export/actions/runs/35287922062) on `591279e` — iPhone 0/2 and iPad 0 green; iPhone 1 and iPad 2 failed; **iPad 1 still in progress**. Do not push until that job completes.

**Local evidence on the unpushed tree:**
- iPad `testPausedAnchorIsVisibleAndOffersBothChoices` passed in 12.5s after in-memory seed (`de52667`).
- iPad share-warning passed after diagnostic JSON 44pt labels.
- Clock/unit contrast and Data-tab Toggle AX fixes are local; not on origin.
- Data-tab detail Latest/Samples wrap at AX sizes: uncommitted, pending iPad RTL detail audit.

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
- [ ] **Wait for macos-build `35287922062`** (~50–90 min from 19:41 ET)
  - iPad 1 still in progress. Do not push while it is running.
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
- [ ] **Data-tab detail Latest/Samples reflow at AX Dynamic Type** — uncommitted; hosted iPad 2 failed this on `591279e`

## After hosted UI is green

- [ ] **Dispatch `accessibility-matrix.yml` immediately** (~60–90 min, 12 hosted jobs)
- [ ] **Fix any matrix findings** (0 if green; 2–4 hours if red, plus another matrix)
- [ ] **Local iPhone UI suite** (~20–40 min) — Air
- [ ] **Local iPad UI suite** (~30–90 min) — this Mac, in flight
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
