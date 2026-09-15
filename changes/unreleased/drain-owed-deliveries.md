---
category: fixed
---

Retry what every destination is still owed at the start of an automatic export,
not only the Mac companion. A destination whose transport failed keeps a durable
obligation, and nothing retried it until the queue's time-to-live expired the
batch. Background wakes drain a few of them so the read they were woken for
still fits in the wake.
