The scheduled iPhone/iPad accessibility matrix is split into six shards per
device family. The prior job ran the roughly 37-minute local suite twice inside
a 60-minute timeout, before accounting for hosted-runner slowdown, so it could
not reliably produce release evidence.

Every shard keeps the two-attempt flake check. Release validation now requires
all twelve named checks, and automation proves that the shard script selects
every UI test exactly once across each family.
