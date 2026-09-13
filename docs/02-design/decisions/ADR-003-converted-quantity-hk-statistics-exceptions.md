# ADR-003: Converted-quantity HealthKit statistics exceptions

**Status:** accepted

## Decision

Making the remaining constructible `HKQuantityType` families selectable adds a
further set of cumulative quantity families. They use
`HKStatisticsCollectionQuery` for canonical P1D totals, for the same overlap
reason as ADR-001 and ADR-002: dietary intake, sport distances, inhaler and
insulin doses, alcoholic beverages and fall counts are all written by more than
one source, and summing the raw samples would double-count overlapping writers.

This covers the dietary nutrient families, the additional sport distances
(`distance_rowing`, `distance_paddle_sports`, `distance_cross_country_skiing`,
`distance_downhill_snow_sports`, `distance_skating_sports`),
`dietary_energy_consumed`, `inhaler_usage`, `insulin_delivery`, `nike_fuel`,
`number_of_alcoholic_beverages` and `number_of_times_fallen`.

Discrete converted quantities — speeds, powers, percentages, temperatures,
spirometry, effort scores and body-size measurements — stay local, because they
are not multi-source cumulative totals.

The committed list remains `spec/v1.0.0/catalogue/hk-statistics-exceptions.json`.

## Verification boundary

Linux verifies the frozen list against `MetricCatalog`, and every exception has
a synthetic reference vector in
`spec/v1.0.0/fixtures/hk-statistics-reference-vectors.json`. Numerical agreement
with `HKStatisticsCollectionQuery` remains part of the named real-device R-87
release pass. No synthetic fixture is represented as device evidence.
