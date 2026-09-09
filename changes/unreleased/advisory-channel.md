### R-38 advisory channel and R-23 denied-notification escalation

Signed (HMAC-SHA256) advisory feed parse/verify, golden GET fixture, ledgered fetches,
fail-open export, and watchdog escalation that still advances the widget when notifications
are off. The iOS foreground path now performs the scheduled fetch through the pinned,
query-free request, persists its schedule state, and renders verified items or stale/disabled
copy without coupling advisory availability to export. Every successful local export also
cancels and reschedules the overdue notification from the persisted destination threshold;
before R-71 supplies that threshold, no deadline is invented. Foreground launches probe
notification settings and ledger only the transition to denied as a suppression security
event, incrementing destination snapshots so the in-app and widget paths remain honest.
Export and reconcile snapshot rewrites preserve configured thresholds and retry windows;
a synthetic-clock integration now proves repeated missed windows retain one overdue
deadline and the next success clears staleness.
Until R-71 evidence exists, the app and README visibly name the ratified six-hour
alarm floor while explicitly stating that it is not a delivery promise.
