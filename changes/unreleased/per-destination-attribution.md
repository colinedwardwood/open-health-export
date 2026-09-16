---
category: fixed
---

Each destination's status now reflects its own delivery result. When one sink
failed and another succeeded from the same read, the run's combined outcome was
written to every destination, so a working archive folder was shown as failed
because an unrelated server was unreachable, and it received a failure notice of
its own. History rows for a repair had the same problem in reverse: a sink that
was attempted and failed was recorded as merely queued.
