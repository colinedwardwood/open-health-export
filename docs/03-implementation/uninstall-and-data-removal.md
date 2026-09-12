# Uninstall and data removal

Use the in-app deletion action before uninstalling when you want to remove exporter-managed data and secrets.

## iPhone and iPad

1. Open Open Health Exporter and choose **Delete everything on this device**.
2. Confirm the second prompt. This removes destinations, queued payloads, logs, history, ledger data, pairing state, credentials, and the ledger signing identity.
3. Remove the app normally.
4. In **Settings > Health > Data Access & Devices**, revoke any remaining Health access if desired.

Do not rely on app deletion alone to remove Keychain items. Current iOS behavior can vary with access groups, restore paths, and OS changes.

## Mac companion

1. Close the receive window.
2. Select the folder previously used for received archives.
3. Choose **Delete everything received**, then confirm. The companion deletes only payloads named by its receipt ledger, the ledger itself, and its stored pairing. It does not glob-delete unrelated `.ndjson` files.
4. Quit the companion and move the app to the Trash.
5. Open **Keychain Access**, search the login keychain for `app.openhealthexporter.mac.psk`, and delete any remaining item with that service name.
6. Inspect any other folders you previously selected and remove archives you intentionally retained there.

Dragging a macOS app to the Trash does not remove its login-keychain items. The manual Keychain step is therefore required after uninstall if the in-app deletion action was not completed or could not be verified.
