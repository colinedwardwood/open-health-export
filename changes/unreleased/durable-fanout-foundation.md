---
category: added
---

Add the durable per-destination delivery-obligation model and SQLite schema
needed to retain one shared export batch until every destination settles.
Automatic wakes now plan every enabled designated destination from one
HealthKit read: local-file, HTTPS, Home Assistant, and MQTT are attempted;
a Mac companion is queued without a background Bonjour dial.
