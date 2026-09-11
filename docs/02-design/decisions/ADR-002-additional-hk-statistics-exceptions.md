# ADR-002: Additional HealthKit statistics exceptions

**Status:** accepted

## Decision

The six cumulative quantity families added with the Core Daily expansion use
`HKStatisticsCollectionQuery` for canonical P1D totals, for the same overlap
reason as ADR-001:

- `swimming_distance`
- `wheelchair_distance`
- `push_count`
- `swimming_stroke_count`
- `time_in_daylight`
- `apple_move_time`

The committed list remains `spec/v1.0.0/catalogue/hk-statistics-exceptions.json`.
Discrete speed, environmental audio, and physical-effort samples stay local
because they are not multi-source cumulative totals.

## Verification boundary

Linux verifies the frozen list against `MetricCatalog`. Numerical agreement
with `HKStatisticsCollectionQuery` remains part of the named real-device R-87
release pass. No synthetic fixture is represented as device evidence.
