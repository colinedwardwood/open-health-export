SEC-18 / R-67: add deterministic, versioned, credential-free destination
configuration files containing per-destination metric/date scopes. Imports
reject unknown or secret-bearing fields and can only become disabled,
test-required drafts after exact typed confirmation; they cannot silently
enable or re-point an existing destination.

The iOS app now provides a `.tributary` review and typed-confirmation flow
that persists imports as protected, backup-excluded disabled drafts with
fresh local identifiers.

Persisted drafts remain visible after relaunch, can be explicitly discarded,
and are included in destructive wipe coverage.

HTTPS and MQTT drafts can now prefill the existing credential editors, preserve
their metric/date scope and fresh imported identity, and are consumed only
after the real destination probe and explicit server confirmation succeed.
Imports refuse occupied slots or settings the runtime path cannot preserve.

Enabled HTTPS and MQTT destinations can now be exported through an explicit
share action as deterministic `.tributary` documents containing supported
settings and scope but no credentials or credential-presence flags.
