Default configuration (local-file export) records zero attributable
`NetEgress` dials. The real HTTP transport, `NWByteStream`, and companion
Bonjour browser append to an opt-in `EgressAttemptLog` before connect; tests
bind a Task-local recorder so parallel suites cannot leak into the isolation
assertion.
