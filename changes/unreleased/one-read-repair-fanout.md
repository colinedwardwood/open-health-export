---
category: changed
---

Repair, gap re-export and backfill now read Health history once and fan that one
read out to every destination owed it, instead of sweeping each destination
separately. Two destinations are repaired from the same observation of a day
rather than from two reads taken moments apart, the work no longer scales with
the number of destinations, and a destination whose circuit breaker is open
keeps its queued obligation instead of cancelling the repair the others were
owed. A single-destination install keeps exactly the behaviour and the flat
single history row it had before.
