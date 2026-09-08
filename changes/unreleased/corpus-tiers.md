### Provenance-aware R-82 corpus tiers

`corpusgen` now has frozen T0 (200), T1 (10 million), and T2 (50 million) plans, streams output
with bounded memory, and writes a provenance header containing seed, tier, generator version, and
synthetic status. Generated coverage spans at least 60 types and six source identities; T2 adds
deterministic replay and tombstone pathologies. T0 now includes category, correlation, and workout
records in addition to quantity points.
