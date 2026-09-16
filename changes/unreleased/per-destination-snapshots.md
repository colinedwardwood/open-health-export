---
category: fixed
---

Each destination's status file is written from that destination's own delivery
result as soon as the read or repair finishes. The combined outcome used to be
written to the primary snapshot first, so a working archive folder could read as
failed for the rest of a long export, and a repaired sink could keep showing an
earlier result until the harness overwrote it.
