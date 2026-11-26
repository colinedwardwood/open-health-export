# Publish a security advisory (in-app feed)

Applies once the feed is hosted at `https://advisories.cewdesign.com/advisories/v1.json`
(#67). The mechanics and key handling are in
[`docs/03-implementation/advisory-signing.md`](../03-implementation/advisory-signing.md); this
page is the decision procedure around them.

## Should this be in the feed?

Yes if users should act (update, change a setting, revoke something). No for ordinary bugs; use
release notes and `docs/support/known-issues.md`. Items are display-only: no field changes
what the app exports. Remember only users who turned on "Check for security notices" see it, so
use GitHub security advisories and release notes too.

## Steps

1. Draft the item (`id`, `published`, `severity`, `affected`, `description`, `url`). No
   Health values, no private hostnames, no medical advice. The `url` is shown in full.
2. Increase `seq` by exactly one. Keep `expires_at` far enough out that a quiet month does not
   expire it. TODO-owner: choose the heartbeat cadence (the app shows "stale" after 30 days
   without a fresh verified feed).
3. Cooling-off: per the [README solo substitutes](README.md#solo-substitutes-for-two-person-controls), unless the issue is actively exploited.
4. Sign with the offline key on an offline-prepared machine; verify with
   `swift run advisory-sign verify v1.json`.
5. Publish as a static file, access logging off (`PRIVACY.md` requires hosting without
   retained logs). TODO-owner: hosting choice (#67).
6. Verify from a second machine: fetch the URL and run `advisory-sign verify` on the download.
   Confirm no query string, cookies or redirects.
7. Log the `seq`, time, and who verified (you, from where).

## If the key is lost or suspect

Do not publish. See `incident.md`, "Advisory signing key compromise or loss".
