# Advisory feed signing

The in-app security-advisory feed is off by default. When it is on, the app accepts a
feed only if it carries a detached **Ed25519** signature from one of two public keys
compiled into the app (`AdvisoryPinnedKeys` in `Sources/WireFormat/AdvisoryFeed.swift`):

| Key ID | Role |
|---|---|
| `active` | Signs every feed. |
| `successor` | Held in reserve. The next app release that retires `active` promotes it, so a lost or suspect active key can be replaced without an app update first. |

A feed can never introduce or change a key. Rotation is always an app release.

## Where the private keys live

Never in this repository, never in CI, never on a server. The owner keeps them offline,
each in separate custody (for example `active` in a password manager's secure file store
and `successor` on an encrypted offline drive). `Tools/advisory-sign` is the only code
that signs. It is not linked into the app.

## Publishing a feed

1. Write `feed.json` with `seq`, `valid_from`, `expires_at` and `items` (each item:
   `id`, `published`, `severity`, `affected`, `description`, `url`). Items are
   presentation-only: no field can change what the app exports.
2. Increase `seq` by exactly one over the last published feed. The app refuses a feed
   whose `seq` is not higher than the last it saw, and one more than
   `AdvisoryDocument.maximumSequenceStep` (1,000) higher.
3. Sign:

   ```sh
   swift run advisory-sign sign --key <path to active key> --key-id active \
     --feed feed.json --out v1.json
   ```

   The tool refuses to write a document that the app's compiled keys would reject.
4. Check it independently: `swift run advisory-sign verify v1.json`.
5. Publish `v1.json` at the advisory URL, which is served as a static file with access
   logs off (#67).
6. Keep `expires_at` far enough out that a quiet month does not expire the feed, and
   republish (with a new `seq`) before it lapses.

## Rotation and suspected compromise

- **Planned rotation:** generate a new key with `swift run advisory-sign keygen <dir>`.
  Ship a release whose `active` is the old `successor` and whose `successor` is the new
  key. Sign with the new `active` only once that release is the one most people run.
- **Suspected compromise of `active`:** stop publishing, publish an advisory through the
  GitHub security advisory and release channels instead, and ship a release that drops
  the compromised key. The in-app feed cannot say anything trustworthy until then.
- **Loss of both keys:** the feed goes silent. Ship a release with two new keys.
  Installed apps show "stale" rather than anything false.
