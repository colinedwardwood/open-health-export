# ADR-0004 — In-repo property tests without a third-party checker

- **Status:** Accepted
- **Date:** 2026-09-09
- **Deciders:** Project owner (O-2)
- **Supersedes:** nothing
- **Consulted:** `docs/01-prd/contributions/08-qa-lead.md` (QA-19),
  `docs/02-design/04-security-design.md` (R-80, no extra runtime packages)

## Context

QA-19 requires P1–P16 as executable property or model tests with shrinking and seed
reporting. Candidate libraries (PropertyBased, Exhaust, SwiftTestKit) are small and
would enter the package graph. R-80 forbids third-party runtime packages in ExportCore;
a test-only package is still a supply-chain and maintenance surface the security review
flagged.

## Decision

Keep property *definitions* in `Tests/ExportCoreTests`: seeded RNGs, shrinking on
encode mismatch (P1), and a stateful reference model (P3–P7). Do not add a property
library. A meta-test (`qa19EveryCorrectnessPropertyHasANamedTest`) fails if any of
P1–P16 lacks a `@Test func pN…` witness.

## Consequences

- Shrinking is hand-rolled and weaker than a dedicated checker.
- Replacing the runner later does not require rewriting the invariants.
