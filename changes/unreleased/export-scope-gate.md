SEC-16: add the fail-closed policy gate used before reads, reconciliation and
queued delivery. It rejects missing or half-configured grants, unselected
metrics, samples outside the start-inclusive/end-exclusive interval, and
missing or malformed day metadata. Day parsing is deterministic UTC integer
arithmetic rather than locale- or tzdata-dependent formatting.
