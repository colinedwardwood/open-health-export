---
category: added
---

Add the durable per-destination delivery-obligation model and SQLite schema
needed to retain one shared export batch until every destination settles.
Export runs now read HealthKit once, enqueue every owed destination, and
deliver independently so a manual-only sink is skipped without a second read.
