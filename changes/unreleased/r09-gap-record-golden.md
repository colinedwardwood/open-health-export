Seeded fill-the-queue eviction now pins gap records byte-for-byte against a
committed NDJSON golden, so R-09 loss accounting stays deterministic under R-84.
