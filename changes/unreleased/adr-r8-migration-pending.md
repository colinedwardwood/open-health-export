Schema migrations no longer run on a background wake. ADR-R8 asked for this and nothing
implemented it: the store migrated on every open, including inside a thirty-second wake.
A multi-second migration there, retried on every wake, is a permanent outage that reads
as a scheduling problem.

A system-scheduled wake now opens the store under a policy that forbids migration. If
the on-disk `user_version` is not the one this build expects, the wake journals
`migrationPending` and returns without touching a table, and the next foreground launch
migrates as before. The check is an integer compare before any table is opened, which is
what ADR-R8's R0 phase budgets for, and the wake reports success to iOS, because
deferring was the correct behaviour and claiming failure would make iOS back off
scheduling over it.

This needed a real outcome rather than a journal note. `WakeAttribution` classifies any
unrecognised journal outcome as an execution failure — "The app woke on time and the
export did not finish. This one is ours" — so a journal-only marker would have made R-22
blame the app for a wake that did exactly what it was designed to do. `migrationPending`
is therefore in the closed R-21 set, counts as a benign outcome for R-22, appears in the
OTLP outcome domain, and carries copy that says what to do about it: the migration only
runs in the foreground, so waiting for another wake would wait forever.

It is the one outcome a call site may name, because the deferral is decided before
anything is read and there is no tally to derive it from. The reachability test records
that exception rather than dropping the guarantee. Covered by tests: the refusal leaves
the on-disk schema untouched, a foreground launch still migrates and does not silently
reset the anchor, an already-current store is unaffected by the rule, and the deferral
is not attributed to us.
