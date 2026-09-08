HealthKit authorization request status is now observed for the enabled
core-activity grant at every launch, foreground activation, HealthKit observer
wake, BG refresh, and BG processing wake. Only the observable
`unnecessary → shouldRequest` transition is treated as revocation; empty reads
are still never described as denial.

An observed transition atomically evicts queued payloads, clears the affected
cursors and emitted-index rows, increments their generation, disables the
types, journals and seals the purge, unlinks payload files after commit, and
disables HealthKit background delivery. A later explicit authorization request
re-enables the types without reducing the generation. Authorization requests
are now scoped to the two metrics used by the core-activity feature rather than
the entire catalogue.
