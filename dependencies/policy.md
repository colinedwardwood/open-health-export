# Runtime dependency policy

Outbound licence is AGPL-3.0-or-later plus the additional permission in `COPYING`.

Allowed SPDX identifiers for first-party files: `AGPL-3.0-or-later`, `CC-BY-4.0` (docs),
`CC0-1.0` (spec and fixtures).

Allowed runtime linkage besides first-party Swift:

- `sqlite3` via the `CSQLite` system library
- `zlib` via the `CZlib` system library

No third-party Swift package may enter the graph without an ADR, a Linux build check, and an
update to `dependencies/licences.lock` and `NOTICE`. `policycheck` already fails on
`.package(url:` and `.binaryTarget(`. A lockfile that lists an identifier not generated from
`Package.swift` also fails.

If an allowed dependency changes licence, pin the last compatible revision immediately, decide
within 90 days, record an ADR, and note the event in the changelog (OSS-19).
