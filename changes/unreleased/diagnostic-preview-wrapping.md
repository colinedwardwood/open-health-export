---
category: fixed
---

The diagnostic preview no longer clips part of the bundle. JSON tokens carry no
spaces, so a long path or value had nowhere to wrap and its tail was cut off,
which an accessibility audit caught on one machine and not another. The preview
now carries break opportunities and arrives in bounded pieces.
