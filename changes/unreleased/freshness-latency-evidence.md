R-24: persist decomposed observation and delivery latency per successful run
and freshness class, derive local p95 only after 100 runs spanning 14 days,
and carry backward-compatible qualified estimates into destination status
snapshots. Evidence is bounded to 10,000 rows per destination and class.
