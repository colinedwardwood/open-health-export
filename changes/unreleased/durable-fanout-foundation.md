---
category: added
---

Add the durable per-destination delivery-obligation model and SQLite schema
needed to retain one shared export batch until every destination settles.
Per-destination attempt payloads are reconstructed from that canonical batch
when destination grants differ. Automatic wakes now plan every enabled designated destination from one
HealthKit read: local-file, HTTPS, Home Assistant, and MQTT are attempted;
a Mac companion is queued on background wakes and Shortcuts, then delivered
when the app is in the foreground or Export now runs from Control Centre.
