### Durable pending delivery

`commitBatch` now persists the payload path and expected record count in the same transaction
that advances the HealthKit cursor. A process restart can replay the oldest batch through
`PendingDeliveryRunner`, with at most one transport attempt per sink invocation; partial and
unknown acknowledgements stay queued, while a full receipt removes the batch. Eviction removes
the payload reference and records a gap.
