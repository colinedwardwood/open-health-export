### Companion receive-and-write, Mac app, secrets, notices

`CompanionReceive` writes committed batches with `FileWriteKit` and a `.ohe-receipts.json`
index so O1 (idempotent re-OFFER) survives a process restart. Batch IDs are rejected if they
look like path traversal. iCloud / Mobile Documents folders produce a warning and are not
refused (O-10).

`CompanionListener` (`NWListener` + TLS 1.3 PSK) lives in `NetEgress` under `#if os(macOS)` —
the iOS app source never mentions a listener, and `policycheck` still fails `Apps/` on
`NWListener` / `NWBrowser`. The Mac app (`Apps/Companion-macOS`) depends on `ExportCore` only
and is CI-asserted not to mention HealthKit (AR-01). It advertises `_ohx-recv._tcp` only while
the receive window is open, shows the pairing payload as selectable text (QR rendering later),
and carries an AGPL source-offer line because the receiver is network-interactive.

`SecretHandle` / `SecretStore` (R-33, R-43 `deleteAll`) sit on `EnginePorts`. Tests use
`MemorySecretStore`. Darwin `KeychainSecretStore` uses AfterFirstUnlockThisDeviceOnly and
`synchronizable = false`.

R-40 copy is `NoticeCopy` in `DestinationTrust` (every `UserNotice.Kind`, no call-site prose).
The iOS harness has `LocalUserNotifier` (`UserNotifications`) and a button that posts one
sample notice. iOS `Info.plist` now declares `_ohx-recv._tcp` and a local-network usage string
so the phone can *browse*; it still does not listen.

Not done: live two-device transfer, QR images, Keychain round-trip in CI, and computing the SAS
from the phone's HELLO installation ID on the Mac UI.
