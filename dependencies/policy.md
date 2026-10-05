# Runtime dependency policy

Outbound licence is FSL-1.1-ALv2 (`LICENSE`); the reference receiver is Apache-2.0 (ADR-0005).

Allowed SPDX identifiers for first-party files: `FSL-1.1-ALv2`, `Apache-2.0` (reference receiver), `CC-BY-4.0` (docs),
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

## Pin-and-assess procedure (OSS-19)

No third-party Swift package is in the graph today. Before one may land:

1. Pin a git revision (commit SHA), never a floating branch or moving tag.
2. Confirm the licence is permissive (MIT, BSD, ISC, Apache-2.0, zlib or public domain). Copyleft
   dependencies (GPL, AGPL, LGPL) can't be distributed inside an FSL work and are denied.
3. Confirm the package has no bundled telemetry, install-time network, or unchecksummed blobs.
4. Record an ADR, regenerate `dependencies/licences.lock` and `NOTICE`, and land the pin in
   `Package.swift` in the same change.
5. `swift run policycheck` must pass. It already fails on `.package(url:` and `.binaryTarget(`.

Historical dry-run (2026-09-11): `Package.swift` contains zero `.package(url:` lines;
`policycheck` prints `no third-party runtime package: ok`. Repeat that command whenever the
manifest changes. There is no older third-party pin to roll back to.
