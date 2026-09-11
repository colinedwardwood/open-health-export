QA-04 / R-82: validate all 10,000,000 Tier-1 synthetic records through
the committed wire schema in the nightly job. The second deterministic
generation is streamed simultaneously to the digest and validator, preserving
the reproducibility check without paying for a third full corpus generation.
