Adopt REUSE 3.3 (OSS-15): SPDX copyright and licence headers in every source
file, `LICENSES/` with the verbatim text of each identifier in use, and a
`REUSE.toml` covering the data files that cannot hold a comment. The licence
split is the one COPYING already described — code AGPL-3.0-or-later, `docs/`
CC-BY-4.0, `spec/` CC0-1.0. `reuse lint` now runs in CI, and policycheck
asserts the copy of the grant under `LICENSES/` still matches `LICENSE`.
