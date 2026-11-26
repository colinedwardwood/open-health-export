# Incident response

A solo owner will improvise under stress unless this is short. Do the first block for every
incident, then the matching branch.

## First hour (every incident)

1. Start the log (UTC). Do not copy Health values or secrets into it.
2. Stop the damage: if a release is rolling out, pause the phased release; do not publish
   further builds until you understand the cause.
3. Classify (below) and write one line: what is known, what is not.
4. Decide what to tell users and where (see "Telling users"). If unsure, say less, truthfully.

## Branches

### Crash loop or launch crash
Pause the phased release. Reproduce from the Organizer crash or a shared `.ips`
(`docs/support/sharing-crash-logs.md`). Ship a fix; list the affected versions in
`docs/support/known-issues.md`. Users can delete and reinstall only if the fix needs it: warn
them that local queue and history go with the app (`docs/03-implementation/uninstall-and-data-removal.md`).

### Silent data loss, or wrong or duplicated data
Highest priority: this is the correctness product. Pause the phased release on the first credible
report. Identify the affected versions, data types and destinations. Say plainly what was and
was not sent and how to re-export. Do not minimise.

### Vulnerability
Handle per `SECURITY.md` and `CYBERSECURITY.md`: private advisory, fix, coordinated disclosure,
then publish. If exploited or likely to be exploited, tell users the same day through the
channels in "Telling users". Cooling-off applies to the fix release but may be shortened to the
shortest time that still lets you re-read the diff.

### Advisory signing key compromise or loss
Stop publishing the feed. Do not sign anything with the suspect key. Follow "Rotation and
suspected compromise" in `docs/03-implementation/advisory-signing.md`. Use GitHub security
advisories and App Store release notes; state that the in-app feed could not be updated.

### Domain or hosting loss (advisories.cewdesign.com, or other project domains)
The app fails open: export is unaffected and users see "stale". Regain or replace the host. A
replacement hostname needs an app release, because the host is compiled in. TODO-owner:
registrar and DNS account recovery details are not recorded in this repository on purpose.

### An iOS update breaks HealthKit access or background delivery
Reproduce on the new beta/release. Publish the symptom and workaround
(manual Export now) in `docs/support/known-issues.md` the same day. Ship a fix if one exists.

### User data went to a place the user did not choose
Treat as a possible breach of health data. Stop the cause first (pause, fix). Then assess
notification duties: US FTC Health Breach Notification Rule and any state law, and GDPR if any
EU users exist (no EU storefronts at launch per `docs/03-implementation/launch-status.md`).
TODO-owner: have counsel confirm whether the app falls under the Rule and the notification
deadlines (#21). Until then, do not assert either way in public; record the assessment and
the date you made it.

### CRA reporting branch (only if the project is later found to be in scope)
`CYBERSECURITY.md` records that no CRA classification has been determined. If counsel concludes
reporting applies: early warning within 24 hours and notification within 72 hours of becoming
aware of an actively exploited vulnerability or severe incident, to the CSIRT designated by the
relevant member state and ENISA. TODO-owner: the exact obligations, reporting platform and
designated CSIRT, to be supplied by counsel. Do not file or claim a role without that review.

## Telling users

Channels that exist: GitHub security advisories and releases; App Store release notes; the
in-app signed feed (opt-in; not hosted yet, see `PRIVACY.md`). TODO-owner:
status page or social channel, if any. Message content: affected versions, what to do, what
we do not know. No medical advice.

## After

Within a week: write what happened, timeline, cause, fix and what changes, keeping Health values
out. Add a line to `qa/` or `docs/` as appropriate and update these runbooks.
