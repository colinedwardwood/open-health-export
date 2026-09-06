### Queue bound and fail-closed checkpoints

Pending batches now carry a byte count. Enqueue evicts oldest queued work first when the
256 MiB cap would be exceeded, records a gap, and unlinks victim payload files only after
the transaction commits. Cursor rows are versioned `OHEC` envelopes: corrupt or
forward-version blobs fail closed and never look like an empty store. Policycheck now
bans ambient `Date()` / calendar / timezone / locale clocks outside CoreTemporal and
HealthKitSource. CI checks `Signed-off-by` on each commit.
