### Pairing vault, QR scan, loopback MQTT TCP

`PairingVault` stores the PSK in `SecretStore` (Keychain on device, memory in tests) and names
in a JSON sidecar that is asserted not to contain the secret. Reopening the Mac receive window
reuses the same pairing and QR. Forget pairing deletes the keychain item and the sidecar (R-43
for this handle). The phone restores the same way.

The iOS harness can scan the Mac QR with VisionKit (`DataScannerViewController`); paste remains
as a fallback when the scanner is unsupported (simulator). Camera use is described in
`NSCameraUsageDescription` and the image is not stored.

`mqttPublishesOverLoopbackTCP` is a real `NWListener` MQTT 3.1.1 broker in Tests/ (not Sources/,
so it does not become an iOS listening socket) plus `MQTTSink` over `NWByteStream` to
`127.0.0.1`. That is the first live TCP MQTT path, still without TLS and without a third-party
broker.
