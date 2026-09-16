---
category: fixed
---

Report an enabled destination that the export could not rebuild. If a
destination's stored configuration or credential could no longer be
reconstructed it was skipped in silence, and then inherited the combined outcome
of the destinations that did run — so a destination that exported nothing could
show as successful. It now records its own failure with an error class, posts a
notice, and says so in the run's result lines.
