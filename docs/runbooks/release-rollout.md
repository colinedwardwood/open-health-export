# Release and rollout

## Before the tag

1. Open the release issue (`.github/ISSUE_TEMPLATE/release.yml`) and fill every section with
   linked evidence. Leave a gate unticked if you cannot truthfully tick it.
2. Fold the changelog (below).
3. Confirm `README.md` maintenance status and the supported-OS matrix are current
   (`scripts/validate-release.py` checks them).
4. Record the last-good tag and its `BUILDINFO` (once those exist, see `PROVENANCE.md`) for
   roll-forward.
5. Cooling-off: stop after the checklist and re-read it at least 12 hours later. Record both times.
6. Verification from a second machine: fresh clone, `swift run policycheck`, and
   `./scripts/build-from-source.sh`. Paste the output into the release issue. If the release
   publishes attestations, run `gh attestation verify` from that machine too.

### Fold the changelog

1. Read `changes/unreleased/` and write the user-facing entry in `CHANGELOG.md` under
   `## <version> - <date>`. Plain words, no internal IDs, nothing a user cannot see.
2. Update `store/en/whats-new.txt` from that entry. App Store Connect allows 4000 characters;
   check with `wc -m store/en/whats-new.txt` and keep it well under. `swift run policycheck`
   scans it against the medical-claim denylist.
3. Move the folded fragments to `changes/archive/<version>/` (git keeps history) so
   `changes/unreleased/` is empty at tag time. No CI check reads that directory's emptiness today.

## Phased rollout

Turn on phased release for automatic updates in App Store Connect. TODO-owner: confirm the
setting is available and chosen for the 1.0 submission.

The numbers below are pre-committed. Do not adjust them after the rollout starts. Record the
baseline (previous release) beside each one in the release issue before release day. For 1.0
there is no previous release: use the absolute floors and TODO-owner: record the first-week
baseline for 1.0.1.

**Halt the phased release (pause in App Store Connect) if any of these is true:**

- Crash-free sessions in Xcode Organizer is below 99.5 %, or 0.5 percentage points worse than
  the previous release.
- The same launch-crash signature appears from two or more devices.
- Background terminations (Organizer, or MetricKit counters
  `cumulativeMemoryResourceLimitExitCount`, `cumulativeSuspendedWithLockedFileExitCount`) are
  twice the previous release's.
- Any credible report of data loss, duplicated or wrong exported data, or data sent to a
  destination the user did not choose. One report is enough. Credible means a reproduction, a
  ledger or History screenshot, or a receiver-side record.

**Cadence:** look daily for the first 7 days (Organizer figures lag; note the data date).
Decide within 24 hours of a criterion being met. The decision is: halt, then either ship a fix
(roll forward) or record in the release issue why the signal was a false alarm.

**Halting never means reverting.** Apple does not return users to an older build. After a halt:
ship a fixed build, update `docs/support/known-issues.md`, and follow `incident.md`.

## After the rollout

- Day 7 and day 30: write a short note in the release issue (counts only, no user data). See
  `docs/03-implementation/launch-metrics.md`.
- Add anything users must know to `docs/support/known-issues.md`.
