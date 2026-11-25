<!--
SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
SPDX-License-Identifier: FSL-1.1-ALv2
-->

# UI-test overrides

Every launch environment variable and launch argument a test uses to change what the
app does, the production behaviour it hides, and where that behaviour is covered
without the override (#74). `swift run policycheck` fails when an `OHE_*` name read by
`Apps/` or `Sources/` is missing from the first column of the first table, so a new
override cannot ship unlisted. All `OHE_*` hooks are `#if DEBUG` only; the Release scan
(`scripts/scan-release-artifacts.sh`) fails if any of their names appears in a shipped
binary (#69).

"Un-masked coverage" names the case that runs the same behaviour with the override
absent. `No` rows point at a numbered manual step below.

## Environment hooks

| Override | Masks | Un-masked coverage |
| --- | --- | --- |
| `OHE_RESET_SEEDED_SURFACES` | State carried over between cases on one simulator: advisory defaults, network ledger, destination records, snapshots | Yes: `scripts/smoke-launch.sh` launches a clean install with nothing set (#37) |
| `OHE_RESET_FIRST_RUN` | The disclosure acknowledgement is stored, so first run happens once per install | Yes: `testFirstRunReachesAFirstExport` and the smoke launch |
| `OHE_SEED_DESTINATION_STATUS` | Real exports, network and days passing: success, stale and failed destination snapshots | No: manual step M1 |
| `OHE_SEED_LOCAL_EXPORT_FOLDER` | The Files picker, which XCUITest cannot drive | No: manual step M2 |
| `OHE_SEED_ICLOUD_FOLDER` | A folder under iCloud Drive chosen in the picker | No: manual step M2 |
| `OHE_FAIL_DATA_SAVE` | A real storage failure when saving Data types | Yes: `testDataAsksBeforeASensitiveTypeAndSaves` saves with the hook off |
| `OHE_UNLOCK_STATE` | StoreKit purchase state | No: manual step M3 |
| `OHE_OPEN_URL` | A notification or widget tap delivering the URL | No: manual step M4 |
| `OHE_TEST_USER_PRESENCE` | Face ID, Touch ID and passcode prompts | No: manual step M5 |
| `OHE_SEED_NOTIFICATION_AUTHORIZATION` | The notification permission the user actually granted | No: manual step M6 |
| `OHE_ACCESSIBILITY_MATRIX` | The system's own dark appearance and bold text settings | No: manual step M7 |
| `OHE_FORCE_METERED_PATH` | The real network path (cellular, low data mode) | No: manual step M8 |
| `OHE_HEALTHKIT_UNAVAILABLE` | A device that has no Health store | No: manual step M9 |
| `OHE_IPAD_ONLY_EXPORTER` | The iPad idiom check for the "only exporter" notice | No: manual step M9 |

## Launch arguments

These land in UserDefaults' argument domain, which the app reads in Release too. They
cannot be gated by `#if DEBUG`; they stay inert because they only set preferences the
user can set in Settings.

| Argument | Masks | Un-masked coverage |
| --- | --- | --- |
| `-ohe.disclosureAcknowledged true` | First-run disclosure | Yes: `testFirstRunReachesAFirstExport` and the smoke launch |
| `-ohe.advisoryEnabled false` | The advisory fetch, which would reach the network | No: manual step M10 |
| `-ohe.appPrivacyGateEnabled false` | The optional privacy gate's lock screen | Yes: `testOptionalPrivacyGateFailsClosedAndUsesInjectedAuthenticator` (gate on, hook for the authenticator only) |
| `-UIPreferredContentSizeCategoryName`, `-NSDoubleLocalizedStrings`, `-AppleLanguages`, `-NSForceRightToLeftWritingDirection` | System text size, language and layout direction | Yes: they are the system's own switches; the default case is every other case |

## Manual steps

Run on a physical iPhone with a Release build before each release, recording
`pass`, `fail` or `blocked` in the release issue (see `qa/non-automated-verification.md`).

- M1. Add a real destination, run an export, and confirm Status shows success. Turn the destination off and confirm it goes stale after its interval, then failed after a failing export.
- M2. In first run and in Destinations, choose a real folder with the Files picker, once on device storage and once in iCloud Drive. Confirm the iCloud warning appears for iCloud Drive only.
- M3. On a TestFlight build, confirm locked, unlocked and restored purchase states with a sandbox account.
- M4. Tap a real failure notification and a real widget; confirm each opens the destination.
- M5. Turn the privacy gate on. Confirm Face ID, then passcode fallback, then a cancelled prompt that leaves the app locked.
- M6. Deny notifications in iOS Settings; confirm the denied explanation. Allow them again.
- M7. Turn on dark appearance and bold text in iOS Settings; page through every tab.
- M8. Export on cellular with Low Data Mode on; confirm the metered-network rules apply.
- M9. On an iPad, confirm the "only exporter" notice. A device with no Health store is not available for manual testing; the check is covered by unit tests only.
- M10. With a network available, launch a Release build with advisories at their defaults and confirm the advisory request is the only one sent.
