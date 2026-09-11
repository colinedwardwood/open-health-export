# Project continuity

Open Health Exporter currently has one maintainer and is seeking additional
maintainers. This document describes what remains possible if that maintainer
is unavailable; it does not imply that a deputy or credential escrow exists.

## What anyone can continue

- Fork the AGPL-3.0-or-later source, run the documented clean build, and publish
  source releases under a different signing identity.
- Build and test the Linux core, iOS app, widget, Mac companion, wire fixtures,
  reference receiver, and container contracts from the repository.
- Validate advisory documents with the public verification material committed
  to the project.

No repository secret is needed for builds or pull-request CI. Fork pull
requests do not execute credentialed jobs.

## What currently depends on the owner

- GitHub repository administration and release-environment approval.
- Apple Developer and App Store Connect administration.
- Developer ID and App Store distribution through the existing team.
- Security-advisory signing-key rotation and control of the advisory hostname.
- Grafana community-catalogue publishing (no project Grafana Cloud account is held yet).

Private signing keys, Apple credentials, and service tokens are not committed
or shared through this repository. A successor cannot impersonate the existing
Apple team or advisory identity merely by obtaining the source.

## Release continuity

Source releases remain forkable. Releases under the existing project identity
require the owner until a second maintainer is appointed, receives the required
service roles, completes the stranger-test release checklist, and is recorded
in `MAINTAINERS.md`.

If Apple distribution becomes unavailable, the last published binary remains
independent of the repository. Under individual enrolment the App Store channel
has a bus factor of one. That is mitigated by the documented build-from-source
path (R-108) and by the licence permitting a rebranded fork. A fork can publish
a separately identified app, subject to Apple's rules and the licence, but cannot
issue an in-place update signed as this project.

## Incident continuity

We can **inform** essentially every user within one visible foreground launch.
We cannot **change** what an installed app does remotely. There is no remote
configuration or feature-flag service. Containment is therefore:

1. pause releases and the advisory feed if its signing identity is uncertain;
2. publish a signed advisory when the identity remains trustworthy;
3. disclose the affected versions and destinations without medical advice;
4. roll forward with a reviewed release; and
5. preserve the ledger, build provenance, and incident evidence.

If the advisory key is unavailable or suspect, use the GitHub security advisory
and release channels and state explicitly that the in-app feed could not be
updated.

## Succession checklist

1. Add the maintainer through a reviewed `MAINTAINERS.md` change.
2. Grant least-privilege repository and protected-environment roles.
3. Complete Apple role onboarding separately; never transfer private keys in
   the repository.
4. Rehearse source release, clean build, advisory rotation, rollback, and
   incident communication.
5. Record which maintainer completed each release in release history.
6. Revoke access promptly when a maintainer leaves.
