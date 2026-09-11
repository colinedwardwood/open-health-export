OBS-02: bound the export journal. Retention is 90 days or 1,000 runs,
whichever is reached first, enforced in the store's journal append because that
is the single point all six engine call sites go through — a sweep someone has
to remember to call is a sweep that eventually is not called. The cutoff is
measured from the newest row rather than the wall clock, so retention is
deterministic under test and cannot be moved by a device whose clock jumped.

Tested with the requirement's own case: 1,200 runs over 120 simulated days,
asserting both bounds and that the file stays under 5 MB, plus a burst inside
the age window to prove the run-count bound bites on its own.
