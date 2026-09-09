# Contributing

Inbound licence equals outbound: AGPL-3.0 plus the additional permission in `COPYING`.

## Developer Certificate of Origin

Every commit must be signed off (`git commit -s`) under DCO 1.1:

```
Developer Certificate of Origin
Version 1.1

Copyright (C) 2004, 2006 The Linux Foundation and its contributors.

Everyone is permitted to copy and distribute verbatim copies of this
license document, but changing it is not allowed.

Developer's Certificate of Origin 1.1

By making a contribution to this project, I certify that:

(a) The contribution was created in whole or in part by me and I
    have the right to submit it under the open source license
    indicated in the file; or

(b) The contribution is based upon previous work that, to the best
    of my knowledge, is covered under an appropriate open source
    license and I have the right under that license to submit that
    work with modifications, whether created in whole or in part
    by me, under the same open source license (unless I am
    permitted to submit under a different license), as indicated
    in the file; or

(c) The contribution was provided directly to me by some other
    person who certified (a), (b) or (c) and I have not modified
    it.

(d) I understand and agree that this project and the contribution
    are public and that a record of the contribution (including all
    personal information I submit with it, including my sign-off) is
    maintained indefinitely and may be redistributed consistent with
    this project or the open source license(s) involved.
```

Signing off also grants the **Additional permission under GNU AGPL version 3 section 7**
reproduced verbatim in `COPYING`.

## Rules

- No real health data in the repo, issues, or CI, including your own. If that happens, follow
  the incident steps in `SECURITY.md`.
- No new runtime dependency without an ADR and a Linux-build check.
- Changelog fragment in `changes/unreleased/` for user-visible changes.
- Frozen `spec/` versions are not edited in place.
