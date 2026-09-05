### Error-class registry, HAE loss gate, MQTT retain off

`ErrorClassManifest` is a total switch over `ErrorClass` (DP-6). The HAE encoder lives next to
native wire but only runs when the caller passes `HAELossAccepted`; tombstones and HealthKit UUIDs
are not representable. MQTT sessions refuse `retain=true` so a data PUBLISH cannot leave a retained
message on the broker. Keychain PSK uses the data-protection keychain, AfterFirstUnlockThisDeviceOnly,
no biometry. Logs go through `os.Logger` with `%{private}` — `import Logging` is a policycheck fail.
