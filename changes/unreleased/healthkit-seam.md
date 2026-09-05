### HealthKit seam and R-70 measure API

`HealthKitSampleSource` implements `SampleSource`. `HKQuantitySample` and `HKQueryAnchor`
are converted inside the anchored-query callback; the core sees `SampleRecord` and an
`OHEA` envelope. `HealthKitThroughput.measure` is the R-70 on-device entry point.
