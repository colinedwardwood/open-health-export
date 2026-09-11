The destination status line now ages with the clock and names the reason a send failed
(QA-14).

It was showing the state stored at the last run, so a destination that succeeded once
and then stopped kept reporting healthy no matter how long the silence lasted — the
exact failure this surface exists to reveal. Staleness is now computed when the line is
read, the way the widget already did it.

A failure also carries its reason code. "Failing" on its own is not something anyone can
act on or put in a bug report.

The in-app surface no longer depends on the container the widget reads. If that
container is unavailable the app falls back to its own storage, because showing nothing
looks identical to nothing being wrong.
