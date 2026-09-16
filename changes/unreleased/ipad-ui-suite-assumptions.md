---
category: fixed
---

Fixed three iPad UI-test failures that came from iPhone layout assumptions rather
than from the app: an iPad keyboard parked off screen counted as visible, so
dismissing it failed outright, and a doubled pseudo-locale tab label grew wider
than the screen so the tap meant for it landed outside the window. Tab selection
is now confirmed by the page that appears rather than by the tap.
