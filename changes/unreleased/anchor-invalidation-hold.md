An anchor that can no longer be trusted now stops the metric and waits for a decision
instead of re-reading everything (QA-17).

Two cases used to be indistinguishable from a first export. A cursor row that has gone
missing, and a delta that comes back carrying the whole store. Both would have been read
with no usable anchor and sent again in full: years of history duplicated at the
destination, paid for in battery and, for anyone on a metered API, in quota.

Either one now records a hold naming what was seen and the last day known to have been
sent, and the metric stays stopped. Authorising the re-export is what releases it, and
that authorisation is recorded before the run rather than inferred from it.
