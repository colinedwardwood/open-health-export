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
The delivery audit is now keyed by batch and destination (schema 20), so a
second sink's acknowledgement no longer overwrites the first's, and evicting a
batch clears the obligations that were owed on its payload. Run history shows a
fan-out read as one parent run with a row per destination underneath, so a
queued Mac companion is visible beside a destination that already delivered;
those child rows stay on the device rather than multiplying one run into
several telemetry spans.
