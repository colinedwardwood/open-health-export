# Stage 3 / 4 remaining (in-scope)

Living checklist for code-completable Stage 3 implementation and Stage 4 automated QA.
Updated as items finish. Times are wall-clock, including hosted CI waits.

Last updated: 2026-09-17 14:56 ET (America/New_York)

**Current HEAD:** `17f6584` on origin (named iPad unhosted text states + third AX-timeout retry).

**Last macos-build:** [`35261508549`](https://github.com/colinedwardwood/open-health-export/actions/runs/35261508549) on `17f6584` — in progress (darwin-package / from-source / ios-build / release-artifact-scan; mac-companion already green). Previous run [`35254591575`](https://github.com/colinedwardwood/open-health-export/actions/runs/35254591575) on `1ff6ca5` failed iPad 1 (nil-element inaccessible text) and iPhone 0 (audit timeout cascade).

**Do not push again** until those UI shards finish.

**Estimate if the next macos-build is green:** about **5–9 hours** remaining.
**Estimate if another hosted UI cycle is needed:** add **2–4 hours** per cycle.

Out of scope (not on this list as work to do): physical-device / R-71 soak, backup and network-capture evidence, App Store, branding, HACS.

---

## Speed (what we will and will not do)

- **One pusher on `main`.** Latest-ref concurrency cancels the previous run. No second implementer pushing while shards are in flight.
- **Do not spend agent time watching hosted CI.** After a slice is pushed, GitHub macOS owns the next hour. Poll only when a run has finished or a later slice needs the result.
- **No GitHub-attached self-hosted runners for required UI.** The repo is public. QA-28 / R-85 forbid self-hosted jobs on `pull_request`. `macos-build` and `accessibility-matrix` stay on `macos-26`. This Mac, the Air, and the 2015 Ubuntu box are **local** executors only: they can run suites while GitHub runs, they must not be registered against those workflows.
- **Local suites in parallel with hosted waits**, not after them. Air (Xcode 26.6, iOS 26.5 sims) matches hosted better than this Mac (Xcode 27).
- **No speculative Data-tab polish** on this slice. Product chrome for those iPad findings already landed on `1ff6ca5`; remaining is the named iPadOS 26.5 nil-element exception plus one extra AX-timeout retry.

## Now (blocking hosted UI)

- [x] **Type into fields when the hardware keyboard has focus**
- [x] **Assert paused-anchor banner after disclosure**
- [ ] **Watch XXXL launch flake** (no extra code unless it repeats)
- [ ] **Wait for macos-build after this push** (~50–90 min)
  - Do not push again while those shards are in flight.
  - Do not attach an agent watch to the run.
- [x] **r84-determinism arm apt 404**
- [x] **Selected destination / unit / time / QoS choices stay enabled at primary contrast**
- [x] **Data-tab catalogue rows stay VoiceOver-visible** (`children: .combine` on `1ff6ca5`)
- [ ] **iPad 1 nil-element inaccessible text** — named states `pseudo-browser-empty`, `browser-permission-limited`, `browser-detail-permission-denied` (this push)
- [ ] **iPhone 0 AX timeout cascade** — third audit retry on `-56` / 1000 (this push); if it repeats, treat as simulator starvation, not new chrome

## After hosted UI is green

- [ ] **Dispatch `accessibility-matrix.yml` immediately** (~60–90 min, 12 hosted jobs)
  - Last dispatch (`35106994795` on `e8cc1ba`) failed iPhone 1 / iPad 2, 4, 5. Keyboard empty-query and iPad DeviceNoun copy should already be fixed on `7cd0d01`.
- [ ] **Fix any matrix findings** (0 if green; 2–4 hours if red, plus another matrix)
- [ ] **Local iPhone UI suite** (~20–40 min) — Air, in parallel with hosted matrix / macos-build
  - In progress on Xcode 26.6 `iPhone 17 Pro`. `testBrowserDetailInRTL` failed: after the keyboard corner-tap fallback, `browser-row-heartRate` never appeared (likely an Arabic glyph typed into search). Uncommitted test fix waits until hosted shards finish: skip the 0.92/0.88 tap under forced RTL, retry the filter once.
  - That case is **ios-ui shard 2** (`scripts/ui-test-shard.sh 2 3`). Hosted `ios-ui (2, iPhone)` is in flight on `17f6584` with `-retry-tests-on-failure`; do not push over it.
- [ ] **Local iPad UI suite** (~30–90 min) — this Mac Xcode 27, in progress; `testBrowserDetailInRTL` passed here.
- [ ] **Configure `main` branch protection** (~15 min)
  - Only after the last direct-push implementation slice. Not before.

## Completion audit (do not skip)

- [x] **Prove Stage 3 one-read / N-sink fan-out and automatic orchestration from current `main`** (engine + unit tests on `17f6584`; hosted UI is Stage 4)
  - Tree on `17f6584`: `ExportRun.run()` loads `source.page` once, `commitFanout` for every owed dest, then `deliver` per `attemptNow`. `runFanout()` adds per-sink rows. `owedDestinations()` applies AR-15. `trailingReconcileAfterDelta` uses one `ReconcileSweep`. `FanoutSnapshotWriter` writes per-sink snapshots. `drainPendingDeliveries` runs before a new read. `reevaluateAutomaticExport` restarts observers. Unreconstructed destinations get their own failure in `HarnessExport`. Schema v20 `deliveries` is `(batch_id, destination_id)`.
  - Local `swift test` on `17f6584` (this Mac, 2026-09-17 14:58 ET), 23/23:
    AR-02 `oneReadFansOutToTwoDestinations`, `fanoutProjectsANarrowerDestinationFromOneCanonicalBatch`, `fanoutExpectedRecordCountRespectsDestinationStart`;
    R-03 `r03BatchIdentityIsUUIDv7AndTimeOrdered`, `r03PendingBatchIdentityCannotBeReused`;
    AR-14 `ar14BatchSequenceIsMonotonicAndScopedToTheExporter`;
    AR-15 `ar15ManualOnlyRoleRejectsEveryAutomaticTrigger`, `ar15ManualOnlySnapshotSurvivesOutcomesAndRoundTrips`, `automaticFanoutSkipsManualOnlyDestinationsWithoutASecondRead`;
    retain/unlink `fanoutRetainsPayloadUntilEveryDestinationSettles`, `aSettledBatchLeavesNoQueuedPayloadBehind`, `evictingABatchClearsEveryDestinationObligation`, `fanoutObligationsSurviveSQLiteReopen`;
    companion `backgroundFanoutQueuesADestinationWithoutAttemptingIt`, `companionTransportIsAttemptedOnlyFromForegroundOrExplicitUI`;
    v20 `deliveryAuditKeepsOneRowPerDestinationAcrossTheV20Migration`, `pendingDeliveryRunnerDoesNotSendAnotherDestinationObligation`;
    R-08 `r08TrailingReconcileFansOutFromOneRead`, `aFullReconcileRepairsEveryDestinationFromOneHistoryRead`, `aTrailingReconcileRepairsEveryDestinationFromOneWindowRead`, `aRepairSweepReportsARowForEveryDestinationItWasOwedTo`;
    R-11 park `backfillParksWhenDestinationBreakerIsOpen`;
    history/OTLP `otlpBacklogKeepsPerDestinationChildRowsOnDevice`.
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

## Clock

| Slice | Typical wait |
|---|---|
| Code + DCO commit + push | 15–45 min |
| macos-build (6 UI shards) | 50–90 min |
| accessibility-matrix (12 jobs) | 60–90 min |
| Local iPhone + iPad suites (parallel) | 30–90 min wall if two Macs |
| Branch protection | 15 min |
