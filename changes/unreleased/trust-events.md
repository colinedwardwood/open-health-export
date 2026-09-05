### Trust events and the notifier port (R-40 / R-41)

`DestinationSetup` transitions now accumulate `TrustEvent`s — canary confirmed, pin recorded,
pin changed and halted, destination enabled, trust lost — drained by the caller with
`drainEvents()`. Transitions stay synchronous and side-effect-free: no notification is sent from
inside a state change. A timeout still emits nothing, because a timeout is not a trust change.
One halt is one notice: re-observing an already-halted destination throws again without
re-notifying.

`UserNotice` carries a classified `kind` plus identifiers and **no prose** — no title, no body —
so user copy cannot be written at the call site (DP-6). `UserNotifier` has no suppression
parameter, so no call site can decline to notify (R-41). The event-to-notice mapping lives in
`DestinationTrust` rather than `EnginePorts`, keeping the port ignorant of trust vocabulary, and
it is a `switch` with no `default`, so a new trust event cannot ship unnotified.

Not done: the platform notification implementation, the copy registry, and the escalation rungs
(badge / banner / widget) — all app-target work. Undrained events are in-memory only; the
durable answer to a crash before draining is the R-30 ledger, not this buffer.
