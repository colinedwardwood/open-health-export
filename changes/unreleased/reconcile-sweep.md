### Fixture-driven reconcile sweep applies repairs

`ReconcileSweep` plans the trailing seven days from stored census versus
date-ranged observations, then enqueues a repair batch (re-emit and absence
tombstones) without advancing the HealthKit cursor. A user-triggered full
reconcile discovers the first and last available HealthKit day, scans that
inclusive range, and uses HealthKit statistics for canonical cumulative
aggregates while leaving anchored cursors unchanged.
