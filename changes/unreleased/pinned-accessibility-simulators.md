---
category: changed
---

Pin the accessibility matrix to the same simulator models the UI suite uses.
It previously audited whichever device the runner image listed first, which
makes a contrast finding impossible to reproduce and lets an image change
silently move the audit to a different screen size.
