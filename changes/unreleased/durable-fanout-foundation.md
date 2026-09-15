---
category: added
---

Add the durable per-destination delivery-obligation model and SQLite schema
needed to retain one shared export batch until every destination settles.
Export runs and catch-up now enqueue that obligation and release the payload
only after every owed destination acknowledges.
