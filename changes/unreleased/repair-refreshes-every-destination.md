---
category: fixed
---

A repair or backfill that reached several destinations now updates each one's
status. Only the destination the sweep was built around was refreshed, so the
others kept showing a result from an earlier run: a sink that had just been
repaired could still be presented as overdue, and one that had just failed could
still look fine.
