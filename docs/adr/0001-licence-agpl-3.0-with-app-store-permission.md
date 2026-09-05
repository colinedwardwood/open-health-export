# ADR-0001 — AGPL-3.0 with a GPLv3 §7 app-store additional permission

- **Status:** Accepted
- **Date:** 2026-09-02
- **Deciders:** Project owner (D-01, D-02)
- **Supersedes:** nothing
- **Consulted:** `docs/01-prd/contributions/09-oss-governance.md`, `01-competitive-market-analyst.md`, `07-marketing-manager.md`, `docs/01-prd/reviews/01-adversarial-review.md` (AR-F-18)

## Context

The licence had to be settled before the first commit (R-100) because it constrains every
dependency we may link and, once external contributors send patches, it is expensive to
change — VLC took over a year to relicense and still left code behind.

Four specialists reached four different recommendations: permissive-or-GPL+§7, Apache-2.0/MIT,
MPL-2.0, and AGPL+§7. The disagreement was not about values but about a widely-repeated claim
that GPL-family licences are incompatible with the App Store.

**That claim did not survive research.** Apple does not police licences. AGPL-3.0 apps (Ice
Cubes; `health-md`, which competes with us directly) and GPL-3.0 apps (Passepartout, Blink)
ship on the App Store today. VLC was pulled in 2011 because a copyright holder who had not
consented complained to Apple — not because Apple objected.

The real constraint is therefore different from the folklore, and worse in one specific way:
**under copyleft, every contributor holds a de facto veto over App Store distribution**,
because Apple's standard EULA imposes restrictions that the GPL family forbids adding, and any
one rightsholder can raise it. It is a copyright-concentration problem, not a licence problem,
which is why the licence and the contribution-intake mechanism had to be decided together.

## Decision

The app and all first-party modules are licensed **AGPL-3.0**, accompanied by an explicit
**GPLv3 §7 additional permission** authorising distribution through app stores whose terms are
otherwise incompatible with §6.

Every contributor grants that additional permission. The mechanism is DCO sign-off, with the
permission text stated in `COPYING`, restated in `CONTRIBUTING.md`, and incorporated by
reference into the DCO assertion so that signing off is an affirmative grant rather than an
implied one.

Documentation is CC BY 4.0. The wire-format specification and its fixtures are CC0-1.0, because
the specification's value depends on third parties being able to implement receivers without
any licence question at all (R-12, and the ecosystem argument behind HAE wire compatibility).

## Alternatives considered

| Option | Why not |
|---|---|
| **MPL-2.0** (my recommendation, and the governance lead's) | Weaker copyleft than the owner wanted. Its anti-clone property is also thinner than it sounds: copyleft is per-file, so a competitor can put all differentiation in new files as a Larger Work under §3.3 and publish nothing |
| **Apache-2.0 / MIT** | Simplest and most familiar, but permits a closed paid clone of a project whose whole proposition is that you can audit the code handling your health data |
| **EPL-2.0** | Satisfies the same three criteria as MPL-2.0 (file-level copyleft, express patent grant, app-store-clean), but adds an uncapped commercial-contributor indemnity and is unfamiliar in the Swift ecosystem |
| **AGPL-3.0 with a bare DCO** | Leaves the contributor veto open. This is the one combination that is actually dangerous, and it is the one a project would drift into by default |
| **AGPL-3.0 with a CLA** | Closes the veto and preserves future dual-licensing, but depresses casual contribution and signals commercial intent. Now technically available given the legal entity (D-03); rejected as disproportionate for a project whose primary risk is too few contributors, not too many |

## Consequences

**Positive.** The strongest available guarantee that a user's auditable health-data tool stays
auditable. A closed paid fork is foreclosed in a way permissive licensing does not achieve.
The §7 permission removes the App Store risk that would otherwise make AGPL reckless here.
AGPL's patent provisions carry over from GPLv3.

**Negative, and accepted.** AGPL deters some corporate contribution, though this project's
contributor pool is individuals. The §7 permission must be genuinely granted by every
contributor — a lapsed or ambiguous grant reopens the veto, so CI enforcement of DCO (R-101) is
load-bearing rather than hygiene. AGPL is also incompatible with linking some permissively-
licensed-but-GPL-incompatible code, which narrows the dependency allowlist; given D-04 admits
exactly one third-party runtime dependency (MQTT), the dependency review must check licence
compatibility explicitly rather than assume it.

**Requiring legal review (R-112).** The §7 permission text itself. The governance lead noted
that any GPL-family adoption warrants a paid opinion, and D-12 confirms budget exists.

**Note on §13.** AGPL's network clause is largely inert for a client application, but the Mac
companion receives over the local network. The interaction is benign — the operator and the
user are the same person — but Stage 2 should not assume that stays true if the companion ever
serves anyone else.
