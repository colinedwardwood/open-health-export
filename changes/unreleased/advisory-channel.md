### R-38 advisory channel and R-23 denied-notification escalation

Signed (HMAC-SHA256) advisory feed parse/verify, golden GET fixture, ledgered fetches,
fail-open export, and watchdog escalation that still advances the widget when notifications
are off. The iOS foreground path now performs the scheduled fetch through the pinned,
query-free request, persists its schedule state, and renders verified items or stale/disabled
copy without coupling advisory availability to export. Every successful local export also
cancels and reschedules the overdue notification from the persisted destination threshold;
before R-71 supplies that threshold, no deadline is invented.
