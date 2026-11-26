# Support triage

Support is best-effort (`SUPPORT.md`). These are targets, not guarantees.

## Targets

Response targets are defined once, in [`SUPPORT.md`](../../SUPPORT.md). Purchase and refund
requests: see "Purchases" below.

## Routine

- Daily when a rollout is live, otherwise on working days: GitHub issues, support email,
  App Store Connect resolution centre. TODO-owner: the support email address and web page are
  not recorded in this repository.
- Weekly: read App Store reviews; reply to 1-2 star reviews that report a defect, once, with
  how to reach support. Do not argue.
- Monthly: add a counts-only row to `qa/support-log.md`. No names, emails or Health values.

## Tags

Tag every contact with one tag (use two only when both are real): `setup`, `HA` (Home
Assistant), `HTTPS`, `MQTT`, `Mac`, `background-overdue`, `purchase-refund`, `data-correctness`.
The `data-correctness` tag is also the signal for the halt criteria in `release-rollout.md`.

## Handling

1. Ask for: app version, iOS version, destination type, what they expected, what History/Status
   shows. Ask for a screenshot of Status or History, not of Health data. Offer
   `docs/support/sharing-crash-logs.md` for crashes.
2. Check `docs/support/known-issues.md` first.
3. Suspected data loss or wrong data: tag `data-correctness`, reproduce or ask for the receiver
   record, and if credible follow `incident.md`.
4. Anything that reveals real Health values or secrets: ask the user to delete the message,
   do not copy it anywhere, and follow `SECURITY.md` "Accidental health data or secrets".
5. Vulnerability reports go to `SECURITY.md`, not the public tracker.

## Purchases

Refunds are handled by Apple (reportaproblem.apple.com). Do not promise refunds or promise
that they will be denied. TODO-owner: refund and unlock-restore wording once the in-app
purchase exists (#23, #21).
