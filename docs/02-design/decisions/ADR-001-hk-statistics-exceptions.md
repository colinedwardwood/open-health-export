# ADR-001: HealthKit statistics exceptions

**Status:** accepted

## Decision

Canonical P1D totals for cumulative quantity metrics use
`HKStatisticsCollectionQuery` rather than folding anchored samples. The frozen exception list is
`spec/v1.0.0/catalogue/hk-statistics-exceptions.json`.

HealthKit de-duplicates overlapping contributions from multiple sources according to its own
statistics semantics. A local sum can double-count those contributions and is therefore forbidden
for these metrics. Adding an exception requires a new accepted ADR; changing the JSON alone must
not be treated as evidence that the exception is safe.

## Verification boundary

Linux verifies the frozen list, declared units, resolver behavior, and synthetic contract vectors.
The numerical comparison against `HKStatisticsCollectionQuery` remains part of the named real-device
R-87 release pass and must be recorded with device, OS, store span, and source count. No synthetic
fixture is represented as device evidence.
