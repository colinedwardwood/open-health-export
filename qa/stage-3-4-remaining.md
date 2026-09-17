# Stage 3 / 4 remaining (in-scope)

Living checklist for code-completable Stage 3 implementation and Stage 4 automated QA.
Updated as items finish. Times are wall-clock, including hosted CI waits.

Last updated: 2026-09-17 09:00 ET (America/New_York)

**Current HEAD:** `ios-build` on `214cd91` failed: XCUIElement has no `hasKeyboardFocus` member. Pushing KVC focus check.

**Estimate if the next macos-build is green:** about **6–10 hours** remaining.
**Estimate if another hosted UI cycle is needed:** add **2–4 hours** per cycle.

Out of scope (not on this list as work to do): physical-device / R-71 soak, backup and network-capture evidence, App Store, branding, HACS.

---

## Now (blocking hosted UI)

- [ ] **Type into fields when the hardware keyboard has focus**
  - Property access failed hosted compile; KVC `hasKeyboardFocus` is the replacement.
- [x] **Assert paused-anchor banner after disclosure**
- [ ] **Watch XXXL launch flake** (no extra code unless it repeats)
- [ ] **Wait for macos-build after this push** (~50–90 min)
  - Do not push again while those shards are in flight.
- [x] **r84-determinism arm apt 404**
  - Green on `2e0182f`.

## After hosted UI is green

- [ ] **Dispatch `accessibility-matrix.yml`** (~60–90 min, 12 jobs)
  - Last dispatch (`35106994795` on `e8cc1ba`) failed iPhone 1 / iPad 2, 4, 5. Keyboard empty-query and iPad DeviceNoun copy should already be fixed on `7cd0d01`. iPad Dynamic Type, share-warning contrast, and pseudo-locale clip may still be real; do not suppress them without a product fix.
- [ ] **Fix any matrix findings** (0 if green; 2–4 hours if red, plus another matrix)
- [ ] **Local iPhone UI suite on an idle machine** (~20–40 min)
- [ ] **Local iPad UI suite on an idle machine** (~30–90 min)
- [ ] **Configure `main` branch protection** (~15 min)
  - Only after the last direct-push implementation slice. Not before.

## Completion audit (do not skip)

- [ ] **Prove Stage 3 one-read / N-sink fan-out and automatic orchestration from current `main`** (~20 min)
  - Tree check on `7cd0d01` (not a substitute for hosted UI): `ExportRun.run()` loads once then delivers per `owed` dest; `trailingReconcileAfterDelta` takes covering destinations into one `ReconcileSweep`; `FanoutSnapshotWriter` writes per-sink snapshots; `drainPendingDeliveries` walks owed transports; `reevaluateAutomaticExport` restarts observers on destination change. Still need requirement-by-requirement confirmation after hosted UI is green.
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
| Local iPhone + iPad suites | 50–130 min |
| Branch protection | 15 min |
