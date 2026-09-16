---
category: fixed
---

Each destination's status file is written from that destination's own delivery
result as soon as the read finishes. The combined outcome used to be written to
the primary snapshot first, so a working archive folder could read as failed for
the rest of a long export while later types were still running.
