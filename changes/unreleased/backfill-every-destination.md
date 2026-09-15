---
category: changed
---

Send historical backfill to every enabled destination, each bounded by its own
export window, instead of the archive folder alone. History is the one read that
costs a user minutes, and an archive-only backfill left every other destination
holding today's data with nothing before it. A backfill already in progress
keeps the destinations it was planned for; a destination enabled mid-job gets
its own backfill afterwards rather than inheriting days marked complete for
someone else.
