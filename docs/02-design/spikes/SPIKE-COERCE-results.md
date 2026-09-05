# SPIKE-COERCE results

**Date:** 2026-09-03
**Operator:** product owner
**Completeness:** partial — two load-bearing observations, no device/iOS/proxy-app log

## Observed

| Question | Result |
|---|---|
| Scheduled / local notification arrived after hide | **Yes** |
| Widget after hide | **Survived** (present; not removed) |
| Notification body (full vs generic vs none) | **Not recorded** |
| Repeat with notifications denied | **Not recorded** |
| Un-hide restored widgets without re-adding | **Not recorded** |
| Device / iOS / Hide-and-Require-Face-ID vs other hide | **Not recorded** |

## Design reading

Secondary sources that claimed hiding **removes widgets** and **suppresses notifications
entirely** are **falsified** for this owner's device and the hide path they used.

R-23 therefore still has **at least one Home-adjacent rung against concealment**: the widget.
Notification *delivery* also survived, so the chain is not zero. Apple's documented stripping
of **previews** is unchanged: R-40 still must not rely on hostname-in-preview as the only
carrier of the fact.

The notifications-denied repeat was the PRD acceptance criterion's second clause. With the
widget surviving hide, that clause is no longer the difference between one rung and zero: a
coercer who hides the app and also denies notifications still faces a live widget. Treat as
**should-confirm-in-M0**, not Stage 2 blocking.

## Residual risk

If the hide path used was “remove from Home Screen” rather than **Hide and Require Face ID**,
this result would not apply to T-24. Owner described the observation after being pointed at
the spike protocol (Hide and Require Face ID). Recorded as **assumed Hide and Require Face ID;
not independently witnessed**.
