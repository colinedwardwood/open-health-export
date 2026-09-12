Export snapshots now write R-23 stale and overdue thresholds from the local
freshness p95 (floor 6 hours, cap 48 hours) so overdue notifications have a
window instead of inheriting a nil prior.
