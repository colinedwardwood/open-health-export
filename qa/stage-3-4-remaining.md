# Stage 3 / 4 remaining (in-scope)

Living checklist for code-completable Stage 3 implementation and Stage 4 automated QA.
Updated as items finish. Times are wall-clock, including hosted CI waits.

Last updated: 2026-09-16 15:15 ET (America/New_York)

**Current HEAD:** local UI-test slice on top of `fdadc78`. Previous macos-build `35129159849` **failed** (3 of 6 UI shards). Hosted UI is not done until the next six shards are green.

**Estimate if the next macos-build is green:** about **6–10 hours** remaining.
**Estimate if another hosted UI cycle is needed:** add **2–4 hours** per cycle.

Out of scope (not on this list as work to do): physical-device / R-71 soak, backup and network-capture evidence, App Store, branding, HACS.

---

## Now (blocking hosted UI)

- [x] **Fix empty-keyboard XCTest queries** (code done; waiting on hosted CI)
  - `visibleKeyboard()` now uses `waitForExistence` so an empty Keyboard query does not fail the case.
- [x] **Assert paused-anchor banner after disclosure** (code done; waiting on hosted CI)
  - Paused-anchor cases tap Continue first; the banner lives under the first-run cover.
- [ ] **Watch XXXL launch flake** (no extra code unless it repeats)
  - Evidence: `ios-ui (0, iPad)` — `testAccessibilityExtraExtraExtraLargeContentSize` timed out launching, then failed acquiring a background assertion. Already has `-retry-tests-on-failure`. Revisit only if it fails again after the two fixes above.
- [ ] **Push the UI-test slice and wait for macos-build** (~50–90 min)
  - Gate: all six `ios-ui` shards green on the new SHA. Do not push again while those shards are in flight.

## After hosted UI is green

- [ ] **Dispatch `accessibility-matrix.yml`** (~60–90 min, 12 jobs)
- [ ] **Fix any matrix findings** (0 if green; 2–4 hours if red, plus another matrix)
- [ ] **Local iPhone UI suite on an idle machine** (~20–40 min)
- [ ] **Local iPad UI suite on an idle machine** (~30–90 min)
- [ ] **Configure `main` branch protection** (~15 min)
  - Only after the last direct-push implementation slice. Not before.

## Completion audit (do not skip)

- [ ] **Prove Stage 3 one-read / N-sink fan-out and automatic orchestration from current `main`** (~20 min)
  - Engine, harness drain, observers, trailing reconcile, per-destination snapshots — already implemented; audit against current tree, not memory.
- [ ] **Prove Stage 4 automated QA wedges from current CI** (~20 min)
  - Hosted six UI shards, accessibility matrix, T1/T2 volume checks, release-gate names. Physical soak / backup / store listing stay out of scope.

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
