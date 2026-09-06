### Reconcile planner names day repairs

`ReconcilePlanner.planDay` classifies a stored census cell against observed
samples and returns ordered repairs (`reemitDay`, `emitAbsenceTombstones`).
`trailingDays` builds the default seven-day R-08 window. `clearDirty` lets a
later aggregate drain drop a day once it has been recomputed and enqueued.
The HealthKit date-ranged sweep still does not run.
