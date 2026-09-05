### Engine write-ahead cursor, census, local-file sink

`ExportRun` commits the HealthKit-free cursor in the same SQLite transaction as the batch,
updates the per-(metric, day) census and dirty-bucket ledger, then delivers via `LocalFileSink`
(atomic write). Re-running after commit is `successNothingDue`. Same idempotency key overwrites
one file.
