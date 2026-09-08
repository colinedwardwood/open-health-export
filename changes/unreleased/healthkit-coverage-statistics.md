### HealthKit coverage and statistics adapters

`HealthKitDayObservationSource` pages date-ranged samples with a throwaway
anchor for reconciliation, leaving the live delta anchor untouched.
`HealthKitStatisticsSource` returns de-duplicated P1D cumulative totals with
explicit `healthKitStatisticsCollectionQuery` provenance.
The iOS local export now supplies both adapters: each metric delta is followed
by a bounded trailing seven-day reconcile, and cumulative runs resolve daily
aggregates from HealthKit statistics rather than leaving the adapters test-only.
After the disclosure has been acknowledged once, relaunching the app starts one
bounded local catch-up automatically when that destination already has a
passing R-25 report. Journal and external-status attribution use
`appForeground`.
