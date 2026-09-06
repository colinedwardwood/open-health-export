### Reproducible tier-zero corpus

`corpusgen` now emits deterministic canonical quantity records from a counter and committed seed.
The first R-82 tier contains 200 checked-in NDJSON records across every currently catalogued
metric. Linux CI regenerates it byte-for-byte and verifies its SHA-256 digest.
