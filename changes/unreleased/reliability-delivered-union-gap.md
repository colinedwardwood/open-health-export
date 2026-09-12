Queue eviction, TTL expiry, and type purge copy each pending batch's sample
count and day extent onto the gap record, so `delivered ∪ gap ⊇ read` and I5
over-cover are checkable after arbitrary enqueue, ack, and drop interleavings.
