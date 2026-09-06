### Per-type queue purge on observed revocation

Pending batches are indexed by metric. `TypePurge` drops that type's queued
payloads, records a ledger/journal row, and disables the type — only on an
observed grant→denied transition or an explicit stop, never on an empty read.
The 60-second SLA is from observation; HealthKit still has no revocation
callback, and product UI for stop-and-purge is not in this change.
