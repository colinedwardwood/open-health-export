### HealthKit coverage and statistics adapters

`HealthKitDayObservationSource` pages date-ranged samples with a throwaway
anchor for reconciliation, leaving the live delta anchor untouched.
`HealthKitStatisticsSource` returns de-duplicated P1D cumulative totals with
explicit `healthKitStatisticsCollectionQuery` provenance.
