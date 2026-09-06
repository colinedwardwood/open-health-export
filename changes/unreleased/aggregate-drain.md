### Local sample fold and dirty-day aggregate drain

`AggregateRecord` is a domain value. `AggregateFold` computes P1D sum/mean from
in-memory samples; `AggregateDrain.planDay` stamps a stable `bucketKey` and
`open`/`final`/`revised` state. `NativeWire` encodes aggregate lines and footer
counts. HealthKit statistics and ExportRun stage-5 wiring are still deferred.
