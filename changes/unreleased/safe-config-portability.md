SEC-18 / R-67: add deterministic, versioned, credential-free destination
configuration files containing per-destination metric/date scopes. Imports
reject unknown or secret-bearing fields and can only become disabled,
test-required drafts after exact typed confirmation; they cannot silently
enable or re-point an existing destination.

The iOS app now provides a `.tributary` review and typed-confirmation flow
that persists imports as protected, backup-excluded disabled drafts with
fresh local identifiers.
