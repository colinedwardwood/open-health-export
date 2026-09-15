---
category: fixed
---

Re-export a queue-eviction gap to every enabled destination whose scope covers
the type. The repair previously went to the archive folder alone, so any other
sink stayed permanently short the records the evicted batch was carrying. The
reported result is the worst of the destinations, so a sink that failed is not
hidden by one that succeeded.
