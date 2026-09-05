### R-31 destination verification core

`ExportRun` accepts only `VerifiedDestination`. `DestinationSetup` is the state machine
(draft → previewed → canary_sent → canary_confirmed → pinned → enabled, or halted). Canary
payloads are `ohe.wire/1` with `kind: canary`, not health samples. Pin-on-first-use compares
leaf (default) or issuer SPKI; mismatch throws before `HTTPTransport.execute`. Timeouts are not
a pin change. Preview bytes are the production encoder. `VerifiedDestination.testing` is the
R-83 seam for tests and the M0 harness. Live `URLSession` SPKI extraction is not in this slice.
