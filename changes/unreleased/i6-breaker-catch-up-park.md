Catch-up (gap re-export, reconcile, backfill) now parks when the destination
breaker is open, halted, or blocked, so a one-tap re-export into a still-broken
sink leaves live deltas in the queue instead of evicting them.
