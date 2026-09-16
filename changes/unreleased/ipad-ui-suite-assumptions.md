---
category: fixed
---

Fixed three iPad UI-test failures that were assumptions from the iPhone layout,
not product faults: an iPad keyboard parked off screen was treated as visible and
dismissing it failed outright, and a doubled pseudo-locale tab label grew wider
than the screen so the tap meant for it landed outside the window. Tab selection
is now confirmed by the page that appears rather than by the tap.
