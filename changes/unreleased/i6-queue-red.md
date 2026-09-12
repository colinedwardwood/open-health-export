I6 Red occupancy now purges derived attempt caches, truncates the SQLite WAL,
and raises an approaching-loss notice at 80% of the queue cap, still without
evicting live batches.
