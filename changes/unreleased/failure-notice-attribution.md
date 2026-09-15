---
category: fixed
---

Attribute a failed export notice to a destination that was actually part of the
run. A background wake or on-screen run that failed before any destination could
report for itself always named the archive folder, even when the failing
destination was HTTPS, MQTT or Home Assistant, and even when no archive folder
was configured at all.
