---
category: fixed
---

Start background Health observers as soon as any destination is enabled, not
only the archive folder. A user whose single destination was HTTPS, MQTT, Home
Assistant or the Mac companion had no wake source until the next app launch, so
automatic export silently did not begin. Disabling a destination, forgetting a
companion pairing, and switching a destination between automatic and manual-only
now re-decide the observers the same way.
