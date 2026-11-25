# Governance

Product and repository decisions are made by the owner listed in
`MAINTAINERS.md`. There is no voting body, community governance process, or open
path to a maintainer role.

## Exceptional succession

The owner may appoint a successor or contractor only as an explicit continuity
decision. That person is recorded by a reviewed change to `MAINTAINERS.md` that
names GitHub handle, scope, and a contactable address, then receives only the
GitHub and Apple roles needed. Removal is the reverse, including revoking those
roles. Private keys are never transferred through this repository. See
`CONTINUITY.md`.

## Licence change

The outbound licence is FSL-1.1-ALv2 (`LICENSE`); the reference receiver is Apache-2.0, the spec CC0-1.0 and the docs CC-BY-4.0 (ADR-0005).
Changing that licence requires the consent of all copyright holders. Inbound contributions
are under the same licence (`CONTRIBUTING.md`).

## Dormancy

If the owner has not responded to issues or security reports for **90 days**,
regard the project as unmaintained: the README status line should read
`archived`, and a fork is the continuity path. Source remains usable under the
licence without anyone's permission.
