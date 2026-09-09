### Queue bound and fail-closed checkpoints

Pending batches now carry a byte count. Enqueue evicts oldest queued work first when the
256 MiB cap would be exceeded, records a gap, and unlinks victim payload files only after
the transaction commits. Queue rows and gap records persist the affected metric and inclusive
date range; the iOS gap surface can re-read and re-export that exact range in one tap without
advancing the anchored cursor. A newly evicted range posts classified local-notification copy
instead of failing silently. Cursor rows are versioned `OHEC` envelopes: corrupt or
forward-version blobs fail closed and never look like an empty store. Policycheck now
bans ambient `Date()` / calendar / timezone / locale clocks outside CoreTemporal and
HealthKitSource. CI checks `Signed-off-by` on each commit.
