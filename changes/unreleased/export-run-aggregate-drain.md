### ExportRun drains dirty days into the same batch

A live delta page now folds P1D `localSampleFold` aggregates for every day
the page touches, encodes them beside samples and tombstones, persists
`emitSeq` so a later page of the same day is `revised`, and clears those
dirty days in the write-ahead transaction. HealthKit statistics remain unused.
