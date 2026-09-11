# Governance

Decisions are made by the people listed in `MAINTAINERS.md`. Today that is one person.
There is no voting body and no company behind the project.

## Adding or removing a maintainer

A new maintainer is added by a reviewed change to `MAINTAINERS.md` that names GitHub
handle, scope, and a contactable address, then by granting the least GitHub and Apple
roles needed. Removal is the reverse, including revoking those roles. Private keys are
never transferred through this repository. See `CONTINUITY.md`.

## Licence change

The outbound licence is AGPL-3.0-or-later plus the additional permission in `COPYING`.
Changing that licence requires the consent of all copyright holders. Inbound contributions
are under the same licence (`CONTRIBUTING.md`).

## Dormancy

If no maintainer has responded to issues, security reports, or pull requests for **90
days**, regard the project as unmaintained: the README status line should read `archived`
or `seeking-maintainers`, and a fork is the continuity path. Source remains usable under
the licence without anyone's permission.
