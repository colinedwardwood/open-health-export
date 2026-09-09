### Provenance-aware R-82 corpus tiers

`corpusgen` now has frozen T0 (200), T1 (10 million), and T2 (50 million) plans, streams output
with bounded memory, and writes a provenance header containing seed, tier, generator version, and
synthetic status. Generated coverage spans at least 60 types and six source identities; T2 adds
deterministic replay and tombstone pathologies. T0 now includes category, correlation, and workout
records in addition to quantity points. A scheduled CI gate streams T1 twice through SHA-256,
requires identical digests, and enforces the ten-minute generation ceiling on each run without
materializing the multi-gigabyte corpus. A manual CI job similarly streams the complete
50-million-record T2 replay/tombstone pathology tier through SHA-256.
