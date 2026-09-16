---
category: fixed
---

The trailing reconcile after a delta export now reads the window once and fans
it out. It was still looping per destination, so two sinks would re-observe the
same days and could be repaired from two different observations of them.
