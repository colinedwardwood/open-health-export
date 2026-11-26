# Changelog

User-visible changes land as fragments in `changes/unreleased/` in the same pull request
as the code. A tagged release is not a release without folding those fragments into a
version heading here.

The fragments are engineering notes, not release copy. At release time the owner writes the
user-facing entry below by hand from them (see `docs/runbooks/release-rollout.md`, "Fold the
changelog"), then moves the fragments to `changes/archive/<version>/` so
`changes/unreleased/` is empty when the tag is cut. Fragments are kept in git history either way.

## 1.0.0 - TODO-owner: release date (draft, not yet released)

Initial release (iPhone only; the Mac companion is planned for 1.1).

### What it does

- Reads the Apple Health types you choose and delivers them to destinations you set up:
  Home Assistant (MQTT discovery sensors, or a webhook), an MQTT broker, your own HTTPS
  server, or a folder in Files.
- Every destination starts with no Health types selected. Nothing is exported until you choose
  types and a date range and confirm the destination.
- Every destination is tested before it is saved, and you see each step as it runs. A server
  certificate that is not publicly trusted receives nothing until you compare its fingerprint
  and confirm it.
- Catches late data, such as readings an Apple Watch syncs hours later.
- Status shows each destination in plain words and says what to do when one stops answering.
  History keeps 90 days of runs. The Data tab shows what the app can read.
- Export now and the Control Centre button run one export whenever you choose.
- A one-time purchase adds automatic exports. There is no subscription. Security notices and
  updates are never part of the purchase.
- Demo mode shows plausible values and writes to a separate output.
- Warns before writing to a folder in iCloud Drive, and writes nothing there until you confirm.
- Optional "Check for security notices" (off by default); see `PRIVACY.md` for what it sends.

### Honest limits

- iOS decides when background exports run, and Health data is locked while the iPhone is
  locked, so automatic exports catch up after you unlock.
- Deletions in Health are best-effort: HealthKit gives no deletion callback.
- No account, no analytics, no crash reporting. Data goes from your iPhone to your destination.

### Under the hood

- Source-available under FSL-1.1-ALv2; the wire format (`ohe.wire/1`) is frozen under `spec/`.
- Accessibility, large text and light and dark appearance are covered by automated audits.
