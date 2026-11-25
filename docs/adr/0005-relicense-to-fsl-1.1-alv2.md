# ADR-0005: Relicense to FSL-1.1-ALv2

**Status:** Accepted, 2026-10-05. Supersedes ADR-0001.
**Decision by:** the owner, with counsel's approval (#21).

## Context

ADR-0001 chose AGPL-3.0 with an App Store additional permission. AGPL stops closed
forks, but not cheaper ones: anyone could rebuild the app and sell it on the App
Store under another name (LEG-14, #90). The only remaining levers were a trademark
and speed. KeepMyMetrics is now a paid product (D-08a, D-08b), so that gap matters.

Every commit up to this change has a single author, the owner, so the owner can
relicense without anyone else's consent (GOVERNANCE.md).

## Decision

| Part of the tree | Licence |
|---|---|
| App, libraries, tools (everything not listed below) | **FSL-1.1-ALv2**: source-available; any use except a competing commercial product; each version becomes **Apache-2.0** two years after release |
| Reference receiver (`receiver/`, `Tools/receiver/`) | **Apache-2.0**, so anyone can build tools that read KeepMyMetrics exports |
| Wire spec and fixtures (`spec/`) | CC0-1.0 (unchanged) |
| Documentation (`docs/`) | CC-BY-4.0 (unchanged) |

The licensor is Colin Edward Wood. `LICENSE` and `LICENSES/FSL-1.1-ALv2.txt` hold the
canonical SPDX text, byte-identical; `REUSE.toml` and every SPDX header follow.

## Consequences

- **No cheaper App Store clones.** A competing commercial product is not a permitted
  purpose for two years per version.
- **Not "open source".** FSL is not OSI-approved. Copy says "source-available" (Fair
  Source), never "open source". The store listing, About, README and brand guide follow.
- **Earlier versions stay AGPL-3.0.** Everything published before this change remains
  available under AGPL-3.0; that cannot be withdrawn. The exposure is an early beta.
- **No App Store permission needed.** The AGPL §7 permission and `COPYING` are removed;
  contributors sign off under the licence of the files they change (CONTRIBUTING.md).
- **Dependencies must be permissive.** GPL, AGPL and LGPL code can't be distributed
  inside an FSL work (`dependencies/policy.md`). Today the graph is sqlite3 and zlib only.
- **R-110 still holds.** Nothing is gated on sponsorship; the only gate is the paid
  unlock for automatic exports (D-08b), and security updates reach everyone.
- **Dated design records** (stage-2 design docs, PRD contributions and reviews)
  describe the AGPL reasoning as it was. They are left as written; this ADR governs.
