### Fixture-driven reconcile sweep applies repairs

`ReconcileSweep` plans the trailing seven days from stored census versus
date-ranged observations, then enqueues a repair batch (re-emit and absence
tombstones) without advancing the HealthKit cursor. HealthKit statistics
queries are still unused.
