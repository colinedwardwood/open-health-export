### Retry and circuit-breaker policy

The engine now has a pure, reproducible retry state machine: 15-second exponential full jitter
capped at six hours, `Retry-After` capped at 24 hours, five transient failures or three unknown
acknowledgements to open, immediate user-block/halt classes, foreground half-open probes, and a
six-hour probe cadence after seven days. One policy call records one attempt; it never loops.
